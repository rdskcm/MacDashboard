// Tests/MacDashboardTests/ReportWriterTests.swift
// Behaviour checks for Engine/ReportWriter.swift (REDESIGN-REPORT): the short report format in EN and RU,
// missing sections, task lines, key padding, parse-failure tail, helpers, and the data-integrity / error
// paths of ReportWriter.write. All writes go to a fresh temp directory that is removed afterwards;
// nothing here touches the user's App Support.
import Foundation
import Testing
@testable import MacDashboard

private func rwMode(_ path: String) -> UInt16? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let mode = attrs[.posixPermissions] as? NSNumber else { return nil }
    return mode.uint16Value & 0o777
}

private func pad(_ s: String, _ w: Int) -> String { s + String(repeating: " ", count: max(0, w - s.count)) }

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
    #expect(allPresent, "ReportWriter: \(tag) every section header present")
    let ints = idx.compactMap { $0 }
    let increasing = zip(ints, ints.dropFirst()).allSatisfy { $0 < $1 }
    #expect(allPresent && increasing, "ReportWriter: \(tag) section headers in fixed order")
    let headerCount = lines.filter { $0.hasPrefix("===== ") }.count
    #expect(headerCount == names.count, "ReportWriter: \(tag) each header exactly once (got \(headerCount))")
}


/// The short report with the full diagnostic sections appended (REDESIGN-REPORT fix wave 2).
private func renderDetails(_ r: FullReport, _ l: LiveSnapshot) -> String {
    var i = emptyInput()
    i.parseFailures = r.parseFailures + l.parseFailures
    i.details = ReportDetails(report: r, live: l)
    return ReportWriter.render(i)
}

private func upd(_ label: String) -> SoftwareUpdate {
    SoftwareUpdate(label: label, title: label, version: nil, sizeBytes: nil, restartRequired: false)
}

private let rwGiB: Int64 = 1 << 30

private func rwDate() -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    return cal.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 18, minute: 37, second: 3))!
}

/// Two tasks (one hot, one amber) built through the real task builder.
private func rwTasks() -> [HomeTask] {
    var a = Assessment()
    a.items = [
        AttentionItem(kind: .smartErrors, sev: .crit, label: "", detail: "", fullText: "", verb: ""),
        AttentionItem(kind: .firewallOff, sev: .warn, label: "", detail: "", fullText: "", verb: ""),
    ]
    return HomeModel.tasks(a, report: FullReport(), disk: nil, battery: nil)
}

private func fullInput() -> ReportSummaryInput {
    let at = rwDate()
    let tasks = rwTasks()
    return ReportSummaryInput(
        generatedAt: at,
        system: SystemInfo(osName: "macOS", osVersion: "26.1", osBuild: "25B78", modelName: "MacBook Air",
                           modelId: "Mac15,12", chip: "Apple M3", cores: nil, memBytes: nil, uptime: "3 d 4 h", hostName: nil),
        status: .critical, tasks: tasks,
        cpu: CPUUsage(user: 18.5, sys: 7.2, idle: 74.3), load: [2.10, 1.85, 1.60], ncpu: 8, socTempC: 48,
        mem: MemSnapshot(total: 16 * rwGiB, pageSize: 16384, free: 0, active: 7 * rwGiB, inactive: 0, speculative: 0,
                         wired: 2 * rwGiB, compressor: rwGiB / 2, purgeable: 0, fileBacked: 0),
        memPressure: .normal, swap: SwapInfo(total: 2 * rwGiB, used: 512 << 20, free: 0),
        disk: DiskInfo(size: 494_400_000_000, avail: 187_600_000_000, purgeable: 19_700_000_000),
        hasBattery: true, battery: BatteryInfo(source: nil, charge: 82, state: "charging", cycles: 412, condition: nil, maxCapacity: 88),
        security: SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false),
        claudeBackup: .lastSuccess(at.addingTimeInterval(-5 * 3600)), snapshotCount: 3, now: at, parseFailures: [])
}

private func emptyInput() -> ReportSummaryInput {
    let at = rwDate()
    return ReportSummaryInput(
        generatedAt: at, system: nil, status: .good, tasks: [], cpu: nil, load: nil, ncpu: 8, socTempC: nil,
        mem: nil, memPressure: nil, swap: nil, disk: nil, hasBattery: false, battery: nil, security: nil,
        claudeBackup: nil, snapshotCount: nil, now: at, parseFailures: [])
}

extension SerialTests {
    struct ReportWriterTests {
        @Test func renderEN() {
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            L10nStore.shared.language = .en
            let tasks = rwTasks()
            let k = { (s: String) in pad(s, 16) }
            let lines = [
                "MacDashboard report — MacBook Air (Apple M3)",
                "Generated Jul 3, 2026, 18:37 · macOS 26.1 (25B78)",
                "",
                k("STATUS") + "Critical · 2 tasks",
                "  !! " + pad(tasks[0].object, 14) + tasks[0].state,
                "  !  " + pad(tasks[1].object, 14) + tasks[1].state,
                "",
                k("CPU") + "25.7% · load 2.10 · 8 cores · SoC 48 °C",
                k("MEMORY") + "9.5 of 16 GB · pressure low · swap 512 MB",
                k("STORAGE") + "187.6 of 494.4 GB free · purgeable 19.7 GB",
                k("BATTERY") + "82%, charging · capacity 88% · 412 cycles",
                k("SECURITY") + "FileVault · Gatekeeper · SIP · Firewall off",
                k("BACKUPS") + "Claude backup 5 h ago · 3 local snapshots",
                k("UPTIME") + "3 d 4 h",
            ]
            let want = lines.joined(separator: "\n") + "\n"
            let got = ReportWriter.render(fullInput())
            #expect(got == want, "renderEN: \(got)")
            #expect(tasks[0].tone == .hot && tasks[1].tone == .amber, "renderEN: task tones")
        }

        @Test func renderRU() {
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            L10nStore.shared.language = .ru
            let out = ReportWriter.render(fullInput())
            let rows = out.components(separatedBy: "\n")
            let k = { (s: String) in pad(s, 16) }
            #expect(rows[0] == "Отчёт MacDashboard — MacBook Air (Apple M3)", "renderRU title (got \(rows[0]))")
            // The month word comes from the system CLDR data: «июл.» or «июля» depending on the macOS version.
            #expect(rows[1].hasPrefix("Создан 3 июл") && rows[1].contains(" 2026, 18:37 · macOS 26.1 (25B78)"),
                    "renderRU generated line (got \(rows[1]))")
            for key in ["СОСТОЯНИЕ", "ПРОЦЕССОР", "ПАМЯТЬ", "ХРАНИЛИЩЕ", "БАТАРЕЯ", "ЗАЩИТА", "КОПИИ", "АПТАЙМ"] {
                #expect(rows.contains { $0.hasPrefix(k(key)) && $0.count > 16 }, "renderRU key \(key) padded to 16")
            }
            #expect(rows.contains(k("ПРОЦЕССОР") + "25,7 % · нагрузка 2,10 · 8 ядер · SoC 48 °C"), "renderRU CPU")
            #expect(rows.contains(k("ПАМЯТЬ") + "9,5 из 16 ГБ · давление низкое · swap 512 МБ"), "renderRU MEMORY")
            #expect(rows.contains(k("ХРАНИЛИЩЕ") + "свободно 187,6 из 494,4 ГБ · очищаемое 19,7 ГБ"), "renderRU STORAGE")
            #expect(rows.contains(k("БАТАРЕЯ") + "82 %, charging · ёмкость 88 % · 412 циклов"), "renderRU BATTERY")
            #expect(rows.contains(k("ЗАЩИТА") + "FileVault · Gatekeeper · SIP · брандмауэр выкл."), "renderRU SECURITY")
            #expect(rows.contains(k("КОПИИ") + "Бэкап Claude 5 ч назад · 3 локальных снимка"), "renderRU BACKUPS")
        }

        @Test func renderSecurityOffAndUnknown() {
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            var input = fullInput()
            input.security = SecurityState(fileVault: false, gatekeeper: true, sip: nil, firewall: true)
            let k = { (s: String) in pad(s, 16) }
            L10nStore.shared.language = .en
            #expect(ReportWriter.render(input).components(separatedBy: "\n")
                .contains(k("SECURITY") + "FileVault off · Gatekeeper · SIP ? · Firewall"), "security EN off/unknown")
            L10nStore.shared.language = .ru
            #expect(ReportWriter.render(input).components(separatedBy: "\n")
                .contains(k("ЗАЩИТА") + "FileVault выкл. · Gatekeeper · SIP ? · брандмауэр"), "security RU off/unknown")
        }

        @Test func renderMissing() {
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            L10nStore.shared.language = .en
            let out = ReportWriter.render(emptyInput())
            let rows = out.components(separatedBy: "\n")
            let k = { (s: String) in pad(s, 16) }
            #expect(rows[0] == "MacDashboard report — Mac", "renderMissing title")
            #expect(rows[1] == "Generated Jul 3, 2026, 18:37", "renderMissing generated line has no macOS part (got \(rows[1]))")
            #expect(rows[3] == k("STATUS") + "All good", "renderMissing status has no task count (got \(rows[3]))")
            #expect(rows[4] == "", "renderMissing blank after status without task lines")
            #expect(rows[5] == k("CPU") + "—" && rows[6] == k("MEMORY") + "—" && rows[7] == k("STORAGE") + "—", "renderMissing dashes")
            #expect(rows[8] == k("BATTERY") + L.reportNoBattery, "renderMissing no battery")
            #expect(rows[9] == k("SECURITY") + "—" && rows[10] == k("BACKUPS") + "—" && rows[11] == k("UPTIME") + "—", "renderMissing dashes 2")
            #expect(out.hasSuffix("—\n") && !out.hasSuffix("\n\n"), "renderMissing ends with exactly one newline")
        }

        @Test func renderNoBatteryValues() {
            var i = emptyInput()
            i.hasBattery = true
            i.battery = BatteryInfo()
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            L10nStore.shared.language = .en
            #expect(ReportWriter.render(i).contains(pad("BATTERY", 16) + "—\n"), "renderNoBatteryValues: all-nil battery is a dash")
        }

        @Test func renderLongObject() {
            var i = emptyInput()
            var task = rwTasks()[0]
            task = HomeTask(id: task.id, kind: task.kind, tone: .hot, object: "0123456789abcdef", state: "bad", section: task.section,
                            destination: task.destination, verb: nil, help: "", tileTag: "", legacyAction: nil, wakeHolderKeys: [])
            i.tasks = [task]
            i.status = .critical
            #expect(ReportWriter.render(i).contains("  !! 0123456789abcdef bad\n"), "renderLongObject: exactly one space before the state")
        }

        @Test func renderParseFailures() {
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            L10nStore.shared.language = .en
            var i = emptyInput()
            i.parseFailures = [ParseFailure(.spHardware, stdout: "{\n\"SPHardwareDataType\" : 5\n}")!]
            let out = ReportWriter.render(i)
            let tail = "UPTIME          —\n\n===== \(L.reportSectionUnparsed) =====\n"
            #expect(out.contains(tail), "renderParseFailures: tail after the UPTIME row")
            #expect(out.contains("$ system_profiler -json SPHardwareDataType"), "renderParseFailures: command line")
            i.parseFailures = []
            #expect(!ReportWriter.render(i).contains(L.reportSectionUnparsed), "renderParseFailures: absent without failures")
        }

        @Test func detailsAppended() async {
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            L10nStore.shared.language = .ru

            let gib: Int64 = 1 << 30
            let mib: Int64 = 1 << 20
            let tib: Int64 = 1 << 40
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let t = cal.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 18, minute: 37, second: 3))!

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
                r.updates = [upd("macOS Tahoe 26.0.1")]
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
            let out = renderDetails(fr, flive)
            let u = reportUpdatedTimeString(t)
            do {
                func sec(_ name: String, _ body: [String], _ label: String) {
                    let got = rwSection(out, name)
                    let ok = got == body
                    #expect(ok, Comment(rawValue: "ReportWriter: \(label) populated body" + (ok ? "" : " (got \(String(describing: got)))")))
                }
                sec(L.reportSectionSystem, ["ProductName:\tmacOS", "ProductVersion:\t26.0", "BuildVersion:\t25A354", "      Model Name: MacBook Air", "      Model Identifier: Mac15,12", "      Chip: Apple M3", "      Total Number of Cores: 8 (4 performance and 4 efficiency)", "      Memory: 16,0 ГБ", L.reportUptime("2 дня 3 мин")], "SYSTEM")
                sec(L.reportSectionDisk, [diskHeader(),
                                          diskRow("/", "500,0 ГБ", "12,0 ГБ", "100,0 ГБ", "2%", "/"),
                                          diskRow("/System/Volumes/Data", "500,0 ГБ", "350,0 ГБ", "100,0 ГБ", "70%", "/System/Volumes/Data")], "DISK")
                sec(L.reportSectionSnapshots, ["com.apple.TimeMachine.2026-07-03-183000.local"], "SNAPSHOTS")
                let hd = rwSection(out, L.reportSectionHomeDirs) ?? []
                #expect(hd.count == 22, "ReportWriter: HOMEDIRS 22 lines (got \(hd.count))")
                if hd.count == 22 {
                    #expect(hd[0] == "    1,0 КБ  /Users/u/d01", "ReportWriter: HOMEDIRS first row")
                    #expect(hd[19] == "   20,0 КБ  /Users/u/d20", "ReportWriter: HOMEDIRS 20th row")
                    #expect(!hd.contains { $0.contains("/Users/u/d21") }, "ReportWriter: HOMEDIRS capped at 20")
                    #expect(hd[20] == L.storageFoldersNoFDA("/Users/u/Library/Mail"), "ReportWriter: HOMEDIRS unreadable line")
                    #expect(hd[21] == L.reportFoldersCountedAt(u), "ReportWriter: HOMEDIRS counted-at line")
                } else {
                    Issue.record("ReportWriter: HOMEDIRS row checks skipped (wrong line count)")
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

                // R3: order, uniqueness, tail rows, EN pass
                rwCheckOrder(out, "RU")
                let tailRows = out.components(separatedBy: "\n")
                let uptimeAt = tailRows.firstIndex { $0.hasPrefix(pad(L.reportKeyUptime, 16)) }
                let systemAt = tailRows.firstIndex(of: "===== \(L.reportSectionSystem) =====")
                let timingsAt = tailRows.firstIndex(of: "===== \(L.reportSectionTimings) =====")
                let unparsedAt = tailRows.firstIndex(of: "===== \(L.reportSectionUnparsed) =====")
                #expect(uptimeAt != nil && systemAt != nil && uptimeAt! < systemAt!, "ReportWriter: details start after the UPTIME row")
                #expect(timingsAt != nil && unparsedAt != nil && timingsAt! < unparsedAt!, "ReportWriter: parse-failure tail after the details")
                #expect(out.hasSuffix("\n") && !out.hasSuffix("\n\n"), "ReportWriter: ends with exactly one newline")
                #expect(!out.contains("===== ГОТОВО") && !out.contains("===== DONE") && !out.contains("Отчёт сохранён"), "ReportWriter: no DONE banner or saved-to footer")

                L10nStore.shared.language = .en
                let outEN = renderDetails(fr, flive)
                rwCheckOrder(outEN, "EN")
                #expect(rwSection(outEN, L.reportSectionSystem)?.contains("      Memory: 16.0 GB") == true, "ReportWriter: EN memory uses dot decimal and GB")
                L10nStore.shared.language = .ru
            }

            // ---- §C: variants ----
            do {
                func render(_ f: (inout FullReport, inout LiveSnapshot) -> Void) -> String {
                    var r = FullReport()
                    var l = LiveSnapshot()
                    r.createdAt = t
                    f(&r, &l)
                    return renderDetails(r, l)
                }
                func eq(_ o: String, _ name: String, _ body: [String], _ label: String) {
                    let got = rwSection(o, name)
                    let ok = got == body
                    #expect(ok, Comment(rawValue: "ReportWriter: \(label)" + (ok ? "" : " (got \(String(describing: got)))")))
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
                #expect(StringsRU().storageFoldersNotMeasured("X") == "Не успели измерить: X." && StringsEN().storageFoldersNotMeasured("X") == "Not measured in time: X.", "SERVICE-DIRS-TIMEOUT: RU/EN not-measured strings")
                eq(render { _, l in l.mem = nil; l.swap = SwapInfo(total: 0, used: 0, free: 0) }, L.reportSectionMemory,
                   ["Mach Virtual Memory Statistics: \(L.sharedUnavailable)", "vm.swapusage: total = 0.00M  used = 0.00M  free = 0.00M"], "C7 nil mem, zero swap")
                let c8 = rwSection(render { _, l in
                    l.mem = MemSnapshot(total: 0, pageSize: 0, free: 4096, active: 0, inactive: 0, speculative: 0, wired: 0, compressor: 0, purgeable: 0, fileBacked: 0)
                    l.swap = nil
                }, L.reportSectionMemory) ?? []
                #expect(c8.count == 10 && c8[0] == "Mach Virtual Memory Statistics: (page size of 0 bytes)" && c8[1] == rwVM("Pages free", 0)
                      && c8.last == "vm.swapusage: \(L.sharedUnavailable)", "ReportWriter: C8 page size 0, nil swap (got \(c8))")
                let c9 = rwSection(render { _, l in
                    l.topMem = (1...12).map { ProcEntry(name: "proc-" + String(format: "%02d", $0), cpu: 1.0, memBytes: mib) }
                }, L.reportSectionTopMem) ?? []
                #expect(c9.count == 11 && c9.last!.hasSuffix("proc-10") && !c9.contains { $0.hasSuffix("proc-11") }, "ReportWriter: C9 top-10 cap (count \(c9.count))")
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
                #expect(c18.count == 15 && c18.last == L.maintenanceCrashRow("c15", 1), "ReportWriter: C18 crashes cap 15 (count \(c18.count))")
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
        }

        @Test func padHelpers() {
            let tib: Int64 = 1 << 40
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            L10nStore.shared.language = .ru
            do {
                let fb: [(Int64, String)] = [(0, "0 Б"), (1023, "1023 Б"), (1024, "1,0 КБ"), (1536, "1,5 КБ"), (-2048, "-2,0 КБ"),
                                             (5 * tib, "5,0 ТБ"), (1024 * tib, "1024,0 ТБ"), (Int64.min, "-8388608,0 ТБ")]
                for (n, want) in fb {
                    let got = ReportWriter.fmtBytes(n)
                    #expect(got == want, "ReportWriter: fmtBytes(\(n)) == \(want) (got \(got))")
                }
                #expect(ReportWriter.padRight("abc", 5) == "abc  ", "ReportWriter: padRight pads")
                #expect(ReportWriter.padRight("abcdef", 3) == "abcdef", "ReportWriter: padRight never truncates")
                #expect(ReportWriter.padLeft("7", 3) == "  7", "ReportWriter: padLeft pads")
                #expect(ReportWriter.padLeft("abcd", 2) == "abcd", "ReportWriter: padLeft never truncates")
            }
        }

        @Test func smartHelpers() {
            let originalLang = L10nStore.shared.language
            defer { L10nStore.shared.language = originalLang }
            L10nStore.shared.language = .ru
            do {
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
                    #expect(got == want, "ReportWriter: smartCriticalWarningRU(\(raw.debugDescription)) (got \(got.debugDescription))")
                }

                let now = Date(timeIntervalSince1970: 1_760_000_000)
                #expect(folderSizesAgeString(countedAt: now.addingTimeInterval(-60), now: now) == L.foldersCountedAgo("1 \(L.uptimeUnitMinute)"), "ReportWriter: folderSizesAgeString 1 minute")
                #expect(folderSizesAgeString(countedAt: now.addingTimeInterval(-2 * 3600), now: now) == L.foldersCountedAgo("2 \(L.uptimeUnitHour)"), "ReportWriter: folderSizesAgeString 2 hours")
                #expect(folderSizesAgeString(countedAt: now.addingTimeInterval(-3 * 86_400), now: now) == L.foldersCountedAgo("3 \(L.uptimeUnitDay)"), "ReportWriter: folderSizesAgeString 3 days")
            }
        }

        @Test func writeIntegrity() {
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
                } catch { Issue.record("ReportWriter: E1 overwrite threw \(error)") }
                #expect((try? Data(contentsOf: file)) == Data("new".utf8), "ReportWriter: E1 overwrite leaves exactly the new bytes")

                // E2 pre-existing 0644 file
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
                #expect(rwMode(file.path) == 0o644, "ReportWriter: E2 precondition, file is 0644")
                do { try ReportWriter.write(text: "again", to: file) } catch { Issue.record("ReportWriter: E2 rewrite threw \(error)") }
                #expect(rwMode(file.path) == 0o600, "ReportWriter: E2 rewritten file is 0600 (got \(String(describing: rwMode(file.path))))")
                #expect((try? Data(contentsOf: file)) == Data("again".utf8), "ReportWriter: E2 content after rewrite")

                // E3 round-trip
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }
                L10nStore.shared.language = .ru
                let text = ReportWriter.render(fullInput())
                do { try ReportWriter.write(text: text, to: file) } catch { Issue.record("ReportWriter: E3 round-trip threw \(error)") }
                #expect((try? Data(contentsOf: file)) == Data(text.utf8), "ReportWriter: E3 short Cyrillic report round-trips byte-exact")

                // E4 no leftovers
                #expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["mac_report.txt"], "ReportWriter: E4 no temp files left next to the report")

                // E5 parent is a regular file
                let blocker = root.appendingPathComponent("blocker")
                FileManager.default.createFile(atPath: blocker.path, contents: Data("keep".utf8))
                var threw5 = false
                do { try ReportWriter.write(text: "x", to: blocker.appendingPathComponent("mac_report.txt")) } catch { threw5 = true }
                #expect(threw5, "ReportWriter: E5 write throws when the parent is a regular file")
                #expect((try? Data(contentsOf: blocker)) == Data("keep".utf8), "ReportWriter: E5 blocker file unchanged")

                // E6 destination is a non-empty directory
                let target = root.appendingPathComponent("isdir").appendingPathComponent("mac_report.txt")
                do {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: target.appendingPathComponent("inner.txt").path, contents: Data("keep".utf8))
                } catch { Issue.record("ReportWriter: E6 setup threw \(error)") }
                var threw6 = false
                do { try ReportWriter.write(text: "x", to: target) } catch { threw6 = true }
                #expect(threw6, "ReportWriter: E6 write throws when the destination is a non-empty directory")
                #expect((try? Data(contentsOf: target.appendingPathComponent("inner.txt"))) == Data("keep".utf8), "ReportWriter: E6 directory content unchanged")
            }
        }
    }
}
