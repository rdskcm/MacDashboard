// Engine/ProcessSampler.swift
// Live process-list sampler: TWO subprocesses per call, each supplying only the columns
// it alone can — one non-sleeping `/bin/ps` snapshot for pids, names and cumulative CPU
// time (turned into per-process CPU% by a measured delta against the previous snapshot,
// Block V2-PROC-NATIVE), and one `/usr/bin/top` snapshot for the memory footprint of
// every process (re-review 2 [M1]; see `memoryFootprints()` for why it takes both).
// NOT thread-safe — keeps mutable per-instance state (the previous snapshot and its
// timestamp), so use one instance per background context, the same contract
// `LiveCollector` itself follows. `sample()` blocks (two subprocesses + a one-time
// priming sleep) and must never be called on the main actor.
import Foundation

final class ProcessSampler {
    /// pid -> cumulative CPU seconds at the previous snapshot.
    private var previousCPUSeconds: [Int32: Double] = [:]
    /// Monotonic (awake-time) timestamp of the previous snapshot; nil until primed.
    private var previousAt: TimeInterval?
    /// Window used for the FIRST sample of an instance only (see the file header).
    static let primingWindow: TimeInterval = 0.6

    /// One `/bin/ps` invocation, parsed. No sleep, and no per-pid work of any kind: the
    /// memory footprints come from ONE separate `/usr/bin/top` snapshot per tick
    /// (`memoryFootprints()`), never from a call per process.
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

    /// pid -> physical memory footprint in bytes for EVERY process on the machine, from ONE
    /// `/usr/bin/top` snapshot. This is the metric Activity Monitor's "Memory" column shows.
    /// `ps -o rss` (what `Parsers.PSRow.memBytes` carries) is a different quantity: it counts
    /// shared framework pages in every process that maps them and ignores compressed memory,
    /// which on this machine put WindowServer at 178 M against top's 760 M and produced a
    /// different top-5 entirely (V2-RELEASE re-review [M2]).
    ///
    /// Why a subprocess and not libproc: `proc_pid_rusage` (the first attempt at [M2]) and
    /// every in-process alternative — `proc_pidinfo(PROC_PIDTASKINFO)`, `task_for_pid` —
    /// apply a same-uid-or-root check to an unentitled binary like this one. Measured: 285
    /// of 384 pids refused with EPERM, WindowServer among them, so the Memory column silently
    /// mixed footprint for our own processes with RSS for everyone else and `rankedByMem`
    /// sorted across the mix (re-review 2 [M1]). `/usr/bin/top` is an Apple-signed platform
    /// binary carrying the task-port entitlement we cannot have, so it reads every process;
    /// one invocation for the whole table costs one fork/exec per tick, not one per pid.
    ///
    /// Why `ps` is still run alongside it: top's COMMAND column is hard-truncated to 16
    /// characters (the truncation this sampler exists to escape — see `Parsers.psCommandName`),
    /// and in `-l 1` logging mode its %CPU is a since-boot average, not a delta over our
    /// measured window. So top supplies exactly one column: MEM.
    ///
    /// Total: `[:]` when top cannot be launched or times out, and a pid is simply absent when
    /// its row did not parse. Either way the caller keeps that row's RSS — a failure here must
    /// never drop a row or fail a sample.
    static func memoryFootprints() -> [Int32: Int64] {
        guard let out = CommandRunner.run("/usr/bin/top",
            ["-l", "1", "-stats", "pid,command,mem"], timeout: 15) else { return [:] }
        return Parsers.topMemoryFootprints(out)
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

        // AFTER the ps snapshot on purpose: `now` and `rows` are both captured before this
        // call, so top's runtime shifts neither end of the CPU-delta window. One call for the
        // whole table — the per-pid syscall this replaced could not see foreign uids at all.
        let footprints = Self.memoryFootprints()

        let entries = rows.enumerated().map { index, r in
            ProcEntry(rank: index, name: r.name,
                      cpu: Self.cpuPercent(previousSeconds: previousCPUSeconds[r.pid],
                                            currentSeconds: r.cpuSeconds, elapsed: elapsed),
                      // [M1]: top's footprint for every process; RSS only for a pid top did
                      // not report (born between the two snapshots, or an unparsable row).
                      memBytes: footprints[r.pid] ?? r.memBytes,
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
