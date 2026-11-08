// Engine/SmartToolsController.swift
// ARCH-MODEL-SPLIT block 5: the Storage page's disk-health (SMART) feature, moved out of the coordinator unchanged in
// behaviour. Owns the 300 s SMART sampler (SPEC Block H), the on-demand re-check, the in-app smartmontools install
// (Block N8), the smartctl/brew availability state, the Disks card's "updated HH:MM" stamp and their Task handles.
import Foundation
import Observation

@MainActor
@Observable
final class SmartToolsController {
    struct Dependencies {
        /// The SMART disks (`collectSmartDisks`) and the Time Machine destination (`collectTMDestInfo`; nil = tmutil
        /// failed), read through one fresh ReportCollector never shared with another reader.
        var collect: @MainActor () async -> (disks: [SmartDisk], tmDest: TMDestination??)
        /// `brew install smartmontools` with Homebrew's environment, 300 s timeout; the argument is brew's path.
        var install: @MainActor (_ brew: String) async -> CommandOutcome
        /// `ReportCollector.findSmartctl()` / `findBrew()`: `isExecutableFile` probes, no process spawn.
        var findSmartctl: @MainActor () -> String?
        var findBrew: @MainActor () -> String?
        /// Records a destination read outside a pass; the coordinator passes `timeMachine.recordDestination(_:)`.
        var markTMUpdated: @MainActor (TMDestination??) -> Void

        /// A function, not a `static let`: the Time Machine closure comes from the coordinator.
        static func live(markTMUpdated: @escaping @MainActor (TMDestination??) -> Void) -> Dependencies {
            Dependencies(
                collect: {
                    let collector = ReportCollector()
                    let disks = await collector.collectSmartDisks()
                    let tmDest = await collector.collectTMDestInfo()
                    return (disks, tmDest)
                },
                install: { brew in
                    // brew is a Homebrew-prefix script that shells out to its own helper binaries (ruby, git, curl, …)
                    // inside that prefix — same reason BrewUpgrader.upgradeAll and collectBrewInfo() build this env
                    // (V2-POLISH B1).
                    var env = CommandRunner.environment(prependingPATH: [(brew as NSString).deletingLastPathComponent])
                    // Formerly `/usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 brew …`; same variable, set directly (R0(c)).
                    env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
                    return await CommandRunner.run(brew, ["install", "smartmontools"], timeout: 300, environment: env)
                },
                findSmartctl: { ReportCollector.findSmartctl() },
                findBrew: { ReportCollector.findBrew() },
                markTMUpdated: markTMUpdated)
        }
    }

    /// SMART re-check cadence (SPEC Block H): SMART attributes change slowly (wear level, reallocated sectors), so this
    /// is far slower than the fast (~2 s) / slow (~6 s) live gauges — a real-time refresh would just spawn
    /// diskutil/smartctl for no benefit.
    static let samplerInterval: Duration = .seconds(300)

    /// Last SMART collection — the launch/manual pass, `refreshNow()` or the sampler, whichever landed last.
    private(set) var updatedAt: Date? = nil
    /// Whether `smartctl` is installed, installable via Homebrew, or blocked on Homebrew missing (Block N8).
    private(set) var toolsState: ReportCollector.SmartToolsAvailability = .needsHomebrew
    /// True while an in-app `brew install smartmontools` runs; the re-entrancy guard of `installNow()`.
    private(set) var installing = false
    /// The last `installNow()` failure; cleared when the next run starts. Typed so the page words it at render time.
    private(set) var installFailure: SmartInstallFailure? = nil
    /// Re-entrancy guard for `refreshNow()`: two re-check reads never overlap.
    private var refreshing = false

    /// The 300 s sampler `startSampling()` runs; `stop()` cancels it. Tests read it.
    @ObservationIgnored private(set) var samplerTask: Task<Void, Never>?
    /// The in-flight on-demand re-check; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?
    /// The in-flight install; `stop()` cancels it (CommandRunner kills brew's process group). Tests await it.
    @ObservationIgnored private(set) var installTask: Task<Void, Never>?
    /// The read plan of the newest volume event; a new event or `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var volumeReadTask: Task<Void, Never>?
    /// A volume event arrived while paused; `resumeVolumeRead()` consumes it (`no-unseen-work`).
    @ObservationIgnored private var volumeReadPending = false

    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies) {
        self.host = host; self.time = time; self.deps = deps
        recomputeToolsState()
    }

    // MARK: - Sampler

    /// Called by the coordinator's `start()`. Sleeps first: the launch pass has just collected SMART.
    func startSampling() {
        samplerTask?.cancel()                                   // one sampler at a time
        samplerTask = Task(priority: .utility) { [weak self] in await self?.sample() }
    }

    private func sample() async {
        while !Task.isCancelled {
            await time.sleep(Self.samplerInterval)
            guard !Task.isCancelled else { return }
            if host.isPaused() {                                // no-unseen-work: nothing spawns while paused
                await time.sleep(.seconds(2))
                continue
            }
            let collectSp = PerfSignposts.begin(PerfSignposts.smartCollect)
            let (disks, tmDest) = await CommandRunner.$qos.withValue(.utility) { await self.deps.collect() }
            collectSp.end()
            guard !Task.isCancelled else { return }
            let landSp = PerfSignposts.begin(PerfSignposts.smartLand)
            await land(disks: disks, tmDest: tmDest)
            landSp.end()
        }
    }

    // MARK: - Re-check, install

    /// On-demand SMART re-check, run by `installNow()` right after smartmontools is installed (the Disks card's
    /// "Refresh" button was removed in REFRESH-BUTTONS-AUDIT: the sampler re-reads the same data).
    func refreshNow() {
        guard !refreshing else { return }
        refreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshing = false }
            let (disks, tmDest) = await self.deps.collect()
            guard !Task.isCancelled else { return }
            await self.land(disks: disks, tmDest: tmDest)
        }
    }

    /// Lands one read after any in-flight pass (ReportHost.afterPass; a pass would overwrite `report.smart` when it commits).
    /// No re-assess: the fast tick assesses every ~2 s and reads the committed report this lands in.
    /// `keepOldOnFailedRead` (volume events): an empty disk list (disk0 is always listed) or a failed destination
    /// read leaves the old value, so a busy `diskutil` during a mount burst does not blank a card.
    private func land(disks: [SmartDisk], tmDest: TMDestination??, keepOldOnFailedRead: Bool = false) async {
        await host.refreshClaudeBackup()
        guard !Task.isCancelled else { return }
        host.afterPass { [weak self] in
            guard let self else { return }
            if !(keepOldOnFailedRead && disks.isEmpty) { self.host.write(\.smart, .some(disks)) }
            if !(keepOldOnFailedRead && tmDest == nil) { self.deps.markTMUpdated(tmDest) }
            self.updatedAt = self.time.now()
        }
    }

    /// In-app smartmontools install (Block N8), from the Disks card when Homebrew is present but smartctl isn't.
    /// Unprivileged — brew runs as the user, never via PrivilegedRunner. Success = smartctl is found afterwards:
    /// `.installed` and a SMART re-check; otherwise a typed failure (exit code, 300 s timeout, no brew).
    /// Mirrors `brew.upgradeNow()`.
    func installNow() {
        guard !installing else { return }
        installing = true
        installFailure = nil
        installTask = Task { [weak self] in
            guard let self else { return }
            defer { self.installing = false }   // also after a cancel (guard below): the button re-enables
            guard let brew = self.deps.findBrew() else { self.installFailure = .noBrew; return }
            let outcome = await self.deps.install(brew)
            guard !Task.isCancelled else { return }
            if self.deps.findSmartctl() != nil {
                self.toolsState = .installed
                self.installFailure = nil
                self.refreshNow()
            } else {
                switch outcome.termination {
                case .timedOut: self.installFailure = .timedOut
                case .exited(let code): self.installFailure = .exitCode(code)
                case .signaled, .launchFailed, .cancelled: self.installFailure = .exitCode(-1)
                }
            }
        }
    }

    // MARK: - Volume events (DISK-MOUNT-LIVE)

    /// A relevant volume mounted or unmounted (`VolumeEvents.isRelevant` already passed). The newest event restarts the
    /// plan (debounce, read, follow-up read), so a burst costs one plan. Paused: nothing spawns; `resumeVolumeRead()` reads.
    func volumesChanged() {
        volumeReadTask?.cancel()
        volumeReadTask = nil
        if host.isPaused() {
            volumeReadPending = true
            return
        }
        startVolumeReads(debounce: true)
    }

    /// The app resumed (`AppModel.setPaused(false)`): one plan if an event arrived meanwhile, with no debounce.
    func resumeVolumeRead() {
        guard volumeReadPending else { return }
        startVolumeReads(debounce: false)
    }

    private func startVolumeReads(debounce: Bool) {
        volumeReadPending = false
        volumeReadTask = Task { [weak self] in await self?.runVolumeReads(debounce: debounce) }
    }

    private func runVolumeReads(debounce: Bool) async {
        if debounce { await time.sleep(VolumeEvents.debounce) }
        guard await readVolumesOnce() else { return }
        await time.sleep(VolumeEvents.followUp)
        _ = await readVolumesOnce()
    }

    /// One read through the sampler's path. False ends the plan: superseded, stopped, or paused (pending again).
    private func readVolumesOnce() async -> Bool {
        guard !Task.isCancelled else { return false }
        if host.isPaused() {
            volumeReadPending = true
            return false
        }
        let (disks, tmDest) = await deps.collect()
        guard !Task.isCancelled else { return false }
        await land(disks: disks, tmDest: tmDest, keepOldOnFailedRead: true)
        return !Task.isCancelled
    }

    // MARK: - Pass hooks

    /// The coordinator's report pass landed its `.smart` section (the pass writes `report` itself): stamp «updated».
    func markUpdated() { updatedAt = time.now() }

    /// Re-probes smartctl/brew (file checks only) and writes the state only when it changed; the pass calls it at
    /// every section and at its end.
    func recomputeToolsState() {
        let state = ReportCollector.smartToolsAvailability(smartctl: deps.findSmartctl(), brew: deps.findBrew())
        if toolsState != state { toolsState = state }
    }

    // MARK: - Fixture, teardown

    /// Visual fixture only (REDESIGN-STORAGE): the card's stamp, the smartmontools state, the install flag and failure.
    func applyFixture(updatedAt: Date?, tools: ReportCollector.SmartToolsAvailability, installing: Bool,
                      failure: SmartInstallFailure?) {
        self.updatedAt = updatedAt; toolsState = tools; self.installing = installing; installFailure = failure
    }

    /// Cancels the sampler, the re-check, the install and the volume read; the coordinator's `stop()` calls it.
    func stop() {
        samplerTask?.cancel(); samplerTask = nil
        refreshTask?.cancel(); refreshTask = nil
        installTask?.cancel(); installTask = nil
        volumeReadTask?.cancel(); volumeReadTask = nil; volumeReadPending = false
    }
}
