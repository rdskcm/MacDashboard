// Engine/BrewController.swift
// ARCH-MODEL-SPLIT block 2: the Homebrew state, moved out of the coordinator unchanged in behaviour.
// Owns the in-app `brew upgrade` (BREW-CANCEL Stop), the standalone re-check («Try again»), the session
// cache the report pass reuses (Block N5) and their Task handles.
import Foundation
import Observation

@MainActor
@Observable
final class BrewController {
    struct Dependencies {
        /// `BrewUpgrader.upgradeAll`: runs `brew upgrade`; cancelling the awaiting Task kills its process group.
        /// nil = brew exited 0, else a short localized failure line. `onProgress` may be called on any thread.
        var upgrade: @MainActor (_ totalOutdated: Int, _ onProgress: @escaping @Sendable (BrewProgress) -> Void) async -> String?
        /// `ReportCollector().collectBrewInfo(refreshIndex: false)` — a fresh collector per call, no index update.
        var collect: @MainActor () async -> BrewSnapshot

        static let live = Dependencies(
            upgrade: { total, onProgress in await BrewUpgrader.upgradeAll(totalOutdated: total, onProgress: onProgress) },
            collect: { await ReportCollector().collectBrewInfo(refreshIndex: false) })
    }

    /// Re-entrancy guard for `upgradeNow()`: true while an in-app `brew upgrade` (and its re-check) is in flight.
    private(set) var upgrading = false
    /// Set when the last `upgradeNow()` run failed; cleared at the start of the next run. Shown under the Homebrew
    /// section of the System page and on the Home attention card.
    private(set) var upgradeError: String? = nil
    /// Live `brew upgrade` progress while `upgrading` is true; nil otherwise.
    private(set) var progress: BrewProgress? = nil
    /// True only while the `brew upgrade` process itself runs (BREW-CANCEL): the one window in which Stop can act.
    /// False during the re-check that follows.
    private(set) var upgradeStoppable = false
    /// Set by `stopUpgrade()`; cleared when the run ends.
    private(set) var stopRequested = false
    /// Neutral outcome line of the last run the user stopped (BREW-CANCEL); cleared at the next run's start.
    private(set) var upgradeNotice: String? = nil
    /// When the session cache was filled; also the System page's «Checked today at HH:MM».
    private(set) var checkedAt: Date? = nil
    /// True while `refreshNow()` re-checks brew on its own (System page «Try again»).
    private(set) var refreshing = false

    /// Session cache (Block N5): the last good snapshot. Reused by the report pass within
    /// `ReportCollector.brewCacheWindow`, so a manual «Обновить отчёт» does not pay `brew update` + `brew outdated`
    /// every time. In-memory only.
    @ObservationIgnored private var cache: BrewSnapshot?
    /// The whole upgrade flow (brew step + re-check); `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var upgradeTask: Task<Void, Never>?
    /// The `brew upgrade` step only; the user's Stop cancels this.
    @ObservationIgnored private var upgradeRun: Task<String?, Never>?
    /// The standalone re-check; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?

    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies = .live) {
        self.host = host; self.time = time; self.deps = deps
    }

    // MARK: - Session cache (the report pass)

    /// The cached snapshot when it is fresh at `now` (age in [0, brewCacheWindow)), else nil = the pass runs brew.
    func cachedSnapshot(now: Date) -> BrewSnapshot? {
        ReportCollector.isBrewCacheFresh(collectedAt: checkedAt, now: now) ? cache : nil
    }

    /// Called by the pass when brew actually ran: refills the cache from the pass's final report, but never with a
    /// failed brew check (BREW-OUTDATED-FAIL, BREW-VERSION-FAIL) or a missing section — the next refresh retries it.
    func record(_ report: FullReport) {
        let failed = ReportCollector.brewCheckFailed(status: report.brewStatus, outdated: report.brewOutdated)
        if !failed, let status = report.brewStatus {
            cache = BrewSnapshot(status: status, outdated: report.brewOutdated,
                                 outdatedDetail: report.brewOutdatedDetail, installedCount: report.brewInstalledCount)
            checkedAt = time.now()
        } else {
            cache = nil
            checkedAt = nil
        }
    }

    // MARK: - Upgrade

    /// In-app Homebrew package upgrade («Обновить пакеты…» after its confirmation, or the advice chip). Runs
    /// `brew upgrade`, then re-collects a fresh snapshot so the card reflects the outcome whether it succeeded or not.
    /// The brew step runs in its own Task so Stop (`stopUpgrade()`) can end just that process; the re-check still runs.
    func upgradeNow() {
        guard !upgrading else { return }
        upgrading = true
        upgradeError = nil
        upgradeNotice = nil
        stopRequested = false
        progress = nil

        let before = host.read().brewOutdated ?? []
        let upgrade = deps.upgrade
        let onProgress: @Sendable (BrewProgress) -> Void = { p in
            Task { @MainActor [weak self] in self?.receive(p) }
        }
        let run = Task { await upgrade(before.count, onProgress) }
        upgradeRun = run
        upgradeStoppable = true

        upgradeTask = Task { [weak self] in
            guard let self else { run.cancel(); return }
            defer {
                self.upgrading = false
                self.progress = nil
                self.stopRequested = false
                self.upgradeStoppable = false
                self.upgradeRun = nil
            }

            // stop() cancels this task; forward that to the brew step (the user's Stop cancels only `run`).
            let error = await withTaskCancellationHandler { await run.value } onCancel: { run.cancel() }
            self.upgradeStoppable = false
            // A Stop counts only if brew had not already exited 0 before the signal landed.
            let stoppedByUser = self.stopRequested && error != nil
            guard !Task.isCancelled else { return }        // global teardown: no re-check, no write-back

            guard let info = await self.recollect() else { return }
            self.upgradeError = stoppedByUser ? nil : error
            self.upgradeNotice = stoppedByUser
                ? BrewUpgrader.stoppedNotice(before: before, after: info.outdated) : nil
        }
    }

    /// User Stop (BREW-CANCEL). Interrupts only the running `brew upgrade`: SIGINT to its process group, SIGKILL after
    /// BrewUpgrader's grace. `upgradeNow()`'s flow then re-checks brew so the card shows what really changed.
    /// No-op outside the brew step or after a first press.
    func stopUpgrade() {
        guard upgradeStoppable, !stopRequested, let run = upgradeRun else { return }
        stopRequested = true
        run.cancel()
    }

    /// A progress value from the brew step, already on the main actor. Dropped once the run has ended.
    private func receive(_ p: BrewProgress) {
        guard upgrading else { return }
        progress = p
    }

    // MARK: - Re-check

    /// Re-checks brew on its own (System page «Try again» after a failed check), without a full report pass:
    /// `refreshReport()` rebuilds every section blank for 10-30 s (assessment-complete-collect).
    func refreshNow() {
        guard !upgrading, !refreshing else { return }
        refreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshing = false }
            _ = await self.recollect()
        }
    }

    /// The re-check tail shared by `upgradeNow()` and `refreshNow()`: collect a fresh snapshot (no index update), wait
    /// for any report pass, write the four report fields and refill the cache. nil = cancelled (teardown): nothing written.
    private func recollect() async -> BrewSnapshot? {
        let info = await deps.collect()
        guard !Task.isCancelled else { return nil }

        // The collect that starts while `brew upgrade` runs captures the PRE-upgrade cached snapshot and would write it
        // over these values when it commits. Same reason the sibling updaters wait — see ReportHost.awaitPassEnd.
        _ = await host.awaitPassEnd()
        guard !Task.isCancelled else { return nil }

        host.update { report in
            report.brewStatus = info.status
            report.brewOutdated = info.outdated
            report.brewOutdatedDetail = info.outdatedDetail
            report.brewInstalledCount = info.installedCount
        }
        let failed = ReportCollector.brewCheckFailed(status: info.status, outdated: info.outdated)
        cache = failed ? nil : info
        checkedAt = failed ? nil : time.now()
        return info
    }

    // MARK: - Fixture, teardown

    /// Visual fixture only (REDESIGN-SYSTEM): the Homebrew card's transient state.
    func applyFixture(checkedAt: Date?, upgrading: Bool, progress: BrewProgress?, error: String?,
                      notice: String?, stoppable: Bool) {
        self.checkedAt = checkedAt; self.upgrading = upgrading; self.progress = progress
        upgradeError = error; upgradeNotice = notice; upgradeStoppable = stoppable
    }

    /// Cancels an in-flight upgrade (and its brew step) and an in-flight re-check; the coordinator's `stop()` calls it.
    func stop() {
        upgradeTask?.cancel()
        upgradeTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }
}
