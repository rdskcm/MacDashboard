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
        let unknown = [CoreGroup(name: nil, count: ncpu, coreIndices: Array(0..<max(ncpu, 0)))]
        guard ncpu > 0, !levels.isEmpty, let letters = clusterLetters, letters.count == ncpu,
              levels.reduce(0, { $0 + $1.count }) == ncpu else { return unknown }
        // A level maps to a cluster letter by its name initial (P → Performance, E → Efficiency).
        var initials: [Character] = []
        for level in levels {
            guard let initial = level.name?.first?.uppercased().first else { return unknown }
            initials.append(initial)
        }
        guard Set(initials).count == initials.count else { return unknown }   // two levels, one letter: ambiguous
        var groups: [CoreGroup] = []
        var covered = 0
        for (i, level) in levels.enumerated() where level.count > 0 {
            let indices = letters.indices.filter { letters[$0].uppercased().first == initials[i] }
            guard indices.count == level.count else { return unknown }
            covered += indices.count
            groups.append(CoreGroup(name: level.name, count: level.count, coreIndices: indices))
        }
        guard covered == ncpu else { return unknown }
        return groups
    }

    /// IOKit + sysctl. Read once per process (see `cached`). Groups in perflevel index order, so Performance first (D19).
    static func read() -> [CoreGroup] {
        let ncpu = ProcessInfo.processInfo.activeProcessorCount
        var levels: [PerfLevel] = []
        var i = 0
        while let count = sysctlInt32("hw.perflevel\(i).physicalcpu") {
            levels.append(PerfLevel(name: sysctlString("hw.perflevel\(i).name"), count: Int(count)))
            i += 1
        }
        return resolve(levels: levels, clusterLetters: readClusterLetters(), ncpu: ncpu)
    }

    /// Cached result of `read()`: the topology never changes while the process runs.
    static let cached: [CoreGroup] = read()

    /// First byte of `cluster-type` for cpu0...cpuN-1, ordered by core index. nil when the node, a child or a
    /// property is missing, or the indices are not exactly 0...N-1.
    static func readClusterLetters() -> [Character]? {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return nil }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS,
              iterator != 0 else { return nil }
        defer { IOObjectRelease(iterator) }
        var byIndex: [Int: Character] = [:]
        while true {
            let child = IOIteratorNext(iterator)
            if child == 0 { break }
            defer { IOObjectRelease(child) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(child, &nameBuffer) == KERN_SUCCESS else { continue }
            guard let index = coreIndex(fromNodeName: String(cString: nameBuffer)) else { continue }
            guard let cf = IORegistryEntryCreateCFProperty(child, "cluster-type" as CFString, kCFAllocatorDefault, 0),
                  let data = cf.takeRetainedValue() as? Data, let first = data.first else { return nil }
            byIndex[index] = Character(UnicodeScalar(first))
        }
        guard !byIndex.isEmpty, Set(byIndex.keys) == Set(0..<byIndex.count) else { return nil }
        return (0..<byIndex.count).map { byIndex[$0]! }
    }

    /// Pure. "cpu7" → 7; anything else (including "cpus") → nil.
    static func coreIndex(fromNodeName name: String) -> Int? {
        guard name.hasPrefix("cpu"), name.count > 3 else { return nil }
        return Int(name.dropFirst(3))
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, size == MemoryLayout<Int32>.size else { return nil }
        return value
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let s = String(cString: buffer)
        return s.isEmpty ? nil : s
    }
}

enum CoreLoadReader {
    /// `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`: cumulative ticks per core, index order. nil on any failure.
    static func readTicks() -> [CoreTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        guard cpuCount > 0, Int(infoCount) >= Int(cpuCount) * states else { return nil }
        return (0..<Int(cpuCount)).map { i in
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[i * states + Int(state)])) }
            return CoreTicks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                             idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        }
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
