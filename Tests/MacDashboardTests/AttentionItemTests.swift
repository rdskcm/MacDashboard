// Tests/MacDashboardTests/AttentionItemTests.swift
// Port of Checks/main.swift lines 2129-2376 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

// A "full-bad" fixture that trips every branch except disk (parameterized: disk.pct
// picks diskFull vs. diskFullSoon — see below).
private func attnFullBadFixture(diskPct: Double) -> (FullReport, LiveSnapshot) {
    var report = FullReport()
    report.security = SecurityState(fileVault: false, gatekeeper: false, sip: false, firewall: false)
    report.updates = [upd("u1")]
    report.crashes = [CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir)]
    report.tmDest = .some(.none)
    report.smart = [
        SmartDisk(device: "internal", title: "Boot SSD", status: .mediaErrors,
                  attrs: [("Media and Data Integrity Errors", "3")], severity: .crit),
        SmartDisk(device: "/dev/disk4", title: "External SSD", status: .wearHigh,
                  attrs: [("Percentage Used", "85")], severity: .warn),
    ]
    report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: nil, condition: "Replace Now", maxCapacity: 60)
    report.brewOutdated = ["pkg1"]
    var live = LiveSnapshot()
    let size: Int64 = 256 * GIB
    live.disk = DiskInfo(size: size, avail: Int64(Double(size) * (1 - diskPct)), dataUsed: nil, sysUsed: nil)
    let swapUsed = 5 * GIB
    live.swap = SwapInfo(total: 8 * GIB, used: swapUsed, free: 3 * GIB)
    live.mem = memFixture(total: 16 * GIB)
    return (report, live)
}

// A broader fixture that trips more AttentionItem-producing branches, for the parity
// and regression checks below (these do not need all 17 AttentionKinds, just a healthy
// mix of items with both nil and non-nil actions).
private func attnMegaBadFixture() -> (FullReport, LiveSnapshot) {
    var (report, live) = attnFullBadFixture(diskPct: 0.94)
    report.brewOutdated = ["pkg1", "pkg2", "pkg3"]
    report.smart?.append(SmartDisk(device: "/dev/disk5", title: "External HDD", status: .noAccess,
                                    attrs: [], severity: .warn))
    report.homeDirs = [
        DirSize(path: "/Users/x/Downloads", bytes: 11 * GIB),
        DirSize(path: "/Users/x/.Trash", bytes: 2 * GIB),
    ]
    report.homeCaches = DirSize(path: FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Caches", bytes: 4 * GIB)
    return (report, live)
}

extension SerialTests {
    struct AttentionItemTests {
        @Test func attentionModel() async {
            // =====================================================================
            // MARK: - AttentionItem
            // =====================================================================

            // 5. Every AttentionKind produces non-empty label/detail/fullText in both languages.
            do {
                // diskFull and diskFullSoon share one `if/else if` on the same live.disk.pct
                // (Assessment.swift), so no single report can trip both; two fixtures that
                // differ only in disk% cover all 17 kinds between them.
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }

                for lang in AppLanguage.allCases {
                    L10nStore.shared.language = lang
                    let (reportFull, liveFull) = attnFullBadFixture(diskPct: 0.94)   // -> diskFull
                    var (reportSoon, liveSoon) = attnFullBadFixture(diskPct: 0.87)   // 13 % = 35.7 GB -> diskFullSoon
                    // No report holds both TM kinds: this one carries the overdue kind, the 0.94 one `.timeMachine`.
                    var dest = TMDestination(name: "Backup", kind: "Local", mountPoint: "/Volumes/B", quotaBytes: nil, lastBackup: nil)
                    dest.lastBackupDate = Date().addingTimeInterval(-10 * 86_400)
                    reportSoon.tmDest = .some(.some(dest))
                    let itemsFull = Assess.assess(report: reportFull, live: liveFull, language: L10nStore.shared.language, memPressure: .critical, wakeHolders: [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)], claudeBackup: .noSuccessFound).items
                    let itemsSoon = Assess.assess(report: reportSoon, live: liveSoon, language: L10nStore.shared.language, memPressure: .critical, wakeHolders: [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)], claudeBackup: .noSuccessFound).items
                    let allItems = itemsFull + itemsSoon
                    let kinds = Set(allItems.map(\.kind))
                    #expect(kinds.count == AttentionKind.allCases.count, "AttentionItem coverage (\(lang)): all \(AttentionKind.allCases.count) AttentionKind cases produced (got \(kinds.count))")
                    for item in allItems {
                        #expect(!item.label.isEmpty, "AttentionItem coverage (\(lang)): \(item.kind.rawValue) label non-empty")
                        #expect(!item.detail.isEmpty, "AttentionItem coverage (\(lang)): \(item.kind.rawValue) detail non-empty")
                        #expect(!item.fullText.isEmpty, "AttentionItem coverage (\(lang)): \(item.kind.rawValue) fullText non-empty")
                        #expect(item.why != nil, "AttentionItem coverage (\(lang)): \(item.kind.rawValue) why non-nil")
                    }
                }
            }

            do {
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }
                L10nStore.shared.language = .ru

                let (report, live) = attnMegaBadFixture()
                let a = Assess.assess(report: report, live: live, language: L10nStore.shared.language, memPressure: .critical)

                #expect(!a.items.isEmpty, "AttentionItem regression guard: fixture produced items")

                // 8. Regression guard: crit > serious > warn ordering unchanged.
                func rankFor(_ s: Severity) -> Int {
                    switch s {
                    case .crit: return 3
                    case .serious: return 2
                    case .warn: return 1
                    default: return 0
                    }
                }
                let sevRanks = a.items.map { rankFor($0.sev) }
                #expect(sevRanks == sevRanks.sorted(by: >), "AttentionItem regression guard: items.map(sev) non-increasing (crit -> serious -> warn)")
            }
        }
    }
}

private func upd(_ label: String) -> SoftwareUpdate {
    SoftwareUpdate(label: label, title: label, version: nil, sizeBytes: nil, restartRequired: false)
}
