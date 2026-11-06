// Views/SocCoresCard.swift
// SOC-DETAILS 2.4 (design 7.5): the full-width CPU cores card. One row per core group: a 200 pt heading column
// (swatch, "Performance · 4", frequency) and a grid of cells, each a core id, its load and a 5 pt bar. The number of
// columns comes from `SocCoresCardModel.columns` through `SocCoreGridLayout`, which reads only the proposed width.
//
// Every bar is a `BarFillLayer` (Core Animation), so a tick costs one commit and no per-frame SwiftUI work. The group
// hue never depends on the value (D14). Nothing is measured and fed back (`no-measured-size-feedback`).

import SwiftUI

/// Internal: the visual fixture renders it (Tests/MacDashboardTests/ContentSnapshotTests.swift).
@MainActor
struct SocCoresCard: View {
    let model: AppModel

    var body: some View {
        // Stage 5a: the body reads only the slot list and the failure flag. A load or frequency change is read by its
        // own cell or heading, so a tick does not re-run this body. While the slots do not exist yet (the off-main
        // setup has not finished) transient slots with the same ids give the card its final height on the first frame.
        let sampler = model.socLive
        let groups = sampler.coreSlots ?? SocCoreGroupSlot.make(sampler.displayCores ?? [])
        DS3Card(title: L.socCoresTitle, caption: SocCoresCardModel.caption(loadFailed: sampler.coreLoadsFailed)) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    let hue = SocCoresCardModel.hue(forName: group.group.name)
                    HStack(alignment: .top, spacing: 16) {
                        SocCoreGroupHeading(slot: group)
                            .frame(width: 200, alignment: .leading)
                        SocCoreGridLayout {
                            ForEach(group.cells) { cell in
                                SocCoreCell(slot: cell, sampler: sampler, hue: SocCoresCard.hue(hue))
                            }
                        }
                    }
                }
            }
        }
    }

    /// One hue per group, never by value (D14): P blue, E sky, a third type purple.
    static func hue(_ index: Int) -> Color {
        switch index % 3 {
        case 0: return DS3.s1
        case 1: return DS3.s8
        default: return DS3.s9
        }
    }
}

// MARK: - Heading column

private struct SocCoreGroupHeading: View {
    let slot: SocCoreGroupSlot

    var body: some View {
        let heading = SocCoresCardModel.heading(slot.group)
        let hue = SocCoresCardModel.hue(forName: slot.group.name)
        let frequency = SocCoresCardModel.frequency(slot.frequency)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(SocCoresCard.hue(hue))
                    .frame(width: 10, height: 10)
                Text(heading)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS3.inkSoft)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L.socFrequency)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS3.muted)
                Text(frequency.text)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(frequency.isValue ? DS3.ink : DS3.muted)
            }
            .lineLimit(1)
            .padding(.leading, 17)
            .hoverTip(frequency.help ?? "")
        }
    }
}

// MARK: - Cell

private struct SocCoreCell: View {
    let slot: SocCoreCellSlot
    let sampler: SocLiveSampler
    let hue: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cell = SocCoresCardModel.cell(id: slot.id, load: slot.load, loadFailed: sampler.coreLoadsFailed,
                                          hasReading: sampler.hasCoreReading)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(cell.id)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS3.muted)
                Spacer(minLength: 0)
                Text(cell.valueText)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(cell.valueText == "—" ? DS3.muted : DS3.ink)
            }
            .lineLimit(1)
            .frame(height: 16)
            Capsule().fill(DS3.track)
                .frame(height: 5)
                .overlay {
                    BarFillLayer(spans: [BarSpan(key: "core", fraction: CGFloat(cell.fraction), color: hue)],
                                 layout: .single(minWidth: 0, cornerRadius: nil),
                                 animated: !reduceMotion)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("soc-core-bar")
                }
        }
        .frame(height: SocCoreGridLayout.cellHeight)
        // "P3 · 63 %"; nothing before the first reading (an empty text shows no tip).
        .hoverTip(cell.valueText.isEmpty ? "" : "\(cell.id) · \(cell.valueText)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cell.valueText.isEmpty ? cell.id : "\(cell.id), \(cell.valueText)")
    }
}

// MARK: - Grid layout

/// Cells in `k` equal columns (gap 12 x 10), `k` from `SocCoresCardModel.columns(count:cellsArea:)`. The cells area is
/// the proposed width, nothing measured from the cells, so no size feeds back (`no-measured-size-feedback`).
/// Modelled on `EqualColumnsLayout` (Views/HomeSectionTiles.swift).
struct SocCoreGridLayout: Layout {
    static let columnGap: CGFloat = 12
    static let rowGap: CGFloat = 10
    static let cellHeight: CGFloat = 26
    /// Design 7.5: a cell is at least 96 pt wide.
    static let minCellWidth: CGFloat = 96

    private func width(_ proposal: ProposedViewSize, count n: Int) -> CGFloat {
        if let w = proposal.width, w.isFinite { return w }
        // nil or infinite proposal: one row at the minimum cell width (never infinite, so the result is finite).
        return CGFloat(n) * Self.minCellWidth + CGFloat(max(0, n - 1)) * Self.columnGap
    }

    private func height(rows: Int) -> CGFloat {
        CGFloat(rows) * Self.cellHeight + CGFloat(max(0, rows - 1)) * Self.rowGap
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let n = subviews.count
        guard n > 0 else { return .zero }
        let w = width(proposal, count: n)
        let k = SocCoresCardModel.columns(count: n, cellsArea: w)
        return CGSize(width: w, height: height(rows: (n + k - 1) / k))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = subviews.count
        guard n > 0 else { return }
        let k = SocCoresCardModel.columns(count: n, cellsArea: bounds.width)
        let cellWidth = max(0, (bounds.width - Self.columnGap * CGFloat(k - 1)) / CGFloat(k))
        for (i, subview) in subviews.enumerated() {
            let row = i / k, col = i % k
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(col) * (cellWidth + Self.columnGap),
                                      y: bounds.minY + CGFloat(row) * (Self.cellHeight + Self.rowGap)),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: cellWidth, height: Self.cellHeight))
        }
    }
}
