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
    var value: String = ""
    /// `DS.hot` for the "диск не подключён"/no-date state (OS:646); `DS.inkSoft`
    /// otherwise.
    var valueColor: Color = DS.inkSoft
    /// V2-FIX-MONO-FONT: this row renders in the system face, not mono — mono
    /// is reserved for verbatim machine output and the few prototype-specified
    /// sites elsewhere in the app. Numeric/quota values get `.monospacedDigit()`
    /// so digit columns line up and don't jitter as they tick; prose values
    /// (name, type, snapshot summary) get the plain system face.
    var tabularNumerals: Bool = false
    /// V2-FIX-UNITS follow-up: pre-split value/unit for the byte-quota call
    /// site — this row renders a literal space as a full glyph advance, so
    /// the quota row passes `fmtBytesParts` here instead of a plain `value:`
    /// string, and gets a tight `.padding(.leading, 1.5)` gap.
    /// (Second pass: this row's 13.5pt font makes a flat 3pt gap read
    /// proportionally wide — ~22% of the em vs. ~11% at the 27pt tile the
    /// value was copied from — so it's now 1.5pt here. V2-FIX-MONO-FONT:
    /// this padding was originally sized for a mono glyph and is deliberately
    /// held as-is rather than re-tuned now that the row is system-face —
    /// re-tuning a gap is a size change and out of this block's scope.)
    /// Every other TMRow call site keeps using `value:` unchanged.
    var valueParts: (String, String)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(DS.muted)
                .frame(width: 150, alignment: .leading)
            if let valueParts {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(valueParts.0).monospacedDigit()
                    Text(valueParts.1)
                        .monospacedDigit()
                        .padding(.leading, 1.5)
                }
                .font(.system(size: 13.5))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Group {
                    if tabularNumerals {
                        Text(value).monospacedDigit()
                    } else {
                        Text(value)
                    }
                }
                .font(.system(size: 13.5))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
            }
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
                        let quotaParts = fmtBytesParts(quota)
                        TMRow(label: L.timeMachineQuota, valueParts: (quotaParts.value, quotaParts.unit ?? ""))
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
