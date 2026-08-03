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
    let color: Color
    let bytes: Int64
}

private func memorySegments(_ mem: MemSnapshot) -> [MemSegment] {
    [
        MemSegment(key: "active", label: L.memoryLegendActive, color: SeriesPalette.s1, bytes: mem.active),
        MemSegment(key: "wired", label: L.memoryLegendWired, color: SeriesPalette.s2, bytes: mem.wired),
        MemSegment(key: "other", label: L.memoryLegendOther, color: SeriesPalette.s3, bytes: mem.otherBytes),
        MemSegment(key: "inactive", label: L.memoryLegendInactive, color: SeriesPalette.s4, bytes: mem.inactive),
        MemSegment(key: "speculative", label: L.memoryLegendSpeculative, color: SeriesPalette.s5, bytes: mem.speculative),
        MemSegment(key: "free", label: L.memoryLegendFree, color: SeriesPalette.free, bytes: mem.free)
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
                        }
                    }
                }
                .frame(height: 24)

                FlowLayout(spacing: 14) {
                    ForEach(segments, id: \.key) { seg in
                        MemoryLegendItem(color: seg.color, label: seg.label, value: fmtBytes(seg.bytes))
                            .hoverTip(memoryNotes[seg.label] ?? "")
                    }
                }

                Text(footerNote(mem))
                    .font(.system(size: 12.5))
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

/// Legend swatch + series name + mono value (memory stack chart only). A local
/// replacement for the shared `LegendItem` (SharedUI.swift): the shared component
/// renders its value in the default (non-mono) font and this card needs tabular
/// mono numbers, but `SharedUI.swift` is out of scope for this block beyond the
/// chart/table toggle — see block spec.
private struct MemoryLegendItem: View {
    let color: Color
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.inkSoft)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DS.inkSoft)
        }
        .contentShape(Rectangle())
    }
}

@MainActor
private struct MemoryTable: View {
    let model: DashboardModel

    // Plain (non-ViewBuilder) computed property: imperative row-building lives
    // here, not inside `body`, so appending to an array isn't misparsed as a
    // View-producing branch by the result builder.
    private var rows: [[String]]? {
        guard let mem = model.mem else { return nil }
        let segments = memorySegments(mem)
        let total = max(mem.total, 1)
        var r: [[String]] = segments.map { seg in
            [seg.label, fmtBytes(seg.bytes), fmtNum(Double(seg.bytes) / Double(total) * 100, decimals: 1) + "%"]
        }
        if mem.purgeable > 0 {
            r.append([L.memoryLegendPurgeable, fmtBytes(mem.purgeable),
                      fmtNum(Double(mem.purgeable) / Double(total) * 100, decimals: 1) + "%"])
        }
        if mem.fileBacked > 0 {
            r.append([L.memoryLegendFileCache, fmtBytes(mem.fileBacked),
                      fmtNum(Double(mem.fileBacked) / Double(total) * 100, decimals: 1) + "%"])
        }
        return r
    }

    var body: some View {
        if let rows {
            SimpleTable(
                headers: [L.memoryColCategory, L.memoryColVolume, L.storageColShare],
                rows: rows,
                numericColumns: [1, 2],
                cellTooltip: { r, c in
                    guard c == 0, r < rows.count else { return nil }
                    return memoryNotes[rows[r][0]]
                }
            )
        }
    }
}
