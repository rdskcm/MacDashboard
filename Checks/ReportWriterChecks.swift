// Checks/ReportWriterChecks.swift
// COVERAGE-REPORT: behaviour checks for Engine/ReportWriter.swift — every section
// renderer's populated and variant output, section order, footer, helpers, and the
// data-integrity / error paths of ReportWriter.write. All writes go to a fresh temp
// directory that is removed afterwards; nothing here touches the user's App Support.

import Foundation

/// Body lines of one "===== name =====" section of a rendered report: the lines after
/// the header up to (not including) the blank line addSection() leaves before the next
/// header. nil when the header line is absent.
private func rwSection(_ report: String, _ name: String) -> [String]? {
    let lines = report.components(separatedBy: "\n")
    guard let h = lines.firstIndex(of: "===== \(name) =====") else { return nil }
    var body: [String] = []
    for line in lines[(h + 1)...] {
        if line.isEmpty { break }
        body.append(line)
    }
    return body
}

/// Trailing-space pad to `width` characters, never truncates. Written independently of
/// ReportWriter.padRight so layout expectations do not reuse the code under test.
private func rwCol(_ s: String, _ width: Int) -> String {
    s + String(repeating: " ", count: max(0, width - s.count))
}

/// Expected vm_stat-style line: "<label>:" padded to 32 columns, then "<pages>." right-aligned in 10.
private func rwVM(_ label: String, _ pages: Int64) -> String {
    let n = "\(pages)."
    return rwCol(label + ":", 32) + String(repeating: " ", count: max(0, 10 - n.count)) + n
}

private func rwMode(_ path: String) -> UInt16? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let mode = attrs[.posixPermissions] as? NSNumber else { return nil }
    return mode.uint16Value & 0o777
}

private func rwNames() -> [String] {
    [L.reportSectionSystem, L.reportSectionDisk, L.reportSectionSnapshots, L.reportSectionHomeDirs,
     L.reportSectionServiceDirs, L.reportSectionMemory, L.reportSectionTopMem, L.reportSectionTopCPU,
     L.reportSectionLoginItems, L.reportSectionAgents, L.reportSectionBackground, L.reportSectionBattery,
     L.reportSectionEnergy, L.reportSectionSecurity, L.reportSectionTMDest, "SPOTLIGHT",
     L.reportSectionCrashes, "HOMEBREW", L.reportSectionUpdates, L.reportSectionSmart,
     L.reportSectionTimings, L.reportSectionUnparsed]
}

private func rwCheckOrder(_ out: String, _ tag: String) {
    let lines = out.components(separatedBy: "\n")
    let names = rwNames()
    let idx = names.map { lines.firstIndex(of: "===== \($0) =====") }
    let allPresent = !idx.contains { $0 == nil }
    check(allPresent, "ReportWriter: \(tag) every section header present")
    let ints = idx.compactMap { $0 }
    let increasing = zip(ints, ints.dropFirst()).allSatisfy { $0 < $1 }
    check(allPresent && increasing, "ReportWriter: \(tag) section headers in fixed order")
    let headerCount = lines.filter { $0.hasPrefix("===== ") }.count
    check(headerCount == names.count + 1, "ReportWriter: \(tag) each header exactly once + done banner (got \(headerCount))")
}

func runReportWriterChecks() {
    let originalLang = L10nStore.shared.language
    defer { L10nStore.shared.language = originalLang }
    L10nStore.shared.language = .ru

    let gib: Int64 = 1 << 30
    let mib: Int64 = 1 << 20
    let tib: Int64 = 1 << 40
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let t = cal.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 18, minute: 37, second: 3))!
    let hist = HistoryState()

    func fullFixture() -> (FullReport, LiveSnapshot) {
        var r = FullReport()
        var live = LiveSnapshot()
        r.createdAt = t
        r.system = SystemInfo(osName: "macOS", osVersion: "26.0", osBuild: "25A354", modelName: "MacBook Air", modelId: "Mac15,12", chip: "Apple M3", cores: "8 (4 performance and 4 efficiency)", memBytes: 16 * gib, uptime: "2 дня 3 мин")
        live.disk = DiskInfo(size: 500 * gib, avail: 100 * gib, dataUsed: 350 * gib, sysUsed: 12 * gib)
        r.snapshots = ["com.apple.TimeMachine.2026-07-03-183000.local"]
        r.homeDirs = (1...25).map { DirSize(path: "/Users/u/d" + String(format: "%02d", $0), bytes: Int64($0) * 1024) }
        r.homeDirsUnreadable = ["/Users/u/Library/Mail"]
        r.serviceDirs = [DirSize(path: "/Users/u/Library/Caches", bytes: 5 * gib), DirSize(path: "/Users/u/Library/Developer", bytes: 12 * gib + 512 * mib)]
        r.serviceDirsUnreadable = ["/a/x", "/b/y"]
        r.folderSizesCountedAt = t
        r.folderSizesCountDuration = 6.4
        live.mem = MemSnapshot(total: 16 * gib, pageSize: 16384, free: 100 * 16384, active: 200 * 16384, inactive: 300 * 16384, speculative: 4 * 16384, wired: 50 * 16384, compressor: 60 * 16384, purgeable: 7 * 16384, fileBacked: 80 * 16384)
        live.swap = SwapInfo(total: 2 * gib, used: 512 * mib, free: 1536 * mib)
        let procs = [ProcEntry(name: "Safari", cpu: 12.34, memBytes: 3 * gib), ProcEntry(name: "kernel_task", cpu: nil, memBytes: nil)]
        live.topMem = procs
        live.topCPU = procs
        r.autostart = AutostartInfo(loginItems: ["Dropbox", "Rectangle"], userAgents: [LaunchdPlistInfo(path: "/Users/u/Library/LaunchAgents/com.a.plist", isOrphan: false), LaunchdPlistInfo(path: "/Users/u/Library/LaunchAgents/com.b.plist", isOrphan: true)], systemAgents: [LaunchdPlistInfo(path: "/Library/LaunchAgents/com.c.plist", isOrphan: false)], systemDaemons: [LaunchdPlistInfo(path: "/Library/LaunchDaemons/com.d.plist", isOrphan: false)], background: [(pid: "123", label: "com.x.helper"), (pid: "-", label: "com.y.agent")])
        r.battery = BatteryInfo(source: "AC Power", charge: 80, state: "charging", cycles: 123, condition: "Normal", maxCapacity: 91)
        live.battery = BatteryInfo(charge: 10)
        r.energy = EnergySettings(battery: [("displaysleep", "2"), ("sleep", "1")], ac: [("displaysleep", "10")])
        r.security = SecurityState(fileVault: true, gatekeeper: false, sip: nil, firewall: true)
        r.tmDest = TMDestination(name: "Backup", kind: "Local", mountPoint: "/Volumes/Backup", quotaBytes: 2 * tib, lastBackup: "2026-07-03-120000")
        r.spotlight = "Indexing enabled."
        r.crashes = [CrashGroup(process: "diffscore", count: 3, directory: "/x"), CrashGroup(process: "Finder", count: 1, directory: "/x")]
        r.brewStatus = .installed(version: "Homebrew 4.6.0")
        r.brewOutdated = ["git", "node"]
        r.updates = ["macOS Tahoe 26.0.1"]
        r.updatesCheckedAt = t
        r.updatesCheckDuration = 30
        r.sectionDurations = ["system": 0.2, "disk": 1.5, "brew": 1.5]
        r.passDuration = 7
        r.smart = [SmartDisk(device: "/dev/disk0", title: "APPLE SSD", status: "SMART: OK", attrs: [("Temperature", "35 C"), ("Critical Warning", "0x00"), ("Custom Attr", "7")]), SmartDisk(device: "/dev/disk4", title: "Ext", status: "NO ACCESS")]
        r.parseFailures = [ParseFailure(.spHardware, stdout: (1...10).map { "l\($0)" }.joined(separator: "\n"))!]
        live.parseFailures = [ParseFailure(.ps, stdout: "garbage")!]
        return (r, live)
    }

    func diskHeader() -> String {
        rwCol("Filesystem", 24) + rwCol("Size", 9) + rwCol("Used", 9) + rwCol("Avail", 9) + rwCol("Capacity", 10) + "Mounted on"
    }
    func diskRow(_ fs: String, _ size: String, _ used: String, _ avail: String, _ pct: String, _ mount: String) -> String {
        rwCol(fs, 24) + rwCol(size, 9) + rwCol(used, 9) + rwCol(avail, 9) + rwCol(pct, 10) + mount
    }

    // ---- §B: full fixture ----
    let (fr, flive) = fullFixture()
    let out = ReportWriter.render(report: fr, live: flive, history: hist)
    let u = reportUpdatedTimeString(t)
    do {
        func sec(_ name: String, _ body: [String], _ label: String) {
            let got = rwSection(out, name)
            let ok = got == body
            check(ok, "ReportWriter: \(label) populated body" + (ok ? "" : " (got \(String(describing: got)))"))
        }
        sec(L.reportSectionSystem, ["ProductName:\tmacOS", "ProductVersion:\t26.0", "BuildVersion:\t25A354", "      Model Name: MacBook Air", "      Model Identifier: Mac15,12", "      Chip: Apple M3", "      Total Number of Cores: 8 (4 performance and 4 efficiency)", "      Memory: 16,0 ГБ", L.reportUptime("2 дня 3 мин")], "SYSTEM")
        sec(L.reportSectionDisk, [diskHeader(),
                                  diskRow("/", "500,0 ГБ", "12,0 ГБ", "100,0 ГБ", "2%", "/"),
                                  diskRow("/System/Volumes/Data", "500,0 ГБ", "350,0 ГБ", "100,0 ГБ", "70%", "/System/Volumes/Data")], "DISK")
        sec(L.reportSectionSnapshots, ["com.apple.TimeMachine.2026-07-03-183000.local"], "SNAPSHOTS")
        let hd = rwSection(out, L.reportSectionHomeDirs) ?? []
        check(hd.count == 22, "ReportWriter: HOMEDIRS 22 lines (got \(hd.count))")
        if hd.count == 22 {
            check(hd[0] == "    1,0 КБ  /Users/u/d01", "ReportWriter: HOMEDIRS first row")
            check(hd[19] == "   20,0 КБ  /Users/u/d20", "ReportWriter: HOMEDIRS 20th row")
            check(!hd.contains { $0.contains("/Users/u/d21") }, "ReportWriter: HOMEDIRS capped at 20")
            check(hd[20] == L.storageFoldersNoFDA("/Users/u/Library/Mail"), "ReportWriter: HOMEDIRS unreadable line")
            check(hd[21] == L.reportFoldersCountedAt(u), "ReportWriter: HOMEDIRS counted-at line")
        } else {
            check(false, "ReportWriter: HOMEDIRS row checks skipped (wrong line count)")
        }
        sec(L.reportSectionServiceDirs, ["    5,0 ГБ  /Users/u/Library/Caches", "   12,5 ГБ  /Users/u/Library/Developer", L.storageFoldersNoFDA("/a/x, /b/y"), L.reportFoldersCountedAt(u)], "SERVICEDIRS")
        sec(L.reportSectionMemory, ["Mach Virtual Memory Statistics: (page size of 16384 bytes)", rwVM("Pages free", 100), rwVM("Pages active", 200), rwVM("Pages inactive", 300), rwVM("Pages speculative", 4), rwVM("Pages wired down", 50), rwVM("Pages purgeable", 7), rwVM("Pages occupied by compressor", 60), rwVM("File-backed pages", 80), "vm.swapusage: total = 2048.00M  used = 512.00M  free = 1536.00M"], "MEMORY")
        sec(L.reportSectionTopMem, [rwCol("MEM", 8) + rwCol("%CPU", 7) + "COMMAND", rwCol("3,0 ГБ", 8) + rwCol("12.3", 7) + "Safari", rwCol("?", 8) + rwCol("?", 7) + "kernel_task"], "TOPMEM")
        sec(L.reportSectionTopCPU, [rwCol("%CPU", 7) + rwCol("MEM", 8) + "COMMAND", rwCol("12.3", 7) + rwCol("3,0 ГБ", 8) + "Safari", rwCol("?", 7) + rwCol("?", 8) + "kernel_task"], "TOPCPU")
        sec(L.reportSectionLoginItems, ["Dropbox", "Rectangle"], "LOGINITEMS")
        sec(L.reportSectionAgents, [L.reportAgentsUserHeader, "com.a.plist", "com.b.plist [ORPHAN]", L.reportAgentsSystemHeader, "com.c.plist", "com.d.plist"], "AGENTS")
        sec(L.reportSectionBackground, [rwCol("PID", 7) + "Label", rwCol("123", 7) + "com.x.helper", rwCol("-", 7) + "com.y.agent"], "BACKGROUND")
        sec(L.reportSectionBattery, [L.reportBatterySource("AC Power"), L.reportBatteryCharge("80%"), L.reportBatteryState("charging"), "Cycle Count: 123", "Condition: Normal", "Maximum Capacity: 91%"], "BATTERY")
        sec(L.reportSectionEnergy, ["Battery Power:", " displaysleep 2", " sleep 1", "AC Power:", " displaysleep 10"], "ENERGY")
        sec(L.reportSectionSecurity, ["FileVault: On", "Gatekeeper: Off", "SIP: ?", "Firewall: On"], "SECURITY")
        sec(L.reportSectionTMDest, ["Name          : Backup", "Kind          : Local", "Mount Point   : /Volumes/Backup", "Quota         : 2,0 ТБ", L.reportTMLastBackup("2026-07-03-120000")], "TMDEST")
        sec("SPOTLIGHT", ["Indexing enabled."], "SPOTLIGHT")
        sec(L.reportSectionCrashes, [L.maintenanceCrashRow("diffscore", 3), L.maintenanceCrashRow("Finder", 1)], "CRASHES")
        sec("HOMEBREW", ["Homebrew 4.6.0", L.reportBrewOutdatedHeader, "git", "node"], "HOMEBREW")
        sec(L.reportSectionUpdates, ["macOS Tahoe 26.0.1", L.reportUpdatesCheckedAt(u)], "UPDATES")
        let w = "Критическое предупреждение".count + 3
        sec(L.reportSectionSmart, [L.reportSmartDiskLine("APPLE SSD", "/dev/disk0", L.reportSmartStatusOk),
                                   "  " + rwCol("Температура:", w) + "35 C",
                                   "  " + rwCol("Критическое предупреждение:", w) + L.reportSmartWarningNone,
                                   "  " + rwCol("Custom Attr:", w) + "7",
                                   L.reportSmartDiskLine("Ext", "/dev/disk4", "NO ACCESS")], "SMART")
        sec(L.reportSectionTimings, [L.reportTimingsNote, L.reportTimingsPass("7,0 с"), "  Homebrew: 1,5 с", "  disk:     1,5 с", "  Система:  0,2 с", L.reportTimingsUpdates("30,0 с", u), L.reportTimingsFolderSizes("6,4 с", u)], "TIMINGS")
        sec(L.reportSectionUnparsed, [L.reportUnparsedHint, "$ ps -axww -o pid=,rss=,time=,comm=", "  garbage", "$ system_profiler -json SPHardwareDataType", "  l1", "  l2", "  l3", "  l4", "  l5", "  l6", "  l7", "  l8", "  " + L.reportUnparsedMoreLines(2)], "UNPARSED")

        // R3: order, uniqueness, footer, history, created-at, EN pass
        rwCheckOrder(out, "RU")
        let footer = "\n===== \(L.reportDoneBanner) =====\n" + L.reportSavedTo(NSHomeDirectory() + "/Library/Application Support/MacDashboard/mac_report.txt") + "\n"
        check(out.hasSuffix(footer), "ReportWriter: done banner and saved-to footer")
        let histOut = ReportWriter.render(report: fr, live: flive, history: HistoryState(last_run: "2026-07-01", mac_history: [MacHistoryEntry(date: "2026-07-01", macos: "HIST-SENTINEL")]))
        check(histOut == out, "ReportWriter: history argument has no effect")
        let first = out.components(separatedBy: "\n")[0]
        check(first.hasPrefix(L.reportCreatedAt("Fri Jul  3 18:37:03 ")) && first.hasSuffix(" 2026"), "ReportWriter: created-at line format (got \(first))")
        var r13 = fr
        r13.createdAt = cal.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 18, minute: 37, second: 3))!
        let first13 = ReportWriter.render(report: r13, live: flive, history: hist).components(separatedBy: "\n")[0]
        check(first13.hasPrefix(L.reportCreatedAt("Mon Jul 13 18:37:03 ")), "ReportWriter: created-at two-digit day (got \(first13))")

        L10nStore.shared.language = .en
        let outEN = ReportWriter.render(report: fr, live: flive, history: hist)
        rwCheckOrder(outEN, "EN")
        check(rwSection(outEN, L.reportSectionSystem)?.contains("      Memory: 16.0 GB") == true, "ReportWriter: EN memory uses dot decimal and GB")
        L10nStore.shared.language = .ru
    }

    // ---- §C: variants ----
    do {
        func render(_ f: (inout FullReport, inout LiveSnapshot) -> Void) -> String {
            var r = FullReport()
            var l = LiveSnapshot()
            r.createdAt = t
            f(&r, &l)
            return ReportWriter.render(report: r, live: l, history: hist)
        }
        func eq(_ o: String, _ name: String, _ body: [String], _ label: String) {
            let got = rwSection(o, name)
            let ok = got == body
            check(ok, "ReportWriter: \(label)" + (ok ? "" : " (got \(String(describing: got)))"))
        }
        let dataRow = { (s: String, us: String, a: String, p: String) in diskRow("/System/Volumes/Data", s, us, a, p, "/System/Volumes/Data") }

        eq(render { _, l in l.disk = DiskInfo(size: 1000, avail: 250) }, L.reportSectionDisk,
           [diskHeader(), dataRow("1000 Б", "750 Б", "250 Б", "75%")], "C1 disk derived used/pct, no / row")
        eq(render { _, l in l.disk = DiskInfo(size: 0, avail: 0, dataUsed: 0, sysUsed: 0) }, L.reportSectionDisk,
           [diskHeader(), diskRow("/", "0 Б", "0 Б", "0 Б", "0%", "/"), dataRow("0 Б", "0 Б", "0 Б", "0%")], "C2 disk zero size")
        eq(render { r, _ in r.system = SystemInfo() }, L.reportSectionSystem, [L.sharedUnavailable], "C3 empty system")
        eq(render { r, _ in r.snapshots = [] }, L.reportSectionSnapshots, [L.reportNone], "C4 no snapshots")
        eq(render { r, _ in r.homeDirs = nil; r.homeDirsUnreadable = ["/x"]; r.folderSizesCountedAt = t }, L.reportSectionHomeDirs,
           [L.sharedUnavailable, L.storageFoldersNoFDA("/x")], "C5 nil homeDirs")
        eq(render { r, _ in r.homeDirs = []; r.folderSizesCountedAt = t }, L.reportSectionHomeDirs,
           [L.reportNone, L.reportFoldersCountedAt(reportUpdatedTimeString(t))], "C6 empty homeDirs")
        eq(render { r, _ in r.serviceDirs = []; r.serviceDirsNotMeasured = ["/Applications", "/Users/u/Library/Containers"]
                    r.serviceDirsUnreadable = ["/a/x"]; r.folderSizesCountedAt = t }, L.reportSectionServiceDirs,
           [L.reportNone, L.storageFoldersNotMeasured("/Applications, /Users/u/Library/Containers"),
            L.storageFoldersNoFDA("/a/x"), L.reportFoldersCountedAt(reportUpdatedTimeString(t))],
           "C6b service not measured in time, before unreadable (SERVICE-DIRS-TIMEOUT)")
        eq(render { r, _ in r.homeDirs = nil; r.homeDirsNotMeasured = ["/Users/u/Documents"] }, L.reportSectionHomeDirs,
           [L.sharedUnavailable, L.storageFoldersNotMeasured("/Users/u/Documents")], "C6c home not measured in time")
        check(StringsRU().storageFoldersNotMeasured("X") == "Не успели измерить: X." && StringsEN().storageFoldersNotMeasured("X") == "Not measured in time: X.", "SERVICE-DIRS-TIMEOUT: RU/EN not-measured strings")
        eq(render { _, l in l.mem = nil; l.swap = SwapInfo(total: 0, used: 0, free: 0) }, L.reportSectionMemory,
           ["Mach Virtual Memory Statistics: \(L.sharedUnavailable)", "vm.swapusage: total = 0.00M  used = 0.00M  free = 0.00M"], "C7 nil mem, zero swap")
        let c8 = rwSection(render { _, l in
            l.mem = MemSnapshot(total: 0, pageSize: 0, free: 4096, active: 0, inactive: 0, speculative: 0, wired: 0, compressor: 0, purgeable: 0, fileBacked: 0)
            l.swap = nil
        }, L.reportSectionMemory) ?? []
        check(c8.count == 10 && c8[0] == "Mach Virtual Memory Statistics: (page size of 0 bytes)" && c8[1] == rwVM("Pages free", 0)
              && c8.last == "vm.swapusage: \(L.sharedUnavailable)", "ReportWriter: C8 page size 0, nil swap (got \(c8))")
        let c9 = rwSection(render { _, l in
            l.topMem = (1...12).map { ProcEntry(name: "proc-" + String(format: "%02d", $0), cpu: 1.0, memBytes: mib) }
        }, L.reportSectionTopMem) ?? []
        check(c9.count == 11 && c9.last!.hasSuffix("proc-10") && !c9.contains { $0.hasSuffix("proc-11") }, "ReportWriter: C9 top-10 cap (count \(c9.count))")
        let c10 = render { r, _ in r.autostart = AutostartInfo(loginItems: nil) }
        eq(c10, L.reportSectionLoginItems, [L.autostartNoPermission], "C10 login items no permission")
        eq(c10, L.reportSectionAgents, [L.reportAgentsUserHeader, L.reportEmpty, L.reportAgentsSystemHeader], "C10 agents empty")
        eq(c10, L.reportSectionBackground, [L.reportNone], "C10 background none")
        eq(render { r, _ in r.autostart = AutostartInfo(loginItems: []) }, L.reportSectionLoginItems, [L.reportNone], "C11 empty login items")
        eq(render { _, l in l.battery = BatteryInfo() }, L.reportSectionBattery,
           [L.reportBatterySource("?"), L.reportBatteryCharge("?"), L.reportBatteryState("?"), "Cycle Count: ?", "Condition: ?", "Maximum Capacity: ?"], "C12 live battery fallback, all nil")
        eq(render { r, _ in r.tmDest = .some(nil) }, L.reportSectionTMDest, [L.reportTMNotConfigured], "C13 tmDest .some(nil)")
        eq(render { r, _ in r.tmDest = TMDestination() }, L.reportSectionTMDest, [L.reportTMNotConfigured], "C14 empty tmDest")
        eq(render { r, _ in r.tmDest = TMDestination(name: "Backup", lastBackupUnavailableReason: .diskNotConnected) }, L.reportSectionTMDest,
           ["Name          : Backup", L.reportTMLastBackup(L.reportCollectorDiskNotConnected)], "C15 tm unavailable reason")
        eq(render { r, _ in r.tmDest = TMDestination(lastBackup: "2026-07-03-120000", lastBackupUnavailableReason: .dateUnavailableNoFDA) }, L.reportSectionTMDest,
           [L.reportTMLastBackup("2026-07-03-120000")], "C16 tm date wins over reason")
        eq(render { r, _ in r.crashes = [] }, L.reportSectionCrashes, [L.reportNone], "C17 no crashes")
        let c18 = rwSection(render { r, _ in
            r.crashes = (1...17).map { CrashGroup(process: "c" + String(format: "%02d", $0), count: 1, directory: "/x") }
        }, L.reportSectionCrashes) ?? []
        check(c18.count == 15 && c18.last == L.maintenanceCrashRow("c15", 1), "ReportWriter: C18 crashes cap 15 (count \(c18.count))")
        eq(render { r, _ in r.brewStatus = .notInstalled }, "HOMEBREW", [L.maintenanceBrewNotInstalled], "C19 brew not installed")
        eq(render { r, _ in r.brewStatus = .installed(version: "Homebrew 4.6.0"); r.brewOutdated = nil }, "HOMEBREW", ["Homebrew 4.6.0", L.maintenanceBrewOutdatedCheckFailed], "C20 brew outdated check failed")
        eq(render { r, _ in r.brewStatus = .installed(version: nil); r.brewOutdated = ["git"] }, "HOMEBREW",
           [L.maintenanceBrewVersionUnknown, L.reportBrewOutdatedHeader, "git"], "C20b brew version unknown, list ok")
        eq(render { r, _ in r.brewStatus = .installed(version: nil); r.brewOutdated = nil }, "HOMEBREW",
           [L.maintenanceBrewVersionUnknown, L.maintenanceBrewOutdatedCheckFailed], "C20c brew version unknown, outdated failed")
        eq(render { r, _ in r.updates = [] }, L.reportSectionUpdates, ["No new software available."], "C21 no updates")
        eq(render { r, _ in r.updatesCheckDuration = 30; r.updatesCheckedAt = nil; r.passDuration = 1 }, L.reportSectionTimings,
           [L.reportTimingsNote, L.reportTimingsPass("1,0 с")], "C22 duration without timestamp")
        eq(render { r, _ in r.smart = [] }, L.reportSectionSmart, [L.reportNone], "C23 no smart disks")
    }

    // ---- §D: helpers ----
    do {
        let fb: [(Int64, String)] = [(0, "0 Б"), (1023, "1023 Б"), (1024, "1,0 КБ"), (1536, "1,5 КБ"), (-2048, "-2,0 КБ"),
                                     (5 * tib, "5,0 ТБ"), (1024 * tib, "1024,0 ТБ"), (Int64.min, "-8388608,0 ТБ")]
        for (n, want) in fb {
            let got = ReportWriter.fmtBytes(n)
            check(got == want, "ReportWriter: fmtBytes(\(n)) == \(want) (got \(got))")
        }
        check(ReportWriter.padRight("abc", 5) == "abc  ", "ReportWriter: padRight pads")
        check(ReportWriter.padRight("abcdef", 3) == "abcdef", "ReportWriter: padRight never truncates")
        check(ReportWriter.padLeft("7", 3) == "  7", "ReportWriter: padLeft pads")
        check(ReportWriter.padLeft("abcd", 2) == "abcd", "ReportWriter: padLeft never truncates")

        let sw: [(String, String)] = [
            ("0x00", L.reportSmartWarningNone),
            ("0x01", L.reportSmartWarningLowSpareCapacity),
            ("0x03", L.reportSmartWarningLowSpareCapacity + ", " + L.reportSmartWarningCriticalTemp),
            ("0X02", L.reportSmartWarningCriticalTemp),
            (" 0x04\n", L.reportSmartWarningReliabilityDegraded),
            ("08", L.reportSmartWarningReadOnlyMode),
            ("0x30", L.reportSmartWarningBackupPowerFail + ", " + L.reportSmartWarningPersistentMemoryReadOnly),
            ("0x40", L.reportSmartWarningGeneric("0x40")),
            ("zz", "zz"), ("0x", "0x"), ("", ""),
        ]
        for (raw, want) in sw {
            let got = smartCriticalWarningRU(raw)
            check(got == want, "ReportWriter: smartCriticalWarningRU(\(raw.debugDescription)) (got \(got.debugDescription))")
        }

        let now = Date(timeIntervalSince1970: 1_760_000_000)
        check(folderSizesAgeString(countedAt: now.addingTimeInterval(-60), now: now) == L.foldersCountedAgo("1 \(L.uptimeUnitMinute)"), "ReportWriter: folderSizesAgeString 1 minute")
        check(folderSizesAgeString(countedAt: now.addingTimeInterval(-2 * 3600), now: now) == L.foldersCountedAgo("2 \(L.uptimeUnitHour)"), "ReportWriter: folderSizesAgeString 2 hours")
        check(folderSizesAgeString(countedAt: now.addingTimeInterval(-3 * 86_400), now: now) == L.foldersCountedAgo("3 \(L.uptimeUnitDay)"), "ReportWriter: folderSizesAgeString 3 days")
    }

    // ---- §E: write() integrity and error paths ----
    do {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdashboard-reportwriter-\(UUID().uuidString)", isDirectory: true)
        precondition(!root.path.contains("/Library/Application Support/"), "ReportWriterChecks: temp root must never be App Support")
        defer { try? FileManager.default.removeItem(at: root) }

        let dir = root.appendingPathComponent("ok", isDirectory: true)
        let file = dir.appendingPathComponent("mac_report.txt")

        // E1 overwrite
        do {
            try ReportWriter.write(text: "OLD CONTENT THAT IS LONGER THAN NEW\n", to: file)
            try ReportWriter.write(text: "new", to: file)
        } catch { check(false, "ReportWriter: E1 overwrite threw \(error)") }
        check((try? Data(contentsOf: file)) == Data("new".utf8), "ReportWriter: E1 overwrite leaves exactly the new bytes")

        // E2 pre-existing 0644 file
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        check(rwMode(file.path) == 0o644, "ReportWriter: E2 precondition, file is 0644")
        do { try ReportWriter.write(text: "again", to: file) } catch { check(false, "ReportWriter: E2 rewrite threw \(error)") }
        check(rwMode(file.path) == 0o600, "ReportWriter: E2 rewritten file is 0600 (got \(String(describing: rwMode(file.path))))")
        check((try? Data(contentsOf: file)) == Data("again".utf8), "ReportWriter: E2 content after rewrite")

        // E3 round-trip
        let (rr, rl) = fullFixture()
        let text = ReportWriter.render(report: rr, live: rl, history: hist)
        do { try ReportWriter.write(text: text, to: file) } catch { check(false, "ReportWriter: E3 round-trip threw \(error)") }
        check((try? Data(contentsOf: file)) == Data(text.utf8), "ReportWriter: E3 full Cyrillic report round-trips byte-exact")

        // E4 no leftovers
        check((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["mac_report.txt"], "ReportWriter: E4 no temp files left next to the report")

        // E5 parent is a regular file
        let blocker = root.appendingPathComponent("blocker")
        FileManager.default.createFile(atPath: blocker.path, contents: Data("keep".utf8))
        var threw5 = false
        do { try ReportWriter.write(text: "x", to: blocker.appendingPathComponent("mac_report.txt")) } catch { threw5 = true }
        check(threw5, "ReportWriter: E5 write throws when the parent is a regular file")
        check((try? Data(contentsOf: blocker)) == Data("keep".utf8), "ReportWriter: E5 blocker file unchanged")

        // E6 destination is a non-empty directory
        let target = root.appendingPathComponent("isdir").appendingPathComponent("mac_report.txt")
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: target.appendingPathComponent("inner.txt").path, contents: Data("keep".utf8))
        } catch { check(false, "ReportWriter: E6 setup threw \(error)") }
        var threw6 = false
        do { try ReportWriter.write(text: "x", to: target) } catch { threw6 = true }
        check(threw6, "ReportWriter: E6 write throws when the destination is a non-empty directory")
        check((try? Data(contentsOf: target.appendingPathComponent("inner.txt"))) == Data("keep".utf8), "ReportWriter: E6 directory content unchanged")
    }
}
