// Views/HistoryPage.swift
// REDESIGN-HISTORY: the History section page (handoff 10-history, History.dc.html) on the shared §8 blocks.
// Every text, range state and row comes from the pure HistoryPageModel; this file only draws them.
import SwiftUI
import Charts

@MainActor
struct HistoryPage: View {
    let model: DashboardModel
    let router: NavigationRouter
    let windowWidth: CGFloat
    let onBack: () -> Void
    @State private var pulse: CardID? = nil

    /// Reads no live model field (only `router.navigationSerial` / `destination`): the bar and the card do the reading.
    var body: some View {
        ScrollViewReader { _ in            // one card, no scrollTo needed
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HistoryCardView(model: model, router: router, narrow: windowWidth < 1000)
                        .id(CardID.hist)
                        .sectionFocusPulse(pulse == .hist)
                        .ds3Appear(delay: 0.08)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) { HistoryPageBar(model: model, onBack: onBack) }
            .task(id: router.navigationSerial) {
                let d = router.destination
                guard d.page == .history, d.focus == .hist else { return }
                pulse = .hist
                try? await Task.sleep(for: .seconds(3))
                pulse = nil
            }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
    }
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it.
@MainActor
struct HistoryPageBar: View {
    let model: DashboardModel
    let onBack: () -> Void

    var body: some View {
        let b = HistoryPageModel.bar(entries: model.history.mac_history, unreadable: model.historyUnreadable,
                                     refreshing: model.historyRefreshing, now: model.fixtureNow ?? Date())
        SectionPageBar(symbol: Page.history.symbol, title: Page.history.title, sub: b.sub, onBack: onBack) {
            if !b.tag.isEmpty { DS3Tag(tone: tone(b.tone), text: b.tag).help(b.tag) }
        } trailing: {
            refresh
        }
    }

    private func tone(_ t: HistoryPageModel.Bar.Tone) -> DS3Tag.Tone {
        switch t {
        case .neutral: return .neutral
        case .hot: return .hot
        case .accent: return .accent
        }
    }

    /// Opacity ZStack: «Refresh» ↔ «Refreshing…» without a width change (`swap-in-place`).
    private var refresh: some View {
        let busy = model.historyRefreshing
        return Button { model.refreshHistoryNow() } label: {
            ZStack {
                Text(L.commonRefresh).opacity(busy ? 0 : 1)
                Text(L.commonRefreshing).opacity(busy ? 1 : 0)
            }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14))
        .disabled(busy)
        .accessibilityLabel(L.historyRefreshA11y)
        .accessibilityIdentifier("history-refresh")
    }
}

// MARK: - Card

/// Internal (not private): the visual fixture renders it with pinned states (`initial*`, D15).
@MainActor
struct HistoryCardView: View {
    let model: DashboardModel
    let router: NavigationRouter
    let narrow: Bool
    @State private var metric: HistoryMetric
    @State private var range: HistoryRange
    @State private var view: HistoryViewMode
    @State private var showAll: Bool
    /// true after the first Chart | Table switch: the entering block then plays its entrance (D16).
    @State private var switched = false
    private let initialHover: Int?

    init(model: DashboardModel, router: NavigationRouter, narrow: Bool,
         initialMetric: HistoryMetric = .disk, initialRange: HistoryRange = .month,
         initialView: HistoryViewMode = .chart, initialShowAll: Bool = false, initialHover: Int? = nil) {
        self.model = model
        self.router = router
        self.narrow = narrow
        _metric = State(initialValue: initialMetric)
        _range = State(initialValue: initialRange)
        _view = State(initialValue: initialView)
        _showAll = State(initialValue: initialShowAll)
        self.initialHover = initialHover
    }

    var body: some View {
        let m = HistoryPageModel.make(.init(entries: model.history.mac_history, unreadable: model.historyUnreadable,
                                            refreshing: model.historyRefreshing, metric: metric, range: range, view: view,
                                            showAll: showAll, narrow: narrow, now: model.fixtureNow ?? Date(),
                                            historyPath: model.historyFilePath))
        DS3Card(title: m.title, caption: m.caption, trailing: {
            HStack(spacing: 10) {
                if m.showsMetricControl { metricControl }
                viewControl
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                if let name = model.history.unreadable_backup { restartNote(name) }
                if m.showsRangeRow {
                    // The range row's branch depends only on unreadable/refreshing, never on range/metric/view,
                    // so the range control keeps its own slide (`control-identity-branch`).
                    VStack(alignment: .leading, spacing: 8) {
                        rangeRow(m)
                        content(m)
                    }
                } else {
                    stateBlock(m)       // error / wait
                }
            }
        }
        .onChange(of: router.navigationSerial, initial: true) { applyDestination() }
        .onChange(of: range) { showAll = false }     // 10-history: a range change collapses the table
    }

    // MARK: Controls (outside every data/mode branch)

    /// Shown only in chart mode (`History.dc.html:292`). Its branch depends on `view`, never on `metric`, so its own
    /// slide survives every metric change (`control-identity-branch`).
    private var metricControl: some View {
        DSSlidingSegmented(options: HistoryMetric.allCases, selection: $metric, size: .section,
                           groupLabel: L.historyMetricA11y, identifier: { "history-metric-\($0)" }) { o in
            switch o {
            case .disk: return L.historyMetricPickerDisk
            case .battery: return L.historyMetricPickerBattery
            case .cycles: return L.historyMetricPickerCycles
            case .swap: return L.historyMetricPickerSwap
            }
        }
    }

    private var viewBinding: Binding<HistoryViewMode> {
        Binding(get: { view }, set: { view = $0; switched = true; showAll = false })
    }

    private var viewControl: some View {
        DSSlidingSegmented(options: [HistoryViewMode.chart, .table], selection: viewBinding, size: .section,
                           groupLabel: L.historyViewA11y,
                           identifier: { $0 == .chart ? "history-view-chart" : "history-view-table" }) { o in
            o == .chart ? L.commonChart : L.commonTable
        }
    }

    /// The thumb shows the fallback range; the stored selection is untouched until the user picks (R4).
    private func rangeRow(_ m: HistoryPageModel) -> some View {
        let binding = Binding<HistoryRange>(get: { m.effectiveRange ?? range }, set: { range = $0 })
        return HStack(spacing: 10) {
            DSSlidingSegmented(options: HistoryRange.allCases, selection: binding, size: .section,
                               groupLabel: L.historyRangeA11y, identifier: { "history-range-\($0)" },
                               disabled: { !m.enabledRanges.contains($0) }, disabledHelp: m.disabledHelp) { o in
                switch o {
                case .month: return L.historyRangeMonth
                case .quarter: return L.historyRangeQuarter
                case .year: return L.historyRangeYear
                case .all: return L.historyRangeAll
                }
            }
            if let d = m.deltaCaption {
                Text(d).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(DS3.muted).lineLimit(1)
            }
        }
    }

    // MARK: Blocks

    @ViewBuilder private func content(_ m: HistoryPageModel) -> some View {
        switch m.block {
        case .chart(let d):
            HistoryChart(data: d, initialHover: initialHover)
                .modifier(HistoryBlockEnter(animated: switched))
                .id(view)
        case .table(let t):
            tableBlock(t)
                .modifier(HistoryBlockEnter(animated: switched))
                .id(view)
        case .empty(let title, let sub):
            emptyPanel(title, sub)
        case .error, .wait:
            EmptyView()
        }
    }

    @ViewBuilder private func stateBlock(_ m: HistoryPageModel) -> some View {
        switch m.block {
        case .error(let path): errorBlock(path)
        case .wait: SectionWait(text: L.historyReading)
        default: EmptyView()
        }
    }

    private func emptyPanel(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(sub).font(.system(size: 12.5)).monospacedDigit()
        }
        .foregroundStyle(DS3.muted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 246)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), ring: DS3.line)
    }

    private func errorBlock(_ path: String) -> some View {
        HStack(spacing: 12) {
            Circle().fill(DS3.hot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.historyUnreadableTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS3.hotInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(path)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(0.26)
                    .foregroundStyle(DS3.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button(L.commonTryAgain) { model.refreshHistoryNow() }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                .accessibilityLabel(L.historyTryAgainA11y)
                .accessibilityIdentifier("history-try-again")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .ds3TintPanel(DS3.hot, from: 0.14, to: 0.05, ring: 0.45, cornerRadius: 20)
    }

    /// The «History started over» notice (D9, D19): a neutral note inside the card, above the range row.
    private func restartNote(_ name: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(DS3.muted).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.historyRestartTitle).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(DS3.ink)
                Text(L.historyRestartDetail(name))
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS3.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button(L.historyRestartReveal) {
                    if let p = model.historyRestartRevealPath { AdviceActionRunner.reveal(p) }
                }
                .accessibilityLabel(L.historyRestartRevealA11y)
                .accessibilityIdentifier("history-restart-reveal")
                Button(L.historyRestartHide) { model.dismissHistoryRestartNotice() }
                    .accessibilityLabel(L.historyRestartHideA11y)
                    .accessibilityIdentifier("history-restart-hide")
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
            .layoutPriority(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .ds3RowPanel(cornerRadius: 20)
    }

    private func tableBlock(_ t: HistoryTableData) -> some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                headerRow(t)
                ForEach(t.rows.indices, id: \.self) { HistoryTableRow(cells: t.rows[$0]) }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
            .ds3InsetRims(RoundedRectangle(cornerRadius: 22, style: .continuous), ring: DS3.line)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L.historyTableA11y)
            if t.hasMore {
                HomeShowAllButton(title: t.moreLabel) { showAll.toggle() }
            }
        }
    }

    private func headerRow(_ t: HistoryTableData) -> some View {
        IPhoneFractionRow(fractions: Array(repeating: 1, count: t.headers.count), spacing: 16) {
            ForEach(t.headers.indices, id: \.self) { i in
                Text(t.headers[i])
                    .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
                    .help(i == t.batteryColumn ? L.historyBatteryHelp : "")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(DS3.muted)
        .lineLimit(1)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }

    private func applyDestination() {
        let d = router.destination
        guard d.page == .history, let m = d.historyMetric else { return }
        metric = m
        if view != .chart { view = .chart; switched = true }
    }
}

// MARK: - Table row

private struct HistoryTableRow: View {
    let cells: [String?]
    @State private var hover = false

    var body: some View {
        IPhoneFractionRow(fractions: Array(repeating: 1, count: cells.count), spacing: 16) {
            ForEach(cells.indices, id: \.self) { i in
                Text(cells[i] ?? "—")
                    .foregroundStyle(cells[i] == nil ? DS3.muted : DS3.ink)
                    .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
            }
        }
        .font(.system(size: 13.5))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? DS3.lens : Color.clear))
        .overlay(alignment: .top) { Rectangle().fill(DS3.line).frame(height: 1) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.16), value: hover)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Block entrance (D16)

/// The Chart | Table entrance: `DS3Appear`'s shape (opacity/scale/offset from a `@State` committed in `onAppear`),
/// played only after the first switch (`animated`). Not `.animation(value: view)`: the block's size depends on `view`
/// (`animation-value-size-coupling`). Reduce Motion: opacity only, 0.12 s.
private struct HistoryBlockEnter: ViewModifier {
    let animated: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : DS3Motion.appearScale)
            .offset(y: shown || reduceMotion ? 0 : DS3Motion.appearOffsetY)
            .onAppear {
                if !animated || DS3Motion.isFrozen {
                    shown = true
                } else if reduceMotion {
                    withAnimation(.easeOut(duration: 0.12)) { shown = true }
                } else {
                    withAnimation(DS3Motion.appear.delay(0.08)) { shown = true }
                }
            }
    }
}

// MARK: - Chart

/// Time-based x over the range window, DS3 axes, hover rule/point/tooltip as CA layers (`HistoryHoverLayer`).
private struct HistoryChart: View {
    let data: HistoryChartData
    let initialHover: Int?

    var body: some View {
        let scale = data.yScale
        Chart {
            ForEach(data.points) { p in
                // The area ends at the domain floor, never 0 (`chart-tooltip-facts`).
                AreaMark(x: .value("day", p.date), yStart: .value("v", scale.lower), yEnd: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(
                        stops: [.init(color: DS3.accent.opacity(0.42), location: 0),
                                .init(color: DS3.accent.opacity(0.02), location: 1)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("day", p.date), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(DS3.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXScale(domain: data.xDomain)
        .chartYScale(domain: scale.lower...scale.upper)
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.gridValues) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(DS3.line)
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(HistoryPageModel.axisLabel(d, metric: data.metric, decimals: scale.decimals))
                            .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(DS3.muted)
                    }
                }
            }
        }
        .chartXAxis {
            // Dashed lines only at month starts (`.weekLabel` draws none, History.dc.html:91); a thinned month
            // start keeps its line and has no label.
            AxisMarks(values: monthLineDates) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(DS3.lineStrong)
            }
            AxisMarks(values: labelledTicks.map(\.date)) { v in
                AxisValueLabel(anchor: .top) {
                    if let d = v.as(Date.self), let l = labelledTicks.first(where: { $0.date == d })?.label {
                        Text(l).font(.system(size: 11.5)).foregroundStyle(DS3.muted)
                    }
                }
            }
        }
        .chartOverlay { proxy in Hover(proxy: proxy, points: data.points, metric: data.metric, initialHover: initialHover) }
        .frame(height: 246)    // 220 plot + 26 axis strip (History.dc.html:89)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history-chart")
    }

    private var monthLineDates: [Date] {
        data.ticks.compactMap { if case .monthStart(let d, _) = $0 { return d } else { return nil } }
    }

    private var labelledTicks: [HistoryXTick] { data.ticks.filter { $0.label != nil } }

    /// Owns no state: converts the proxy into pixel positions once per layout and hands them to the Core Animation
    /// overlay (`HistoryHoverLayer`), so neither the Chart's marks nor any SwiftUI view update on hover (HISTORY-HOVER-COST).
    private struct Hover: View {
        let proxy: ChartProxy
        let points: [HistoryChartPoint]
        let metric: HistoryMetric
        let initialHover: Int?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { geo in
                HistoryHoverLayer(frame: frame(geo), points: points, metric: metric,
                                  reduceMotion: reduceMotion, initialHover: initialHover)
            }
        }

        /// nil when the plot frame or any sample position is unknown; then nothing is shown and hover ends.
        private func frame(_ geo: GeometryProxy) -> HistoryHoverFrame? {
            guard let a = proxy.plotFrame else { return nil }
            let plot = geo[a]
            var xs: [CGFloat] = []; var ys: [CGFloat] = []
            xs.reserveCapacity(points.count); ys.reserveCapacity(points.count)
            for p in points {
                guard let px = proxy.position(forX: p.date), let py = proxy.position(forY: p.value) else { return nil }
                xs.append(plot.minX + px); ys.append(plot.minY + py)
            }
            return HistoryHoverFrame(plot: plot, xs: xs, ys: ys)
        }
    }
}
