// Engine/HistoryPageModel.swift
// REDESIGN-HISTORY: pure model of the History page (handoff 10-history, History.dc.html). The view draws it.
// Foundation only; covered by Tests/MacDashboardTests/HistoryPageModelTests.
import Foundation

enum HistoryViewMode: Hashable { case chart, table }

/// One plotted sample (moved here from HistoryCard.swift, where it was private).
struct HistoryChartPoint: Equatable, Identifiable {
    let id: String          // "yyyy-MM-dd"
    let date: Date          // local-midnight Date of `id`
    let value: Double
}

struct HistoryYScale: Equatable {
    let lower: Double; let upper: Double; let step: Double
    let gridValues: [Double]   // lower, lower+step, … upper
    let decimals: Int          // label decimals: step < 1 → (step < 0.1 ? 2 : 1), else 0
}

enum HistoryXTick: Equatable {
    case monthStart(date: Date, label: String?)   // dashed line + label (nil when thinned out; nil in 1M: line only, H:91 + H:266)
    case weekLabel(date: Date, label: String)     // label only, 1M

    var date: Date {
        switch self {
        case .monthStart(let d, _), .weekLabel(let d, _): return d
        }
    }
    var label: String? {
        switch self {
        case .monthStart(_, let l): return l
        case .weekLabel(_, let l): return l
        }
    }
}

struct HistoryChartData: Equatable {
    let points: [HistoryChartPoint]
    let xDomain: ClosedRange<Date>
    let yScale: HistoryYScale
    let ticks: [HistoryXTick]
    let metric: HistoryMetric
}

struct HistoryTableData: Equatable {
    let headers: [String]          // after narrow filtering
    let batteryColumn: Int?        // index of the Battery header (for `.help`)
    let rows: [[String?]]          // nil cell → "—" muted; newest first; already cut to 10 unless showAll
    let totalRows: Int
    let hasMore: Bool              // totalRows > 10
    let moreLabel: String          // L.homeShowAll(totalRows) / L.commonShowLess
}

struct HistoryPageModel: Equatable {
    struct Input {
        var entries: [MacHistoryEntry]
        var unreadable: Bool
        var refreshing: Bool
        var metric: HistoryMetric
        var range: HistoryRange        // the stored selection; `effectiveRange` may differ
        var view: HistoryViewMode
        var showAll: Bool
        var narrow: Bool               // windowWidth < 1000
        var now: Date                  // model.fixtureNow ?? Date(): "current year" for date labels
        var historyPath: String        // display path for the error block
    }
    struct Bar: Equatable { enum Tone { case neutral, hot, accent }; var sub: String; var tone: Tone; var tag: String }
    enum Block: Equatable {
        case error(path: String)
        case wait
        case empty(title: String, sub: String)
        case chart(HistoryChartData)
        case table(HistoryTableData)
    }

    var title: String
    var caption: String
    var showsMetricControl: Bool       // view == .chart
    var showsRangeRow: Bool            // block is not error/wait
    var enabledRanges: Set<HistoryRange>
    var disabledHelp: String?          // reason for the disabled ranges (nil when all enabled)
    var effectiveRange: HistoryRange?  // nil ⇒ < 2 samples
    var deltaCaption: String?          // chart mode only
    var block: Block

    static let collapsedRows = 10
    static let fileName = "mac_check_state.json"
    static let daysPerMonth = 30.44

    // MARK: dates

    /// Same locale/timeZone/format as `HistorySeries.dayFormatter` (local midnight, not UTC).
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    static func parseDay(_ s: String) -> Date? { dayFormatter.date(from: s) }

    /// Calendar days from the first to the last sample (last − first); nil for no entries or an unparseable date.
    static func spanDays(_ entries: [MacHistoryEntry]) -> Int? {
        guard let f = entries.first, let l = entries.last,
              let a = HomeModel.dayNumber(f.date), let b = HomeModel.dayNumber(l.date) else { return nil }
        return b - a
    }

    // MARK: ranges (D21)

    /// A range is enabled iff there are ≥ 2 samples and (it is All or the data covers at least `range.days`
    /// calendar days, first…last inclusive).
    static func enabledRanges(sampleCount: Int, spanDays: Int) -> Set<HistoryRange> {
        guard sampleCount >= 2 else { return [] }
        let covered = spanDays + 1
        return Set(HistoryRange.allCases.filter { r in r.days.map { $0 <= covered } ?? true })
    }

    /// `selected` when enabled, else the last enabled range in `HistoryRange.allCases` order (All whenever there are
    /// ≥ 2 samples: «122 days of data, 1Y selected → All»); nil when none is enabled.
    static func effectiveRange(selected: HistoryRange, enabled: Set<HistoryRange>) -> HistoryRange? {
        if enabled.contains(selected) { return selected }
        return HistoryRange.allCases.last { enabled.contains($0) }
    }

    /// Calendar days in the window: `range.days`, or first…last inclusive for All.
    static func windowDays(range: HistoryRange, spanDays: Int) -> Int { range.days ?? (spanDays + 1) }

    /// `range.days` consecutive calendar days ending on the last sample's day (as `HistorySeries.dateRange`,
    /// but with the caller's calendar); All = first…last day. nil for no entries / unparseable dates.
    static func window(_ entries: [MacHistoryEntry], range: HistoryRange, calendar: Calendar) -> ClosedRange<Date>? {
        guard let first = entries.first.flatMap({ parseDay($0.date) }),
              let last = entries.last.flatMap({ parseDay($0.date) }) else { return nil }
        guard let days = range.days else { return first...last }
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: last) else { return nil }
        return start...last
    }

    static func visiblePoints(_ entries: [MacHistoryEntry], metric: HistoryMetric, range: HistoryRange,
                              calendar: Calendar) -> [HistoryChartPoint] {
        guard let w = window(entries, range: range, calendar: calendar) else { return [] }
        let parsed: [HistoryChartPoint] = HistorySeries.series(entries, metric: metric).compactMap { p in
            guard let d = parseDay(p.date), w.contains(d) else { return nil }
            return HistoryChartPoint(id: p.date, date: d, value: p.value)
        }
        return HistorySeries.thinned(parsed, maxCount: HistorySeries.maxChartPoints)
    }

    // MARK: delta per month (D10)

    /// (last − first) / (day difference / 30.44); nil for < 2 points or the same day.
    static func deltaPerMonth(_ points: [HistoryChartPoint]) -> Double? {
        guard let f = points.first, let l = points.last, points.count >= 2,
              let a = HomeModel.dayNumber(f.id), let b = HomeModel.dayNumber(l.id), b != a else { return nil }
        return (l.value - f.value) / (Double(b - a) / daysPerMonth)
    }

    /// Cycles are whole numbers; Disk, Battery (percent points) and Swap: |Δ| < 1 → 2, < 10 → 1, else 0.
    static func deltaDecimals(_ delta: Double, metric: HistoryMetric) -> Int {
        if metric == .cycles { return 0 }
        let a = abs(delta)
        return a < 1 ? 2 : (a < 10 ? 1 : 0)
    }

    static func deltaCaption(_ delta: Double, metric: HistoryMetric) -> String {
        let d = deltaDecimals(delta, metric: metric)
        let f = pow(10.0, Double(d))
        let magnitude = (abs(delta) * f).rounded() / f
        let sign = magnitude == 0 ? "±" : (delta > 0 ? "+" : "\u{2212}")
        // A magnitude that rounds to 0 prints as a plain «0» («±0 GB per month»), not «0.00».
        let number = d == 0 || magnitude == 0 ? fmtGrouped(Int(magnitude)) : fmtFixed(magnitude, decimals: d)
        let value: String
        switch metric {
        case .cycles: value = L.historyCycles(Int(magnitude))
        case .battery:
            value = L.historyPercentText(number)
        case .disk, .swap:
            value = number + " " + L.byteUnitGB
        }
        return L.historyDeltaPerMonth(sign + value)
    }

    // MARK: y scale (D3, D17)

    static func yScale(values: [Double], integer: Bool) -> HistoryYScale {
        var mn = values.min() ?? 0, mx = values.max() ?? 0
        var pad = (mx - mn) * 0.1
        if pad == 0 { pad = 1 }
        mn -= pad; mx += pad
        let raw = (mx - mn) / 4
        let pw10 = pow(10.0, floor(log10(raw)))
        var step = [1.0, 2, 5, 10].map { $0 * pw10 }.first { $0 >= raw } ?? 10 * pw10
        if integer { step = max(step, 1) }
        let lower = floor(mn / step) * step
        let upper = ceil(mx / step) * step
        let count = Int(((upper - lower) / step).rounded()) + 1
        let grid = (0..<count).map { lower + Double($0) * step }
        return HistoryYScale(lower: lower, upper: upper, step: step, gridValues: grid,
                             decimals: step < 1 ? (step < 0.1 ? 2 : 1) : 0)
    }

    static func axisLabel(_ v: Double, metric: HistoryMetric, decimals: Int) -> String {
        let number = decimals == 0 ? fmtGrouped(Int(v.rounded())) : fmtFixed(v, decimals: decimals)
        switch metric {
        case .disk, .swap: return number + " " + L.byteUnitGB
        case .battery: return L.historyPercent(Int(v.rounded()))
        case .cycles: return number
        }
    }

    static func tooltipValue(_ v: Double, metric: HistoryMetric) -> String {
        switch metric {
        case .disk: return L.historyGbValue(Int(v.rounded()))
        case .battery: return L.historyPercent(Int(v.rounded()))
        case .cycles: return L.historyCycles(Int(v.rounded()))
        case .swap: return fmtFixed(v, decimals: 2) + " " + L.byteUnitGB
        }
    }

    // MARK: x ticks

    static func xTicks(window: ClosedRange<Date>, range: HistoryRange, narrow: Bool, calendar: Calendar) -> [HistoryXTick] {
        let start = window.lowerBound, end = window.upperBound
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return [] }
        let sc = calendar.dateComponents([.year, .month], from: start)
        guard var y = sc.year, var m = sc.month else { return [] }
        var starts: [(date: Date, month: Int, year: Int)] = []
        while true {
            m += 1
            if m > 12 { m = 1; y += 1 }
            guard let d = calendar.date(from: DateComponents(year: y, month: m, day: 1)) else { break }
            if d > end { break }
            let x = d.timeIntervalSince(start) / total
            if d <= start || x < 0.015 || x > 0.985 { continue }
            starts.append((d, m, y))
        }
        if range == .month {
            let weeks: [HistoryXTick] = [25, 18, 11, 4].compactMap { back in
                guard let d = calendar.date(byAdding: .day, value: -back, to: end) else { return nil }
                let c = calendar.dateComponents([.day, .month], from: d)
                return .weekLabel(date: d, label: L.historyShortDate(day: c.day ?? 1, month: c.month ?? 1, year: nil))
            }
            return starts.map { HistoryXTick.monthStart(date: $0.date, label: nil) } + weeks
        }
        let n = starts.count
        let limit = narrow ? 7 : 10
        return starts.enumerated().map { i, s in
            let label = s.month == 1 ? String(s.year) : L.historyMonthLabel(s.month)
            let keep = n <= limit || i % 2 == (n - 1) % 2
            return .monthStart(date: s.date, label: keep ? label : nil)
        }
    }

    // MARK: display dates (D13)

    static func shortDate(_ d: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        let ny = calendar.component(.year, from: now)
        return L.historyShortDate(day: c.day ?? 1, month: c.month ?? 1, year: c.year == ny ? nil : c.year)
    }

    static func tooltipDate(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: d)
        return L.historyTooltipDate(weekday: c.weekday ?? 1, day: c.day ?? 1, month: c.month ?? 1, year: c.year ?? 1970)
    }

    // MARK: table (D6, D7, D8)

    static func table(_ entries: [MacHistoryEntry], window: ClosedRange<Date>?, narrow: Bool, showAll: Bool,
                      now: Date, calendar: Calendar) -> HistoryTableData {
        let inWindow = entries.filter { e in
            guard let w = window else { return true }
            guard let d = parseDay(e.date) else { return false }
            return w.contains(d)
        }
        let all: [[String?]] = inWindow.reversed().map { e in
            let date = parseDay(e.date).map { shortDate($0, now: now, calendar: calendar) } ?? e.date
            return [date,
                    e.disk_used_gb.map { L.historyGbValue($0) },
                    e.disk_free_gb.map { L.historyGbValue($0) },
                    e.battery_pct.map { L.historyPercent($0) },
                    e.cycles.map { fmtGrouped($0) },
                    HistorySeries.formattedSwap(e.swap),
                    e.macos]
        }
        let headers = [L.historyColDate, L.historyColDiskUsed, L.historyColFree, L.commonBattery,
                       L.historyColCycles, "Swap", "macOS"]
        let hidden: Set<Int> = narrow ? [2, 6] : []
        func keep<T>(_ a: [T]) -> [T] { a.enumerated().filter { !hidden.contains($0.offset) }.map(\.element) }
        let shownHeaders = keep(headers)
        let rows = (showAll ? all : Array(all.prefix(collapsedRows))).map { keep($0) }
        return HistoryTableData(headers: shownHeaders,
                                batteryColumn: shownHeaders.firstIndex(of: L.commonBattery),
                                rows: rows, totalRows: all.count, hasMore: all.count > collapsedRows,
                                moreLabel: showAll ? L.commonShowLess : L.homeShowAll(all.count))
    }

    // MARK: page bar (D20)

    static func bar(entries: [MacHistoryEntry], unreadable: Bool, refreshing: Bool, now: Date,
                    calendar: Calendar = .current) -> Bar {
        if unreadable && refreshing { return Bar(sub: fileName, tone: .accent, tag: L.historyTagReading) }
        if unreadable { return Bar(sub: fileName, tone: .hot, tag: L.historyTagUnreadable) }
        var tag = ""
        if let first = entries.first, let d = parseDay(first.date) {
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            let sameYear = c.year == calendar.component(.year, from: now)
            tag = L.historySince(day: c.day ?? 1, month: c.month ?? 1, year: sameYear ? nil : c.year)
        }
        return Bar(sub: L.historySub(entries.count), tone: .neutral, tag: tag)
    }

    // MARK: page / card

    static func make(_ i: Input, calendar: Calendar = .current) -> HistoryPageModel {
        let entries = i.entries
        let span = spanDays(entries) ?? 0
        let enabled = enabledRanges(sampleCount: entries.count, spanDays: span)
        let effective = effectiveRange(selected: i.range, enabled: enabled)
        let covered = span + 1
        let help: String?
        if entries.count < 2 { help = L.historyNeedsTwo }
        else if enabled.count < HistoryRange.allCases.count {
            help = L.historyOnlyMonths(Int((Double(covered) / daysPerMonth).rounded()))
        } else { help = nil }

        let title: String
        if i.view == .table { title = L.historyAllMetrics }
        else {
            switch i.metric {
            case .disk: title = L.historyTitleDisk
            case .battery: title = L.historyTitleBattery
            case .cycles: title = L.historyTitleCycles
            case .swap: title = L.historyTitleSwap
            }
        }
        let caption = effective.map { L.historyDaysCaption(windowDays(range: $0, spanDays: span)) }
            ?? L.historySamples(entries.count)

        var block: Block
        var delta: String?
        if i.unreadable {
            block = i.refreshing ? .wait : .error(path: i.historyPath)
        } else if let r = effective, let w = window(entries, range: r, calendar: calendar) {
            if i.view == .table {
                block = .table(table(entries, window: w, narrow: i.narrow, showAll: i.showAll, now: i.now, calendar: calendar))
            } else {
                let pts = visiblePoints(entries, metric: i.metric, range: r, calendar: calendar)
                if pts.count >= 2 {
                    let scale = yScale(values: pts.map(\.value), integer: i.metric == .battery || i.metric == .cycles)
                    block = .chart(HistoryChartData(points: pts, xDomain: w, yScale: scale,
                                                    ticks: xTicks(window: w, range: r, narrow: i.narrow, calendar: calendar),
                                                    metric: i.metric))
                    delta = deltaPerMonth(pts).map { deltaCaption($0, metric: i.metric) }
                } else {
                    block = .empty(title: L.historyEmptyTitle, sub: L.historyEmptySub(pts.count))
                }
            }
        } else {
            block = .empty(title: L.historyEmptyTitle, sub: L.historyEmptySub(entries.count))
        }

        let isState: Bool
        switch block { case .error, .wait: isState = true; default: isState = false }
        return HistoryPageModel(title: title, caption: caption, showsMetricControl: i.view == .chart,
                                showsRangeRow: !isState, enabledRanges: enabled, disabledHelp: help,
                                effectiveRange: effective, deltaCaption: delta, block: block)
    }
}
