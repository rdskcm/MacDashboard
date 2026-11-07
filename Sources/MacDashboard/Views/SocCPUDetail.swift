// Views/SocCPUDetail.swift
// SOC-DETAILS 2.1 (design 7.4): the CPU card's detail area, two panels of 105 pt in a fixed 218 pt stack: the
// user / system / idle split (a stacked bar and three values) and the load-average tile. Both read pure view models
// (`SocSplit`, `SocLoadAverage`); the bar is a `BarFillLayer`, so a tick is one Core Animation commit.

import SwiftUI

/// Panel surface shared by both tiles: row fill, 0.5 pt hairline, radius 20 (the `SectionTile` look).
private extension View {
    func socPanel() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
            .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), top: DS3.rimLo, ring: DS3.line)
    }
}

// MARK: - Split

struct SocSplitPanel: View, Equatable {
    let split: SocSplit

    /// Explicit: the panel holds an `@Environment` value, so the synthesized comparison is not available (Stage 5a).
    nonisolated static func == (a: Self, b: Self) -> Bool { a.split == b.split }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Part: Identifiable {
        let id: String
        let label: String
        let value: String
        let fraction: Double
        let color: Color
    }

    private var parts: [Part] {
        [Part(id: "user", label: L.cpuUser, value: split.user, fraction: split.userFraction, color: DS3.s1),
         Part(id: "system", label: L.cpuSystem, value: split.system, fraction: split.systemFraction, color: DS3.s2),
         Part(id: "idle", label: L.cpuIdle, value: split.idle, fraction: split.idleFraction, color: DS3.sidle)]
    }

    var body: some View {
        let parts = parts
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(DS3.track)
                .frame(height: 8)
                .overlay {
                    BarFillLayer(spans: parts.map { BarSpan(key: $0.id, fraction: CGFloat($0.fraction), color: $0.color) },
                                 layout: .segments(gap: 2, minWidth: 0, cornerRadius: 4),
                                 animated: !reduceMotion)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            Spacer(minLength: 0)
            EqualColumnsLayout(columns: 3, spacing: 8) {
                ForEach(parts) { part in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(part.color)
                                .frame(width: 8, height: 8)
                            Text(part.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DS3.inkSoft)
                                .lineLimit(1)
                                // "Пользователь" is within a point of the 108 pt column at the 900 pt minimum.
                                .minimumScaleFactor(0.85)
                        }
                        Text(part.value)
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(part.value == "—" ? DS3.muted : DS3.ink)
                            .lineLimit(1)
                    }
                }
            }
        }
        .socPanel()
    }
}

// MARK: - Load average

struct SocLoadAverageTile: View, Equatable {
    let load: SocLoadAverage

    nonisolated static func == (a: Self, b: Self) -> Bool { a.load == b.load }

    var body: some View {
        let columns: [(value: String, caption: String)] = [(load.one, L.socLoadMin(1)), (load.five, L.socLoadMin(5)),
                                                           (load.fifteen, L.socLoadMin(15))]
        VStack(alignment: .leading, spacing: 8) {
            Text(L.socLoadAverage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS3.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 0)
            EqualColumnsLayout(columns: 3, spacing: 8) {
                ForEach(columns.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(columns[i].value)
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(load.available ? DS3.ink : DS3.muted)
                            .lineLimit(1)
                        Text(columns[i].caption)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DS3.muted)
                            .lineLimit(1)
                    }
                }
            }
        }
        .socPanel()
        .hoverTip(load.available ? L.socLoadAverageHelp : L.socLoadAverageUnavailable)
    }
}
