// Engine/ClaudeBackupController.swift
// BACKUP-CARD-FAILURE: the Claude backup card's live state: the job, the last attempt, the disk, Back up now and its outcome.
// The poll exists only while BackupsPage awaits `observe()` (`no-unseen-work`).
import Foundation
import Observation

enum ClaudeBackupAction: Equatable, Sendable { case idle, starting, diskNotConnected, alreadyRunning, noResponse, launchFailed }

@MainActor
@Observable
final class ClaudeBackupController {
    struct Dependencies {
        var findJob: @MainActor () async -> ClaudeBackupJob?
        var readAttempt: @MainActor (_ now: Date) async -> ClaudeBackupAttempt?
        var readClickOutcome: @MainActor (_ since: Date) async -> ClaudeBackupClickOutcome?
        var launch: @MainActor (_ appPath: String) async -> CommandOutcome
        var pathExists: @MainActor (_ path: String) async -> Bool

        static func live(settings: AppSettings) -> Dependencies {
            Dependencies(
                findJob: { await ClaudeBackupJob.load() },
                readAttempt: { now in
                    let u = BackupLog.resolvedURLs(custom: settings.claudeLogPath)
                    return await BackupLog.readAttempt(logURL: u.log, rotatedURL: u.rotated, now: now)
                },
                readClickOutcome: { since in
                    await BackupLog.readClickOutcome(logURL: BackupLog.resolvedURLs(custom: settings.claudeLogPath).log, since: since)
                },
                launch: { app in await CommandRunner.run("/usr/bin/open", ClaudeBackupJob.launchArguments(appPath: app), timeout: 15, environment: ClaudeBackupJob.launchEnvironment) },
                pathExists: { await BackupLog.pathExists($0) })
        }
    }

    private(set) var job: ClaudeBackupJob? = nil
    private(set) var attempt: ClaudeBackupAttempt? = nil
    private(set) var diskConnected: Bool? = nil   // nil = unknown (no mount path in the log read)
    private(set) var action: ClaudeBackupAction = .idle

    /// The poll `observe()` runs and awaits; `stop()` cancels it. Tests read it.
    @ObservationIgnored private(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollGeneration = 0
    @ObservationIgnored private(set) var launchTask: Task<Void, Never>?
    @ObservationIgnored private var clickedAt: Date? = nil
    @ObservationIgnored private var startingPolls = 0
    @ObservationIgnored private var refreshDue = false

    static let tick: Duration = .seconds(2)
    static let runningTicks = 3     // 6 s
    static let idleTicks = 15       // 30 s
    static let clickTimeoutPolls = 15   // 30 s at one poll per tick

    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies) {
        self.host = host; self.time = time; self.deps = deps
    }

    /// Awaited by BackupsPage's `.task`; returns when that task is cancelled (the page left) or `stop()` runs.
    func observe() async {
        guard !VisualFixture.isRequested else { return }   // fixture data only; never read the real log or launch anything
        pollTask?.cancel()
        pollGeneration += 1
        let generation = pollGeneration
        let task: Task<Void, Never> = Task { [weak self] in await self?.poll() }
        pollTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard generation == pollGeneration else { return }
        pollTask = nil
        action = .idle      // a notice lives for this visit; the log tells the next visit what happened
        clickedAt = nil
    }

    private func poll() async {
        refreshDue = true
        var jobDue = true       // once per page visit: the plist and launchd's answer rarely change
        var ticks = 0
        while !Task.isCancelled {
            let every = action == .starting ? 1 : (attempt?.result == .running ? Self.runningTicks : Self.idleTicks)
            if (refreshDue || ticks >= every) && !host.isPaused() {
                refreshDue = false
                ticks = 0
                if jobDue { jobDue = false; await refreshJob() }
                await host.refreshClaudeBackup()     // AppModel re-reads the status and calls refreshAttempt()
                guard !Task.isCancelled else { return }
                await refreshDisk()
                guard !Task.isCancelled else { return }
                await resolveAction()
            }
            ticks += 1          // counts through a pause, so a read due during it runs right after resume
            await time.sleep(Self.tick)
        }
    }

    func refreshAttempt() async {
        let a = await deps.readAttempt(time.now())
        if attempt != a { attempt = a }
    }

    func refreshJob() async {
        let j = await deps.findJob()
        if job != j { job = j }
    }

    private func refreshDisk() async {
        var connected: Bool? = nil
        if let m = attempt?.mount { connected = await deps.pathExists(m) }
        if diskConnected != connected { diskConnected = connected }
    }

    /// Turns the log into the click's outcome, and clears a notice the log has overtaken.
    private func resolveAction() async {
        guard let since = clickedAt, action != .idle, action != .launchFailed else { return }
        if let a = attempt, a.at >= since { action = .idle; return }
        switch action {
        case .starting:
            if let o = await deps.readClickOutcome(since) {
                guard action == .starting else { return }
                action = o == .diskNotConnected ? .diskNotConnected : .alreadyRunning
                return
            }
            startingPolls += 1
            if startingPolls >= Self.clickTimeoutPolls, action == .starting { action = .noResponse }
        case .alreadyRunning:
            if attempt?.result != .running { action = .idle }
        default: break
        }
    }

    /// `open` starts the launcher through LaunchServices; the launcher stays up after a page leave and needs no cancelling here.
    func startBackupNow() {
        guard let app = job?.appPath, action != .starting, attempt?.result != .running else { return }
        action = .starting
        clickedAt = Date(timeIntervalSince1970: floor(time.now().timeIntervalSince1970))
        startingPolls = 0
        refreshDue = true
        launchTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.deps.launch(app)
            guard !Task.isCancelled, self.action == .starting else { return }
            if case .exited(0) = outcome.termination { return }
            self.action = .launchFailed
        }
    }

    /// DISK-MOUNT-LIVE's monitor: read at the next tick. No poll running = the flag is simply reset by the next visit.
    func volumesChanged() { refreshDue = true }

    /// Visual fixture only.
    func applyFixture(job: ClaudeBackupJob?, attempt: ClaudeBackupAttempt?, diskConnected: Bool?, action: ClaudeBackupAction) {
        self.job = job; self.attempt = attempt; self.diskConnected = diskConnected; self.action = action
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        launchTask?.cancel()
        launchTask = nil
    }
}
