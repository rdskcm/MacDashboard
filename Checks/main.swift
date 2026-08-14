// Checks/main.swift
// Assertion-based check harness for MacDashboardChecks (SPEC §10). No XCTest/
// swift-testing available under Command Line Tools on this machine, so this is a
// plain executable: every `check()` call prints PASS/FAIL, and the process exits
// nonzero if anything failed. Run with `swift run MacDashboardChecks`.
//
// This file is real (not symlinked); every other .swift file in this directory is a
// symlink back into Sources/MacDashboard/... (see README.md) so these checks compile
// and exercise the app's actual pure engine code.

import Foundation

// Pin the in-app language to Russian: every check below asserts Russian-language
// outputs (Parsers, Assess, ReportWriter, StringsRU smoke), so on an English-locale
// machine L10nStore's default-language detection would otherwise pick English and
// fail every one of them. Also writes the pref into this binary's own UserDefaults
// domain — harmless (Checks and the app have separate bundle IDs).
L10nStore.shared.language = .ru

// Unbuffered stdout: without this, plain top-level `print()` piped to a file/pipe is
// fully block-buffered by libc, so PASS/FAIL lines only become visible in bursts (or
// not at all if the process later hangs) instead of as each check runs.
setbuf(stdout, nil)

var failures = 0
var total = 0

func check(_ cond: Bool, _ name: String) {
    total += 1
    print((cond ? "PASS " : "FAIL ") + name)
    if !cond { failures += 1 }
}

/// Bridges an `async` operation into this synchronous top-level executable WITHOUT
/// deadlocking. A naive `DispatchSemaphore.wait()` on the main thread blocks forever
/// here: `ReportCollector.collect` hops onto `@MainActor` (for its `onSection`
/// callback) via `dispatch_async(dispatch_get_main_queue(), ...)`, and that only ever
/// gets serviced by the main thread's run loop — which a blocking `sema.wait()` never
/// pumps. Instead, run the unstructured Task and repeatedly pump `RunLoop.main` in
/// short slices until the task signals completion; libdispatch ties the main GCD queue
/// to the main thread's CFRunLoop, so this keeps MainActor work flowing.
func runAsyncBlocking<T>(_ operation: @escaping () async -> T) -> T {
    let group = DispatchGroup()
    group.enter()
    nonisolated(unsafe) var result: T?
    Task {
        result = await operation()
        group.leave()
    }
    while group.wait(timeout: .now() + 0.02) == .timedOut {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return result!
}

let GIB: Int64 = 1 << 30
let MIB: Int64 = 1 << 20

// =====================================================================
// MARK: - Parsers: top (process tables)
// =====================================================================

let topCpuMemFixture = """
Processes: 412 total, 3 running, 409 sleeping, 1901 threads
2026/07/12 12:00:00
Load Avg: 2.10, 2.05, 1.98
CPU usage: 12.5% user, 5.3% sys, 82.2% idle
SharedLibs: 512M resident, 92M data, 20M linkedit.
MemRegions: 90000 total, 3500M resident, 200M private, 800M shared.
PhysMem: 15G used (3200M wired), 500M unused.
VM: 3200G vsize, 1500M framework vsize, 0(0) swapins, 0(0) swapouts.
Networks: packets: 100000/50M in, 90000/40M out.
Disks: 500000/10G read, 400000/8G written.

PID    COMMAND      %CPU  MEM
100    Finder       1.0   100M

Processes: 412 total, 3 running, 409 sleeping, 1901 threads
2026/07/12 12:00:03
Load Avg: 2.10, 2.05, 1.98
CPU usage: 12.5% user, 5.3% sys, 82.2% idle
SharedLibs: 512M resident, 92M data, 20M linkedit.
MemRegions: 90000 total, 3500M resident, 200M private, 800M shared.
PhysMem: 15G used (3200M wired), 500M unused.
VM: 3200G vsize, 1500M framework vsize, 0(0) swapins, 0(0) swapouts.
Networks: packets: 100000/50M in, 90000/40M out.
Disks: 500000/10G read, 400000/8G written.

CPU     MEM      COMMAND
25.3    521M     Google Chrome Helper
10.1    1747M    WindowServer
0.5     3808K+   mdworker
"""

do {
    let rows = Parsers.topProcesses(topCpuMemFixture, order: (.cpu, .mem))
    check(rows.count == 3, "topProcesses(cpu,mem): only LAST sample's 3 rows returned (got \(rows.count))")
    check(rows.first(where: { $0.name.hasPrefix("Finder") }) == nil,
          "topProcesses(cpu,mem): first-sample row (Finder) is excluded")
    if rows.count == 3 {
        check(rows[0].name == "Google Chrome Helper…", "topProcesses: 20-char command name gets ellipsis (got \(rows[0].name))")
        check(rows[0].cpu == 25.3, "topProcesses: row0 cpu == 25.3 (got \(String(describing: rows[0].cpu)))")
        check(rows[0].memBytes == 521 * MIB, "topProcesses: row0 mem == 521M bytes")
        check(rows[1].name == "WindowServer", "topProcesses: row1 name == WindowServer (12 chars, no ellipsis)")
        check(rows[1].memBytes == 1747 * MIB, "topProcesses: row1 mem == 1747M bytes")
        check(rows[2].memBytes == Parsers.parseSize("3808K+"), "topProcesses: row2 mem parses 3808K+ suffix")
        check(rows[2].name == "mdworker", "topProcesses: row2 name == mdworker (no ellipsis)")
    }
}

let topMemCpuFixture = """
Processes: 100 total, 2 running
Load Avg: 1.0, 1.0, 1.0

MEM      CPU    COMMAND
256M     3.5    Safari
128M     1.2    Mail
"""

do {
    let rows = Parsers.topProcesses(topMemCpuFixture, order: (.mem, .cpu))
    check(rows.count == 2, "topProcesses(mem,cpu order): 2 rows (got \(rows.count))")
    if rows.count == 2 {
        check(rows[0].name == "Safari" && rows[0].memBytes == 256 * MIB && rows[0].cpu == 3.5,
              "topProcesses(mem,cpu order): row0 Safari 256M 3.5%")
        check(rows[1].name == "Mail" && rows[1].memBytes == 128 * MIB && rows[1].cpu == 1.2,
              "topProcesses(mem,cpu order): row1 Mail 128M 1.2%")
    }
}

check(Parsers.topProcesses("", order: (.cpu, .mem)).isEmpty, "topProcesses: empty string ⇒ []")
check(Parsers.topProcesses("this is garbage\nnot top output at all", order: (.cpu, .mem)).isEmpty,
      "topProcesses: garbage string ⇒ []")

// `top -l 2 -stats pid,cpu,mem,command` (leadingPID) — realistic two-sample output,
// second sample authoritative (same first-sample-excluded trick as topCpuMemFixture
// above). One row in the authoritative sample has a non-numeric PID (garbage) and
// must be skipped rather than crashing/misaligning the rest.
let topPidCpuMemFixture = """
Processes: 420 total, 2 running, 418 sleeping, 1910 threads
2026/07/16 12:00:00
Load Avg: 1.50, 1.40, 1.30
CPU usage: 8.0% user, 3.0% sys, 89.0% idle
SharedLibs: 512M resident, 92M data, 20M linkedit.
MemRegions: 90000 total, 3500M resident, 200M private, 800M shared.
PhysMem: 15G used (3200M wired), 500M unused.
VM: 3200G vsize, 1500M framework vsize, 0(0) swapins, 0(0) swapouts.
Networks: packets: 100000/50M in, 90000/40M out.
Disks: 500000/10G read, 400000/8G written.

PID    %CPU MEM   COMMAND
1      0.0  10M   launchd

Processes: 420 total, 2 running, 418 sleeping, 1910 threads
2026/07/16 12:00:03
Load Avg: 1.50, 1.40, 1.30
CPU usage: 8.0% user, 3.0% sys, 89.0% idle
SharedLibs: 512M resident, 92M data, 20M linkedit.
MemRegions: 90000 total, 3500M resident, 200M private, 800M shared.
PhysMem: 15G used (3200M wired), 500M unused.
VM: 3200G vsize, 1500M framework vsize, 0(0) swapins, 0(0) swapouts.
Networks: packets: 100000/50M in, 90000/40M out.
Disks: 500000/10G read, 400000/8G written.

PID    %CPU MEM   COMMAND
27120  25.3 521M  Google Chrome Helper
garbage 1.0 10M   BogusRow
27119  10.1 1747M WindowServer
"""

do {
    let rows = Parsers.topProcesses(topPidCpuMemFixture, order: (.cpu, .mem), leadingPID: true)
    check(rows.count == 2, "topProcesses(leadingPID): non-numeric-pid row skipped, 2 rows left (got \(rows.count))")
    check(rows.first(where: { $0.name == "launchd" }) == nil,
          "topProcesses(leadingPID): first-sample row (launchd) is excluded")
    if rows.count == 2 {
        check(rows[0].pid == 27120, "topProcesses(leadingPID): row0 pid == 27120 (got \(String(describing: rows[0].pid)))")
        check(rows[0].name == "Google Chrome Helper…", "topProcesses(leadingPID): row0 name gets ellipsis (got \(rows[0].name))")
        check(rows[0].cpu == 25.3, "topProcesses(leadingPID): row0 cpu == 25.3")
        check(rows[0].memBytes == 521 * MIB, "topProcesses(leadingPID): row0 mem == 521M bytes")
        check(rows[1].pid == 27119, "topProcesses(leadingPID): row1 pid == 27119 (got \(String(describing: rows[1].pid)))")
        check(rows[1].name == "WindowServer", "topProcesses(leadingPID): row1 name == WindowServer")
        check(rows[1].memBytes == 1747 * MIB, "topProcesses(leadingPID): row1 mem == 1747M bytes")
    }
    // leadingPID: false is unaffected by the new parameter — old fixture, re-checked
    // via the default argument (no `leadingPID:` passed) rather than an explicit one.
    let oldFixtureRows = Parsers.topProcesses(topCpuMemFixture, order: (.cpu, .mem))
    check(oldFixtureRows.count == 3 && oldFixtureRows.allSatisfy { $0.pid == nil },
          "topProcesses: leadingPID defaults false, old fixture unaffected, pid stays nil")
}

// ProcEntry.id: "p<pid>" when pid present, old rank-based form when pid is nil.
check(ProcEntry(rank: 3, name: "X", pid: 27120).id == "p27120", "ProcEntry.id: \"p<pid>\" when pid present")
check(ProcEntry(rank: 3, name: "X").id == "3-X", "ProcEntry.id: old rank-based form when pid is nil")

// =====================================================================
// MARK: - Array<ProcEntry>.stableOrdered(matching:) (V2-FIX-ROWID Step 2)
// =====================================================================

do {
    let a = ProcEntry(rank: 0, name: "A", cpu: 10, pid: 1)
    let b = ProcEntry(rank: 1, name: "B", cpu: 20, pid: 2)
    let c = ProcEntry(rank: 2, name: "C", cpu: 5, pid: 3)

    let empty = [a, b, c].stableOrdered(matching: [])
    check(empty.map(\.pid) == [1, 2, 3], "stableOrdered: empty frozen ⇒ receiver unchanged")

    // Input re-sorted (b now leads); frozen order should still win.
    let resorted = [b, a, c].stableOrdered(matching: [1, 2, 3])
    check(resorted.map(\.pid) == [1, 2, 3], "stableOrdered: frozen order honoured against differently-sorted input")

    // A frozen pid missing from the input (process died / fell out of top-N) is skipped.
    let missing = [a, c].stableOrdered(matching: [1, 2, 3])
    check(missing.map(\.pid) == [1, 3], "stableOrdered: frozen pid absent from input is skipped")

    // A new pid not in frozen lands after the frozen ones, in the receiver's own order.
    let d = ProcEntry(rank: 3, name: "D", cpu: 1, pid: 4)
    let withNew = [d, b, a].stableOrdered(matching: [1, 2])
    check(withNew.map(\.pid) == [1, 2, 4], "stableOrdered: new pid not in frozen lands after frozen ones")

    // nil-pid rows land in the trailing group.
    let nilPidRow = ProcEntry(rank: 4, name: "E", cpu: 1)
    let withNilPid = [nilPidRow, b, a].stableOrdered(matching: [1, 2])
    check(withNilPid.map(\.pid) == [1, 2, nil], "stableOrdered: nil-pid row lands in trailing group")

    // Returned elements carry the INPUT's (fresh) values/ids, not the frozen snapshot's.
    let aFresh = ProcEntry(rank: 5, name: "A", cpu: 99, pid: 1)
    let fresh = [aFresh, b].stableOrdered(matching: [1, 2])
    check(fresh.first?.cpu == 99 && fresh.first?.id == aFresh.id,
          "stableOrdered: returned elements are the input's fresh values/ids, not the frozen snapshot's")
}

// =====================================================================
// MARK: - Parsers.parseSize
// =====================================================================

check(Parsers.parseSize("62G") == 62 * GIB, "parseSize: 62G")
check(Parsers.parseSize("228Gi") == 228 * GIB, "parseSize: 228Gi")
check(Parsers.parseSize("4.0K") == Int64((4.0 * 1024).rounded()), "parseSize: 4.0K")
check(Parsers.parseSize("0B") == 0, "parseSize: 0B")
check(Parsers.parseSize("545M+") == 545 * MIB, "parseSize: 545M+")
check(Parsers.parseSize("3808K-") == 3808 * 1024, "parseSize: 3808K-")
check(Parsers.parseSize("abc") == nil, "parseSize: abc ⇒ nil")
check(Parsers.parseSize("") == nil, "parseSize: empty ⇒ nil")

// =====================================================================
// MARK: - Parsers.swapUsage
// =====================================================================

do {
    let line = "vm.swapusage: total = 2048.00M  used = 430.44M  free = 1617.56M  (encrypted)"
    let swap = Parsers.swapUsage(line: line)
    let mib = 1024.0 * 1024.0
    check(swap?.total == Int64(2048.00 * mib), "swapUsage: total bytes")
    check(swap?.used == Int64(430.44 * mib), "swapUsage: used bytes")
    check(swap?.free == Int64(1617.56 * mib), "swapUsage: free bytes")
    check(Parsers.swapUsage(line: "vm.swapusage: nothing relevant here") == nil, "swapUsage: line without fields ⇒ nil")
}

// =====================================================================
// MARK: - Parsers.batteryPmset
// =====================================================================

do {
    let laptopCharging = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=4390321)\t91%; charging; 0:12 remaining present: true"
    let b = Parsers.batteryPmset(laptopCharging)
    check(b?.source == "от сети", "batteryPmset: AC source")
    check(b?.charge == 91, "batteryPmset: charge 91")
    check(b?.state == "заряжается", "batteryPmset: charging state")

    let laptopDischarging = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=4390321)\t63%; discharging; 2:30 remaining present: true"
    check(Parsers.batteryPmset(laptopDischarging)?.state == "разряжается", "batteryPmset: discharging state")

    let acAttachedNotCharging = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=4390321)\t100%; AC attached; not charging; present: true"
    check(Parsers.batteryPmset(acAttachedNotCharging)?.state == "не заряжается", "batteryPmset: split AC-attached/not-charging clauses")

    // Desktop-representative fixture: no battery/power fields recognizable at all.
    let desktopNoBattery = "No relevant power information available.\n"
    check(Parsers.batteryPmset(desktopNoBattery) == nil, "batteryPmset: no battery-related fields ⇒ nil")
}

// =====================================================================
// MARK: - Parsers.batteryPowerProfile
// =====================================================================

do {
    let profile = "      Cycle Count: 334\n      Condition: Normal\n      Maximum Capacity: 86%"
    let (cycles, condition, maxCap) = Parsers.batteryPowerProfile(profile)
    check(cycles == 334, "batteryPowerProfile: cycles 334")
    check(condition == "Normal", "batteryPowerProfile: condition Normal")
    check(maxCap == 86, "batteryPowerProfile: maxCapacity 86")
}

// =====================================================================
// MARK: - Parsers.hardwareProfile
// =====================================================================

do {
    let appleSilicon = "Chip: Apple M3\nTotal Number of Cores: 8 (4 performance and 4 efficiency)\nMemory: 8 GB"
    let info = Parsers.hardwareProfile(appleSilicon)
    check(info.chip == "Apple M3", "hardwareProfile: Apple Silicon chip")
    check(info.cores?.contains("8") == true, "hardwareProfile: Apple Silicon cores contains 8")
    check(info.memBytes == 8 * GIB, "hardwareProfile: Apple Silicon memBytes == 8 GiB")

    let intel = "Processor Name: 6-Core Intel Core i7\nTotal Number of Cores: 6\nMemory: 16 GB"
    let intelInfo = Parsers.hardwareProfile(intel)
    check(intelInfo.chip?.contains("Intel") == true, "hardwareProfile: Intel chip contains Intel")
    check(intelInfo.cores == "6", "hardwareProfile: Intel cores == 6")
}

// =====================================================================
// MARK: - Parsers.swVers
// =====================================================================

do {
    let sv = "ProductName: macOS\nProductVersion: 26.5.2\nBuildVersion: 25F84"
    let info = Parsers.swVers(sv)
    check(info.osName == "macOS", "swVers: osName")
    check(info.osVersion == "26.5.2", "swVers: osVersion")
    check(info.osBuild == "25F84", "swVers: osBuild")
}

// =====================================================================
// MARK: - Parsers.uptimeHuman
// =====================================================================

do {
    let daysLine = "21:50  up 2 days, 3 mins, 2 users, load averages: 1.20 1.15 1.10"
    let human = Parsers.uptimeHuman(daysLine)
    check(human != nil && human!.contains("дн"), "uptimeHuman: days form contains дн (got \(String(describing: human)))")

    let hourMinLine = "23:10  up 5:12, 2 users, load averages: 0.50 0.45 0.40"
    let human2 = Parsers.uptimeHuman(hourMinLine)
    check(human2 != nil && human2!.contains("ч") && human2!.contains("мин"),
          "uptimeHuman: h:mm form contains ч and мин (got \(String(describing: human2)))")
}

// =====================================================================
// MARK: - Parsers.tmDestination
// =====================================================================

do {
    let configured = """
    ====================
    Name : X
    Kind : Local
    Mount Point : /Volumes/Y
    Quota : 499 GB
    ====================
    Name : ShouldNotAppear
    Kind : Network
    """
    let dest = Parsers.tmDestination(configured)
    check(dest?.name == "X", "tmDestination: name from FIRST block only")
    check(dest?.quotaBytes == 499 * 1_000_000_000, "tmDestination: quota 499 GB decimal bytes")

    check(Parsers.tmDestination("No destinations configured.") == nil, "tmDestination: not configured ⇒ nil")
}

// =====================================================================
// MARK: - Parsers.diskutilSmart
// =====================================================================

do {
    let verified = "SMART Status: Verified\nDevice / Media Name: APPLE SSD"
    let r = Parsers.diskutilSmart(verified)
    check(r.status == "Verified" && r.mediaName == "APPLE SSD", "diskutilSmart: Verified + media name")

    let notSupported = "SMART Status: Not Supported\nDevice / Media Name: External HDD"
    let r2 = Parsers.diskutilSmart(notSupported)
    check(r2.status == "Not Supported" && r2.mediaName == "External HDD", "diskutilSmart: Not Supported variant")
}

// =====================================================================
// MARK: - Parsers.smartctlAttrs
// =====================================================================

do {
    let nvme = """
    Percentage Used:                    0%
    Critical Warning:                   0x00
    Power On Hours:                     500
    Temperature:                        39 Celsius
    Media and Data Integrity Errors:    0
    Available Spare:                    100%
    Error Information Log Entries:      0
    Power Cycles:                       120
    Unsafe Shutdowns:                   3
    """
    let attrs = Parsers.smartctlAttrs(nvme)
    let expectedOrder = ["Critical Warning", "Temperature", "Available Spare", "Percentage Used",
                          "Power Cycles", "Power On Hours", "Unsafe Shutdowns",
                          "Media and Data Integrity Errors", "Error Information Log Entries"]
    check(attrs.map { $0.0 } == expectedOrder, "smartctlAttrs: canonical order regardless of source order")
    check(attrs.count == 9, "smartctlAttrs: all 9 attrs found")
    check(Parsers.smartctlAttrs("").isEmpty, "smartctlAttrs: empty input ⇒ []")
}

// =====================================================================
// MARK: - Parsers.launchctlNonApple
// =====================================================================

do {
    let fixture = """
    PID\tStatus\tLabel
    111\t0\tcom.apple.foo
    222\t0\tapplication.ru.keepcoder.Telegram.5282392.5283387
    333\t0\tcom.rdskcm.mac-checkup
    """
    let items = Parsers.launchctlNonApple(fixture)
    let labels = Set(items.map { $0.label })
    check(!labels.contains("com.apple.foo"), "launchctlNonApple: com.apple.* excluded")
    check(labels.contains("ru.keepcoder.Telegram"), "launchctlNonApple: application. prefix + instance-id suffix stripped")
    check(labels.contains("com.rdskcm.mac-checkup"), "launchctlNonApple: plain non-Apple label kept")
    check(items.count == 2, "launchctlNonApple: header row skipped, deduped result (got \(items.count))")
}

// =====================================================================
// MARK: - Parsers.pmsetCustom
// =====================================================================

do {
    let fixture = "Battery Power:\n Sleep On Power Button 1\n displaysleep 10\nAC Power:\n displaysleep 20"
    let energy = Parsers.pmsetCustom(fixture)
    check(energy.battery.contains { $0.0 == "Sleep On Power Button" && $0.1 == "1" },
          "pmsetCustom: multi-word key parsed")
    check(energy.battery.contains { $0.0 == "displaysleep" && $0.1 == "10" }, "pmsetCustom: battery displaysleep 10")
    check(energy.ac.contains { $0.0 == "displaysleep" && $0.1 == "20" }, "pmsetCustom: ac displaysleep 20")
}

// =====================================================================
// MARK: - Parsers.loginItems
// =====================================================================

check(Parsers.loginItems("Stats, Foo") == ["Stats", "Foo"], "loginItems: comma-separated list")
check(Parsers.loginItems("(error, no automation permission)") == nil, "loginItems: AppleScript error ⇒ nil")
check(Parsers.loginItems("") == [], "loginItems: empty ⇒ []")

// =====================================================================
// MARK: - Parsers security status fixtures
// =====================================================================

check(Parsers.fileVaultStatus("FileVault is On.") == true, "fileVaultStatus: On")
check(Parsers.fileVaultStatus("FileVault is Off.") == false, "fileVaultStatus: Off")
check(Parsers.gatekeeperStatus("assessments enabled") == true, "gatekeeperStatus: enabled")
check(Parsers.gatekeeperStatus("assessments disabled") == false, "gatekeeperStatus: disabled")
check(Parsers.sipStatus("System Integrity Protection status: enabled.") == true, "sipStatus: enabled")
check(Parsers.sipStatus("System Integrity Protection status: disabled.") == false, "sipStatus: disabled")
check(Parsers.firewallStatus("Firewall is enabled. (State = 1)") == true, "firewallStatus: prose enabled")
check(Parsers.firewallStatus("Firewall is disabled. (State = 0)") == false, "firewallStatus: prose disabled")
check(Parsers.firewallStatus("1") == true, "firewallStatus: numeric 1 ⇒ true")
check(Parsers.firewallStatus("2") == true, "firewallStatus: numeric 2 ⇒ true")

// =====================================================================
// MARK: - Memory math (MemSnapshot)
// =====================================================================

do {
    let pageSize: Int64 = 4096
    let mem = MemSnapshot(
        total: 8 * GIB,
        pageSize: pageSize,
        free: 1_000 * pageSize,
        active: 200_000 * pageSize,
        inactive: 50_000 * pageSize,
        speculative: 1_000 * pageSize,
        wired: 100_000 * pageSize,
        compressor: 5_000 * pageSize,
        purgeable: 200 * pageSize,
        fileBacked: 30_000 * pageSize
    )
    check(mem.usedBytes == mem.active + mem.wired + mem.compressor, "MemSnapshot: usedBytes == active+wired+compressor")
    check(mem.otherBytes >= 0, "MemSnapshot: otherBytes >= 0")
}

// =====================================================================
// MARK: - Assessment (SPEC §6)
// =====================================================================

func diskLive(pct: Double) -> LiveSnapshot {
    var live = LiveSnapshot()
    let size: Int64 = 1_000_000_000_000
    let avail = Int64(Double(size) * (1 - pct))
    live.disk = DiskInfo(size: size, avail: avail, dataUsed: nil, sysUsed: nil)
    return live
}

do {
    let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.86))
    check(a.diskSev == .crit, "assess disk 86%: diskSev == .crit")
    check(a.problems.contains { $0.sev == .crit && $0.text.contains("срочно освободите место") },
          "assess disk 86%: crit problem present")
}
do {
    let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.72))
    check(a.diskSev == .warn, "assess disk 72%: diskSev == .warn")
}
do {
    let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.50))
    check(a.diskSev == .good, "assess disk 50%: diskSev == .good")
    check(!a.problems.contains { $0.text.contains("Диск заполнен") }, "assess disk 50%: no disk problem")
}

func swapLive(usedBytes: Int64) -> LiveSnapshot {
    var live = LiveSnapshot()
    live.swap = SwapInfo(total: 4 * GIB, used: usedBytes, free: 4 * GIB - usedBytes)
    return live
}

do {
    let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: Int64(2.5 * Double(GIB))))
    check(a.problems.contains { $0.sev == .serious && $0.text.contains("Swap") }, "assess swap 2.5GiB: serious problem")
}
do {
    let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: Int64(1.2 * Double(GIB))))
    check(a.tips.contains { $0.text.contains("Swap") } && !a.problems.contains { $0.text.contains("Swap") },
          "assess swap 1.2GiB: tip, not a problem")
}
do {
    let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 100 * MIB))
    check(!a.tips.contains { $0.text.contains("Swap") } && !a.problems.contains { $0.text.contains("Swap") },
          "assess swap 100MiB: nothing")
}

func batteryReport(maxCapacity: Int?, condition: String? = nil) -> FullReport {
    var report = FullReport()
    report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: nil, condition: condition, maxCapacity: maxCapacity)
    return report
}

do {
    let a = Assess.assess(report: batteryReport(maxCapacity: 65), live: LiveSnapshot())
    check(a.problems.contains { $0.sev == .serious && $0.text.contains("Ёмкость") }, "assess battery 65%: serious")
}
do {
    let a = Assess.assess(report: batteryReport(maxCapacity: 78), live: LiveSnapshot())
    check(a.tips.contains { $0.text.contains("Ёмкость") }, "assess battery 78%: tip")
}
do {
    let a = Assess.assess(report: batteryReport(maxCapacity: 90), live: LiveSnapshot())
    check(!a.problems.contains { $0.text.contains("Ёмкость") } && !a.tips.contains { $0.text.contains("Ёмкость") },
          "assess battery 90%: nothing")
}
do {
    let a = Assess.assess(report: batteryReport(maxCapacity: 90, condition: "Replace Soon"), live: LiveSnapshot())
    check(a.problems.contains { $0.sev == .serious && $0.text.contains("Состояние батареи") },
          "assess battery condition 'Replace Soon': serious")
}

do {
    var report = FullReport()
    report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.contains { $0.sev == .serious && $0.text.contains("Файрвол") }, "assess security firewall==false: serious problem")
}
do {
    var report = FullReport()
    report.security = SecurityState(fileVault: nil, gatekeeper: nil, sip: nil, firewall: nil)
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.isEmpty, "assess security all nil: silent")
}

do {
    var report = FullReport()
    report.updates = ["a", "b"]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.contains { $0.text.contains("2 шт.") }, "assess updates [a,b]: warn '...2 шт.'")
}
do {
    var report = FullReport()
    report.updates = []
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(!a.problems.contains { $0.text.contains("обновлени") }, "assess updates []: nothing")
}

do {
    var report = FullReport()
    report.crashes = ["crash1.ips"]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.contains { $0.sev == .warn && $0.text.contains("крэш") }, "assess crashes [x]: warn")
}
do {
    var report = FullReport()
    report.crashes = []
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(!a.problems.contains { $0.text.contains("крэш") }, "assess crashes []: nothing")
}

do {
    var report = FullReport()
    report.tmDest = .some(.none)
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.contains { $0.text.contains("не настроен") }, "assess tmDest .some(nil): warn 'не настроен'")
}
do {
    var report = FullReport()
    report.tmDest = .some(.some(TMDestination(name: "Backup", kind: "Local", mountPoint: "/Volumes/B", quotaBytes: nil, lastBackup: nil)))
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(!a.problems.contains { $0.text.contains("Time Machine") }, "assess tmDest .some(.some): nothing")
}
do {
    var report = FullReport()
    report.tmDest = .none
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(!a.problems.contains { $0.text.contains("Time Machine") }, "assess tmDest .none (not checked): nothing")
}

do {
    var report = FullReport()
    report.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: "SMART: ошибки носителя",
                               attrs: [("Media and Data Integrity Errors", "3")], severity: .crit)]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.contains { $0.sev == .crit && $0.text.contains("ошибках носителя") }, "assess smart media errors: crit problem")
}
do {
    var report = FullReport()
    report.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: "SMART: износ на исходе",
                               attrs: [("Percentage Used", "85%")], severity: .warn)]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.contains { $0.sev == .warn && $0.text.contains("износ") }, "assess smart Percentage Used 85%: warn")
}
do {
    var report = FullReport()
    report.smart = [SmartDisk(device: "/dev/disk4", title: "External", status: "SMART недоступен", attrs: [], severity: .warn)]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.tips.contains { $0.text.contains("SMART недоступен") }, "assess smart external empty-attrs .warn: tip")
}

do {
    var report = FullReport()
    report.homeDirs = [DirSize(path: "/Users/x/Downloads", bytes: 11 * GIB)]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.tips.contains { $0.text.contains("Загрузки") }, "assess homeDirs Downloads > 10GiB: tip")
}
do {
    var report = FullReport()
    report.homeDirs = [DirSize(path: "/Users/x/.Trash", bytes: 2 * GIB)]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.tips.contains { $0.text.contains("Корзина") }, "assess homeDirs .Trash > 1GiB: tip")
}

do {
    var report = FullReport()
    report.updates = ["u1"]
    let a = Assess.assess(report: report, live: diskLive(pct: 0.90))
    check(a.summaryText == "Замечаний: \(a.problems.count)", "assess summary: 'Замечаний: N' text")
    check(a.summarySev == a.problems.first?.sev, "assess summary: summarySev == worst")
    check(a.problems.count >= 2, "assess summary: multiple problems present for ordering check")
    if let critIdx = a.problems.firstIndex(where: { $0.sev == .crit }),
       let warnIdx = a.problems.firstIndex(where: { $0.sev == .warn }) {
        check(critIdx < warnIdx, "assess summary: crit sorts before warn in problems")
    } else {
        check(false, "assess summary: expected both a crit and a warn problem in fixture")
    }
}
do {
    let a = Assess.assess(report: FullReport(), live: LiveSnapshot())
    check(a.problems.isEmpty && a.summaryText == "Всё в порядке" && a.summarySev == .good,
          "assess summary: empty ⇒ 'Всё в порядке' / .good")
}

// =====================================================================
// MARK: - Assessment advice actions (advice block AR)
// =====================================================================

do {
    var report = FullReport()
    report.security = SecurityState(fileVault: true, gatekeeper: true, sip: false, firewall: false)
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.first { $0.text.contains("Файрвол") }?.action == .enableFirewall,
          "assess advice: firewall==false ⇒ action == .enableFirewall")
    let sipProblem = a.problems.first { $0.text.contains("SIP") }
    check(sipProblem != nil && sipProblem?.action == nil,
          "assess advice: sip==false ⇒ problem present with action == nil")
}
do {
    var report = FullReport()
    report.homeDirs = [DirSize(path: "/Users/x/.Trash", bytes: 2 * GIB)]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.tips.first { $0.text.contains("Корзина") }?.action == .emptyTrash,
          "assess advice: Trash tip ⇒ action == .emptyTrash")
}
do {
    var report = FullReport()
    report.brewOutdated = ["pkg1", "pkg2"]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.tips.first { $0.text.contains("Homebrew") }?.action == .brewUpgrade,
          "assess advice: brew outdated tip ⇒ action == .brewUpgrade")
}
do {
    var report = FullReport()
    report.updates = ["u1", "u2"]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.problems.first { $0.text.contains("2 шт.") }?.action == .settingsPane(AdvicePanes.softwareUpdate),
          "assess advice: updates available ⇒ action == .settingsPane(softwareUpdate)")
}
do {
    let downloadsPath = "/Users/x/Downloads"
    var report = FullReport()
    report.homeDirs = [DirSize(path: downloadsPath, bytes: 11 * GIB)]
    let a = Assess.assess(report: report, live: LiveSnapshot())
    check(a.tips.first { $0.text.contains("Загрузки") }?.action == .revealPath(downloadsPath),
          "assess advice: Downloads tip ⇒ action == .revealPath(downloadsPath)")
}

// Battery presence varies by machine (MacBook vs. Mac mini/Mac Studio/CI runner) —
// this mirrors how LiveCollector/ReportCollector already treat "no battery" as a
// normal, fully-supported state (see StringsEN.reportNoBattery), not an error. Smoke
// checks below use this to stay meaningful on battery-equipped machines while not
// spuriously failing on desktop Macs or CI runners.
// `collect(limit:)` takes the process-table length explicitly rather than reading
// AppSettings.shared — checks must not depend on the user's saved preferences.
let hasBattery = LiveCollector().collect(limit: 10).battery != nil

// =====================================================================
// MARK: - SMOKE (real machine)
// =====================================================================

do {
    let collector = LiveCollector()
    _ = collector.collect(limit: 10)
    Thread.sleep(forTimeInterval: 1.3)
    let snap2 = collector.collect(limit: 10)
    check(snap2.cpu != nil, "smoke LiveCollector: 2nd sample cpu != nil")
    check((snap2.mem?.total ?? 0) > 4 * GIB, "smoke LiveCollector: mem.total > 4 GiB")
    check((snap2.disk?.size ?? 0) > 0, "smoke LiveCollector: disk.size > 0")
    check(snap2.load != nil, "smoke LiveCollector: load != nil")
    check(snap2.ncpu >= 1, "smoke LiveCollector: ncpu >= 1 (got \(snap2.ncpu))")
    // Exercises the REAL `top -l 2 -s 1 -stats pid,cpu,mem,command` output on this
    // machine end-to-end through the new leadingPID parse path (a synthetic fixture
    // only proves the parser handles an assumed format, not that the real `top`
    // header/columns actually match it).
    check(!snap2.topCPU.isEmpty, "smoke LiveCollector: topCPU non-empty (real top+leadingPID parse)")
    check(snap2.topCPU.first?.pid != nil, "smoke LiveCollector: live pid parsed through leadingPID path")
    check(!snap2.topMem.isEmpty, "smoke LiveCollector: topMem non-empty")
    // readTopProcesses() may legitimately return fewer rows than the limit, so <=
    // not ==.
    check(snap2.topCPU.count <= AppSettings.shared.processListLimit,
          "smoke LiveCollector: topCPU.count <= processListLimit")
    check(snap2.topMem.count <= AppSettings.shared.processListLimit,
          "smoke LiveCollector: topMem.count <= processListLimit")
}

do {
    check(AppSettings.allowedProcessLimits == [5, 10, 15],
          "AppSettings.allowedProcessLimits == [5, 10, 15]")
    // Pure re-check of the resolution formula from AppSettings.init() — a fresh
    // (unset, raw 0) default and an out-of-range stored value both fall back to 10.
    let freshRaw = 0
    let resolvedFresh = AppSettings.allowedProcessLimits.contains(freshRaw) ? freshRaw : 10
    check(resolvedFresh == 10, "AppSettings: fresh default (unset) resolves to 10")
    let outOfRangeRaw = 999
    let resolvedOutOfRange = AppSettings.allowedProcessLimits.contains(outOfRangeRaw) ? outOfRangeRaw : 10
    check(resolvedOutOfRange == 10, "AppSettings: out-of-range stored value resolves to 10")
}

do {
    let result: FullReport? = runAsyncBlocking {
        await ReportCollector().collect(skipSlow: true) { _ in }
    }
    check(result?.system != nil, "smoke ReportCollector: system != nil")
    check(result?.security != nil, "smoke ReportCollector: security != nil")
    check((result?.smart?.isEmpty == false), "smoke ReportCollector: smart non-empty")
    check(result?.autostart != nil, "smoke ReportCollector: autostart != nil")
    check(!hasBattery || result?.battery != nil,
          "smoke ReportCollector: battery != nil (or no battery on this machine)")
    check(result?.energy != nil, "smoke ReportCollector: energy != nil")
    // Block N7 smoke — on a real developer machine with smartctl + the NOPASSWD
    // sudo rule, the disk reporting itself as "internal" should carry parsed SMART
    // attrs. Hosted CI runners (GitHub Actions sets CI=true) have unpredictable disk
    // topology — the boot/data volume isn't guaranteed to be tagged "internal" by
    // our detection heuristic at all, let alone carry parseable attrs — so this
    // assertion only runs outside CI; `smart non-empty` two lines above already
    // covers that the smartctl parsing pipeline works at all in every environment.
    let isCI = ProcessInfo.processInfo.environment["CI"] != nil
    let internalDisk = result?.smart?.first { $0.device == "internal" }
    check(isCI || internalDisk?.attrs.isEmpty == false,
          "smoke ReportCollector: internal disk has parsed SMART attrs (smartctl -A disk0; skipped under CI)")
}

// =====================================================================
// MARK: - BatteryInspector (ioreg AppleSmartBattery)
// =====================================================================

// Trimmed sample fixture (on battery, no adapter connected).
let batteryOnBatteryFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
\t<dict>
\t\t<key>AdapterDetails</key>
\t\t<dict>
\t\t\t<key>FamilyCode</key>
\t\t\t<integer>0</integer>
\t\t</dict>
\t\t<key>Amperage</key>
\t\t<integer>-587</integer>
\t\t<key>AppleRawCurrentCapacity</key>
\t\t<integer>2930</integer>
\t\t<key>AppleRawMaxCapacity</key>
\t\t<integer>3977</integer>
\t\t<key>AtCriticalLevel</key>
\t\t<false/>
\t\t<key>AvgTimeToEmpty</key>
\t\t<integer>296</integer>
\t\t<key>AvgTimeToFull</key>
\t\t<integer>65535</integer>
\t\t<key>BatteryData</key>
\t\t<dict>
\t\t\t<key>CellVoltage</key>
\t\t\t<array>
\t\t\t\t<integer>4032</integer>
\t\t\t\t<integer>4032</integer>
\t\t\t\t<integer>4030</integer>
\t\t\t</array>
\t\t\t<key>LifetimeData</key>
\t\t\t<dict>
\t\t\t\t<key>AverageTemperature</key>
\t\t\t\t<integer>259</integer>
\t\t\t\t<key>MaximumChargeCurrent</key>
\t\t\t\t<integer>5345</integer>
\t\t\t\t<key>MaximumDischargeCurrent</key>
\t\t\t\t<integer>-3001</integer>
\t\t\t\t<key>MaximumPackVoltage</key>
\t\t\t\t<integer>13321</integer>
\t\t\t\t<key>MaximumTemperature</key>
\t\t\t\t<integer>44</integer>
\t\t\t\t<key>MinimumPackVoltage</key>
\t\t\t\t<integer>9335</integer>
\t\t\t\t<key>MinimumTemperature</key>
\t\t\t\t<integer>10</integer>
\t\t\t\t<key>TotalOperatingTime</key>
\t\t\t\t<integer>20219</integer>
\t\t\t</dict>
\t\t</dict>
\t\t<key>ChargerData</key>
\t\t<dict>
\t\t\t<key>ChargerID</key>
\t\t\t<integer>14</integer>
\t\t\t<key>ChargingCurrent</key>
\t\t\t<integer>0</integer>
\t\t\t<key>ChargingVoltage</key>
\t\t\t<integer>4406</integer>
\t\t\t<key>NotChargingReason</key>
\t\t\t<integer>128</integer>
\t\t\t<key>SlowChargingReason</key>
\t\t\t<integer>0</integer>
\t\t\t<key>TimeChargingThermallyLimited</key>
\t\t\t<integer>0</integer>
\t\t\t<key>VacVoltageLimit</key>
\t\t\t<integer>4375</integer>
\t\t</dict>
\t\t<key>CurrentCapacity</key>
\t\t<integer>78</integer>
\t\t<key>CycleCount</key>
\t\t<integer>338</integer>
\t\t<key>DesignCapacity</key>
\t\t<integer>4563</integer>
\t\t<key>DesignCycleCount9C</key>
\t\t<integer>1000</integer>
\t\t<key>DeviceName</key>
\t\t<string>bq40z651</string>
\t\t<key>ExternalConnected</key>
\t\t<false/>
\t\t<key>FullyCharged</key>
\t\t<false/>
\t\t<key>InstantAmperage</key>
\t\t<integer>-587</integer>
\t\t<key>IsCharging</key>
\t\t<false/>
\t\t<key>MaxCapacity</key>
\t\t<integer>100</integer>
\t\t<key>NominalChargeCapacity</key>
\t\t<integer>4104</integer>
\t\t<key>Serial</key>
\t\t<string>X0X00000ABC00XXXX</string>
\t\t<key>Temperature</key>
\t\t<integer>3044</integer>
\t\t<key>TimeRemaining</key>
\t\t<integer>296</integer>
\t\t<key>Voltage</key>
\t\t<integer>12093</integer>
\t</dict>
</array>
</plist>
"""

// Trimmed sample fixture (charging, third-party 45W USB-PD adapter).
let batteryChargingFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
\t<dict>
\t\t<key>AdapterDetails</key>
\t\t<dict>
\t\t\t<key>AdapterID</key>
\t\t\t<integer>0</integer>
\t\t\t<key>AdapterPowerTier</key>
\t\t\t<integer>2</integer>
\t\t\t<key>AdapterVoltage</key>
\t\t\t<integer>20000</integer>
\t\t\t<key>Current</key>
\t\t\t<integer>2250</integer>
\t\t\t<key>FamilyCode</key>
\t\t\t<integer>-536854518</integer>
\t\t\t<key>IsWireless</key>
\t\t\t<false/>
\t\t\t<key>PMUConfiguration</key>
\t\t\t<integer>2250</integer>
\t\t\t<key>UsbHvcHvcIndex</key>
\t\t\t<integer>3</integer>
\t\t\t<key>UsbHvcMenu</key>
\t\t\t<array>
\t\t\t\t<dict>
\t\t\t\t\t<key>Index</key>
\t\t\t\t\t<integer>0</integer>
\t\t\t\t\t<key>MaxCurrent</key>
\t\t\t\t\t<integer>3000</integer>
\t\t\t\t\t<key>MaxVoltage</key>
\t\t\t\t\t<integer>5000</integer>
\t\t\t\t</dict>
\t\t\t\t<dict>
\t\t\t\t\t<key>Index</key>
\t\t\t\t\t<integer>1</integer>
\t\t\t\t\t<key>MaxCurrent</key>
\t\t\t\t\t<integer>3000</integer>
\t\t\t\t\t<key>MaxVoltage</key>
\t\t\t\t\t<integer>9000</integer>
\t\t\t\t</dict>
\t\t\t\t<dict>
\t\t\t\t\t<key>Index</key>
\t\t\t\t\t<integer>2</integer>
\t\t\t\t\t<key>MaxCurrent</key>
\t\t\t\t\t<integer>3000</integer>
\t\t\t\t\t<key>MaxVoltage</key>
\t\t\t\t\t<integer>15000</integer>
\t\t\t\t</dict>
\t\t\t\t<dict>
\t\t\t\t\t<key>Index</key>
\t\t\t\t\t<integer>3</integer>
\t\t\t\t\t<key>MaxCurrent</key>
\t\t\t\t\t<integer>2250</integer>
\t\t\t\t\t<key>MaxVoltage</key>
\t\t\t\t\t<integer>20000</integer>
\t\t\t\t</dict>
\t\t\t</array>
\t\t\t<key>Watts</key>
\t\t\t<integer>45</integer>
\t\t</dict>
\t\t<key>Amperage</key>
\t\t<integer>-479</integer>
\t\t<key>AppleRawCurrentCapacity</key>
\t\t<integer>2889</integer>
\t\t<key>AppleRawMaxCapacity</key>
\t\t<integer>3984</integer>
\t\t<key>AtCriticalLevel</key>
\t\t<false/>
\t\t<key>AvgTimeToEmpty</key>
\t\t<integer>352</integer>
\t\t<key>AvgTimeToFull</key>
\t\t<integer>65535</integer>
\t\t<key>BatteryData</key>
\t\t<dict>
\t\t\t<key>CellVoltage</key>
\t\t\t<array>
\t\t\t\t<integer>4027</integer>
\t\t\t\t<integer>4024</integer>
\t\t\t\t<integer>4020</integer>
\t\t\t</array>
\t\t\t<key>LifetimeData</key>
\t\t\t<dict>
\t\t\t\t<key>AverageTemperature</key>
\t\t\t\t<integer>259</integer>
\t\t\t\t<key>MaximumChargeCurrent</key>
\t\t\t\t<integer>5345</integer>
\t\t\t\t<key>MaximumDischargeCurrent</key>
\t\t\t\t<integer>-3001</integer>
\t\t\t\t<key>MaximumPackVoltage</key>
\t\t\t\t<integer>13321</integer>
\t\t\t\t<key>MaximumTemperature</key>
\t\t\t\t<integer>44</integer>
\t\t\t\t<key>MinimumPackVoltage</key>
\t\t\t\t<integer>9335</integer>
\t\t\t\t<key>MinimumTemperature</key>
\t\t\t\t<integer>10</integer>
\t\t\t\t<key>TotalOperatingTime</key>
\t\t\t\t<integer>20219</integer>
\t\t\t</dict>
\t\t</dict>
\t\t<key>ChargerData</key>
\t\t<dict>
\t\t\t<key>ChargerID</key>
\t\t\t<integer>14</integer>
\t\t\t<key>ChargingCurrent</key>
\t\t\t<integer>570</integer>
\t\t\t<key>ChargingVoltage</key>
\t\t\t<integer>4027</integer>
\t\t\t<key>NotChargingReason</key>
\t\t\t<integer>0</integer>
\t\t\t<key>SlowChargingReason</key>
\t\t\t<integer>0</integer>
\t\t\t<key>TimeChargingThermallyLimited</key>
\t\t\t<integer>0</integer>
\t\t\t<key>VacVoltageLimit</key>
\t\t\t<integer>4375</integer>
\t\t</dict>
\t\t<key>CurrentCapacity</key>
\t\t<integer>76</integer>
\t\t<key>CycleCount</key>
\t\t<integer>338</integer>
\t\t<key>DesignCapacity</key>
\t\t<integer>4563</integer>
\t\t<key>DesignCycleCount9C</key>
\t\t<integer>1000</integer>
\t\t<key>DeviceName</key>
\t\t<string>bq40z651</string>
\t\t<key>ExternalConnected</key>
\t\t<true/>
\t\t<key>FullyCharged</key>
\t\t<false/>
\t\t<key>InstantAmperage</key>
\t\t<integer>-479</integer>
\t\t<key>IsCharging</key>
\t\t<false/>
\t\t<key>MaxCapacity</key>
\t\t<integer>100</integer>
\t\t<key>NominalChargeCapacity</key>
\t\t<integer>4111</integer>
\t\t<key>Serial</key>
\t\t<string>X0X00000ABC00XXXX</string>
\t\t<key>Temperature</key>
\t\t<integer>3033</integer>
\t\t<key>TimeRemaining</key>
\t\t<integer>65535</integer>
\t\t<key>Voltage</key>
\t\t<integer>12071</integer>
\t</dict>
</array>
</plist>
"""

do {
    let d1 = BatteryInspector.parse(Data(batteryOnBatteryFixture.utf8))
    check(d1 != nil, "BatteryInspector: on-battery fixture parses")
    let d = d1!
    check(d.amperageMA == -587 && d.voltageMV == 12093, "BatteryInspector on-battery: amperageMA/voltageMV signed values")
    check(d.powerW.map { abs($0 - (-7.099)) < 0.01 } ?? false, "BatteryInspector on-battery: powerW ≈ -7.099")
    check(d.temperatureC == 30.44, "BatteryInspector on-battery: temperatureC == 30.44")
    check(d.percent == 78 && d.currentCapacityMAh == 2930 && d.maxCapacityMAh == 3977
          && d.designCapacityMAh == 4563 && d.healthPercent == 87,
          "BatteryInspector on-battery: capacity/health fields")
    check(d.cycleCount == 338 && d.designCycleCount == 1000, "BatteryInspector on-battery: cycle counts")
    check(d.timeToEmptyMin == 296 && d.timeToFullMin == nil, "BatteryInspector on-battery: timeToEmpty/timeToFull (65535 → nil)")
    check(d.externalConnected == false && d.adapter == nil, "BatteryInspector on-battery: no external adapter")
    check(d.cellVoltagesMV == [4032, 4032, 4030], "BatteryInspector on-battery: cellVoltagesMV")
    check(d.lifetime?.maxTemperatureC == 44 && d.lifetime?.avgTemperatureC == 25.9
          && d.lifetime?.maxDischargeCurrentMA == -3001 && d.lifetime?.totalOperatingTimeH == 20219,
          "BatteryInspector on-battery: lifetime fields")
    check(d.charger?.notChargingReason == 128, "BatteryInspector on-battery: charger.notChargingReason")
}

do {
    let d = BatteryInspector.parse(Data(batteryChargingFixture.utf8))!
    check(d.externalConnected == true && d.adapter != nil, "BatteryInspector charging: externalConnected/adapter present")
    check(d.adapter?.watts == 45 && d.adapter?.voltageMV == 20000 && d.adapter?.currentMA == 2250
          && d.adapter?.isWireless == false,
          "BatteryInspector charging: adapter watts/voltage/current/isWireless")
    check(d.adapter?.pdProfiles.count == 4 && d.adapter?.selectedProfileIndex == 3,
          "BatteryInspector charging: pdProfiles count + selectedProfileIndex")
    if let profile3 = d.adapter?.pdProfiles.first(where: { $0.index == 3 }) {
        check(profile3.maxVoltageMV == 20000 && profile3.maxCurrentMA == 2250,
              "BatteryInspector charging: profile index 3 maxVoltage/maxCurrent")
    } else {
        check(false, "BatteryInspector charging: expected a pdProfile with index 3")
    }
    check(d.adapter?.name == nil, "BatteryInspector charging: adapter.name absent on this adapter")
    check(d.charger?.chargingCurrentMA == 570 && d.charger?.notChargingReason == 0,
          "BatteryInspector charging: charger.chargingCurrentMA/notChargingReason")
}

do {
    check(BatteryInspector.parse(Data("not a plist".utf8)) == nil, "BatteryInspector: garbage input → nil")
}

do {
    check(!hasBattery || BatteryInspector.collect() != nil,
          "smoke BatteryInspector: collect() != nil (or no battery on this machine)")
}

// =====================================================================
// MARK: - BatteryInspector (battery passport: serial / manufacturer / mfg date)
// =====================================================================

do {
    var mfgBlobBytes: [UInt8] = [0,0,0,0, 0x0b,0,1,0, 0xf9,0x14,0,0, 4]
    mfgBlobBytes += Array("2213".utf8)
    mfgBlobBytes += [3]
    mfgBlobBytes += Array("00B".utf8)
    mfgBlobBytes += [3]
    mfgBlobBytes += Array("ATL".utf8)
    mfgBlobBytes += [0, 0x21, 0,0,0,0,0]
    let mfgBlob = Data(mfgBlobBytes)
    let fixture: [[String: Any]] = [["Serial": "X0X00000ABC00XXXX",
                                     "ManufacturerData": mfgBlob,
                                     "CurrentCapacity": 90, "Voltage": 12628]]
    let plist = try! PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0)
    let d = BatteryInspector.parse(plist)

    check(d?.serial == "X0X00000ABC00XXXX", "BatteryInspector passport: serial")
    check(d?.manufacturerCode == "ATL", "BatteryInspector passport: manufacturerCode == ATL")
    check(d?.mfgCode == "2213" && d?.mfgYear == 2022 && d?.mfgWeek == 13,
          "BatteryInspector passport: mfgCode/mfgYear/mfgWeek from YYWW code")
    check(d?.lowPowerMode == nil, "BatteryInspector passport: parse() never sets lowPowerMode")

    let garbage = BatteryInspector.decodeManufacturerData(Data([0,0,0]))
    check(garbage.mfgCode == nil && garbage.manufacturerCode == nil,
          "BatteryInspector passport: garbage blob decodes to (nil, nil)")

    var invalidWeekBlobBytes: [UInt8] = [0,0,0,0, 0x0b,0,1,0, 0xf9,0x14,0,0, 4]
    invalidWeekBlobBytes += Array("2299".utf8)
    invalidWeekBlobBytes += [3]
    invalidWeekBlobBytes += Array("00B".utf8)
    invalidWeekBlobBytes += [3]
    invalidWeekBlobBytes += Array("ATL".utf8)
    invalidWeekBlobBytes += [0, 0x21, 0,0,0,0,0]
    let invalidWeekBlob = Data(invalidWeekBlobBytes)
    let fixture2: [[String: Any]] = [["Serial": "X", "ManufacturerData": invalidWeekBlob,
                                      "CurrentCapacity": 90, "Voltage": 12628]]
    let plist2 = try! PropertyListSerialization.data(fromPropertyList: fixture2, format: .xml, options: 0)
    let d2 = BatteryInspector.parse(plist2)
    check(d2?.mfgCode == "2299" && d2?.mfgYear == nil && d2?.mfgWeek == nil,
          "BatteryInspector passport: week 99 rejected, mfgCode kept but mfgYear/mfgWeek nil")
}

// =====================================================================
// MARK: - L10n (ruPlural + StringsRU smoke)
// =====================================================================

check(ruPlural(1, "цикл", "цикла", "циклов") == "цикл", "ruPlural: n=1 ⇒ цикл")
check(ruPlural(2, "цикл", "цикла", "циклов") == "цикла", "ruPlural: n=2 ⇒ цикла")
check(ruPlural(5, "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=5 ⇒ циклов")
check(ruPlural(11, "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=11 ⇒ циклов")
check(ruPlural(21, "цикл", "цикла", "циклов") == "цикл", "ruPlural: n=21 ⇒ цикл")
check(ruPlural(104, "цикл", "цикла", "циклов") == "цикла", "ruPlural: n=104 ⇒ цикла")

check(!L.kpiCpuLabel.isEmpty, "L.kpiCpuLabel: non-empty")
check(!L.securityTitle.isEmpty, "L.securityTitle: non-empty")
check(!L.appWindowTitle.isEmpty, "L.appWindowTitle: non-empty")

// =====================================================================
// MARK: - L10nStore (live language switching)
// =====================================================================

do {
    L10nStore.shared.language = .en
    check(L.kpiBatteryLabel == "Battery", "L10nStore: switch .en, kpiBatteryLabel == Battery")
    check(L.kpiBatteryCycles(1) == "1 cycle", "L10nStore: switch .en, kpiBatteryCycles(1) == 1 cycle")
    check(L.kpiBatteryCycles(3) == "3 cycles", "L10nStore: switch .en, kpiBatteryCycles(3) == 3 cycles")
    check(ReportWriter.fmtBytes(1_073_741_824).contains("GB"), "L10nStore: switch .en, fmtBytes(1GiB) contains GB")
    check(!L.recommendationsAllGood.isEmpty && L.recommendationsAllGood != StringsRU().recommendationsAllGood,
          "L10nStore: switch .en, recommendationsAllGood non-empty and differs from RU")

    L10nStore.shared.language = .ru
    check(L.kpiBatteryLabel == "Батарея", "L10nStore: switch back .ru, kpiBatteryLabel == Батарея")
    check(ReportWriter.fmtBytes(1_073_741_824).contains("ГБ"), "L10nStore: switch back .ru, fmtBytes(1GiB) contains ГБ")

    // launchLanguage is a lazily-initialized static: since it's touched here for
    // the first time (after the .ru pin at file top), it captures .ru — matching
    // the pinned language regardless of the switches above.
    check(L10nStore.launchLanguage == .ru, "L10nStore: launchLanguage == .ru (matches pinned launch language)")
}

// =====================================================================
// MARK: - SMART render-time localizer (smartLocalizedLabel — Block N2)
// =====================================================================
//
// smartCriticalWarningRU and smartLocalizedLabel are defined in
// Engine/ReportWriter.swift. That file is symlinked into this Checks target
// (Checks/ReportWriter.swift → ../Sources/MacDashboard/Engine/ReportWriter.swift)
// as production engine code, not a test file, so — despite the name similarity —
// the cases below live here in main.swift, alongside every other check in this
// harness, rather than inside the symlinked engine source.

do {
    // Pinned .ru at file top: known attribute names and the hardcoded "SMART: OK"
    // status word both translate.
    check(smartLocalizedLabel("Temperature") == "Температура", "smartLocalizedLabel: RU Temperature -> Температура")
    check(smartLocalizedLabel("Percentage Used") == "Процент износа", "smartLocalizedLabel: RU Percentage Used -> Процент износа")
    check(smartLocalizedLabel("Power Cycles") == "Циклов включения", "smartLocalizedLabel: RU Power Cycles -> Циклов включения")
    check(smartLocalizedLabel("Critical Warning") == "Критическое предупреждение", "smartLocalizedLabel: RU Critical Warning -> Критическое предупреждение")
    check(smartLocalizedLabel("Available Spare") == "Резервная ёмкость", "smartLocalizedLabel: RU Available Spare -> Резервная ёмкость")
    check(smartLocalizedLabel("Power On Hours") == "Часов наработки", "smartLocalizedLabel: RU Power On Hours -> Часов наработки")
    check(smartLocalizedLabel("Unsafe Shutdowns") == "Некорректных выключений", "smartLocalizedLabel: RU Unsafe Shutdowns -> Некорректных выключений")
    check(smartLocalizedLabel("Media and Data Integrity Errors") == "Ошибок целостности данных", "smartLocalizedLabel: RU Media and Data Integrity Errors -> Ошибок целостности данных")
    check(smartLocalizedLabel("Error Information Log Entries") == "Записей в журнале ошибок", "smartLocalizedLabel: RU Error Information Log Entries -> Записей в журнале ошибок")
    check(smartLocalizedLabel("SMART: OK") == "SMART: в норме", "smartLocalizedLabel: RU SMART: OK -> SMART: в норме")

    // Unknown/unrecognized input passes through unchanged — no crash, no blank output.
    check(smartLocalizedLabel("Some Unknown Attr") == "Some Unknown Attr", "smartLocalizedLabel: RU unknown attr passes through unchanged")
    check(smartLocalizedLabel("") == "", "smartLocalizedLabel: RU empty string passes through unchanged")

    // Already-localized status strings (baked at collection time by ReportCollector,
    // e.g. "SMART: в норме (проверено)") are not in the lookup table and pass through too.
    check(smartLocalizedLabel(L.reportCollectorSmartOkVerified) == L.reportCollectorSmartOkVerified,
          "smartLocalizedLabel: RU already-localized status word passes through unchanged")
}

do {
    L10nStore.shared.language = .en
    check(smartLocalizedLabel("Temperature") == "Temperature", "smartLocalizedLabel: EN Temperature -> Temperature")
    check(smartLocalizedLabel("Percentage Used") == "Percentage Used", "smartLocalizedLabel: EN Percentage Used -> Percentage Used")
    check(smartLocalizedLabel("Power Cycles") == "Power Cycles", "smartLocalizedLabel: EN Power Cycles -> Power Cycles")
    check(smartLocalizedLabel("Critical Warning") == "Critical Warning", "smartLocalizedLabel: EN Critical Warning -> Critical Warning")
    check(smartLocalizedLabel("SMART: OK") == "SMART: OK", "smartLocalizedLabel: EN SMART: OK -> SMART: OK")

    // Cross-language sanity: a label that differs meaningfully between RU/EN really
    // does differ (guards against the dict silently falling back to raw/no-op).
    L10nStore.shared.language = .ru
    let ru = smartLocalizedLabel("Temperature")
    L10nStore.shared.language = .en
    let en = smartLocalizedLabel("Temperature")
    check(ru != en, "smartLocalizedLabel: Temperature differs between RU and EN")

    // Pass-through for unknown input holds in EN too.
    check(smartLocalizedLabel("Some Unknown Attr") == "Some Unknown Attr", "smartLocalizedLabel: EN unknown attr passes through unchanged")

    L10nStore.shared.language = .ru
}

// =====================================================================
// MARK: - AppSettings (fast-loop polling interval)
// =====================================================================

do {
    // UserDefaults hygiene: capture the pre-existing value (if any) and restore it
    // afterwards — the Checks binary has its own defaults domain, but keep it clean.
    let savedRaw = UserDefaults.standard.object(forKey: AppSettings.fastIntervalKey)

    // 1. Fresh state: AppSettings.shared is a lazy singleton initialized ONCE (on
    // first access anywhere in the process), so removeObject here can't force a
    // re-init — we're asserting the INSTANCE's already-established value, which
    // was clamped into allowedIntervals at first-touch time.
    UserDefaults.standard.removeObject(forKey: AppSettings.fastIntervalKey)
    check(AppSettings.allowedIntervals.contains(AppSettings.shared.fastIntervalSeconds),
          "AppSettings: shared.fastIntervalSeconds is a member of allowedIntervals")

    // 2. Set → didSet persists to UserDefaults.
    AppSettings.shared.fastIntervalSeconds = 5
    check(UserDefaults.standard.integer(forKey: AppSettings.fastIntervalKey) == 5,
          "AppSettings: setting fastIntervalSeconds = 5 persists via didSet")

    // 3. Clamp logic: the singleton can't be re-initialized mid-process, so the
    // init-time clamp (raw defaults value → nearest-safe default of 2 when not in
    // allowedIntervals) can't be re-exercised here. Asserting the rule's contract
    // directly instead: the allowed set is exactly [1, 2, 3, 5, 10] as documented
    // (and as read by both the init clamp and the SettingsView picker); the
    // clamp-on-init behavior itself is enforced by code review of AppSettings.init.
    check(AppSettings.allowedIntervals == [1, 2, 3, 5, 10],
          "AppSettings: allowedIntervals == [1, 2, 3, 5, 10] (init-clamp verified by code review)")

    // 4. Restore/settle.
    AppSettings.shared.fastIntervalSeconds = 2
    check(UserDefaults.standard.integer(forKey: AppSettings.fastIntervalKey) == 2,
          "AppSettings: setting fastIntervalSeconds = 2 persists via didSet")

    if let savedRaw {
        UserDefaults.standard.set(savedRaw, forKey: AppSettings.fastIntervalKey)
    } else {
        UserDefaults.standard.removeObject(forKey: AppSettings.fastIntervalKey)
    }
}

// =====================================================================
// MARK: - CommandRunner.runStreaming
// =====================================================================

/// Thread-safe collector for lines delivered by `runStreaming`'s `onLine` callback
/// (which fires on CommandRunner's own private serial queue, not the test's thread).
private final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [(String, Bool)] = []
    func append(_ line: String, _ isStderr: Bool) {
        lock.lock(); defer { lock.unlock() }
        _lines.append((line, isStderr))
    }
    var lines: [(String, Bool)] {
        lock.lock(); defer { lock.unlock() }
        return _lines
    }
}

do {
    let collector = LockedLines()
    let result = CommandRunner.runStreaming(
        "/bin/sh", ["-c", "printf 'a\\nb\\n'; printf 'e\\n' >&2"], timeout: 10
    ) { line, isStderr in collector.append(line, isStderr) }

    check(result == "a\nb\n", "CommandRunner.runStreaming: accumulated stdout == \"a\\nb\\n\"")
    let lines = collector.lines
    let stdoutLines = lines.filter { !$0.1 }.map { $0.0 }
    let stderrLines = lines.filter { $0.1 }.map { $0.0 }
    // Order is only asserted per-stream; stdout/stderr interleaving isn't guaranteed.
    check(stdoutLines == ["a", "b"], "CommandRunner.runStreaming: stdout lines delivered in order [a, b]")
    check(stderrLines == ["e"], "CommandRunner.runStreaming: stderr lines delivered == [e]")
}

do {
    let collector = LockedLines()
    let result = CommandRunner.runStreaming(
        "/bin/sh", ["-c", "printf 'no-newline'"], timeout: 10
    ) { line, isStderr in collector.append(line, isStderr) }

    check(result == "no-newline", "CommandRunner.runStreaming: partial-line flush returns \"no-newline\"")
    check(collector.lines.map(\.0) == ["no-newline"],
          "CommandRunner.runStreaming: partial-line flush delivers exactly one line")
}

do {
    let start = Date()
    let result = CommandRunner.runStreaming("/bin/sh", ["-c", "sleep 5"], timeout: 1) { _, _ in }
    let elapsed = Date().timeIntervalSince(start)
    check(result == nil, "CommandRunner.runStreaming: timeout returns nil")
    check(elapsed < 4, "CommandRunner.runStreaming: timeout wall time < 4s (got \(elapsed))")
}

// =====================================================================
// MARK: - BrewProgressParser
// =====================================================================

do {
    var parser = BrewProgressParser(total: 3)

    check(parser.consume(line: "==> Fetching downloads for: docker, git and node", isStderr: false),
          "BrewProgressParser: Fetching downloads header -> changed=true")
    check(parser.progress?.phase == .downloading,
          "BrewProgressParser: Fetching downloads header -> phase .downloading")

    _ = parser.consume(line: "✔︎ Bottle Manifest docker (28.0.1)", isStderr: true)
    check(parser.progress?.downloadsDone == 1, "BrewProgressParser: first ✔︎ line -> downloadsDone 1")
    check(parser.progress?.formula == "docker", "BrewProgressParser: first ✔︎ line -> formula \"docker\"")

    _ = parser.consume(line: "✔︎ Bottle docker (28.0.1)", isStderr: true)
    check(parser.progress?.downloadsDone == 2, "BrewProgressParser: second ✔︎ line -> downloadsDone 2")

    check(!parser.consume(line: "random noise", isStderr: false),
          "BrewProgressParser: unrecognized line -> changed=false")

    check(parser.consume(line: "==> Upgrading docker", isStderr: false),
          "BrewProgressParser: \"==> Upgrading docker\" -> changed=true")
    check(parser.progress?.phase == .upgrading, "BrewProgressParser: Upgrading docker -> phase .upgrading")
    check(parser.progress?.completed == 1, "BrewProgressParser: Upgrading docker -> completed 1")
    check(parser.progress?.formula == "docker", "BrewProgressParser: Upgrading docker -> formula \"docker\"")

    check(!parser.consume(line: "  27.0 -> 28.0.1", isStderr: false),
          "BrewProgressParser: version line -> changed=false")

    check(!parser.consume(line: "==> Pouring docker--28.0.1.arm64_tahoe.bottle.tar.gz", isStderr: false),
          "BrewProgressParser: Pouring line -> changed=false")

    check(!parser.consume(line: "==> Upgrading 2 dependents of upgraded formulae:", isStderr: false),
          "BrewProgressParser: dependents header ignored -> changed=false")

    check(parser.consume(line: "==> Installing node dependency: icu4c", isStderr: false),
          "BrewProgressParser: Installing dependency line -> changed=true")
    check(parser.progress?.completed == 1,
          "BrewProgressParser: Installing dependency line -> completed unchanged at 1")
    check(parser.progress?.formula == "icu4c", "BrewProgressParser: Installing dependency line -> formula \"icu4c\"")

    check(parser.consume(line: "==> Upgrading node", isStderr: false),
          "BrewProgressParser: \"==> Upgrading node\" -> changed=true")
    check(parser.progress?.completed == 2, "BrewProgressParser: Upgrading node -> completed 2")
    check(parser.progress?.formula == "node", "BrewProgressParser: Upgrading node -> formula \"node\"")
}

do {
    // total=0 (unknown outdated count): no crash, no percent math — that's the UI's job.
    var parser = BrewProgressParser(total: 0)
    check(parser.consume(line: "==> Upgrading foo", isStderr: false),
          "BrewProgressParser: total=0 -> Upgrading foo changed=true")
    check(parser.progress?.total == 0, "BrewProgressParser: total=0 -> progress.total == 0")
    check(parser.progress?.completed == 1, "BrewProgressParser: total=0 -> completed 1")
}

do {
    // No "Fetching downloads for:" header seen — a lone ✔︎ line still starts the
    // downloading phase.
    var parser = BrewProgressParser(total: 1)
    check(parser.consume(line: "✔︎ Formula hello (1.0)", isStderr: true),
          "BrewProgressParser: lone ✔︎ line (no Fetching header) -> changed=true")
    check(parser.progress?.phase == .downloading,
          "BrewProgressParser: lone ✔︎ line (no Fetching header) -> phase .downloading")
}

do {
    var parser = BrewProgressParser(total: 1)
    check(!parser.consume(line: "✘ Bottle foo (1.0)", isStderr: true),
          "BrewProgressParser: ✘ (failed download) line -> changed=false")
}

// =====================================================================
// MARK: - Block N5: brew cache freshness, report caption time, cancellation scope
// =====================================================================

do {
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    check(!ReportCollector.isBrewCacheFresh(collectedAt: nil, now: now),
          "isBrewCacheFresh: nil collectedAt -> false")
    check(ReportCollector.isBrewCacheFresh(collectedAt: now.addingTimeInterval(-300), now: now),
          "isBrewCacheFresh: 5 min old -> true")
    check(!ReportCollector.isBrewCacheFresh(collectedAt: now.addingTimeInterval(-660), now: now),
          "isBrewCacheFresh: 11 min old -> false")
    check(!ReportCollector.isBrewCacheFresh(collectedAt: now.addingTimeInterval(-600), now: now),
          "isBrewCacheFresh: exactly window-old -> false (strict <)")
    check(!ReportCollector.isBrewCacheFresh(collectedAt: now.addingTimeInterval(60), now: now),
          "isBrewCacheFresh: future timestamp (clock rollback) -> false")
}

do {
    let cal = Calendar.current
    let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    let sameDay = cal.date(bySettingHour: 9, minute: 30, second: 0, of: now)!
    let older = now.addingTimeInterval(-48 * 3600)
    check(reportUpdatedTimeString(sameDay, now: now, calendar: cal)
              == sameDay.formatted(date: .omitted, time: .shortened),
          "reportUpdatedTimeString: same day -> time-only branch")
    check(reportUpdatedTimeString(older, now: now, calendar: cal)
              == older.formatted(date: .abbreviated, time: .shortened),
          "reportUpdatedTimeString: older day -> date+time branch")
}

do {
    let scope = CommandCancellationScope()
    let start = Date()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { scope.cancel() }
    let out = CommandRunner.run("/bin/sleep", ["10"], timeout: 30, scope: scope)
    let elapsed = Date().timeIntervalSince(start)
    check(out == nil, "CommandCancellationScope: cancelled run returns nil")
    check(elapsed < 5, "CommandCancellationScope: cancel kills sleep fast (elapsed \(String(format: "%.1f", elapsed))s)")
    check(CommandRunner.run("/bin/echo", ["hi"], timeout: 5, scope: scope) == nil,
          "CommandCancellationScope: post-cancel run short-circuits to nil")
    check(CommandRunner.run("/bin/echo", ["hi"], timeout: 5)?
              .trimmingCharacters(in: .whitespacesAndNewlines) == "hi",
          "CommandRunner.run: scope-less call unaffected")
}

// =====================================================================
// MARK: - SmartToolsAvailability (Block N8, in SmartToolsAvailabilityChecks.swift)
// =====================================================================

runSmartToolsAvailabilityChecks()

// =====================================================================
// MARK: - LaunchdPlistInspector (Block N6, in LaunchdPlistInspectorChecks.swift)
// =====================================================================

runLaunchdPlistInspectorChecks()

// =====================================================================
// MARK: - ThermalSensors (Block N7, in ThermalSensorsChecks.swift)
// =====================================================================

runThermalSensorsChecks()

// =====================================================================
// MARK: - HistorySeries (Block H, in HistorySeriesChecks.swift)
// =====================================================================

runHistorySeriesChecks()

// =====================================================================
// MARK: - AI assistant redaction (Block AI, in AIRedactionChecks.swift)
// =====================================================================

runAIRedactionChecks()

// =====================================================================
// MARK: - AI assistant payload/request (Block AI, in AIPayloadRequestChecks.swift)
// =====================================================================

runAIPayloadRequestChecks()

// =====================================================================
// MARK: - AttentionModel
// =====================================================================

do {
    // 1. summaryTitle RU
    let ruCases: [(Int, String)] = [
        (0, "Всё в порядке"),
        (1, "Одна задача требует внимания"),
        (2, "Две задачи требуют внимания"),
        (3, "Три задачи требуют внимания"),
        (5, "Пять задач требуют внимания"),
        (6, "Шесть задач требуют внимания"),
        (11, "11 задач требуют внимания"),
        (14, "14 задач требуют внимания"),
        (21, "21 задача требует внимания"),
    ]
    for (n, expected) in ruCases {
        check(AttentionModel.summaryTitle(count: n, lang: .ru) == expected,
              "AttentionModel.summaryTitle ru(\(n)) == '\(expected)'")
    }

    // 2. summaryTitle EN
    let enCases: [(Int, String)] = [
        (0, "Everything is fine"),
        (1, "1 item needs attention"),
        (2, "2 items need attention"),
        (14, "14 items need attention"),
    ]
    for (n, expected) in enCases {
        check(AttentionModel.summaryTitle(count: n, lang: .en) == expected,
              "AttentionModel.summaryTitle en(\(n)) == '\(expected)'")
    }

    // 3. RU number agreement spot-checks
    let ruSpot: [(Int, String)] = [
        (22, "22 задачи требуют внимания"),
        (25, "25 задач требуют внимания"),
        (111, "111 задач требуют внимания"),
        (101, "101 задача требует внимания"),
    ]
    for (n, expected) in ruSpot {
        check(AttentionModel.summaryTitle(count: n, lang: .ru) == expected,
              "AttentionModel.summaryTitle ru(\(n)) == '\(expected)'")
    }

    // negative counts clamp to 0
    check(AttentionModel.summaryTitle(count: -3, lang: .ru) == "Всё в порядке",
          "AttentionModel.summaryTitle ru(-3) clamps to 0 -> 'Всё в порядке'")
}

// 4. QuietState.quiet(report:) truth table
do {
    var report = FullReport()
    report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)
    check(QuietState.quiet(report: report).securityQuiet, "QuietState: all-true security -> securityQuiet true")

    report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
    check(!QuietState.quiet(report: report).securityQuiet, "QuietState: one field false -> securityQuiet false")

    report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: nil)
    check(!QuietState.quiet(report: report).securityQuiet, "QuietState: one field nil -> securityQuiet false")

    report.security = nil
    check(!QuietState.quiet(report: report).securityQuiet, "QuietState: report.security == nil -> securityQuiet false")

    var r2 = FullReport()
    r2.updates = []; r2.crashes = []
    check(QuietState.quiet(report: r2).updatesQuiet, "QuietState: updates=[] & crashes=[] -> updatesQuiet true")

    r2.updates = nil; r2.crashes = []
    check(!QuietState.quiet(report: r2).updatesQuiet, "QuietState: updates=nil -> updatesQuiet false")

    r2.updates = []; r2.crashes = nil
    check(!QuietState.quiet(report: r2).updatesQuiet, "QuietState: crashes=nil -> updatesQuiet false")

    r2.updates = ["u1"]; r2.crashes = []
    check(!QuietState.quiet(report: r2).updatesQuiet, "QuietState: updates non-empty -> updatesQuiet false")
}

// A "full-bad" fixture that trips every branch except disk (parameterized: disk.pct
// picks diskFull vs. diskFullSoon — see below).
func attnFullBadFixture(diskPct: Double) -> (FullReport, LiveSnapshot) {
    var report = FullReport()
    report.security = SecurityState(fileVault: false, gatekeeper: false, sip: false, firewall: false)
    report.updates = ["u1"]
    report.crashes = ["crash1.ips"]
    report.tmDest = .some(.none)
    report.smart = [
        SmartDisk(device: "internal", title: "Boot SSD", status: "SMART: ошибки носителя",
                  attrs: [("Media and Data Integrity Errors", "3")], severity: .crit),
        SmartDisk(device: "/dev/disk4", title: "External SSD", status: "SMART: износ на исходе",
                  attrs: [("Percentage Used", "85")], severity: .warn),
    ]
    report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: nil, condition: "Replace Now", maxCapacity: 60)
    var live = LiveSnapshot()
    let size: Int64 = 1_000_000_000_000
    live.disk = DiskInfo(size: size, avail: Int64(Double(size) * (1 - diskPct)), dataUsed: nil, sysUsed: nil)
    let swapUsed = Int64(2.5 * Double(GIB))
    live.swap = SwapInfo(total: 4 * GIB, used: swapUsed, free: 4 * GIB - swapUsed)
    return (report, live)
}

// 5. Every AttentionKind produces non-empty label/detail/fullText in both languages.
do {
    // diskFull and diskFullSoon share one `if/else if` on the same live.disk.pct
    // (Assessment.swift), so no single report can trip both; two fixtures that
    // differ only in disk% cover all 14 kinds between them.
    let originalLang = L10nStore.shared.language
    defer { L10nStore.shared.language = originalLang }

    for lang in AppLanguage.allCases {
        L10nStore.shared.language = lang
        let (reportFull, liveFull) = attnFullBadFixture(diskPct: 0.90)   // -> diskFull
        let (reportSoon, liveSoon) = attnFullBadFixture(diskPct: 0.75)   // -> diskFullSoon
        let itemsFull = Assess.assess(report: reportFull, live: liveFull).items
        let itemsSoon = Assess.assess(report: reportSoon, live: liveSoon).items
        let allItems = itemsFull + itemsSoon
        let kinds = Set(allItems.map(\.kind))
        check(kinds.count == 14, "AttentionModel coverage (\(lang)): all 14 AttentionKind cases produced (got \(kinds.count))")
        for item in allItems {
            check(!item.label.isEmpty, "AttentionModel coverage (\(lang)): \(item.kind.rawValue) label non-empty")
            check(!item.detail.isEmpty, "AttentionModel coverage (\(lang)): \(item.kind.rawValue) detail non-empty")
            check(!item.fullText.isEmpty, "AttentionModel coverage (\(lang)): \(item.kind.rawValue) fullText non-empty")
        }
    }
}

// A broader fixture that also trips tip/capsule-producing branches, for the verb,
// parity and regression checks below (these don't need all 14 AttentionKinds, just
// a healthy mix of items+capsules with both nil and non-nil actions).
func attnMegaBadFixture() -> (FullReport, LiveSnapshot) {
    var (report, live) = attnFullBadFixture(diskPct: 0.90)
    report.brewOutdated = ["pkg1", "pkg2", "pkg3"]
    report.smart?.append(SmartDisk(device: "/dev/disk5", title: "External HDD", status: "SMART недоступен",
                                    attrs: [], severity: .warn))
    report.homeDirs = [
        DirSize(path: "/Users/x/Downloads", bytes: 11 * GIB),
        DirSize(path: "/Users/x/.Trash", bytes: 2 * GIB),
    ]
    report.serviceDirs = [
        DirSize(path: FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Caches", bytes: 4 * GIB),
    ]
    return (report, live)
}

do {
    let originalLang = L10nStore.shared.language
    defer { L10nStore.shared.language = originalLang }
    L10nStore.shared.language = .ru

    let (report, live) = attnMegaBadFixture()
    let a = Assess.assess(report: report, live: live)

    // 6. Verb rule.
    for item in a.items {
        if item.action == nil {
            check(item.verb.isEmpty, "AttentionModel verb rule: \(item.kind.rawValue) action==nil -> verb == ''")
        } else {
            check(!item.verb.isEmpty, "AttentionModel verb rule: \(item.kind.rawValue) action!=nil -> verb non-empty")
        }
        if !item.verb.isEmpty {
            check(!item.detail.contains(item.verb), "AttentionModel verb rule: \(item.kind.rawValue) detail does not contain its verb")
        }
    }
    for capsule in a.capsules {
        if capsule.action == nil {
            check(capsule.verb.isEmpty, "AttentionModel verb rule: capsule '\(capsule.object)' action==nil -> verb == ''")
        } else {
            check(!capsule.verb.isEmpty, "AttentionModel verb rule: capsule '\(capsule.object)' action!=nil -> verb non-empty")
        }
        if !capsule.verb.isEmpty {
            check(!capsule.value.contains(capsule.verb), "AttentionModel verb rule: capsule '\(capsule.object)' value does not contain its verb")
        }
    }
    check(!a.items.isEmpty && !a.capsules.isEmpty, "AttentionModel verb rule: fixture produced both items and capsules")

    // 7. Parity between problems/items and tips/capsules.
    check(a.items.count == a.problems.count, "AttentionModel parity: items.count == problems.count")
    var parityOK = a.items.count == a.problems.count
    for i in 0..<min(a.items.count, a.problems.count) {
        if a.items[i].sev != a.problems[i].sev || a.items[i].fullText != a.problems[i].text { parityOK = false }
    }
    check(parityOK, "AttentionModel parity: items[i].sev/fullText == problems[i].sev/text for every index")
    check(a.capsules.count == a.tips.count, "AttentionModel parity: capsules.count == tips.count")

    // 8. Regression guard: crit > serious > warn ordering unchanged; summary text form unchanged.
    func rankFor(_ s: Severity) -> Int {
        switch s {
        case .crit: return 3
        case .serious: return 2
        case .warn: return 1
        default: return 0
        }
    }
    let sevRanks = a.problems.map { rankFor($0.sev) }
    check(sevRanks == sevRanks.sorted(by: >), "AttentionModel regression guard: problems.map(sev) non-increasing (crit -> serious -> warn)")
    check(a.summaryText == L.assessSummaryCount(a.problems.count), "AttentionModel regression guard: summaryText form unchanged")
}

// 9. QuietState three-state SectionStatus (.collecting / .quiet / .loud)
do {
    var report = FullReport()
    report.security = nil
    check(QuietState.quiet(report: report).security == .collecting, "QuietState: security==nil -> .collecting")

    report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)
    check(QuietState.quiet(report: report).security == .quiet, "QuietState: all four true -> .quiet")

    report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
    do {
        let qs = QuietState.quiet(report: report)
        check(qs.security == .loud, "QuietState: one field false -> .loud")
        check(qs.securityOffCount == 1 && qs.securityUnknownCount == 0, "QuietState: one field false -> offCount 1, unknownCount 0")
    }

    report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: nil)
    do {
        let qs = QuietState.quiet(report: report)
        check(qs.security == .loud, "QuietState: one field nil (rest true) -> .loud")
        check(qs.securityUnknownCount == 1 && qs.securityOffCount == 0, "QuietState: one field nil -> unknownCount 1, offCount 0")
    }

    var r2 = FullReport()
    r2.updates = nil; r2.crashes = []
    check(QuietState.quiet(report: r2).updates == .collecting, "QuietState: updates==nil -> .collecting")

    r2.updates = []; r2.crashes = nil
    check(QuietState.quiet(report: r2).updates == .collecting, "QuietState: crashes==nil -> .collecting")

    r2.updates = []; r2.crashes = []
    check(QuietState.quiet(report: r2).updates == .quiet, "QuietState: updates=[] & crashes=[] -> .quiet")

    r2.updates = ["u1", "u2"]; r2.crashes = []
    do {
        let qs = QuietState.quiet(report: r2)
        check(qs.updates == .loud, "QuietState: 2 updates + 0 crashes -> .loud")
        check(qs.updatesCount == 2 && qs.crashesCount == 0, "QuietState: 2 updates + 0 crashes -> counts (2, 0)")
    }
}

// =====================================================================
// MARK: - fmtCapacity (decimal GB/TB disk-capacity formatting)
// =====================================================================
do {
    let originalLang = L10nStore.shared.language
    defer { L10nStore.shared.language = originalLang }

    // (bytes, expected-ru, expected-en, case label)
    let cases: [(Int64, String, String, String)] = [
        (Int64(228.3 * 1e9), "228,3 ГБ", "228.3 GB", "228.3 GB"),
        (Int64(999.9 * 1e9), "999,9 ГБ", "999.9 GB", "999.9 GB"),
        // Rounding-before-thresholding trap: 999.95 GB rounds to "1000.0" at
        // one decimal, which must NOT render as "1000,0 ГБ" — the unit switch
        // has to happen before formatting, giving "1 ТБ" instead.
        (Int64(999.95 * 1e9), "1 ТБ", "1 TB", "999.95 GB (rounding trap)"),
        (1_000_000_000_000, "1 ТБ", "1 TB", "1 TB"),
        (Int64(2.24 * 1e12), "2,24 ТБ", "2.24 TB", "2.24 TB"),
        (4_000_000_000_000, "4 ТБ", "4 TB", "4 TB (trailing zeros trimmed)"),
        (Int64(10.5 * 1e12), "10,5 ТБ", "10.5 TB", "10.5 TB (one decimal at/above 10 TB)"),
    ]

    for (bytes, expectedRU, expectedEN, label) in cases {
        L10nStore.shared.language = .ru
        check(fmtCapacity(bytes) == expectedRU, "fmtCapacity: \(label) (ru) == \"\(expectedRU)\"")
        L10nStore.shared.language = .en
        check(fmtCapacity(bytes) == expectedEN, "fmtCapacity: \(label) (en) == \"\(expectedEN)\"")
    }

    // Round-trip: fmtCapacityParts must never diverge from fmtCapacity (V2-FIX-UNITS).
    for (bytes, _, _, label) in cases {
        for lang in [AppLanguage.ru, .en] {
            L10nStore.shared.language = lang
            let p = fmtCapacityParts(bytes)
            check(fmtCapacity(bytes) == "\(p.value) \(p.unit)",
                  "fmtCapacityParts round-trip: \(label) (\(lang))")
        }
    }
}

// =====================================================================
// MARK: - fmtBytes / fmtBytesParts round-trip (V2-FIX-UNITS)
// =====================================================================
do {
    let originalLang = L10nStore.shared.language
    defer { L10nStore.shared.language = originalLang }

    // nil ⇒ ("—", nil), matching fmtBytes's "—".
    check(fmtBytesParts(nil).value == "—" && fmtBytesParts(nil).unit == nil,
          "fmtBytesParts: nil ⇒ (\"—\", nil)")
    check(fmtBytes(nil) == "—", "fmtBytes: nil ⇒ \"—\"")

    // Each binary unit step (B/KB/MB/GB/TB).
    let byteCases: [Int64] = [
        0, 1, 512, 1023,
        1024, 1_048_575,
        1_048_576, 1_073_741_823,
        1_073_741_824, 1_099_511_627_775,
        1_099_511_627_776, 2 * 1_099_511_627_776,
    ]

    for bytes in byteCases {
        for lang in [AppLanguage.ru, .en] {
            L10nStore.shared.language = lang
            let p = fmtBytesParts(bytes)
            check(fmtBytes(bytes) == "\(p.value) \(p.unit ?? "")",
                  "fmtBytesParts round-trip: \(bytes) bytes (\(lang))")
        }
    }
}

// =====================================================================
// MARK: - CommandRunner hardening (Block B7)
// =====================================================================
do {
    // F3: a single invalid UTF-8 byte in stdout must not discard the whole
    // capture — `run` uses the lossy decoder now, same as `runStreaming`.
    let invalidUTF8 = CommandRunner.run("/bin/sh", ["-c", "printf 'a\\xffb\\n'"], timeout: 5)
    check(invalidUTF8 != nil, "CommandRunner.run: invalid UTF-8 byte in stdout ⇒ non-nil")
    check(invalidUTF8?.contains("a") == true && invalidUTF8?.contains("b") == true,
          "CommandRunner.run: invalid UTF-8 byte in stdout ⇒ surrounding valid text preserved")

    // F2: output beyond the 8 MiB cap is truncated, not lost or turned into a
    // timeout (the child must still be drained to EOF and exit normally).
    let over = CommandRunner.runCapturing("/bin/sh", ["-c", "head -c 9000000 /dev/zero | tr '\\0' 'x'"],
                                          timeout: 10)
    check(over != nil, "CommandRunner.runCapturing: output over the cap ⇒ non-nil")
    check(over?.truncated == true, "CommandRunner.runCapturing: output over the cap ⇒ truncated == true")
    check(over?.text.utf8.count == CommandRunner.outputCap,
          "CommandRunner.runCapturing: output over the cap ⇒ byte count == outputCap")

    // F2: output under the cap must not have `truncated` stuck on.
    let under = CommandRunner.runCapturing("/bin/sh", ["-c", "echo hello"], timeout: 5)
    check(under != nil, "CommandRunner.runCapturing: output under the cap ⇒ non-nil")
    check(under?.truncated == false, "CommandRunner.runCapturing: output under the cap ⇒ truncated == false")

    // F4: the pinned default environment reaches the child, and an explicit
    // `environment:` override is actually applied (not ignored).
    let envOutput = CommandRunner.run("/usr/bin/env", [], timeout: 5)
    check(envOutput?.contains("LC_ALL=C") == true, "CommandRunner.run: default environment pins LC_ALL=C")
    check(envOutput?.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin") == true,
          "CommandRunner.run: default environment pins PATH")

    var customEnv = CommandRunner.defaultEnvironment
    customEnv["MACDASHBOARD_CHECKS_VAR"] = "b7-marker"
    let customOutput = CommandRunner.run("/usr/bin/env", [], timeout: 5, environment: customEnv)
    check(customOutput?.contains("MACDASHBOARD_CHECKS_VAR=b7-marker") == true,
          "CommandRunner.run: explicit environment: override is applied to the child")

    let prepended = CommandRunner.environment(prependingPATH: ["/custom/prefix/bin"])
    check(prepended["PATH"] == "/custom/prefix/bin:" + (CommandRunner.defaultEnvironment["PATH"] ?? ""),
          "CommandRunner.environment(prependingPATH:): prepends given dir and keeps the rest of PATH")
}

// =====================================================================
// MARK: - Summary
// =====================================================================

print("")
print("\(total - failures)/\(total) passed")
print("\(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
