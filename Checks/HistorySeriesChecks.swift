// Checks/HistorySeriesChecks.swift
// Block H: pure-logic checks for HistorySeries (metric series extraction, swap
// string parsing/formatting). Real file (not a symlink) — main.swift owns the
// single top-level-statements slot, so this exposes a plain function it calls
// (see README.md). HISTORY-RANGE: range windows + chart point cap.

import Foundation

func runHistorySeriesChecks() {
    let fixture: [MacHistoryEntry] = [
        MacHistoryEntry(date: "2026-07-01", disk_used_gb: 100, disk_free_gb: 50,
                         battery_pct: 92, cycles: 120, swap: "512MB/2048MB", macos: "14.5"),
        MacHistoryEntry(date: "2026-07-02", disk_used_gb: nil, disk_free_gb: 60,
                         battery_pct: 91, cycles: nil, swap: nil, macos: "14.5"),
        MacHistoryEntry(date: "2026-07-03", disk_used_gb: 105, disk_free_gb: 45,
                         battery_pct: nil, cycles: 121, swap: "1024MB/2048MB", macos: "14.5"),
    ]

    // MARK: series() per metric

    let disk = HistorySeries.series(fixture, metric: .disk)
    check(disk.count == 2, "series(.disk): 2 non-nil entries")
    check(disk.map(\.date) == ["2026-07-01", "2026-07-03"], "series(.disk): order preserved, nil entry skipped")
    check(disk.map(\.value) == [100.0, 105.0], "series(.disk): correct values")

    let battery = HistorySeries.series(fixture, metric: .battery)
    check(battery.count == 2, "series(.battery): 2 non-nil entries")
    check(battery.map(\.date) == ["2026-07-01", "2026-07-02"], "series(.battery): order preserved, nil entry skipped")
    check(battery.map(\.value) == [92.0, 91.0], "series(.battery): correct values")

    let cycles = HistorySeries.series(fixture, metric: .cycles)
    check(cycles.count == 2, "series(.cycles): 2 non-nil entries")
    check(cycles.map(\.date) == ["2026-07-01", "2026-07-03"], "series(.cycles): order preserved, nil entry skipped")
    check(cycles.map(\.value) == [120.0, 121.0], "series(.cycles): correct values")

    let swap = HistorySeries.series(fixture, metric: .swap)
    check(swap.count == 2, "series(.swap): 2 parseable entries")
    check(swap.map(\.date) == ["2026-07-01", "2026-07-03"], "series(.swap): order preserved, unparseable entry skipped")
    check(swap[0].value == 0.5, "series(.swap): 512MB used ⇒ 0.5 GB")
    check(swap[1].value == 1.0, "series(.swap): 1024MB used ⇒ 1.0 GB")

    // MARK: empty entries array

    for m in HistoryMetric.allCases {
        check(HistorySeries.series([], metric: m).isEmpty, "series([], .\(m)): empty, no crash")
    }

    // MARK: parseSwapUsedBytes

    check(HistorySeries.parseSwapUsedBytes("512MB/2048MB") == 512 * 1_048_576,
          "parseSwapUsedBytes: \"512MB/2048MB\" ⇒ correct byte count")
    check(HistorySeries.parseSwapUsedBytes(nil) == nil, "parseSwapUsedBytes: nil ⇒ nil")
    check(HistorySeries.parseSwapUsedBytes("") == nil, "parseSwapUsedBytes: empty string ⇒ nil")
    check(HistorySeries.parseSwapUsedBytes("512MB") == nil, "parseSwapUsedBytes: no \"/\" ⇒ nil")
    check(HistorySeries.parseSwapUsedBytes("512KB/2048MB") == nil, "parseSwapUsedBytes: non-MB suffix ⇒ nil")
    check(HistorySeries.parseSwapUsedBytes("abcMB/2048MB") == nil, "parseSwapUsedBytes: non-numeric ⇒ nil")

    // MARK: formattedSwap

    check(HistorySeries.formattedSwap("512MB/2048MB") == "\(fmtBytes(Int64(512) * 1_048_576)) / \(fmtBytes(Int64(2048) * 1_048_576))",
          "formattedSwap: valid string ⇒ \"X / Y\" via shared fmtBytes")
    check(HistorySeries.formattedSwap(nil) == "—", "formattedSwap: nil ⇒ em dash")
    check(HistorySeries.formattedSwap("garbage") == "—", "formattedSwap: unparseable ⇒ em dash")

    // MARK: dateRange (HistoryRange windows)

    let dayFmt: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    func makeEntry(_ date: String) -> MacHistoryEntry {
        MacHistoryEntry(date: date, disk_used_gb: 1, disk_free_gb: 1,
                         battery_pct: 1, cycles: 1, swap: nil, macos: "14.5")
    }

    // Normal case: ≥30 entries, no gaps.
    var thirtyDays: [MacHistoryEntry] = []
    var cursor = dayFmt.date(from: "2026-06-01")!
    for _ in 0..<32 {
        thirtyDays.append(makeEntry(dayFmt.string(from: cursor)))
        cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor)!
    }

    // Gap in dates ⇒ range still spans exactly N calendar days ending on last entry's date.
    let gapFixture: [MacHistoryEntry] = [
        makeEntry("2026-07-01"),
        makeEntry("2026-07-03"),   // gap: 07-02 skipped
        makeEntry("2026-07-10"),
    ]

    // .month reproduces the former last30Range exactly; .quarter/.year use the
    // same calendar-day arithmetic. Anchor is always the last entry's date.
    let windows: [(HistoryRange, Int)] = [(.month, 30), (.quarter, 90), (.year, 365)]
    for (range, days) in windows {
        for (name, entries) in [("≥30 entries, no gaps", thirtyDays), ("<30 entries", fixture), ("gap in dates", gapFixture)] {
            if let window = HistorySeries.dateRange(entries, range) {
                let lastDate = dayFmt.date(from: entries.last!.date)!
                let expectedStart = Calendar.current.date(byAdding: .day, value: -(days - 1), to: lastDate)!
                check(window.upperBound == lastDate, "dateRange(.\(range)): \(name) ⇒ end == last entry date")
                check(window.lowerBound == expectedStart, "dateRange(.\(range)): \(name) ⇒ start == last date − \(days - 1) days")
            } else {
                check(false, "dateRange(.\(range)): \(name) ⇒ non-nil")
            }
        }
    }
    check(HistorySeries.dateRange(thirtyDays, .all) == nil, "dateRange(.all): no window ⇒ nil")
    for r in HistoryRange.allCases {
        check(HistorySeries.dateRange([], r) == nil, "dateRange([], .\(r)): empty entries ⇒ nil")
    }
    check(HistorySeries.dateRange([makeEntry("not-a-date")], .month) == nil,
          "dateRange: unparseable last date ⇒ nil")
    check(HistoryRange.allCases == [.month, .quarter, .year, .all],
          "HistoryRange: case order == segment order Месяц · 3 мес · Год · Всё")

    // Window membership over a 400-day unbroken run: each window holds exactly
    // its day count, Всё holds everything.
    let runStart = dayFmt.date(from: "2025-01-01")!
    let longRun: [MacHistoryEntry] = (0..<400).map { i in
        makeEntry(dayFmt.string(from: Calendar.current.date(byAdding: .day, value: i, to: runStart)!))
    }
    let memberships: [(HistoryRange, Int)] = [(.month, 30), (.quarter, 90), (.year, 365), (.all, 400)]
    for (range, expected) in memberships {
        let inWindow = HistorySeries.dateRange(longRun, range).map { w in
            longRun.filter { w.contains(dayFmt.date(from: $0.date)!) }.count
        } ?? longRun.count
        check(inWindow == expected, "dateRange(.\(range)): 400-day run ⇒ \(expected) entries in window, got \(inWindow)")
    }

    // MARK: thinned / maxChartPoints

    check(HistorySeries.maxChartPoints >= 365, "maxChartPoints ≥ a full Год window, so only Всё is ever thinned")
    let big = Array(0..<1000)
    let thin = HistorySeries.thinned(big, maxCount: 365)
    check(thin.count == 365, "thinned: 1000 → exactly maxCount")
    check(thin.first == 0 && thin.last == 999, "thinned: first and last kept")
    check(zip(thin, thin.dropFirst()).allSatisfy { $0 < $1 }, "thinned: strictly increasing — order kept, no duplicates")
    check(HistorySeries.thinned(Array(0..<365), maxCount: 365) == Array(0..<365), "thinned: count == maxCount ⇒ unchanged")
    let justOver = HistorySeries.thinned(Array(0..<366), maxCount: 365)
    check(justOver.count == 365 && justOver.first == 0 && justOver.last == 365
          && zip(justOver, justOver.dropFirst()).allSatisfy { $0 < $1 },
          "thinned: maxCount + 1 ⇒ maxCount, ends kept, no duplicates")
    check(HistorySeries.thinned([Int](), maxCount: 365).isEmpty, "thinned: empty ⇒ empty")
    check(HistorySeries.thinned([1, 2, 3], maxCount: 1) == [1, 2, 3], "thinned: maxCount < 2 ⇒ unchanged")
}
