// Engine/Assessment.swift
// Started as a port of the legacy `assess()`; thresholds reviewed in TRIAGE-THRESHOLDS-REVIEW (block spec has the table).
// Same crit > serious > warn ordering and summary text.
// Pure and total: absent data ⇒ silent/good, never a fabricated warning. SPEC §6.

import Foundation

/// macOS memory-pressure level as `kern.memorystatus_vm_pressure_level` reports it
/// (the DISPATCH_MEMORYPRESSURE_* values; the signal behind Activity Monitor's graph).
enum MemoryPressureLevel: Equatable {
    case normal, warn, critical
    /// 1 → normal, 2 → warn, 4 → critical; any other value → nil (unknown, never guessed).
    init?(sysctlValue: Int32) {
        switch sysctlValue {
        case 1: self = .normal
        case 2: self = .warn
        case 4: self = .critical
        default: return nil
        }
    }
}

enum Assess {
    private static let GIB: Int64 = 1 << 30

    // --- V21-THRESHOLDS: every rule below states the mechanism it reads and the
    // machine parameter it scales with. Values are fixed by the block spec; do not
    // re-tune them to make a fixture pass.

    /// Cycles below which a capacity under 80 % counts as early wear. Mechanism:
    /// `BatteryInfo.maxCapacity` + `cycles`. Parameter: rated cycle life (1000 cycles to
    /// 80 % on modern Mac notebooks); 800 is 80 % of that life.
    private static let batteryEarlyWearCycles = 800

    static func memoryPressureSeverity(_ level: MemoryPressureLevel?) -> Severity? {
        switch level {
        case .warn: return .warn
        case .critical: return .serious
        case .normal, nil: return nil
        }
    }

    static func assess(report: FullReport, live: LiveSnapshot, language: AppLanguage, memPressure: MemoryPressureLevel? = nil, topApps: [AppMemory] = [], wakeHolders: [WakeHolder] = [], ignoredWakeHolders: [WakeHolderKey] = [], claudeBackup: ClaudeBackupStatus? = nil, claudeAttempt: ClaudeBackupAttempt? = nil, backupStaleHours: Int = AppSettings.defaultBackupStaleDays * 24, lowSpacePercent: Int = AppSettings.defaultLowSpacePercent, claudeLogPath: String = BackupLog.logURL.path, now: Date = Date()) -> Assessment {
        var a = Assessment()
        // Paired with its `Problem` so the final sort keeps `items` in lockstep
        // with `problems` (see §3 of the v2 attention spec — parity is structural,
        // not re-derived by a second sort).
        var pairs: [(Problem, AttentionItem)] = []
        var tips: [Tip] = []
        var capsules: [TipCapsule] = []
        let S = language.strings
        func verb(_ action: AdviceAction?) -> String { AttentionModel.verb(for: action, lang: language) }

        // --- disk (live is the freshest source; report carries none) ---
        let spaceLevel = live.disk.flatMap { $0.size > 0 ? StorageSpace.level(avail: $0.avail, size: $0.size, lowPercent: lowSpacePercent) : nil }
        if let disk = live.disk, disk.size > 0 {
            switch spaceLevel {
            case .critical:
                a.diskSev = .crit
                let action = AdviceAction.settingsPane(AdvicePanes.storage)
                let text = S.assessDiskFull(pct(disk.pct))
                pairs.append((Problem(sev: .crit, text: text, action: action),
                               AttentionItem(kind: .diskFull, sev: .crit, label: S.attnLabelDiskFull,
                                             detail: S.attnDetailDiskFull(pct(disk.pct)), fullText: text,
                                             verb: verb(action), action: action, why: S.attnWhyDiskFull)))
            case .low:
                a.diskSev = .warn
                let action = AdviceAction.settingsPane(AdvicePanes.storage)
                let text = S.assessDiskFullSoon(pct(disk.pct))
                pairs.append((Problem(sev: .warn, text: text, action: action),
                               AttentionItem(kind: .diskFullSoon, sev: .warn, label: S.attnLabelDiskFullSoon,
                                             detail: S.attnDetailDiskFullSoon(pct(disk.pct)), fullText: text,
                                             verb: verb(action), action: action, why: S.attnWhyDiskFullSoon)))
            case .ok, nil:
                break
            }
        }

        // --- memory pressure (TIPS-MEMORY): the SYSTEM's verdict only. Swap/compressed
        // size is not a shortage signal on modern macOS; an unreadable level stays silent.
        if let sev = memoryPressureSeverity(memPressure) {
            a.swapSev = sev
            // D2: a warn level only sets `swapSev`; the row, notification and Problem appear at critical.
            if sev == .serious {
                let action = AdviceAction.openApp(AdviceApps.activityMonitor)
                let text = S.assessMemPressure(critical: sev == .serious,
                                               apps: topApps.map { "\($0.name) (\(fmt($0.bytes, language: language)))" })
                pairs.append((Problem(sev: sev, text: text, action: action),
                              AttentionItem(kind: .swapHigh, sev: sev, label: S.attnLabelSwapHigh,
                                            detail: S.attnDetailMemPressureCritical,
                                            fullText: text, verb: verb(action), action: action,
                                            why: S.attnWhyMemPressure)))
            }
        }

        // --- battery: static fields from the report, falling back field by field to the live sample (BatteryInfo.merged) ---
        let batt = BatteryInfo.merged(live: live.battery, report: report.battery)
        if let cap = batt?.maxCapacity {
            if cap < 70 {
                a.battSev = .serious
                let action = AdviceAction.settingsPane(AdvicePanes.battery)
                let text = S.assessBatteryCapacityLow(cap)
                pairs.append((Problem(sev: .serious, text: text, action: action),
                               AttentionItem(kind: .batteryCapacity, sev: .serious, label: S.attnLabelBatteryCapacity,
                                             detail: S.attnDetailBatteryCapacity(cap), fullText: text,
                                             verb: verb(action), action: action, why: S.attnWhyBatteryWorn)))
            } else if cap < 80, (batt?.cycles ?? 0) < batteryEarlyWearCycles {
                a.battSev = .warn
                let action = AdviceAction.settingsPane(AdvicePanes.battery)
                let text = S.assessBatteryCapacityWarn(cap)
                pairs.append((Problem(sev: .warn, text: text, action: action),
                               AttentionItem(kind: .batteryCapacity, sev: .warn, label: S.attnLabelBatteryCapacity,
                                             detail: S.attnDetailBatteryCapacity(cap), fullText: text,
                                             verb: verb(action), action: action, why: S.attnWhyBatteryWorn)))
            }
        }
        if let cond = batt?.condition, !cond.isEmpty, cond != "Normal" {
            a.battSev = .serious
            let action = AdviceAction.settingsPane(AdvicePanes.battery)
            let text = S.assessBatteryConditionBad(cond)
            pairs.append((Problem(sev: .serious, text: text, action: action),
                           AttentionItem(kind: .batteryCondition, sev: .serious, label: S.attnLabelBatteryCondition,
                                         detail: S.attnDetailBatteryCondition(cond), fullText: text,
                                         verb: verb(action), action: action, why: S.attnWhyBatteryService)))
        }

        // --- security (nil = unknown ⇒ silent; only an explicit false warns) ---
        if let sec = report.security {
            if sec.fileVault == false {
                let action = AdviceAction.settingsPane(AdvicePanes.fileVault)
                let text = S.assessFileVaultOff
                pairs.append((Problem(sev: .serious, text: text, action: action),
                               AttentionItem(kind: .fileVaultOff, sev: .serious, label: S.attnLabelFileVaultOff,
                                             detail: S.attnDetailFileVaultOff, fullText: text,
                                             verb: verb(action), action: action, why: S.attnWhyFileVault)))
            }
            if sec.gatekeeper == false {
                let action = AdviceAction.enableGatekeeper
                let text = S.assessGatekeeperOff
                pairs.append((Problem(sev: .serious, text: text, action: action),
                               AttentionItem(kind: .gatekeeperOff, sev: .serious, label: S.attnLabelGatekeeperOff,
                                             detail: S.attnDetailGatekeeperOff, fullText: text,
                                             verb: verb(action), action: action, why: S.attnWhyGatekeeper)))
            }
            if sec.sip == false {
                let text = S.assessSipOff
                pairs.append((Problem(sev: .serious, text: text),
                               AttentionItem(kind: .sipOff, sev: .serious, label: S.attnLabelSipOff,
                                             detail: S.attnDetailSipOff, fullText: text,
                                             verb: verb(nil), action: nil, why: S.attnWhySip)))
            }
            if sec.firewall == false {
                let action = AdviceAction.enableFirewall
                let text = S.assessFirewallOff
                pairs.append((Problem(sev: .warn, text: text, action: action),
                               AttentionItem(kind: .firewallOff, sev: .warn, label: S.attnLabelFirewallOff,
                                             detail: S.attnDetailFirewallOff, fullText: text,
                                             verb: verb(action), action: action, why: S.attnWhyFirewall)))
            }
        }

        // --- macOS updates ---
        if let upd = report.updates, !upd.isEmpty {
            let action = AdviceAction.settingsPane(AdvicePanes.softwareUpdate)
            let text = S.assessMacUpdatesAvailable(upd.count)
            pairs.append((Problem(sev: .warn, text: text, action: action),
                           AttentionItem(kind: .updates, sev: .warn, label: S.attnLabelUpdates,
                                         detail: S.attnDetailUpdates(upd.count), fullText: text,
                                         verb: verb(action), action: action, why: S.attnWhyUpdates)))
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
        // The predicate lives in ReportCollector.crashRaisesAttention: the group cap
        // in crashGroups protects exactly these groups, and the two must not drift
        // apart (V2-CRASH-DETECT).
        let raisingCrashes = (report.crashes ?? []).filter {
            ReportCollector.crashRaisesAttention($0) && $0.count > 0
        }
        if !raisingCrashes.isEmpty {
            // The reveal target is DATA now, not a guess: a report from the system directory
            // used to open the (often empty) per-user one (V2-CRASH-REVEAL, item 1).
            // `raisingCrashes` preserves crashGroups' order — notable groups lead, count desc —
            // so this is the loudest raising group's directory. Per-group precision lives on the
            // card's own rows; this single item can only carry one target.
            let action = AdviceAction.revealPath(raisingCrashes[0].directory)
            let panicCount = raisingCrashes.filter { $0.isPanic }.reduce(0) { $0 + $1.count }
            let ownCount = raisingCrashes.filter { !$0.isPanic }.reduce(0) { $0 + $1.count }
            var sentences: [String] = []
            if panicCount > 0 { sentences.append(S.assessKernelPanicsRecent(panicCount)) }
            if ownCount > 0 { sentences.append(S.assessOwnCrashesRecent(AppInfo.name, ownCount)) }
            let text = sentences.joined(separator: " ")
            pairs.append((Problem(sev: .warn, text: text, action: action),
                           AttentionItem(kind: .crashes, sev: .warn, label: S.attnLabelCrashes,
                                         detail: S.attnDetailCrashes(panicCount + ownCount), fullText: text,
                                         verb: verb(action), action: action,
                                         why: panicCount > 0 ? S.attnWhyKernelPanic : S.attnWhyOwnCrash)))
        }

        // --- Time Machine (double optional: .some(nil) = checked & not configured) ---
        if case .some(.none) = report.tmDest {
            let action = AdviceAction.settingsPane(AdvicePanes.timeMachine)
            let text = S.assessTimeMachineNotSetUp
            pairs.append((Problem(sev: .warn, text: text, action: action),
                           AttentionItem(kind: .timeMachine, sev: .warn, label: S.attnLabelTimeMachine,
                                         detail: S.attnDetailTimeMachine, fullText: text,
                                         verb: verb(action), action: action, why: S.attnWhyTimeMachine)))
        }

        // --- Time Machine overdue (TRIAGE-THRESHOLDS-REVIEW D7): the Backups page's own 7 / 30-day rule ---
        if case .some(.some(let dest)) = report.tmDest, let last = dest.lastBackupDate {
            let state = BackupsPageModel.tmState(dest: dest, backup: nil, action: .idle, now: now)
            if state == .overdue7 || state == .overdue30 {
                let sev: Severity = state == .overdue30 ? .serious : .warn
                let days = BackupsPageModel.daysSince(last, now: now)
                let action = AdviceAction.settingsPane(AdvicePanes.timeMachine)
                let text = S.assessTimeMachineOverdue(days)
                pairs.append((Problem(sev: sev, text: text, action: action),
                              AttentionItem(kind: .timeMachineOverdue, sev: sev, label: S.attnLabelTimeMachine,
                                            detail: S.bkDaysAgo(days), fullText: text, verb: verb(action), action: action,
                                            why: S.attnWhyTimeMachineOverdue)))
            }
        }

        // --- Claude backup age (BACKUP-AGE): read from the backup log, never the disk ---
        if let backup = claudeBackup, BackupLog.isStale(backup, thresholdHours: backupStaleHours, now: now) {
            let action = AdviceAction.revealPath(claudeLogPath)
            let text: String, detail: String
            if case .lastSuccess(let d) = backup {
                let age = BackupLog.durationText(seconds: Int(max(0, now.timeIntervalSince(d))), language: language)
                switch claudeAttempt?.result {
                case .failed(let exit, let reason)?:
                    text = S.assessClaudeBackupStaleFailed(age, BackupLog.reasonText(reason, exit: exit, language: language))
                    detail = S.attnDetailClaudeBackupFailed
                case .interrupted?:
                    text = S.assessClaudeBackupStaleInterrupted(age); detail = S.attnDetailClaudeBackupInterrupted
                default:
                    text = S.assessClaudeBackupStale(age); detail = S.claudeBackupAgo(age)
                }
            } else if case .failed(let exit, let reason)? = claudeAttempt?.result {
                text = S.assessClaudeBackupNoneFailed(BackupLog.reasonText(reason, exit: exit, language: language))
                detail = S.attnDetailClaudeBackupFailed
            } else {
                text = S.assessClaudeBackupNone; detail = S.attnDetailClaudeBackupNone
            }
            pairs.append((Problem(sev: .warn, text: text, action: action),
                          AttentionItem(kind: .claudeBackup, sev: .warn, label: S.attnLabelClaudeBackup,
                                        detail: detail, fullText: text, verb: verb(action), action: action,
                                        why: S.attnWhyClaudeBackup)))
        }

        // --- SMART / disks ---
        if let disks = report.smart {
            for d in disks {
                a.smartSev = worse(a.smartSev, d.severity)
                let media = attrInt(d, "Media and Data Integrity Errors") ?? 0
                if SmartRules.isFailing(warningBits: SmartRules.warningBits(attr: attr(d, "Critical Warning")), mediaErrors: UInt64(max(0, media))) {
                    let action = AdviceAction.openApp(AdviceApps.diskUtility)
                    let text = S.assessSmartDiskErrors(d.displayTitle(S))
                    pairs.append((Problem(sev: .crit, text: text, action: action),
                                   AttentionItem(kind: .smartErrors, sev: .crit, label: S.attnLabelSmartErrors(d.displayTitle(S)),
                                                 detail: S.attnDetailSmartErrors, fullText: text,
                                                 verb: verb(action), action: action, why: S.attnWhySmartErrors)))
                } else if let pu = attrInt(d, "Percentage Used"), pu >= 80 {
                    let action = AdviceAction.openApp(AdviceApps.diskUtility)
                    let text = S.assessSmartDiskWearHigh(d.displayTitle(S), pu)
                    pairs.append((Problem(sev: .warn, text: text, action: action),
                                   AttentionItem(kind: .smartWear, sev: .warn, label: S.attnLabelSmartWear(d.displayTitle(S)),
                                                 detail: S.attnDetailSmartWear(pu), fullText: text,
                                                 verb: verb(action), action: action, why: S.attnWhySmartWear)))
                } else if isExternal(d), d.attrs.isEmpty, d.severity == .warn {
                    // Note: the Tip keeps action == nil (no logic drift from today's
                    // behaviour); the capsule gets an action so it stays actionable —
                    // the one intentional place item/tip and capsule actions differ.
                    tips.append(Tip(text: S.assessSmartDiskUnavailableTip(d.displayTitle(S))))
                    let capsuleAction = AdviceAction.openApp(AdviceApps.diskUtility)
                    capsules.append(TipCapsule(object: d.displayTitle(S), value: S.attnCapSmartNoData, verb: verb(capsuleAction),
                                                explanation: S.attnExplainSmart, action: capsuleAction))
                }
            }
        }

        // --- what keeps the Mac awake (WAKE-HOLDERS) --- read-only: names and ages only,
        // the click opens Activity Monitor; nothing here ever terminates a process.
        // SLEEP-IGNORE-APP: holders the user chose not to be warned about are dropped first —
        // they appear in neither the count, the text nor the per-app menu, and when none are
        // left there is no item at all.
        let warnHolders = WakeHolders.unignored(wakeHolders, ignored: ignoredWakeHolders)
        if !warnHolders.isEmpty {
            let action = AdviceAction.openApp(AdviceApps.activityMonitor)
            let entries = warnHolders.map { S.wakeHolderEntry(WakeHolders.label(for: $0, language: language), WakeHolders.ageText($0.ageSeconds, language: language)) }
            let text = S.assessWakeHolders(entries)
            pairs.append((Problem(sev: .warn, text: text, action: action),
                          AttentionItem(kind: .wakeHolders, sev: .warn, label: S.attnLabelWakeHolders,
                                        detail: S.attnDetailWakeHolders(entries[0], more: warnHolders.count - 1),
                                        fullText: text, verb: verb(action), action: action,
                                        wakeHolderKeys: warnHolders.map(\.key),
                                        why: S.attnWhyWakeHolders)))
        }

        // --- disk-space tips (home / caches) ---
        if let dirs = report.homeDirs {
            for d in dirs {
                let name = (d.path as NSString).lastPathComponent
                if name == "Downloads", d.bytes > 10 * GIB, StorageSpace.suggestsFreeing(spaceLevel) {
                    var share = ""
                    if let disk = live.disk, disk.size > 0 {
                        share = S.assessDownloadsShareSuffix(pct(Double(d.bytes) / Double(disk.size)))
                    }
                    let action = AdviceAction.revealPath(d.path)
                    tips.append(Tip(text: S.assessDownloadsTip(fmt(d.bytes, language: language), share), action: action))
                    capsules.append(TipCapsule(object: S.attnCapDownloads, value: fmt(d.bytes, language: language), verb: verb(action),
                                                explanation: S.attnExplainDownloads, action: action))
                }
                if name == ".Trash", d.bytes > 1 * GIB {
                    let action = AdviceAction.emptyTrash
                    tips.append(Tip(text: S.assessTrashTip(fmt(d.bytes, language: language)), action: action))
                    capsules.append(TipCapsule(object: S.attnCapTrash, value: fmt(d.bytes, language: language), verb: verb(action),
                                                explanation: S.attnExplainTrash, action: action))
                }
            }
        }
        if let d = report.homeCaches, d.bytes > 3 * GIB, StorageSpace.suggestsFreeing(spaceLevel) {
            let action = AdviceAction.revealPath(d.path)
            tips.append(Tip(text: S.assessCachesTip(fmt(d.bytes, language: language)), action: action))
            capsules.append(TipCapsule(object: S.attnCapCaches, value: fmt(d.bytes, language: language), verb: verb(action),
                                        explanation: S.attnExplainCaches, action: action))
        }

        // --- folders the collector was refused (V2-FDA-DEGRADE) ---
        // ONE tip + ONE capsule for the whole condition, whichever card(s) it
        // affects — and never a Problem/AttentionItem: a permission the user has
        // not granted is not a machine fault and does not belong in «Требует
        // внимания». TipCapsule carries no Severity, so this is info by
        // construction; no colour mapping is involved.
        if !report.homeDirsUnreadable.isEmpty || !report.serviceDirsUnreadable.isEmpty {
            let action = AdviceAction.settingsPane(AdvicePanes.fullDiskAccess)
            tips.append(Tip(text: S.assessNoFDATip, action: action))
            capsules.append(TipCapsule(object: S.attnCapFolders, value: S.attnCapFoldersNoAccess,
                                        verb: verb(action), explanation: S.attnExplainNoFDA, action: action))
        }

        // --- sort & summarize (crit > serious > warn, others last) ---
        // `Array.sort` is NOT documented stable, and `items` is now a visible ordered list
        // recomputed on every fast tick — equal-severity rows could swap places between
        // ticks for no reason. Decorating with the build index (which is AttentionKind's
        // declaration order, AttentionModel.swift:9-14 — the spec order) makes the order
        // deterministic. The dedupe guards the one way ids can collide: two identical
        // external disks failing the same SMART test yield the same kind AND the same
        // text, and `Problem.id`/`AttentionItem.id` are derived from those — duplicate
        // ids make SwiftUI's ForEach misbehave silently.
        var seen = Set<String>()
        pairs = pairs.enumerated()
            .sorted { l, r in
                let a = rank(l.element.0.sev), b = rank(r.element.0.sev)
                return a == b ? l.offset < r.offset : a > b
            }
            .map(\.element)
            .filter { seen.insert($0.0.id + "\u{1}" + $0.1.id).inserted }
        a.problems = pairs.map(\.0)
        a.items = pairs.map(\.1)
        a.tips = tips
        a.capsules = capsules
        a.summarySev = a.problems.first?.sev ?? .good
        a.summaryText = a.problems.isEmpty ? S.recommendationsAllGood : S.assessSummaryCount(a.problems.count)
        return a
    }

    // MARK: - helpers

    private static func pct(_ frac: Double) -> String { String(Int((frac * 100).rounded())) }
    private static func fmt(_ bytes: Int64, language: AppLanguage) -> String { ReportWriter.fmtBytes(bytes, language: language) }

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
