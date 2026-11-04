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
    /// What `listSnapshots` returns (nil = the read failed) and each `deleteSnapshot` outcome by date; absent = exit 0.
    var currentSnapshots: [String]? = nil
    var deleteResults: [String: CommandOutcome] = [:]
    var holdDelete = false
    private(set) var deletes: [String] = []
    private(set) var deleteParked = false
    private var deleteGate: CheckedContinuation<Void, Never>?
    func releaseDelete() { deleteGate?.resume(); deleteGate = nil }
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
            },
            deleteSnapshot: { date in
                self.deletes.append(date)
                if self.holdDelete {
                    await withCheckedContinuation { self.deleteGate = $0; self.deleteParked = true }
                }
                return self.deleteResults[date] ?? FakeTimeMachine.exit0
            },
            listSnapshots: { self.currentSnapshots })
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

        // 1 (R4, R5): an idle Mac is probed once in the first 10 s; the poll sleeps 2 s on the injected clock
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
        // R9: an idle Mac is sampled every 10 s (ticks 0, 5, 10)
        @Test func anIdleMacIsSampledEveryTenSeconds() async {
            let (c, _, fake, clock) = make()
            clock.onSleep = { n in if n == 11 { c.stop() } }
            await c.observeStatus()
            #expect(fake.statusCalls == 3)
            #expect(clock.sleeps.allSatisfy { $0 == .seconds(2) })
        }
        // R9: a backup macOS started is noticed at the next idle sample, then the 2 s cadence applies
        @Test func aBackupStartedByMacOSIsNoticedAtTheNextIdleSample() async {
            let (c, _, fake, clock) = make()
            fake.statuses = [FakeTimeMachine.exit0, FakeTimeMachine.running]
            var callsAtSleep: [Int: Int] = [:]
            var runningAtSleep: [Int: Bool] = [:]
            clock.onSleep = { n in
                callsAtSleep[n] = fake.statusCalls
                runningAtSleep[n] = c.backup?.running == true
                if n == 8 { c.stop() }
            }
            await c.observeStatus()
            #expect(runningAtSleep[1] == false && runningAtSleep[5] == false)
            #expect(callsAtSleep[5] == 1 && callsAtSleep[6] == 2)
            #expect(runningAtSleep[6] == true)
            #expect(callsAtSleep[7] == 3 && callsAtSleep[8] == 4)      // one call per further sleep
        }
        // R9: a sample due during a pause runs at the first tick after resume
        @Test func anIdleSampleDueDuringAPauseRunsOnResume() async {
            let (c, host, fake, clock) = make()
            host.paused = true
            var callsAtSleep: [Int: Int] = [:]
            clock.onSleep = { n in
                callsAtSleep[n] = fake.statusCalls
                if n == 7 { host.paused = false }
                if n == 8 { c.stop() }
            }
            await c.observeStatus()
            #expect(callsAtSleep[6] == 0 && callsAtSleep[7] == 0)
            #expect(fake.statusCalls == 1 && callsAtSleep[8] == 1)
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
        // STORAGE-ACTIONS-COPY Stage 2. Every test here runs through the fake; `liveDeleteIsRefused` proves the live closure refuses.
        private func snap(_ time: String) -> String { "com.apple.TimeMachine.2026-11-03-\(time).local" }
        private func exit70(_ line: String) -> CommandOutcome {
            CommandOutcome(termination: .exited(70), stdout: "", stdoutTruncated: false, stderrHead: line + "\n")
        }

        /// The Backups page is open (a run that ends with no page observing leaves no note). Paused, so the poll adds no status reads.
        private func openPage(_ c: TimeMachineController, _ host: FakeHost) async -> Task<Void, Never> {
            host.paused = true
            let visit = Task { await c.observeStatus() }
            await settle { c.pollTask != nil }
            return visit
        }

        @Test func noDeleteWithoutTheConfirmation() async {
            let (c, _, fake, _) = make()
            fake.currentSnapshots = [snap("043250")]
            c.confirmSnapshotDelete(names: [snap("043250")])
            await c.deleteTask?.value
            #expect(fake.deletes.isEmpty && fake.statusCalls == 0 && c.deleteState == .idle)
            c.requestSnapshotDelete()
            #expect(c.showDeleteConfirm && fake.deletes.isEmpty, "opening the panel deletes nothing")
            c.cancelSnapshotDelete()
            c.confirmSnapshotDelete(names: [snap("043250")])
            await c.deleteTask?.value
            #expect(fake.deletes.isEmpty && c.deleteState == .idle, "a cancelled panel deletes nothing")
        }

        @Test func deletesEachDateInOrderThenReReads() async {
            let (c, host, fake, _) = make()
            let visit = await openPage(c, host); defer { visit.cancel() }
            fake.currentSnapshots = [snap("043250"), snap("053250")]
            fake.collected = (nil, [])
            host.report.snapshots = [snap("043250"), snap("053250")]
            c.requestSnapshotDelete()
            c.confirmSnapshotDelete(names: [snap("043250"), snap("053250")])
            #expect(!c.showDeleteConfirm && c.deleteState == .deleting)
            await c.deleteTask?.value
            #expect(fake.deletes == ["2026-11-03-043250", "2026-11-03-053250"])
            #expect(c.deleteState == .finished(SnapshotDeleteResult(deleted: 2, failed: 0, failure: nil)))
            #expect(fake.statusCalls == 1, "one status read at the click, no polling")
            #expect(fake.collectCalls == 1 && host.report.snapshots == [] && host.reassessCalls == 1)
        }

        @Test func anEarlierReReadDoesNotSwallowTheOneAfterTheRun() async {
            let (c, host, fake, _) = make()
            fake.currentSnapshots = [snap("043250")]
            fake.collected = (nil, [snap("043250")])
            fake.holdCollect = true
            c.refreshNow()
            await settle { fake.collectParked }
            c.requestSnapshotDelete()
            c.confirmSnapshotDelete(names: [snap("043250")])
            await settle { fake.deletes.count == 1 }
            fake.holdCollect = false
            fake.collected = (nil, [])
            fake.releaseCollect()
            await c.deleteTask?.value
            #expect(fake.collectCalls == 2 && host.report.snapshots == [])
        }

        @Test func noSecondRunWhileOneIsInFlight() async {
            let (c, host, fake, _) = make()
            host.report.tmDest = .some(dest(mounted: true))
            fake.currentSnapshots = [snap("043250")]
            fake.holdDelete = true
            c.requestSnapshotDelete()
            c.confirmSnapshotDelete(names: [snap("043250")])
            await settle { fake.deleteParked }
            c.requestSnapshotDelete()
            #expect(!c.showDeleteConfirm)
            c.confirmSnapshotDelete(names: [snap("043250")])
            c.startBackupNow()
            #expect(fake.commands.isEmpty && c.action == .idle, "no backup starts during a run")
            fake.releaseDelete()
            await c.deleteTask?.value
            #expect(fake.deletes.count == 1)
        }

        @Test func partialFailureContinuesAndCountsHonestly() async {
            let (c, host, fake, _) = make()
            let visit = await openPage(c, host); defer { visit.cancel() }
            let names = [snap("043250"), snap("053250"), snap("063250")]
            fake.currentSnapshots = names
            fake.deleteResults["2026-11-03-053250"] = exit70("Failed to delete local snapshot '2026-11-03-053250'")
            c.requestSnapshotDelete()
            c.confirmSnapshotDelete(names: names)
            await c.deleteTask?.value
            #expect(fake.deletes.count == 3)
            #expect(c.deleteState == .finished(SnapshotDeleteResult(deleted: 2, failed: 1, failure: .tool("Failed to delete local snapshot '2026-11-03-053250'"))))
        }

        @Test func permissionFailureAndTimeoutStopTheRun() async {
            let names = [snap("043250"), snap("053250"), snap("063250")]
            for (result, failure) in [
                (CommandOutcome(termination: .exited(1), stdout: "", stdoutTruncated: false, stderrHead: "requires Full Disk Access\n"), SnapshotDeleteFailure.permission),
                (CommandOutcome(termination: .timedOut, stdout: "", stdoutTruncated: false, stderrHead: ""), SnapshotDeleteFailure.timedOut),
            ] {
                let (c, host, fake, _) = make()
                let visit = await openPage(c, host); defer { visit.cancel() }
                fake.currentSnapshots = names
                fake.deleteResults["2026-11-03-053250"] = result
                c.requestSnapshotDelete()
                c.confirmSnapshotDelete(names: names)
                await c.deleteTask?.value
                #expect(fake.deletes == ["2026-11-03-043250", "2026-11-03-053250"])
                #expect(c.deleteState == .finished(SnapshotDeleteResult(deleted: 1, failed: 2, failure: failure)))
            }
        }

        @Test func aRunningBackupStopsTheRunBeforeAnyDelete() async {
            let (c, host, fake, _) = make()
            let visit = await openPage(c, host); defer { visit.cancel() }
            fake.statuses = [FakeTimeMachine.running]
            fake.currentSnapshots = [snap("043250")]
            c.requestSnapshotDelete()   // Home's chip: `backup` is nil, the controller cannot know yet
            #expect(c.showDeleteConfirm)
            c.confirmSnapshotDelete(names: [snap("043250")])
            await c.deleteTask?.value
            #expect(fake.deletes.isEmpty)
            #expect(c.deleteState == .finished(SnapshotDeleteResult(deleted: 0, failed: 1, failure: .backupRunning)))
            #expect(fake.collectCalls == 1, "the list is re-read after a failed run too")
        }

        @Test func deletesOnlyConfirmedNamesStillOnTheFreshList() async {
            let (c, host, fake, _) = make()
            let visit = await openPage(c, host); defer { visit.cancel() }
            fake.currentSnapshots = [snap("053250"), snap("063250")]   // 043250 vanished, 063250 is new
            c.requestSnapshotDelete()
            c.confirmSnapshotDelete(names: [snap("043250"), snap("053250")])
            await c.deleteTask?.value
            #expect(fake.deletes == ["2026-11-03-053250"])
            #expect(c.deleteState == .finished(SnapshotDeleteResult(deleted: 1, failed: 0, failure: nil)))
        }

        @Test func aBackupSeenByThePollClosesThePanelAndBlocksTheButton() async {
            let (c, _, fake, _) = make()
            fake.statuses = [FakeTimeMachine.running]
            c.requestSnapshotDelete()
            let visit = Task { await c.observeStatus() }
            await settle { fake.statusCalls >= 1 && !c.showDeleteConfirm }
            c.requestSnapshotDelete()
            #expect(!c.showDeleteConfirm)
            visit.cancel(); await visit.value
        }

        @Test func leavingThePageClearsTheNoteAndARequestClearsItToo() async {
            let (c, _, fake, _) = make()
            let done = SnapshotDeleteState.finished(SnapshotDeleteResult(deleted: 1, failed: 0, failure: nil))
            c.applyFixtureSnapshotDelete(state: done)
            let visit = Task { await c.observeStatus() }
            await settle { fake.statusCalls >= 1 }
            visit.cancel(); await visit.value
            #expect(c.deleteState == .idle)
            c.applyFixtureSnapshotDelete(state: done)
            c.requestSnapshotDelete()
            #expect(c.deleteState == .idle && c.showDeleteConfirm)
        }

        @Test func aRequestDoesNotSurviveTheVisitItWasMadeFor() async {
            let (c, _, fake, _) = make()
            c.requestSnapshotDelete()          // Home's chip; the page then shows `.wait`, so no panel mounts
            let visit = Task { await c.observeStatus() }
            await settle { fake.statusCalls >= 1 }
            #expect(c.showDeleteConfirm)
            visit.cancel(); await visit.value
            #expect(!c.showDeleteConfirm)
        }

        @Test func aRunThatEndsAfterTheVisitLeavesNoNote() async {
            let (c, _, fake, _) = make()
            fake.currentSnapshots = [snap("043250")]
            c.requestSnapshotDelete()
            c.confirmSnapshotDelete(names: [snap("043250")])
            await c.deleteTask?.value
            #expect(c.deleteState == .idle)
            #expect(fake.collectCalls == 1, "the list is still re-read")
        }

        @Test func stopCancelsARunAndLeavesNoSpinner() async {
            let (c, _, fake, _) = make()
            fake.currentSnapshots = [snap("043250")]
            fake.holdDelete = true
            c.requestSnapshotDelete()
            c.confirmSnapshotDelete(names: [snap("043250")])
            await settle { fake.deleteParked }
            let task = c.deleteTask
            c.stop()
            #expect(c.deleteState == .idle && c.deleteTask == nil)
            fake.releaseDelete()
            await task?.value
            #expect(c.deleteState == .idle && fake.collectCalls == 0)
        }

        @Test func homeChipOpensTheConfirmationAndDeletesNothing() async {
            let (c, _, fake, _) = make()
            let router = NavigationRouter()
            let chip = HomeChip(id: "snapshots", object: "Delete", value: "3 snapshots", destination: Destination(.backups, focus: .tm), opensDeleteConfirm: true)
            HomeAttentionCard.activate(chip, timeMachine: c, router: router)
            #expect(c.showDeleteConfirm && router.destination == Destination(.backups, focus: .tm))
            #expect(fake.deletes.isEmpty && fake.statusCalls == 0)
            let other = HomeChip(id: "brew", object: "Update Homebrew", value: "(3)", destination: Destination(.system, focus: .brew))
            c.cancelSnapshotDelete()
            HomeAttentionCard.activate(other, timeMachine: c, router: router)
            #expect(!c.showDeleteConfirm && router.destination == Destination(.system, focus: .brew))
        }

        /// The date does not exist on any Mac, so even a broken gate could delete nothing.
        @Test func liveDeleteIsRefused() async {
            let outcome = await TimeMachineController.Dependencies.live.deleteSnapshot("1999-01-01-000000")
            #expect(outcome.termination == .launchFailed(EPERM))
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

        // Opt-in: MACDASH_LIVE=1 swift test --filter liveCanarySnapshotDates
        // STORAGE-ACTIONS-COPY R28. Reads only: the production list closure and `tmutil listlocalsnapshotdates /`. Deletes nothing.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanarySnapshotDates() async {
            let names = await TimeMachineController.Dependencies.live.listSnapshots()
            print("liveCanary snapshot names=\(String(describing: names))")
            #expect(names != nil)
            let dates = (names ?? []).compactMap(SnapshotDeletion.date(fromName:))
            #expect(dates.count == names?.count, "every real name has the exact shape")
            func independent(_ env: [String: String]) async -> [String] {
                let text = await CommandRunner.run("/usr/bin/tmutil", ["listlocalsnapshotdates", "/"], timeout: 15, environment: env).text ?? ""
                return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { SnapshotDeletion.isValidDate($0) }
            }
            let local = await independent(SnapshotDeletion.environment)
            let utc = await independent(CommandRunner.defaultEnvironment)
            print("liveCanary dates=\(dates) listlocalsnapshotdates(local)=\(local) listlocalsnapshotdates(TZ=UTC)=\(utc)")
            #expect(Set(dates) == Set(local), "the delete argument agrees with an independent tmutil verb in the delete environment")
        }
    }
}
