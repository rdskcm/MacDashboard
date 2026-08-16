// Views/AdviceActionDispatch.swift
// Stateful counterpart to `AdviceActionRunner` (stateless system calls, reused
// as-is): confirmations, busy/done bookkeeping and the `AdviceAction` switch,
// moved verbatim out of the legacy Рекомендации card (Block V2-SUMMARY) so the
// new AttentionSummaryCard owns no dialog logic of its own.
//
// Shaped as an `@Observable` reference type (the codebase's established idiom
// for shared mutable UI state — see DashboardModel/AppSettings/L10nStore)
// rather than a `ViewModifier` value type: the card needs to READ this state
// (completedAdviceIDs/trashError) while laying out chips/plates,
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

    /// Whether the empty-trash confirmation dialog is up.
    ///
    /// Kept SEPARATE from the advice id below on purpose. These used to be one
    /// optional whose nil-ness both drove the dialog and identified the target: the
    /// dialog's dismissal cleared it, so whether the confirm button's action still saw
    /// an id depended on whether SwiftUI runs the action before or after writing the
    /// isPresented binding. When it lost that race the Trash was emptied but the done
    /// state never appeared. Correctness must not rest on that ordering.
    var showTrashConfirm = false
    /// Advice id (AttentionItem/TipCapsule `.id`) the pending empty-trash applies to,
    /// captured when the action is dispatched and cleared only when it completes.
    private var trashTargetID: String? = nil
    var showFirewallConfirm = false
    /// Whether the brew-upgrade confirmation is up (SPEC §1.6 row 5). Same plain-Bool
    /// shape as the firewall gate above — brew needs no target id the way trash does.
    var showBrewConfirm = false
    /// Advice ids whose action already completed successfully this session
    /// (currently only `.emptyTrash`) — the plate keeps rendering (assessment
    /// still lists it until the next report refresh drops it) but shows a done
    /// state instead of its verb.
    var completedAdviceIDs: Set<String> = []
    var trashError: String? = nil

    var trashConfirmBinding: Binding<Bool> {
        Binding(get: { self.showTrashConfirm }, set: { self.showTrashConfirm = $0 })
    }

    func handle(_ action: AdviceAction, id: String) {
        switch action {
        case .settingsPane(let u): AdviceActionRunner.openPane(u)
        case .openApp(let p): AdviceActionRunner.openApp(p)
        case .revealPath(let p): AdviceActionRunner.reveal(p)
        case .brewUpgrade:
            guard model.report.brewOutdated?.isEmpty == false else { return }
            showBrewConfirm = true
        case .emptyTrash:
            trashTargetID = id
            showTrashConfirm = true
        case .enableFirewall: showFirewallConfirm = true
        }
    }

    func confirmEmptyTrash() {
        let id = trashTargetID
        AdviceActionRunner.emptyTrash { [weak self] outcome in
            guard let self else { return }
            self.trashTargetID = nil
            switch outcome {
            case .emptied:
                if let id { self.completedAdviceIDs.insert(id) }
                self.trashError = nil
            case .cancelled:
                // Backing out is not a failure: leave the plate on its verb, say nothing.
                self.trashError = nil
            case .failed(let detail):
                // Finder's own message is more useful than our generic line ("the item
                // is in use", a locked file), and it arrives already localized.
                self.trashError = detail.map { "\(L.adviceTrashError): \($0)" } ?? L.adviceTrashError
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
            .brewUpgradeConfirm(isPresented: Binding(
                get: { dispatch.showBrewConfirm },
                set: { dispatch.showBrewConfirm = $0 }
            ), model: dispatch.model)
    }
}

extension View {
    func adviceActionDialogs(_ dispatch: AdviceActionDispatch) -> some View {
        modifier(AdviceActionDialogs(dispatch: dispatch))
    }
}
