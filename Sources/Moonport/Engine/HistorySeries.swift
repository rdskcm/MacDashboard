// Engine/HistorySeries.swift
// Block H: pure series extraction for the History chart's metric picker
// (Disk / Battery / Cycles / Swap). Also the single source of truth for
// swap-string parsing, shared by the chart series path and
// HistoryPageModel.table — no duplicated parsing logic between the two.
// HISTORY-RANGE: also the chart's range window (HistoryRange) and point cap.
//
// Pure Foundation-only, no SwiftUI/Charts import, so it's covered by
// Tests/MoonportTests unchanged.

import Foundation

enum HistoryMetric: CaseIterable {
    case disk, battery, cycles, swap
}

/// The History chart's range switch (Month · 3 months · Year · All). Case order
/// IS the segment order. Pure — covered by Tests/MoonportTests.
enum HistoryRange: CaseIterable {
    case month, quarter, year, all

    /// Calendar days in the window, counting the end day; nil = no window (All).
    var days: Int? {
        switch self {
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}

/// A range switch whose segments are calendar-day windows ending on the newest sample. History (`HistoryRange`) and
/// the iPhone battery history (`IPhoneHistoryRange`) share the enable, fallback and tooltip rule (IPHONE-HISTORY-RANGE).
protocol DayWindowRange: CaseIterable, Hashable {
    /// Calendar days in the window, counting the newest sample's day; nil = no window (All).
    var days: Int? { get }
}

extension HistoryRange: DayWindowRange {}

enum DayWindowRule {
    /// Enabled iff there are >= 2 samples and (the range is All or the data covers at least `days` calendar days,
    /// first...last inclusive). History D21.
    static func enabled<R: DayWindowRange>(_: R.Type, sampleCount: Int, spanDays: Int) -> Set<R> {
        guard sampleCount >= 2 else { return [] }
        let covered = spanDays + 1
        return Set(R.allCases.filter { r in r.days.map { $0 <= covered } ?? true })
    }

    /// `selected` when enabled, else the last enabled range in `allCases` order (All whenever there are >= 2
    /// samples); nil when none is enabled.
    static func effective<R: DayWindowRange>(selected: R, enabled: Set<R>) -> R? {
        if enabled.contains(selected) { return selected }
        return Array(R.allCases).last { enabled.contains($0) }
    }

    /// Tooltip of the disabled segments; nil when every segment is enabled. < 2 samples: "Needs at least 2
    /// samples". Otherwise "Only N months of data" (covered days / 30.44, rounded), or "Only N days of data" while
    /// the data covers less than 30 days (IPHONE-HISTORY-RANGE D5: the month form read "0 months" there).
    @MainActor static func disabledHelp<R: DayWindowRange>(_ type: R.Type, sampleCount: Int, spanDays: Int) -> String? {
        if sampleCount < 2 { return L.historyNeedsTwo }
        guard enabled(type, sampleCount: sampleCount, spanDays: spanDays).count < R.allCases.count else { return nil }
        let covered = spanDays + 1
        if covered < 30 { return L.historyOnlyDays(covered) }
        return L.historyOnlyMonths(Int((Double(covered) / HistoryPageModel.daysPerMonth).rounded()))
    }
}

enum HistorySeries {

    /// One (date, value) point per entry that has a non-nil value for `metric`.
    /// Entries are already chronological — order is preserved, never re-sorted.
    static func series(_ entries: [MacHistoryEntry], metric: HistoryMetric) -> [(date: String, value: Double)] {
        switch metric {
        case .disk:
            return entries.compactMap { e in e.disk_used_gb.map { (e.date, Double($0)) } }
        case .battery:
            return entries.compactMap { e in e.battery_pct.map { (e.date, Double($0)) } }
        case .cycles:
            return entries.compactMap { e in e.cycles.map { (e.date, Double($0)) } }
        case .swap:
            return entries.compactMap { e in
                parseSwapUsedBytes(e.swap).map { (e.date, Double($0) / 1_073_741_824) }
            }
        }
    }

    /// Legacy `swap` field is a pre-formatted "usedMB/totalMB" string (see
    /// HistoryStore.upsertToday); returns the used byte count, or nil if the
    /// string doesn't parse.
    static func parseSwapUsedBytes(_ raw: String?) -> Int64? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              parts[0].hasSuffix("MB"), parts[1].hasSuffix("MB"),
              let usedMiB = Int(parts[0].dropLast(2))
        else { return nil }
        return Int64(usedMiB) * 1_048_576
    }

    /// Table cell «<used, 2 decimals> / <total, 0 decimals> GB» (10-history: «1.25 / 2 GB»); nil if the raw
    /// string is nil or unparseable — the table renders nil as «—».
    @MainActor static func formattedSwap(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              parts[0].hasSuffix("MB"), parts[1].hasSuffix("MB"),
              let usedMiB = Int(parts[0].dropLast(2)),
              let totalMiB = Int(parts[1].dropLast(2))
        else { return nil }
        let used = Double(usedMiB) / 1024
        let total = (Double(totalMiB) / 1024).rounded()
        return "\(fmtFixed(used, decimals: 2)) / \(fmtGrouped(Int(total))) \(L.byteUnitGB)"
    }

    /// Most points the chart plots. ≥ the most a Year window can hold (one entry
    /// per day, 365 days), so only All is ever thinned.
    static let maxChartPoints = 365

    /// Even-stride subsample to at most `maxCount` items, order preserved, first
    /// and last always kept, every item a real element of `items` (no averaging).
    /// Unchanged when `items.count <= maxCount`, or when `maxCount < 2` (not a
    /// meaningful cap). Strictly increasing indices: the stride is > 1 whenever
    /// thinning happens, so no element is picked twice.
    static func thinned<T>(_ items: [T], maxCount: Int) -> [T] {
        guard maxCount >= 2, items.count > maxCount else { return items }
        let step = Double(items.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { items[Int((Double($0) * step).rounded())] }
    }
}
