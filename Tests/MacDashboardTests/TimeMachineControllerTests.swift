// Tests/MacDashboardTests/TimeMachineControllerTests.swift
// ARCH-MODEL-SPLIT block 4: the Time Machine poll, Back up now / Stop and the destination re-read through injected
// closures — no tmutil, no collector, no coordinator. Host and clock fakes: ControllerTestSupport.swift.
// In SerialTests: `observeStatus()` reads the process-wide `VisualFixture.forced` that the snapshot suites set.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeTimeMachine {
    static let exit0 = CommandOutcome(termination: .exited(0), stdout: "", stdoutTruncated: false, stderrHead: "")
    /// A running backup, from the fixture the snapshot suite also uses.
    static let running = CommandOutcome(
        termination: .exited(0),
        stdout: (try? String(contentsOf: fixturesRoot.appendingPathComponent("tmutil-status/tmutil-status-backing-synthetic.txt"),
                             encoding: .utf8)) ?? "",
        stdoutTruncated: false, stderrHead: "")

    /// What each `status` call returns, in order; the last one repeats. Empty output reads as `.idle`.
    var statuses: [CommandOutcome] = [FakeTimeMachine.exit0]
    var commandResult = FakeTimeMachine.exit0
    var collected: (dest: TMDestination??, snapshots: [String]?) = (nil, nil)
    /// When set, `command` / `collect` park until released (not cancellation-aware, like a running process).
    var holdCommand = false
    var holdCollect = false
    private(set) var statusCalls = 0
    private(set) var commands: [String] = []
    private(set) var collectCalls = 0
    private(set) var commandParked = false
    private(set) var collectParked = false
    private var commandGate: CheckedContinuation<Void, Never>?
    private var collectGate: CheckedContinuation<Void, Never>?

    func releaseCommand() { commandGate?.resume(); commandGate = nil }
    func releaseCollect() { collectGate?.resume(); collectGate = nil }

    var deps: TimeMachineController.Dependencies {
        TimeMachineController.Dependencies(
            status: {
                self.statusCalls += 1
                return self.statuses[min(self.statusCalls, self.statuses.count) - 1]
            },
            command: { verb in
                self.commands.append(verb)
                if self.holdCommand {
                    await withCheckedContinuation { self.commandGate = $0; self.commandParked = true }
                }
                return self.commandResult
            },
            collect: {
                self.collectCalls += 1
                if self.holdCollect {
                    await withCheckedContinuation { self.collectGate = $0; self.collectParked = true }
                }
                return self.collected
            })
    }
}

extension SerialTests {
    @MainActor struct TimeMachineControllerTests {
        private func dest(mounted: Bool) -> TMDestination {
            TMDestination(name: "Backup SSD", kind: "Local", mountPoint: mounted ? "/Volumes/Backup SSD" : nil,
                          quotaBytes: nil, lastBackup: nil, lastBackupDate: nil, freeBytes: nil, schedule: nil)
        }
        private var sample: TMBackupProgress { TimeMachineStatus.parse(text: FakeTimeMachine.running.stdout)! }
        private func make() -> (TimeMachineController, FakeHost, FakeTimeMachine, VirtualClock) {
            let host = FakeHost(), fake = FakeTimeMachine(), clock = VirtualClock()
            return (TimeMachineController(host: host.host, time: clock.source, deps: fake.deps), host, fake, clock)
        }
        /// Snapshot the command handles right after the call (before any suspension), then await them.
        private func drain(_ c: TimeMachineController) async { for t in Array(c.commandTasks.values) { await t.value } }
        private func failedExit(_ stderr: String) -> CommandOutcome {
            CommandOutcome(termination: .exited(1), stdout: "", stdoutTruncated: false, stderrHead: stderr)
        }

        // 1 (R4, R5): an idle Mac is probed once per visit; the poll sleeps 2 s on the injected clock
        @Test func observeStatusProbesOnceWhenIdleAndSleepsOnTheClock() async {
            let (c, _, fake, clock) = make()
            clock.onSleep = { n in if n == 3 { c.stop() } }
            await c.observeStatus()
            #expect(fake.statusCalls == 1)
            #expect(clock.sleeps == [.seconds(2), .seconds(2), .seconds(2)])
            #expect(c.backup == nil && c.pollTask == nil)          // the visit's sample is dropped when it ends
        }
        // 2 (R5)
        @Test func observeStatusSpawnsNothingWhilePaused() async {
            let (c, host, fake, clock) = make()
            host.paused = true
            clock.onSleep = { n in if n == 3 { c.stop() } }
            await c.observeStatus()
            #expect(fake.statusCalls == 0 && clock.sleeps.count == 3)
        }
        // 3 (R3, R5): the page leaving cancels the poll and clears a failed action
        @Test func pageLeavingCancelsThePollAndClearsAFailedAction() async {
            let (c, _, fake, _) = make()
            c.applyFixture(updatedAt: nil, backup: nil, action: .failed("x"))
            let visit = Task { await c.observeStatus() }
            await settle { fake.statusCalls == 1 }
            let poll = c.pollTask
            visit.cancel()
            await visit.value
            #expect(poll?.isCancelled == true)
            #expect(c.pollTask == nil && c.backup == nil && c.action == .idle)
        }
        // 4 (D5): a newer visit owns the poll; the older visit's end leaves its state alone
        @Test func aNewerVisitOwnsThePoll() async {
            let (c, _, fake, _) = make()
            let first = Task { await c.observeStatus() }
            await settle { fake.statusCalls == 1 }
            let firstPoll = c.pollTask
            let second = Task { await c.observeStatus() }
            await first.value
            #expect(firstPoll?.isCancelled == true)
            #expect(c.backup == .idle && c.pollTask != nil)
            c.stop()
            await second.value
            #expect(fake.statusCalls == 1 && c.backup == nil)
        }
        // 5 (R2)
        @Test func startBackupRunsStartbackupAndThePollConfirmsIt() async {
            let (c, host, fake, clock) = make()
            host.report.tmDest = .some(dest(mounted: true))
            c.startBackupNow()
            #expect(c.action == .starting)
            await drain(c)
            #expect(fake.commands == ["startbackup"] && c.action == .starting && c.commandTasks.isEmpty)
            fake.statuses = [FakeTimeMachine.running]
            clock.onSleep = { n in if n == 1 { c.stop() } }
            await c.observeStatus()
            #expect(fake.statusCalls == 1 && c.action == .idle)
        }
        // 6 (R2): five polls without a running backup → «did not begin»; leaving the page clears it
        @Test func startGivesUpAfterFivePollsWithoutABackup() async {
            let (c, host, fake, clock) = make()
            host.report.tmDest = .some(dest(mounted: true))
            c.startBackupNow(); await drain(c)
            var atFifth: TMActionState?
            clock.onSleep = { n in if n == 5 { atFifth = c.action; c.stop() } }
            await c.observeStatus()
            #expect(fake.statusCalls == 5 && atFifth == .failed(L.bkStartDidNotBegin))
            #expect(c.action == .idle)
        }
        // 7 (R2)
        @Test func startFailureShowsTheFirstStderrLineAndMayBeRetried() async {
            let (c, host, fake, _) = make()
            host.report.tmDest = .some(dest(mounted: true))
            fake.commandResult = failedExit("\n  boom  \nsecond line")
            c.startBackupNow(); await drain(c)
            #expect(c.action == .failed(L.bkStartFailed("boom")))
            c.startBackupNow(); await drain(c)
            #expect(fake.commands == ["startbackup", "startbackup"])
            fake.commandResult = failedExit("")
            c.startBackupNow(); await drain(c)
            #expect(c.action == .failed(L.bkStartFailed(L.bkFailedNoReason)))
        }
        // 8 (R2)
        @Test func startIsIgnoredWithoutAMountedDestinationOrWhileBusy() async {
            let (c, host, fake, _) = make()
            c.startBackupNow()                                         // not checked yet
            host.report.tmDest = .some(nil); c.startBackupNow()        // not configured
            host.report.tmDest = .some(dest(mounted: false)); c.startBackupNow()   // disk not connected
            #expect(c.action == .idle && fake.commands.isEmpty)
            host.report.tmDest = .some(dest(mounted: true))
            fake.holdCommand = true
            c.startBackupNow()
            await settle { fake.commandParked }
            c.startBackupNow()                                         // .starting: ignored
            #expect(fake.commands == ["startbackup"])
            fake.releaseCommand(); await drain(c)
        }
        // 9 (R2, R8): Stop, then the poll sees the backup end and re-reads the destination
        @Test func stopRunsStopbackupAndTheBackupsEndRereadsTheDestination() async {
            let (c, host, fake, _) = make()
            let d = dest(mounted: true)
            c.applyFixture(updatedAt: nil, backup: sample, action: .idle)
            c.stopBackupNow()
            #expect(c.action == .stopping)
            await drain(c)
            #expect(fake.commands == ["stopbackup"] && c.action == .stopping)
            fake.collected = (.some(d), ["com.apple.TimeMachine.2026-10-29-101500.local"])
            let visit = Task { await c.observeStatus() }
            await settle { fake.statusCalls == 1 }
            visit.cancel(); await visit.value
            await c.refreshTask?.value
            #expect(c.action == .idle)                                 // Running == 0 cleared .stopping
            #expect(fake.collectCalls == 1 && host.report.tmDest == .some(d) && host.reassessCalls == 1)
        }
        // 10 (R2)
        @Test func stopIsIgnoredWithoutARunningBackupOrWhileBusy() {
            let (c, _, fake, _) = make()
            c.stopBackupNow()                                                          // nothing probed yet
            c.applyFixture(updatedAt: nil, backup: .idle, action: .idle); c.stopBackupNow()      // no backup running
            c.applyFixture(updatedAt: nil, backup: sample, action: .starting); c.stopBackupNow() // a start in flight
            #expect(fake.commands.isEmpty && c.action == .starting)
        }
        // 11 (R2, R8)
        @Test func refreshNowWritesAfterThePassStampsAndReassesses() async {
            let (c, host, fake, clock) = make()
            let d = dest(mounted: true)
            fake.collected = (.some(d), ["com.apple.TimeMachine.2026-10-29-101500.local"])
            c.refreshNow()
            await c.refreshTask?.value
            #expect(host.awaitCalls == 1 && host.updateCalls == 2)
            #expect(host.report.tmDest == .some(d) && host.report.snapshots == ["com.apple.TimeMachine.2026-10-29-101500.local"])
            #expect(c.updatedAt == clock.now && host.claudeRefreshCalls == 1 && host.reassessCalls == 1)
        }
        // 12 (R2): a failed tmutil read keeps the old values; the stamp and the re-check still happen
        @Test func refreshNowKeepsTheOldValuesWhenTmutilFailed() async {
            let (c, host, _, clock) = make()
            let d = dest(mounted: true)
            host.report.tmDest = .some(d); host.report.snapshots = ["old"]
            c.refreshNow()
            await c.refreshTask?.value
            #expect(host.updateCalls == 0 && host.report.tmDest == .some(d) && host.report.snapshots == ["old"])
            #expect(c.updatedAt == clock.now && host.claudeRefreshCalls == 1 && host.reassessCalls == 1)
        }
        // 13 (R2)
        @Test func refreshNowIsIgnoredWhileRefreshing() async {
            let (c, _, fake, _) = make()
            fake.holdCollect = true
            c.refreshNow()
            await settle { fake.collectParked }
            c.refreshNow()
            fake.releaseCollect(); await c.refreshTask?.value
            #expect(fake.collectCalls == 1)
        }
        // 14 (R3): stop() cancels the command and the re-read; neither writes anything afterwards
        @Test func stopCancelsCommandsAndTheRefreshAndNothingIsWritten() async {
            let (c, host, fake, _) = make()
            host.report.tmDest = .some(dest(mounted: true))
            fake.holdCommand = true; fake.holdCollect = true
            fake.commandResult = failedExit("boom")
            fake.collected = (.some(nil), [])
            c.startBackupNow(); c.refreshNow()
            await settle { fake.commandParked && fake.collectParked }
            let commands = Array(c.commandTasks.values), refresh = c.refreshTask
            c.stop()
            #expect(c.commandTasks.isEmpty && c.refreshTask == nil && c.pollTask == nil)
            fake.releaseCommand(); fake.releaseCollect()
            for t in commands { await t.value }
            await refresh?.value
            #expect(c.action == .starting)                             // a cancelled command writes no outcome
            #expect(host.updateCalls == 0 && host.awaitCalls == 0 && host.claudeRefreshCalls == 0)
            #expect(host.reassessCalls == 0 && c.updatedAt == nil)
        }
        // 15 (R7)
        @Test func recordDestinationWritesOnlyAChangeAndStamps() async {
            let (c, host, _, clock) = make()
            let d = dest(mounted: true)
            host.report.tmDest = .some(d)
            c.recordDestination(.some(d))
            #expect(host.updateCalls == 0 && c.updatedAt == clock.now)
            await clock.source.sleep(.seconds(60))
            c.recordDestination(.some(nil))
            #expect(host.updateCalls == 1 && host.report.tmDest == .some(nil) && c.updatedAt == clock.now)
            await clock.source.sleep(.seconds(60))
            c.markUpdated()
            #expect(host.updateCalls == 1 && c.updatedAt == clock.now)
        }
        // 16 (R12) Opt-in: MACDASH_LIVE=1 swift test --filter liveCanaryTimeMachine
        // Runs the production status and collect reads on this Mac. Reads only: never startbackup / stopbackup.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryTimeMachine() async {
            let live = TimeMachineController.Dependencies.live
            let status = await live.status()
            let parsed = status.nonEmptyText.flatMap { TimeMachineStatus.parse(text: $0) }
            print("liveCanary tmutil status termination=\(status.termination) running=\(String(describing: parsed?.running)) phase=\(parsed?.phase ?? "-") percent=\(String(describing: parsed?.percent))")
            #expect(status.termination == .exited(0))
            #expect(parsed != nil)                                     // `tmutil status -X` always prints a dictionary with Running
            let (dest, snapshots) = await live.collect()
            print("liveCanary tmDest=\(String(describing: dest))")
            #expect(dest != nil)                                       // destinationinfo answered (.some(nil) = not configured)
            if case .some(.some(let d)) = dest, let mount = d.mountPoint {
                #expect(FileManager.default.fileExists(atPath: mount))   // a reported mount point exists on disk
            }
            let dates = await CommandRunner.run("/usr/bin/tmutil", ["listlocalsnapshotdates", "/"], timeout: 15).text ?? ""
            let dateCount = dates.split(separator: "\n")
                .filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) != nil }.count
            print("liveCanary listlocalsnapshots names=\(String(describing: snapshots?.count)) listlocalsnapshotdates=\(dateCount)")
            #expect(snapshots?.count == dateCount)                     // an independent tmutil verb agrees on the count
        }
    }
}
