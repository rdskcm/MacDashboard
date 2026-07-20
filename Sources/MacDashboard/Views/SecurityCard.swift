// Views/SecurityCard.swift
// Безопасность card: FileVault, Gatekeeper, SIP, firewall status rows.

import SwiftUI

// MARK: - Безопасность

private struct SecurityRow: View {
    let label: String
    let value: Bool?
    var body: some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            switch value {
            case .some(true):
                Text("\u{2713}").font(.callout.bold()).foregroundStyle(Severity.good.color)
            case .some(false):
                Text("\u{2715}").font(.callout.bold()).foregroundStyle(Severity.crit.color)
            case .none:
                Text("?").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct SecurityCard: View {
    let model: DashboardModel
    var body: some View {
        CardChrome(title: L.securityTitle) {
            if let sec = model.report.security {
                VStack(alignment: .leading, spacing: 8) {
                    SecurityRow(label: L.securityFileVault, value: sec.fileVault)
                    SecurityRow(label: "Gatekeeper", value: sec.gatekeeper)
                    SecurityRow(label: L.securitySip, value: sec.sip)
                    SecurityRow(label: L.securityFirewall, value: sec.firewall)
                }
            } else {
                SectionStateView(done: model.report.progress["security"] ?? false)
            }
        }
    }
}
