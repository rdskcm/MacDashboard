// Views/ReportTab.swift
// Implemented in Phase 2 by UI agent (see SPEC §3, §8, §7).
// Monospaced scrollable report text + toolbar («Показать в Finder», «Скопировать»,
// collection spinner). Reads model.reportText / model.reportURL / model.isCollectingReport.

import SwiftUI
import AppKit

@MainActor
struct ReportTab: View {
    var model: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                Text(model.reportText ?? placeholder)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    private var placeholder: String {
        L.reportPlaceholder
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if let updated = model.reportUpdatedAt {
                Text(L.reportFileUpdatedCaption(reportUpdatedTimeString(updated)))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.muted)
            }

            if model.isCollectingReport {
                HStack(spacing: 6) {
                    DSSpinner()
                    Text(L.reportCollecting)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.muted)
                }
            }

            Spacer()

            RainbowCapsuleButton(title: L.reportShowInFinder, recipe: .overview) {
                AdviceActionRunner.reveal(model.reportURL.path)
            }
            .accessibilityLabel(L.reportShowInFinder)

            RainbowCapsuleButton(title: L.reportCopy, recipe: .overview) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(model.reportText ?? "", forType: .string)
            }
            .accessibilityLabel(L.reportCopy)
            .disabled(model.reportText == nil)
        }
        .padding(12)
    }
}
