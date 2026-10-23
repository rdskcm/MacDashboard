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
