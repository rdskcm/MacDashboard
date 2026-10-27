// Views/IPhoneBatteryViews.swift
// Battery panel and battery history for the iPhone device page (layout only, no animation).

import Charts
import SwiftUI

struct IPhoneBatteryCard: View {
    let record: IPhoneDeviceRecord?
    let snapshot: IPhoneSnapshot?
    @AppStorage("iphoneCapacityUnit") private var unit = "mAh"

    var body: some View {
        DS3Card(title: L.iphoneBatteryTitle, caption: caption, spacing: 18, trailing: {
            if let b = snapshot?.battery, b.maxCapacityMAh != nil, b.designCapacityMAh != nil { unitPicker }
        }) {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if let b = snapshot?.battery {
            IPhoneRatioRow(spacing: 12) {
                hero(value: health(b), fraction: (healthNumber(b) ?? 0) / 100, note: L.iphoneHealthNote)
                liveTiles(b)
            }
        } else if snapshot != nil {
            IPhoneMessagePanel(text: snapshot?.batteryRead == false ? L.iphoneBatteryAutoReadOff : L.iphoneBatteryNoData)
        } else if let p = lastPoint {
            VStack(alignment: .leading, spacing: 12) {
                hero(value: p.healthPercent.map { "\($0) %" }, fraction: Double(p.healthPercent ?? 0) / 100,
                     note: L.iphoneHealthHistoryNote(cycles: p.cycles))
                liveReadingsBox
            }
        } else {
            IPhoneMessagePanel(text: L.iphoneBatteryConnectToRead)
        }
    }

    private var lastPoint: BatteryPoint? {
        record?.battery.filter { $0.healthPercent != nil || $0.cycles != nil }.max { $0.day < $1.day }
    }

    private var caption: String? {
        if snapshot != nil { return L.iphoneBatteryMeasuredNow }
        guard let p = lastPoint, let d = IPhoneData.historyDate(p.day) else { return nil }
        return L.iphoneBatteryFromHistory(fmtDisplayDay(d))
    }

    private func state(_ b: BatteryDetail) -> String {
        b.isCharging ? L.iphoneChargeCharging : (b.externalConnected ? L.iphoneChargeExternal : L.iphoneChargeBattery)
    }

    /// mAh | Wh switch, in the header slot outside any branch on the unit or the snapshot.
    private var unitPicker: some View {
        Picker(L.iphoneCapacityUnitA11y, selection: $unit) {
            Text(L.iphoneUnitMAh).tag("mAh")
            Text(L.iphoneUnitWh).tag("Wh")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// One decimal, half-up, when both capacities are known; the integer value otherwise.
    private func health(_ b: BatteryDetail) -> String? {
        if let max = b.maxCapacityMAh, let design = b.designCapacityMAh,
           let h = IPhoneData.preciseHealth(maxMAh: max, designMAh: design) {
            return oneDecimal(h) + " %"
        }
        return b.healthPercent.map { "\($0) %" }
    }

    private func healthNumber(_ b: BatteryDetail) -> Double? {
        if let max = b.maxCapacityMAh, let design = b.designCapacityMAh,
           let h = IPhoneData.preciseHealth(maxMAh: max, designMAh: design) {
            return h
        }
        return b.healthPercent.map(Double.init)
    }

    private func oneDecimal(_ v: Double) -> String {
        iphoneOneDecimal(v)
    }

    private func capacity(_ b: BatteryDetail) -> String? {
        guard let max = b.maxCapacityMAh, let design = b.designCapacityMAh else { return nil }
        if unit == "Wh" {
            return "≈ \(oneDecimal(IPhoneData.wattHours(mAh: max))) / \(oneDecimal(IPhoneData.wattHours(mAh: design))) \(L.iphoneUnitWh)"
        }
        return "\(max) / \(design) \(L.iphoneUnitMAh)"
    }

    private func hero(value: String?, fraction: Double, note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.iphoneBatHealth)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS3.accentInk)
            Spacer(minLength: 0)
            Text(value ?? "—")
                .font(.system(size: 40, weight: .heavy))
                .tracking(-1.2)
                .monospacedDigit()
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
            DS3Bar(
                fraction: fraction,
                height: 8,
                fill: AnyShapeStyle(LinearGradient(
                    stops: [.init(color: DS3.barTop, location: 0), .init(color: DS3.accent, location: 0.7)],
                    startPoint: .top, endPoint: .bottom)),
                recessed: true)
            Text(note)
                .font(.system(size: 12.5))
                .foregroundStyle(DS3.muted)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ds3TintPanel(DS3.accent, from: 0.16, to: 0.06, ring: 0.28, cornerRadius: 24, top: DS3.rimHi)
    }

    private func liveTiles(_ b: BatteryDetail) -> some View {
        let productType = snapshot?.productType ?? record?.productType
        let charge = IPhoneData.chargeTone(percent: b.percent, onExternalPower: b.externalConnected)
        let cycles = IPhoneData.cyclesTone(b.cycleCount, productType: productType)
        let temp = IPhoneData.temperatureTone(b.temperatureC)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            box(L.iphoneBatCharge, b.percent.map { "\($0) %" }, tone: charge, bar: b.percent.map { Double($0) / 100 })
            box(L.iphoneBatState, state(b), accent: b.isCharging || b.externalConnected)
            box(L.iphoneBatCycles, b.cycleCount.map { "\($0)" }, tone: cycles,
                note: cycles == .hot ? L.iphoneCyclesHigh : cycles == .amber ? L.iphoneCyclesAging : nil)
            box(L.iphoneBatTemperature, b.temperatureC.map { L.batteryCelsius(fmtNum($0, decimals: 1)) }, tone: temp,
                dot: b.temperatureC != nil,
                note: b.temperatureC == nil ? nil : temp == .hot ? L.iphoneTempHot : temp == .amber ? L.iphoneTempWarm : L.iphoneTempNormal)
            box(L.iphoneBatVoltage, b.voltageMV.map { L.batteryVolts(fmtNum(Double($0) / 1000, decimals: 2)) })
            box(L.iphoneBatCapacity, capacity(b), help: unit == "Wh" ? L.iphoneWhSourceHelp : nil)
        }
    }

    @ViewBuilder
    private func box(_ label: String, _ value: String?, tone: HomeTone? = nil, accent: Bool = false, dot: Bool = false,
                     note: String? = nil, bar: Double? = nil, help: String? = nil) -> some View {
        let dotColor: Color? = tone?.base ?? ((accent || dot) ? DS3.accent : nil)
        let valueInk: Color = tone?.ink ?? (accent ? DS3.accentInk : DS3.ink)
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                        .background(Circle().fill(dotColor.opacity(0.22)).frame(width: 13, height: 13))
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS3.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value ?? "—")
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.17)
                    .monospacedDigit()
                    .foregroundStyle(valueInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let note {
                    Text(note)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(tone?.ink ?? DS3.muted)
                        .lineLimit(1)
                        .layoutPriority(1)   // the value scales down first (fixed-size-in-header-row: no .fixedSize())
                }
            }
            if let bar {
                DS3Bar(fraction: bar, height: 5, fill: AnyShapeStyle(tone?.base ?? DS3.accent))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .ds3RowPanel(cornerRadius: 20)
        if let help { content.help(help) } else { content }
    }

    private var liveReadingsBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.iphoneLiveReadings)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS3.inkSoft)
            Text(L.iphoneLiveReadingsConnect)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS3.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ds3RowPanel(cornerRadius: 20)
    }
}

struct IPhoneBatteryHistoryCard: View {
    enum HistoryView: Hashable { case chart, table }

    let points: [BatteryPoint]
    @State private var view: HistoryView
    private let initialHover: Int?

    init(points: [BatteryPoint], initialView: HistoryView = .chart, initialHover: Int? = nil) {
        self.points = points
        self.initialHover = initialHover
        _view = State(initialValue: initialView)
    }

    private var sorted: [BatteryPoint] { points.sorted { $0.day < $1.day } }

    var body: some View {
        DS3Card(title: L.iphoneHistoryTitle,
                caption: points.isEmpty ? nil : L.iphoneHistoryCaption(points.count),
                trailing: {
                    if !points.isEmpty {
                        Picker(L.iphoneHistoryViewA11y, selection: $view) {
                            Text(L.iphoneHistoryChart).tag(HistoryView.chart)
                            Text(L.iphoneHistoryTable).tag(HistoryView.table)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }) {
            if points.isEmpty {
                IPhoneMessagePanel(text: L.iphoneHistoryEmpty)
            } else if view == .chart {
                IPhoneHealthChart(points: sorted, initialHover: initialHover)
            } else {
                table
            }
        }
    }

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(sorted.reversed().enumerated()), id: \.offset) { _, p in
                        IPhoneHistoryTableRow(point: p)
                    }
                } header: {
                    tableHeader
                }
            }
        }
        .frame(maxHeight: 320)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS3.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var tableHeader: some View {
        IPhoneFractionRow {
            Text(L.iphoneHistoryColDate).frame(maxWidth: .infinity, alignment: .leading)
            Text(L.iphoneHistoryColHealth).frame(maxWidth: .infinity, alignment: .trailing)
            Text(L.iphoneHistoryColCycles).frame(maxWidth: .infinity, alignment: .trailing)
            Text(L.iphoneHistoryColSource).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(DS3.muted)
        .lineLimit(1)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(DS3.overlay)
        .overlay(alignment: .bottom) { Rectangle().fill(DS3.line).frame(height: 1) }
    }
}

private struct IPhoneHistoryTableRow: View {
    let point: BatteryPoint
    @State private var hover = false

    var body: some View {
        let live = point.source == "live"
        IPhoneFractionRow {
            Text(IPhoneData.historyDate(point.day).map(fmtDisplayDay) ?? point.day)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(point.healthPercent.map { "\($0) %" } ?? "—")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(point.cycles.map { "\($0)" } ?? "—")
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(live ? L.iphoneHistorySourceLive : L.iphoneHistorySourceImport)
                .foregroundStyle(live ? DS3.accentInk : DS3.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14))
        .monospacedDigit()
        .foregroundStyle(DS3.ink)
        .lineLimit(1)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(hover ? DS3.row : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(DS3.line).frame(height: 1) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Health chart: monotone line + area down to the y-domain floor, trailing percent labels, month or week
/// labels below, hover rule/point and a fixed-size tooltip snapped to the nearest day.
private struct IPhoneHealthChart: View {
    private struct P {
        let day: String
        let date: Date
        let health: Int
        let cycles: Int?
        let live: Bool
    }

    private struct Series {
        let pts: [P]
        let dates: [Date]
        let scale: IPhoneData.HealthChartScale
        let xDomain: ClosedRange<Date>
        let ticks: [IPhoneData.ChartTickMark]
    }

    // Parsed once per data change (IPHONE-SCROLL-LAG C2): never in body.
    private let series: Series?
    private let initialHover: Int?

    init(points: [BatteryPoint], initialHover: Int?) {
        self.initialHover = initialHover
        let pts: [P] = points.compactMap { p in
            guard let h = p.healthPercent, let d = IPhoneData.historyDate(p.day) else { return nil }
            return P(day: p.day, date: d, health: h, cycles: p.cycles, live: p.source == "live")
        }
        guard let first = pts.first, let last = pts.last else {
            series = nil
            return
        }
        let t0 = first.date
        let t1 = last.date
        series = Series(
            pts: pts,
            dates: pts.map(\.date),
            scale: IPhoneData.healthChartScale(pts.map(\.health))!,
            xDomain: pts.count == 1 ? t0.addingTimeInterval(-86_400)...t0.addingTimeInterval(86_400) : t0...t1,
            ticks: IPhoneData.chartTicks(from: t0, to: t1, calendar: .current))
    }

    var body: some View {
        if let series {
            plot(series)
        } else {
            IPhoneMessagePanel(text: L.iphoneHistoryEmpty)
        }
    }

    private func label(_ tick: IPhoneData.ChartTick) -> String {
        switch tick {
        case .month(let m): return L.iphoneChartMonth(m)
        case .day(let d, let m): return L.iphoneChartWeekLabel(day: d, month: m)
        }
    }

    @ViewBuilder private func plot(_ s: Series) -> some View {
        Chart {
            ForEach(Array(s.pts.enumerated()), id: \.offset) { i, p in
                marks(i, p, count: s.pts.count, floor: s.scale.lower)
            }
        }
        .chartXScale(domain: s.xDomain)
        .chartYScale(domain: s.scale.lower...s.scale.upper)
        .chartYAxis {
            AxisMarks(position: .trailing, values: s.scale.gridValues) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(DS3.line)
                AxisValueLabel {
                    if let n = v.as(Int.self) {
                        Text("\(n) %").font(.system(size: 12)).monospacedDigit().foregroundStyle(DS3.muted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: s.ticks.map(\.date)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(DS3.lineStrong)
                AxisValueLabel(anchor: .topLeading) {
                    if let d = v.as(Date.self), let m = s.ticks.first(where: { $0.date == d }) {
                        Text(label(m.tick)).font(.system(size: 12)).foregroundStyle(DS3.muted)
                    }
                }
            }
        }
        .chartOverlay { proxy in Hover(proxy: proxy, pts: s.pts, dates: s.dates, initialHover: initialHover) }
        .frame(height: 220)
    }

    @ChartContentBuilder private func marks(_ i: Int, _ p: P, count: Int, floor: Int) -> some ChartContent {
        if count > 1 {
            // The area ends at the domain floor, never 0 (`chart-tooltip-facts`).
            AreaMark(x: .value("day", p.date), yStart: .value("health", floor), yEnd: .value("health", p.health))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(
                    stops: [.init(color: DS3.accent.opacity(0.42), location: 0),
                            .init(color: DS3.accent.opacity(0.02), location: 1)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("day", p.date), y: .value("health", p.health))
                .interpolationMethod(.monotone)
                .foregroundStyle(DS3.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        } else {
            PointMark(x: .value("day", p.date), y: .value("health", p.health))
                .symbol { Circle().fill(DS3.accent).frame(width: 9, height: 9) }
        }
    }

    /// Owns the hover state so the Chart's marks are never rebuilt on hover (D14). Draws the rule, the point and
    /// the tooltip.
    private struct Hover: View {
        let proxy: ChartProxy
        let pts: [P]
        let dates: [Date]
        @State private var hovered: Int?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(proxy: ChartProxy, pts: [P], dates: [Date], initialHover: Int?) {
            self.proxy = proxy
            self.pts = pts
            self.dates = dates
            _hovered = State(initialValue: initialHover)
        }

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    hitArea(geo)
                    marker(geo)
                    tooltipLayer(geo)
                }
            }
        }

        private func hitArea(_ geo: GeometryProxy) -> some View {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let loc):
                        guard let a = proxy.plotFrame else {
                            if hovered != nil { hovered = nil }
                            return
                        }
                        let plot = geo[a]
                        let x = min(max(loc.x, plot.minX), plot.maxX) - plot.minX
                        if let d: Date = proxy.value(atX: x) {
                            let n = IPhoneData.nearestIndex(dates, to: d)
                            if n != hovered { hovered = n }
                        }
                    case .ended:
                        if hovered != nil { hovered = nil }
                    }
                }
        }

        /// No animation modifier on this view or any ancestor inside `Hover`: the rule and the point jump, as the
        /// Chart marks did.
        @ViewBuilder private func marker(_ geo: GeometryProxy) -> some View {
            if let i = hovered, i < pts.count, let a = proxy.plotFrame,
               let px = proxy.position(forX: pts[i].date), let py = proxy.position(forY: pts[i].health) {
                let plot = geo[a]
                Rectangle()
                    .fill(DS3.accent.opacity(0.45))
                    .frame(width: 1, height: plot.height)
                    .position(x: plot.minX + px, y: plot.midY)
                    .allowsHitTesting(false)
                ZStack {
                    Circle().fill(DS3.glassStrong).frame(width: 18, height: 18)
                    Circle().fill(DS3.accent.opacity(0.24)).frame(width: 15, height: 15)
                    Circle().fill(DS3.accent).frame(width: 9, height: 9)
                }
                .position(x: plot.minX + px, y: plot.minY + py)
                .allowsHitTesting(false)
            }
        }

        private func tooltipLayer(_ geo: GeometryProxy) -> some View {
            ZStack(alignment: .topLeading) {
                if let i = hovered, i < pts.count, let a = proxy.plotFrame,
                   let px = proxy.position(forX: pts[i].date), let py = proxy.position(forY: pts[i].health) {
                    let plot = geo[a]
                    let o = IPhoneData.tooltipOrigin(point: CGPoint(x: px, y: py), plot: plot.size)
                    tooltip(pts[i])
                        // Same mechanism as HOVER-TEXT-JITTER (`DSHoverLift`): the day, percent and cycles Texts change
                        // in the same transaction as the animated offset, so without a geometry group they cross-fade
                        // at the in-flight position and leave ghost glyphs outside the box. Must stay BEFORE `.offset`.
                        .geometryGroup()
                        .offset(x: plot.minX + o.x, y: plot.minY + o.y)
                        .allowsHitTesting(false)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.12) : DS3Motion.popIn, value: hovered == nil)
            .animation(DS3Motion.chartTracking, value: hovered)
        }

        private func tooltip(_ p: P) -> some View {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            return VStack(alignment: .leading, spacing: 3) {
                Text(p.day).font(.system(size: 12)).monospacedDigit().foregroundStyle(DS3.muted)
                Text("\(p.health) %")
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.17)
                    .monospacedDigit()
                    .foregroundStyle(DS3.ink)
                // spacing 0 + Spacer(minLength: 4): an HStack(spacing: 8) would add the gap on both sides of the Spacer (16 pt)
                // Worst RU case: «150 циклов» + «sysdiagnose» = 142 pt of 144 pt with the 4 pt minimum gap.
                HStack(spacing: 0) {
                    Text(p.cycles.map { L.iphoneChartCycles($0) } ?? "")
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(p.live ? L.iphoneHistorySourceLive : L.iphoneChartSourceImport)
                        .foregroundStyle(p.live ? DS3.accentInk : DS3.muted)
                }
                .lineLimit(1)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(DS3.inkSoft)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(width: 168, height: 74, alignment: .topLeading)
            .background(shape.fill(DS3.overlay))
            .ds3InsetRims(shape, top: DS3.rimMid, ring: DS3.lineStrong)
            .ds3Elevation(.pop, in: shape)
        }
    }
}

/// IPHONE-DESIGN: history table columns 1.2 : 1 : 1 : 1.4 with 12 pt gaps.
/// REDESIGN-HISTORY: the History table uses it with equal fractions and 16 pt spacing.
struct IPhoneFractionRow: Layout {
    var fractions: [CGFloat] = [1.2, 1, 1, 1.4]
    var spacing: CGFloat = 12
    private func widths(_ w: CGFloat) -> [CGFloat] {
        let avail = max(0, w - spacing * CGFloat(fractions.count - 1))
        let total = fractions.reduce(0, +)
        return fractions.map { avail * $0 / total }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        let ws = widths(w)
        let h = zip(subviews, ws).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (s, w) in zip(subviews, widths(bounds.width)) {
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}

/// One decimal, half-up, with the locale's decimal separator.
func iphoneOneDecimal(_ v: Double) -> String {
    String(format: "%.1f", (v * 10).rounded() / 10).replacingOccurrences(of: ".", with: L.decimalSeparator)
}

/// IPHONE-DESIGN: battery row 0.8 : 2 with a 200 pt minimum for the first child; both get the row height.
private struct IPhoneRatioRow: Layout {
    var spacing: CGFloat = 12
    private func widths(_ w: CGFloat) -> (CGFloat, CGFloat) {
        let first = max(200, (w - spacing) * 0.8 / 2.8)
        return (first, max(0, w - spacing - first))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 700
        let (a, b) = widths(w)
        let h = max(subviews[0].sizeThatFits(ProposedViewSize(width: a, height: nil)).height,
                    subviews[1].sizeThatFits(ProposedViewSize(width: b, height: nil)).height)
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (a, b) = widths(bounds.width)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: a, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + a + spacing, y: bounds.minY),
                          proposal: ProposedViewSize(width: b, height: bounds.height))
    }
}

/// Soft / error / loading message on a row panel (battery, history, logs, identity cards).
struct IPhoneMessagePanel: View {
    enum Tone { case soft, error, loading }

    let text: String
    var tone: Tone = .soft

    var body: some View {
        HStack(spacing: 10) {
            if tone == .loading { DS3Spinner(role: .softRing, size: 14) }
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(tone == .error ? DS3.hotInk : DS3.inkSoft)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
    }
}
