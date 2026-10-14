// Tests/MacDashboardTests/AttentionModelTests.swift
// Port of Checks/main.swift lines 2129-2376 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

// A "full-bad" fixture that trips every branch except disk (parameterized: disk.pct
// picks diskFull vs. diskFullSoon — see below).
private func attnFullBadFixture(diskPct: Double) -> (FullReport, LiveSnapshot) {
    var report = FullReport()
    report.security = SecurityState(fileVault: false, gatekeeper: false, sip: false, firewall: false)
    report.updates = ["u1"]
    report.crashes = [CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir)]
    report.tmDest = .some(.none)
    report.smart = [
        SmartDisk(device: "internal", title: "Boot SSD", status: "SMART: ошибки носителя",
                  attrs: [("Media and Data Integrity Errors", "3")], severity: .crit),
        SmartDisk(device: "/dev/disk4", title: "External SSD", status: "SMART: износ на исходе",
                  attrs: [("Percentage Used", "85")], severity: .warn),
    ]
    report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: nil, condition: "Replace Now", maxCapacity: 60)
    var live = LiveSnapshot()
    let size: Int64 = 256 * GIB
    live.disk = DiskInfo(size: size, avail: Int64(Double(size) * (1 - diskPct)), dataUsed: nil, sysUsed: nil)
    let swapUsed = 5 * GIB
    live.swap = SwapInfo(total: 8 * GIB, used: swapUsed, free: 3 * GIB)
    live.mem = memFixture(total: 16 * GIB)
    return (report, live)
}

// A broader fixture that also trips tip/capsule-producing branches, for the verb,
// parity and regression checks below (these don't need all 16 AttentionKinds, just
// a healthy mix of items+capsules with both nil and non-nil actions).
private func attnMegaBadFixture() -> (FullReport, LiveSnapshot) {
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

extension SerialTests {
    struct AttentionModelTests {
        @Test func attentionModel() async {
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
                    #expect(AttentionModel.summaryTitle(count: n, lang: .ru) == expected,
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
                    #expect(AttentionModel.summaryTitle(count: n, lang: .en) == expected,
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
                    #expect(AttentionModel.summaryTitle(count: n, lang: .ru) == expected,
                          "AttentionModel.summaryTitle ru(\(n)) == '\(expected)'")
                }

                // negative counts clamp to 0
                #expect(AttentionModel.summaryTitle(count: -3, lang: .ru) == "Всё в порядке",
                      "AttentionModel.summaryTitle ru(-3) clamps to 0 -> 'Всё в порядке'")
            }

            // 4. QuietState.quiet(report:) truth table
            do {
                var report = FullReport()
                report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)
                #expect(QuietState.quiet(report: report).securityQuiet, "QuietState: all-true security -> securityQuiet true")

                report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
                #expect(!QuietState.quiet(report: report).securityQuiet, "QuietState: one field false -> securityQuiet false")

                report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: nil)
                #expect(!QuietState.quiet(report: report).securityQuiet, "QuietState: one field nil -> securityQuiet false")

                report.security = nil
                #expect(!QuietState.quiet(report: report).securityQuiet, "QuietState: report.security == nil -> securityQuiet false")

                var r2 = FullReport()
                r2.updates = []; r2.crashes = []
                #expect(QuietState.quiet(report: r2).updatesQuiet, "QuietState: updates=[] & crashes=[] -> updatesQuiet true")

                r2.updates = nil; r2.crashes = []
                #expect(!QuietState.quiet(report: r2).updatesQuiet, "QuietState: updates=nil -> updatesQuiet false")

                r2.updates = []; r2.crashes = nil
                #expect(!QuietState.quiet(report: r2).updatesQuiet, "QuietState: crashes=nil -> updatesQuiet false")

                r2.updates = ["u1"]; r2.crashes = []
                #expect(!QuietState.quiet(report: r2).updatesQuiet, "QuietState: updates non-empty -> updatesQuiet false")
            }

            // 5. Every AttentionKind produces non-empty label/detail/fullText in both languages.
            do {
                // diskFull and diskFullSoon share one `if/else if` on the same live.disk.pct
                // (Assessment.swift), so no single report can trip both; two fixtures that
                // differ only in disk% cover all 16 kinds between them.
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }

                for lang in AppLanguage.allCases {
                    L10nStore.shared.language = lang
                    let (reportFull, liveFull) = attnFullBadFixture(diskPct: 0.94)   // -> diskFull
                    let (reportSoon, liveSoon) = attnFullBadFixture(diskPct: 0.80)   // -> diskFullSoon
                    let itemsFull = Assess.assess(report: reportFull, live: liveFull, memPressure: .critical, wakeHolders: [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)], claudeBackup: .noSuccessFound).items
                    let itemsSoon = Assess.assess(report: reportSoon, live: liveSoon, memPressure: .critical, wakeHolders: [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)], claudeBackup: .noSuccessFound).items
                    let allItems = itemsFull + itemsSoon
                    let kinds = Set(allItems.map(\.kind))
                    #expect(kinds.count == AttentionKind.allCases.count, "AttentionModel coverage (\(lang)): all \(AttentionKind.allCases.count) AttentionKind cases produced (got \(kinds.count))")
                    for item in allItems {
                        #expect(!item.label.isEmpty, "AttentionModel coverage (\(lang)): \(item.kind.rawValue) label non-empty")
                        #expect(!item.detail.isEmpty, "AttentionModel coverage (\(lang)): \(item.kind.rawValue) detail non-empty")
                        #expect(!item.fullText.isEmpty, "AttentionModel coverage (\(lang)): \(item.kind.rawValue) fullText non-empty")
                    }
                }
            }

            do {
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }
                L10nStore.shared.language = .ru

                let (report, live) = attnMegaBadFixture()
                let a = Assess.assess(report: report, live: live, memPressure: .critical)

                // 6. Verb rule.
                for item in a.items {
                    if item.action == nil {
                        #expect(item.verb.isEmpty, "AttentionModel verb rule: \(item.kind.rawValue) action==nil -> verb == ''")
                    } else {
                        #expect(!item.verb.isEmpty, "AttentionModel verb rule: \(item.kind.rawValue) action!=nil -> verb non-empty")
                    }
                    if !item.verb.isEmpty {
                        #expect(!item.detail.contains(item.verb), "AttentionModel verb rule: \(item.kind.rawValue) detail does not contain its verb")
                    }
                }
                for capsule in a.capsules {
                    if capsule.action == nil {
                        #expect(capsule.verb.isEmpty, "AttentionModel verb rule: capsule '\(capsule.object)' action==nil -> verb == ''")
                    } else {
                        #expect(!capsule.verb.isEmpty, "AttentionModel verb rule: capsule '\(capsule.object)' action!=nil -> verb non-empty")
                    }
                    if !capsule.verb.isEmpty {
                        #expect(!capsule.value.contains(capsule.verb), "AttentionModel verb rule: capsule '\(capsule.object)' value does not contain its verb")
                    }
                }
                #expect(!a.items.isEmpty && !a.capsules.isEmpty, "AttentionModel verb rule: fixture produced both items and capsules")

                // 7. Parity between problems/items and tips/capsules.
                #expect(a.items.count == a.problems.count, "AttentionModel parity: items.count == problems.count")
                var parityOK = a.items.count == a.problems.count
                for i in 0..<min(a.items.count, a.problems.count) {
                    if a.items[i].sev != a.problems[i].sev || a.items[i].fullText != a.problems[i].text { parityOK = false }
                }
                #expect(parityOK, "AttentionModel parity: items[i].sev/fullText == problems[i].sev/text for every index")
                #expect(a.capsules.count == a.tips.count, "AttentionModel parity: capsules.count == tips.count")

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
                #expect(sevRanks == sevRanks.sorted(by: >), "AttentionModel regression guard: problems.map(sev) non-increasing (crit -> serious -> warn)")
                #expect(a.summaryText == "Замечаний: \(a.problems.count)", "AttentionModel regression guard: summaryText form unchanged")
            }

            // 9. QuietState three-state SectionStatus (.collecting / .quiet / .loud)
            do {
                var report = FullReport()
                report.security = nil
                #expect(QuietState.quiet(report: report).security == .collecting, "QuietState: security==nil -> .collecting")

                report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)
                #expect(QuietState.quiet(report: report).security == .quiet, "QuietState: all four true -> .quiet")

                report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
                do {
                    let qs = QuietState.quiet(report: report)
                    #expect(qs.security == .loud, "QuietState: one field false -> .loud")
                    #expect(qs.securityOffCount == 1 && qs.securityUnknownCount == 0, "QuietState: one field false -> offCount 1, unknownCount 0")
                }

                report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: nil)
                do {
                    let qs = QuietState.quiet(report: report)
                    #expect(qs.security == .loud, "QuietState: one field nil (rest true) -> .loud")
                    #expect(qs.securityUnknownCount == 1 && qs.securityOffCount == 0, "QuietState: one field nil -> unknownCount 1, offCount 0")
                }

                var r2 = FullReport()
                r2.updates = nil; r2.crashes = []
                #expect(QuietState.quiet(report: r2).updates == .collecting, "QuietState: updates==nil -> .collecting")

                r2.updates = []; r2.crashes = nil
                #expect(QuietState.quiet(report: r2).updates == .collecting, "QuietState: crashes==nil -> .collecting")

                r2.updates = []; r2.crashes = []
                #expect(QuietState.quiet(report: r2).updates == .quiet, "QuietState: updates=[] & crashes=[] -> .quiet")

                r2.updates = ["u1", "u2"]; r2.crashes = []
                do {
                    let qs = QuietState.quiet(report: r2)
                    #expect(qs.updates == .loud, "QuietState: 2 updates + 0 crashes -> .loud")
                    #expect(qs.updatesCount == 2 && qs.crashesCount == 0, "QuietState: 2 updates + 0 crashes -> counts (2, 0)")
                }

                r2.updates = []; r2.crashes = [CrashGroup(process: "diffscore", count: 6, directory: userCrashDir)]
                do {
                    let qs = QuietState.quiet(report: r2)
                    #expect(qs.updates == .loud, "QuietState: system crashes -> .loud (informational card stays)")
                    #expect(qs.crashesCount == 6, "QuietState: crashesCount counts reports, not groups")
                }
            }
        }
    }
}
