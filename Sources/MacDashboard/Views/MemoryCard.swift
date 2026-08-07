// Views/MemoryCard.swift
// Память card (LIVE, chart/table): stacked memory breakdown, legend tooltips and table.

import SwiftUI

// MARK: - Память (LIVE, chart/table)

private var memoryNotes: [String: String] {
    [
        L.memoryLegendActive: L.memoryNoteActive,
        L.memoryLegendWired: L.memoryNoteWired,
        L.memoryLegendOther: L.memoryNoteOther,
        L.memoryLegendInactive: L.memoryNoteInactive,
        L.memoryLegendSpeculative: L.memoryNoteSpeculative,
        L.memoryLegendFree: L.memoryNoteFree,
        L.memoryLegendPurgeable: L.memoryNotePurgeable,
        L.memoryLegendFileCache: L.memoryNoteFileCache
    ]
}

/// Segment keys whose bar width animates on change (FIX 2): the three "live"
/// buckets that actually move sample-to-sample. "inactive"/"speculative" are
/// fixed placeholder fractions and "free" just fills the remainder — none of
/// those three animate, they snap like before.
private let memoryAnimatedSegmentKeys: Set<String> = ["active", "wired", "other"]

/// Same curve/duration as `MeterBar`'s `animated` mode (SharedUI.swift) and
/// `ProcessCards.swift`'s `processRowMotion` — the app-wide bar/gauge-width
/// timing. Defined locally since neither of those constants is shared/public.
private let memorySegmentMotion = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.8)

private struct MemSegment {
    let key: String
    let label: String
    /// Bar-fill color.
    let color: Color
    /// Legend/table swatch color — same as `color` for every segment except
    /// "free" (FIX 3: the bar fill is `DS.track`, the legend/table swatch is
    /// a distinct fixed literal, never the same color).
    let legendColor: Color
    let bytes: Int64

    init(key: String, label: String, color: Color, legendColor: Color? = nil, bytes: Int64) {
        self.key = key
        self.label = label
        self.color = color
        self.legendColor = legendColor ?? color
        self.bytes = bytes
    }
}

private func memorySegments(_ mem: MemSnapshot) -> [MemSegment] {
    [
        MemSegment(key: "active", label: L.memoryLegendActive, color: SeriesPalette.s1, bytes: mem.active),
        MemSegment(key: "wired", label: L.memoryLegendWired, color: SeriesPalette.s2, bytes: mem.wired),
        MemSegment(key: "other", label: L.memoryLegendOther, color: SeriesPalette.s3, bytes: mem.otherBytes),
        MemSegment(key: "inactive", label: L.memoryLegendInactive, color: SeriesPalette.s4, bytes: mem.inactive),
        MemSegment(key: "speculative", label: L.memoryLegendSpeculative, color: SeriesPalette.s5, bytes: mem.speculative),
        // FIX 3: bar fill is the recessed DS.track token (not a solid palette
        // color); the legend swatch is a distinct fixed #7E8896 literal.
        MemSegment(key: "free", label: L.memoryLegendFree, color: DS.track,
                   legendColor: Color(hex: 0x7E8896), bytes: mem.free)
    ].filter { $0.bytes > 0 }
}

struct MemoryCard: View {
    let model: DashboardModel

    var body: some View {
        if let mem = model.mem, mem.total > 0 {
            ChartOrTableCard(title: L.memoryTitle(fmtBytes(mem.total)),
                              caption: L.memoryCaption,
                              infoHelp: L.memoryInfoHelp) {
                MemoryStackChart(model: model)
            } table: {
                MemoryTable(model: model)
            }
        } else {
            CardChrome(title: L.kpiMemLabel) {
                SectionStateView(done: false)
            }
        }
    }
}

@MainActor
private struct MemoryStackChart: View {
    let model: DashboardModel

    var body: some View {
        if let mem = model.mem {
            let segments = memorySegments(mem)
            let total = max(mem.total, 1)
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(segments, id: \.key) { seg in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(seg.color)
                                .frame(width: max(3, geo.size.width * CGFloat(Double(seg.bytes) / Double(total))))
                                .animation(memoryAnimatedSegmentKeys.contains(seg.key) ? memorySegmentMotion : nil,
                                           value: seg.bytes)
                        }
                    }
                }
                .frame(height: 24)

                // FIX 7: row gap 8 / column gap 22 — see MemoryLegendFlowLayout
                // below (a MemoryCard-local layout; the shared `FlowLayout` in
                // SharedUI.swift is out of scope for this pass).
                MemoryLegendFlowLayout(columnSpacing: 22, rowSpacing: 8) {
                    ForEach(segments, id: \.key) { seg in
                        LegendItem(color: seg.legendColor, label: seg.label, value: fmtBytes(seg.bytes))
                            .hoverTip(memoryNotes[seg.label] ?? "")
                    }
                }

                Text(footerNote(mem))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.muted)
            }
        }
    }

    private func footerNote(_ mem: MemSnapshot) -> String {
        var bits: [String] = []
        if let swap = model.swap {
            bits.append(L.memorySwapNote(fmtBytes(swap.used), fmtBytes(swap.total)))
        }
        bits.append(L.memoryOtherNote)
        return bits.joined(separator: " · ")
    }
}

/// Minimal flow/wrap layout local to the memory legend (FIX 7): needs distinct
/// row-gap (8) vs column-gap (22), which the shared `FlowLayout`
/// (SharedUI.swift) doesn't support and is out of scope to modify in this
/// pass. Same wrap algorithm as `FlowLayout`, just with two spacing axes.
private struct MemoryLegendFlowLayout: Layout {
    var columnSpacing: CGFloat = 22
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + columnSpacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + columnSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

@MainActor
private struct MemoryTable: View {
    let model: DashboardModel

    /// Plain (non-ViewBuilder) computed property: imperative row-building lives
    // here, not inside `body`, so appending to an array isn't misparsed as a
    // View-producing branch by the result builder. Pairs each row's display
    // cells with its leading swatch color (FIX 4): the two reference-only
    // rows ("Выгружаемая"/"Файловый кэш") get `.clear` so the swatch column
    // still reserves its layout space without showing a color.
    private var tableRows: [(cells: [String], swatch: TableSwatch)]? {
        guard let mem = model.mem else { return nil }
        let segments = memorySegments(mem)
        let total = max(mem.total, 1)
        var r: [(cells: [String], swatch: TableSwatch)] = segments.map { seg in
            (cells: [seg.label, fmtBytes(seg.bytes), fmtNum(Double(seg.bytes) / Double(total) * 100, decimals: 1) + "%"],
             swatch: .filled(seg.legendColor))
        }
        if mem.purgeable > 0 {
            r.append((cells: [L.memoryLegendPurgeable, fmtBytes(mem.purgeable),
                       fmtNum(Double(mem.purgeable) / Double(total) * 100, decimals: 1) + "%"],
                      swatch: .outline))
        }
        if mem.fileBacked > 0 {
            r.append((cells: [L.memoryLegendFileCache, fmtBytes(mem.fileBacked),
                       fmtNum(Double(mem.fileBacked) / Double(total) * 100, decimals: 1) + "%"],
                      swatch: .outline))
        }
        return r
    }

    var body: some View {
        if let tableRows {
            SimpleTable(
                headers: [L.memoryColCategory, L.memoryColVolume, L.storageColShare],
                rows: tableRows.map(\.cells),
                numericColumns: [1, 2],
                cellTooltip: { r, c in
                    guard c == 0, r < tableRows.count else { return nil }
                    return memoryNotes[tableRows[r].cells[0]]
                },
                swatches: tableRows.map(\.swatch),
                columnSpacing: 10
            )
        }
    }
}
