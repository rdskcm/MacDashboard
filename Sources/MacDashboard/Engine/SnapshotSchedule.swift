// Engine/SnapshotSchedule.swift
import Foundation

/// REDESIGN-SETTINGS: the daily History snapshot is written on the first report pass at or after the chosen
/// wall-clock time, once per occurrence; the Mac is never woken (user decision 2026-10-18 #2).
enum SnapshotSchedule {
    /// `true` when no snapshot has been taken since the most recent occurrence of `minutesAfterMidnight`
    /// (today's if it is already past, else yesterday's). `last == nil` → always due.
    static func isDue(now: Date, last: Date?, minutesAfterMidnight: Int, calendar: Calendar = .current) -> Bool {
        guard let last else { return true }
        let m = max(0, min(1439, minutesAfterMidnight))
        guard let todayAt = calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: now) else { return true }
        let occurrence = todayAt <= now ? todayAt : (calendar.date(byAdding: .day, value: -1, to: todayAt) ?? todayAt)
        return last < occurrence
    }
}
