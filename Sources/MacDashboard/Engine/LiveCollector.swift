// Engine/LiveCollector.swift
// Live metrics via native Mach/sysctl/IOKit calls (no subprocess for CPU/mem/swap/
// disk/battery/load) plus a single short `top` invocation for both process tables.
// SPEC §5.1. NOT thread-safe: keep one instance and call collect() from a single
// background context (the model drives it off the main actor on a serial cadence).
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

    // Slow sample: the single `top` subprocess plus the CPU- and memory-sorted
    // process tables (prefix(12) + reranked()). Split out so it can run on a slower
    // cadence than the native gauges.
    func sampleProcesses() -> (topCPU: [ProcEntry], topMem: [ProcEntry]) {
        let procs = readTopProcesses()
        let topCPU = Array(procs.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }.prefix(12)).reranked()
        let topMem = Array(procs.sorted { ($0.memBytes ?? 0) > ($1.memBytes ?? 0) }.prefix(12)).reranked()
        return (topCPU, topMem)
    }

    // Full snapshot: composed from the two halves above so existing callers (and the
    // Checks target) keep working unchanged.
    func collect() -> LiveSnapshot {
        var s = collectFast()
        let p = sampleProcesses()
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
            let source = psState.map { _ in onAC ? L.battSourceAC : L.battSourceBattery }

            let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
            var state: String?
            if let c = charge, c >= 100 { state = L.battStateCharged }
            else if isCharging { state = L.battStateCharging }
            else if onAC { state = L.battStateNotCharging }
            else { state = L.battStateDischarging }

            return BatteryInfo(source: source, charge: charge, state: state,
                               cycles: nil, condition: nil, maxCapacity: nil)
        }
        return nil
    }

    // MARK: - top process tables (single subprocess, parsed by Parsers)

    private func readTopProcesses() -> [ProcEntry] {
        // -l 2 with a 1s interval: the FIRST sample carries since-boot CPU deltas
        // (garbage); Parsers.topProcesses keeps only the LAST sample, which has a
        // real 1s delta. No -n cap -> top prints ALL processes (logging mode), so
        // sorting by memory in Swift finds the true memory hogs (a -n cap would hide
        // them). One subprocess now feeds both the CPU- and memory-sorted tables.
        guard let out = CommandRunner.run("/usr/bin/top",
            ["-l", "2", "-s", "1", "-stats", "pid,cpu,mem,command"],
            timeout: 12) else { return [] }
        return Parsers.topProcesses(out, order: (.cpu, .mem), leadingPID: true)
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
