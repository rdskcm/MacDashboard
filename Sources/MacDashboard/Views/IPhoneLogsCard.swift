// Views/IPhoneLogsCard.swift
// The phone's crash-log tree grouped by bug_type category (layout only, no animation).

import SwiftUI

struct IPhoneLogsCard: View {
    let model: IPhoneModel
    let deviceKey: String
    @State private var expanded: Set<String> = ["live|appCrash"]

    private var isConnected: Bool { model.connected[deviceKey] != nil }
    private var entries: [IPhoneLogEntry]? { model.logs[deviceKey] }
    private var loading: Bool { model.logsLoading.contains(deviceKey) }

    var body: some View {
        CardChrome(title: L.iphoneLogsTitle, caption: entries.map { L.iphoneLogsCaption($0.count) }) {
            RainbowCapsuleButton(title: L.iphoneRefresh, size: .card) {
                model.loadLogs(deviceKey: deviceKey)
            }
            .disabled(!isConnected || loading)
            .accessibilityLabel(L.iphoneLogsRefreshA11y)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                phoneList
                archiveSections
            }
        }
        // First appearance for a connected phone (also when it connects while the page is open).
        .task(id: isConnected) {
            if isConnected, model.logs[deviceKey] == nil { model.loadLogs(deviceKey: deviceKey) }
        }
    }

    @ViewBuilder private var phoneList: some View {
            if let entries {
                if entries.isEmpty {
                    Text(L.iphoneLogsEmpty).font(.callout).foregroundStyle(DS.muted)
                } else {
                    groups(entries, scope: "live")
                }
            } else if loading {
                SectionStateView(done: false)
            } else if !isConnected {
                Text(L.iphoneLogsConnectToRead).font(.callout).foregroundStyle(DS.muted)
            } else {
                SectionStateView(done: false)
            }
    }

    /// Entries parsed from imported sysdiagnose archives (memory only), same grouping.
    @ViewBuilder private var archiveSections: some View {
        if let archive = model.archiveLogs[deviceKey], !archive.isEmpty {
            let name: String = {
                if case .archive(let n) = archive[0].source { return n }
                return ""
            }()
            Text(L.iphoneLogsFromArchive(name)).dsKicker()
            groups(archive, scope: "archive")
        }
    }

    private func groups(_ entries: [IPhoneLogEntry], scope: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(IPhoneData.grouped(entries), id: \.0) { cat, items in
                let tag = scope + "|" + cat.rawValue
                let isOpen = expanded.contains(tag)
                let label = L.iphoneLogsCategory(cat)
                Button {
                    if isOpen { expanded.remove(tag) } else { expanded.insert(tag) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.muted)
                            .frame(width: 12)
                        Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS.ink)
                        Text("\(items.count)").font(.system(size: 12.5)).monospacedDigit().foregroundStyle(DS.muted)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.iphoneLogsToggleA11y(label, expanded: isOpen))
                if isOpen {
                    ForEach(items) { e in row(e) }
                }
            }
        }
    }

    private func row(_ e: IPhoneLogEntry) -> some View {
        HStack(spacing: 12) {
            Text((e.path as NSString).lastPathComponent)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(e.modified.map { fmtDisplayDay($0) } ?? "—")
                .font(.system(size: 12.5)).foregroundStyle(DS.muted).monospacedDigit()
            Text(fmtBytes(e.size))
                .font(.system(size: 12.5)).foregroundStyle(DS.muted).monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.leading, 20)
    }
}
