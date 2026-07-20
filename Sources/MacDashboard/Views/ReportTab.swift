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
        HStack(spacing: 12) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([model.reportURL])
            } label: {
                Label(L.reportShowInFinder, systemImage: "folder")
            }

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(model.reportText ?? "", forType: .string)
            } label: {
                Label(L.reportCopy, systemImage: "doc.on.doc")
            }
            .disabled(model.reportText == nil)

            Spacer()

            if let updated = model.reportUpdatedAt {
                Text(L.storageSmartUpdatedCaption(reportUpdatedTimeString(updated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.isCollectingReport {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L.reportCollecting)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }
}
