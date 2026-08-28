// Views/BrewUpgradeConfirm.swift
// Confirmation gate for `brew upgrade` (SPEC §1.6 row 5, block V2-ACTION-GATES).
// The action has TWO entry points — the Обслуживание системы card button and the
// attention card's Homebrew capsule — so the dialog and its message builder live
// here once and both sites attach the modifier. Shaped like `AdviceActionDialogs`
// in AdviceActionDispatch.swift: private ViewModifier + an `extension View` verb.

import SwiftUI

enum BrewUpgradeConfirm {
    /// How many package names the dialog spells out before collapsing the rest into
    /// `L.maintenanceAndMore`. 10 is deliberately higher than the card's own 5-name
    /// caption: that caption is a two-line inline label next to the button, this is
    /// the last screen before the action runs and can afford the detail — while
    /// still bounding the alert's height on a 900 pt window.
    static let listCap = 10

    /// "pkg1, pkg2, …" plus "и ещё N" / "and N more" once the list exceeds `listCap`.
    static func message(_ outdated: [String]) -> String {
        let shown = outdated.prefix(listCap)
        let rest = outdated.count - shown.count
        let names = shown.joined(separator: ", ")
        return rest > 0 ? "\(names), \(L.maintenanceAndMore(rest))" : names
    }
}

private struct BrewUpgradeConfirmDialog: ViewModifier {
    @Binding var isPresented: Bool
    let model: DashboardModel

    func body(content: Content) -> some View {
        let outdated = model.report.brewOutdated ?? []
        return content.confirmationDialog(
            L.maintenanceBrewConfirmTitle(outdated.count),
            isPresented: $isPresented
        ) {
            Button(L.maintenanceBrewConfirmButton) { model.upgradeBrewNow() }
            Button(L.adviceCancel, role: .cancel) {}
        } message: {
            Text(BrewUpgradeConfirm.message(outdated))
        }
    }
}

extension View {
    /// Gates `DashboardModel.upgradeBrewNow()` behind an informative confirmation:
    /// how many packages, and which ones.
    func brewUpgradeConfirm(isPresented: Binding<Bool>, model: DashboardModel) -> some View {
        modifier(BrewUpgradeConfirmDialog(isPresented: isPresented, model: model))
    }
}
