// Engine/Assessment.swift
// Port of the legacy `assess()` (mac_dashboard.py lines 516-606). Same thresholds,
// same Russian wording, same crit > serious > warn ordering and summary text.
// Pure and total: absent data ⇒ silent/good, never a fabricated warning. SPEC §6.

import Foundation

enum Assess {
    private static let GIB: Int64 = 1 << 30

    static func assess(report: FullReport, live: LiveSnapshot) -> Assessment {
        var a = Assessment()
        // Paired with its `Problem` so the final sort keeps `items` in lockstep
        // with `problems` (see §3 of the v2 attention spec — parity is structural,
        // not re-derived by a second sort).
        var pairs: [(Problem, AttentionItem)] = []
        var tips: [Tip] = []
        var capsules: [TipCapsule] = []
        let lang = L10nStore.shared.language
        func verb(_ action: AdviceAction?) -> String { AttentionModel.verb(for: action, lang: lang) }

        // --- disk (live is the freshest source; report carries none) ---
        if let disk = live.disk {
            if disk.pct >= 0.85 {
                a.diskSev = .crit
                let action = AdviceAction.settingsPane(AdvicePanes.storage)
                let text = L.assessDiskFull(pct(disk.pct))
                pairs.append((Problem(sev: .crit, text: text, action: action),
                               AttentionItem(kind: .diskFull, sev: .crit, label: L.attnLabelDiskFull,
                                             detail: L.attnDetailDiskFull(pct(disk.pct)), fullText: text,
                                             verb: verb(action), action: action)))
            } else if disk.pct >= 0.70 {
                a.diskSev = .warn
                let action = AdviceAction.settingsPane(AdvicePanes.storage)
                let text = L.assessDiskFullSoon(pct(disk.pct))
                pairs.append((Problem(sev: .warn, text: text, action: action),
                               AttentionItem(kind: .diskFullSoon, sev: .warn, label: L.attnLabelDiskFullSoon,
                                             detail: L.attnDetailDiskFullSoon(pct(disk.pct)), fullText: text,
                                             verb: verb(action), action: action)))
            }
        }

        // --- swap ---
        if let swap = live.swap {
            if swap.used >= 2 * GIB {
                a.swapSev = .serious
                let action = AdviceAction.openApp(AdviceApps.activityMonitor)
                let text = L.assessSwapHighSerious(fmt(swap.used))
                pairs.append((Problem(sev: .serious, text: text, action: action),
                               AttentionItem(kind: .swapHigh, sev: .serious, label: L.attnLabelSwapHigh,
                                             detail: L.attnDetailSwapHigh(fmt(swap.used)), fullText: text,
                                             verb: verb(action), action: action)))
            } else if swap.used >= 1 * GIB {
                a.swapSev = .warn
                let action = AdviceAction.openApp(AdviceApps.activityMonitor)
                tips.append(Tip(text: L.assessSwapHighWarn(fmt(swap.used)), action: action))
                capsules.append(TipCapsule(object: L.attnCapSwap, value: fmt(swap.used), verb: verb(action),
                                            explanation: L.attnExplainSwap, action: action))
            }
        }

        // --- battery (report merge wins; falls back to live) ---
        let batt = report.battery ?? live.battery
        if let cap = batt?.maxCapacity {
            if cap < 70 {
                a.battSev = .serious
                let action = AdviceAction.settingsPane(AdvicePanes.battery)
                let text = L.assessBatteryCapacityLow(cap)
                pairs.append((Problem(sev: .serious, text: text, action: action),
                               AttentionItem(kind: .batteryCapacity, sev: .serious, label: L.attnLabelBatteryCapacity,
                                             detail: L.attnDetailBatteryCapacity(cap), fullText: text,
                                             verb: verb(action), action: action)))
            } else if cap < 80 {
                a.battSev = .warn
                let action = AdviceAction.settingsPane(AdvicePanes.battery)
                tips.append(Tip(text: L.assessBatteryCapacityWarn(cap), action: action))
                capsules.append(TipCapsule(object: L.attnCapBattery, value: L.attnCapBatteryValue(cap), verb: verb(action),
                                            explanation: L.attnExplainBattery, action: action))
            }
        }
        if let cond = batt?.condition, !cond.isEmpty, cond != "Normal" {
            a.battSev = .serious
            let action = AdviceAction.settingsPane(AdvicePanes.battery)
            let text = L.assessBatteryConditionBad(cond)
            pairs.append((Problem(sev: .serious, text: text, action: action),
                           AttentionItem(kind: .batteryCondition, sev: .serious, label: L.attnLabelBatteryCondition,
                                         detail: L.attnDetailBatteryCondition(cond), fullText: text,
                                         verb: verb(action), action: action)))
        }

        // --- security (nil = unknown ⇒ silent; only an explicit false warns) ---
        if let sec = report.security {
            if sec.fileVault == false {
                let action = AdviceAction.settingsPane(AdvicePanes.fileVault)
                let text = L.assessFileVaultOff
                pairs.append((Problem(sev: .serious, text: text, action: action),
                               AttentionItem(kind: .fileVaultOff, sev: .serious, label: L.attnLabelFileVaultOff,
                                             detail: L.attnDetailFileVaultOff, fullText: text,
                                             verb: verb(action), action: action)))
            }
            if sec.gatekeeper == false {
                let action = AdviceAction.settingsPane(AdvicePanes.privacySecurity)
                let text = L.assessGatekeeperOff
                pairs.append((Problem(sev: .serious, text: text, action: action),
                               AttentionItem(kind: .gatekeeperOff, sev: .serious, label: L.attnLabelGatekeeperOff,
                                             detail: L.attnDetailGatekeeperOff, fullText: text,
                                             verb: verb(action), action: action)))
            }
            if sec.sip == false {
                let text = L.assessSipOff
                pairs.append((Problem(sev: .serious, text: text),
                               AttentionItem(kind: .sipOff, sev: .serious, label: L.attnLabelSipOff,
                                             detail: L.attnDetailSipOff, fullText: text,
                                             verb: verb(nil), action: nil)))
            }
            if sec.firewall == false {
                let action = AdviceAction.enableFirewall
                let text = L.assessFirewallOff
                pairs.append((Problem(sev: .serious, text: text, action: action),
                               AttentionItem(kind: .firewallOff, sev: .serious, label: L.attnLabelFirewallOff,
                                             detail: L.attnDetailFirewallOff, fullText: text,
                                             verb: verb(action), action: action)))
            }
        }

        // --- macOS updates ---
        if let upd = report.updates, !upd.isEmpty {
            let action = AdviceAction.settingsPane(AdvicePanes.softwareUpdate)
            let text = L.assessMacUpdatesAvailable(upd.count)
            pairs.append((Problem(sev: .warn, text: text, action: action),
                           AttentionItem(kind: .updates, sev: .warn, label: L.attnLabelUpdates,
                                         detail: L.attnDetailUpdates(upd.count), fullText: text,
                                         verb: verb(action), action: action)))
        }

        // --- homebrew ---
        if let outdated = report.brewOutdated, !outdated.isEmpty {
            let action = AdviceAction.brewUpgrade
            tips.append(Tip(text: L.assessBrewOutdatedTip(outdated.count), action: action))
            capsules.append(TipCapsule(object: L.attnCapBrew, value: L.attnCapBrewValue(outdated.count), verb: verb(action),
                                        explanation: L.attnExplainBrew, action: action))
        }

        // --- crashes ---
        // Exactly two things raise attention here (V2-CRASH-SIGNAL):
        //   1. OUR OWN crash. The report filename carries CFBundleExecutable,
        //      which build_app.sh keeps equal to CFBundleName == AppInfo.name,
        //      so this compare is exact and needs no allowlist of "Apple daemons".
        //   2. A KERNEL PANIC (`.panic` report → CrashGroup.isPanic), whatever
        //      process logged it: the whole machine went down and rebooted, which
        //      is always news the user should see (user correction 2026-08-17).
        // A system/third-party process merely crashing (diffscore,
        // activatehelper…) is something the user cannot act on, and a permanent
        // «Требует внимания» item for it is exactly what trains the indicator to
        // be ignored. Those groups stay visible in the card and the text report.
        let raisingCrashes = (report.crashes ?? []).filter {
            ($0.isPanic || $0.process == AppInfo.name) && $0.count > 0
        }
        if !raisingCrashes.isEmpty {
            let action = AdviceAction.revealPath(FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Logs/DiagnosticReports")
            let panicCount = raisingCrashes.filter { $0.isPanic }.reduce(0) { $0 + $1.count }
            let ownCount = raisingCrashes.filter { !$0.isPanic }.reduce(0) { $0 + $1.count }
            var sentences: [String] = []
            if panicCount > 0 { sentences.append(L.assessKernelPanicsRecent(panicCount)) }
            if ownCount > 0 { sentences.append(L.assessOwnCrashesRecent(AppInfo.name, ownCount)) }
            let text = sentences.joined(separator: " ")
            pairs.append((Problem(sev: .warn, text: text, action: action),
                           AttentionItem(kind: .crashes, sev: .warn, label: L.attnLabelCrashes,
                                         detail: L.attnDetailCrashes(panicCount + ownCount), fullText: text,
                                         verb: verb(action), action: action)))
        }

        // --- Time Machine (double optional: .some(nil) = checked & not configured) ---
        if case .some(.none) = report.tmDest {
            let action = AdviceAction.settingsPane(AdvicePanes.timeMachine)
            let text = L.assessTimeMachineNotSetUp
            pairs.append((Problem(sev: .warn, text: text, action: action),
                           AttentionItem(kind: .timeMachine, sev: .warn, label: L.attnLabelTimeMachine,
                                         detail: L.attnDetailTimeMachine, fullText: text,
                                         verb: verb(action), action: action)))
        }

        // --- SMART / disks ---
        if let disks = report.smart {
            for d in disks {
                a.smartSev = worse(a.smartSev, d.severity)
                let media = attrInt(d, "Media and Data Integrity Errors") ?? 0
                let crit = attr(d, "Critical Warning")
                if (crit != nil && crit != "0x00") || media > 0 {
                    let action = AdviceAction.openApp(AdviceApps.diskUtility)
                    let text = L.assessSmartDiskErrors(d.title)
                    pairs.append((Problem(sev: .crit, text: text, action: action),
                                   AttentionItem(kind: .smartErrors, sev: .crit, label: L.attnLabelSmartErrors(d.title),
                                                 detail: L.attnDetailSmartErrors, fullText: text,
                                                 verb: verb(action), action: action)))
                } else if let pu = attrInt(d, "Percentage Used"), pu >= 80 {
                    let action = AdviceAction.openApp(AdviceApps.diskUtility)
                    let text = L.assessSmartDiskWearHigh(d.title, pu)
                    pairs.append((Problem(sev: .warn, text: text, action: action),
                                   AttentionItem(kind: .smartWear, sev: .warn, label: L.attnLabelSmartWear(d.title),
                                                 detail: L.attnDetailSmartWear(pu), fullText: text,
                                                 verb: verb(action), action: action)))
                } else if isExternal(d), d.attrs.isEmpty, d.severity == .warn {
                    // Note: the Tip keeps action == nil (no logic drift from today's
                    // behaviour); the capsule gets an action so it stays actionable —
                    // the one intentional place item/tip and capsule actions differ.
                    tips.append(Tip(text: L.assessSmartDiskUnavailableTip(d.title)))
                    let capsuleAction = AdviceAction.openApp(AdviceApps.diskUtility)
                    capsules.append(TipCapsule(object: d.title, value: L.attnCapSmartNoData, verb: verb(capsuleAction),
                                                explanation: L.attnExplainSmart, action: capsuleAction))
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
                    let action = AdviceAction.revealPath(d.path)
                    tips.append(Tip(text: L.assessDownloadsTip(fmt(d.bytes), share), action: action))
                    capsules.append(TipCapsule(object: L.attnCapDownloads, value: fmt(d.bytes), verb: verb(action),
                                                explanation: L.attnExplainDownloads, action: action))
                }
                if name == ".Trash", d.bytes > 1 * GIB {
                    let action = AdviceAction.emptyTrash
                    tips.append(Tip(text: L.assessTrashTip(fmt(d.bytes)), action: action))
                    capsules.append(TipCapsule(object: L.attnCapTrash, value: fmt(d.bytes), verb: verb(action),
                                                explanation: L.attnExplainTrash, action: action))
                }
            }
        }
        if let sdirs = report.serviceDirs {
            for d in sdirs where d.path.hasSuffix("/Library/Caches") && d.path.hasPrefix(home) && d.bytes > 3 * GIB {
                let action = AdviceAction.revealPath(d.path)
                tips.append(Tip(text: L.assessCachesTip(fmt(d.bytes)), action: action))
                capsules.append(TipCapsule(object: L.attnCapCaches, value: fmt(d.bytes), verb: verb(action),
                                            explanation: L.attnExplainCaches, action: action))
            }
        }

        // --- folders the collector was refused (V2-FDA-DEGRADE) ---
        // ONE tip + ONE capsule for the whole condition, whichever card(s) it
        // affects — and never a Problem/AttentionItem: a permission the user has
        // not granted is not a machine fault and does not belong in «Требует
        // внимания». TipCapsule carries no Severity, so this is info by
        // construction; no colour mapping is involved.
        if !report.homeDirsUnreadable.isEmpty || !report.serviceDirsUnreadable.isEmpty {
            let action = AdviceAction.settingsPane(AdvicePanes.fullDiskAccess)
            tips.append(Tip(text: L.assessNoFDATip, action: action))
            capsules.append(TipCapsule(object: L.attnCapFolders, value: L.attnCapFoldersNoAccess,
                                        verb: verb(action), explanation: L.attnExplainNoFDA, action: action))
        }

        // --- sort & summarize (crit > serious > warn, others last) ---
        pairs.sort { rank($0.0.sev) > rank($1.0.sev) }
        a.problems = pairs.map(\.0)
        a.items = pairs.map(\.1)
        a.tips = tips
        a.capsules = capsules
        a.summarySev = a.problems.first?.sev ?? .good
        a.summaryText = a.problems.isEmpty ? L.recommendationsAllGood : L.assessSummaryCount(a.problems.count)
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
