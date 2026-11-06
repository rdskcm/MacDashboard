// Engine/CPUFrequencyReader.swift
// SOC-DETAILS 1.2: average CPU frequency per core type while its cores were active, from the IOReport
// "CPU Complex Performance States" residencies weighted by the chip's own voltage-state table.
// App-only private API (libIOReport), plus pure helpers that tests cover.
//
// Method sources (open, MIT), cited by file and line; no code was copied from either:
// - macmon (vladkens/macmon): src/sources.rs (IOReport subscription, channel group walk, state residency reads).
// - Stats (exelban/stats): Modules/CPU/readers.swift:423-439 and :454-479 (residencies weighted by a DVFS table),
//   Kit/plugins/SystemKit.swift:547-558 and Kit/helpers.swift:833-853 (voltage-states tables from the pmgr node).
// - Verified on the reference Mac: inputs/SOC-DETAILS-research/probe-load-tested/probe.swift:120-176 (bindings),
//   :547-573 (weighting, table read), :656-685 (the CPU Stats path). Only the MHz = Hz / 1e6 table unit is
//   implemented; a table in any other unit is rejected by D2(c) as unavailable. This app does not guess per chip.
//
// Linkage: the eight IOReport symbols are resolved at RUNTIME via dlopen/dlsym and never linked (`@_silgen_name` is
// banned in this app, see Engine/ThermalHIDReader.swift for why). Resolution is all-or-nothing, looked up once, a nil
// result is cached and never retried.
//
// Failure model (logic D2): setup (table + state-count checks (a)-(d)) fails → that core type shows unavailable until
// the app restarts. A reading that fails (e) or (f) shows unavailable for that sample and is retested on the next.

import Foundation
import IOKit

/// The two core types the IOReport complex channels name.
enum CoreGroupKey: Hashable, Sendable {
    case efficiency   // channel ECPU, group "Efficiency…"
    case performance  // channel PCPU, group "Performance…"

    /// The core type a `CoreGroup` name maps to; nil for any other name (a third type has no channel: unavailable).
    init?(groupName: String?) {
        guard let groupName else { return nil }
        if groupName.hasPrefix("Efficiency") { self = .efficiency }
        else if groupName.hasPrefix("Performance") { self = .performance }
        else { return nil }
    }
}

enum CPUFrequency {
    /// D3: a core type active for less than this share of the sample shows "idle" instead of a number.
    static let idleShare = 0.05

    /// Pure. nil reading → unavailable; below the idle share → idle; else the average.
    static func state(from reading: FrequencyReading?) -> FrequencyState {
        guard let reading else { return .unavailable }
        return reading.activeShare < idleShare ? .idle : .mhz(reading.mhz)
    }
}

struct FrequencyTable: Equatable {
    let mhz: [Double]
}

struct FrequencyReading: Equatable {
    let mhz: Double
    /// Share of the sample the core type spent in non-idle states, 0...1.
    let activeShare: Double
}

/// Subscription and validated tables, built once per process. Holds the previous cumulative sample: every `sample`
/// call returns the delta against the previous call and advances it, so a caller that wants a fresh baseline just
/// calls once and drops the result.
final class FrequencySetup: @unchecked Sendable {
    fileprivate let symbols: IOReportSymbols
    fileprivate let subscription: OpaquePointer
    fileprivate let channels: CFMutableDictionary
    let tables: [CoreGroupKey: FrequencyTable]
    fileprivate var previous: CFDictionary?
    /// Guards `previous`: `sample` reads, diffs and advances it as one step.
    fileprivate let lock = NSLock()

    fileprivate init(symbols: IOReportSymbols, subscription: OpaquePointer, channels: CFMutableDictionary,
                     tables: [CoreGroupKey: FrequencyTable]) {
        self.symbols = symbols
        self.subscription = subscription
        self.channels = channels
        self.tables = tables
    }
}

/// The IOReport C entry points, as `@convention(c)` function pointers.
fileprivate struct IOReportSymbols {
    typealias CopyGroupFn = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    typealias SubscribeFn = @convention(c) (UnsafeRawPointer?, CFMutableDictionary?, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> OpaquePointer?
    typealias SamplesFn = @convention(c) (OpaquePointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias DeltaFn = @convention(c) (CFDictionary?, CFDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias NameFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    typealias CountFn = @convention(c) (CFDictionary) -> Int32
    typealias StateNameFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    typealias ResidencyFn = @convention(c) (CFDictionary, Int32) -> Int64

    let copyGroup: CopyGroupFn
    let subscribe: SubscribeFn
    let createSamples: SamplesFn
    let createDelta: DeltaFn
    let channelName: NameFn
    let stateCount: CountFn
    let stateName: StateNameFn
    let stateResidency: ResidencyFn
}

enum CPUFrequencyReader {
    // MARK: - Pure

    /// D2 setup checks on one core type's table (MHz) and the report's state count for that channel:
    /// (a) at least 2 entries, (b) strictly ascending, (c) lowest ≥ 100 MHz and highest ≤ 10 000 MHz,
    /// (d) state count == table entries + 1 idle state.
    static func validate(table: [Double], stateCount: Int) -> Bool {
        guard table.count >= 2 else { return false }
        for i in 1..<table.count where !(table[i] > table[i - 1]) { return false }
        guard let lo = table.first, let hi = table.last, lo >= 100, hi <= 10_000 else { return false }
        return stateCount == table.count + 1
    }

    /// Names of the residency states that mean "not running", excluded from the average (macmon / Stats convention).
    static let idleStateNames: Set<String> = ["IDLE", "DOWN", "OFF"]

    /// Pure. Average frequency over the non-idle states, weighted by residency, and the active share of the whole
    /// sample (0...1). Idle states count into `1 − active`.
    /// nil when: array lengths differ, any residency is negative or non-finite, the total is 0 (D2(e)), the number of
    /// non-idle states differs from the table (the mapping is wrong), or the unrounded average leaves
    /// `table.first...table.last` (D2(f)). A sample with no active time returns `(0, 0)`: there is no average, the
    /// caller shows "idle" for an active share under `CPUFrequency.idleShare`.
    static func weightedMHz(residencies: [Double], stateNames: [String], table: [Double])
        -> (mhz: Double, active: Double)? {
        guard residencies.count == stateNames.count, let lo = table.first, let hi = table.last else { return nil }
        var activeResidency: [Double] = []
        var idleTotal = 0.0
        for (name, r) in zip(stateNames, residencies) {
            guard r.isFinite, r >= 0 else { return nil }
            if idleStateNames.contains(name) { idleTotal += r } else { activeResidency.append(r) }
        }
        guard activeResidency.count == table.count else { return nil }
        let activeTotal = activeResidency.reduce(0, +)
        let total = activeTotal + idleTotal
        guard total > 0 else { return nil }
        if activeTotal == 0 { return (0, 0) }
        var mhz = 0.0
        for (r, f) in zip(activeResidency, table) { mhz += r / activeTotal * f }
        guard mhz >= lo, mhz <= hi else { return nil }
        return (mhz, activeTotal / total)
    }

    /// Pure. A `voltage-states*-sram` property: pairs of little-endian UInt32 (frequency in Hz, voltage). MHz = Hz / 1e6.
    /// nil when the data is empty or not a whole number of 8-byte pairs.
    static func parseTable(_ data: Data) -> [Double]? {
        guard !data.isEmpty, data.count % 8 == 0 else { return nil }
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 8).map { o in
            let hz = UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
            return Double(hz) / 1e6
        }
    }

    // MARK: - Private symbols (runtime-resolved, all-or-nothing)

    private static let symbols: IOReportSymbols? = loadSymbols()

    private static func loadSymbols() -> IOReportSymbols? {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        guard let copyGroup = dlsym(handle, "IOReportCopyChannelsInGroup"),
              let subscribe = dlsym(handle, "IOReportCreateSubscription"),
              let createSamples = dlsym(handle, "IOReportCreateSamples"),
              let createDelta = dlsym(handle, "IOReportCreateSamplesDelta"),
              let channelName = dlsym(handle, "IOReportChannelGetChannelName"),
              let stateCount = dlsym(handle, "IOReportStateGetCount"),
              let stateName = dlsym(handle, "IOReportStateGetNameForIndex"),
              let stateResidency = dlsym(handle, "IOReportStateGetResidency")
        else { return nil }   // partial resolution => the whole set fails closed
        return IOReportSymbols(
            copyGroup: unsafeBitCast(copyGroup, to: IOReportSymbols.CopyGroupFn.self),
            subscribe: unsafeBitCast(subscribe, to: IOReportSymbols.SubscribeFn.self),
            createSamples: unsafeBitCast(createSamples, to: IOReportSymbols.SamplesFn.self),
            createDelta: unsafeBitCast(createDelta, to: IOReportSymbols.DeltaFn.self),
            channelName: unsafeBitCast(channelName, to: IOReportSymbols.NameFn.self),
            stateCount: unsafeBitCast(stateCount, to: IOReportSymbols.CountFn.self),
            stateName: unsafeBitCast(stateName, to: IOReportSymbols.StateNameFn.self),
            stateResidency: unsafeBitCast(stateResidency, to: IOReportSymbols.ResidencyFn.self))
    }

    // MARK: - Setup (once per process, nil cached)

    /// Built on first access (about 35-65 ms, the IOReport group lookup), thread-safe by Swift's lazy static
    /// initialisation. nil when a symbol, the subscription, the first sample or every table check fails.
    static let shared: FrequencySetup? = makeSetup()

    private static let groupName = "CPU Stats"
    private static let subgroupName = "CPU Complex Performance States"
    private static let channelNames: [String: CoreGroupKey] = ["ECPU": .efficiency, "PCPU": .performance]
    /// pmgr property per core type (the performance-state tables of the E and P clusters).
    private static let tableProperty: [CoreGroupKey: String] = [.efficiency: "voltage-states1-sram",
                                                                .performance: "voltage-states5-sram"]

    private static func makeSetup() -> FrequencySetup? {
        guard let sym = symbols,
              let channels = sym.copyGroup(groupName as CFString, subgroupName as CFString, 0, 0, 0)?.takeRetainedValue()
        else { return nil }
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let subscription = sym.subscribe(nil, channels, &subscribed, 0, nil),
              let subscribedChannels = subscribed?.takeRetainedValue(),
              let first = sym.createSamples(subscription, subscribedChannels, nil)?.takeRetainedValue()
        else { return nil }

        // D2(d) needs each channel's state count: read it from one sample.
        var stateCounts: [CoreGroupKey: Int] = [:]
        for item in channelItems(first) {
            guard let name = string(sym.channelName(item)), let key = channelNames[name] else { continue }
            stateCounts[key] = Int(sym.stateCount(item))
        }
        let pmgr = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pmgr")
        guard pmgr != 0 else { return nil }
        defer { IOObjectRelease(pmgr) }

        var tables: [CoreGroupKey: FrequencyTable] = [:]
        for (key, property) in tableProperty {
            guard let count = stateCounts[key],
                  let cf = IORegistryEntryCreateCFProperty(pmgr, property as CFString, kCFAllocatorDefault, 0),
                  let data = cf.takeRetainedValue() as? Data,
                  let mhz = parseTable(data), validate(table: mhz, stateCount: count) else { continue }
            tables[key] = FrequencyTable(mhz: mhz)
        }
        guard !tables.isEmpty else { return nil }
        return FrequencySetup(symbols: sym, subscription: subscription, channels: subscribedChannels, tables: tables)
    }

    // MARK: - Sampling

    /// One cumulative sample, then the delta against the previous call. nil on the first call (nothing to compare),
    /// when the sample or the delta cannot be built. Per core type present in the report: the reading, or nil when
    /// D2 (e) or (f) fails for that sample. A core type that has no table (failed setup) or no channel is absent.
    /// Serialised by the setup's lock, so a cancelled in-flight pass and a new pass cannot interleave on `previous`.
    static func sample(_ setup: FrequencySetup) -> [CoreGroupKey: FrequencyReading?]? {
        setup.lock.lock()
        defer { setup.lock.unlock() }
        let sym = setup.symbols
        guard let current = sym.createSamples(setup.subscription, setup.channels, nil)?.takeRetainedValue() else {
            setup.previous = nil
            return nil
        }
        defer { setup.previous = current }
        guard let previous = setup.previous,
              let delta = sym.createDelta(previous, current, nil)?.takeRetainedValue() else { return nil }
        var out: [CoreGroupKey: FrequencyReading?] = [:]
        for item in channelItems(delta) {
            guard let name = string(sym.channelName(item)), let key = channelNames[name],
                  let table = setup.tables[key] else { continue }
            let count = Int(sym.stateCount(item))
            guard count > 0 else { out[key] = .some(nil); continue }
            var names: [String] = []
            var residencies: [Double] = []
            for i in 0..<count {
                names.append(string(sym.stateName(item, Int32(i))) ?? "")
                residencies.append(Double(sym.stateResidency(item, Int32(i))))
            }
            if let w = weightedMHz(residencies: residencies, stateNames: names, table: table.mhz) {
                out[key] = .some(FrequencyReading(mhz: w.mhz, activeShare: w.active))
            } else {
                out[key] = .some(nil)
            }
        }
        return out
    }

    private static func channelItems(_ report: CFDictionary) -> [CFDictionary] {
        guard let array = (report as NSDictionary)["IOReportChannels"] as? [Any] else { return [] }
        return array.compactMap { ($0 as? NSDictionary).map { $0 as CFDictionary } }
    }

    private static func string(_ s: Unmanaged<CFString>?) -> String? {
        s.map { $0.takeUnretainedValue() as String }
    }
}
