// Tests/MacDashboardTests/ControllerTestSupport.swift
// ARCH-MODEL-SPLIT: the fakes every controller test of the series shares — a virtual clock for TimeSource and a
// host over a FullReport value. Grown here, once, whenever ReportHost grows.
import Foundation
import Testing
@testable import MacDashboard

/// A clock the test advances: every `sleep` adds its duration to an integer millisecond counter, records it and
/// calls `onSleep(ordinal)` (the test's hook to end the "pass"). Integer time: 75 × 200 ms is exactly 15 s,
/// so poll counts are deterministic. No wall-clock wait ever happens.
@MainActor final class VirtualClock {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    private(set) var elapsedMs: Int64 = 0
    private(set) var sleeps: [Duration] = []
    var onSleep: @MainActor (Int) -> Void = { _ in }
    var now: Date { base.addingTimeInterval(Double(elapsedMs) / 1000) }
    var source: TimeSource {
        TimeSource(now: { self.now }, sleep: { d in
            self.sleeps.append(d)
            self.elapsedMs += d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000
            self.onSleep(self.sleeps.count)
            await Task.yield()
        })
    }
}

/// A ReportHost over a plain FullReport value, counting every call.
@MainActor final class FakeHost {
    var report = FullReport()
    var collecting = false
    var passEnds = true
    var paused = false
    private(set) var updateCalls = 0
    private(set) var awaitCalls = 0
    private(set) var reassessCalls = 0
    private(set) var claudeRefreshCalls = 0
    /// One block-API call, in order.
    enum BlockCall: Equatable {
        case begin(BlockID, showsLoading: Bool, armsWatchdog: Bool)
        case succeed(BlockID)
        case fail(BlockID, BlockFailure)
    }
    private(set) var mergeCalls = 0
    private(set) var blockCalls: [BlockCall] = []
    private(set) var errors: [String] = []
    var host: ReportHost {
        ReportHost(read: { self.report },
                   update: { mutate in self.updateCalls += 1; mutate(&self.report) },
                   isCollecting: { self.collecting },
                   awaitPassEnd: { self.awaitCalls += 1; return self.passEnds },
                   reassess: { self.reassessCalls += 1 },
                   isPaused: { self.paused },
                   refreshClaudeBackup: { self.claudeRefreshCalls += 1 },
                   mergeBackgroundIntoCommitted: { self.mergeCalls += 1 },
                   beginBlock: { id, loading, watchdog in self.blockCalls.append(.begin(id, showsLoading: loading, armsWatchdog: watchdog)) },
                   succeedBlock: { self.blockCalls.append(.succeed($0)) },
                   failBlock: { self.blockCalls.append(.fail($0, $1)) },
                   reportError: { self.errors.append($0) })
    }
}

/// Yields until `cond` holds (bounded; every fake completes within a few yields). Unstructured Tasks spawned on
/// the main actor do not run until the test suspends — call this before asserting on their side effects.
@MainActor func settle(_ cond: () -> Bool) async {
    for _ in 0..<1000 where !cond() { await Task.yield() }
}
