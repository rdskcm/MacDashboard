// Views/RecommendationsCard.swift
// Рекомендации card: assessment problems + tips, or a quiet "all good" state.
// Rows carrying an AdviceAction (AR wave 2) are clickable — hover/chevron affordance
// mirrors StorageCards' DirBarRow — and drive confirmations + model-owned actions.

import SwiftUI
import AppKit

// MARK: - Рекомендации

@MainActor
struct RecommendationsCard: View {
    let model: DashboardModel

    /// Advice id (Problem/Tip `.id`, i.e. its text) awaiting the empty-trash
    /// confirmation dialog; nil = no confirmation pending.
    @State private var pendingTrashID: String? = nil
    @State private var showFirewallConfirm = false
    /// Advice ids whose action already completed successfully this session (currently
    /// only `.emptyTrash`) — the row keeps rendering (assessment still lists it until
    /// the next report refresh drops it) but shows a done state instead of a chevron.
    @State private var completedAdviceIDs: Set<String> = []
    @State private var trashError: String? = nil

    // Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
    #if AI_ENABLED
    /// Refreshed in `.onAppear` and again when the AI sheet is dismissed, so a
    /// key just saved/deleted in Settings is reflected without restarting the app.
    @State private var aiKeyExists = false
    @State private var showAISheet = false
    #endif

    var body: some View {
        CardChrome(title: L.recommendationsTitle, caption: L.recommendationsCaption, trailing: {
            #if AI_ENABLED
            if AppSettings.shared.aiConfig.isComplete && aiKeyExists {
                Button {
                    showAISheet = true
                } label: {
                    Label(L.aiAskButton, systemImage: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            #endif
        }, content: {
            let problems = model.assessment.problems
            let tips = model.assessment.tips
            if problems.isEmpty && tips.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Severity.good.color)
                    Text(L.recommendationsAllGood)
                        .font(.callout.weight(.medium))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(problems) { p in
                        adviceRow(sev: p.sev, text: p.text, isTip: false, action: p.action, id: p.id)
                    }
                    ForEach(tips) { tip in
                        adviceRow(sev: .info, text: tip.text, isTip: true, action: tip.action, id: tip.id)
                    }
                    if let trashError {
                        Text(trashError).font(.caption2).foregroundStyle(.red)
                    }
                    if let adviceActionError = model.adviceActionError {
                        Text(adviceActionError).font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        })
        .confirmationDialog(L.adviceTrashConfirmTitle, isPresented: trashConfirmBinding) {
            Button(L.adviceTrashConfirmButton, role: .destructive) {
                let id = pendingTrashID
                AdviceActionRunner.emptyTrash { ok in
                    if ok {
                        if let id { completedAdviceIDs.insert(id) }
                        trashError = nil
                    } else {
                        trashError = L.adviceTrashError
                    }
                }
            }
            Button(L.adviceCancel, role: .cancel) {}
        }
        .confirmationDialog(L.adviceFirewallConfirmTitle, isPresented: $showFirewallConfirm) {
            Button(L.adviceFirewallConfirmButton) { model.enableFirewallNow() }
            Button(L.adviceCancel, role: .cancel) {}
        } message: {
            Text(L.adviceFirewallConfirmMessage)
        }
        #if AI_ENABLED
        .onAppear { aiKeyExists = KeychainStore.exists() }
        .sheet(isPresented: $showAISheet, onDismiss: { aiKeyExists = KeychainStore.exists() }) {
            AIAskSheet(model: model)
        }
        #endif
    }

    private var trashConfirmBinding: Binding<Bool> {
        Binding(get: { pendingTrashID != nil }, set: { if !$0 { pendingTrashID = nil } })
    }

    /// One problem/tip row: today's plain content, plus (when `action != nil`) the
    /// DirBarRow hover/chevron affordance, plus busy (brew/firewall in flight) and
    /// done (trash emptied) states layered on top.
    @ViewBuilder
    private func adviceRow(sev: Severity, text: String, isTip: Bool, action: AdviceAction?, id: String) -> some View {
        let done = completedAdviceIDs.contains(id)
        let busy: Bool = {
            switch action {
            case .brewUpgrade: return model.brewUpgrading
            case .enableFirewall: return model.firewallApplying
            default: return false
            }
        }()
        let busyDetail: String? = action == .brewUpgrade && model.brewUpgrading
            ? model.brewProgress.map(brewProgressText) : nil
        AdviceRow(sev: sev, text: text, isTip: isTip, action: action, done: done, busy: busy, busyDetail: busyDetail) {
            if let action { handle(action, id: id) }
        }
    }

    private func handle(_ action: AdviceAction, id: String) {
        switch action {
        case .settingsPane(let u): AdviceActionRunner.openPane(u)
        case .openApp(let p): AdviceActionRunner.openApp(p)
        case .revealPath(let p): AdviceActionRunner.reveal(p)
        case .brewUpgrade: model.upgradeBrewNow()
        case .emptyTrash: pendingTrashID = id
        case .enableFirewall: showFirewallConfirm = true
        }
    }
}

/// A single advice row: plain (no action), clickable (hover + chevron), busy
/// (inline spinner, tap disabled) or done (checkmark, trailing "готово"/"done",
/// no chevron, no tap) — mirrors StorageCards' `DirBarRow` affordance idiom.
private struct AdviceRow: View {
    let sev: Severity
    let text: String
    let isTip: Bool
    let action: AdviceAction?
    let done: Bool
    let busy: Bool
    let busyDetail: String?
    let onTap: () -> Void

    @State private var hovering = false
    /// True while we hold an outstanding `NSCursor.pointingHand.push()` — tracked
    /// explicitly (rather than inferring from `hovering`/`isInteractive`) so a
    /// mid-hover interactive→busy transition (e.g. tapping brew/firewall while the
    /// mouse stays put) still balances the push with a pop, instead of leaving the
    /// pointing-hand cursor stuck until the mouse happens to move.
    @State private var cursorPushed = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Severity.good.color)
                    .padding(.top, 3)
            } else {
                SeverityDot(sev: sev).padding(.top, 5)
            }
            if busy, let busyDetail {
                VStack(alignment: .leading, spacing: 2) {
                    label
                    Text(busyDetail).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                label
            }
            Spacer(minLength: 8)
            if done {
                Text(L.adviceDone).font(.caption).foregroundStyle(.secondary)
            } else if busy {
                ProgressView().controlSize(.small)
            } else if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering && isInteractive ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                guard isInteractive else { return }
                hovering = true
                if !cursorPushed { NSCursor.pointingHand.push(); cursorPushed = true }
            } else {
                hovering = false
                if cursorPushed { NSCursor.pop(); cursorPushed = false }
            }
        }
        .onChange(of: isInteractive) { _, nowInteractive in
            // Row went busy/done while the mouse stayed put (no onHover fired) —
            // balance the push immediately rather than waiting for mouse-exit.
            guard !nowInteractive else { return }
            hovering = false
            if cursorPushed { NSCursor.pop(); cursorPushed = false }
        }
        .onTapGesture {
            guard isInteractive else { return }
            onTap()
        }
    }

    private var isInteractive: Bool { action != nil && !busy && !done }

    @ViewBuilder
    private var label: some View {
        if isTip {
            (Text(L.recommendationsTipPrefix).font(.callout.weight(.semibold))
                + Text(text).font(.callout))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(.callout)
                .foregroundStyle(done ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
