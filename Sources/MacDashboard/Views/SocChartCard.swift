// Views/SocChartCard.swift
// SOC-DETAILS Stage 3 (3.1, 3.2; mockups/SoC.dc.html chart card, design 7.6): the 2-minute CPU and GPU chart in the
// History chart family. The Swift Charts body depends on the two histories only and is rebuilt once per tick (D8,
// gpu-per-frame): no hover state, no TimelineView, no animation. Hover is `SocChartHoverLayer` (Core Animation layers).

import SwiftUI
import Charts

/// Full-width card: title, legend (CPU / GPU), then the chart (160 plot + 26 axis strip).
@MainActor
struct SocChartCard: View {
    let model: AppModel
    /// Pins the hover on a sample for the visual fixture (`HistoryHoverLayer` has the same parameter).
    var initialHover: Int? = nil

    /// Reads `socChartSeries` here, so a tick evaluates it once; the page itself reads no live field.
    var body: some View {
        let series = model.socChartSeries
        DS3Card(title: L.socChartTitle, trailing: { SocChartLegend(gpuMissing: series.state == .gpuMissing) }) {
            SocLoadChart(series: series, initialHover: initialHover)
                .frame(height: 186)
        }
    }
}

/// Two items: a 14 × 3 swatch and the name (13 / 550). With no GPU value the GPU item is dimmed, reads "GPU —" and
/// carries the "Not available" tip.
struct SocChartLegend: View {
    let gpuMissing: Bool

    var body: some View {
        HStack(spacing: 16) {
            item(color: DS3.s1, name: L.commonCPU)
            if gpuMissing {
                item(color: DS3.s6, name: L.commonGPU + " —")
                    .opacity(0.45)
                    .hoverTip(L.gpuNotAvailable)
            } else {
                item(color: DS3.s6, name: L.commonGPU)
            }
        }
    }

    private func item(color: Color, name: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 14, height: 3)
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS3.inkSoft)
                .lineLimit(1)
        }
    }
}

/// The chart itself. Takes the already computed series; nothing in the `Chart` depends on the pointer.
struct SocLoadChart: View {
    let series: SocChartSeries
    var initialHover: Int? = nil

    /// Right gutter for the y labels, design 7.6.
    static let gutter: CGFloat = 40
    static let plotHeight: CGFloat = 160
    /// Height Swift Charts gives the x axis labels (11.5 pt text); the rest of the 26 pt strip is `stripSpacing`.
    static let labelHeight: CGFloat = 18
    static let stripSpacing: CGFloat = 8
    private static let gridValues: [Double] = [0, 25, 50, 75, 100]
    private static let labelledValues: Set<Double> = [0, 50, 100]

    private var drawsMarks: Bool { series.state != .collecting && series.state != .unavailable }
    private var gpuLines: [SocChartSegment] { drawsMarks ? series.gpu.filter { !$0.isDot } : [] }
    private var cpuLines: [SocChartSegment] { drawsMarks ? series.cpu.filter { !$0.isDot } : [] }
    private var dots: [(id: String, point: SocChartPoint, color: Color)] {
        guard drawsMarks else { return [] }
        return series.gpu.filter(\.isDot).map { ($0.id, $0.points[0], DS3.s6) }
            + series.cpu.filter(\.isDot).map { ($0.id, $0.points[0], DS3.s1) }
    }

    /// Total chart body height: 160 plot + 26 axis strip.
    static let bodyHeight: CGFloat = plotHeight + labelHeight + stripSpacing

    /// Fade between the wait / unavailable line and the drawn chart. Fires only when `drawsMarks` flips (the value
    /// below), never on a data tick (D8). Opacity only; Reduce Motion keeps it (`reduce-motion`).
    private var swapAnimation: Animation? { DS3Motion.isFrozen ? nil : .easeOut(duration: 0.25) }

    var body: some View {
        ZStack {
            if drawsMarks {
                chart.transition(.opacity)
            } else {
                message.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.bodyHeight)
        .animation(swapAnimation, value: drawsMarks)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soc-chart")
    }

    private var chart: some View {
        Chart {
            // Areas first, then lines, GPU under CPU in each (mockup order).
            ForEach(gpuLines) { seg in area(seg, DS3.s6) }
            ForEach(cpuLines) { seg in area(seg, DS3.s1) }
            ForEach(gpuLines) { seg in line(seg, DS3.s6) }
            ForEach(cpuLines) { seg in line(seg, DS3.s1) }
            ForEach(dots, id: \.id) { d in
                PointMark(x: .value("t", d.point.t), y: .value("v", d.point.v))
                    .symbol(Circle())
                    .symbolSize(CGSize(width: 5, height: 5))
                    .foregroundStyle(d.color)
            }
        }
        .chartXScale(domain: series.windowStart...series.windowEnd)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: Self.gridValues) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(DS3.line)
                AxisValueLabel(horizontalSpacing: 0) {
                    if let d = v.as(Double.self), Self.labelledValues.contains(d) {
                        Text(L.homePercent(String(Int(d))))
                            .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(DS3.muted)
                            .frame(width: Self.gutter, alignment: .trailing)
                    }
                }
            }
        }
        .chartXAxis {
            // −2 min leading, −1 min centred, now trailing, so none clips (design 7.6).
            AxisMarks(values: xTicks.map(\.date)) { v in
                if let d = v.as(Date.self), let t = xTicks.first(where: { $0.date == d }) {
                    AxisValueLabel(anchor: t.anchor) {
                        Text(t.label).font(.system(size: 11.5)).foregroundStyle(DS3.muted)
                    }
                }
            }
        }
        .chartOverlay { proxy in Hover(proxy: proxy, samples: series.hoverSamples, initialHover: initialHover) }
        // The x axis labels take 18 pt under the plot, so 178 gives a 160 pt plot; the 8 pt below make the 26 pt strip
        // (design 7.6: plot 160 + strip 26). A fixed split, not a measurement.
        .frame(height: Self.plotHeight + Self.labelHeight)
        .padding(.bottom, Self.stripSpacing)
    }

    // MARK: Marks

    @ChartContentBuilder
    private func area(_ seg: SocChartSegment, _ color: Color) -> some ChartContent {
        ForEach(seg.points, id: \.t) { p in
            // The fill ends at the domain floor (`chart-tooltip-facts`), which is 0 here.
            AreaMark(x: .value("t", p.t), yStart: .value("v", 0), yEnd: .value("v", p.v),
                     series: .value("segment", seg.id))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(
                    stops: [.init(color: color.opacity(0.42), location: 0), .init(color: color.opacity(0.02), location: 1)],
                    startPoint: .top, endPoint: .bottom))
        }
    }

    @ChartContentBuilder
    private func line(_ seg: SocChartSegment, _ color: Color) -> some ChartContent {
        ForEach(seg.points, id: \.t) { p in
            LineMark(x: .value("t", p.t), y: .value("v", p.v), series: .value("segment", seg.id))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: x axis

    private struct XTick {
        let date: Date
        let label: String
        let anchor: UnitPoint
    }

    private var xTicks: [XTick] {
        let labels = series.xLabels
        guard labels.count == 3 else { return [] }
        let mid = series.windowStart.addingTimeInterval(series.windowEnd.timeIntervalSince(series.windowStart) / 2)
        return [XTick(date: series.windowStart, label: labels[0], anchor: .topLeading),
                XTick(date: mid, label: labels[1], anchor: .top),
                XTick(date: series.windowEnd, label: labels[2], anchor: .topTrailing)]
    }

    // MARK: Empty states

    /// Centred in the whole chart body (gutter and axis strip included): the wait line while collecting, "Not
    /// available on this Mac" when neither series has a value. No grid, axes or marks (design 7.6).
    @ViewBuilder
    private var message: some View {
        switch series.state {
        case .collecting:
            HStack(spacing: 10) {
                DS3Spinner(role: .track, size: 14)
                Text(L.commonCollectingData).font(.system(size: 13.5)).foregroundStyle(DS3.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            Text(L.gpuNotAvailable).font(.system(size: 13.5)).foregroundStyle(DS3.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .partial, .full, .gpuMissing:
            EmptyView()
        }
    }

    // MARK: Hover

    /// Owns no state: converts the proxy into pixel positions once per layout and hands them to the Core Animation
    /// overlay, so neither the Chart's marks nor any SwiftUI view update on hover (HISTORY-HOVER-COST pattern).
    private struct Hover: View {
        let proxy: ChartProxy
        let samples: [SocChartSample]
        let initialHover: Int?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { geo in
                SocChartHoverLayer(frame: frame(geo), samples: samples, reduceMotion: reduceMotion, initialHover: initialHover)
            }
        }

        /// nil when the plot frame or any sample position is unknown; then nothing is shown and hover ends.
        private func frame(_ geo: GeometryProxy) -> SocChartHoverFrame? {
            guard let a = proxy.plotFrame else { return nil }
            let plot = geo[a]
            var xs: [CGFloat] = [], cpuYs: [CGFloat?] = [], gpuYs: [CGFloat?] = []
            xs.reserveCapacity(samples.count); cpuYs.reserveCapacity(samples.count); gpuYs.reserveCapacity(samples.count)
            for s in samples {
                guard let px = proxy.position(forX: s.t) else { return nil }
                xs.append(plot.minX + px)
                cpuYs.append(s.cpu.flatMap { proxy.position(forY: $0) }.map { plot.minY + $0 })
                gpuYs.append(s.gpu.flatMap { proxy.position(forY: $0) }.map { plot.minY + $0 })
            }
            return SocChartHoverFrame(plot: plot, xs: xs, cpuYs: cpuYs, gpuYs: gpuYs)
        }
    }
}
