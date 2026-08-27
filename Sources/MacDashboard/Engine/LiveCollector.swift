// Engine/LiveCollector.swift
// Live metrics via native Mach/sysctl/IOKit calls (no subprocess for CPU/mem/swap/
// disk/battery/load) plus a single non-sleeping `/bin/ps` snapshot for both process
// tables. SPEC §5.1. NOT thread-safe: keep one instance and call collect() from a single
// background context (the model drives it off the main actor on a serial cadence).
// It reads no shared app state of its own — everything tunable arrives as a
// parameter, so the only state it owns is prevTicks (see collectFast).
//
// The CPU field needs two samples to produce a delta, so the FIRST collect() returns
// cpu == nil (it only primes the tick baseline); every later call returns a real
// user/sys/idle split. Any individual field that can't be read degrades to nil — a
// desktop Mac (no battery) or a locked-down sandbox never crashes the collector.

import Foundation
#if canImport(Darwin)
import Darwin
#endif
import IOKit.ps

final class LiveCollector {

    private var prevTicks: (user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)?
    private let procSampler = ProcessSampler()

    // Fast, all-native sample (no subprocess): load/cpu/mem/swap/disk/battery. This
    // method OWNS the prevTicks CPU-delta state (only readCPU touches it), so the
    // first collectFast() returns cpu == nil to prime the baseline, exactly as before.
    // topCPU/topMem are left at their empty defaults — fill them via sampleProcesses().
    func collectFast() -> LiveSnapshot {
        var snap = LiveSnapshot()
        snap.load = readLoad()
        snap.cpu = readCPU()
        snap.mem = readMemory()
        snap.swap = readSwap()
        snap.disk = readDisk()
        snap.battery = readBattery()
        snap.t = Date()
        return snap
    }

    // Slow sample: one non-sleeping `/bin/ps` snapshot plus the CPU- and memory-sorted
    // process tables (prefix(limit) + reranked()). CPU% is a delta over the interval
    // since this instance's previous sample; the first sample primes itself over
    // 0.6 s (see ProcessSampler). Split out so it can run on a slower cadence than
    // the native gauges.
    //
    // `limit` is a PARAMETER, not a read of AppSettings.shared. This method runs off
    // the main actor, while the setting is written from Settings on the main actor
    // (@Bindable, SettingsView) — reading it here raced with that write, and not only
    // over the Int: @Observable's accessors register the observer on read, so a
    // background read mutates shared bookkeeping. The caller now reads the setting on
    // the main actor and passes the value in, which also stops the collector reaching
    // into global UI state at all.
    func sampleProcesses(limit: Int) -> (topCPU: [ProcEntry], topMem: [ProcEntry]) {
        let procs = procSampler.sample()
        let topCPU = Array(procs.rankedByCPU().prefix(limit)).reranked()
        let topMem = Array(procs.rankedByMem().prefix(limit)).reranked()
        return (topCPU, topMem)
    }

    // Full snapshot: composed from the two halves above so existing callers (and the
    // Checks target) keep working unchanged.
    func collect(limit: Int) -> LiveSnapshot {
        var s = collectFast()
        let p = sampleProcesses(limit: limit)
        s.topCPU = p.topCPU
        s.topMem = p.topMem
        return s
    }

    // MARK: - load average

    private func readLoad() -> [Double]? {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : nil
    }

    // MARK: - CPU (host_statistics HOST_CPU_LOAD_INFO, tick delta between samples)

    private func readCPU() -> CPUUsage? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride
                                           / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        // cpu_ticks is a 4-tuple indexed by CPU_STATE_{USER,SYSTEM,IDLE,NICE} = 0,1,2,3.
        let user = UInt64(info.cpu_ticks.0)
        let sys = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        defer { prevTicks = (user, sys, idle, nice) }
        guard let prev = prevTicks else { return nil }  // first call only primes the baseline

        let dUser = user &- prev.user
        let dSys = sys &- prev.sys
        let dIdle = idle &- prev.idle
        let dNice = nice &- prev.nice
        let total = dUser &+ dSys &+ dIdle &+ dNice
        guard total > 0 else { return nil }
        let t = Double(total)
        // "user" folds in nice time, matching how Activity Monitor presents it.
        return CPUUsage(user: Double(dUser &+ dNice) / t * 100,
                        sys: Double(dSys) / t * 100,
                        idle: Double(dIdle) / t * 100)
    }

    // MARK: - memory (host_statistics64 HOST_VM_INFO64 + sysctl hw.memsize)

    private func readMemory() -> MemSnapshot? {
        var total: UInt64 = 0
        var tsize = MemoryLayout<UInt64>.stride
        guard sysctlbyname("hw.memsize", &total, &tsize, nil, 0) == 0, total > 0 else { return nil }

        var pageSize: vm_size_t = 0
        if host_page_size(mach_host_self(), &pageSize) != KERN_SUCCESS || pageSize == 0 {
            pageSize = 4096
        }
        let ps = Int64(pageSize)

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride
                                           / MemoryLayout<integer_t>.stride)
        var vm = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        func bytes(_ pages: natural_t) -> Int64 { Int64(pages) * ps }
        return MemSnapshot(
            total: Int64(total),
            pageSize: ps,
            free: bytes(vm.free_count),
            active: bytes(vm.active_count),
            inactive: bytes(vm.inactive_count),
            speculative: bytes(vm.speculative_count),
            wired: bytes(vm.wire_count),
            compressor: bytes(vm.compressor_page_count),
            purgeable: bytes(vm.purgeable_count),
            fileBacked: bytes(vm.external_page_count)
        )
    }

    // MARK: - swap (sysctl vm.swapusage → xsw_usage)

    private func readSwap() -> SwapInfo? {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 else { return nil }
        return SwapInfo(total: Int64(xsw.xsu_total),
                        used: Int64(xsw.xsu_used),
                        free: Int64(xsw.xsu_avail))
    }

    // MARK: - disk (volume resource values; Data volume, fall back to root)

    private func readDisk() -> DiskInfo? {
        for path in ["/System/Volumes/Data", "/"] {
            let url = URL(fileURLWithPath: path)
            guard let vals = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
            ]), let total = vals.volumeTotalCapacity, total > 0 else { continue }
            let avail = vals.volumeAvailableCapacityForImportantUsage ?? 0
            return DiskInfo(size: Int64(total), avail: Int64(avail), dataUsed: nil, sysUsed: nil)
        }
        return nil
    }

    // MARK: - battery (IOKit power sources; nil on desktops)

    private func readBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard (desc[kIOPSTypeKey as String] as? String) == (kIOPSInternalBatteryType as String)
            else { continue }

            let cur = desc[kIOPSCurrentCapacityKey as String] as? Int
            let mx = desc[kIOPSMaxCapacityKey as String] as? Int
            var charge: Int?
            if let cur, let mx, mx > 0 {
                charge = Int((Double(cur) / Double(mx) * 100).rounded())
            } else if let cur {
                charge = cur   // some sources already report a 0–100 value with no max
            }

            let psState = desc[kIOPSPowerSourceStateKey as String] as? String
            let onAC = psState == (kIOPSACPowerValue as String)
            // Named sourceLabel, not `source`: the enclosing `for source in list` loop
            // variable is the IOKit power-source object, and shadowing it here read as
            // if this were the same thing.
            let sourceLabel = psState.map { _ in onAC ? L.battSourceAC : L.battSourceBattery }

            let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
            var state: String?
            if let c = charge, c >= 100 { state = L.battStateCharged }
            else if isCharging { state = L.battStateCharging }
            else if onAC { state = L.battStateNotCharging }
            else { state = L.battStateDischarging }

            return BatteryInfo(source: sourceLabel, charge: charge, state: state,
                               cycles: nil, condition: nil, maxCapacity: nil)
        }
        return nil
    }

}

private extension Array where Element == ProcEntry {
    // Re-index rank so ProcEntry.id ("\(rank)-\(name)", used only when pid is nil)
    // stays unique after re-sorting; pid is preserved unchanged (it, not rank, is
    // what ProcessListCard tracks across live ticks for expansion/detail fetch).
    func reranked() -> [ProcEntry] {
        enumerated().map { ProcEntry(rank: $0.offset, name: $0.element.name,
                                     cpu: $0.element.cpu, memBytes: $0.element.memBytes,
                                     pid: $0.element.pid) }
    }
}

/// V2-RELAYOUT-RESIDUAL: the single deterministic tie-break behind both rankings —
/// pid ascending, `nil` pid last, name as the final discriminator so even two
/// pid-less rows can never swap. Its only job is to make the order a pure function
/// of the snapshot's CONTENT, never of `/bin/ps`'s emission order or of introsort's
/// internal state.
private func procTieBreak(_ a: ProcEntry, _ b: ProcEntry) -> Bool {
    switch (a.pid, b.pid) {
    case let (x?, y?): return x != y ? x < y : a.name < b.name
    case (_?, nil):    return true
    case (nil, _?):    return false
    case (nil, nil):   return a.name < b.name
    }
}

// Separate, non-private extension (V2-FIX-ROWID Step 2): `reranked()` above lives in
// a `private extension` (file-scope fileprivate), which `Checks/main.swift` — a
// different file — cannot see. This helper needs Checks coverage, so it gets its
// own non-private extension instead of joining that one.
extension Array where Element == ProcEntry {
    /// Ranks by the CPU% the row actually DISPLAYS — tenths of a percent, matching
    /// `fmtNum(_:decimals: 1)` in ProcessRowView — not by the raw Double, then breaks
    /// ties deterministically.
    ///
    /// V2-RELAYOUT-RESIDUAL: `sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }` was neither
    /// stable nor display-aligned, so the near-identical sub-1% tail of the list (and
    /// with it the `prefix(limit)` membership) re-permuted on sampling noise every 6 s
    /// tick. Every permutation changed `ProcessListCard.rowOrder`, which opened the
    /// 0.45 s reorder transaction (`ProcessCards.swift:241`) — the single most expensive
    /// thing this app does — to animate a change the user cannot see in the numbers.
    /// Rows still reorder for any difference the display shows; they no longer reorder
    /// for differences it doesn't.
    func rankedByCPU() -> [ProcEntry] {
        sorted { a, b in
            let ka = ((a.cpu ?? 0) * 10).rounded()
            let kb = ((b.cpu ?? 0) * 10).rounded()
            if ka != kb { return ka > kb }
            return procTieBreak(a, b)
        }
    }

    /// Ranks by `memBytes` exactly as before — only the tie-break is new (see
    /// `rankedByCPU`). Footprints are not quantised to display precision here: the
    /// memory list is not the default view and its ranks are stable at a 6 s cadence,
    /// so bucketing would be scope this block didn't measure a need for.
    func rankedByMem() -> [ProcEntry] {
        sorted { a, b in
            let ma = a.memBytes ?? 0
            let mb = b.memBytes ?? 0
            if ma != mb { return ma > mb }
            return procTieBreak(a, b)
        }
    }

    /// Reorders a freshly-sorted snapshot to match a previously captured pid
    /// sequence, so the list holds still while a detail panel is open.
    ///
    /// - Rows whose `pid` appears in `frozen` come first, in `frozen`'s order.
    /// - Rows absent from `frozen` (a process that newly entered the top-N) and
    ///   rows with `pid == nil` follow, in the receiver's own relative order.
    /// - Entries in `frozen` with no matching row in the receiver (the process
    ///   died / fell out of the top-N) are skipped.
    /// - Elements are passed through UNCHANGED — no re-ranking, no reconstruction.
    ///   Preserving `rank`/`id` is the entire point; rebuilding them here would
    ///   reintroduce the identity churn Step 1 examined.
    func stableOrdered(matching frozen: [Int32]) -> [ProcEntry] {
        guard !frozen.isEmpty else { return self }
        var byPID: [Int32: ProcEntry] = [:]
        for entry in self {
            if let pid = entry.pid { byPID[pid] = entry }
        }
        let frozenOrdered = frozen.compactMap { byPID[$0] }
        let frozenPIDs = Set(frozen)
        let trailing = self.filter { entry in
            guard let pid = entry.pid else { return true }
            return !frozenPIDs.contains(pid)
        }
        return frozenOrdered + trailing
    }
}
