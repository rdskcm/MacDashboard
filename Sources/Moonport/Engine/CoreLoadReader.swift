// Engine/CoreLoadReader.swift
// SOC-DETAILS 1.1: per-core load and core topology (which core belongs to which core type).
// Public APIs only: host_processor_info (Mach), sysctl hw.perflevel<i>.*, IORegistry `cluster-type`. No private symbols.
//
// Method sources (open, MIT), cited by file and line; no code was copied from either:
// - Stats (exelban/stats): Modules/CPU/readers.swift:45-65 (host_processor_info per-core ticks, then vm_deallocate),
//   Kit/plugins/SystemKit.swift:383-470 (core types from the IORegistry `cluster-type` of the cpuN nodes).
// - Measured on the reference Mac in inputs/SOC-DETAILS-research/probe-load-tested/probe.swift:305-322 (ticks) and
//   :349-370 (registry walk). The device-tree walk here uses `IODeviceTree:/cpus` and its children directly.
//
// Failure model: every read returns nil (ticks) or the "type unknown" single group (topology). Never throws.

import Foundation
import IOKit

/// One group of cores of the same type. `name` is the sysctl `hw.perflevel<i>.name` as the system gives it
/// ("Performance", "Efficiency", an unfamiliar name is kept); nil = type unknown.
struct CoreGroup: Equatable {
    let name: String?
    let count: Int
    let coreIndices: [Int]
}

/// Cumulative tick counters of one core, widened from the kernel's 32-bit counters.
struct CoreTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
}

/// One `hw.perflevel<i>` entry: its name and physical core count.
struct PerfLevel: Equatable {
    let name: String?
    let count: Int
}

enum CoreTopology {
    /// Pure. Maps cores to groups.
    /// - `levels`: sysctl perflevels in index order (0 = the system's first level, Performance on every measured chip).
    /// - `clusterLetters`: the first byte of `cluster-type` for cpu0...cpuN-1 in index order, nil when it could not be read.
    /// - `ncpu`: `activeProcessorCount`.
    /// Any mismatch (levels empty or unnamed, registry count != ncpu, level counts do not sum to ncpu, a letter that
    /// maps to no level or to two, a group whose cores do not match its count) → one group of unknown type (logic 3.1).
    static func resolve(levels: [PerfLevel], clusterLetters: [Character]?, ncpu: Int) -> [CoreGroup] {
        let levelsResult: Result<[PerfLevel], ReaderReason> = levels.isEmpty
            ? .failure(.validationFailed(what: "core topology", check: "hw.perflevel0 present")) : .success(levels)
        let lettersResult: Result<[Character], ReaderReason> = clusterLetters.map { .success($0) }
            ?? .failure(.nullResult(call: "readClusterLetters"))
        return (try? resolution(levels: levelsResult, clusterLetters: lettersResult, ncpu: ncpu).get()) ?? unknownGroup(ncpu: ncpu)
    }

    /// Pure. The one group of unknown type (READER-STATUS: was the local `unknown` of `resolve`).
    static func unknownGroup(ncpu: Int) -> [CoreGroup] {
        [CoreGroup(name: nil, count: ncpu, coreIndices: Array(0..<max(ncpu, 0)))]
    }

    /// Pure. `resolve` with the failed check named (READER-STATUS spec T5); checks run in `resolve`'s order.
    static func resolution(levels levelsResult: Result<[PerfLevel], ReaderReason>,
                           clusterLetters lettersResult: Result<[Character], ReaderReason>,
                           ncpu: Int) -> Result<[CoreGroup], ReaderReason> {
        func fail(_ check: String) -> Result<[CoreGroup], ReaderReason> {
            .failure(.validationFailed(what: "core topology", check: check))
        }
        guard ncpu > 0 else { return fail("activeProcessorCount \(ncpu) > 0") }
        let levels: [PerfLevel]
        switch levelsResult {
        case .success(let l): levels = l
        case .failure(let r): return .failure(r)
        }
        guard !levels.isEmpty else { return fail("hw.perflevel0 present") }
        let letters: [Character]
        switch lettersResult {
        case .success(let l): letters = l
        case .failure(let r): return .failure(r)
        }
        guard letters.count == ncpu else { return fail("cluster-type count \(letters.count) == activeProcessorCount \(ncpu)") }
        let sum = levels.reduce(0) { $0 + $1.count }
        guard sum == ncpu else { return fail("perflevel core sum \(sum) == activeProcessorCount \(ncpu)") }
        // A level maps to a cluster letter by its name initial (P → Performance, E → Efficiency).
        var initials: [Character] = []
        for (i, level) in levels.enumerated() {
            guard let initial = level.name?.first?.uppercased().first else { return fail("hw.perflevel\(i).name present") }
            initials.append(initial)
        }
        guard Set(initials).count == initials.count else { return fail("perflevel name initials unique") }   // two levels, one letter: ambiguous
        var groups: [CoreGroup] = []
        var covered = 0
        for (i, level) in levels.enumerated() where level.count > 0 {
            let indices = letters.indices.filter { letters[$0].uppercased().first == initials[i] }
            guard indices.count == level.count else {
                return fail("\(level.name ?? "unknown") cores \(indices.count) == hw.perflevel\(i).physicalcpu \(level.count)")
            }
            covered += indices.count
            groups.append(CoreGroup(name: level.name, count: level.count, coreIndices: indices))
        }
        guard covered == ncpu else { return fail("covered cores \(covered) == activeProcessorCount \(ncpu)") }
        return .success(groups)
    }

    /// IOKit + sysctl. Read once per process (see `cached`). Groups in perflevel index order, so Performance first (D19).
    static func read() -> [CoreGroup] {
        (try? readResolution().get()) ?? unknownGroup(ncpu: ProcessInfo.processInfo.activeProcessorCount)
    }

    /// `read()` with the failed check named (READER-STATUS).
    static func readResolution() -> Result<[CoreGroup], ReaderReason> {
        resolution(levels: readLevels(), clusterLetters: readClusterLettersResult(),
                   ncpu: ProcessInfo.processInfo.activeProcessorCount)
    }

    /// `hw.perflevel<i>` entries in index order. A failure at index 0 is the result's failure, a later one ends the list.
    static func readLevels() -> Result<[PerfLevel], ReaderReason> {
        var levels: [PerfLevel] = []
        var i = 0
        while true {
            switch SysctlRead.int32("hw.perflevel\(i).physicalcpu") {
            case .success(let count):
                levels.append(PerfLevel(name: sysctlString("hw.perflevel\(i).name"), count: Int(count)))
                i += 1
            case .failure(let reason):
                return i == 0 ? .failure(reason) : .success(levels)
            }
        }
    }

    /// Cached result of `read()`: the topology never changes while the process runs.
    static let cached: [CoreGroup] = read()

    /// First byte of `cluster-type` for cpu0...cpuN-1, ordered by core index. nil when the node, a child or a
    /// property is missing, or the indices are not exactly 0...N-1.
    static func readClusterLetters() -> [Character]? {
        try? readClusterLettersResult().get()
    }

    /// One `cpuN` child of `IODeviceTree:/cpus` as the registry returned it (READER-STATUS spec T5).
    /// `clusterType` is the first byte of `cluster-type`, nil when the property is missing, not Data or empty.
    struct ClusterTypeEntry: Equatable {
        let index: Int
        let clusterType: UInt8?
    }

    /// `readClusterLetters` with the failure reason (READER-STATUS spec T5).
    static func readClusterLettersResult() -> Result<[Character], ReaderReason> {
        clusterLetters(from: readClusterTypeEntries())
    }

    /// Thin IOKit read of the `cpuN` children of `IODeviceTree:/cpus`, in iteration order.
    /// `.success(nil)` means the `IODeviceTree:/cpus` entry does not exist (READER-STATUS spec T5).
    static func readClusterTypeEntries() -> Result<[ClusterTypeEntry]?, ReaderReason> {
        let cpusPath = "IODeviceTree:/cpus"
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, cpusPath)
        guard cpus != 0 else { return .success(nil) }
        defer { IOObjectRelease(cpus) }
        let iteratorCall = "IORegistryEntryGetChildIterator(\(cpusPath))"
        var iterator: io_iterator_t = 0
        let kr = IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator)
        guard kr == KERN_SUCCESS else { return .failure(.kernReturn(call: iteratorCall, code: kr)) }
        guard iterator != 0 else { return .failure(.nullResult(call: iteratorCall)) }
        defer { IOObjectRelease(iterator) }
        var entries: [ClusterTypeEntry] = []
        while true {
            let child = IOIteratorNext(iterator)
            if child == 0 { break }
            defer { IOObjectRelease(child) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(child, &nameBuffer) == KERN_SUCCESS else { continue }
            guard let index = coreIndex(fromNodeName: String(nulTerminated: nameBuffer)) else { continue }
            let data = IORegistryEntryCreateCFProperty(child, "cluster-type" as CFString, kCFAllocatorDefault, 0)
                .flatMap { $0.takeRetainedValue() as? Data }
            entries.append(ClusterTypeEntry(index: index, clusterType: data?.first))
        }
        return .success(entries)
    }

    /// Pure. Maps the raw registry entries to cluster letters ordered by core index, or the T5 reason.
    static func clusterLetters(from raw: Result<[ClusterTypeEntry]?, ReaderReason>) -> Result<[Character], ReaderReason> {
        let cpusPath = "IODeviceTree:/cpus"
        let entries: [ClusterTypeEntry]
        switch raw {
        case .failure(let reason): return .failure(reason)
        case .success(nil): return .failure(.registryEntryAbsent(path: cpusPath))
        case .success(let found?): entries = found
        }
        var byIndex: [Int: Character] = [:]
        for entry in entries {
            guard let first = entry.clusterType else {
                return .failure(.registryPropertyAbsent(entry: "\(cpusPath)/cpu\(entry.index)", property: "cluster-type"))
            }
            byIndex[entry.index] = Character(UnicodeScalar(first))
        }
        guard !byIndex.isEmpty, Set(byIndex.keys) == Set(0..<byIndex.count) else {
            return .failure(.validationFailed(what: "\(cpusPath) children",
                                              check: "indices 0..<\(byIndex.count), got \(byIndex.keys.sorted())"))
        }
        return .success((0..<byIndex.count).map { byIndex[$0]! })
    }

    /// Pure. "cpu7" → 7; anything else (including "cpus") → nil.
    static func coreIndex(fromNodeName name: String) -> Int? {
        guard name.hasPrefix("cpu"), name.count > 3 else { return nil }
        return Int(name.dropFirst(3))
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        try? SysctlRead.int32(name).get()
    }

    static func sysctlString(_ name: String) -> String? {
        try? SysctlRead.string(name).get()
    }
}

enum CoreLoadReader {
    /// `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`: cumulative ticks per core, index order. nil on any failure.
    static func readTicks() -> [CoreTicks]? {
        try? readTicksResult().get()
    }

    /// `readTicks` with the failure reason (READER-STATUS T1 row 10).
    static func readTicksResult() -> Result<[CoreTicks], ReaderReason> {
        let call = "host_processor_info(PROCESSOR_CPU_LOAD_INFO)"
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS else { return .failure(.kernReturn(call: call, code: kr)) }
        guard let info else { return .failure(.nullResult(call: call)) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        guard cpuCount > 0, Int(infoCount) >= Int(cpuCount) * states else {
            return .failure(.validationFailed(what: "host_processor_info",
                                              check: "infoCount \(infoCount) >= cpuCount \(cpuCount) x CPU_STATE_MAX"))
        }
        return .success((0..<Int(cpuCount)).map { i in
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[i * states + Int(state)])) }
            return CoreTicks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                             idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        })
    }

    /// Pure. Per core `(Δuser + Δsystem + Δnice) / Δtotal × 100`, rounded, 0...100. nil for a core with no elapsed
    /// ticks; every entry nil when the core counts differ (logic 3.1). The kernel counters are 32-bit and wrap, so a
    /// delta is taken modulo 2^32.
    static func usage(prev: [CoreTicks], cur: [CoreTicks]) -> [Int?] {
        guard prev.count == cur.count else { return Array(repeating: nil, count: cur.count) }
        func delta(_ a: UInt64, _ b: UInt64) -> UInt64 { (b &- a) & 0xFFFF_FFFF }
        return zip(prev, cur).map { p, c in
            let user = delta(p.user, c.user), system = delta(p.system, c.system)
            let idle = delta(p.idle, c.idle), nice = delta(p.nice, c.nice)
            let total = user + system + idle + nice
            guard total > 0 else { return nil }
            let busy = Double(user + system + nice) / Double(total) * 100
            return min(100, max(0, Int(busy.rounded())))
        }
    }
}
