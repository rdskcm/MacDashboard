// Engine/GPUStats.swift
// GPU-UTILIZATION: whole-machine GPU load from the IOAccelerator registry entry's `PerformanceStatistics`
// (`Device Utilization %`). Undocumented key, matched exactly; absent → nil → the UI shows «—».
// SOC-DETAILS 1.3: the GPU core count (`gpu-core-count`) and the IOAccelerator client list (`IOUserClientCreator`,
// `AppUsage[].accumulatedGPUTime`) for the top-processes-by-GPU list. Public IOKit calls on undocumented property
// names, matched exactly; any failure → nil. Method sources (open, MIT), no code copied: Stats
// Modules/GPU/reader.swift:396-425 and :505-548 (client children and their AppUsage), macmon src/sources.rs:794
// (gpu-core-count); measured in inputs/SOC-DETAILS-research/probe-load-tested/probe.swift:395-414 and :444-445.
import Foundation
import IOKit

enum GPUStats {
    static let deviceUtilizationKey = "Device Utilization %"

    /// Pure. nil when the key is absent or not a number. Clamped to 0...100.
    static func deviceUtilization(performanceStatistics: [String: Any]) -> Int? {
        guard let n = performanceStatistics[deviceUtilizationKey] as? NSNumber else { return nil }
        return min(100, max(0, n.intValue))
    }

    /// IOKit. Max `Device Utilization %` over every IOAccelerator entry; nil when none has it. Never throws.
    static func readDeviceUtilization() -> Int? {
        try? readDeviceUtilizationResult().get()
    }

    /// The IOAccelerator service iterator, or why there is none (READER-STATUS T1 rows 12-14).
    private static func acceleratorIterator() -> Result<io_iterator_t, ReaderReason> {
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
        guard kr == KERN_SUCCESS else {
            return .failure(.kernReturn(call: "IOServiceGetMatchingServices(IOAccelerator)", code: kr))
        }
        guard iterator != 0 else { return .failure(.serviceAbsent(className: "IOAccelerator")) }
        return .success(iterator)
    }

    /// `readDeviceUtilization` with the failure reason (READER-STATUS T1 row 12).
    static func readDeviceUtilizationResult() -> Result<Int, ReaderReason> {
        let iterator: io_iterator_t
        switch acceleratorIterator() {
        case .success(let it): iterator = it
        case .failure(let r): return .failure(r)
        }
        defer { IOObjectRelease(iterator) }
        var best: Int? = nil
        var sawEntry = false
        var sawStats = false
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            sawEntry = true
            guard let cf = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                  let dict = cf.takeRetainedValue() as? [String: Any] else { continue }
            sawStats = true
            guard let v = deviceUtilization(performanceStatistics: dict) else { continue }
            best = max(best ?? v, v)
        }
        if let best { return .success(best) }
        if !sawEntry { return .failure(.serviceAbsent(className: "IOAccelerator")) }
        if !sawStats { return .failure(.registryPropertyAbsent(entry: "IOAccelerator", property: "PerformanceStatistics")) }
        return .failure(.registryPropertyAbsent(entry: "IOAccelerator PerformanceStatistics", property: deviceUtilizationKey))
    }

    // MARK: - SOC-DETAILS: core count and client list

    /// `readCoreCount()` once per process: the count never changes (logic 3.4).
    static let cachedCoreCount: Int? = readCoreCount()

    /// IOKit. `gpu-core-count` of the first IOAccelerator entry that has a positive one; nil when none does.
    static func readCoreCount() -> Int? {
        try? readCoreCountResult().get()
    }

    /// `readCoreCount` with the failure reason (READER-STATUS T1 row 13).
    static func readCoreCountResult() -> Result<Int, ReaderReason> {
        let iterator: io_iterator_t
        switch acceleratorIterator() {
        case .success(let it): iterator = it
        case .failure(let r): return .failure(r)
        }
        defer { IOObjectRelease(iterator) }
        var sawEntry = false
        var firstNonPositive: Int? = nil
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            sawEntry = true
            if let cf = IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString, kCFAllocatorDefault, 0),
               let n = cf.takeRetainedValue() as? NSNumber {
                if n.intValue > 0 { return .success(n.intValue) }
                if firstNonPositive == nil { firstNonPositive = n.intValue }
            }
        }
        if !sawEntry { return .failure(.serviceAbsent(className: "IOAccelerator")) }
        if let bad = firstNonPositive { return .failure(.implausible(what: "gpu-core-count", value: "\(bad)", accepted: "> 0")) }
        return .failure(.registryPropertyAbsent(entry: "IOAccelerator", property: "gpu-core-count"))
    }

    /// Pure. "pid 123, Name" → (123, "Name"). nil when the prefix, the pid or the comma is missing. The name is the
    /// source's own text, at most 16 characters, kept as given apart from surrounding blanks.
    static func parseClientCreator(_ s: String) -> (pid: Int32, name16: String)? {
        guard s.hasPrefix("pid ") else { return nil }
        let parts = s.dropFirst(4).split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let pid = Int32(parts[0].trimmingCharacters(in: .whitespaces)), pid > 0 else { return nil }
        return (pid, parts[1].trimmingCharacters(in: .whitespaces))
    }

    /// Pure. Σ `accumulatedGPUTime` over the `AppUsage` entries; nil when the list is absent or has no readable entry.
    static func accumulatedGPUTimeNs(appUsage: [[String: Any]]) -> UInt64? {
        let times = appUsage.compactMap { ($0["accumulatedGPUTime"] as? NSNumber)?.uint64Value }
        return times.isEmpty ? nil : times.reduce(0, +)
    }

    /// IOKit. One sample per IOAccelerator child that is a client with `AppUsage`. nil when no IOAccelerator entry
    /// exists or an iterator cannot be created; `[]` when the source works and no child has `AppUsage`.
    static func readClients() -> [GPUClientSample]? {
        try? readClientsResult().get()
    }

    /// `readClients` with the failure reason (READER-STATUS T1 row 14).
    static func readClientsResult() -> Result<[GPUClientSample], ReaderReason> {
        let accelerators: io_iterator_t
        switch acceleratorIterator() {
        case .success(let it): accelerators = it
        case .failure(let r): return .failure(r)
        }
        defer { IOObjectRelease(accelerators) }
        var out: [GPUClientSample] = []
        var sawAccelerator = false
        let childCall = "IORegistryEntryGetChildIterator(IOAccelerator)"
        while true {
            let entry = IOIteratorNext(accelerators)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            sawAccelerator = true
            var children: io_iterator_t = 0
            let kr = IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children)
            guard kr == KERN_SUCCESS else { return .failure(.kernReturn(call: childCall, code: kr)) }
            guard children != 0 else { return .failure(.nullResult(call: childCall)) }
            defer { IOObjectRelease(children) }
            while true {
                let child = IOIteratorNext(children)
                if child == 0 { break }
                defer { IOObjectRelease(child) }
                guard let creatorCF = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0),
                      let creator = creatorCF.takeRetainedValue() as? String,
                      let who = parseClientCreator(creator),
                      let usageCF = IORegistryEntryCreateCFProperty(child, "AppUsage" as CFString, kCFAllocatorDefault, 0),
                      let usage = usageCF.takeRetainedValue() as? [[String: Any]],
                      let ns = accumulatedGPUTimeNs(appUsage: usage) else { continue }
                out.append(GPUClientSample(pid: who.pid, name16: who.name16, gpuTimeNs: ns))
            }
        }
        return sawAccelerator ? .success(out) : .failure(.serviceAbsent(className: "IOAccelerator"))
    }
}

/// One IOAccelerator client: its creator pid, the source's 16-character process name and its accumulated GPU time.
struct GPUClientSample: Equatable {
    let pid: Int32
    let name16: String
    let gpuTimeNs: UInt64
}
