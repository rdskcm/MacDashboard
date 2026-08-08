// Views/AdviceActionDispatch.swift
// Stateful counterpart to `AdviceActionRunner` (stateless system calls, reused
// as-is): confirmations, busy/done bookkeeping and the `AdviceAction` switch,
// moved verbatim out of the legacy Рекомендации card (Block V2-SUMMARY) so the
// new AttentionSummaryCard owns no dialog logic of its own.
//
// Shaped as an `@Observable` reference type (the codebase's established idiom
// for shared mutable UI state — see DashboardModel/AppSettings/L10nStore)
// rather than a `ViewModifier` value type: the card needs to READ this state
// (pendingTrashID/completedAdviceIDs/trashError) while laying out chips/plates,
// not just have it silently attached — a ViewModifier's own @State isn't
// legible from outside. `.adviceActionDialogs(_:)` below is the actual
// ViewModifier: it attaches the two confirmation dialogs to the card.

import SwiftUI

@MainActor
@Observable
final class AdviceActionDispatch {
    let model: DashboardModel

    init(model: DashboardModel) {
        self.model = model
    }

    /// Advice id (AttentionItem/TipCapsule `.id`) awaiting the empty-trash
    /// confirmation dialog; nil = no confirmation pending.
    var pendingTrashID: String? = nil
    var showFirewallConfirm = false
    /// Advice ids whose action already completed successfully this session
    /// (currently only `.emptyTrash`) — the plate keeps rendering (assessment
    /// still lists it until the next report refresh drops it) but shows a done
    /// state instead of its verb.
    var completedAdviceIDs: Set<String> = []
    var trashError: String? = nil

    var trashConfirmBinding: Binding<Bool> {
        Binding(get: { self.pendingTrashID != nil }, set: { if !$0 { self.pendingTrashID = nil } })
    }

    func handle(_ action: AdviceAction, id: String) {
        switch action {
        case .settingsPane(let u): AdviceActionRunner.openPane(u)
        case .openApp(let p): AdviceActionRunner.openApp(p)
        case .revealPath(let p): AdviceActionRunner.reveal(p)
        case .brewUpgrade: model.upgradeBrewNow()
        case .emptyTrash: pendingTrashID = id
        case .enableFirewall: showFirewallConfirm = true
        }
    }

    func confirmEmptyTrash() {
        let id = pendingTrashID
        AdviceActionRunner.emptyTrash { [weak self] ok in
            guard let self else { return }
            if ok {
                if let id { self.completedAdviceIDs.insert(id) }
                self.trashError = nil
            } else {
                self.trashError = L.adviceTrashError
            }
        }
    }

    func busy(for action: AdviceAction?) -> Bool {
        switch action {
        case .brewUpgrade: return model.brewUpgrading
        case .enableFirewall: return model.firewallApplying
        default: return false
        }
    }

    func busyDetail(for action: AdviceAction?) -> String? {
        action == .brewUpgrade && model.brewUpgrading ? model.brewProgress.map(brewProgressText) : nil
    }

    func done(_ id: String) -> Bool { completedAdviceIDs.contains(id) }
}

/// Attaches the trash-empty and enable-firewall confirmation dialogs — moved
/// verbatim (behavior-identical) from the legacy Рекомендации card.
private struct AdviceActionDialogs: ViewModifier {
    let dispatch: AdviceActionDispatch

    func body(content: Content) -> some View {
        content
            .confirmationDialog(L.adviceTrashConfirmTitle, isPresented: dispatch.trashConfirmBinding) {
                Button(L.adviceTrashConfirmButton, role: .destructive) {
                    dispatch.confirmEmptyTrash()
                }
                Button(L.adviceCancel, role: .cancel) {}
            }
            .confirmationDialog(L.adviceFirewallConfirmTitle, isPresented: Binding(
                get: { dispatch.showFirewallConfirm },
                set: { dispatch.showFirewallConfirm = $0 }
            )) {
                Button(L.adviceFirewallConfirmButton) { dispatch.model.enableFirewallNow() }
                Button(L.adviceCancel, role: .cancel) {}
            } message: {
                Text(L.adviceFirewallConfirmMessage)
            }
    }
}

extension View {
    func adviceActionDialogs(_ dispatch: AdviceActionDispatch) -> some View {
        modifier(AdviceActionDialogs(dispatch: dispatch))
    }
}
