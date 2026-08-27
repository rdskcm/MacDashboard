// Engine/ProcessSampler.swift
// Live process-list sampler: one non-sleeping `/bin/ps` snapshot per call, turned
// into per-process CPU% by a measured delta against the previous snapshot (Block
// V2-PROC-NATIVE). NOT thread-safe — keeps mutable per-instance state (the previous
// snapshot and its timestamp), so use one instance per background context, the same
// contract `LiveCollector` itself follows. `sample()` blocks (subprocess + a one-time
// priming sleep) and must never be called on the main actor.
import Foundation
import Darwin

final class ProcessSampler {
    /// pid -> cumulative CPU seconds at the previous snapshot.
    private var previousCPUSeconds: [Int32: Double] = [:]
    /// Monotonic (awake-time) timestamp of the previous snapshot; nil until primed.
    private var previousAt: TimeInterval?
    /// Window used for the FIRST sample of an instance only (see the file header).
    static let primingWindow: TimeInterval = 0.6

    /// One `/bin/ps` invocation, parsed. No sleep, no per-pid subprocess.
    private func snapshot() -> [Parsers.PSRow] {
        guard let out = CommandRunner.run("/bin/ps",
            ["-axww", "-o", "pid=,rss=,time=,comm="], timeout: 5) else { return [] }
        return Parsers.psProcesses(out)
    }

    /// Pure CPU% math: percent of ONE core (the same per-core convention `top` used),
    /// computed as Δ(cumulative CPU seconds) / Δt over the caller-measured elapsed
    /// window. No hard-coded window length here — the caller supplies `elapsed`.
    static func cpuPercent(previousSeconds: Double?, currentSeconds: Double, elapsed: TimeInterval) -> Double? {
        guard let previous = previousSeconds else { return nil }
        guard elapsed > 0.05 else { return nil }
        guard currentSeconds >= previous else { return nil }
        return (currentSeconds - previous) / elapsed * 100
    }

    /// Physical footprint in bytes for `pid` — the metric Activity Monitor's "Memory"
    /// column and `top -stats mem` report. `ps -o rss` (what `Parsers.PSRow.memBytes`
    /// carries) is a different quantity: it counts shared framework pages in every
    /// process that maps them and ignores compressed memory, which on this machine put
    /// WindowServer at 178 M against top's 760 M and produced a different top-5
    /// entirely (V2-RELEASE re-review [M2]).
    ///
    /// Returns nil whenever the kernel refuses the read for this pid — this binary is
    /// unentitled, so some foreign-owned processes are simply not readable. The caller
    /// keeps that row's RSS instead; a refused pid must never drop a row or fail a sample.
    /// `RUSAGE_INFO_V4` rather than `RUSAGE_INFO_CURRENT`: `ri_phys_footprint` has been
    /// in the struct since v2, and pinning the version keeps the layout independent of
    /// whichever SDK compiles this.
    static func physFootprintBytes(pid: Int32) -> Int64? {
        var usage = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { raw in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, raw)
            }
        }
        guard rc == 0 else { return nil }
        let footprint = usage.ri_phys_footprint
        guard footprint > 0, footprint <= UInt64(Int64.max) else { return nil }
        return Int64(footprint)
    }

    /// Blocking; call off the main actor. First call on an instance primes itself
    /// (two `ps` runs, `primingWindow` seconds apart) so it never returns an
    /// all-nil-CPU list, including on the one-shot manual refresh path which builds
    /// a fresh `LiveCollector` (and therefore a fresh sampler) per press.
    func sample() -> [ProcEntry] {
        if previousAt == nil {
            let base = snapshot()
            guard !base.isEmpty else { return [] }
            previousCPUSeconds = Dictionary(base.map { ($0.pid, $0.cpuSeconds) },
                                            uniquingKeysWith: { max($0, $1) })
            previousAt = ProcessInfo.processInfo.systemUptime
            Thread.sleep(forTimeInterval: Self.primingWindow)
        }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - (previousAt ?? now)

        let rows = snapshot()
        guard !rows.isEmpty else { return [] }

        let entries = rows.enumerated().map { index, r in
            ProcEntry(rank: index, name: r.name,
                      cpu: Self.cpuPercent(previousSeconds: previousCPUSeconds[r.pid],
                                            currentSeconds: r.cpuSeconds, elapsed: elapsed),
                      // [M2]: footprint where the kernel allows it, this row's RSS otherwise.
                      memBytes: Self.physFootprintBytes(pid: r.pid) ?? r.memBytes,
                      pid: r.pid)
        }

        // Freshly built, not mutated in place — exited pids evaporate here instead
        // of leaking forever. `uniquingKeysWith` rather than `uniqueKeysWithValues`:
        // a duplicate pid in one snapshot must degrade, not trap the app
        // (V2-RELEASE re-review [N1]).
        previousCPUSeconds = Dictionary(rows.map { ($0.pid, $0.cpuSeconds) },
                                        uniquingKeysWith: { max($0, $1) })
        previousAt = now

        return entries
    }
}
