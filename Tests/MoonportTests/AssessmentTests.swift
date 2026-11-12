// Tests/MoonportTests/AssessmentTests.swift
// Port of Checks/main.swift lines 528-925 (CHECKS-SWIFT-TESTING). Memory math, Assess.assess and the advice actions.
import Foundation
import Testing
@testable import Moonport

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
private func diskItemSev(_ a: Assessment) -> Severity? { a.items.first { $0.kind == .diskFull || $0.kind == .diskFullSoon }?.sev }

private func batteryReport(maxCapacity: Int?, condition: String? = nil, cycles: Int? = nil) -> FullReport {
    var report = FullReport()
    report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: cycles, condition: condition, maxCapacity: maxCapacity)
    return report
}

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

        // REDESIGN-STORAGE: one percentage rule — critical < 10 % free, low < lowSpacePercent % free (strict).
        // Sizes are decimal (256 GB); `freeLive` sets `avail` exactly so boundaries are exact.
        func freeLive(freePct: Int, size: Int64 = 256_000_000_000) -> LiveSnapshot {
            var live = LiveSnapshot()
            live.disk = DiskInfo(size: size, avail: size / 100 * Int64(freePct), dataUsed: nil, sysUsed: nil)
            return live
        }
        do {
            let a = Assess.assess(report: FullReport(), live: freeLive(freePct: 25), language: .ru)
            #expect(diskItemSev(a) == nil, "assess disk 25% free: .good")
            #expect(!a.items.contains { $0.fullText.contains("Диск заполнен") }, "assess disk 25% free: no disk problem")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: freeLive(freePct: 19, size: 100_000_000_000), language: .ru)
            #expect(diskItemSev(a) == .warn, "assess disk 19% free: .warn")
            #expect(a.items.contains { $0.kind == .diskFullSoon }, "assess disk 19% free: diskFullSoon item")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: freeLive(freePct: 20), language: .ru)
            #expect(diskItemSev(a) == nil, "assess disk exactly 20% free: .good (strict)")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: freeLive(freePct: 9, size: 100_000_000_000), language: .ru)
            #expect(diskItemSev(a) == .crit, "assess disk 9% free: .crit")
            #expect(a.items.contains { $0.kind == .diskFull }, "assess disk 9% free: diskFull item")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: freeLive(freePct: 10), language: .ru)
            #expect(diskItemSev(a) == .warn, "assess disk exactly 10% free: .warn (strict)")
        }
        do {
            #expect(diskItemSev(Assess.assess(report: FullReport(), live: freeLive(freePct: 12), language: .ru, lowSpacePercent: 10)) == nil, "lowSpacePercent 10, 12% free: .good")
            #expect(diskItemSev(Assess.assess(report: FullReport(), live: freeLive(freePct: 9, size: 100_000_000_000), language: .ru, lowSpacePercent: 10)) == .crit, "lowSpacePercent 10, 9% free: .crit")
            #expect(diskItemSev(Assess.assess(report: FullReport(), live: freeLive(freePct: 10), language: .ru, lowSpacePercent: 10)) == nil, "lowSpacePercent 10, 10% free: .good (no amber band)")
            #expect(diskItemSev(Assess.assess(report: FullReport(), live: freeLive(freePct: 14), language: .ru, lowSpacePercent: 15)) == .warn, "lowSpacePercent 15, 14% free: .warn")
        }
        do {
            // TRIAGE-THRESHOLDS-REVIEW D1: the absolute caps (20 GB red, 40 GB amber).
            #expect(diskItemSev(Assess.assess(report: FullReport(), live: freeLive(freePct: 9), language: .ru)) == .warn, "cap: 23 GB free is amber, not red")
            #expect(diskItemSev(Assess.assess(report: FullReport(), live: freeLive(freePct: 19), language: .ru)) == nil, "cap: 48.6 GB free is fine on 256 GB")
        }
        do {
            var live = LiveSnapshot()
            live.disk = DiskInfo(size: 4096 * GIB, avail: (4096 * GIB + 4) / 5, dataUsed: nil, sysUsed: nil)
            let a = Assess.assess(report: FullReport(), live: live, language: .ru)
            #expect(diskItemSev(a) == nil, "assess disk 4TiB@80% (20% free): .good")
            #expect(!a.items.contains { $0.fullText.contains("Диск") },
                  "assess disk 4TiB@80%: no disk item")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: diskLive(pct: 0.992, size: 4096 * GIB), language: .ru)
            #expect(diskItemSev(a) == .warn, "assess disk 4TiB@99.2% (0.8% free, about 33 GiB): .warn — the percentage rule still applies under the caps")
            #expect(diskItemSev(Assess.assess(report: FullReport(), live: diskLive(pct: 0.85, size: 4096 * GIB), language: .ru)) == nil,
                  "assess disk 4TiB@85% (15% free, about 614 GiB): .good — the 40 GB cap")
        }

        do {
            #expect(MemoryPressureLevel(sysctlValue: 1) == .normal, "MemoryPressureLevel: 1 -> normal")
            #expect(MemoryPressureLevel(sysctlValue: 2) == .warn, "MemoryPressureLevel: 2 -> warn")
            #expect(MemoryPressureLevel(sysctlValue: 4) == .critical, "MemoryPressureLevel: 4 -> critical")
            #expect(MemoryPressureLevel(sysctlValue: 0) == nil, "MemoryPressureLevel: 0 -> nil")
            #expect(MemoryPressureLevel(sysctlValue: 3) == nil, "MemoryPressureLevel: 3 -> nil")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 5 * GIB, ramTotal: 8 * GIB, compressor: 2 * GIB), language: .ru)
            #expect(memItem(a) == nil, "assess with no memPressure: no item (R5)")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 5 * GIB, ramTotal: 8 * GIB, compressor: 2 * GIB), language: .ru, memPressure: .normal)
            #expect(memItem(a) == nil, "assess with .normal pressure: no item (R4)")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), language: .ru, memPressure: .warn)
            #expect(memItem(a) == nil && a.items.isEmpty, "assess with .warn pressure: no item (D2)")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), language: .ru, memPressure: .critical)
            #expect(memItem(a)?.sev == .serious, "assess with .critical pressure: serious item")
            #expect(memItem(a)?.why == StringsRU().attnWhyMemPressure, "assess with .critical pressure: why line")
        }
        do {
            let apps = [AppMemory(name: "Google Chrome", bytes: 3 * GIB), AppMemory(name: "Telegram", bytes: GIB)]
            let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), language: .ru, memPressure: .critical, topApps: apps)
            let expected = "Google Chrome (\(ReportWriter.fmtBytes(3 * GIB, language: .ru))) и Telegram (\(ReportWriter.fmtBytes(GIB, language: .ru)))"
            #expect(memItem(a)?.fullText.contains(expected) == true, "assess mem pressure text names top apps with sizes (R6)")
            let id1 = memItem(a)?.id
            let apps2 = [AppMemory(name: "Google Chrome", bytes: 3 * GIB), AppMemory(name: "Telegram", bytes: 2 * GIB)]
            let a2 = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), language: .ru, memPressure: .critical, topApps: apps2)
            #expect(memItem(a2)?.id == id1, "assess mem pressure item id stable across size changes (R7)")
            #expect(memItem(a)?.detail.contains("Swap") != true && memItem(a)?.detail.contains("сжат") != true,
                  "assess mem pressure detail has no swap/compressed mention (R7)")
        }
        do {
            let a = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), language: .ru, memPressure: .critical, topApps: [])
            #expect(memItem(a)?.fullText.contains("Закройте приложения") == true, "assess mem pressure, 0 apps: generic instruction")
            let a1 = Assess.assess(report: FullReport(), live: swapLive(usedBytes: 0), language: .ru, memPressure: .critical,
                                    topApps: [AppMemory(name: "Google Chrome", bytes: GIB)])
            #expect(a1.items.first { $0.kind == .swapHigh }?.fullText.contains("занимает ") == true,
                  "assess mem pressure, 1 app: singular sentence")
        }
        do {
            #expect(LiveCollector.readMemoryPressure() != nil, "readMemoryPressure: sysctl readable on this Mac")
        }

        do {
            let a = Assess.assess(report: batteryReport(maxCapacity: 65), live: LiveSnapshot(), language: .ru)
            let battery = a.items.filter { $0.kind == .batteryCapacity }
            #expect(battery.count == 1 && battery[0].sev == .warn && battery[0].fullText.contains("Здоровье"),
                  "BATTERY-HEALTH-UNIFY: 65% is one warn item (no serious tier)")
            #expect(!a.items.contains { $0.sev == .serious }, "BATTERY-HEALTH-UNIFY: 65% raises no serious item")
            #expect(a.battShownPercent?.percent == 65, "BATTERY-HEALTH-UNIFY: battShownPercent 65")
        }
        do {
            for (cap, cycles) in [(78, Int?.none), (78, 350), (78, 900), (65, 900), (79, nil)] {
                let a = Assess.assess(report: batteryReport(maxCapacity: cap, cycles: cycles), live: LiveSnapshot(), language: .ru)
                #expect(a.items.contains { $0.kind == .batteryCapacity && $0.sev == .warn && $0.fullText.contains("Здоровье") },
                      "BATTERY-HEALTH-UNIFY: \(cap)%, cycles \(String(describing: cycles)): warn whatever the cycle count")
            }
            let atLine = Assess.assess(report: batteryReport(maxCapacity: 80, cycles: 2000), live: LiveSnapshot(), language: .ru)
            #expect(!atLine.items.contains { $0.kind == .batteryCapacity || $0.kind == .batteryCondition },
                  "BATTERY-HEALTH-UNIFY: 80%, cycles 2000: no battery item")
        }
        do {
            let worn = Assess.assess(report: batteryReport(maxCapacity: 76, condition: "Normal"), live: LiveSnapshot(), language: .ru)
            #expect(worn.items.first { $0.kind == .batteryCapacity }?.why == StringsRU().attnWhyBatteryWorn, "BATTERY-HEALTH-UNIFY: worn why line")
            let service = Assess.assess(report: batteryReport(maxCapacity: 90, condition: "Service Recommended"), live: LiveSnapshot(), language: .ru)
            #expect(service.items.first { $0.kind == .batteryCondition }?.why == StringsRU().attnWhyBatteryService, "BATTERY-HEALTH-UNIFY: service why line")
        }
        do {
            let a = Assess.assess(report: batteryReport(maxCapacity: 90), live: LiveSnapshot(), language: .ru)
            #expect(!a.items.contains { $0.kind == .batteryCapacity || $0.kind == .batteryCondition || $0.fullText.contains("Здоровье") },
                  "BATTERY-HEALTH-UNIFY: 90%: nothing")
        }
        do {
            let a = Assess.assess(report: batteryReport(maxCapacity: 90, condition: "Replace Soon"), live: LiveSnapshot(), language: .ru)
            #expect(a.items.contains { $0.kind == .batteryCondition && $0.sev == .serious && $0.fullText.contains("Состояние батареи") },
                  "BATTERY-HEALTH-UNIFY: condition 'Replace Soon': serious")
            #expect(!a.items.contains { $0.kind == .batteryCapacity }, "BATTERY-HEALTH-UNIFY: no capacity item beside it")
        }
        do {
            let a = Assess.assess(report: batteryReport(maxCapacity: 60, condition: "Replace Now"), live: LiveSnapshot(), language: .ru)
            let battery = a.items.filter { $0.kind == .batteryCondition || $0.kind == .batteryCapacity }
            #expect(battery.count == 1 && battery[0].kind == .batteryCondition, "BATTERY-HEALTH-UNIFY: service supersedes worn (one item)")
            #expect(a.battShownPercent?.percent == 60, "BATTERY-HEALTH-UNIFY: battShownPercent 60")
        }
        do {
            let a = Assess.assess(report: batteryReport(maxCapacity: 76, condition: " Normal "), live: LiveSnapshot(), language: .ru)
            #expect(a.items.contains { $0.kind == .batteryCapacity } && !a.items.contains { $0.kind == .batteryCondition },
                  "BATTERY-HEALTH-UNIFY: ' Normal ' is not a service flag")
            let none = Assess.assess(report: batteryReport(maxCapacity: nil, condition: "Normal"), live: LiveSnapshot(), language: .ru)
            #expect(!none.items.contains { $0.kind == .batteryCapacity || $0.kind == .batteryCondition } && none.battShownPercent == nil,
                  "BATTERY-HEALTH-UNIFY: no maxCapacity: no battery item, battShownPercent nil")
        }
        do {
            let r = batteryReport(maxCapacity: 82, condition: "Normal")
            let on = Assess.assess(report: r, live: LiveSnapshot(), language: .ru, batteryRawPercent: 78, batteryPrefersRaw: true)
            #expect(on.items.contains { $0.kind == .batteryCapacity && $0.detail.contains("78") } && on.battShownPercent?.percent == 78,
                  "BATTERY-HEALTH-UNIFY: raw switch on judges the raw 78")
            let off = Assess.assess(report: r, live: LiveSnapshot(), language: .ru, batteryRawPercent: 78, batteryPrefersRaw: false)
            #expect(!off.items.contains { $0.kind == .batteryCapacity } && off.battShownPercent?.percent == 82,
                  "BATTERY-HEALTH-UNIFY: raw switch off judges Apple's 82")
            let noRaw = Assess.assess(report: r, live: LiveSnapshot(), language: .ru, batteryRawPercent: nil, batteryPrefersRaw: true)
            #expect(noRaw.battShownPercent?.percent == 82, "BATTERY-HEALTH-UNIFY: raw on, no ioreg read: Apple's figure")
        }

        do {
            var report = FullReport()
            report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.contains { $0.sev == .warn && $0.fullText.contains("Файрвол") }, "assess security firewall==false: warn problem (D5)")
            #expect(a.items.first { $0.kind == .firewallOff }?.sev == .warn, "assess security firewall==false: item .warn (D5)")
            for (fv, gk, sip, kind) in [(false, true, true, AttentionKind.fileVaultOff), (true, false, true, .gatekeeperOff), (true, true, false, .sipOff)] {
                var r = FullReport()
                r.security = SecurityState(fileVault: fv, gatekeeper: gk, sip: sip, firewall: true)
                #expect(Assess.assess(report: r, live: LiveSnapshot(), language: .ru).items.first { $0.kind == kind }?.sev == .serious, "assess security \(kind): serious (D5)")
            }
            var fvOff = FullReport()
            fvOff.security = SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: true)
            let fvItem = Assess.assess(report: fvOff, live: LiveSnapshot(), language: .ru).items.first { $0.kind == .fileVaultOff }
            #expect(fvItem?.fullTextWithWhy == StringsRU().assessFileVaultOff + " " + StringsRU().attnWhyFileVault, "assess fileVaultOff: fullTextWithWhy")
        }
        do {
            var report = FullReport()
            report.security = SecurityState(fileVault: nil, gatekeeper: nil, sip: nil, firewall: nil)
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.isEmpty, "assess security all nil: silent")
        }

        do {
            var report = FullReport()
            report.updates = [upd("a"), upd("b")]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.contains { $0.fullText.contains("2 шт.") }, "assess updates [a,b]: warn '...2 шт.'")
        }
        do {
            var report = FullReport()
            report.updates = []
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(!a.items.contains { $0.fullText.contains("обновлени") }, "assess updates []: nothing")
        }

        do {
            var report = FullReport()
            report.crashes = [CrashGroup(process: AppInfo.name, count: 2, directory: userCrashDir)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.contains { $0.sev == .warn && $0.fullText == StringsRU().assessOwnCrashesRecent(AppInfo.name, 2) },
                  "assess crashes: own-app group -> warn problem naming the app")
            #expect(a.items.first { $0.kind == .crashes }?.why == StringsRU().attnWhyOwnCrash, "assess crashes: own-app only -> own-crash why")
            #expect(a.items.contains { $0.kind == .crashes }, "assess crashes: own-app group -> AttentionItem(.crashes)")
        }
        do {
            var report = FullReport()
            report.crashes = [CrashGroup(process: "diffscore", count: 6, directory: userCrashDir),
                              CrashGroup(process: "activatehelper", count: 1, directory: userCrashDir)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(!a.items.contains { $0.kind == .crashes }, "assess crashes: system processes only -> no AttentionItem")
        }
        do {
            var report = FullReport()
            report.crashes = [CrashGroup(process: "diffscore", count: 6, directory: userCrashDir),
                              CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.filter { $0.kind == .crashes }.count == 1, "assess crashes: own + system -> exactly one item")
            #expect(a.items.contains { $0.fullText == StringsRU().assessOwnCrashesRecent(AppInfo.name, 1) },
                  "assess crashes: own + system -> count is own-app only (1, not 7)")
        }
        do {
            // The panic exception: an arbitrary non-MacDashboard process, still raises attention.
            var report = FullReport()
            report.crashes = [CrashGroup(process: "Kernel", count: 1, isPanic: true, directory: systemCrashDir)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.filter { $0.kind == .crashes }.count == 1,
                  "assess crashes: kernel panic from a non-own process -> exactly one AttentionItem(.crashes)")
            #expect(a.items.contains { $0.sev == .warn && $0.fullText == StringsRU().assessKernelPanicsRecent(1) },
                  "assess crashes: kernel panic -> warn problem with the panic sentence")
            #expect(a.items.first { $0.kind == .crashes }?.why == StringsRU().attnWhyKernelPanic, "assess crashes: panic -> kernel-panic why")
        }
        do {
            // CRASH-REPORT-DISMISS: hidden groups never reach the assessment.
            var report = FullReport()
            report.crashes = []
            report.crashesHidden = [CrashGroup(process: AppInfo.name, count: 2, directory: userCrashDir),
                                    CrashGroup(process: "Kernel", count: 1, isPanic: true, directory: systemCrashDir)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(!a.items.contains { $0.kind == .crashes }, "assess crashes: hidden-only -> no AttentionItem")
            #expect(!a.items.contains { $0.fullText == StringsRU().assessOwnCrashesRecent(AppInfo.name, 2) || $0.fullText == StringsRU().assessKernelPanicsRecent(1) },
                  "assess crashes: hidden-only -> no crash problem")
        }
        do {
            var report = FullReport()
            report.crashes = [CrashGroup(process: "diffscore", count: 6, directory: userCrashDir),
                              CrashGroup(process: "Kernel", count: 2, isPanic: true, directory: systemCrashDir)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.filter { $0.kind == .crashes }.count == 1, "assess crashes: panic + system -> exactly one item")
            #expect(a.items.contains { $0.fullText == StringsRU().assessKernelPanicsRecent(2) },
                  "assess crashes: panic + system -> count is the panic group only (2, not 8)")
            #expect(a.items.first { $0.kind == .crashes }?.detail == StringsRU().attnDetailCrashes(2),
                  "assess crashes: panic + system -> detail counts panic reports only")
        }
        do {
            var report = FullReport()
            report.crashes = [CrashGroup(process: "Kernel", count: 2, isPanic: true, directory: systemCrashDir),
                              CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir),
                              CrashGroup(process: "diffscore", count: 6, directory: userCrashDir)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.filter { $0.kind == .crashes }.count == 1, "assess crashes: panic + own + system -> still one item")
            let text = a.items.first { $0.kind == .crashes }?.fullText ?? ""
            #expect(text.contains(StringsRU().assessKernelPanicsRecent(2)) && text.contains(StringsRU().assessOwnCrashesRecent(AppInfo.name, 1)),
                  "assess crashes: panic + own -> the single item carries both sentences")
            #expect(a.items.first { $0.kind == .crashes }?.detail == StringsRU().attnDetailCrashes(3),
                  "assess crashes: panic + own -> detail counts panic + own reports (3, not 9)")
        }
        do {
            var report = FullReport()
            report.crashes = []
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(!a.items.contains { $0.kind == .crashes }, "assess crashes []: nothing")
        }

        do {
            var report = FullReport()
            report.tmDest = .some(.none)
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.contains { $0.fullText.contains("не настроен") }, "assess tmDest .some(nil): warn 'не настроен'")
        }
        do {
            var report = FullReport()
            report.tmDest = .some(.some(TMDestination(name: "Backup", kind: "Local", mountPoint: "/Volumes/B", quotaBytes: nil, lastBackup: nil)))
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(!a.items.contains { $0.fullText.contains("Time Machine") }, "assess tmDest .some(.some): nothing")
        }
        do {
            // D7: overdue by the Backups page's own rule (strictly more than 7 / 30 days).
            let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
            func overdue(_ last: Date?) -> AttentionItem? {
                var dest = TMDestination(name: "Backup", kind: "Local", mountPoint: "/Volumes/B", quotaBytes: nil, lastBackup: nil)
                dest.lastBackupDate = last
                var report = FullReport()
                report.tmDest = .some(.some(dest))
                return Assess.assess(report: report, live: LiveSnapshot(), language: .ru, now: t0).items.first { $0.kind == .timeMachineOverdue }
            }
            #expect(overdue(t0 - 7 * 86_400) == nil, "TM overdue: exactly 7 days is not overdue")
            #expect(overdue(t0 - 7 * 86_400 - 1)?.sev == .warn, "TM overdue: 7 days and 1 s is warn")
            #expect(overdue(t0 - 7 * 86_400 - 1)?.detail == StringsRU().bkDaysAgo(7), "TM overdue: detail is the day count")
            #expect(overdue(t0 - 30 * 86_400)?.sev == .warn, "TM overdue: exactly 30 days is still warn")
            #expect(overdue(t0 - 30 * 86_400 - 1)?.sev == .serious, "TM overdue: 30 days and 1 s is serious")
            #expect(overdue(nil) == nil, "TM overdue: unknown age is silent")
            #expect(overdue(t0 - 10 * 86_400)?.why == StringsRU().attnWhyTimeMachineOverdue, "TM overdue: why line")
            var none = FullReport()
            none.tmDest = .some(.none)
            let kinds = Assess.assess(report: none, live: LiveSnapshot(), language: .ru, now: t0).items.map(\.kind)
            #expect(kinds == [.timeMachine], "TM not set up: only .timeMachine")
        }
        do {
            var report = FullReport()
            report.tmDest = .none
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(!a.items.contains { $0.fullText.contains("Time Machine") }, "assess tmDest .none (not checked): nothing")
        }

        do {
            var report = FullReport()
            report.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: .mediaErrors,
                                       attrs: [("Media and Data Integrity Errors", "3")], severity: .crit)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.contains { $0.sev == .crit && $0.fullText.contains("ошибках носителя") }, "assess smart media errors: crit problem")
        }
        do {
            // T15: only the failure bits of Critical Warning count (0x02 temperature alone does not).
            func smartKinds(_ attrs: [(String, String)]) -> [AttentionKind] {
                var r = FullReport()
                r.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: .ok, attrs: attrs, severity: .good)]
                return Assess.assess(report: r, live: LiveSnapshot(), language: .ru).items.map(\.kind)
            }
            #expect(!smartKinds([("Critical Warning", "0x02")]).contains(.smartErrors), "SMART 0x02: no smartErrors")
            #expect(smartKinds([("Critical Warning", "0x04")]).contains(.smartErrors), "SMART 0x04: smartErrors")
            #expect(smartKinds([("Critical Warning", "0x00"), ("Media and Data Integrity Errors", "1")]).contains(.smartErrors), "SMART media 1: smartErrors")
            var r = FullReport()
            r.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: .mediaErrors, attrs: [("Critical Warning", "0x04")], severity: .crit)]
            #expect(Assess.assess(report: r, live: LiveSnapshot(), language: .ru).items.first { $0.kind == .smartErrors }?.sev == .crit, "SMART 0x04: crit")
        }
        do {
            var report = FullReport()
            report.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: .wearHigh,
                                       attrs: [("Percentage Used", "85%")], severity: .warn)]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.contains { $0.sev == .warn && $0.fullText.contains("износ") }, "assess smart Percentage Used 85%: warn")
        }


        do {
            var report = FullReport()
            report.updates = [upd("u1")]
            let a = Assess.assess(report: report, live: diskLive(pct: 0.94), language: .ru)
            #expect(a.items.count >= 2, "assess summary: multiple items present for ordering check")
            if let critIdx = a.items.firstIndex(where: { $0.sev == .crit }),
               let warnIdx = a.items.firstIndex(where: { $0.sev == .warn }) {
                #expect(critIdx < warnIdx, "assess summary: crit sorts before warn in items")
            } else {
                Issue.record("assess summary: expected both a crit and a warn item in fixture")
            }
        }
        do {
            let a = Assess.assess(report: FullReport(), live: LiveSnapshot(), language: .ru)
            #expect(a.items.isEmpty, "assess summary: nothing to report ⇒ no items")
        }
    }

    @Test func adviceActions() async {
        // =====================================================================
        // MARK: - Assessment advice actions (advice block AR)
        // =====================================================================

        do {
            var report = FullReport()
            report.security = SecurityState(fileVault: true, gatekeeper: true, sip: false, firewall: false)
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.first { $0.fullText.contains("Файрвол") }?.action == .enableFirewall,
                  "assess advice: firewall==false ⇒ action == .enableFirewall")
            var gkReport = FullReport()
            gkReport.security = SecurityState(fileVault: true, gatekeeper: false, sip: true, firewall: true)
            let gk = Assess.assess(report: gkReport, live: LiveSnapshot(), language: .ru)
            #expect(gk.items.first { $0.fullText.contains("Gatekeeper") }?.action == .enableGatekeeper,
                  "assess advice: gatekeeper==false ⇒ action == .enableGatekeeper")
            let sipItem = a.items.first { $0.fullText.contains("SIP") }
            #expect(sipItem != nil && sipItem?.action == nil,
                  "assess advice: sip==false ⇒ item present with action == nil")
        }
        do {
            // Outdated Homebrew packages are never an attention item (TRIAGE-THRESHOLDS-REVIEW, [BREW]).
            var report = FullReport()
            report.brewOutdated = ["pkg1", "pkg2"]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            var none = report; none.brewOutdated = []
            let b = Assess.assess(report: none, live: LiveSnapshot(), language: .ru)
            #expect(!a.items.contains { $0.label.contains("Homebrew") || $0.detail.contains("Homebrew") || $0.fullText.contains("Homebrew") },
                  "assess advice: brew outdated ⇒ no item mentions Homebrew")
            #expect(a.items.count == b.items.count, "assess advice: brew outdated leaves the item count unchanged")
        }
        do {
            var report = FullReport()
            report.updates = [upd("u1"), upd("u2")]
            let a = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a.items.first { $0.fullText.contains("2 шт.") }?.action == .settingsPane(AdvicePanes.softwareUpdate),
                  "assess advice: updates available ⇒ action == .settingsPane(softwareUpdate)")
        }
    }
}

private func upd(_ label: String) -> SoftwareUpdate {
    SoftwareUpdate(label: label, title: label, version: nil, sizeBytes: nil, restartRequired: false)
}
