// Views/TimeMachineCard.swift
// Time Machine card: destination, quota, last backup, local snapshots.

import SwiftUI

// MARK: - Time Machine

@MainActor
struct TimeMachineCard: View {
    let model: DashboardModel

    /// «обновлено HH:MM» — mirrors `SmartDisksCard.updatedCaption`: `tmDest` now rides
    /// the same periodic SMART sampler (and the manual «Обновить» refresh), so its
    /// freshness timestamp is the same `smartUpdatedAt`.
    private var updatedCaption: String? {
        model.smartUpdatedAt.map { L.storageSmartUpdatedCaption($0.formatted(date: .omitted, time: .shortened)) }
    }

    var body: some View {
        CardChrome(title: "Time Machine", caption: updatedCaption) {
            switch model.report.tmDest {
            case .none:
                SectionStateView(done: model.report.progress["tmDest"] ?? false)
            case .some(.none):
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(L.timeMachineNotConfigured).font(.callout).foregroundStyle(.secondary)
                }
            case .some(.some(let dest)):
                VStack(alignment: .leading, spacing: 6) {
                    LabeledRow(label: L.timeMachineDestination, value: dest.name ?? "—")
                    if let kind = dest.kind {
                        LabeledRow(label: L.timeMachineType, value: kind == "Local" ? L.timeMachineTypeLocal : kind)
                    }
                    if let quota = dest.quotaBytes {
                        LabeledRow(label: L.timeMachineQuota, value: fmtBytes(quota))
                    }
                    LabeledRow(label: L.timeMachineLastBackup, value: dest.lastBackup ?? dest.lastBackupUnavailableReason ?? "—")
                    if let snaps = model.report.snapshots {
                        let last = snaps.max()
                        LabeledRow(label: L.timeMachineSnapshots,
                                   value: snaps.isEmpty ? L.timeMachineSnapshotsNone : L.timeMachineSnapshotsCount(snaps.count) + (last.map { L.timeMachineSnapshotsLast($0) } ?? ""))
                    }
                }
            }
        }
    }
}
