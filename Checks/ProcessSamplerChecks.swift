// Checks/ProcessSamplerChecks.swift
// Block V2-PROC-NATIVE: pure-logic checks for the `ps`-based process sampler
// (time parsing, table parsing, CPU% delta math) plus a real-machine smoke test.
// Real file (not a symlink) — main.swift owns the single top-level-statements slot,
// so this exposes a plain function it calls (see README.md).

import Foundation

func runProcessSamplerChecks() {
    // MARK: - Parsers.psCPUSeconds

    func approxEqual(_ a: Double?, _ b: Double, tolerance: Double = 1e-6) -> Bool {
        guard let a else { return false }
        return abs(a - b) < tolerance
    }

    check(approxEqual(Parsers.psCPUSeconds("0:00.05"), 0.05), "psCPUSeconds: \"0:00.05\" == 0.05")
    check(approxEqual(Parsers.psCPUSeconds("145:22.35"), 8722.35),
          "psCPUSeconds: \"145:22.35\" == 8722.35 (minutes not rolled into hours)")
    check(approxEqual(Parsers.psCPUSeconds("1:02:03"), 3723), "psCPUSeconds: \"1:02:03\" == 3723")
    check(approxEqual(Parsers.psCPUSeconds("2-03:04:05"), 183845), "psCPUSeconds: \"2-03:04:05\" == 183845")
    check(Parsers.psCPUSeconds("") == nil, "psCPUSeconds: empty ⇒ nil")
    check(Parsers.psCPUSeconds("-") == nil, "psCPUSeconds: \"-\" ⇒ nil")
    check(Parsers.psCPUSeconds("abc") == nil, "psCPUSeconds: \"abc\" ⇒ nil")
    check(Parsers.psCPUSeconds("1:2:3:4:5") == nil, "psCPUSeconds: \"1:2:3:4:5\" (too many components) ⇒ nil")

    // MARK: - Parsers.psProcesses

    let psFixture = """
        1      3216   0:12.34 /sbin/launchd
      602    401584 145:22.35 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
        0     29184  33:10.00 kernel_task
    99999      1024   0:00.01 (bash)
      bad      1024   0:00.01 /usr/bin/garbage
     1234      2048   nope    /usr/bin/garbage2
     4321      4096   0:00.10 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper
    """

    let rows = Parsers.psProcesses(psFixture)
    check(rows.count == 5, "psProcesses: 5 rows survive (bad pid + nope time skipped), got \(rows.count)")

    if let windowServer = rows.first(where: { $0.pid == 602 }) {
        check(approxEqual(windowServer.cpuSeconds, 8722.35), "psProcesses: WindowServer cpuSeconds == 8722.35")
        check(windowServer.memBytes == 401584 * 1024, "psProcesses: WindowServer memBytes == 401584 KiB in bytes")
        check(windowServer.name == "WindowServer", "psProcesses: WindowServer name has path stripped, no ellipsis (got \(windowServer.name))")
    } else {
        check(false, "psProcesses: pid 602 (WindowServer) row present")
    }

    if let kernelTask = rows.first(where: { $0.pid == 0 }) {
        check(kernelTask.name == "kernel_task", "psProcesses: kernel_task keeps pid 0 and exact name (got \(kernelTask.name))")
    } else {
        check(false, "psProcesses: pid 0 (kernel_task) row present")
    }

    if let bash = rows.first(where: { $0.pid == 99999 }) {
        check(bash.name == "bash", "psProcesses: (bash) parenthesized name ⇒ \"bash\" (got \(bash.name))")
    } else {
        check(false, "psProcesses: pid 99999 (bash) row present")
    }

    if let chromeHelper = rows.first(where: { $0.pid == 4321 }) {
        check(chromeHelper.name == "Google Chrome Helper…",
              "psProcesses: \"Google Chrome Helper\" (spaces preserved) gets ellipsis (got \(chromeHelper.name))")
    } else {
        check(false, "psProcesses: pid 4321 (Google Chrome Helper) row present")
    }

    check(Parsers.psProcesses("").isEmpty, "psProcesses: empty string ⇒ []")
    check(Parsers.psProcesses("garbage\nnot ps output").isEmpty, "psProcesses: garbage lines ⇒ []")

    // MARK: - ProcessSampler.cpuPercent

    check(ProcessSampler.cpuPercent(previousSeconds: nil, currentSeconds: 6, elapsed: 6) == nil,
          "cpuPercent: nil baseline ⇒ nil")
    check(ProcessSampler.cpuPercent(previousSeconds: 0, currentSeconds: 6, elapsed: 6) == 100,
          "cpuPercent: (prev 0, cur 6, elapsed 6) ⇒ 100 (one full core)")
    check(approxEqual(ProcessSampler.cpuPercent(previousSeconds: 1.0, currentSeconds: 1.3, elapsed: 6), 5.0, tolerance: 1e-9),
          "cpuPercent: (prev 1.0, cur 1.3, elapsed 6) ≈ 5.0")
    check(ProcessSampler.cpuPercent(previousSeconds: 5, currentSeconds: 1, elapsed: 6) == nil,
          "cpuPercent: (prev 5, cur 1, elapsed 6) ⇒ nil (counter went backwards, pid reuse)")
    check(ProcessSampler.cpuPercent(previousSeconds: 0, currentSeconds: 1, elapsed: 0) == nil,
          "cpuPercent: elapsed 0 ⇒ nil")
    check(ProcessSampler.cpuPercent(previousSeconds: 0, currentSeconds: 1, elapsed: 0.01) == nil,
          "cpuPercent: elapsed 0.01 ⇒ nil (degenerate window)")
    check(ProcessSampler.cpuPercent(previousSeconds: 0, currentSeconds: 24, elapsed: 6) == 400,
          "cpuPercent: (prev 0, cur 24, elapsed 6) ⇒ 400 (4-thread process, not clamped)")

    // MARK: - Real-machine smoke (R6 coverage guard)

    let sampler = ProcessSampler()
    let first = sampler.sample()   // primes: two `ps` runs, 0.6 s apart
    // `ps` itself only takes ~10-20 ms, well under cpuPercent's 0.05 s degenerate-window
    // guard — without this gap, `second`'s elapsed since `first`'s post-priming snapshot
    // can land under the guard and every row reads back nil.
    Thread.sleep(forTimeInterval: 0.1)
    let second = sampler.sample()

    check(!first.isEmpty, "ProcessSampler smoke: first sample() non-empty")
    check(!second.isEmpty, "ProcessSampler smoke: second sample() non-empty")

    let myPid = getpid()
    check(second.contains { $0.cpu != nil }, "ProcessSampler smoke: at least one row has a cpu value")
    if let mine = second.first(where: { $0.pid == myPid }) {
        check((mine.cpu ?? -1) >= 0, "ProcessSampler smoke: own pid row has non-nil cpu >= 0 (got \(String(describing: mine.cpu)))")
    } else {
        check(false, "ProcessSampler smoke: own pid (\(myPid)) present in second sample")
    }
    check(second.allSatisfy { ($0.cpu ?? 0) < 10_000 }, "ProcessSampler smoke: no absurd cpu value (sanity, not a clamp)")

    // R6: this coverage guard is the whole reason this block reads `ps` instead of
    // libproc — WindowServer and kernel_task are EPERM to `proc_pidinfo` from an
    // unentitled binary but readable via `ps`.
    check(second.contains { $0.name.hasPrefix("WindowServer") },
          "ProcessSampler smoke: WindowServer present (R6 coverage guard)")
    // kernel_task (pid 0) was absent from `/bin/ps -axww` on the machine this block
    // was implemented on (Step 0 item 3) — per spec, that guard is omitted here.
}
