// Tests/MacDashboardTests/BrewControllerTests.swift
// ARCH-MODEL-SPLIT block 2: the Homebrew state machine through injected closures — no brew, no collector,
// no coordinator. Host and clock fakes: ControllerTestSupport.swift.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeBrew {
    var snapshot = BrewSnapshot(status: .installed(version: "Homebrew 4.6.0"), outdated: ["git"],
                                outdatedDetail: nil, installedCount: 12)
    var upgradeResult: String? = nil
    /// Sent through `onProgress` (on the main actor) before the upgrade returns or parks.
    var progressToSend: [BrewProgress] = []
    /// When set, `upgrade` parks until `releaseUpgrade()` or until its Task is cancelled (then returns "stopped").
    var holdUpgrade = false
    /// When set, `collect` parks until `releaseCollect()`.
    var holdCollect = false
    private(set) var upgradeTotals: [Int] = []
    private(set) var collectCalls = 0
    private(set) var upgradeParked = false
    private(set) var collectParked = false
    private(set) var upgradeCancelled = false
    private(set) var lastOnProgress: (@Sendable (BrewProgress) -> Void)?
    private var upgradeGate: CheckedContinuation<Void, Never>?
    private var collectGate: CheckedContinuation<Void, Never>?

    func releaseUpgrade() { upgradeGate?.resume(); upgradeGate = nil }
    func releaseCollect() { collectGate?.resume(); collectGate = nil }

    var deps: BrewController.Dependencies {
        BrewController.Dependencies(
            upgrade: { total, onProgress in
                self.upgradeTotals.append(total)
                self.lastOnProgress = onProgress
                for p in self.progressToSend { onProgress(p) }
                if self.holdUpgrade {
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { self.upgradeGate = $0; self.upgradeParked = true }
                    } onCancel: {
                        Task { @MainActor in self.upgradeCancelled = true; self.releaseUpgrade() }
                    }
                }
                return self.upgradeCancelled ? "stopped" : self.upgradeResult
            },
            collect: {
                self.collectCalls += 1
                if self.holdCollect {
                    await withCheckedContinuation { self.collectGate = $0; self.collectParked = true }
                }
                return self.snapshot
            })
    }
}

extension SerialTests {
    @MainActor struct BrewControllerTests {
        private func make() -> (BrewController, FakeHost, FakeBrew, VirtualClock) {
            let host = FakeHost(), fake = FakeBrew(), clock = VirtualClock()
            return (BrewController(host: host.host, time: clock.source, deps: fake.deps), host, fake, clock)
        }
        private func report(_ status: BrewStatus?, outdated: [String]?) -> FullReport {
            var r = FullReport()
            r.brewStatus = status; r.brewOutdated = outdated; r.brewOutdatedDetail = nil; r.brewInstalledCount = 12
            return r
        }
        private let ok = BrewStatus.installed(version: "Homebrew 4.6.0")
        private let progress = BrewProgress(phase: .upgrading, formula: "node", completed: 1, total: 2, downloadsDone: 2)

        // 1 (R3)
        @Test func cacheIsEmptyBeforeAnyRecord() {
            let (c, _, _, clock) = make()
            #expect(c.cachedSnapshot(now: clock.now) == nil && c.checkedAt == nil)
        }
        // 2 (R3: freshness is age in [0, 600 s))
        @Test func recordFillsTheCacheAndFreshnessFollowsTheWindow() {
            let (c, _, _, clock) = make()
            c.record(report(ok, outdated: ["node"]))
            let expected = BrewSnapshot(status: ok, outdated: ["node"], outdatedDetail: nil, installedCount: 12)
            #expect(c.checkedAt == clock.now)
            #expect(c.cachedSnapshot(now: clock.now) == expected)
            #expect(c.cachedSnapshot(now: clock.now.addingTimeInterval(599)) == expected)
            #expect(c.cachedSnapshot(now: clock.now.addingTimeInterval(600)) == nil)
            #expect(c.cachedSnapshot(now: clock.now.addingTimeInterval(-1)) == nil)   // future stamp = stale
        }
        // 3 (R3: a failed check or a missing section clears; "not installed" is a valid, cacheable answer)
        @Test func recordOfAFailedCheckClearsTheCache() {
            let (c, _, _, clock) = make()
            for bad in [report(.installed(version: nil), outdated: ["node"]), report(ok, outdated: nil), report(nil, outdated: nil)] {
                c.record(report(ok, outdated: []))
                #expect(c.cachedSnapshot(now: clock.now) != nil)
                c.record(bad)
                #expect(c.cachedSnapshot(now: clock.now) == nil && c.checkedAt == nil)
            }
            c.record(report(.notInstalled, outdated: nil))
            #expect(c.cachedSnapshot(now: clock.now)?.status == .notInstalled)
        }
        // 4 (R3 + R7: re-check writes after the pass, one mutation, and refills the cache)
        @Test func refreshNowWritesTheFourFieldsAfterThePassAndFillsTheCache() async {
            let (c, host, fake, clock) = make()
            c.refreshNow()
            #expect(c.refreshing)
            await c.refreshTask?.value
            #expect(fake.collectCalls == 1 && host.awaitCalls == 1 && host.updateCalls == 1)
            #expect(host.report.brewStatus == fake.snapshot.status && host.report.brewOutdated == ["git"])
            #expect(host.report.brewInstalledCount == 12)
            #expect(c.cachedSnapshot(now: clock.now) == fake.snapshot && c.checkedAt == clock.now)
            #expect(c.refreshing == false)
        }
        // 5
        @Test func refreshNowIsIgnoredWhileRefreshingOrUpgrading() async {
            let (c, _, fake, _) = make()
            fake.holdCollect = true
            c.refreshNow()
            await settle { fake.collectParked }
            c.refreshNow()
            fake.releaseCollect(); await c.refreshTask?.value
            #expect(fake.collectCalls == 1)
            fake.holdCollect = false
            fake.holdUpgrade = true
            c.upgradeNow()
            await settle { fake.upgradeParked }
            c.refreshNow()
            #expect(c.refreshing == false)
            fake.releaseUpgrade(); await c.upgradeTask?.value
        }
        // 6 (R7: start, re-check, run state cleared)
        @Test func upgradeSuccessRechecksAndClearsTheRunState() async {
            let (c, host, fake, _) = make()
            host.report.brewOutdated = ["node", "git"]
            c.upgradeNow()
            #expect(c.upgrading && c.upgradeStoppable && c.upgradeTask != nil)
            await c.upgradeTask?.value
            #expect(fake.upgradeTotals == [2] && fake.collectCalls == 1)
            #expect(host.report.brewOutdated == ["git"])
            #expect(!c.upgrading && !c.upgradeStoppable && !c.stopRequested && c.progress == nil)
            #expect(c.upgradeError == nil && c.upgradeNotice == nil)
        }
        // 7
        @Test func upgradeFailureShowsTheErrorAfterTheRecheck() async {
            let (c, _, fake, _) = make()
            fake.upgradeResult = "Update failed: Error: node: checksum mismatch"
            c.upgradeNow(); await c.upgradeTask?.value
            #expect(fake.collectCalls == 1)
            #expect(c.upgradeError == "Update failed: Error: node: checksum mismatch" && c.upgradeNotice == nil)
        }
        // 8
        @Test func upgradeWhileUpgradingIsIgnored() async {
            let (c, _, fake, _) = make()
            fake.holdUpgrade = true
            c.upgradeNow()
            await settle { fake.upgradeParked }
            c.upgradeNow()
            #expect(fake.upgradeTotals.count == 1)
            fake.releaseUpgrade(); await c.upgradeTask?.value
            #expect(!c.upgrading)
        }
        // 9 (R7: the user's Stop cancels only the brew step; the re-check runs and words the neutral notice)
        @Test func userStopEndsTheBrewStepThenRechecksWithANotice() async {
            let (c, host, fake, _) = make()
            host.report.brewOutdated = ["node", "git", "python@3.13"]
            fake.snapshot.outdated = ["git", "python@3.13"]
            fake.holdUpgrade = true
            c.upgradeNow()
            await settle { fake.upgradeParked }
            c.stopUpgrade()
            #expect(c.stopRequested)
            await c.upgradeTask?.value
            #expect(fake.upgradeCancelled && fake.collectCalls == 1)
            #expect(c.upgradeError == nil)
            #expect(c.upgradeNotice == BrewUpgrader.stoppedNotice(before: ["node", "git", "python@3.13"],
                                                                after: ["git", "python@3.13"]))
            #expect(!c.upgrading && !c.stopRequested && !c.upgradeStoppable)
        }
        // 10
        @Test func stopUpgradeOutsideTheBrewStepIsANoOp() async {
            let (c, _, fake, _) = make()
            c.stopUpgrade()
            #expect(!c.stopRequested)
            fake.holdCollect = true
            c.upgradeNow()
            await settle { fake.collectParked }               // brew step done, re-check in flight: not stoppable
            c.stopUpgrade()
            #expect(!c.stopRequested && !fake.upgradeCancelled)
            fake.releaseCollect(); await c.upgradeTask?.value
        }
        // 11 (R5: stop() cancels the upgrade Task and through it the brew step; no re-check, no write)
        @Test func stopCancelsTheUpgradeTaskAndSkipsTheRecheck() async {
            let (c, host, fake, _) = make()
            fake.holdUpgrade = true
            c.upgradeNow()
            await settle { fake.upgradeParked }
            let task = c.upgradeTask
            c.stop()
            #expect(c.upgradeTask == nil)
            await task?.value
            #expect(fake.upgradeCancelled)
            #expect(fake.collectCalls == 0 && host.updateCalls == 0 && host.awaitCalls == 0)
            #expect(!c.upgrading && !c.upgradeStoppable && c.upgradeError == nil && c.upgradeNotice == nil)
        }
        // 12 (R5 + D7: stop() cancels an in-flight re-check; nothing is written)
        @Test func stopCancelsTheInFlightRecheck() async {
            let (c, host, fake, _) = make()
            fake.holdCollect = true
            c.refreshNow()
            await settle { fake.collectParked }
            let task = c.refreshTask
            c.stop()
            #expect(c.refreshTask == nil)
            fake.releaseCollect(); await task?.value
            #expect(host.updateCalls == 0 && host.awaitCalls == 0 && c.checkedAt == nil && !c.refreshing)
        }
        // 13 (R4: progress arrives through a main-actor Task while upgrading; a late value is dropped)
        @Test func progressIsShownWhileUpgradingAndDroppedAfter() async {
            let (c, _, fake, _) = make()
            fake.progressToSend = [progress]
            fake.holdUpgrade = true
            c.upgradeNow()
            await settle { c.progress == progress }
            #expect(c.progress == progress)
            fake.releaseUpgrade(); await c.upgradeTask?.value
            #expect(c.progress == nil)
            fake.lastOnProgress?(progress)                    // a hop that lands after the run ended
            for _ in 0..<20 { await Task.yield() }
            #expect(c.progress == nil)
        }
        // 14
        @Test func fixtureSetsTheState() {
            let (c, _, _, clock) = make()
            c.applyFixture(checkedAt: clock.now, upgrading: true, progress: progress, error: "e", notice: "n", stoppable: true)
            #expect(c.checkedAt == clock.now && c.upgrading && c.progress == progress)
            #expect(c.upgradeError == "e" && c.upgradeNotice == "n" && c.upgradeStoppable)
        }
    }
}
