// Tests/MacDashboardTests/ProcessSamplerTests.swift
// Port of Checks/ProcessSamplerChecks.swift (CHECKS-SWIFT-TESTING).
// Block V2-PROC-NATIVE: pure-logic checks for the `ps`-based process sampler
// (time parsing, table parsing, CPU% delta math) plus a real-machine smoke test.
// Real file (not a symlink) — main.swift owns the single top-level-statements slot,
// so this exposes a plain function it calls (see README.md).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct ProcessSamplerTests {
        @Test func processSampler() async {
            // MARK: - Parsers.psCPUSeconds

            func approxEqual(_ a: Double?, _ b: Double, tolerance: Double = 1e-6) -> Bool {
                guard let a else { return false }
                return abs(a - b) < tolerance
            }

            #expect(approxEqual(Parsers.psCPUSeconds("0:00.05"), 0.05), "psCPUSeconds: \"0:00.05\" == 0.05")
            #expect(approxEqual(Parsers.psCPUSeconds("145:22.35"), 8722.35),
                  "psCPUSeconds: \"145:22.35\" == 8722.35 (minutes not rolled into hours)")
            #expect(approxEqual(Parsers.psCPUSeconds("1:02:03"), 3723), "psCPUSeconds: \"1:02:03\" == 3723")
            #expect(approxEqual(Parsers.psCPUSeconds("2-03:04:05"), 183845), "psCPUSeconds: \"2-03:04:05\" == 183845")
            #expect(Parsers.psCPUSeconds("") == nil, "psCPUSeconds: empty ⇒ nil")
            #expect(Parsers.psCPUSeconds("-") == nil, "psCPUSeconds: \"-\" ⇒ nil")
            #expect(Parsers.psCPUSeconds("abc") == nil, "psCPUSeconds: \"abc\" ⇒ nil")
            #expect(Parsers.psCPUSeconds("1:2:3:4:5") == nil, "psCPUSeconds: \"1:2:3:4:5\" (too many components) ⇒ nil")

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
            #expect(rows.count == 5, "psProcesses: 5 rows survive (bad pid + nope time skipped), got \(rows.count)")

            if let windowServer = rows.first(where: { $0.pid == 602 }) {
                #expect(approxEqual(windowServer.cpuSeconds, 8722.35), "psProcesses: WindowServer cpuSeconds == 8722.35")
                #expect(windowServer.memBytes == 401584 * 1024, "psProcesses: WindowServer memBytes == 401584 KiB in bytes")
                #expect(windowServer.name == "WindowServer", "psProcesses: WindowServer name has path stripped, no ellipsis (got \(windowServer.name))")
            } else {
                Issue.record( "psProcesses: pid 602 (WindowServer) row present")
            }

            if let kernelTask = rows.first(where: { $0.pid == 0 }) {
                #expect(kernelTask.name == "kernel_task", "psProcesses: kernel_task keeps pid 0 and exact name (got \(kernelTask.name))")
            } else {
                Issue.record( "psProcesses: pid 0 (kernel_task) row present")
            }

            if let bash = rows.first(where: { $0.pid == 99999 }) {
                #expect(bash.name == "bash", "psProcesses: (bash) parenthesized name ⇒ \"bash\" (got \(bash.name))")
            } else {
                Issue.record( "psProcesses: pid 99999 (bash) row present")
            }

            if let chromeHelper = rows.first(where: { $0.pid == 4321 }) {
                #expect(chromeHelper.name == "Google Chrome Helper",
                      "psProcesses: \"Google Chrome Helper\" (spaces preserved, no ellipsis) (got \(chromeHelper.name))")
            } else {
                Issue.record( "psProcesses: pid 4321 (Google Chrome Helper) row present")
            }

            // MARK: - Parsers.appBundleName / ProcessSampler.rankApps (TIPS-MEMORY)

            if let chromeHelper = rows.first(where: { $0.pid == 4321 }) {
                #expect(chromeHelper.appName == "Google Chrome", "psProcesses: pid 4321 appName == \"Google Chrome\"")
            } else {
                Issue.record( "psProcesses: pid 4321 (Google Chrome Helper) row present")
            }
            if let windowServer = rows.first(where: { $0.pid == 602 }) {
                #expect(windowServer.appName == nil, "psProcesses: pid 602 (WindowServer) appName == nil")
            } else {
                Issue.record( "psProcesses: pid 602 (WindowServer) row present")
            }
            if let bash = rows.first(where: { $0.pid == 99999 }) {
                #expect(bash.appName == nil, "psProcesses: pid 99999 (bash) appName == nil")
            } else {
                Issue.record( "psProcesses: pid 99999 (bash) row present")
            }

            #expect(Parsers.appBundleName(fromCommandPath: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)") == "Google Chrome",
                  "appBundleName: outermost .app bundle wins, deep Chrome helper path")
            #expect(Parsers.appBundleName(fromCommandPath: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder") == nil,
                  "appBundleName: /System/Library/ path excluded (Finder)")
            #expect(Parsers.appBundleName(fromCommandPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari") == "Safari",
                  "appBundleName: Safari cryptex path resolves to \"Safari\"")
            #expect(Parsers.appBundleName(fromCommandPath: "/usr/libexec/foo") == nil,
                  "appBundleName: no .app component ⇒ nil")

            #expect(ProcessSampler.rankApps([("B", 1), ("A", 5), ("B", 6), ("C", 1)], limit: 2) ==
                  [AppMemory(name: "B", bytes: 7), AppMemory(name: "A", bytes: 5)],
                  "rankApps: sums per app, largest first, tie ordered by name")
            #expect(ProcessSampler.rankApps([("B", 1), ("A", 5), ("B", 6), ("C", 1)], limit: 10).count == 3,
                  "rankApps: limit larger than group count returns all groups")

            // [M1] regression guard: a basename far over the old 16-char threshold must come
            // through whole. `ps -o comm=` does not truncate, so nothing may mark it as if it did.
            let longNameRows = Parsers.psProcesses("  777      2048   0:00.10 /usr/libexec/AppleCredentialManagerDaemon")
            #expect(longNameRows.first?.name == "AppleCredentialManagerDaemon",
                  "psProcesses: 28-char basename survives whole, no trailing ellipsis (got \(longNameRows.first?.name ?? "nil"))")

            #expect(Parsers.psProcesses("").isEmpty, "psProcesses: empty string ⇒ []")
            #expect(Parsers.psProcesses("garbage\nnot ps output").isEmpty, "psProcesses: garbage lines ⇒ []")

            // MARK: - Parsers.topMemoryFootprints (re-review 2 [M1])

            let topFixture = """
            Processes: 669 total, 3 running, 666 sleeping, 3410 threads
            2026/08/27 12:00:00
            Load Avg: 1.50, 1.60, 1.70
            CPU usage: 4.11% user, 6.16% sys, 89.71% idle
            PhysMem: 15G used (2G wired), 500M unused.
            Disks: 123456/4G read, 65432/2G written.

            PID    COMMAND          MEM
            602    WindowServer     520M
            1      launchd          12M-
            4321   Google Chrome He 1024M+
            777    tiny             3808K
            888    huge             2G
            999    broken           -
            bad    nope             5M
            """

            let fp = Parsers.topMemoryFootprints(topFixture)
            let ok602 = fp[602] == 520 * 1024 * 1024   // hoisted: #expect mis-evaluates Int64? == literal product (P6)
            #expect(ok602, "topMemoryFootprints: \"520M\" ⇒ 520 MiB")
            let ok1 = fp[1] == 12 * 1024 * 1024   // hoisted: #expect mis-evaluates Int64? == literal product (P6)
            #expect(ok1, "topMemoryFootprints: trailing \"-\" delta marker ignored")
            let ok4321 = fp[4321] == 1024 * 1024 * 1024   // hoisted: #expect mis-evaluates Int64? == literal product (P6)
            #expect(ok4321,
                  "topMemoryFootprints: COMMAND containing spaces + trailing \"+\" still parses")
            let ok777 = fp[777] == 3808 * 1024   // hoisted: #expect mis-evaluates Int64? == literal product (P6)
            #expect(ok777, "topMemoryFootprints: K suffix")
            let ok888 = fp[888] == 2 * 1024 * 1024 * 1024   // hoisted: #expect mis-evaluates Int64? == literal product (P6)
            #expect(ok888, "topMemoryFootprints: G suffix")
            #expect(fp[999] == nil, "topMemoryFootprints: unparsable MEM ⇒ pid absent (row keeps ps RSS)")
            #expect(fp.count == 5,
                  "topMemoryFootprints: banner, column header and a non-numeric pid are all skipped (got \(fp.count))")

            // MARK: - ProcessSampler.cpuPercent

            #expect(ProcessSampler.cpuPercent(previousSeconds: nil, currentSeconds: 6, elapsed: 6) == nil,
                  "cpuPercent: nil baseline ⇒ nil")
            #expect(ProcessSampler.cpuPercent(previousSeconds: 0, currentSeconds: 6, elapsed: 6) == 100,
                  "cpuPercent: (prev 0, cur 6, elapsed 6) ⇒ 100 (one full core)")
            #expect(approxEqual(ProcessSampler.cpuPercent(previousSeconds: 1.0, currentSeconds: 1.3, elapsed: 6), 5.0, tolerance: 1e-9),
                  "cpuPercent: (prev 1.0, cur 1.3, elapsed 6) ≈ 5.0")
            #expect(ProcessSampler.cpuPercent(previousSeconds: 5, currentSeconds: 1, elapsed: 6) == nil,
                  "cpuPercent: (prev 5, cur 1, elapsed 6) ⇒ nil (counter went backwards, pid reuse)")
            #expect(ProcessSampler.cpuPercent(previousSeconds: 0, currentSeconds: 1, elapsed: 0) == nil,
                  "cpuPercent: elapsed 0 ⇒ nil")
            #expect(ProcessSampler.cpuPercent(previousSeconds: 0, currentSeconds: 1, elapsed: 0.01) == nil,
                  "cpuPercent: elapsed 0.01 ⇒ nil (degenerate window)")
            #expect(ProcessSampler.cpuPercent(previousSeconds: 0, currentSeconds: 24, elapsed: 6) == 400,
                  "cpuPercent: (prev 0, cur 24, elapsed 6) ⇒ 400 (4-thread process, not clamped)")

            // MARK: - Real-machine smoke (R6 coverage guard)

            let sampler = ProcessSampler()
            let first = await sampler.sample()   // primes: two `ps` runs, 0.6 s apart
            // `ps` itself only takes ~10-20 ms, well under cpuPercent's 0.05 s degenerate-window
            // guard — without this gap, `second`'s elapsed since `first`'s post-priming snapshot
            // can land under the guard and every row reads back nil. Runs on the check thread,
            // not in the runner.
            Thread.sleep(forTimeInterval: 0.1)
            let second = await sampler.sample()

            #expect(!first.isEmpty, "ProcessSampler smoke: first sample() non-empty")
            #expect(!second.isEmpty, "ProcessSampler smoke: second sample() non-empty")

            let myPid = getpid()
            #expect(second.contains { $0.cpu != nil }, "ProcessSampler smoke: at least one row has a cpu value")
            if let mine = second.first(where: { $0.pid == myPid }) {
                #expect((mine.cpu ?? -1) >= 0, "ProcessSampler smoke: own pid row has non-nil cpu >= 0 (got \(String(describing: mine.cpu)))")
            } else {
                Issue.record( "ProcessSampler smoke: own pid (\(myPid)) present in second sample")
            }
            #expect(second.allSatisfy { ($0.cpu ?? 0) < 10_000 }, "ProcessSampler smoke: no absurd cpu value (sanity, not a clamp)")

            // R6: this coverage guard is the whole reason this block reads `ps` instead of
            // libproc — WindowServer and kernel_task are EPERM to `proc_pidinfo` from an
            // unentitled binary but readable via `ps`.
            #expect(second.contains { $0.name.hasPrefix("WindowServer") },
                  "ProcessSampler smoke: WindowServer present (R6 coverage guard)")

            // [M1] one top snapshot must cover EVERY process, not just our own uid: the
            // proc_pid_rusage path this replaced refused 285 of 384 pids (WindowServer among them),
            // leaving two different metrics in one column and in one ranking.
            let footprints = await ProcessSampler.memoryFootprints()
            #expect(footprints.count > 50,
                  "memoryFootprints: one top snapshot yields the whole process table (got \(footprints.count))")
            #expect((footprints[myPid] ?? 0) > 1_000_000,
                  "memoryFootprints: own pid ⇒ plausible footprint > 1 MB (got \(String(describing: footprints[myPid])))")
            #expect(footprints[999_999] == nil,
                  "memoryFootprints: impossible pid ⇒ absent (no bogus value)")
            #expect(footprints.values.allSatisfy { $0 > 0 },
                  "memoryFootprints: every reported footprint is positive")
            if let wsPid = second.first(where: { $0.name.hasPrefix("WindowServer") })?.pid {
                #expect((footprints[wsPid] ?? 0) > 1_000_000,
                      "memoryFootprints: WindowServer (foreign uid) has a footprint — the cross-uid gap [M1] is closed (got \(String(describing: footprints[wsPid])))")
            } else {
                Issue.record( "memoryFootprints: WindowServer pid available from the ps snapshot")
            }
            #expect(second.first(where: { $0.pid == myPid })?.memBytes ?? 0 > 1_000_000,
                  "ProcessSampler smoke: own row carries a memBytes value after the footprint substitution")

            // kernel_task (pid 0) was absent from `/bin/ps -axww` on the machine this block
            // was implemented on (Step 0 item 3) — per spec, that guard is omitted here.
        }
    }
}
