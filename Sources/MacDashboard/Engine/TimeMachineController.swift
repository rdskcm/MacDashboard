// Engine/TimeMachineController.swift
// ARCH-MODEL-SPLIT block 4: the Backups page's Time Machine state, moved out of the coordinator unchanged in
// behaviour. Owns the `tmutil status` poll (REDESIGN-BACKUPS D2/D3), Back up now / Stop (R3), the destination
// re-read after a backup ends, the card's «updated HH:MM» stamp and their Task handles.
import Foundation
import Observation

@MainActor
@Observable
final class TimeMachineController {
    struct Dependencies {
        /// `tmutil status -X` (`ParsedCommand.tmutilStatus`, 10 s timeout).
        var status: @MainActor () async -> CommandOutcome
        /// `/usr/bin/tmutil <verb>` with a 15 s timeout: "startbackup" / "stopbackup" (no root, per tmutil(8)).
        var command: @MainActor (_ verb: String) async -> CommandOutcome
        /// The destination (`collectTMDestInfo`; nil = tmutil failed) and the local snapshot names
        /// (`collectLocalSnapshotNames`; nil = failed), read through one fresh ReportCollector never shared with a sampler.
        var collect: @MainActor () async -> (dest: TMDestination??, snapshots: [String]?)

        static let live = Dependencies(
            status: { await ParsedCommand.tmutilStatus.run() },
            command: { verb in await CommandRunner.run("/usr/bin/tmutil", [verb], timeout: 15) },
            collect: {
                let collector = ReportCollector()
                let dest = await collector.collectTMDestInfo()
                let snapshots = await collector.collectLocalSnapshotNames()
                return (dest, snapshots)
            })
    }

    /// Last `tmutil status` sample while the Backups page polls; nil = not probed on this visit.
    private(set) var backup: TMBackupProgress? = nil
    /// In-flight / last-failed Back up now / Stop.
    private(set) var action: TMActionState = .idle
    /// When the Time Machine destination was last (re)collected — the card's «updated HH:MM».
    private(set) var updatedAt: Date? = nil
    /// Re-entrancy guard for `refreshNow()`.
    private var refreshing = false

    /// The poll `observeStatus()` runs and awaits; `stop()` cancels it. Tests read it.
    @ObservationIgnored private(set) var pollTask: Task<Void, Never>?
    /// Counts `observeStatus()` calls: an older call that returns after a newer one started leaves the state alone.
    @ObservationIgnored private var pollGeneration = 0
    /// In-flight `tmutil startbackup` / `stopbackup` runs, keyed by start order: a start may still be running when the
    /// poll has already moved on and the user presses Stop or retries. Each drops its own entry; `stop()` cancels all.
    @ObservationIgnored private(set) var commandTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextCommandID = 0
    /// The in-flight destination re-read; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?

    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies = .live) {
        self.host = host; self.time = time; self.deps = deps
    }

    // MARK: - Status poll

    /// REDESIGN-BACKUPS D2/D3: awaited by BackupsPage's `.task`; returns when that task is cancelled (the page left) or
    /// `stop()` cancels the poll. Spawns `tmutil status` only for the first probe, while a backup runs, or while a
    /// start/stop is in flight, and never while the app is paused (`no-unseen-work`). 2 s between samples.
    func observeStatus() async {
        guard !VisualFixture.isRequested else { return }   // fixture data only; never spawn tmutil (HIDDEN-CONTENT-WORK)
        pollTask?.cancel()                                  // one poll at a time: the newest page visit owns it
        pollGeneration += 1
        let generation = pollGeneration
        let task: Task<Void, Never> = Task { [weak self] in await self?.poll() }
        pollTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard generation == pollGeneration else { return }  // a newer observeStatus() owns the state now
        pollTask = nil
        backup = nil
        if case .failed = action { action = .idle }
    }

    private func poll() async {
        var pollsSinceStart = 0
        while !Task.isCancelled {
            let needed = backup == nil || backup?.running == true || action == .starting || action == .stopping
            if needed && !host.isPaused() {
                let outcome = await deps.status()
                guard !Task.isCancelled else { return }
                let wasRunning = backup?.running == true
                let sample = outcome.nonEmptyText.flatMap { TimeMachineStatus.parse(text: $0) } ?? .idle
                if backup != sample { backup = sample }
                switch action {
                case .starting:
                    if sample.running { action = .idle; pollsSinceStart = 0 }
                    else { pollsSinceStart += 1; if pollsSinceStart >= 5 { action = .failed(L.bkStartDidNotBegin); pollsSinceStart = 0 } }
                case .stopping:
                    if !sample.running { action = .idle }
                default: break
                }
                if wasRunning && !sample.running { refreshNow() }
            }
            await time.sleep(.seconds(2))
        }
    }

    // MARK: - Back up now / Stop

    /// REDESIGN-BACKUPS R3: `tmutil startbackup` (no root per tmutil(8)); the poll confirms it began.
    func startBackupNow() {
        switch action { case .idle, .failed: break; case .starting, .stopping: return }   // a failed attempt may be retried
        guard case .some(.some(let dest)) = host.read().tmDest, dest.mountPoint != nil else { return }
        action = .starting
        runCommand("startbackup") { L.bkStartFailed($0) }
    }

    /// REDESIGN-BACKUPS R3: `tmutil stopbackup`; the poll clears `.stopping` once Running == 0.
    func stopBackupNow() {
        switch action { case .idle, .failed: break; case .starting, .stopping: return }   // a failed action is cleared by a new stop
        guard backup?.running == true else { return }
        action = .stopping
        runCommand("stopbackup") { L.bkStopFailed($0) }
    }

    /// Runs one tmutil verb as a Task this controller owns. Exit 0: the poll takes over (.starting → .idle / .failed,
    /// .stopping → .idle); otherwise `.failed` with the first stderr line. Cancelled by `stop()`: nothing is written.
    private func runCommand(_ verb: String, failed: @escaping @MainActor (String) -> String) {
        let id = nextCommandID
        nextCommandID += 1
        commandTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.commandTasks[id] = nil }
            let outcome = await self.deps.command(verb)
            guard !Task.isCancelled else { return }
            if case .exited(0) = outcome.termination { return }
            self.action = .failed(failed(Self.firstLine(outcome.stderrHead)))
        }
    }

    /// First non-blank line of a command's stderr, or a generic reason.
    private static func firstLine(_ s: String) -> String {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? L.bkFailedNoReason
    }

    // MARK: - Destination

    /// REDESIGN-BACKUPS: destination + local snapshots now (the poll calls it when a backup ends, e.g. after Stop).
    func refreshNow() {
        guard !refreshing else { return }
        refreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshing = false }
            let (dest, snapshots) = await self.deps.collect()
            guard !Task.isCancelled else { return }
            // A pass in flight would overwrite these sections with its own scan when it commits (ReportHost.awaitPassEnd).
            _ = await self.host.awaitPassEnd()
            guard !Task.isCancelled else { return }
            if let dest { self.host.write(\.tmDest, .some(dest)) }                  // nil = tmutil failed: keep the old value
            if let snapshots { self.host.write(\.snapshots, .some(snapshots)) }
            self.updatedAt = self.time.now()
            await self.host.refreshClaudeBackup()
            guard !Task.isCancelled else { return }
            self.host.reassess()                                                     // the committed report, never a partial
        }
    }

    /// The coordinator's report pass landed its Time Machine section (the pass writes `report` itself): stamp «updated».
    func markUpdated() { updatedAt = time.now() }

    /// A destination read outside a pass (SmartToolsController's 300 s sampler and `refreshNow()`): write it when it changed, stamp.
    /// A nil read is written as read — what those paths have always done (unlike `refreshNow()`'s keep-old rule).
    func recordDestination(_ dest: TMDestination??) {
        host.write(\.tmDest, dest)
        markUpdated()
    }

    // MARK: - Fixture, teardown

    /// Visual fixture only (REDESIGN-BACKUPS): the card's stamp and transient states (backing, stopping, failed start).
    func applyFixture(updatedAt: Date?, backup: TMBackupProgress?, action: TMActionState) {
        self.updatedAt = updatedAt; self.backup = backup; self.action = action
    }

    /// Cancels the poll, every in-flight start/stop command and the re-read; the coordinator's `stop()` calls it.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        for task in commandTasks.values { task.cancel() }
        commandTasks = [:]
        refreshTask?.cancel()
        refreshTask = nil
    }
}
