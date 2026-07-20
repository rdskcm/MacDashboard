// Views/HistoryCard.swift
// История card (chart/table): mac_check_state.json time series.

import SwiftUI
import Charts

// MARK: - История

@MainActor
struct HistoryCard: View {
    let model: DashboardModel

    // Local timezone deliberately (not UTC): Charts renders x-axis labels using
    // the current calendar, so a UTC-midnight Date would shift a day backward
    // on the axis for anyone west of UTC. Parsing in the local zone keeps the
    // "YYYY-MM-DD" string and its displayed axis label the same calendar day.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var entries: [MacHistoryEntry] { model.history.mac_history }

    // Clickable (not hover) explanation panel toggle — ChartOrTableCard's own
    // trailing slot only supports a hover tip (`infoHelp`), so the button lives
    // in the table content instead, above the SimpleTable.
    @State private var showInfo = false

    // Which series the chart above the table currently plots.
    @State private var metric: HistoryMetric = .disk

    var body: some View {
        if entries.count >= 2 {
            ChartOrTableCard(title: L.historyTitle, caption: L.historyCaption(entries.count)) {
                chart
            } table: {
                table
            }
        }
    }

    private var metricYLabel: String {
        switch metric {
        case .disk: return L.historyMetricYLabelDisk
        case .battery: return L.historyMetricYLabelBattery
        case .cycles: return L.historyMetricYLabelCycles
        case .swap: return L.historyMetricYLabelSwap
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $metric) {
                ForEach(HistoryMetric.allCases, id: \.self) { m in
                    Text(label(for: m)).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let points = HistorySeries.series(entries, metric: metric)
            if points.count < 2 {
                Text(L.historyMetricInsufficientData)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 220)
            } else {
                Chart(points, id: \.date) { point in
                    if let date = Self.dateFormatter.date(from: point.date) {
                        LineMark(x: .value(L.historyColDate, date), y: .value(metricYLabel, point.value))
                            .foregroundStyle(SeriesPalette.s1)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value(L.historyColDate, date), y: .value(metricYLabel, point.value))
                            .foregroundStyle(SeriesPalette.s1)
                            .symbolSize(28)
                    }
                }
                .chartXAxisLabel(L.historyColDate)
                .chartYAxisLabel(metricYLabel)
                .frame(height: 220)
            }
        }
    }

    private func label(for m: HistoryMetric) -> String {
        switch m {
        case .disk: return L.historyMetricPickerDisk
        case .battery: return L.historyMetricPickerBattery
        case .cycles: return L.historyMetricPickerCycles
        case .swap: return L.historyMetricPickerSwap
        }
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    showInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(showInfo ? L.historyInfoHideLabel : L.historyInfoShowLabel)
            }
            if showInfo {
                infoPanel
            }
            SimpleTable(
                headers: [L.historyColDate, L.historyColDiskUsed, L.historyColFree, L.kpiBatteryLabel, L.historyColCycles, "Swap", "macOS"],
                rows: entries.map { e in
                    [
                        e.date,
                        e.disk_used_gb.map { L.historyGbValue($0) } ?? "—",
                        e.disk_free_gb.map { L.historyGbValue($0) } ?? "—",
                        e.battery_pct.map { "\($0)%" } ?? "—",
                        e.cycles.map { "\($0)" } ?? "—",
                        HistorySeries.formattedSwap(e.swap),
                        e.macos ?? "—"
                    ]
                },
                numericColumns: [1, 2, 3, 4, 5]
            )
        }
    }

    /// Column explanations (Russian, click-to-toggle via `showInfo`).
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L.historyInfoDate)
            Text(L.historyInfoDiskFree)
            Text(L.historyInfoBattery)
            Text(L.historyInfoCycles)
            Text(L.historyInfoSwap)
            Text(L.historyInfoMacos)
            Text(L.historyInfoSource)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
