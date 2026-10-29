// Views/BackupsPage.swift
// REDESIGN-BACKUPS: the Backups section page (handoff 08-backups) on the shared §8 blocks. Every text, tone and
// tile comes from the pure BackupsPageModel; this file only draws them and forwards actions to the model's TimeMachineController.
// The only live loop is `model.timeMachine.observeStatus()` (2 s `tmutil status` poll while a backup runs,
// awaited by this page's `.task`, so it stops when the page leaves).

import SwiftUI

@MainActor
struct BackupsPage: View {
    let model: DashboardModel
    let router: NavigationRouter
    let narrow: Bool

    @State private var pulse: CardID? = nil


    /// Reads no live model field (only `router.navigationSerial` / `destination`): the bar and the cards do the reading.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BackupsTimeMachineCard(model: model, narrow: narrow)
                        .id(CardID.tm)
                        .sectionFocusPulse(pulse == .tm)
                        .ds3Appear(delay: 0.08)
                    BackupsClaudeCard(model: model)
                        .id(CardID.claude)
                        .sectionFocusPulse(pulse == .claude)
                        .ds3Appear(delay: 0.14)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) { BackupsPageBar(model: model, onBack: { _ = router.back() }) }
            .task(id: router.navigationSerial) {
                // Deep link: scroll the focused card under the bar (Time Machine is already on top) and pulse it.
                let d = router.destination
                guard d.page == .backups, let f = d.focus else { return }
                if f != .tm { proxy.scrollTo(f, anchor: .top) }
                pulse = f
                try? await Task.sleep(for: .seconds(3))
                pulse = nil
            }
            // REDESIGN-BACKUPS D2: cancelled with the page, which is exactly the «only while on screen» rule.
            .task { await model.timeMachine.observeStatus() }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
    }
}

// MARK: - Input and mapping helpers

@MainActor
private func backupsInput(_ model: DashboardModel, now: Date) -> BackupsPageModel.Input {
    .init(tmDest: model.report.tmDest, snapshots: model.report.snapshots, backup: model.timeMachine.backup,
          action: model.timeMachine.action, updatedAt: model.timeMachine.updatedAt, claudeBackup: model.claudeBackup,
          claudeLogPath: model.claudeLogPath, warnAfterHours: model.settings.backupStaleHours, now: now)
}

private func toneColor(_ t: BackupsTone) -> Color {
    switch t {
    case .green: return DS3.green
    case .amber: return DS3.amber
    case .hot: return DS3.hot
    case .neutral: return DS3.muted
    case .accent: return DS3.accent
    }
}

private func toneInk(_ t: BackupsTone?) -> Color {
    switch t {
    case nil: return DS3.ink
    case .green?: return DS3.greenInk
    case .amber?: return DS3.amberInk
    case .hot?: return DS3.hotInk
    case .neutral?: return DS3.muted
    case .accent?: return DS3.accentInk
    }
}

private func tagTone(_ t: BackupsTone) -> DS3Tag.Tone {
    switch t {
    case .green: return .green
    case .amber: return .amber
    case .hot: return .hot
    case .neutral: return .neutral
    case .accent: return .accent
    }
}

@MainActor
private func backupsTileView(_ t: BackupsTile) -> some View {
    SectionTile(label: t.label, value: t.value, note: t.note,
                noteInk: t.noteTone.map(toneInk) ?? DS3.muted,
                dot: t.dot.map(toneColor), valueInk: toneInk(t.valueTone))
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it. No Refresh button on this page.
@MainActor
struct BackupsPageBar: View {
    let model: DashboardModel
    let onBack: () -> Void

    var body: some View {
        let m = BackupsPageModel.make(backupsInput(model, now: model.now()))
        SectionPageBar(symbol: Page.backups.symbol, title: Page.backups.title, sub: m.sub, onBack: onBack) {
            DS3Tag(tone: tagTone(m.tag), text: m.tagText).help(m.tagText)
        } trailing: {
            EmptyView()
        }
    }
}

// MARK: - Time Machine card

@MainActor
struct BackupsTimeMachineCard: View {
    let model: DashboardModel
    let narrow: Bool

    /// The ageing texts («50 min ago», «in 10 min») re-render once a minute (`gpu-per-frame`).
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            card(now: model.now(or: ctx.date))
        }
    }

    @ViewBuilder
    private func card(now: Date) -> some View {
        let m = BackupsPageModel.make(backupsInput(model, now: now))
        DS3Card(title: "Time Machine", caption: m.tmCaption) {
            switch m.tmState {
            case .wait:
                SectionWait(text: L.commonCollectingData)
            default:
                VStack(alignment: .leading, spacing: 16) {
                    if let n = m.tmNote { note(n) }
                    if let p = m.tmProgress {
                        BackupsProgressBlock(progress: p, stopBusy: model.timeMachine.action == .stopping) {
                            model.timeMachine.stopBackupNow()
                        }
                    }
                    if let f = m.tmFailure { SectionNote(tone: DS3.hot, text: f) }
                    EqualColumnsLayout(columns: m.tmState == .notSet ? 3 : (narrow ? 2 : 4), spacing: 8) {
                        ForEach(m.tmTiles, id: \.id) { t in
                            if t.id == "purgeable" { BackupsPurgeableTile(model: model) } else { backupsTileView(t) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func note(_ n: BackupsNote) -> some View {
        switch n.button {
        case .setUp?:
            SectionNote(tone: toneColor(n.tone), text: n.text,
                        button: (L.commonSetUp, L.bkSetUpA11y, false, { AdviceActionRunner.openPane(AdvicePanes.timeMachine) }),
                        buttonIdentifier: "backups-tm-setup", primary: true)
        case .backUpNow(let enabled)?:
            let disk: String = {
                if case .some(.some(let d)) = model.report.tmDest { return d.name ?? L.bkTheBackupDisk }
                return L.bkTheBackupDisk
            }()
            SectionNote(tone: toneColor(n.tone), text: n.text,
                        button: (L.bkBackUpNow, L.bkBackUpNowA11y, model.timeMachine.action == .starting, { model.timeMachine.startBackupNow() }),
                        buttonIdentifier: "backups-tm-backup-now", primary: true,
                        buttonDisabled: !enabled, buttonHelp: enabled ? nil : L.bkConnectFirst(disk))
        default:
            SectionNote(tone: toneColor(n.tone), text: n.text)
        }
    }
}

/// The accent panel of a running backup: spinner, «Backing up to <disk>», bytes caption, Stop, and the 6 pt bar.
/// The bar's fraction changes only when a poll lands; only its fill width animates (`animation-value-size-coupling`).
private struct BackupsProgressBlock: View {
    let progress: BackupsProgress
    let stopBusy: Bool
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DS3Spinner(role: .tinted, size: 14)
                Text(progress.text)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS3.accentInk)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(progress.caption)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
                    .layoutPriority(1)
                Button { onStop() } label: {
                    Text(L.bkStop).dsSwapInPlace(stopBusy) { DS3Spinner(role: .softRing, size: 12) }
                }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(stopBusy || progress.stopping)
                .accessibilityLabel(L.bkStopA11y)
                .ds3BusyValue(stopBusy)
                .accessibilityIdentifier("backups-tm-stop")
            }
            if let f = progress.fraction {
                DS3Bar(fraction: f, height: 6, fill: AnyShapeStyle(DS3.accent))
                    .animation(.easeOut(duration: 0.3), value: f)
            } else {
                ProgressView().progressViewStyle(.linear).controlSize(.small).tint(DS3.accent)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .ds3TintPanel(DS3.accent, from: 0.16, to: 0.06, ring: 0.42, cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }
}

/// Reads the live `model.disk` itself, so the ~2 s live tick invalidates only this tile and not the whole card (D13).
private struct BackupsPurgeableTile: View {
    let model: DashboardModel

    var body: some View {
        let purgeable = model.disk?.purgeable
        SectionTile(label: L.bkPurgeable, value: purgeable.map(fmtCapacity) ?? "—", note: L.bkPurgeableNote,
                    noteInk: DS3.muted, valueInk: purgeable == nil ? DS3.muted : DS3.ink)
    }
}

// MARK: - Claude backup card

@MainActor
struct BackupsClaudeCard: View {
    let model: DashboardModel

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            card(now: model.now(or: ctx.date))
        }
    }

    @ViewBuilder
    private func card(now: Date) -> some View {
        let m = BackupsPageModel.make(backupsInput(model, now: now))
        DS3Card(title: L.commonClaudeBackup, caption: m.claudeCaption) {
            VStack(alignment: .leading, spacing: 16) {
                if let n = m.claudeNote { note(n) }
                EqualColumnsLayout(columns: 3, spacing: 8) {
                    ForEach(m.claudeTiles, id: \.id) { backupsTileView($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func note(_ n: BackupsNote) -> some View {
        switch n.button {
        case .openSettingsBackups?:
            SectionNote(tone: toneColor(n.tone), text: n.text,
                        button: (L.bkOpenSettingsBackups, L.bkOpenSettingsBackupsA11y, false, {
                            SettingsWindowController.shared.show(section: .backup)
                        }),
                        buttonIdentifier: "backups-claude-settings")
        case .openFullDiskAccess?:
            SectionNote(tone: toneColor(n.tone), text: n.text,
                        button: (L.bkOpenPrivacy, L.bkOpenPrivacyA11y, false, { AdviceActionRunner.openPane(AdvicePanes.fullDiskAccess) }),
                        buttonIdentifier: "backups-claude-privacy")
        default:
            SectionNote(tone: toneColor(n.tone), text: n.text)
        }
    }
}
