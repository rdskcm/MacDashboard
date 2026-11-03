// Tests/MacDashboardTests/ClaudeBackupControllerTests.swift
// BACKUP-CARD-FAILURE R8, R9: the Claude card's poll cadence, pause and cancel behaviour, and the Back up now click
// with its outcomes, all through injected closures: no real log, no launch. Host and clock fakes: ControllerTestSupport.swift.
// In SerialTests: `observe()` reads the process-wide `VisualFixture.forced`.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeClaudeBackup {
    static let exit0 = CommandOutcome(termination: .exited(0), stdout: "", stdoutTruncated: false, stderrHead: "")
    static let exit1 = CommandOutcome(termination: .exited(1), stdout: "", stdoutTruncated: false, stderrHead: "")
    var job: ClaudeBackupJob? = ClaudeBackupJob(label: "x", appPath: "/Apps/ClaudeBackup.app", schedule: [], startsOnMount: true)
    var attempt: ClaudeBackupAttempt? = nil
    var size: ClaudeBackupSize? = nil
    var outcome: ClaudeBackupClickOutcome? = nil
    var launchResult = FakeClaudeBackup.exit0
    var existing: Set<String> = []
    private(set) var jobReads = 0, attemptReads = 0, outcomeReads = 0, existsReads = 0
    private(set) var launched: [String] = []

    var deps: ClaudeBackupController.Dependencies {
        .init(findJob: { self.jobReads += 1; return self.job },
              readAttempt: { _ in self.attemptReads += 1; return self.attempt },
              readSize: { self.size },
              readClickOutcome: { _ in self.outcomeReads += 1; return self.outcome },
              launch: { app in self.launched.append(app); return self.launchResult },
              pathExists: { self.existsReads += 1; return self.existing.contains($0) })
    }
}

extension SerialTests {
    @MainActor struct ClaudeBackupControllerTests {
        private let mnt = "/Volumes/Backup SSD"
        private func make() -> (ClaudeBackupController, FakeHost, FakeClaudeBackup, VirtualClock) {
            let host = FakeHost(), fake = FakeClaudeBackup(), clock = VirtualClock()
            let c = ClaudeBackupController(host: host.host, time: clock.source, deps: fake.deps)
            host.onClaudeRefresh = { await c.refreshAttempt() }
            return (c, host, fake, clock)
        }
        private func ok(_ at: Date) -> ClaudeBackupAttempt { .init(at: at, result: .ok, mount: mnt) }
        private func running(_ at: Date) -> ClaudeBackupAttempt { .init(at: at, result: .running, mount: mnt) }

        @Test func idleReadsEveryThirtySeconds() async {
            let (c, _, fake, clock) = make()
            clock.onSleep = { n in if n == 31 { c.stop() } }
            await c.observe()
            #expect(fake.attemptReads == 3)
            #expect(clock.sleeps.allSatisfy { $0 == .seconds(2) })
        }

        @Test func runningReadsEverySixSeconds() async {
            let (c, _, fake, clock) = make()
            fake.attempt = running(clock.now)
            clock.onSleep = { n in if n == 10 { c.stop() } }     // iterations 0..9 → reads at 0, 3, 6, 9
            await c.observe()
            #expect(fake.attemptReads == 4)
        }

        @Test func pausedReadsNothingThenResumes() async {
            let (c, host, fake, clock) = make()
            host.paused = true
            var atSleep: [Int: Int] = [:]
            clock.onSleep = { n in
                atSleep[n] = fake.attemptReads + fake.jobReads + fake.existsReads
                if n == 3 { host.paused = false }
                if n == 5 { c.stop() }
            }
            await c.observe()
            #expect(atSleep[3] == 0)
            #expect(fake.attemptReads >= 1 && fake.jobReads == 1)
        }

        @Test func noWorkAfterStopOrCancel() async {
            let (c, _, fake, clock) = make()
            clock.onSleep = { n in if n == 2 { c.stop() } }
            await c.observe()
            let reads = fake.attemptReads, sleeps = clock.sleeps.count
            #expect(c.pollTask == nil)
            for _ in 0..<20 { await Task.yield() }
            #expect(fake.attemptReads == reads && clock.sleeps.count == sleeps)

            let (c2, _, _, clock2) = make()
            var t: Task<Void, Never>!
            clock2.onSleep = { n in if n == 3 { t.cancel() } }
            t = Task { await c2.observe() }
            await t.value
            #expect(c2.pollTask == nil)
            #expect(clock2.sleeps.count <= 4)
        }

        @Test func refreshAttemptPublishesTheSize() async {
            let (c, _, fake, _) = make()
            #expect(c.size == nil)
            fake.size = ClaudeBackupSize(snapshotBytes: 3, addedBytes: 2, totalBytes: 5)
            await c.refreshAttempt()
            #expect(c.size == fake.size)
            fake.size = nil
            await c.refreshAttempt()
            #expect(c.size == nil)
        }

        @Test func visualFixtureReadsNothing() async {
            let (c, _, fake, clock) = make()
            VisualFixture.forced = true
            defer { VisualFixture.forced = false }
            await c.observe()
            #expect(fake.attemptReads == 0 && fake.jobReads == 0 && clock.sleeps.isEmpty)
        }

        @Test func clickGuards() async {
            let (c, _, fake, clock) = make()
            c.applyFixture(job: nil, attempt: ok(clock.now), diskConnected: true, action: .idle)
            c.startBackupNow(); #expect(c.action == .idle && fake.launched.isEmpty)
            c.applyFixture(job: ClaudeBackupJob(label: nil, appPath: nil, schedule: [], startsOnMount: false), attempt: nil, diskConnected: nil, action: .idle)
            c.startBackupNow(); #expect(c.action == .idle && fake.launched.isEmpty)
            c.applyFixture(job: fake.job, attempt: running(clock.now), diskConnected: true, action: .idle)
            c.startBackupNow(); #expect(c.action == .idle && fake.launched.isEmpty)
            c.applyFixture(job: fake.job, attempt: ok(clock.now), diskConnected: true, action: .idle)
            c.startBackupNow(); c.startBackupNow()
            await settle { c.launchTask != nil && fake.launched.count >= 1 }
            await c.launchTask?.value
            #expect(fake.launched == ["/Apps/ClaudeBackup.app"])
        }

        @Test func launchFailureAndTheLoopContinues() async {
            let (c, _, fake, clock) = make()
            fake.launchResult = FakeClaudeBackup.exit1
            c.applyFixture(job: fake.job, attempt: ok(clock.now.addingTimeInterval(-3600)), diskConnected: true, action: .idle)
            var seen: [ClaudeBackupAction] = []
            clock.onSleep = { n in
                if n == 1 { c.startBackupNow() }
                seen.append(c.action)
                if n == 6 { c.stop() }
            }
            await c.observe()
            #expect(seen.last == .launchFailed)
            #expect(clock.sleeps.count == 6)
        }

        @Test func newAttemptClearsTheClick() async {
            let (c, _, fake, clock) = make()
            c.applyFixture(job: fake.job, attempt: ok(clock.now.addingTimeInterval(-3600)), diskConnected: true, action: .idle)
            fake.attempt = ok(clock.now.addingTimeInterval(-3600))
            var seen: [ClaudeBackupAction] = []
            clock.onSleep = { n in
                if n == 1 { c.startBackupNow() }
                if n == 3 { fake.attempt = running(clock.now) }
                seen.append(c.action)
                if n == 6 { c.stop() }
            }
            await c.observe()
            #expect(seen[1] == .starting)
            #expect(seen.last == .idle)
            #expect(fake.launched.count == 1)
        }

        @Test func outcomesFromTheLog() async {
            for (o, expected) in [(ClaudeBackupClickOutcome.diskNotConnected, ClaudeBackupAction.diskNotConnected),
                                  (.alreadyRunning, .alreadyRunning)] {
                let (c, _, fake, clock) = make()
                fake.attempt = ok(clock.now.addingTimeInterval(-3600))
                fake.outcome = o
                var seen: [ClaudeBackupAction] = []
                clock.onSleep = { n in
                    if n == 1 { c.startBackupNow() }
                    seen.append(c.action)
                    if n == 5 { c.stop() }
                }
                await c.observe()
                #expect(seen.last == expected, "\(o)")
            }
        }

        @Test func noResponseAfterFifteenPollsThenALaterAttemptClearsIt() async {
            let (c, _, fake, clock) = make()
            fake.attempt = ok(clock.now.addingTimeInterval(-3600))
            var seen: [Int: ClaudeBackupAction] = [:]
            clock.onSleep = { n in
                if n == 1 { c.startBackupNow() }
                if n == 20 { fake.attempt = ok(clock.now) }
                seen[n] = c.action
                if n == 40 { c.stop() }
            }
            await c.observe()
            #expect(seen[10] == .starting)
            #expect(seen[19] == .noResponse)
            #expect(seen[40] == .idle)   // noResponse is read at the idle cadence (30 s)
        }

        @Test func alreadyRunningClearsWhenTheRunEnds() async {
            let (c, _, fake, clock) = make()
            let old = clock.now.addingTimeInterval(-3600)
            fake.attempt = ok(old)
            fake.outcome = .alreadyRunning
            var seen: [Int: ClaudeBackupAction] = [:]
            clock.onSleep = { n in
                if n == 1 { c.startBackupNow() }
                if n == 4 { fake.attempt = running(old); fake.outcome = nil }
                if n == 12 { fake.attempt = ok(old) }
                seen[n] = c.action
                if n == 20 { c.stop() }
            }
            await c.observe()
            #expect(seen[3] == .alreadyRunning)
            #expect(seen[11] == .alreadyRunning)
            #expect(seen[20] == .idle)
        }

        @Test func leavingThePageResetsTheActionKeepsTheState() async {
            let (c, _, fake, clock) = make()
            fake.attempt = ok(clock.now)
            fake.outcome = .diskNotConnected
            clock.onSleep = { n in
                if n == 1 { c.startBackupNow() }
                if n == 5 { c.stop() }
            }
            await c.observe()
            #expect(c.action == .idle)
            #expect(c.job != nil && c.attempt != nil)
        }

        @Test func volumeEventReadsAtTheNextTick() async {
            let (c, _, fake, clock) = make()
            var at: [Int: Int] = [:]
            clock.onSleep = { n in
                at[n] = fake.attemptReads
                if n == 4 { c.volumesChanged() }
                if n == 6 { c.stop() }
            }
            await c.observe()
            #expect(at[4] == 1)
            #expect(at[5] == 2)
        }

        @Test func diskFollowsThePathOfTheMount() async {
            let (c, _, fake, clock) = make()
            fake.attempt = ok(clock.now)
            fake.existing = [mnt]
            clock.onSleep = { n in if n == 2 { c.stop() } }
            await c.observe()
            #expect(c.diskConnected == true)
            let (c2, _, fake2, clock2) = make()
            fake2.attempt = ClaudeBackupAttempt(at: clock2.now, result: .ok, mount: nil)
            clock2.onSleep = { n in if n == 2 { c2.stop() } }
            await c2.observe()
            #expect(c2.diskConnected == nil && fake2.existsReads == 0)
        }
    }
}
