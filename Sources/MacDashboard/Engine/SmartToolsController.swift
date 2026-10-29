// Engine/SmartToolsController.swift
// ARCH-MODEL-SPLIT block 5: the Storage page's disk-health (SMART) feature, moved out of the coordinator unchanged in
// behaviour. Owns the 300 s SMART sampler (SPEC Block H), the on-demand re-check, the in-app smartmontools install
// (Block N8), the smartctl/brew availability state, the Диски card's «updated HH:MM» stamp and their Task handles.
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
            let (disks, tmDest) = await CommandRunner.$qos.withValue(.utility) { await self.deps.collect() }
            guard !Task.isCancelled else { return }
            await land(disks: disks, tmDest: tmDest)
        }
    }

    // MARK: - Re-check, install

    /// On-demand SMART re-check, run by `installNow()` right after smartmontools is installed (the Диски card's
    /// «Обновить» button was removed in REFRESH-BUTTONS-AUDIT: the sampler re-reads the same data).
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

    /// Lands one read after the in-flight pass has ended (a pass would overwrite `report.smart` when it commits).
    /// No re-assess: the fast tick assesses every ~2 s, and `report.smart` is committed before it because this waits.
    private func land(disks: [SmartDisk], tmDest: TMDestination??) async {
        _ = await host.awaitPassEnd()
        guard !Task.isCancelled else { return }
        host.write(\.smart, .some(disks))
        deps.markTMUpdated(tmDest)
        await host.refreshClaudeBackup()
        guard !Task.isCancelled else { return }
        updatedAt = time.now()
    }

    /// In-app smartmontools install (Block N8), from the Диски card when Homebrew is present but smartctl isn't.
    /// Unprivileged — brew runs as the user, never via PrivilegedRunner. Success = smartctl is found afterwards:
    /// `.installed` and a SMART re-check; otherwise a typed failure (exit code, 300 s timeout, no brew).
    /// Mirrors `brew.upgradeNow()`.
    func installNow() {
        guard !installing else { return }
        installing = true
        installFailure = nil
        installTask = Task { [weak self] in
            guard let self else { return }
            defer { self.installing = false }
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

    /// Cancels the sampler, the re-check and the install; the coordinator's `stop()` calls it.
    func stop() {
        samplerTask?.cancel(); samplerTask = nil
        refreshTask?.cancel(); refreshTask = nil
        installTask?.cancel(); installTask = nil
    }
}
