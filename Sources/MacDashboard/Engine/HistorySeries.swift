// Engine/HistorySeries.swift
// Block H: pure series extraction for the История chart's metric picker
// (Диск / Батарея / Циклы / Swap). Also the single source of truth for
// swap-string parsing, shared by the chart series path and HistoryCard's
// table formatting — no duplicated parsing logic between the two.
//
// Pure Foundation-only, no SwiftUI/Charts import, so it's symlinked into
// MacDashboardChecks unchanged.

import Foundation

enum HistoryMetric: CaseIterable {
    case disk, battery, cycles, swap
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

    /// 30-consecutive-calendar-day range ending on the last entry's date.
    /// Entries are already chronological — `entries.last` is the most recent.
    /// nil if `entries` is empty or the last entry's date string fails to parse.
    static func last30Range(_ entries: [MacHistoryEntry]) -> ClosedRange<Date>? {
        guard let last = entries.last,
              let endDate = dayFormatter.date(from: last.date)
        else { return nil }
        guard let startDate = Calendar.current.date(byAdding: .day, value: -29, to: endDate)
        else { return nil }
        return startDate...endDate
    }
}
