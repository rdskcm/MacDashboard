// Tests/MacDashboardTests/AssessmentTests.swift
// Port of Checks/main.swift lines 528-925 (CHECKS-SWIFT-TESTING). Memory math, Assess.assess and the advice actions.
import Foundation
import Testing
@testable import MacDashboard

private func diskLive(pct: Double, size: Int64 = 256 * GIB) -> LiveSnapshot {
    var live = LiveSnapshot()
    let avail = Int64(Double(size) * (1 - pct))
    live.disk = DiskInfo(size: size, avail: avail, dataUsed: nil, sysUsed: nil)
    return live
}

private func swapLive(usedBytes: Int64, ramTotal: Int64 = 16 * GIB, compressor: Int64 = 0) -> LiveSnapshot {
    var live = LiveSnapshot()
    live.swap = SwapInfo(total: 8 * GIB, used: usedBytes, free: 8 * GIB - usedBytes)
    live.mem = memFixture(total: ramTotal, compressor: compressor)
    return live
}
private func memItem(_ a: Assessment) -> AttentionItem? { a.items.first { $0.kind == .swapHigh } }

private func batteryReport(maxCapacity: Int?, condition: String? = nil, cycles: Int? = nil) -> FullReport {
    var report = FullReport()
    report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: cycles, condition: condition, maxCapacity: maxCapacity)
    return report
}

extension SerialTests {
    struct AssessmentTests {
        @Test func memoryMath() async {
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
                #expect(mem.usedBytes == mem.active + mem.wired + mem.compressor, "MemSnapshot: usedBytes == active+wired+compressor")
                #expect(mem.otherBytes >= 0, "MemSnapshot: otherBytes >= 0")
            }
        }

        @Test func assessment() async {
            // =====================================================================
            // MARK: - Assessment (SPEC §6)
            // =====================================================================

            do {
                let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.94))
                #expect(a.diskSev == .crit, "assess disk 94%: diskSev == .crit")
                #expect(a.problems.contains { $0.sev == .crit && $0.text.contains("срочно освободите место") },
                      "assess disk 94%: crit problem present")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.80))
                #expect(a.diskSev == .warn, "assess disk 80%: diskSev == .warn")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.50))
                #expect(a.diskSev == .good, "assess disk 50%: diskSev == .good")
                #expect(!a.problems.contains { $0.text.contains("Диск заполнен") }, "assess disk 50%: no disk problem")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.80, size: 4096 * GIB))
                #expect(a.diskSev == .good, "assess disk 4TiB@80%: diskSev == .good (R3, large volume quiet)")
                #expect(!a.problems.contains { $0.text.contains("Диск") } && !a.tips.contains { $0.text.contains("Диск") },
                      "assess disk 4TiB@80%: no disk problem or tip (R3)")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.99, size: 4096 * GIB))
                #expect(a.diskSev == .warn, "assess disk 4TiB@99% (41 GiB free): diskSev == .warn")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.995, size: 4096 * GIB))
                #expect(a.diskSev == .crit, "assess disk 4TiB@99.5% (20.5 GiB free): diskSev == .crit")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.86, size: 128 * GIB))
                #expect(a.diskSev == .crit, "assess disk 128GiB@86%: diskSev == .crit (R2 parity with old 0.85 constant)")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.72, size: 128 * GIB))
                #expect(a.diskSev == .warn, "assess disk 128GiB@72%: diskSev == .warn (R2 parity with old 0.70 constant)")
            }
            // MUTATION-SURVIVORS M04: free space exactly AT the critical floor is critical (<=, not <).
            // 256 GiB volume: 15 % = 38.4 GiB, so the 24 GiB upgrade-reserve cap is the floor.
            do {
                var live = LiveSnapshot()
                live.disk = DiskInfo(size: 256 * GIB, avail: 24 * GIB, dataUsed: nil, sysUsed: nil)
                let a = Assess.assess(report: FullReport(), live: live)
                #expect(a.diskSev == .crit, "assess disk 256GiB, avail == crit floor (24 GiB): diskSev == .crit (got \(a.diskSev))")
            }

            do {
                #expect(MemoryPressureLevel(sysctlValue: 1) == .normal, "MemoryPressureLevel: 1 -> normal")
                #expect(MemoryPressureLevel(sysctlValue: 2) == .warn, "MemoryPressureLevel: 2 -> warn")
                #expect(MemoryPressureLevel(sysctlValue: 4) == .critical, "MemoryPressureLevel: 4 -> critical")
                #expect(MemoryPressureLevel(sysctlValue: 0) == nil, "MemoryPressureLevel: 0 -> nil")
                #expect(MemoryPressureLevel(sysctlValue: 3) == nil, "MemoryPressureLevel: 3 -> nil")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 5 * GIB, ramTotal: 8 * GIB, compressor: 2 * GIB))
                #expect(memItem(a) == nil && a.swapSev == .good && !a.capsules.contains { $0.object == "Память" },
                      "assess with no memPressure: no item, swapSev good, no capsule (R5)")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 5 * GIB, ramTotal: 8 * GIB, compressor: 2 * GIB), memPressure: .normal)
                #expect(memItem(a) == nil && a.swapSev == .good, "assess with .normal pressure: no item, swapSev good (R4)")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), memPressure: .warn)
                #expect(memItem(a)?.sev == .warn && a.swapSev == .warn, "assess with .warn pressure, no swap: warn item (R4)")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), memPressure: .critical)
                #expect(memItem(a)?.sev == .serious && a.swapSev == .serious, "assess with .critical pressure: serious item")
            }
            do {
                let apps = [AppMemory(name: "Google Chrome", bytes: 3 * GIB), AppMemory(name: "Telegram", bytes: GIB)]
                let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), memPressure: .critical, topApps: apps)
                let expected = "Google Chrome (\(ReportWriter.fmtBytes(3 * GIB))) и Telegram (\(ReportWriter.fmtBytes(GIB)))"
                #expect(memItem(a)?.fullText.contains(expected) == true, "assess mem pressure text names top apps with sizes (R6)")
                let id1 = memItem(a)?.id
                let apps2 = [AppMemory(name: "Google Chrome", bytes: 3 * GIB), AppMemory(name: "Telegram", bytes: 2 * GIB)]
                let a2 = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), memPressure: .critical, topApps: apps2)
                #expect(memItem(a2)?.id == id1, "assess mem pressure item id stable across size changes (R7)")
                #expect(memItem(a)?.detail.contains("Swap") != true && memItem(a)?.detail.contains("сжат") != true,
                      "assess mem pressure detail has no swap/compressed mention (R7)")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), memPressure: .warn, topApps: [])
                #expect(memItem(a)?.fullText.contains("Закройте приложения") == true, "assess mem pressure, 0 apps: generic instruction")
                let a1 = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), memPressure: .warn,
                                        topApps: [AppMemory(name: "Google Chrome", bytes: GIB)])
                #expect(a1.items.first { $0.kind == .swapHigh }?.fullText.contains("занимает ") == true,
                      "assess mem pressure, 1 app: singular sentence")
            }
            do {
                #expect(LiveCollector.readMemoryPressure() != nil, "readMemoryPressure: sysctl readable on this Mac")
            }

            do {
                let a = Assess.assess(report: batteryReport(maxCapacity: 65), live: LiveSnapshot())
                #expect(a.problems.contains { $0.sev == .serious && $0.text.contains("Ёмкость") }, "assess battery 65%: serious")
            }
            do {
                let a = Assess.assess(report: batteryReport(maxCapacity: 78), live: LiveSnapshot())
                #expect(a.tips.contains { $0.text.contains("Ёмкость") }, "assess battery 78%, cycles == nil: tip (still warns)")
            }
            do {
                let a = Assess.assess(report: batteryReport(maxCapacity: 90), live: LiveSnapshot())
                #expect(!a.problems.contains { $0.text.contains("Ёмкость") } && !a.tips.contains { $0.text.contains("Ёмкость") },
                      "assess battery 90%: nothing")
            }
            do {
                let a = Assess.assess(report: batteryReport(maxCapacity: 90, condition: "Replace Soon"), live: LiveSnapshot())
                #expect(a.problems.contains { $0.sev == .serious && $0.text.contains("Состояние батареи") },
                      "assess battery condition 'Replace Soon': serious")
            }
            do {
                let a = Assess.assess(report: batteryReport(maxCapacity: 78, cycles: 350), live: LiveSnapshot())
                #expect(a.tips.contains { $0.text.contains("Ёмкость") }, "assess battery 78%, cycles 350: tip (early wear, R8)")
            }
            do {
                let a = Assess.assess(report: batteryReport(maxCapacity: 78, cycles: 900), live: LiveSnapshot())
                #expect(!a.tips.contains { $0.text.contains("Ёмкость") } && !a.problems.contains { $0.text.contains("Ёмкость") },
                      "assess battery 78%, cycles 900: nothing (on-spec wear, R8)")
            }
            do {
                let a = Assess.assess(report: batteryReport(maxCapacity: 65, cycles: 900), live: LiveSnapshot())
                #expect(a.problems.contains { $0.sev == .serious && $0.text.contains("Ёмкость") },
                      "assess battery 65%, cycles 900: serious (level rule survives any cycle count, R8)")
            }

            do {
                var report = FullReport()
                report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.contains { $0.sev == .serious && $0.text.contains("Файрвол") }, "assess security firewall==false: serious problem")
            }
            do {
                var report = FullReport()
                report.security = SecurityState(fileVault: nil, gatekeeper: nil, sip: nil, firewall: nil)
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.isEmpty, "assess security all nil: silent")
            }

            do {
                var report = FullReport()
                report.updates = ["a", "b"]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.contains { $0.text.contains("2 шт.") }, "assess updates [a,b]: warn '...2 шт.'")
            }
            do {
                var report = FullReport()
                report.updates = []
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(!a.problems.contains { $0.text.contains("обновлени") }, "assess updates []: nothing")
            }

            do {
                var report = FullReport()
                report.crashes = [CrashGroup(process: AppInfo.name, count: 2, directory: userCrashDir)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.contains { $0.sev == .warn && $0.text == L.assessOwnCrashesRecent(AppInfo.name, 2) },
                      "assess crashes: own-app group -> warn problem naming the app")
                #expect(a.items.contains { $0.kind == .crashes }, "assess crashes: own-app group -> AttentionItem(.crashes)")
            }
            do {
                var report = FullReport()
                report.crashes = [CrashGroup(process: "diffscore", count: 6, directory: userCrashDir),
                                  CrashGroup(process: "activatehelper", count: 1, directory: userCrashDir)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(!a.items.contains { $0.kind == .crashes }, "assess crashes: system processes only -> no AttentionItem")
                #expect(a.problems.isEmpty, "assess crashes: system processes only -> no problem")
                #expect(a.tips.isEmpty && a.capsules.isEmpty, "assess crashes: system processes only -> no tip/capsule either")
            }
            do {
                var report = FullReport()
                report.crashes = [CrashGroup(process: "diffscore", count: 6, directory: userCrashDir),
                                  CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.items.filter { $0.kind == .crashes }.count == 1, "assess crashes: own + system -> exactly one item")
                #expect(a.problems.contains { $0.text == L.assessOwnCrashesRecent(AppInfo.name, 1) },
                      "assess crashes: own + system -> count is own-app only (1, not 7)")
            }
            do {
                // The panic exception: an arbitrary non-MacDashboard process, still raises attention.
                var report = FullReport()
                report.crashes = [CrashGroup(process: "Kernel", count: 1, isPanic: true, directory: systemCrashDir)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.items.filter { $0.kind == .crashes }.count == 1,
                      "assess crashes: kernel panic from a non-own process -> exactly one AttentionItem(.crashes)")
                #expect(a.problems.contains { $0.sev == .warn && $0.text == L.assessKernelPanicsRecent(1) },
                      "assess crashes: kernel panic -> warn problem with the panic sentence")
            }
            do {
                var report = FullReport()
                report.crashes = [CrashGroup(process: "diffscore", count: 6, directory: userCrashDir),
                                  CrashGroup(process: "Kernel", count: 2, isPanic: true, directory: systemCrashDir)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.items.filter { $0.kind == .crashes }.count == 1, "assess crashes: panic + system -> exactly one item")
                #expect(a.problems.contains { $0.text == L.assessKernelPanicsRecent(2) },
                      "assess crashes: panic + system -> count is the panic group only (2, not 8)")
                #expect(a.items.first { $0.kind == .crashes }?.detail == L.attnDetailCrashes(2),
                      "assess crashes: panic + system -> detail counts panic reports only")
            }
            do {
                var report = FullReport()
                report.crashes = [CrashGroup(process: "Kernel", count: 2, isPanic: true, directory: systemCrashDir),
                                  CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir),
                                  CrashGroup(process: "diffscore", count: 6, directory: userCrashDir)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.items.filter { $0.kind == .crashes }.count == 1, "assess crashes: panic + own + system -> still one item")
                let text = a.items.first { $0.kind == .crashes }?.fullText ?? ""
                #expect(text.contains(L.assessKernelPanicsRecent(2)) && text.contains(L.assessOwnCrashesRecent(AppInfo.name, 1)),
                      "assess crashes: panic + own -> the single item carries both sentences")
                #expect(a.items.first { $0.kind == .crashes }?.detail == L.attnDetailCrashes(3),
                      "assess crashes: panic + own -> detail counts panic + own reports (3, not 9)")
            }
            do {
                var report = FullReport()
                report.crashes = []
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(!a.items.contains { $0.kind == .crashes }, "assess crashes []: nothing")
            }

            do {
                var report = FullReport()
                report.tmDest = .some(.none)
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.contains { $0.text.contains("не настроен") }, "assess tmDest .some(nil): warn 'не настроен'")
            }
            do {
                var report = FullReport()
                report.tmDest = .some(.some(TMDestination(name: "Backup", kind: "Local", mountPoint: "/Volumes/B", quotaBytes: nil, lastBackup: nil)))
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(!a.problems.contains { $0.text.contains("Time Machine") }, "assess tmDest .some(.some): nothing")
            }
            do {
                var report = FullReport()
                report.tmDest = .none
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(!a.problems.contains { $0.text.contains("Time Machine") }, "assess tmDest .none (not checked): nothing")
            }

            do {
                var report = FullReport()
                report.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: "SMART: ошибки носителя",
                                           attrs: [("Media and Data Integrity Errors", "3")], severity: .crit)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.contains { $0.sev == .crit && $0.text.contains("ошибках носителя") }, "assess smart media errors: crit problem")
            }
            do {
                var report = FullReport()
                report.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: "SMART: износ на исходе",
                                           attrs: [("Percentage Used", "85%")], severity: .warn)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.contains { $0.sev == .warn && $0.text.contains("износ") }, "assess smart Percentage Used 85%: warn")
            }
            do {
                var report = FullReport()
                report.smart = [SmartDisk(device: "/dev/disk4", title: "External", status: "SMART недоступен", attrs: [], severity: .warn)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.tips.contains { $0.text.contains("SMART недоступен") }, "assess smart external empty-attrs .warn: tip")
            }

            do {
                var report = FullReport()
                report.homeDirs = [DirSize(path: "/Users/x/Downloads", bytes: 11 * GIB)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.tips.contains { $0.text.contains("Загрузки") }, "assess homeDirs Downloads > 10GiB: tip")
            }
            do {
                var report = FullReport()
                report.homeDirs = [DirSize(path: "/Users/x/.Trash", bytes: 2 * GIB)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.tips.contains { $0.text.contains("Корзина") }, "assess homeDirs .Trash > 1GiB: tip")
            }

            do {
                var report = FullReport()
                report.updates = ["u1"]
                let a = Assess.assess(report: report, live: diskLive(pct: 0.94))
                #expect(a.summaryText == "Замечаний: \(a.problems.count)", "assess summary: 'Замечаний: N' text")
                #expect(a.summarySev == a.problems.first?.sev, "assess summary: summarySev == worst")
                #expect(a.problems.count >= 2, "assess summary: multiple problems present for ordering check")
                if let critIdx = a.problems.firstIndex(where: { $0.sev == .crit }),
                   let warnIdx = a.problems.firstIndex(where: { $0.sev == .warn }) {
                    #expect(critIdx < warnIdx, "assess summary: crit sorts before warn in problems")
                } else {
                    Issue.record("assess summary: expected both a crit and a warn problem in fixture")
                }
            }
            do {
                let a = Assess.assess(report: FullReport(), live: LiveSnapshot())
                #expect(a.problems.isEmpty && a.summaryText == "Всё в порядке" && a.summarySev == .good,
                      "assess summary: empty ⇒ 'Всё в порядке' / .good")
            }
        }

        @Test func adviceActions() async {
            // =====================================================================
            // MARK: - Assessment advice actions (advice block AR)
            // =====================================================================

            do {
                var report = FullReport()
                report.security = SecurityState(fileVault: true, gatekeeper: true, sip: false, firewall: false)
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.first { $0.text.contains("Файрвол") }?.action == .enableFirewall,
                      "assess advice: firewall==false ⇒ action == .enableFirewall")
                let sipProblem = a.problems.first { $0.text.contains("SIP") }
                #expect(sipProblem != nil && sipProblem?.action == nil,
                      "assess advice: sip==false ⇒ problem present with action == nil")
            }
            do {
                var report = FullReport()
                report.homeDirs = [DirSize(path: "/Users/x/.Trash", bytes: 2 * GIB)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.tips.first { $0.text.contains("Корзина") }?.action == .emptyTrash,
                      "assess advice: Trash tip ⇒ action == .emptyTrash")
            }
            do {
                var report = FullReport()
                report.brewOutdated = ["pkg1", "pkg2"]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.tips.first { $0.text.contains("Homebrew") }?.action == .brewUpgrade,
                      "assess advice: brew outdated tip ⇒ action == .brewUpgrade")
            }
            do {
                var report = FullReport()
                report.brewStatus = .installed(version: "Homebrew 4.6.0")
                report.brewOutdated = nil
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(!a.tips.contains { $0.action == .brewUpgrade } && !a.capsules.contains { $0.action == .brewUpgrade },
                      "assess advice: brew outdated check failed ⇒ no brew tip or capsule")
            }
            do {
                var report = FullReport()
                report.updates = ["u1", "u2"]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.problems.first { $0.text.contains("2 шт.") }?.action == .settingsPane(AdvicePanes.softwareUpdate),
                      "assess advice: updates available ⇒ action == .settingsPane(softwareUpdate)")
            }
            do {
                let downloadsPath = "/Users/x/Downloads"
                var report = FullReport()
                report.homeDirs = [DirSize(path: downloadsPath, bytes: 11 * GIB)]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.tips.first { $0.text.contains("Загрузки") }?.action == .revealPath(downloadsPath),
                      "assess advice: Downloads tip ⇒ action == .revealPath(downloadsPath)")
            }
        }
    }
}
