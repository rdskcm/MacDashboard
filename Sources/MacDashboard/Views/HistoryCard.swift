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
    // Same semantics as HistorySeries.last30Range's own private dayFormatter —
    // deliberately duplicated (not shared) since that one is private there.
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
    @State private var histInfo = false

    // Which series the chart above the table currently plots.
    @State private var metric: HistoryMetric = .disk

    var body: some View {
        if entries.count >= 2 {
            ChartOrTableCard(
                title: L.historyTitle,
                caption: L.historyCaption(entries.count),
                headerAccessory: { metricControl },
                chart: { chart },
                table: { table }
            )
        }
    }

    // The metric picker (`DSSlidingSegmented`, stateful, spring-animated thumb)
    // lives in `ChartOrTableCard`'s header slot — OUTSIDE both the chart/table
    // toggle branch and the `points.count < 2` branch inside `chart` below. A
    // control bound to `$metric` that gets a fresh identity whenever the
    // surrounding view also branches on data loses its thumb-slide animation
    // (fresh instance mounts pre-selected instead of sliding; see FoldersCard's
    // segmentedControl note in StorageCards.swift for the reference precedent).
    private var metricControl: some View {
        DSSlidingSegmented(options: HistoryMetric.allCases, selection: $metric) { m in
            label(for: m)
        }
        .accessibilityLabel(L.historyMetricA11y)
    }

    private var metricYLabel: String {
        switch metric {
        case .disk: return L.historyMetricYLabelDisk
        case .battery: return L.historyMetricYLabelBattery
        case .cycles: return L.historyMetricYLabelCycles
        case .swap: return L.historyMetricYLabelSwap
        }
    }

    /// `HistorySeries.series` points for `metric`, parsed to `Date` and
    /// filtered to the 30-day window `HistorySeries.last30Range` reports (the
    /// 60-day-capped history can hold points OUTSIDE that window — those must
    /// not render compressed into the visible axis). Falls back to all parsed
    /// points, unfiltered, if `last30Range` can't compute one (defensive only:
    /// `body` already guards `entries.count >= 2`, so entries is never empty
    /// here).
    private func chartPoints(for metric: HistoryMetric) -> [HistoryChartPoint] {
        let parsed: [HistoryChartPoint] = HistorySeries.series(entries, metric: metric).compactMap { p in
            guard let date = Self.dateFormatter.date(from: p.date) else { return nil }
            return HistoryChartPoint(id: p.date, date: date, value: p.value)
        }
        guard let range = HistorySeries.last30Range(entries) else { return parsed }
        return parsed.filter { range.contains($0.date) }
    }

    // The metric picker moved to `ChartOrTableCard`'s header slot (see
    // `metricControl` / `body` above); only the plot content — empty-state
    // text vs. the real chart — varies with `metric` here.
    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            let points = chartPoints(for: metric)
            if points.count < 2 {
                Text(L.historyMetricInsufficientData)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                HistoryTrendChart(points: points, metric: metric, yLabel: metricYLabel)
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
                    histInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(histInfo ? L.historyInfoHideLabel : L.historyInfoShowLabel)
            }
            if histInfo {
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

    /// Column explanations (Russian, click-to-toggle via `histInfo`).
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

// MARK: - Chart point

/// One plotted (date, value) sample. Charts needs a `Date` (not the raw
/// "yyyy-MM-dd" string `HistorySeries.series` returns), and `id` gives the
/// hover-tracking logic below (and its `.animation(value:)`) a stable,
/// cheaply-comparable key.
private struct HistoryChartPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let value: Double
}

// MARK: - Trend chart (line + area + hover tracking)

/// Line+area trend chart with hover/tap point tracking. A private subview
/// (not inlined into `HistoryCard.chart`) so its hover-tracking `@State`
/// (`tracked`, `tooltipSize`) only invalidates this subtree on mouse move,
/// never the metric picker or the rest of the card.
///
/// X is plotted by ORDINAL INDEX into `points`, not by calendar `Date` (spec
/// correction: prototype's `xAt(i) = i/(n-1)*300`, Overview Screen.dc.html:
/// 1489). `points` is still date-filtered to the last-30-day window upstream
/// (`HistoryCard.chartPoints`/`HistorySeries.last30Range`) — that selection
/// step is correct and stays — but the plotted x-axis itself is an index over
/// exactly those (already-filtered) points, so it always fills the full plot
/// width regardless of how many of the 30 days actually have data. A `Date`-
/// domain x-scale left blank space before the line when fewer than 30 days
/// existed.
private struct HistoryTrendChart: View {
    let points: [HistoryChartPoint]
    let metric: HistoryMetric
    let yLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tracked: HistoryChartPoint?
    @State private var tooltipSize: CGSize = .zero

    private var trackedIndex: Int? {
        guard let tracked else { return nil }
        return points.firstIndex(where: { $0.id == tracked.id })
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: DS.accent.opacity(0.42), location: 0),
                .init(color: DS.accent.opacity(0.02), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var trackingAnimation: Animation {
        reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.fillHover
    }

    /// Y-domain padded ~9.52% of the value span above/below the actual
    /// min/max (prototype: `lo/hi/span` then bars mapped into an effective
    /// [8,92]-of-100 band — algebraically equivalent to padding each side by
    /// `span * 2/21`; see Overview Screen.dc.html:1459-1494). A zero-based or
    /// unpadded auto domain visually flattens real variation near the top of
    /// the plot for value ranges that sit well above zero (e.g. 96-140 GB).
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let span = max(hi - lo, 1)
        let pad = span * (2.0 / 21.0)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            plot
                .frame(height: 120)
                .chartYScale(domain: yDomain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover(coordinateSpace: .local) { phase in
                                    switch phase {
                                    case .active(let location):
                                        updateTracked(at: location, proxy: proxy, geo: geo)
                                    case .ended:
                                        tracked = nil
                                    }
                                }
                            if let tracked, let trackedIndex {
                                tooltip(for: tracked, index: trackedIndex, proxy: proxy, geo: geo)
                            }
                        }
                    }
                }
                .animation(trackingAnimation, value: tracked?.id)
            footer
        }
    }

    /// Plain unit label (leading) + plotted date range (trailing) — the
    /// prototype's chart has NO gridlines/tick labels/axis titles at all
    /// (Overview Screen.dc.html:705-720); this footer row is the only
    /// axis-adjacent text (OS:722-725).
    private var footer: some View {
        HStack {
            Text(yLabel)
                .font(.system(size: 11))
                .foregroundStyle(DS.muted)
            Spacer()
            Text("\(points.first.map { fmtDisplayDay($0.date) } ?? "") → \(points.last.map { fmtDisplayDay($0.date) } ?? "")")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(DS.muted)
        }
    }

    private var plot: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                // Terminate the area at the domain floor, not 0 — a series whose domain excludes 0 would otherwise spill past the plot rect.
                AreaMark(x: .value("i", Double(index)), yStart: .value(yLabel, yDomain.lowerBound), yEnd: .value(yLabel, point.value))
                    .foregroundStyle(areaGradient)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("i", Double(index)), y: .value(yLabel, point.value))
                    .foregroundStyle(DS.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                if let tracked, tracked.id == point.id {
                    RuleMark(x: .value("i", Double(index)))
                        .foregroundStyle(DS.muted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("i", Double(index)), y: .value(yLabel, point.value))
                        .symbol {
                            ZStack {
                                Circle()
                                    .stroke(DS.accent.opacity(0.24), lineWidth: 3)
                                    .frame(width: 13.5, height: 13.5)
                                Circle()
                                    .fill(DS.accent)
                                    .frame(width: 9, height: 9)
                            }
                        }
                }
            }
        }
    }

    /// Nearest daily point to the hover/tap location, tracked anywhere over
    /// the plot area (not just directly over the line/a mark). Mirrors the
    /// prototype's `histMove` exactly now that x is index-based: cursor
    /// fraction across the plot width → nearest ordinal index, clamped to
    /// `[0, n-1]` (Overview Screen.dc.html:1509-1513) — no `Date`/timezone
    /// math needed.
    private func updateTracked(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame, !points.isEmpty else {
            tracked = nil
            return
        }
        let plotFrame = geo[plotFrameAnchor]
        guard plotFrame.width > 0 else {
            tracked = nil
            return
        }
        let fraction = (location.x - plotFrame.origin.x) / plotFrame.width
        let rawIndex = Int((fraction * Double(points.count - 1)).rounded())
        let index = max(0, min(points.count - 1, rawIndex))
        tracked = points[index]
    }

    /// Tooltip placement (authoritative rule, no fixed-pixel clamp):
    /// vertically BELOW the point when it falls in the top 38% of the plot's
    /// height (no room to show it above without going off the card), else
    /// ABOVE (prototype: `yAt(hs[hv]) > 38 ? bottom: ... : top: ...`, where
    /// `yAt` is fraction-from-top and CSS `bottom:` positioning renders the
    /// tooltip visually ABOVE the point — OS:1504); horizontally pinned to
    /// the plot's left/right edge near either end of the plotted range
    /// (index ≤ 3 / ≥ n−4), else centred on the point's x.
    @ViewBuilder
    private func tooltip(for point: HistoryChartPoint, index: Int, proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotFrameAnchor = proxy.plotFrame,
           let px = proxy.position(forX: Double(index)), let py = proxy.position(forY: point.value) {
            let plotFrame = geo[plotFrameAnchor]
            let anchor = CGPoint(x: plotFrame.origin.x + px, y: plotFrame.origin.y + py)
            let n = points.count
            let gap: CGFloat = 8
            let isTopZone = (anchor.y - plotFrame.minY) <= plotFrame.height * 0.38

            let x: CGFloat = {
                if index <= 3 { return plotFrame.minX + tooltipSize.width / 2 }
                if index >= n - 4 { return plotFrame.maxX - tooltipSize.width / 2 }
                return anchor.x
            }()
            let y: CGFloat = isTopZone
                ? anchor.y + gap + tooltipSize.height / 2
                : anchor.y - gap - tooltipSize.height / 2

            tooltipContent(for: point)
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
                    tooltipSize = newSize
                }
                .position(x: x, y: y)
        }
    }

    private func tooltipContent(for point: HistoryChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.id)
                .font(.system(size: 11))
                .foregroundStyle(DS.muted)
            let parts = valueParts(for: point)
            if let unit = parts.unit {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(parts.value)
                    Text(unit)
                        .padding(.leading, 1.5)
                }
                .font(.system(size: 12.5, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(DS.ink)
            } else {
                Text(parts.value)
                    .font(.system(size: 12.5, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(DS.ink)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(DS.ground2))
    }

    /// Value + unit, reusing the same formatting the table already uses for
    /// disk/battery/cycles, plus the existing byte unit string (no new
    /// localization keys needed). V2-FIX-UNITS follow-up: this monospaced
    /// tooltip renders a literal space as a full glyph advance, so disk/swap
    /// split value and unit into two `Text` views with a tight
    /// `.padding(.leading, 1.5)` gap, matching TMRow.valueParts and
    /// LegendItem elsewhere in this block. Battery/cycles don't have the
    /// gap defect (`%` touches the number directly; cycles is a count + word
    /// label, not a byte/capacity unit) so they stay single strings.
    private func valueParts(for point: HistoryChartPoint) -> (value: String, unit: String?) {
        switch metric {
        case .disk:
            return (String(Int(point.value.rounded())), L.byteUnitGB)
        case .battery:
            return ("\(Int(point.value.rounded()))%", nil)
        case .cycles:
            return ("\(Int(point.value.rounded())) \(L.historyMetricYLabelCycles)", nil)
        case .swap:
            return (String(format: "%.1f", point.value), L.byteUnitGB)
        }
    }
}
