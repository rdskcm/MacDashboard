// Tests/MacDashboardTests/BlockStateTests.swift
// REDESIGN-FOUNDATION: per-block load state. Pure value logic, fixed dates, no process-wide state.
import Foundation
import Testing
@testable import MacDashboard

struct BlockStateTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func timeouts() {
        #expect(BlockID.cpu.timeout == 5, "BlockID.cpu.timeout == 5")
        #expect(BlockID.memory.timeout == 5, "BlockID.memory.timeout == 5")
        #expect(BlockID.battery.timeout == 5, "BlockID.battery.timeout == 5 (06-battery Reading timeout)")
        #expect(BlockID.scan.timeout == 30, "BlockID.scan.timeout == 30")
        #expect(BlockID.folders.timeout == 10, "folders timeout = 10 (the visible Counting wait; du keeps its 90 s deadline)")
        #expect(ReportCollector.folderSizesDeadline == 90, "folderSizesDeadline == 90 (tripwire: Storage copy must follow)")
    }

    @Test func initialIsLoading() {
        let s = BlockState(.cpu, createdAt: t0)
        #expect(s.phase == .loading(since: t0), "initial phase is loading(since: createdAt)")
        #expect(s.lastGoodAt == nil, "no last good yet")
        #expect(s.attemptStartedAt == nil, "no attempt in flight")
        #expect(s.deadline == nil, "no deadline without an attempt")
        #expect(s.timeout == 5, "cpu timeout 5")
    }

    @Test func backgroundAttemptSucceeds() {
        var s = BlockState(.cpu, createdAt: t0)
        s.begin(at: at(1), showsLoading: false)
        #expect(s.phase == .loading(since: t0), "background begin leaves the phase")
        #expect(s.deadline == at(6), "deadline = start + timeout")
        s.succeed(at: at(1.2))
        #expect(s.phase == .ok(at: at(1.2)), "succeed -> ok")
        #expect(s.lastGoodAt == at(1.2), "lastGoodAt set")
        #expect(s.attemptStartedAt == nil, "attempt closed")
    }

    @Test func backgroundAttemptKeepsOkPhase() {
        var s = BlockState(.cpu, createdAt: t0)
        s.succeed(at: at(1))
        s.begin(at: at(3), showsLoading: false)
        #expect(s.phase == .ok(at: at(1)), "background attempt keeps ok")
    }

    @Test func failureKeepsLastGood() {
        var s = BlockState(.cpu, createdAt: t0)
        s.succeed(at: at(1))
        s.begin(at: at(3), showsLoading: false)
        s.fail(.noReading)
        #expect(s.phase == .failed(.noReading, lastGoodAt: at(1)), "failed keeps lastGoodAt")
        s.begin(at: at(5), showsLoading: false)
        #expect(s.phase == .failed(.noReading, lastGoodAt: at(1)), "background attempt keeps failed")
        s.succeed(at: at(5.1))
        #expect(s.phase == .ok(at: at(5.1)), "late success recovers")
    }

    @Test func userAttemptShowsLoading() {
        var s = BlockState(.cpu, createdAt: t0)
        s.succeed(at: at(1))
        s.begin(at: at(10), showsLoading: true)
        #expect(s.phase == .loading(since: at(10)), "user attempt shows loading")
        #expect(s.lastGoodAt == at(1), "lastGoodAt kept")
    }

    @Test func watchdog() {
        var s = BlockState(.cpu, createdAt: t0)
        s.begin(at: t0, showsLoading: false)
        s.expire(now: at(4.9))
        #expect(s.phase == .loading(since: t0), "before deadline: unchanged")
        s.expire(now: at(5))
        #expect(s.phase == .failed(.timedOut, lastGoodAt: nil), "at deadline: timedOut")
        s.expire(now: at(9))
        #expect(s.phase == .failed(.timedOut, lastGoodAt: nil), "expire is idempotent")
        s.succeed(at: at(12))
        #expect(s.phase == .ok(at: at(12)), "late result lands as ok")
        s.begin(at: at(20), showsLoading: false)
        s.expire(now: at(25))
        #expect(s.phase == .failed(.timedOut, lastGoodAt: at(12)), "timedOut keeps lastGoodAt")
    }

    @Test func expireWithoutAttemptIsNoOp() {
        var s = BlockState(.cpu, createdAt: t0)
        s.expire(now: at(1000))
        #expect(s.phase == .loading(since: t0), "no attempt: stays loading")
        s.succeed(at: at(1))
        s.expire(now: at(1000))
        #expect(s.phase == .ok(at: at(1)), "no attempt: stays ok")
    }

    @Test func noVerdictEndsAttemptOnly() {
        var s = BlockState(.cpu, createdAt: t0)
        s.begin(at: t0, showsLoading: false)
        s.endWithoutVerdict()
        #expect(s.attemptStartedAt == nil, "attempt closed")
        #expect(s.phase == .loading(since: t0), "phase unchanged")
        s.expire(now: at(100))
        #expect(s.phase == .loading(since: t0), "expire after no-verdict: unchanged")
    }
}
