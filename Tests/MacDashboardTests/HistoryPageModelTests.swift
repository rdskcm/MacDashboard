// Tests/MacDashboardTests/HistoryPageModelTests.swift
// REDESIGN-HISTORY: the pure History page model (Engine/HistoryPageModel.swift) — range availability and
// fallback, delta per month, y scale, x ticks, date labels, table rows, bar and titles. Language-dependent
// strings, so the suite sits in `SerialTests` and every test sets and restores the UI language.
import Foundation
import Testing
@testable import MacDashboard

@MainActor private func withLanguage(_ lang: AppLanguage, _ body: @MainActor () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    return c
}()

private let dayFmt: DateFormatter = {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "yyyy-MM-dd"
    return df
}()

private func day(_ s: String) -> Date { dayFmt.date(from: s)! }

private func entry(_ date: String, disk: Int? = 300, free: Int? = 200, pct: Int? = 90, cycles: Int? = 100,
                   swap: String? = "512MB/2048MB", macos: String? = "26.1 (25B78)") -> MacHistoryEntry {
    MacHistoryEntry(date: date, disk_used_gb: disk, disk_free_gb: free, battery_pct: pct, cycles: cycles,
                    swap: swap, macos: macos)
}

/// `n` consecutive daily entries ending on `end`; `tweak(i, &entry)` edits entry i (0 = oldest).
private func entries(_ n: Int, end: String = "2026-10-21", tweak: (Int, inout MacHistoryEntry) -> Void = { _, _ in }) -> [MacHistoryEntry] {
    let last = day(end)
    return (0..<n).map { i in
        let d = cal.date(byAdding: .day, value: -(n - 1 - i), to: last)!
        var e = entry(dayFmt.string(from: d))
        tweak(i, &e)
        return e
    }
}

private func input(_ e: [MacHistoryEntry], metric: HistoryMetric = .disk, range: HistoryRange = .month,
                   view: HistoryViewMode = .chart, showAll: Bool = false, narrow: Bool = false,
                   unreadable: Bool = false, refreshing: Bool = false) -> HistoryPageModel.Input {
    .init(entries: e, unreadable: unreadable, refreshing: refreshing, metric: metric, range: range, view: view,
          showAll: showAll, narrow: narrow, now: day("2026-10-21"), historyPath: "~/x/mac_check_state.json")
}

@MainActor private func make(_ i: HistoryPageModel.Input) -> HistoryPageModel { HistoryPageModel.make(i, calendar: cal) }

private func pt(_ date: String, _ v: Double) -> HistoryChartPoint { .init(id: date, date: day(date), value: v) }
private func chart(_ m: HistoryPageModel) -> HistoryChartData? { if case .chart(let d) = m.block { return d } else { return nil } }

extension SerialTests {
    @MainActor struct HistoryPageModelTests {
        @Test func spanAndRanges() {
            withLanguage(.en) {
                let e500 = entries(500)
                #expect(HistoryPageModel.spanDays(e500) == 499)
                #expect(HistoryPageModel.enabledRanges(sampleCount: 500, spanDays: 499) == Set(HistoryRange.allCases))
                #expect(make(input(e500)).disabledHelp == nil)

                let m122 = make(input(entries(122)))
                #expect(m122.enabledRanges == [.month, .quarter, .all])
                #expect(m122.disabledHelp == "Only 4 months of data")

                let m30 = make(input(entries(30)))
                #expect(m30.enabledRanges == [.month, .all])
                #expect(m30.disabledHelp == "Only 1 month of data")

                let m1 = make(input(entries(1)))
                #expect(m1.enabledRanges.isEmpty)
                #expect(m1.disabledHelp == "Needs at least 2 samples")

                #expect(make(input(entries(2))).enabledRanges == [.all])
                #expect(HistoryPageModel.spanDays([]) == nil)
            }
            withLanguage(.ru) {
                #expect(make(input(entries(122))).disabledHelp == "Данных только за 4 месяца")
            }
        }

        @Test func fallback() {
            withLanguage(.en) {
                let e122 = entries(122)
                let en122 = HistoryPageModel.enabledRanges(sampleCount: 122, spanDays: 121)
                #expect(HistoryPageModel.effectiveRange(selected: .year, enabled: en122) == .all)
                #expect(HistoryPageModel.effectiveRange(selected: .all, enabled: en122) == .all)
                let en10 = HistoryPageModel.enabledRanges(sampleCount: 10, spanDays: 9)
                #expect(HistoryPageModel.effectiveRange(selected: .month, enabled: en10) == .all)
                #expect(HistoryPageModel.effectiveRange(selected: .month, enabled: []) == nil)
                // the stored selection is never rewritten: the model reports the fallback, the input keeps `.year`
                let m = make(input(e122, range: .year))
                #expect(m.effectiveRange == .all && m.caption == "122 days")

                let one = make(input(entries(1)))
                #expect(one.block == .empty(title: "Not enough data yet", sub: "1 sample · the chart needs at least 2"))
                #expect(one.caption == "1 sample")
                #expect(one.effectiveRange == nil)
            }
        }

        @Test func deltaCaption() {
            // two samples `gap` days apart, `.all` range
            func caption(_ metric: HistoryMetric, _ first: MacHistoryEntry, _ last: MacHistoryEntry) -> String? {
                make(input([first, last], metric: metric, range: .all)).deltaCaption
            }
            withLanguage(.en) {
                #expect(caption(.disk, entry("2026-08-01", disk: 100), entry("2026-10-01", disk: 148)) == "+24 GB per month")
                #expect(caption(.cycles, entry("2026-08-01", cycles: 400), entry("2026-10-01", cycles: 394)) == "−3 cycles per month")
                #expect(caption(.swap, entry("2026-09-01", swap: "1024MB/2048MB"), entry("2026-10-01", swap: "1536MB/2048MB")) == "+0.51 GB per month")
                #expect(caption(.disk, entry("2026-09-01", disk: 100), entry("2026-10-01", disk: 100)) == "±0 GB per month")
                #expect(caption(.cycles, entry("2026-09-01", cycles: 400), entry("2026-10-01", cycles: 401)) == "+1 cycle per month")
                // battery uses the disk/swap decimals rule, formatted as a percent: 90 → 89 and 90 → 80 over 61 days
                #expect(caption(.battery, entry("2026-08-01", pct: 90), entry("2026-10-01", pct: 89)) == "−0.50% per month")
                #expect(caption(.battery, entry("2026-08-01", pct: 90), entry("2026-10-01", pct: 80)) == "−5.0% per month")
                #expect(caption(.battery, entry("2026-08-01", pct: 90), entry("2026-10-01", pct: 90)) == "±0% per month")
                #expect(HistoryPageModel.deltaPerMonth([pt("2026-10-01", 1)]) == nil)
                #expect(HistoryPageModel.deltaPerMonth([pt("2026-10-01", 1), pt("2026-10-01", 2)]) == nil)
                // table mode has no delta caption
                #expect(make(input(entries(30), view: .table)).deltaCaption == nil)
            }
            withLanguage(.ru) {
                #expect(caption(.disk, entry("2026-08-01", disk: 100), entry("2026-10-01", disk: 148)) == "+24 ГБ за месяц")
                #expect(caption(.cycles, entry("2026-08-01", cycles: 400), entry("2026-10-01", cycles: 394)) == "−3 цикла за месяц")
                #expect(caption(.swap, entry("2026-09-01", swap: "1024MB/2048MB"), entry("2026-10-01", swap: "1536MB/2048MB")) == "+0,51 ГБ за месяц")
                #expect(caption(.battery, entry("2026-08-01", pct: 90), entry("2026-10-01", pct: 89)) == "−0,50 % за месяц")
            }
        }

        @Test func yScale() {
            func close(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 } }
            withLanguage(.en) {
                let a = HistoryPageModel.yScale(values: [96, 140], integer: false)
                #expect((a.gridValues[1] - a.gridValues[0]) == 20 && a.lower == 80 && a.upper == 160 && a.decimals == 0)
                #expect(a.gridValues == [80, 100, 120, 140, 160])
                let b = HistoryPageModel.yScale(values: [1.2, 1.3], integer: false)
                #expect(abs((b.gridValues[1] - b.gridValues[0]) - 0.05) < 1e-9 && b.decimals == 2 && abs(b.lower - 1.15) < 1e-9 && abs(b.upper - 1.35) < 1e-9)
                let c = HistoryPageModel.yScale(values: [76, 76], integer: true)
                #expect((c.gridValues[1] - c.gridValues[0]) == 1 && c.lower == 75 && c.upper == 77 && c.gridValues == [75, 76, 77])
                let d = HistoryPageModel.yScale(values: [76, 76], integer: false)
                #expect((d.gridValues[1] - d.gridValues[0]) == 0.5 && d.decimals == 1)
                #expect(close(d.gridValues, [75, 75.5, 76, 76.5, 77]))
                #expect(HistoryPageModel.axisLabel(76, metric: .battery, decimals: 0) == "76%")
                #expect(HistoryPageModel.axisLabel(1200, metric: .disk, decimals: 0) == "1,200 GB")
                #expect(HistoryPageModel.axisLabel(1.25, metric: .swap, decimals: 2) == "1.25 GB")
                #expect(HistoryPageModel.axisLabel(412, metric: .cycles, decimals: 0) == "412")
            }
            withLanguage(.ru) {
                #expect(HistoryPageModel.axisLabel(76, metric: .battery, decimals: 0) == "76 %")
                #expect(HistoryPageModel.axisLabel(1200, metric: .disk, decimals: 0) == "1\u{2009}200 ГБ")
            }
        }

        @Test func tooltipValues() {
            withLanguage(.en) {
                #expect(HistoryPageModel.tooltipValue(312, metric: .disk) == "312 GB")
                #expect(HistoryPageModel.tooltipValue(76, metric: .battery) == "76%")
                #expect(HistoryPageModel.tooltipValue(412, metric: .cycles) == "412 cycles")
                #expect(HistoryPageModel.tooltipValue(1, metric: .cycles) == "1 cycle")
                #expect(HistoryPageModel.tooltipValue(1.25, metric: .swap) == "1.25 GB")
            }
            withLanguage(.ru) {
                #expect(HistoryPageModel.tooltipValue(412, metric: .cycles) == "412 циклов")
                #expect(HistoryPageModel.tooltipValue(1, metric: .cycles) == "1 цикл")
                #expect(HistoryPageModel.tooltipValue(1.25, metric: .swap) == "1,25 ГБ")
            }
        }

        @Test func xTicks() {
            withLanguage(.en) {
                @MainActor func ticks(_ n: Int, _ r: HistoryRange, narrow: Bool = false, end: String = "2026-10-21") -> [HistoryXTick] {
                    let es = entries(n, end: end)
                    let w = HistoryPageModel.window(es, range: r, calendar: cal)!
                    return HistoryPageModel.xTicks(window: w, range: r, narrow: narrow, calendar: cal)
                }
                let m = ticks(400, .month)
                let weeks = m.filter { if case .weekLabel = $0 { return true } else { return false } }
                #expect(weeks.count == 4)
                #expect(weeks.map(\.date) == ["2026-09-26", "2026-10-03", "2026-10-10", "2026-10-17"].map(day))
                #expect(weeks.compactMap(\.label) == ["Sep 26", "Oct 3", "Oct 10", "Oct 17"])
                // 1M also draws a label-less line at the month start inside the window (Oct 1 at x ≈ 0.33)
                let mStarts = m.compactMap { t -> (Date, String?)? in
                    if case .monthStart(let d, let l) = t { return (d, l) } else { return nil }
                }
                #expect(mStarts.count == 1 && mStarts[0].0 == day("2026-10-01") && mStarts[0].1 == nil)
                // window ending on Oct 1: Oct 1 is at the edge (x = 1), Sep 1 lies before the window
                let m2 = ticks(400, .month, end: "2026-10-01")
                #expect(!m2.contains { if case .monthStart = $0 { return true } else { return false } })

                let q = ticks(400, .quarter)
                #expect(q.map(\.date) == ["2026-08-01", "2026-09-01", "2026-10-01"].map(day))
                #expect(q.compactMap(\.label) == ["Aug", "Sep", "Oct"])
                #expect(q.allSatisfy { if case .monthStart = $0 { return true } else { return false } })

                for narrow in [false, true] {
                    let y = ticks(400, .year, narrow: narrow)
                    #expect(y.count == 12)
                    #expect(y.map(\.label) == [nil, "Dec", nil, "Feb", nil, "Apr", nil, "Jun", nil, "Aug", nil, "Oct"])
                    // January (index 2) keeps its line but loses its label to the thinning
                    if case .monthStart(let d, let l) = y[2] { #expect(d == day("2026-01-01") && l == nil) } else { Issue.record("not a monthStart") }
                }

                // a 9-month window keeps every label (9 ≤ 10) and January reads as the year
                let nine = ticks(300, .all, end: "2026-10-21")      // 2025-12-26 … 2026-10-21 → 10 month starts
                #expect(nine.compactMap(\.label).contains("2026") && nine.count == 10 && nine.allSatisfy { $0.label != nil })
                #expect(ticks(300, .all, narrow: true).filter { $0.label != nil }.count == 5)   // 10 > 7 → every second label

                // edge rule: month starts within 1.5 % of either end are dropped
                #expect(ticks(90, .quarter, end: "2026-10-28").map(\.date) == ["2026-09-01", "2026-10-01"].map(day))
                #expect(ticks(90, .quarter, end: "2026-10-26").map(\.date) == ["2026-08-01", "2026-09-01", "2026-10-01"].map(day))
            }
        }

        @Test func dates() {
            let now = day("2026-10-21")
            withLanguage(.en) {
                #expect(HistoryPageModel.shortDate(day("2026-10-14"), now: now, calendar: cal) == "Oct 14")
                #expect(HistoryPageModel.shortDate(day("2025-09-02"), now: now, calendar: cal) == "Sep 2, 2025")
                #expect(HistoryPageModel.tooltipDate(day("2026-10-17"), calendar: cal) == "Sat, Oct 17, 2026")
                #expect(L.historyMonthLabel(6) == "Jun")
            }
            withLanguage(.ru) {
                #expect(HistoryPageModel.shortDate(day("2026-10-14"), now: now, calendar: cal) == "14 окт.")
                #expect(HistoryPageModel.shortDate(day("2025-09-02"), now: now, calendar: cal) == "2 сент. 2025")
                #expect(HistoryPageModel.shortDate(day("2026-05-03"), now: now, calendar: cal) == "3 мая")
                #expect(HistoryPageModel.tooltipDate(day("2026-10-17"), calendar: cal) == "сб, 17 окт. 2026")
                #expect(L.historyMonthLabel(6) == "июнь")
            }
        }

        @Test func tableRows() {
            withLanguage(.en) {
                let now = day("2026-10-21")
                let es = entries(12) { i, e in if i == 5 { e.disk_used_gb = nil }; if i == 11 { e.swap = "1280MB/2048MB" } }
                let t = HistoryPageModel.table(es, window: nil, narrow: false, showAll: false, now: now, calendar: cal)
                #expect(t.rows.count == 10 && t.hasMore && t.moreLabel == "Show all (12)")
                #expect(t.rows[0][0] == "Oct 21")                       // newest first
                #expect(t.rows[0][5] == "1.25 / 2 GB" && t.rows[0][6] == "26.1 (25B78)")
                #expect(t.rows[0][1] == "300 GB" && t.rows[0][2] == "200 GB" && t.rows[0][3] == "90%" && t.rows[0][4] == "100")
                #expect(t.headers == ["Date", "Disk used", "Free", "Battery", "Cycles", "Swap", "macOS"] && t.batteryColumn == 3)
                #expect(t.rows[6][1] == nil)                            // entry 5 of 12 is row 11 − 5 = 6
                let all = HistoryPageModel.table(es, window: nil, narrow: false, showAll: true, now: now, calendar: cal)
                #expect(all.rows.count == 12 && all.moreLabel == "Show less")

                let narrow = HistoryPageModel.table(es, window: nil, narrow: true, showAll: false, now: now, calendar: cal)
                #expect(narrow.headers == ["Date", "Disk used", "Battery", "Cycles", "Swap"] && narrow.batteryColumn == 2)
                #expect(narrow.rows[0].count == 5)

                let w = HistoryPageModel.window(es, range: .month, calendar: cal)
                let long = entries(60)
                let cut = HistoryPageModel.table(long, window: HistoryPageModel.window(long, range: .month, calendar: cal),
                                                 narrow: false, showAll: true, now: now, calendar: cal)
                #expect(cut.rows.count == 30 && w != nil)

                let old = HistoryPageModel.table([entry("2025-09-02")], window: nil, narrow: false, showAll: false, now: now, calendar: cal)
                #expect(old.rows[0][0] == "Sep 2, 2025")
                let noSwap = HistoryPageModel.table([entry("2026-10-01", swap: "garbage")], window: nil, narrow: false, showAll: false, now: now, calendar: cal)
                #expect(noSwap.rows[0][5] == nil)
            }
        }

        @Test func bar() {
            let now = day("2026-10-21")
            func bar(_ e: [MacHistoryEntry], unreadable: Bool = false, refreshing: Bool = false) -> HistoryPageModel.Bar {
                HistoryPageModel.bar(entries: e, unreadable: unreadable, refreshing: refreshing, now: now, calendar: cal)
            }
            withLanguage(.en) {
                let e500 = entries(500)          // first day 2025-06-09
                let b = bar(e500)
                #expect(b.sub == "500 daily samples · mac_check_state.json" && b.tone == .neutral)
                #expect(b.tag == "since Jun 9, 2025")
                #expect(bar(entries(30)).tag == "since Sep 22")
                #expect(bar([entry("2026-10-21")]).sub == "1 daily sample · mac_check_state.json")
                #expect(bar([]).tag.isEmpty && bar([]).sub == "0 daily samples · mac_check_state.json")
                let u = bar(e500, unreadable: true)
                #expect(u.sub == "mac_check_state.json" && u.tone == .hot && u.tag == "file unreadable")
                let r = bar(e500, unreadable: true, refreshing: true)
                #expect(r.tone == .accent && r.tag == "reading…")
                #expect(bar(e500, refreshing: true).tone == .neutral)       // refreshing alone changes nothing in the bar
            }
            withLanguage(.ru) {
                #expect(bar(entries(500)).sub == "500 ежедневных замеров · mac_check_state.json")
                #expect(bar([entry("2026-10-21")]).sub == "1 ежедневный замер · mac_check_state.json")
                #expect(bar(entries(2)).sub == "2 ежедневных замера · mac_check_state.json")
                #expect(bar([entry("2025-09-02"), entry("2026-10-21")]).tag == "с 2 сентября 2025")
            }
        }

        @Test func titlesAndCaptions() {
            withLanguage(.en) {
                let e = entries(500)
                #expect(make(input(e, metric: .disk)).title == "Disk: used")
                #expect(make(input(e, metric: .battery)).title == "Battery: maximum capacity")
                #expect(make(input(e, metric: .cycles)).title == "Battery: charge cycles")
                #expect(make(input(e, metric: .swap)).title == "Swap: used")
                let t = make(input(e, view: .table))
                #expect(t.title == "All metrics" && !t.showsMetricControl && t.showsRangeRow)
                #expect(make(input(e)).showsMetricControl)
                #expect(make(input(e, range: .month)).caption == "30 days")
                #expect(make(input(e, range: .quarter)).caption == "90 days")
                #expect(make(input(e, range: .year)).caption == "365 days")
                #expect(make(input(e, range: .all)).caption == "500 days")
                // error / wait states
                #expect(make(input(e, unreadable: true)).block == .error(path: "~/x/mac_check_state.json"))
                #expect(make(input(e, unreadable: true)).showsRangeRow == false)
                #expect(make(input(e, unreadable: true, refreshing: true)).block == .wait)
            }
            withLanguage(.ru) {
                #expect(make(input(entries(500), range: .month)).caption == "30 дней")
                #expect(make(input(entries(91), range: .all)).caption == "91 день")
                #expect(make(input(entries(2), range: .all)).caption == "2 дня")
            }
        }

        @Test func metricWithoutData() {
            withLanguage(.en) {
                let e = entries(30) { _, e in e.battery_pct = nil }
                let m = make(input(e, metric: .battery))
                #expect(m.block == .empty(title: "Not enough data yet", sub: "0 samples · the chart needs at least 2"))
                #expect(m.enabledRanges == [.month, .all] && m.caption == "30 days")
            }
        }

        // MARK: CHART-RANGE-START

        /// The user's case on 2026-10-30: samples on Sep 30 and Oct 3, none between, so 1M starts on Oct 3.
        @Test func sinceGapCrossesWindowStart() {
            let gone: Set<String> = ["2026-10-01", "2026-10-02", "2026-10-04"]
            let e = entries(60, end: "2026-10-30").filter { !gone.contains($0.date) }
            withLanguage(.en) {
                let m = make(input(e, range: .month))
                #expect(m.enabledRanges.contains(.month))
                #expect(m.sinceNote == "since Oct 3" && m.caption == "28 days")
                #expect(chart(m)?.xDomain == (day("2026-10-03")...day("2026-10-30")))
                #expect(chart(m)?.points.first?.id == "2026-10-03")
                #expect(chart(m)?.ticks.compactMap(\.label) == ["Oct 5", "Oct 12", "Oct 19", "Oct 26"])
            }
            withLanguage(.ru) {
                let m = make(input(e, range: .month))
                #expect(m.sinceNote == "с 3 октября" && m.caption == "28 дней")
            }
        }

        /// Swap has values only for the last 40 of 120 days; the other metrics of the same entries are unaffected.
        @Test func sinceMetricStartsLater() {
            withLanguage(.en) {
                let e = entries(120) { i, e in if i < 80 { e.swap = nil } }
                let q = make(input(e, metric: .swap, range: .quarter))
                #expect(q.sinceNote == "since Sep 12" && q.caption == "40 days")
                #expect(chart(q)?.xDomain == (day("2026-09-12")...day("2026-10-21")))
                #expect(chart(q)?.ticks.compactMap(\.label) == ["Sep 19", "Sep 26", "Oct 3", "Oct 10", "Oct 17"])
                #expect(q.enabledRanges == [.month, .quarter, .all])
                let all = make(input(e, metric: .swap, range: .all))
                #expect(all.sinceNote == "since Sep 12" && chart(all)?.xDomain == chart(q)?.xDomain)
                #expect(make(input(e, metric: .swap, range: .month)).sinceNote == nil)
                let disk = make(input(e, metric: .disk, range: .quarter))
                #expect(disk.sinceNote == nil && disk.caption == "90 days")
                #expect(chart(disk)?.xDomain == HistoryPageModel.window(e, range: .quarter, calendar: cal))
                let diskAll = make(input(e, metric: .disk, range: .all))
                #expect(diskAll.sinceNote == nil && diskAll.caption == "120 days")
            }
        }

        /// History exactly as long as the range, and longer: domain, ticks and caption as before, no note.
        @Test func sinceNoNoteWhenRangeIsCovered() {
            withLanguage(.en) {
                let exact = make(input(entries(30), range: .month))
                #expect(exact.sinceNote == nil && exact.caption == "30 days")
                let e = entries(500)
                for r in HistoryRange.allCases {
                    let m = make(input(e, range: r))
                    let w = HistoryPageModel.window(e, range: r, calendar: cal)!
                    #expect(m.sinceNote == nil)
                    #expect(chart(m)?.xDomain == w)
                    #expect(chart(m)?.ticks == HistoryPageModel.xTicks(window: w, range: r, narrow: false, calendar: cal))
                }
            }
        }

        /// A gap inside the window keeps the full axis; the line bridges it.
        @Test func sinceGapInsideWindowHasNoNote() {
            withLanguage(.en) {
                let gone: Set<String> = ["2026-10-10", "2026-10-11"]
                let m = make(input(entries(60).filter { !gone.contains($0.date) }, range: .month))
                #expect(m.sinceNote == nil && m.caption == "30 days")
                #expect(chart(m)?.xDomain == (day("2026-09-22")...day("2026-10-21")))
                #expect(chart(m)?.points.count == 28)
            }
        }

        /// One or no sample in the window: the empty panel, nominal caption, no note. Two samples: a chart.
        @Test func sinceFewSamples() {
            withLanguage(.en) {
                let one = make(input(entries(60) { i, e in if i < 59 { e.disk_used_gb = nil } }, range: .month))
                #expect(one.block == .empty(title: "Not enough data yet", sub: "1 sample · the chart needs at least 2"))
                #expect(one.sinceNote == nil && one.caption == "30 days")
                let none = make(input(entries(60) { _, e in e.battery_pct = nil }, metric: .battery, range: .month))
                #expect(none.sinceNote == nil && none.caption == "30 days")
                let two = make(input(entries(60) { i, e in if i < 58 { e.disk_used_gb = nil } }, range: .month))
                #expect(two.sinceNote == "since Oct 20" && two.caption == "2 days")
                #expect(chart(two)?.xDomain == (day("2026-10-20")...day("2026-10-21")))
                #expect(chart(two)?.ticks.isEmpty == true)
            }
        }

        /// Table view keeps the nominal window and caption, and has no note.
        @Test func sinceTableUnaffected() {
            withLanguage(.en) {
                let gone: Set<String> = ["2026-10-01", "2026-10-02", "2026-10-04"]
                let e = entries(60, end: "2026-10-30").filter { !gone.contains($0.date) }
                let m = make(input(e, range: .month, view: .table, showAll: true))
                #expect(m.sinceNote == nil && m.caption == "30 days" && m.deltaCaption == nil)
                if case .table(let t) = m.block { #expect(t.rows.count == 27) } else { Issue.record("not a table") }
            }
        }

        /// Ticks by plotted length; Swap only on the last `keep` of 120 days, 3M. End day 2026-10-21.
        @Test func sinceTicksByWindowLength() {
            withLanguage(.en) {
                @MainActor func data(_ keep: Int) -> HistoryChartData? {
                    let e = entries(120) { i, e in if i < 120 - keep { e.swap = nil } }
                    return chart(make(input(e, metric: .swap, range: .quarter)))
                }
                @MainActor func labels(_ keep: Int) -> [String] { data(keep)?.ticks.compactMap(\.label) ?? [] }
                #expect(labels(2) == [])
                #expect(labels(3) == ["Oct 20"])
                #expect(labels(4) == ["Oct 20"])
                #expect(labels(5) == ["Oct 19"])
                #expect(labels(6) == ["Oct 17"])
                #expect(labels(20) == ["Oct 3", "Oct 10", "Oct 17"])
                #expect(labels(27) == ["Oct 3", "Oct 10", "Oct 17"])        // Sep 26 is under 4 % from the left edge
                #expect(labels(28) == ["Sep 26", "Oct 3", "Oct 10", "Oct 17"])
                #expect(labels(46) == ["Oct"])                              // over 45 days: month style
                for keep in [2, 3, 4, 5, 6, 20, 27, 28, 40, 45, 46, 60] {
                    guard let d = data(keep) else { Issue.record("no chart for \(keep)"); continue }
                    #expect(d.ticks.allSatisfy { d.xDomain.contains($0.date) })
                }
            }
        }

        /// Shortened slightly on 3M: month labels stay.
        @Test func sinceQuarterKeepsMonthLabels() {
            withLanguage(.en) {
                let m = make(input(entries(120).filter { $0.date != "2026-07-24" }, range: .quarter))
                #expect(m.sinceNote == "since Jul 25" && m.caption == "89 days")
                #expect(chart(m)?.ticks.compactMap(\.label) == ["Aug", "Sep", "Oct"])
            }
        }

        /// The year appears only when it is not `now`'s year (2026 in `input`).
        @Test func sinceShowsOtherYear() {
            let gone: Set<String> = ["2025-10-22", "2025-10-23", "2025-10-24"]
            let e = entries(500).filter { !gone.contains($0.date) }
            withLanguage(.en) {
                let m = make(input(e, range: .year))
                #expect(m.sinceNote == "since Oct 25, 2025" && m.caption == "362 days")
            }
            withLanguage(.ru) { #expect(make(input(e, range: .year)).sinceNote == "с 25 октября 2025") }
        }

        /// The delta is still first to last sample by date.
        @Test func sinceDeltaUnchanged() {
            withLanguage(.en) {
                let gone: Set<String> = ["2026-10-01", "2026-10-02"]
                let e = entries(60, end: "2026-10-30") { i, e in e.disk_used_gb = 100 + i }.filter { !gone.contains($0.date) }
                #expect(make(input(e, range: .month)).deltaCaption == "+30 GB per month")
            }
        }

        @Test func sinceA11y() {
            withLanguage(.en) { #expect(L.historyChartSinceA11y("since Oct 3") == "Chart shows data since Oct 3") }
            withLanguage(.ru) { #expect(L.historyChartSinceA11y("с 3 октября") == "На графике данные с 3 октября") }
        }

        /// `visual-fixture-coverage`: the fixture shows the note on Swap 3M, and only where intended.
        @Test func sinceInVisualFixture() {
            withLanguage(.en) {
                let e = VisualFixture.make().history.mac_history
                let q = make(input(e, metric: .swap, range: .quarter))
                #expect(q.sinceNote == "since Nov 17, 2025" && q.caption == "60 days")
                #expect(make(input(e, metric: .swap, range: .month)).sinceNote == nil)
                #expect(make(input(e, metric: .disk, range: .quarter)).sinceNote == nil)
            }
        }
    }
}
