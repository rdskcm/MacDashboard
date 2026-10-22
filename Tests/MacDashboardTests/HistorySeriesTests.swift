// Tests/MacDashboardTests/HistorySeriesTests.swift
// Port of Checks/HistorySeriesChecks.swift (CHECKS-SWIFT-TESTING).
// Block H: pure-logic checks for HistorySeries (metric series extraction, swap
// string parsing/formatting). Real file (not a symlink) — main.swift owns the
// single top-level-statements slot, so this exposes a plain function it calls
// (see README.md). HISTORY-RANGE: range windows + chart point cap.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct HistorySeriesTests {
        @Test func historySeries() async {
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
            #expect(disk.count == 2, "series(.disk): 2 non-nil entries")
            #expect(disk.map(\.date) == ["2026-07-01", "2026-07-03"], "series(.disk): order preserved, nil entry skipped")
            #expect(disk.map(\.value) == [100.0, 105.0], "series(.disk): correct values")

            let battery = HistorySeries.series(fixture, metric: .battery)
            #expect(battery.count == 2, "series(.battery): 2 non-nil entries")
            #expect(battery.map(\.date) == ["2026-07-01", "2026-07-02"], "series(.battery): order preserved, nil entry skipped")
            #expect(battery.map(\.value) == [92.0, 91.0], "series(.battery): correct values")

            let cycles = HistorySeries.series(fixture, metric: .cycles)
            #expect(cycles.count == 2, "series(.cycles): 2 non-nil entries")
            #expect(cycles.map(\.date) == ["2026-07-01", "2026-07-03"], "series(.cycles): order preserved, nil entry skipped")
            #expect(cycles.map(\.value) == [120.0, 121.0], "series(.cycles): correct values")

            let swap = HistorySeries.series(fixture, metric: .swap)
            #expect(swap.count == 2, "series(.swap): 2 parseable entries")
            #expect(swap.map(\.date) == ["2026-07-01", "2026-07-03"], "series(.swap): order preserved, unparseable entry skipped")
            #expect(swap[0].value == 0.5, "series(.swap): 512MB used ⇒ 0.5 GB")
            #expect(swap[1].value == 1.0, "series(.swap): 1024MB used ⇒ 1.0 GB")

            // MARK: empty entries array

            for m in HistoryMetric.allCases {
                #expect(HistorySeries.series([], metric: m).isEmpty, "series([], .\(m)): empty, no crash")
            }

            // MARK: parseSwapUsedBytes

            let ok512 = HistorySeries.parseSwapUsedBytes("512MB/2048MB") == 512 * 1_048_576   // hoisted: #expect mis-evaluates Int64? == literal product (P6)
            #expect(ok512, "parseSwapUsedBytes: \"512MB/2048MB\" ⇒ correct byte count")
            #expect(HistorySeries.parseSwapUsedBytes(nil) == nil, "parseSwapUsedBytes: nil ⇒ nil")
            #expect(HistorySeries.parseSwapUsedBytes("") == nil, "parseSwapUsedBytes: empty string ⇒ nil")
            #expect(HistorySeries.parseSwapUsedBytes("512MB") == nil, "parseSwapUsedBytes: no \"/\" ⇒ nil")
            #expect(HistorySeries.parseSwapUsedBytes("512KB/2048MB") == nil, "parseSwapUsedBytes: non-MB suffix ⇒ nil")
            #expect(HistorySeries.parseSwapUsedBytes("abcMB/2048MB") == nil, "parseSwapUsedBytes: non-numeric ⇒ nil")

            // MARK: formattedSwap

            L10nStore.shared.language = .en
            #expect(HistorySeries.formattedSwap("512MB/2048MB") == "0.50 / 2 GB", "formattedSwap: valid string ⇒ \"used 2 dec / total 0 dec GB\"")
            #expect(HistorySeries.formattedSwap("1280MB/3072MB") == "1.25 / 3 GB", "formattedSwap: 1.25 / 3 GB")
            #expect(HistorySeries.formattedSwap(nil) == nil, "formattedSwap: nil ⇒ nil")
            #expect(HistorySeries.formattedSwap("garbage") == nil, "formattedSwap: unparseable ⇒ nil")

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

            // Each bounded range spans exactly `days` calendar days ending on the last
            // entry's date (calendar-day arithmetic, gaps in the data do not matter).
            let windows: [(HistoryRange, Int)] = [(.month, 30), (.quarter, 90), (.year, 365)]
            for (range, days) in windows {
                for (name, entries) in [("≥30 entries, no gaps", thirtyDays), ("<30 entries", fixture), ("gap in dates", gapFixture)] {
                    if let window = HistorySeries.dateRange(entries, range) {
                        let lastDate = dayFmt.date(from: entries.last!.date)!
                        let expectedStart = Calendar.current.date(byAdding: .day, value: -(days - 1), to: lastDate)!
                        #expect(window.upperBound == lastDate, "dateRange(.\(range)): \(name) ⇒ end == last entry date")
                        #expect(window.lowerBound == expectedStart, "dateRange(.\(range)): \(name) ⇒ start == last date − \(days - 1) days")
                    } else {
                        Issue.record("dateRange(.\(range)): \(name) ⇒ non-nil")
                    }
                }
            }
            #expect(HistorySeries.dateRange(thirtyDays, .all) == nil, "dateRange(.all): no window ⇒ nil")
            for r in HistoryRange.allCases {
                #expect(HistorySeries.dateRange([], r) == nil, "dateRange([], .\(r)): empty entries ⇒ nil")
            }
            #expect(HistorySeries.dateRange([makeEntry("not-a-date")], .month) == nil,
                  "dateRange: unparseable last date ⇒ nil")
            let spans = HistoryRange.allCases.map { $0.days ?? Int.max }
            #expect(zip(spans, spans.dropFirst()).allSatisfy { $0 < $1 },
                  "HistoryRange: segments run shortest → longest window, Всё (no window) last")

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
                #expect(inWindow == expected, "dateRange(.\(range)): 400-day run ⇒ \(expected) entries in window, got \(inWindow)")
            }

            // MARK: thinned / maxChartPoints

            #expect(HistorySeries.maxChartPoints >= 365, "maxChartPoints ≥ a full Год window, so only Всё is ever thinned")
            let big = Array(0..<1000)
            let thin = HistorySeries.thinned(big, maxCount: 365)
            #expect(thin.count == 365, "thinned: 1000 → exactly maxCount")
            #expect(thin.first == 0 && thin.last == 999, "thinned: first and last kept")
            #expect(zip(thin, thin.dropFirst()).allSatisfy { $0 < $1 }, "thinned: strictly increasing — order kept, no duplicates")
            #expect(HistorySeries.thinned(Array(0..<365), maxCount: 365) == Array(0..<365), "thinned: count == maxCount ⇒ unchanged")
            let justOver = HistorySeries.thinned(Array(0..<366), maxCount: 365)
            #expect(justOver.count == 365 && justOver.first == 0 && justOver.last == 365
                  && zip(justOver, justOver.dropFirst()).allSatisfy { $0 < $1 },
                  "thinned: maxCount + 1 ⇒ maxCount, ends kept, no duplicates")
            #expect(HistorySeries.thinned([Int](), maxCount: 365).isEmpty, "thinned: empty ⇒ empty")
            #expect(HistorySeries.thinned([1, 2, 3], maxCount: 1) == [1, 2, 3], "thinned: maxCount < 2 ⇒ unchanged")
        }
    }
}
