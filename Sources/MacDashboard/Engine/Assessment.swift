// Engine/Assessment.swift
// Port of the legacy `assess()` (mac_dashboard.py lines 516-606). Same thresholds,
// same Russian wording, same crit > serious > warn ordering and summary text.
// Pure and total: absent data ⇒ silent/good, never a fabricated warning. SPEC §6.

import Foundation

enum Assess {
    private static let GIB: Int64 = 1 << 30

    static func assess(report: FullReport, live: LiveSnapshot) -> Assessment {
        var a = Assessment()
        var problems: [Problem] = []
        var tips: [Tip] = []

        // --- disk (live is the freshest source; report carries none) ---
        if let disk = live.disk {
            if disk.pct >= 0.85 {
                a.diskSev = .crit
                problems.append(Problem(sev: .crit, text: L.assessDiskFull(pct(disk.pct)), action: .settingsPane(AdvicePanes.storage)))
            } else if disk.pct >= 0.70 {
                a.diskSev = .warn
                problems.append(Problem(sev: .warn, text: L.assessDiskFullSoon(pct(disk.pct)), action: .settingsPane(AdvicePanes.storage)))
            }
        }

        // --- swap ---
        if let swap = live.swap {
            if swap.used >= 2 * GIB {
                a.swapSev = .serious
                problems.append(Problem(sev: .serious, text: L.assessSwapHighSerious(fmt(swap.used)), action: .openApp(AdviceApps.activityMonitor)))
            } else if swap.used >= 1 * GIB {
                a.swapSev = .warn
                tips.append(Tip(text: L.assessSwapHighWarn(fmt(swap.used)), action: .openApp(AdviceApps.activityMonitor)))
            }
        }

        // --- battery (report merge wins; falls back to live) ---
        let batt = report.battery ?? live.battery
        if let cap = batt?.maxCapacity {
            if cap < 70 {
                a.battSev = .serious
                problems.append(Problem(sev: .serious, text: L.assessBatteryCapacityLow(cap), action: .settingsPane(AdvicePanes.battery)))
            } else if cap < 80 {
                a.battSev = .warn
                tips.append(Tip(text: L.assessBatteryCapacityWarn(cap), action: .settingsPane(AdvicePanes.battery)))
            }
        }
        if let cond = batt?.condition, !cond.isEmpty, cond != "Normal" {
            a.battSev = .serious
            problems.append(Problem(sev: .serious, text: L.assessBatteryConditionBad(cond), action: .settingsPane(AdvicePanes.battery)))
        }

        // --- security (nil = unknown ⇒ silent; only an explicit false warns) ---
        if let sec = report.security {
            if sec.fileVault == false { problems.append(Problem(sev: .serious, text: L.assessFileVaultOff, action: .settingsPane(AdvicePanes.fileVault))) }
            if sec.gatekeeper == false { problems.append(Problem(sev: .serious, text: L.assessGatekeeperOff, action: .settingsPane(AdvicePanes.privacySecurity))) }
            if sec.sip == false { problems.append(Problem(sev: .serious, text: L.assessSipOff)) }
            if sec.firewall == false { problems.append(Problem(sev: .serious, text: L.assessFirewallOff, action: .enableFirewall)) }
        }

        // --- macOS updates ---
        if let upd = report.updates, !upd.isEmpty {
            problems.append(Problem(sev: .warn, text: L.assessMacUpdatesAvailable(upd.count), action: .settingsPane(AdvicePanes.softwareUpdate)))
        }

        // --- homebrew ---
        if let outdated = report.brewOutdated, !outdated.isEmpty {
            tips.append(Tip(text: L.assessBrewOutdatedTip(outdated.count), action: .brewUpgrade))
        }

        // --- crashes ---
        if let crashes = report.crashes, !crashes.isEmpty {
            problems.append(Problem(sev: .warn, text: L.assessCrashesRecent(crashes.count),
                                     action: .revealPath(FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Logs/DiagnosticReports")))
        }

        // --- Time Machine (double optional: .some(nil) = checked & not configured) ---
        if case .some(.none) = report.tmDest {
            problems.append(Problem(sev: .warn, text: L.assessTimeMachineNotSetUp, action: .settingsPane(AdvicePanes.timeMachine)))
        }

        // --- SMART / disks ---
        if let disks = report.smart {
            for d in disks {
                a.smartSev = worse(a.smartSev, d.severity)
                let media = attrInt(d, "Media and Data Integrity Errors") ?? 0
                let crit = attr(d, "Critical Warning")
                if (crit != nil && crit != "0x00") || media > 0 {
                    problems.append(Problem(sev: .crit, text: L.assessSmartDiskErrors(d.title), action: .openApp(AdviceApps.diskUtility)))
                } else if let pu = attrInt(d, "Percentage Used"), pu >= 80 {
                    problems.append(Problem(sev: .warn, text: L.assessSmartDiskWearHigh(d.title, pu), action: .openApp(AdviceApps.diskUtility)))
                } else if isExternal(d), d.attrs.isEmpty, d.severity == .warn {
                    tips.append(Tip(text: L.assessSmartDiskUnavailableTip(d.title)))
                }
            }
        }

        // --- disk-space tips (home / caches) ---
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let dirs = report.homeDirs {
            for d in dirs {
                let name = (d.path as NSString).lastPathComponent
                if name == "Downloads", d.bytes > 10 * GIB {
                    var share = ""
                    if let disk = live.disk, disk.size > 0 {
                        share = L.assessDownloadsShareSuffix(pct(Double(d.bytes) / Double(disk.size)))
                    }
                    tips.append(Tip(text: L.assessDownloadsTip(fmt(d.bytes), share), action: .revealPath(d.path)))
                }
                if name == ".Trash", d.bytes > 1 * GIB {
                    tips.append(Tip(text: L.assessTrashTip(fmt(d.bytes)), action: .emptyTrash))
                }
            }
        }
        if let sdirs = report.serviceDirs {
            for d in sdirs where d.path.hasSuffix("/Library/Caches") && d.path.hasPrefix(home) && d.bytes > 3 * GIB {
                tips.append(Tip(text: L.assessCachesTip(fmt(d.bytes)), action: .revealPath(d.path)))
            }
        }

        // --- sort & summarize (crit > serious > warn, others last) ---
        problems.sort { rank($0.sev) > rank($1.sev) }
        a.problems = problems
        a.tips = tips
        a.summarySev = problems.first?.sev ?? .good
        a.summaryText = problems.isEmpty ? L.recommendationsAllGood : L.assessSummaryCount(problems.count)
        return a
    }

    // MARK: - helpers

    private static func pct(_ frac: Double) -> String { String(Int((frac * 100).rounded())) }
    private static func fmt(_ bytes: Int64) -> String { ReportWriter.fmtBytes(bytes) }

    private static func rank(_ s: Severity) -> Int {
        switch s {
        case .crit: return 3
        case .serious: return 2
        case .warn: return 1
        default: return 0
        }
    }

    // "worst so far" rollup, where info sits above good but below warn.
    private static func worse(_ a: Severity, _ b: Severity) -> Severity {
        rankAll(a) >= rankAll(b) ? a : b
    }
    private static func rankAll(_ s: Severity) -> Int {
        switch s {
        case .crit: return 4
        case .serious: return 3
        case .warn: return 2
        case .info: return 1
        case .good: return 0
        }
    }

    private static func isExternal(_ d: SmartDisk) -> Bool { d.device.hasPrefix("/dev/") }

    private static func attr(_ d: SmartDisk, _ key: String) -> String? {
        d.attrs.first { $0.0 == key }?.1
    }
    private static func attrInt(_ d: SmartDisk, _ key: String) -> Int? {
        guard let raw = attr(d, key) else { return nil }
        let digits = raw.filter { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
