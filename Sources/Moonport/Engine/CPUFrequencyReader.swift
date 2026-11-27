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
// banned in this app, see Engine/ThermalHIDReader.swift for why). Resolution is all-or-nothing, looked up once, a failure
// is cached and never retried.
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

struct FrequencyReading: Equatable, Sendable {
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
    /// Core types without a validated table, and why (READER-STATUS).
    let skipped: [CoreGroupKey: ReaderReason]
    fileprivate var previous: CFDictionary?
    /// Guards `previous`: `sample` reads, diffs and advances it as one step.
    fileprivate let lock = NSLock()

    fileprivate init(symbols: IOReportSymbols, subscription: OpaquePointer, channels: CFMutableDictionary,
                     tables: [CoreGroupKey: FrequencyTable], skipped: [CoreGroupKey: ReaderReason]) {
        self.symbols = symbols
        self.subscription = subscription
        self.channels = channels
        self.tables = tables
        self.skipped = skipped
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
        tableCheckFailure(table: table, stateCount: stateCount) == nil
    }

    /// Pure (READER-STATUS). The first failing D2 setup check as text, or nil when the table passes.
    static func tableCheckFailure(table: [Double], stateCount: Int) -> String? {
        guard table.count >= 2 else { return "(a) at least 2 entries, got \(table.count)" }
        for i in 1..<table.count where !(table[i] > table[i - 1]) { return "(b) strictly ascending" }
        guard let lo = table.first, let hi = table.last, lo >= 100, hi <= 10_000 else {
            return "(c) 100...10000 MHz, got \(Int((table.first ?? 0).rounded()))...\(Int((table.last ?? 0).rounded()))"
        }
        guard stateCount == table.count + 1 else { return "(d) state count \(stateCount) == entries \(table.count) + 1" }
        return nil
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

    static let libraryPath = "/usr/lib/libIOReport.dylib"
    static let symbolNames = ["IOReportCopyChannelsInGroup", "IOReportCreateSubscription", "IOReportCreateSamples",
                              "IOReportCreateSamplesDelta", "IOReportChannelGetChannelName", "IOReportStateGetCount",
                              "IOReportStateGetNameForIndex", "IOReportStateGetResidency"]

    /// READER-STATUS D10/D11: the failure keeps the first missing symbol or the dlerror text; partial resolution
    /// => the whole set fails closed. Looked up once, never retried.
    private static let symbolLoad: Result<IOReportSymbols, ReaderReason> =
        SymbolLoader.load(path: libraryPath, mode: RTLD_NOW, symbols: symbolNames).map { p in
            IOReportSymbols(
                copyGroup: unsafeBitCast(p[0], to: IOReportSymbols.CopyGroupFn.self),
                subscribe: unsafeBitCast(p[1], to: IOReportSymbols.SubscribeFn.self),
                createSamples: unsafeBitCast(p[2], to: IOReportSymbols.SamplesFn.self),
                createDelta: unsafeBitCast(p[3], to: IOReportSymbols.DeltaFn.self),
                channelName: unsafeBitCast(p[4], to: IOReportSymbols.NameFn.self),
                stateCount: unsafeBitCast(p[5], to: IOReportSymbols.CountFn.self),
                stateName: unsafeBitCast(p[6], to: IOReportSymbols.StateNameFn.self),
                stateResidency: unsafeBitCast(p[7], to: IOReportSymbols.ResidencyFn.self))
        }

    // MARK: - Setup (once per process, failure cached)

    /// Built on first access (about 35-65 ms, the IOReport group lookup), thread-safe by Swift's lazy static
    /// initialisation. The failure (READER-STATUS) says which of a symbol, the subscription, the first sample or
    /// every table check failed. Never retried.
    static let setupResult: Result<FrequencySetup, ReaderReason> = makeSetup()

    /// The setup, or nil when it failed: the same object every call, built once, never retried.
    static var shared: FrequencySetup? { try? setupResult.get() }

    static let groupName = "CPU Stats"
    static let subgroupName = "CPU Complex Performance States"
    private static let channelNames: [String: CoreGroupKey] = ["ECPU": .efficiency, "PCPU": .performance]
    private static let channelLabel: [CoreGroupKey: String] = [.efficiency: "ECPU", .performance: "PCPU"]
    /// pmgr property per core type (the performance-state tables of the E and P clusters).
    private static let tableProperty: [CoreGroupKey: String] = [.efficiency: "voltage-states1-sram",
                                                                .performance: "voltage-states5-sram"]

    private static func makeSetup() -> Result<FrequencySetup, ReaderReason> {
        let sym: IOReportSymbols
        switch symbolLoad {
        case .failure(let r): return .failure(r)
        case .success(let s): sym = s
        }
        guard let channels = sym.copyGroup(groupName as CFString, subgroupName as CFString, 0, 0, 0)?.takeRetainedValue()
        else { return .failure(.ioReportChannelAbsent(group: groupName, subgroup: subgroupName, channel: nil)) }
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let subscription = sym.subscribe(nil, channels, &subscribed, 0, nil)
        else { return .failure(.nullResult(call: "IOReportCreateSubscription")) }
        guard let subscribedChannels = subscribed?.takeRetainedValue()
        else { return .failure(.nullResult(call: "IOReportCreateSubscription subscribed channels")) }
        guard let first = sym.createSamples(subscription, subscribedChannels, nil)?.takeRetainedValue()
        else { return .failure(.nullResult(call: "IOReportCreateSamples")) }

        // D2(d) needs each channel's state count: read it from one sample.
        var stateCounts: [CoreGroupKey: Int] = [:]
        for item in channelItems(first) {
            guard let name = string(sym.channelName(item)), let key = channelNames[name] else { continue }
            stateCounts[key] = Int(sym.stateCount(item))
        }
        let pmgr = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pmgr")
        guard pmgr != 0 else { return .failure(.registryEntryAbsent(path: "IODeviceTree:/arm-io/pmgr")) }
        defer { IOObjectRelease(pmgr) }

        var tables: [CoreGroupKey: FrequencyTable] = [:]
        var skipped: [CoreGroupKey: ReaderReason] = [:]
        for (key, property) in tableProperty {
            guard let count = stateCounts[key] else {
                skipped[key] = .ioReportChannelAbsent(group: groupName, subgroup: subgroupName, channel: channelLabel[key])
                continue
            }
            guard let cf = IORegistryEntryCreateCFProperty(pmgr, property as CFString, kCFAllocatorDefault, 0),
                  let data = cf.takeRetainedValue() as? Data else {
                skipped[key] = .registryPropertyAbsent(entry: "IODeviceTree:/arm-io/pmgr", property: property)
                continue
            }
            guard let mhz = parseTable(data) else {
                skipped[key] = .validationFailed(what: property, check: "whole 8-byte pairs")
                continue
            }
            if let failure = tableCheckFailure(table: mhz, stateCount: count) {
                skipped[key] = .validationFailed(what: property, check: failure)
                continue
            }
            tables[key] = FrequencyTable(mhz: mhz)
        }
        guard !tables.isEmpty else { return .failure(.joined([.efficiency, .performance].compactMap { skipped[$0] })) }
        return .success(FrequencySetup(symbols: sym, subscription: subscription, channels: subscribedChannels,
                                       tables: tables, skipped: skipped))
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
            let r: FrequencyReading? = try? reading(item, channel: name, table: table, sym: sym).get()
            out[key] = .some(r)
        }
        return out
    }

    /// One channel's frequency reading from a delta item, or why it has none (READER-STATUS).
    private static func reading(_ item: CFDictionary, channel: String, table: FrequencyTable,
                                sym: IOReportSymbols) -> Result<FrequencyReading, ReaderReason> {
        let count = Int(sym.stateCount(item))
        guard count > 0 else { return .failure(.validationFailed(what: "IOReport \(channel)", check: "state count > 0")) }
        var names: [String] = []
        var residencies: [Double] = []
        for i in 0..<count {
            names.append(string(sym.stateName(item, Int32(i))) ?? "")
            residencies.append(Double(sym.stateResidency(item, Int32(i))))
        }
        guard let w = weightedMHz(residencies: residencies, stateNames: names, table: table.mhz) else {
            return .failure(.validationFailed(what: "IOReport \(channel) residencies", check: "D2 (e)/(f) weighting"))
        }
        return .success(FrequencyReading(mhz: w.mhz, activeShare: w.active))
    }

    /// The report's own frequency check (READER-STATUS D8): two samples `window` apart, diffed locally. Never touches
    /// `setup.previous`, so the live sampler's next delta is unchanged; the lock is held only around each createSamples.
    static func probe(window: TimeInterval = 0.25) -> FrequencyProbe {
        let setup: FrequencySetup
        switch setupResult {
        case .failure(let r): return FrequencyProbe(setupFailure: r)
        case .success(let s): setup = s
        }
        var p = FrequencyProbe(skipped: setup.skipped)
        let sym = setup.symbols
        func take() -> CFDictionary? {
            setup.lock.lock()
            defer { setup.lock.unlock() }
            return sym.createSamples(setup.subscription, setup.channels, nil)?.takeRetainedValue()
        }
        guard let first = take() else { p.sampleFailure = .nullResult(call: "IOReportCreateSamples"); return p }
        Thread.sleep(forTimeInterval: window)
        guard let second = take() else { p.sampleFailure = .nullResult(call: "IOReportCreateSamples"); return p }
        guard let delta = sym.createDelta(first, second, nil)?.takeRetainedValue() else {
            p.sampleFailure = .nullResult(call: "IOReportCreateSamplesDelta"); return p
        }
        for key in setup.tables.keys {
            p.readings[key] = .failure(.ioReportChannelAbsent(group: groupName, subgroup: subgroupName, channel: channelLabel[key]))
        }
        for item in channelItems(delta) {
            guard let name = string(sym.channelName(item)), let key = channelNames[name], let table = setup.tables[key] else { continue }
            p.readings[key] = reading(item, channel: name, table: table, sym: sym)
        }
        return p
    }

    private static func channelItems(_ report: CFDictionary) -> [CFDictionary] {
        guard let array = (report as NSDictionary)["IOReportChannels"] as? [Any] else { return [] }
        return array.compactMap { ($0 as? NSDictionary).map { $0 as CFDictionary } }
    }

    private static func string(_ s: Unmanaged<CFString>?) -> String? {
        s.map { $0.takeUnretainedValue() as String }
    }
}

/// What the report's frequency check found (READER-STATUS).
struct FrequencyProbe: Equatable, Sendable {
    var setupFailure: ReaderReason? = nil
    var skipped: [CoreGroupKey: ReaderReason] = [:]
    var sampleFailure: ReaderReason? = nil
    var readings: [CoreGroupKey: Result<FrequencyReading, ReaderReason>] = [:]
}
