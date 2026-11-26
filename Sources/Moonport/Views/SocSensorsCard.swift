// Views/SocSensorsCard.swift
// TEMP-SENSORS-DETAIL: the "Sensors" card on the SoC page. Current temperatures only, from
// `SocLiveSampler.sensors`, which reads only while the SoC page is shown (no-unseen-work). Shell = DS3Card; lists =
// SocGPUList's container (padding 6, radius 22, DS3.row, inset rims); rows = SocGPURowView's layout without the gauge
// (D13). One fixed container height in every state, so the cards below never move (D12). Neutral ink only (D14).

import SwiftUI

/// Internal: the visual fixture renders it.
@MainActor
struct SocSensorsCard: View {
    let model: AppModel

    /// 6 + 4 x 38 + 3 x 4 + 6: the tallest list (four rows).
    static let containerHeight: CGFloat = 176

    var body: some View {
        let state = model.socLive.sensors
        DS3Card(title: L.socSensorsTitle, caption: L.socSensorsCaption) {
            switch state {
            case .notYet:
                container {
                    SectionWait(text: L.commonCollectingData)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .unavailable:
                container { message(L.socSensorsUnavailable) }
            case .rows(let readings):
                let lists = SocSensorsModel.lists(readings)
                EqualColumnsLayout(columns: max(1, lists.count), spacing: 16, fillsHeight: true) {
                    ForEach(lists.indices, id: \.self) { i in
                        container {
                            VStack(spacing: 4) {
                                ForEach(lists[i], id: \.name) { SocSensorRowView(row: $0) }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    private func container<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: Self.containerHeight, maxHeight: Self.containerHeight, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
            .ds3InsetRims(RoundedRectangle(cornerRadius: 22, style: .continuous), ring: DS3.line)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(DS3.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One row: name (14, tail truncation, full name on hover) and value (SF Mono 13 / 600, at least 64 pt, trailing).
struct SocSensorRowView: View {
    let row: SocSensorsModel.Row

    var body: some View {
        HStack(spacing: 10) {
            Text(row.name)
                .font(.system(size: 14))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(row.name)
            Spacer(minLength: 8)
            Text(row.valueText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(row.noValueHelp == nil ? DS3.ink : DS3.muted)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing)
                .layoutPriority(1)
                .help(row.noValueHelp ?? "")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.valueText)")
        .accessibilityAddTraits(.isStaticText)
    }
}
