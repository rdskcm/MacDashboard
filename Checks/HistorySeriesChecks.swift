// Checks/HistorySeriesChecks.swift
// Block H: pure-logic checks for HistorySeries (metric series extraction, swap
// string parsing/formatting). Real file (not a symlink) — main.swift owns the
// single top-level-statements slot, so this exposes a plain function it calls
// (see README.md).

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
}
