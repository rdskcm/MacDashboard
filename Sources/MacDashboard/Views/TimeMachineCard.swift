// Views/TimeMachineCard.swift
// Time Machine card: destination, quota, last backup, local snapshots.

import SwiftUI

// MARK: - Time Machine

/// One label→value row (spec §5.10): 150 pt fixed label column (`DS.muted`,
/// 11.5 pt) · value right, mono font family so numeric values (quota) read
/// as tabular columns — `LabeledRow` (SharedUI.swift) is out of scope for
/// this v2 restyle, so this is a private, card-local row (same convention
/// `DirBarRow`/`DirBarList` already use in StorageCards.swift).
private struct TMRow: View {
    let label: String
    let value: String
    /// `DS.hot` for the "диск не подключён"/no-date state (OS:646); `DS.inkSoft`
    /// otherwise.
    var valueColor: Color = DS.inkSoft
    /// Numeric values (quota) get `.monospacedDigit()` on top of the shared
    /// mono font family so digit columns actually line up; text values (name,
    /// type, snapshot summary) keep the mono family but don't need it.
    var tabularNumerals: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(DS.muted)
                .frame(width: 150, alignment: .leading)
            Group {
                if tabularNumerals {
                    Text(value).monospacedDigit()
                } else {
                    Text(value)
                }
            }
            .font(.system(size: 13.5, design: .monospaced))
            .foregroundStyle(valueColor)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

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
                    Image(systemName: "info.circle").foregroundStyle(DS.muted)
                    Text(L.timeMachineNotConfigured)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS.inkSoft)
                }
            case .some(.some(let dest)):
                VStack(alignment: .leading, spacing: 10) {
                    TMRow(label: L.timeMachineDestination, value: dest.name ?? "—")
                    if let kind = dest.kind {
                        TMRow(label: L.timeMachineType, value: kind == "Local" ? L.timeMachineTypeLocal : kind)
                    }
                    if let quota = dest.quotaBytes {
                        TMRow(label: L.timeMachineQuota, value: fmtBytes(quota), tabularNumerals: true)
                    }
                    TMRow(
                        label: L.timeMachineLastBackup,
                        value: dest.lastBackup ?? dest.lastBackupUnavailableReason ?? "—",
                        // No resolvable backup date (disk unmounted, no permission, …)
                        // reads in `hot` — the "диск не подключён" state (spec §5.10).
                        valueColor: dest.lastBackup == nil ? DS.hot : DS.inkSoft
                    )
                    if let snaps = model.report.snapshots {
                        let last = snaps.max()
                        TMRow(label: L.timeMachineSnapshots,
                              value: snaps.isEmpty ? L.timeMachineSnapshotsNone : L.timeMachineSnapshotsCount(snaps.count) + (last.map { L.timeMachineSnapshotsLast($0) } ?? ""))
                    }
                }
            }
        }
    }
}
