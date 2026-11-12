import Testing
import Foundation
@testable import Moonport

struct DiskReadScheduleTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func firstTickReads() {
        var s = DiskReadSchedule()
        let first = s.shouldRead(now: t0)
        #expect(first)
        #expect(s.lastReadAt == t0)
    }

    @Test func skipsInsideTheInterval() {
        var s = DiskReadSchedule()
        _ = s.shouldRead(now: t0)
        let at2 = s.shouldRead(now: t0.addingTimeInterval(2))
        let at29 = s.shouldRead(now: t0.addingTimeInterval(29.9))
        #expect(!at2 && !at29)
        #expect(s.lastReadAt == t0, "a skipped tick does not move the read time")
    }

    @Test func readsAtTheInterval() {
        var s = DiskReadSchedule()
        _ = s.shouldRead(now: t0)
        let t30 = t0.addingTimeInterval(30)
        let due = s.shouldRead(now: t30)
        #expect(due)
        #expect(s.lastReadAt == t30)
    }

    @Test func requestedReadComesAtAnyElapsedAndRestartsTheInterval() {
        var s = DiskReadSchedule()
        _ = s.shouldRead(now: t0)
        s.requestRead()
        let t5 = t0.addingTimeInterval(5)
        let forced = s.shouldRead(now: t5)
        let early = s.shouldRead(now: t5.addingTimeInterval(29))
        let due = s.shouldRead(now: t5.addingTimeInterval(30))
        #expect(forced)
        #expect(!early, "the interval counts from the forced read")
        #expect(due)
    }

    @Test func clockMovedBackwardsReads() {
        var s = DiskReadSchedule()
        _ = s.shouldRead(now: t0)
        let back = s.shouldRead(now: t0.addingTimeInterval(-60))
        #expect(back)
    }

    @Test func twoRequestsBeforeATickMakeOneRead() {
        var s = DiskReadSchedule()
        _ = s.shouldRead(now: t0)
        s.requestRead()
        s.requestRead()
        let t2 = t0.addingTimeInterval(2)
        let one = s.shouldRead(now: t2)
        let two = s.shouldRead(now: t2.addingTimeInterval(2))
        #expect(one)
        #expect(!two)
    }
}
