// Views/SecurityCard.swift
// Безопасность card: FileVault, Gatekeeper, SIP, firewall status rows.

import SwiftUI

// MARK: - Безопасность

struct SecurityCard: View {
    let model: DashboardModel
    let state: QuietState
    var body: some View {
        switch state.security {
        case .collecting:
            CardChrome(title: L.securityTitle) { SectionStateView(done: model.report.progress["security"] ?? false) }
        case .quiet:
            EmptyView()   // the strip owns it
        case .loud:
            LoudSectionCard(title: L.securityTitle,
                             dotColor: state.securityOffCount > 0 ? DS.hot : DS.amber,
                             failTone: DS.hot,
                             rows: securityRows(model.report.security ?? SecurityState())) {
                EmptyView()
            }
        }
    }
}
