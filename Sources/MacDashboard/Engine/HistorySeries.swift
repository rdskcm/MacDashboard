// Engine/HistorySeries.swift
// Block H: pure series extraction for the История chart's metric picker
// (Диск / Батарея / Циклы / Swap). Also the single source of truth for
// swap-string parsing, shared by the chart series path and HistoryCard's
// table formatting — no duplicated parsing logic between the two.
// HISTORY-RANGE: also the chart's range window (HistoryRange) and point cap.
//
// Pure Foundation-only, no SwiftUI/Charts import, so it's symlinked into
// MacDashboardChecks unchanged.

import Foundation

enum HistoryMetric: CaseIterable {
    case disk, battery, cycles, swap
}

/// The История chart's range switch (Месяц · 3 мес · Год · Всё). Case order
/// IS the segment order. Pure — symlinked into MacDashboardChecks.
enum HistoryRange: CaseIterable {
    case month, quarter, year, all

    /// Calendar days in the window, counting the end day; nil = no window (Всё).
    var days: Int? {
        switch self {
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
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

    /// Table-display formatting: reparses both used+total and reuses the shared
    /// `fmtBytes` formatter so the column matches the ГБ styling of the disk
    /// columns instead of showing raw "512MB/2048MB" text. "—" if unparseable/nil.
    static func formattedSwap(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              parts[0].hasSuffix("MB"), parts[1].hasSuffix("MB"),
              let usedMiB = Int(parts[0].dropLast(2)),
              let totalMiB = Int(parts[1].dropLast(2))
        else { return "—" }
        let usedBytes = Int64(usedMiB) * 1_048_576
        let totalBytes = Int64(totalMiB) * 1_048_576
        return "\(fmtBytes(usedBytes)) / \(fmtBytes(totalBytes))"
    }

    /// Same locale/timeZone/format as HistoryStore's `dayFormatter` and
    /// HistoryCard's `dateFormatter` — local timeZone, not UTC, so the range
    /// this returns lines up with how the view parses each point's date string
    /// (a UTC parse would disagree by up to a day for anyone west of UTC).
    private static var dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    /// `range.days` consecutive calendar days ending on the last entry's date
    /// (entries are chronological — `entries.last` is the most recent).
    /// nil for `.all` (no window: plot everything), for empty `entries`, or if
    /// the last entry's date string fails to parse.
    static func dateRange(_ entries: [MacHistoryEntry], _ range: HistoryRange) -> ClosedRange<Date>? {
        guard let days = range.days,
              let last = entries.last,
              let endDate = dayFormatter.date(from: last.date),
              let startDate = Calendar.current.date(byAdding: .day, value: -(days - 1), to: endDate)
        else { return nil }
        return startDate...endDate
    }

    /// Most points the chart plots. ≥ the most a Год window can hold (one entry
    /// per day, 365 days), so only Всё is ever thinned.
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
