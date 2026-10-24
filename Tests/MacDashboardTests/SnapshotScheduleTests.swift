// Tests/MacDashboardTests/SnapshotScheduleTests.swift
// REDESIGN-SETTINGS R10: pure schedule rule.
import Foundation
import Testing
@testable import MacDashboard

struct SnapshotScheduleTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }()
    private func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    private func due(now: Date, last: Date?, minutes: Int = 180) -> Bool {
        SnapshotSchedule.isDue(now: now, last: last, minutesAfterMidnight: minutes, calendar: Self.cal)
    }

    @Test func neverSnapshotted() { #expect(due(now: at(20, 9, 0), last: nil)) }
    @Test func justAfterTime() { #expect(due(now: at(20, 3, 5), last: at(19, 3, 10))) }
    @Test func beforeTime() { #expect(!due(now: at(20, 2, 50), last: at(19, 3, 10))) }
    @Test func alreadyTakenToday() { #expect(!due(now: at(20, 9, 0), last: at(20, 3, 30))) }
    @Test func takenBeforeTodaysTime() { #expect(due(now: at(20, 9, 0), last: at(20, 2, 59))) }
    @Test func asleepOverTime() { #expect(due(now: at(20, 9, 0), last: at(19, 4, 0))) }
    @Test func edgeMinutes() {
        #expect(due(now: at(20, 23, 59), last: at(19, 23, 0), minutes: 1439))
        #expect(!due(now: at(20, 23, 59), last: at(20, 23, 59), minutes: 1439))
        #expect(due(now: at(20, 0, 5), last: at(19, 12, 0), minutes: 0))
        #expect(!due(now: at(20, 0, 5), last: at(20, 0, 1), minutes: 0))
    }
    @Test func outOfRangeClamps() {
        _ = due(now: at(20, 9, 0), last: at(19, 9, 0), minutes: -5)
        _ = due(now: at(20, 9, 0), last: at(19, 9, 0), minutes: 5000)
    }
}
