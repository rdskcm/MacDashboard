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

/// The memory bar's geometry: 2 pt gaps, a 3 pt minimum per segment, 2 pt corners —
/// exactly what the old `HStack` of `RoundedRectangle`s produced implicitly (a
/// clamped sub-3-pt segment pushes its successors right and the row may overflow).
private let memoryBarLayout = BarFillLayout.segments(gap: 2, minWidth: 3, cornerRadius: 2)

private func memoryBarSpans(_ segments: [MemSegment], total: Int64, hoveredKey: String?) -> [BarSpan] {
    segments.map { seg in
        BarSpan(key: seg.key,
                fraction: CGFloat(Double(seg.bytes) / Double(total)),
                color: seg.color,
                dim: (hoveredKey == nil || hoveredKey == seg.key) ? 1 : 0.45)
    }
}

/// Hit region for one memory-bar segment. The bar itself is drawn by
/// `BarFillLayer` (one CALayer per segment, CoreAnimation-animated); this shape
/// exists only so each segment's `.onHover` responds to its own drawn rect
/// instead of to the whole bar. Both values are points, from `barSpanRects`.
private struct MemorySegmentShape: Shape {
    var x: CGFloat
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = max(0, width)
        guard w > 0, rect.height > 0 else { return Path() }
        return Path(CGRect(x: rect.minX + x, y: rect.minY, width: w, height: rect.height))
    }
}

struct MemoryCard: View {
    let model: DashboardModel

    var body: some View {
        if let mem = model.mem, mem.total > 0 {
            ChartOrTableCard(title: L.memoryTitle(tight(fmtBytesParts(mem.total))),
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredKey: String?

    var body: some View {
        if let mem = model.mem {
            let segments = memorySegments(mem)
            let total = max(mem.total, 1)
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    let spans = memoryBarSpans(segments, total: total, hoveredKey: hoveredKey)
                    let rects = barSpanRects(spans, layout: memoryBarLayout, width: geo.size.width)
                    // V2-FIX-MEM: the prototype (design_handoff_macdashboard/
                    // Overview Screen.dc.html:262-267) only CSS-transitions the
                    // first three segments; this app deliberately animates all
                    // six as one bar so the shared boundaries never desync.
                    // V2-RELAYOUT-COREANIM: all six are CALayers inside ONE
                    // NSView, animated by CoreAnimation on the same 0.8 s curve —
                    // no `.animation(_:value:)` anywhere in this subtree. The
                    // hover dim rides the layers' `opacity` on CA's own 0.12 s
                    // ease-out; the transparent overlay below only hit-tests.
                    BarFillLayer(spans: spans, layout: memoryBarLayout, animated: !reduceMotion)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                            ZStack(alignment: .topLeading) {
                                ForEach(Array(segments.enumerated()), id: \.element.key) { idx, seg in
                                    Color.clear
                                        .contentShape(MemorySegmentShape(x: rects[idx].x, width: rects[idx].width))
                                        .onHover { inside in
                                            if inside { hoveredKey = seg.key }
                                            else if hoveredKey == seg.key { hoveredKey = nil }
                                        }
                                }
                            }
                        }
                }
                .frame(height: 24)

                // FIX 7: row gap 8 / column gap 22 — see MemoryLegendFlowLayout
                // below (a MemoryCard-local layout; the shared `FlowLayout` in
                // SharedUI.swift is out of scope for this pass).
                MemoryLegendFlowLayout(columnSpacing: 22, rowSpacing: 8) {
                    ForEach(segments, id: \.key) { seg in
                        let parts = fmtBytesParts(seg.bytes)
                        let emphasis: LegendEmphasis = hoveredKey == nil ? .neutral : (hoveredKey == seg.key ? .active : .dimmed)
                        LegendItem(color: seg.legendColor, label: seg.label, value: parts.value, unit: parts.unit, emphasis: emphasis)
                            .hoverTip(memoryNotes[seg.label] ?? "")
                            .onHover { inside in
                                if inside { hoveredKey = seg.key }
                                else if hoveredKey == seg.key { hoveredKey = nil }
                            }
                    }
                }

                Text(footerNote(mem))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.muted)
            }
            .animation(.easeOut(duration: 0.12), value: hoveredKey)
        }
    }

    private func footerNote(_ mem: MemSnapshot) -> String {
        var bits: [String] = []
        if let swap = model.swap {
            bits.append(L.memorySwapNote(tight(fmtBytesParts(swap.used)), tight(fmtBytesParts(swap.total))))
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
                columnSpacing: 10,
                unitSplitColumns: [1]
            )
        }
    }
}
