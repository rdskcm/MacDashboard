// Views/BackupsPage.swift
// REDESIGN-BACKUPS: the Backups section page (handoff 08-backups) on the shared §8 blocks. Every text, tone and
// tile comes from the pure BackupsPageModel; this file only draws them and forwards actions to the model's TimeMachineController.
// Live loops: `model.timeMachine.observeStatus()` (2 s `tmutil status` poll while a backup runs) and
// `model.claudeRun.observe()` (BACKUP-CARD-FAILURE: the Claude card's page-scoped poll); both are awaited by this page's `.task`s,
// so they stop when the page leaves.

import SwiftUI

@MainActor
struct BackupsPage: View {
    let model: AppModel
    let router: NavigationRouter
    let narrow: Bool

    @State private var pulse: CardID? = nil


    /// Reads no live model field (only `router.navigationSerial` / `destination`): the bar and the cards do the reading.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BackupsTimeMachineCard(model: model, narrow: narrow, router: router)
                        .id(CardID.tm)
                        .sectionFocusPulse(pulse == .tm)
                        .ds3Appear(delay: 0.08)
                    BackupsClaudeCard(model: model)
                        .id(CardID.claude)
                        .sectionFocusPulse(pulse == .claude)
                        .ds3Appear(delay: 0.14)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.top, 16, for: .scrollContent)
            .ds3KeepFocusScroll(pulse, top: .tm, proxy: proxy, router: router)
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
            .task { await model.claudeRun.observe() }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
    }
}

// MARK: - Input and mapping helpers

@MainActor
private func backupsInput(_ model: AppModel, now: Date) -> BackupsPageModel.Input {
    .init(tmDest: model.report.tmDest, snapshots: model.report.snapshots, backup: model.timeMachine.backup,
          action: model.timeMachine.action, updatedAt: model.timeMachine.updatedAt, claudeBackup: model.claudeBackup,
          claudeLogPath: model.claudeLogPath, warnAfterHours: model.settings.backupStaleHours, now: now,
          claudeAttempt: model.claudeRun.attempt, claudeSize: model.claudeRun.size, claudeProgress: model.claudeRun.progress, claudeJob: model.claudeRun.job, claudeDiskConnected: model.claudeRun.diskConnected,
          claudeAction: model.claudeRun.action, claudeUsesDefaultLog: model.claudeUsesDefaultLog,
          deleteNames: model.homeReport.snapshots, snapshotDelete: model.timeMachine.deleteState,
          deleteConfirmOpen: model.timeMachine.showDeleteConfirm)
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

/// The header «Back up now» of both Backups cards. The label swaps for a spinner without changing the width (`swap-in-place`).
@MainActor
private func backupsHeaderButton(busy: Bool, primary: Bool, disabled: Bool, a11y: String, identifier: String,
                                 action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(L.bkBackUpNow).dsSwapInPlace(busy) { DS3Spinner(role: primary ? .onSolid : .softRing, size: 12) }
    }
    .buttonStyle(DS3ButtonStyle(kind: primary ? .primary : .secondary, height: 30, hPad: 13, fontSize: 12.5))
    .disabled(disabled)
    .accessibilityLabel(a11y)
    .ds3BusyValue(busy)
    .accessibilityIdentifier(identifier)
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it. No Refresh button on this page.
@MainActor
struct BackupsPageBar: View {
    let model: AppModel
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
    let model: AppModel
    let narrow: Bool
    /// The page's router, for `isInlineConfirmOpen` while the delete confirmation owns Esc; nil in the snapshots.
    var router: NavigationRouter? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The ageing texts («50 min ago», «in 10 min») re-render once a minute (`gpu-per-frame`).
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            card(now: model.now(or: ctx.date))
        }
        .onDisappear {
            // A confirmation must not reappear on return. A run in flight finishes; its note waits for the next visit.
            model.timeMachine.cancelSnapshotDelete()
            router?.isInlineConfirmOpen = false
        }
    }

    @ViewBuilder
    private func card(now: Date) -> some View {
        let m = BackupsPageModel.make(backupsInput(model, now: now))
        // The Storage confirm's motion: opacity + offset 14 + scale .98 with a spring; Reduce Motion: opacity only.
        let curve: Animation = reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.7)
        DS3Card(title: "Time Machine", caption: m.tmCaption, trailing: {
            // Outside the state switch (`control-identity-branch`): one button through starting, running and the end of a backup.
            HStack(spacing: 8) {
                if let d = m.tmDeleteButton { deleteSnapshotsButton(d) }
                if let b = m.tmButton { backUpNowButton(b) }
            }
        }, content: {
            switch m.tmState {
            case .wait:
                SectionWait(text: L.commonCollectingData)
            default:
                VStack(alignment: .leading, spacing: 16) {
                    if let n = m.tmNote { note(n) }
                    if let p = m.tmProgress {
                        BackupsProgressBlock(progress: p, stopBusy: model.timeMachine.action == .stopping, onStop: {
                            model.timeMachine.stopBackupNow()
                        })
                    }
                    if let f = m.tmFailure { SectionNote(tone: DS3.hot, text: f) }
                    if let d = m.tmDeleteNote { note(d) }
                    if let c = m.tmDeleteConfirm {
                        BackupsDeleteConfirmPanel(confirm: c,
                                                  onCancel: { model.timeMachine.cancelSnapshotDelete() },
                                                  onDelete: { model.timeMachine.confirmSnapshotDelete(names: c.names) })
                            .transition(reduceMotion ? .opacity
                                        : .opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.98)))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        EqualColumnsLayout(columns: m.tmState == .notSet ? 3 : (narrow ? 2 : 4), spacing: 8) {
                            ForEach(m.tmTiles, id: \.id) { t in
                                if t.id == "purgeable" { BackupsPurgeableTile(model: model) } else { backupsTileView(t) }
                            }
                        }
                        let lines = m.tmDestinationFacts
                            + (m.tmSnapshotsExplanation.map { [SectionFactLine(label: L.commonLocalSnapshots, text: $0)] } ?? [])
                        if !lines.isEmpty { SectionFactLines(rows: lines) }
                    }
                }
                .animation(curve, value: m.tmDeleteConfirm != nil)
            }
        })
        .onChange(of: m.tmDeleteConfirm != nil, initial: true) { _, open in router?.isInlineConfirmOpen = open }
    }

    /// A disabled macOS button shows no help tag, so the tooltip sits on a clear layer over it. The layer exists only
    /// while the button is disabled for that reason, so it never takes a click from an enabled button.
    private func backUpNowButton(_ b: BackupsTMButton) -> some View {
        backupsHeaderButton(busy: b.busy, primary: b.primary, disabled: !b.enabled, a11y: L.bkBackUpNowA11y,
                            identifier: "backups-tm-backup-now") { model.timeMachine.startBackupNow() }
            .overlay {
                if let help = b.help {
                    Color.clear.contentShape(Capsule()).help(help).accessibilityHidden(true)
                }
            }
    }

    /// «Delete N snapshots»: opens the confirmation. The label swaps for a spinner without changing the width (`swap-in-place`).
    /// The clear help layer is `backUpNowButton`'s: a disabled macOS button shows no help tag.
    private func deleteSnapshotsButton(_ b: BackupsTMDeleteButton) -> some View {
        Button { model.timeMachine.requestSnapshotDelete() } label: {
            Text(b.title).lineLimit(1).dsSwapInPlace(b.busy) {
                if !model.isPaused { DS3Spinner(role: .softRing, size: 12) }   // `no-unseen-work`: a run continues in the background, the spinner does not
            }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
        .disabled(!b.enabled)
        .accessibilityLabel(b.title)
        .accessibilityHint(b.help ?? "")
        .ds3BusyValue(b.busy)
        .accessibilityIdentifier("backups-tm-delete-snapshots")
        .overlay {
            if let help = b.help {
                Color.clear.contentShape(Capsule()).help(help).accessibilityHidden(true)
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
        case .openFullDiskAccess?:
            SectionNote(tone: toneColor(n.tone), text: n.text,
                        button: (L.bkOpenPrivacy, L.bkOpenPrivacyA11y, false, { AdviceActionRunner.openPane(AdvicePanes.fullDiskAccess) }),
                        buttonIdentifier: "backups-tm-privacy")
        default:
            SectionNote(tone: toneColor(n.tone), text: n.text)
        }
    }
}

/// The inline «Delete N snapshots?» confirm (the `StorageFoldersCard.confirmPanel` recipe). Cancel is the default action
/// (Return). Esc cancels through `.onExitCommand` (Cancel takes focus on appear) and a hidden `.cancelAction` button, which needs no focus.
private struct BackupsDeleteConfirmPanel: View {
    let confirm: BackupsDeleteConfirm
    let onCancel: () -> Void
    let onDelete: () -> Void
    @FocusState private var cancelFocused: Bool

    init(confirm: BackupsDeleteConfirm, onCancel: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.confirm = confirm
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(confirm.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS3.ink)
            Text(confirm.text)
                .font(.system(size: 13))
                .foregroundStyle(DS3.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L.storageConfirmCancel, action: onCancel)
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                    .keyboardShortcut(.defaultAction)
                    .focused($cancelFocused)
                    .accessibilityLabel(L.storageConfirmCancel)
                    .accessibilityIdentifier("backups-tm-delete-cancel")
                    .background {
                        Button("", action: onCancel)
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                Button(L.bkDeleteVerb, action: onDelete)
                    .buttonStyle(DS3ButtonStyle(kind: .dangerSolid, height: 30, hPad: 13, fontSize: 12.5))
                    .accessibilityLabel(confirm.confirmA11y)
                    .accessibilityIdentifier("backups-tm-delete-confirm")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.overlay))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), top: DS3.rimMid, ring: DS3.lineStrong)
        .onExitCommand(perform: onCancel)
        .onAppear { cancelFocused = true }
    }
}

/// The accent panel of a running backup: spinner, «Backing up to <disk>», bytes caption, Stop, and the 6 pt bar.
/// The bar's fraction changes only when a poll lands; only its fill width animates (`animation-value-size-coupling`).
private struct BackupsProgressBlock: View {
    let progress: BackupsProgress
    let stopBusy: Bool
    let onStop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DS3Spinner(role: .tinted, size: 14)
                Text(progress.text)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS3.accentInk)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !progress.caption.isEmpty {
                    Text(progress.caption)
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(DS3.muted)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if let onStop {
                    Button { onStop() } label: {
                        Text(L.bkStop).dsSwapInPlace(stopBusy) { DS3Spinner(role: .softRing, size: 12) }
                    }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                    .disabled(stopBusy || progress.stopping)
                    .accessibilityLabel(L.bkStopA11y)
                    .ds3BusyValue(stopBusy)
                    .accessibilityIdentifier("backups-tm-stop")
                }
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

/// Reads the live `model.disk` itself, so a disk read (every 30 s or on request, IDLE-WORK-TRIM) invalidates only this tile and not the whole card (D13).
private struct BackupsPurgeableTile: View {
    let model: AppModel

    var body: some View {
        let purgeable = model.disk?.purgeable
        SectionTile(label: L.bkPurgeable, value: purgeable.map(fmtCapacity) ?? "—", note: L.bkPurgeableNote,
                    noteInk: DS3.muted, valueInk: purgeable == nil ? DS3.muted : DS3.ink)
    }
}

// MARK: - Claude backup card

@MainActor
struct BackupsClaudeCard: View {
    let model: AppModel

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            card(now: model.now(or: ctx.date))
        }
    }

    @ViewBuilder
    private func card(now: Date) -> some View {
        let m = BackupsPageModel.make(backupsInput(model, now: now))
        DS3Card(title: L.commonClaudeBackup, caption: m.claudeCaption, trailing: {
            if let b = m.claudeButton { backUpNowButton(b) }
        }, content: {
            VStack(alignment: .leading, spacing: 16) {
                if let n = m.claudeActionNote { SectionNote(tone: toneColor(n.tone), text: n.text) }
                if let p = m.claudeRunProgress { BackupsProgressBlock(progress: p, stopBusy: false, onStop: nil) }
                if let n = m.claudeNote { note(n) }
                if !m.claudeRunTiles.isEmpty {
                    EqualColumnsLayout(columns: 3, spacing: 8) {
                        ForEach(m.claudeRunTiles, id: \.id) { backupsTileView($0) }
                    }
                }
                EqualColumnsLayout(columns: 3, spacing: 8) {
                    ForEach(m.claudeTiles, id: \.id) { backupsTileView($0) }
                }
            }
        })
    }

    private func backUpNowButton(_ b: BackupsClaudeButton) -> some View {
        backupsHeaderButton(busy: b.busy, primary: b.primary, disabled: b.busy, a11y: L.bkClaudeBackUpNowA11y,
                            identifier: "backups-claude-backup-now") { model.claudeRun.startBackupNow() }
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
