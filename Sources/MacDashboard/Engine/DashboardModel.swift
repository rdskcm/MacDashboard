// Engine/DashboardModel.swift
// Integration phase (SPEC §3, §4): wires the real collectors (LiveCollector,
// ReportCollector, Assess, ReportWriter, HistoryStore) behind the observable
// contract the UI depends on. Starts empty/honest — no fabricated data — and
// fills in as collection completes, exactly like the on-disk report/history
// files behave.

import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class DashboardModel {
    // Per-field observable state (replaces the monolithic `live` snapshot). Each is
    // assigned under an equality guard in the live loop so a card reading only one
    // field doesn't re-render when an unrelated field changed — @Observable fires a
    // change notification on EVERY set regardless of equality, so the guard is what
    // makes the per-field split actually reduce re-renders.
    var load: [Double]? = nil
    var cpu: CPUUsage? = nil
    var mem: MemSnapshot? = nil
    var swap: SwapInfo? = nil
    var disk: DiskInfo? = nil
    var battery: BatteryInfo? = nil   // read by BatteryTile (falls back to report.battery)
    /// Block N7: rounded SOC die temperature (°C), max over valid PMU tdie sensors,
    /// sampled by the fast task via ThermalHIDReader (app-only private API). nil =
    /// unavailable (Intel / API failure) — CPUTile hides the segment (honest-empty).
    /// Stored pre-rounded to Int so the equality guard suppresses sub-degree jitter.
    var socTempC: Int? = nil
    var topCPU: [ProcEntry] = []
    var topMem: [ProcEntry] = []
    var lastSampleAt: Date = .init()
    let ncpu = ProcessInfo.processInfo.activeProcessorCount   // constant → not tracked

    /// Timestamp of the last SMART collection — launch report, manual refresh, or the
    /// periodic sampler, whichever most recently landed a `.smart` section — so the
    /// Диски card can show "обновлено HH:MM" from app start onward.
    var smartUpdatedAt: Date? = nil

    /// Re-entrancy guard for `refreshSmartNow()` (SPEC Block H follow-up): true while a
    /// manual SMART refresh is in flight, so the card's «Обновить» button can disable
    /// itself and avoid overlapping ReportCollector instances.
    var smartRefreshing = false

    /// Re-entrancy guard for `refreshEnergyNow()` (SPEC Block K), true while a
    /// manual energy (pmset) refresh is in flight — mirrors `smartRefreshing`.
    var energyRefreshing = false

    /// Re-entrancy guard for `refreshProcessesNow()`, true while a manual process-list
    /// refresh is in flight — mirrors `smartRefreshing`.
    var processesRefreshing = false

    /// Re-entrancy guard for `upgradeBrewNow()`, true while an in-app `brew upgrade`
    /// is in flight — mirrors `smartRefreshing`.
    var brewUpgrading = false

    /// Set when the last `upgradeBrewNow()` run failed; cleared at the start of the
    /// next run. Shown as an inline error under the Homebrew sub-section.
    var brewUpgradeError: String? = nil

    /// Live `brew upgrade` progress while `brewUpgrading` is true; nil otherwise.
    var brewProgress: BrewProgress? = nil

    /// Whether the SMART CLI toolchain (`smartctl`) is installed, installable via
    /// Homebrew, or blocked on Homebrew itself missing (Block N8). Recomputed
    /// whenever a fresh report lands and again after `installSmartmontoolsNow()`.
    var smartToolsState: ReportCollector.SmartToolsAvailability = .needsHomebrew

    /// Re-entrancy guard for `installSmartmontoolsNow()`, true while an in-app
    /// `brew install smartmontools` is in flight — mirrors `brewUpgrading`.
    var smartInstalling = false

    /// Set when the last `installSmartmontoolsNow()` run failed; cleared at the
    /// start of the next run. Shown as an inline error under the install button.
    var smartInstallError: String? = nil

    /// Re-entrancy guard for `enableFirewallNow()`, true while an in-app firewall
    /// enable (via `PrivilegedRunner`) is in flight — mirrors `smartRefreshing`.
    var firewallApplying = false

    /// Set when the last advice-card action (currently only `enableFirewallNow()`)
    /// failed; cleared at the start of the next run. Shown as an inline error on
    /// the Рекомендации card.
    var adviceActionError: String? = nil

    /// Paths of orphaned launchd plists currently being deleted (Автозагрузка card's
    /// "check for outdated" flow) — lets a per-row delete button show a spinner and
    /// stay disabled while its own delete is in flight, without blocking other rows.
    var deletingPlistPaths: Set<String> = []

    /// Set when the last `deleteOrphanPlist()` run failed; cleared at the start of
    /// the next run. Shown as an inline error on the Автозагрузка card.
    var plistDeleteError: String? = nil

    /// Paths whose most recent delete attempt did NOT remove the file — the user
    /// dismissed the Touch ID/admin prompt, the file op failed, validation
    /// rejected the path, or the outcome is simply unknown. The Автозагрузка card
    /// collapses a row optimistically the instant the user confirms (see
    /// `OrphanRow.onConfirm`); this is the ONLY signal that puts it back.
    /// Accumulates until the card acknowledges — see `PlistDeleteRestoreSignal`.
    private(set) var plistDeleteRestore = PlistDeleteRestoreSignal()

    /// Assembled on demand for the imperative report/assess/history code paths ONLY.
    /// MUST stay `private` — a VIEW reading this would re-register a dependency on every
    /// field and defeat the per-field observation split. (Views read the individual
    /// properties above instead.)
    private var live: LiveSnapshot {
        var s = LiveSnapshot()
        s.t = lastSampleAt; s.load = load; s.ncpu = ncpu; s.cpu = cpu
        s.topCPU = topCPU; s.topMem = topMem; s.mem = mem; s.swap = swap
        s.disk = disk; s.battery = battery
        return s
    }

    /// Imperative one-shot read of `live` for the AI sheet's payload builder. Views
    /// MUST NOT treat this as an observed/reactive binding — call it once when
    /// building the payload, not from a view body (see `live`'s doc comment above).
    func currentLiveSnapshot() -> LiveSnapshot { live }

    var cpuHistory: [(Date, Double)]  // last 60 points of user+sys for sparkline
    var report: FullReport            // sections fill in as collected

    /// Last non-nil `report.system`, retained across refreshes. `refreshReport()` rebuilds
    /// from a blank FullReport, so `report.system` is nil for most of every collect; the
    /// header reads this instead, so the subtitle does not collapse and the header's
    /// ViewThatFits does not swap branches mid-collect. Hardware/OS are static between
    /// passes. nil only before the very first successful collect.
    private(set) var lastKnownSystem: SystemInfo? = nil

    /// What the HEADER shows. Cards keep reading `report.system` directly.
    var headerSystem: SystemInfo? { report.system ?? lastKnownSystem }

    /// The report as it stood when the current collect started — i.e. the last fully
    /// collected one plus any out-of-band section writes (SMART task, firewall action).
    /// `refreshReport()` rebuilds from a blank FullReport, so `report` itself is a partial
    /// for most of a pass and must never be assessed (V2-HEADER-CHURN); the fast tick
    /// assesses THIS instead while a pass is in flight, so the report-derived checks stay
    /// frozen while the live-derived ones (disk, swap) keep updating (V2-HONEST-READINGS).
    /// Blank before the very first collect — which is correct: `Assess.assess` is total and
    /// stays silent on absent sections.
    private var lastCommittedReport = FullReport()

    var assessment: Assessment
    var history: HistoryState
    var reportText: String?           // rendered text report (for Отчёт tab)

    /// Timestamp of the report currently shown in the Отчёт tab: the on-disk file's
    /// mtime when a cached report was loaded at launch, or the completion time of the
    /// last successful collect(). Drives the «обновлено HH:MM» staleness caption.
    var reportUpdatedAt: Date? = nil

    var reportURL: URL                // fixed file path
    var isCollectingReport: Bool
    var lastError: String?

    /// Sibling of reportURL in the same App Support dir (SPEC §2).
    private let historyURL: URL
    /// The app is the only writer of the history file, so this in-memory instance
    /// (loaded once at init) is authoritative — no need to re-load it per refresh.
    private let historyStore: HistoryStore

    // Two independent live cadences (SPEC §5.1 decoupling): the fast task samples the
    // all-native gauges (~2s) while the slow task samples the `top` process tables
    // (~6s), so the responsive gauges no longer pay the ~1s `top` cost every tick.
    private var fastTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?
    private var smartTask: Task<Void, Never>?

    /// Session cache for the brew section (Block N5): last collected
    /// (version, outdated) and when. Reused by refreshReport() within
    /// ReportCollector.brewCacheWindow so a manual «Обновить отчёт» doesn't pay
    /// the ~30 s `brew outdated` cost every time. In-memory only.
    private var lastBrewInfo: (version: String??, outdated: [String]?)?
    private var lastBrewCollectedAt: Date?

    /// Set when refreshReport() is requested while a collect is already in flight
    /// (e.g. a language switch during the launch collect). The in-flight pass kicks
    /// off exactly one follow-up refresh on completion instead of silently dropping
    /// the request. Bool, not a counter: N coalesced requests → one follow-up.
    private var reportRefreshPending = false

    /// SMART re-check cadence (SPEC Block H): SMART attrs change slowly (wear level,
    /// reallocated sectors), so this is far slower than the fast (~2s) / slow (~6s)
    /// live gauges — a real-time refresh here would just spawn diskutil/smartctl
    /// for no benefit.
    private let smartRefreshInterval: Duration = .seconds(300)

    /// Set whenever there is no effectively visible, non-panel window on a frontmost
    /// app, so the live loop can skip the (relatively heavy — spawns `top` twice)
    /// collect() call and just keep sleeping, per SPEC §1.4 "pause timer when window
    /// closed / app hidden to save energy". Derived by `recomputeIsPaused()` from
    /// `NSApp.isActive` plus `NSApp.windows` visibility/occlusion state (excluding
    /// `NSPanel`s such as `HoverTip`'s tooltip panels, which should never keep the
    /// app un-paused). Recomputed on app activate/resign, window close (deferred one
    /// runloop turn since the closing window is still in `NSApp.windows` and still
    /// reports `isVisible == true` at the moment `willCloseNotification` fires),
    /// miniaturize/deminiaturize, and occlusion-state change. Registered once, from
    /// start(), directly on NSApplication's / NSWindow's notification center — this
    /// needs no changes to MacDashboardApp.swift / no ScenePhase plumbing.
    /// Also read (via @Observable tracking) by AutostartCard's breathing-badge
    /// gate, so the badge animation pauses/resumes together with the collectors.
    private(set) var isPaused = false
    private var activityObservers: [NSObjectProtocol] = []

    init() {
        cpuHistory = []
        report = FullReport()
        assessment = Assessment()
        reportText = nil
        isCollectingReport = false
        lastError = nil

        let url = Self.defaultReportURL()
        reportURL = url
        historyURL = url.deletingLastPathComponent().appendingPathComponent("mac_check_state.json")
        // Load synchronously so the История card has data as soon as the window
        // appears (empty HistoryState on first run is fine — HistoryStore.load()
        // never throws).
        historyStore = HistoryStore(url: historyURL)
        history = historyStore.load()
        smartToolsState = Self.recomputeSmartToolsState()
    }

    // MARK: - Lifecycle (SPEC §4 contract)

    func start() {
        guard fastTask == nil else { return }
        observeActivity()

        // Each task drives its OWN LiveCollector instance. LiveCollector isn't Sendable
        // (per its own doc comment: "NOT thread-safe — keep ONE instance and call
        // collect() from a single background context"), so the two tasks must NOT share
        // one — each boxes a private instance to cross into its DispatchQueue closure.
        // Only the fast task's collector calls readCPU, so it alone owns prevTicks and
        // produces a correct delta over the steady ~2s cadence.
        let fastBox = UncheckedSendableBox(LiveCollector())
        let procBox = UncheckedSendableBox(LiveCollector())

        // Fast task (~2s cadence, user-configurable — default 2 s, see AppSettings):
        // all-native gauges only. Never touches topCPU/topMem.
        fastTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                if self.isPaused {
                    try? await Task.sleep(for: .seconds(AppSettings.shared.fastIntervalSeconds))
                    continue
                }

                // collectFast() blocks briefly on syscalls — hop off the main actor for
                // it, then resume back on the main actor (this Task inherited MainActor
                // isolation from start(), so resuming the continuation lands here).
                let (snap, socTempC): (LiveSnapshot, Int?) = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let s = fastBox.value.collectFast()
                        // Block N7: same background hop — one HID pass costs ~50 ms.
                        let soc = ThermalSensors.socTemperature(
                            from: ThermalHIDReader.readTemperatureSensors())
                        continuation.resume(returning: (s, soc.map { Int($0.rounded()) }))
                    }
                }
                guard !Task.isCancelled else { return }

                // Guarded per-field assignment: skip the set (and its @Observable
                // notification) when the field is unchanged, so a card observing only
                // one field re-renders only when THAT field actually changed.
                if self.load    != snap.load    { self.load    = snap.load }
                if self.cpu     != snap.cpu     { self.cpu     = snap.cpu }
                if self.mem     != snap.mem     { self.mem     = snap.mem }
                if self.swap    != snap.swap    { self.swap    = snap.swap }
                if self.disk    != snap.disk    { self.disk    = snap.disk }
                if self.battery != snap.battery { self.battery = snap.battery }
                if self.socTempC != socTempC { self.socTempC = socTempC }
                self.lastSampleAt = snap.t
                if let cpu = snap.cpu {
                    self.cpuHistory.append((snap.t, cpu.user + cpu.sys))
                    if self.cpuHistory.count > 60 {
                        self.cpuHistory.removeFirst(self.cpuHistory.count - 60)
                    }
                }
                // `self.report` is a partial during a collect and a partial must never be
                // assessed — it would resurrect the header churn (V2-HEADER-CHURN). But the
                // live disk/swap readings are ready every tick, so instead of freezing the
                // whole verdict for the 10–30 s of a pass, assess the LAST COMMITTED report
                // together with the FRESH live snapshot: report-derived checks stay exactly
                // as they were when the pass started, live-derived ones keep moving
                // (V2-HONEST-READINGS, A11).
                let assessedReport = self.isCollectingReport ? self.lastCommittedReport : self.report
                self.setAssessment(Assess.assess(report: assessedReport, live: self.live))

                try? await Task.sleep(for: .seconds(AppSettings.shared.fastIntervalSeconds))
            }
        }

        // Slow task (~6s): the `top` process tables only. No setAssessment here — the
        // assessment depends only on disk/swap, which the fast task owns.
        slowTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                if self.isPaused {
                    try? await Task.sleep(for: .seconds(6))
                    continue
                }

                // sampleProcesses() runs `top` (~1s) — hop off the main actor for it.
                // Read the setting HERE, on the main actor, and pass it across: the
                // collector must not touch AppSettings.shared from a background queue.
                let limit = AppSettings.shared.processListLimit
                let procs = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume(returning: procBox.value.sampleProcesses(limit: limit))
                    }
                }
                guard !Task.isCancelled else { return }

                if self.topCPU != procs.topCPU { self.topCPU = procs.topCPU }
                if self.topMem != procs.topMem { self.topMem = procs.topMem }

                try? await Task.sleep(for: .seconds(6))
            }
        }

        // SMART task (~5 min): periodic re-check of disk health, independent of the
        // report/fast/slow cadences. Own ReportCollector instance — collectors aren't
        // shared across tasks (see fastBox/procBox comment above).
        let smartBox = UncheckedSendableBox(ReportCollector())
        smartTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // The launch report (refreshReport(), called below) just collected SMART,
                // so sleep first rather than re-checking immediately on start().
                try? await Task.sleep(for: self.smartRefreshInterval)
                guard !Task.isCancelled else { return }

                if self.isPaused {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }

                let (disks, tmDest): ([SmartDisk], TMDestination??) = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        let disks = smartBox.value.collectSmartDisks()
                        let tmDest = smartBox.value.collectTMDestInfo()
                        continuation.resume(returning: (disks, tmDest))
                    }
                }
                guard !Task.isCancelled else { return }

                // Assessment (smartSev) is recomputed from `self.report` every ~2s by the
                // fast task above, so a changed report.smart flows into it automatically —
                // no explicit setAssessment() call needed here.
                await self.waitForReportRefreshToFinish()
                guard !Task.isCancelled else { return }
                if self.report.smart != disks { self.report.smart = disks }
                if self.report.tmDest != tmDest { self.report.tmDest = tmDest }
                self.smartUpdatedAt = Date()
            }
        }

        loadCachedReportFromDisk()
        refreshReport()
    }

    /// Cold-launch disk cache (Block N5): if a report from a previous run exists on
    /// disk, show it in the Отчёт tab immediately (with a staleness caption) while
    /// the background collect() refreshes it. Raw text only — FullReport is not
    /// serialized, so the Обзор cards still fill in progressively from the live
    /// collect. Synchronous by design: the file is tens of KB and this runs once,
    /// before the first collect() is kicked off.
    private func loadCachedReportFromDisk() {
        guard reportText == nil else { return }
        guard let text = try? String(contentsOf: reportURL, encoding: .utf8),
              !text.isEmpty else { return }
        reportText = text
        reportUpdatedAt = try? reportURL.resourceValues(
            forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Cancels the live loop and any in-flight report collection, and stops observing
    /// app-activity notifications. Not currently called by the UI (single-window app
    /// whose lifetime matches the process), but kept as a clean shutdown path.
    func stop() {
        fastTask?.cancel()
        fastTask = nil
        slowTask?.cancel()
        slowTask = nil
        reportTask?.cancel()
        reportTask = nil
        smartTask?.cancel()
        smartTask = nil
        for observer in activityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        activityObservers.removeAll()
    }

    func refreshReport() {
        guard !isCollectingReport else { reportRefreshPending = true; return }
        reportTask?.cancel()
        // Snapshot BEFORE the collect wipes `report` section by section: this is what the
        // fast tick assesses for the duration of the pass (V2-HONEST-READINGS).
        lastCommittedReport = report
        isCollectingReport = true

        reportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isCollectingReport = false   // always clear, incl. cancellation
                if self.reportRefreshPending {
                    self.reportRefreshPending = false
                    // Don't relaunch from a cancelled task (stop() during shutdown).
                    if !Task.isCancelled { self.refreshReport() }
                }
            }

            let cachedBrew: (version: String??, outdated: [String]?)? =
                ReportCollector.isBrewCacheFresh(collectedAt: self.lastBrewCollectedAt, now: Date())
                    ? self.lastBrewInfo : nil
            let final = await ReportCollector().collect(skipSlow: false, cachedBrew: cachedBrew) { partial in
                // onSection is @MainActor; we're already isolated here. Detect the
                // .smart section's arrival by its progress-flag transition (false/absent
                // -> true) BEFORE overwriting self.report, so smartUpdatedAt reflects the
                // launch/manual report too, not only the periodic sampler.
                if partial.progress["smart"] == true, self.report.progress["smart"] != true {
                    self.smartUpdatedAt = Date()
                }
                self.report = partial
                if let sys = partial.system { self.lastKnownSystem = sys }
                // Deliberately NOT recomputed here: `partial` has most sections nil during
                // a collect, so assessing it makes "not collected yet" and "nothing is
                // wrong" the same value and the header thrashes between them. The verdict
                // updates once the pass completes, at the `final` assessment below.
                self.smartToolsState = Self.recomputeSmartToolsState()
            }
            guard !Task.isCancelled else { return }

            if cachedBrew == nil {
                // brew actually ran this pass — refill the session cache.
                self.lastBrewInfo = (final.brewVersion, final.brewOutdated)
                self.lastBrewCollectedAt = Date()
            }

            self.historyStore.upsertToday(from: final, live: self.live)
            do {
                try self.historyStore.save()
            } catch {
                self.lastError = L.errorHistorySaveFailed(error.localizedDescription)
            }
            self.history = self.historyStore.state

            let text = ReportWriter.render(report: final, live: self.live, history: self.historyStore.state)
            do {
                try ReportWriter.write(text: text, to: self.reportURL)
            } catch {
                self.lastError = L.errorReportWriteFailed(error.localizedDescription)
            }
            self.reportText = text
            self.reportUpdatedAt = Date()

            self.report = final
            if let sys = final.system { self.lastKnownSystem = sys }
            self.setAssessment(Assess.assess(report: final, live: self.live))
            self.smartToolsState = Self.recomputeSmartToolsState()
        }
    }

    /// Waits (cooperatively, polling) until no refreshReport() pass is in flight, so this
    /// updater's field write can't be clobbered by a subsequent onSection snapshot that
    /// hasn't collected this section in its own pass yet. Bounded so a stuck refresh can
    /// never starve this updater forever.
    private func waitForReportRefreshToFinish() async {
        var waited = 0
        while isCollectingReport && waited < 15_000 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 200
        }
    }

    /// Manual, on-demand SMART re-check (SPEC Block H follow-up), triggered by the
    /// «Обновить» button on the Диски card. Independent of the periodic smartTask
    /// sampler — a fresh ReportCollector instance is created per call, never shared
    /// with a concurrent sampler pass (see the fastBox/procBox/smartBox comment above).
    func refreshSmartNow() {
        guard !smartRefreshing else { return }
        smartRefreshing = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.smartRefreshing = false }

            let collectorBox = UncheckedSendableBox(ReportCollector())
            let (disks, tmDest): ([SmartDisk], TMDestination??) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let disks = collectorBox.value.collectSmartDisks()
                    let tmDest = collectorBox.value.collectTMDestInfo()
                    continuation.resume(returning: (disks, tmDest))
                }
            }
            guard !Task.isCancelled else { return }

            await self.waitForReportRefreshToFinish()
            guard !Task.isCancelled else { return }
            if self.report.smart != disks { self.report.smart = disks }
            if self.report.tmDest != tmDest { self.report.tmDest = tmDest }
            self.smartUpdatedAt = Date()
        }
    }

    /// Manual, on-demand energy (pmset) re-check (SPEC Block K), triggered after a
    /// batched `pmset` apply from the Energy card, so the table shows what the
    /// system actually accepted rather than the values we merely requested.
    /// Mirrors `refreshSmartNow()` exactly — a fresh ReportCollector instance is
    /// created per call, one-shot only (no sampler loop).
    func refreshEnergyNow() {
        guard !energyRefreshing else { return }
        energyRefreshing = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.energyRefreshing = false }

            let collectorBox = UncheckedSendableBox(ReportCollector())
            let settings: EnergySettings? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: collectorBox.value.collectEnergySettings())
                }
            }
            guard !Task.isCancelled else { return }

            await self.waitForReportRefreshToFinish()
            guard !Task.isCancelled else { return }
            if self.report.energy != settings { self.report.energy = settings }
        }
    }

    /// Manual, on-demand process-list re-sample (V2-SETTINGS-PROCLIMIT follow-up),
    /// triggered by the «Применить» button next to the process-limit setting so a
    /// limit change is visible immediately instead of waiting for the next ~6s slow
    /// tick. One-shot, independent of the periodic slowTask sampler — a fresh
    /// LiveCollector instance is created per call, never shared with a concurrent
    /// sampler pass (see the fastBox/procBox/smartBox comment in start()).
    func refreshProcessesNow() {
        guard !processesRefreshing else { return }
        processesRefreshing = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.processesRefreshing = false }

            let collectorBox = UncheckedSendableBox(LiveCollector())
            // Same rule as the slow task: read the setting on the main actor, pass it in.
            let limit = AppSettings.shared.processListLimit
            let procs = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: collectorBox.value.sampleProcesses(limit: limit))
                }
            }
            guard !Task.isCancelled else { return }

            if self.topCPU != procs.topCPU { self.topCPU = procs.topCPU }
            if self.topMem != procs.topMem { self.topMem = procs.topMem }
        }
    }

    /// In-app Homebrew package upgrade, triggered by the «Обновить пакеты» button
    /// on the Обслуживание системы card. Runs `brew upgrade` off-main, then
    /// re-collects a fresh Homebrew snapshot so the card reflects the outcome
    /// regardless of success or failure. Mirrors `refreshSmartNow()`.
    func upgradeBrewNow() {
        guard !brewUpgrading else { return }
        brewUpgrading = true
        brewUpgradeError = nil
        brewProgress = nil

        let total = report.brewOutdated?.count ?? 0

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.brewUpgrading = false
                self.brewProgress = nil
            }

            let collectorBox = UncheckedSendableBox(ReportCollector())
            let (error, info): (String?, (version: String??, outdated: [String]?)) =
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        let err = BrewUpgrader.upgradeAll(totalOutdated: total, onProgress: { progress in
                            DispatchQueue.main.async { [weak self] in self?.brewProgress = progress }
                        })
                        let fresh = collectorBox.value.collectBrewInfo()
                        continuation.resume(returning: (err, fresh))
                    }
                }
            guard !Task.isCancelled else { return }

            self.brewUpgradeError = error
            self.report.brewVersion = info.version
            self.report.brewOutdated = info.outdated
            self.lastBrewInfo = info
            self.lastBrewCollectedAt = Date()
        }
    }

    /// In-app `smartmontools` install, triggered by the install button on the Диски
    /// card when Homebrew is present but `smartctl` isn't (Block N8). Runs
    /// `brew install smartmontools` off-main (unprivileged — brew runs as the user,
    /// never via PrivilegedRunner), then re-probes `findSmartctl()`: on success,
    /// flips `smartToolsState` to `.installed` and re-collects external SMART via
    /// `refreshSmartNow()`; on failure, reports the last non-empty output line.
    /// Mirrors `upgradeBrewNow()`.
    func installSmartmontoolsNow() {
        guard !smartInstalling else { return }
        smartInstalling = true
        smartInstallError = nil

        Task { [weak self] in
            guard let self else { return }
            defer { self.smartInstalling = false }

            guard let brew = ReportCollector.findBrew() else {
                self.smartInstallError = L.storageSmartInstallFailed(L.maintenanceBrewUpgradeFailed)
                return
            }

            let lastLineBox = LastLineBox()
            _ = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let result = CommandRunner.runStreaming(
                        "/usr/bin/env",
                        ["HOMEBREW_NO_AUTO_UPDATE=1", brew, "install", "smartmontools"],
                        timeout: 600,
                        onLine: { line, _ in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { lastLineBox.value = trimmed }
                        })
                    continuation.resume(returning: result)
                }
            }
            guard !Task.isCancelled else { return }

            if ReportCollector.findSmartctl() != nil {
                self.smartToolsState = .installed
                self.smartInstallError = nil
                self.refreshSmartNow()
            } else {
                self.smartInstallError = L.storageSmartInstallFailed(lastLineBox.value)
            }
        }
    }

    /// In-app firewall enable, triggered by the confirmation dialog on the
    /// Рекомендации card's `.enableFirewall` advice row. Runs
    /// `socketfilterfw --setglobalstate on` via `PrivilegedRunner` (Touch ID / admin
    /// password) off-main, then re-collects security state so the row disappears the
    /// instant success lands, without waiting for the next fast tick. Mirrors
    /// `refreshSmartNow()`/`upgradeBrewNow()`.
    func enableFirewallNow() {
        guard !firewallApplying else { return }
        firewallApplying = true
        adviceActionError = nil

        Task { [weak self] in
            guard let self else { return }
            defer { self.firewallApplying = false }

            let outcome: PrivilegedRunner.Outcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: PrivilegedRunner.run(
                        "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"))
                }
            }
            guard !Task.isCancelled else { return }

            switch outcome {
            case .success:
                let collectorBox = UncheckedSendableBox(ReportCollector())
                let s: SecurityState = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        continuation.resume(returning: collectorBox.value.collectSecurityInfo())
                    }
                }
                guard !Task.isCancelled else { return }
                await self.waitForReportRefreshToFinish()
                guard !Task.isCancelled else { return }
                self.report.security = s
                self.setAssessment(Assess.assess(report: self.report, live: self.live))
            case .cancelled:
                break
            case .failed:
                self.adviceActionError = L.adviceFirewallError
            }
        }
    }

    /// Removes `paths` from `report.autostart`'s three plist arrays in place and
    /// recomputes the assessment, WITHOUT a full `refreshReport()` recollect.
    /// `refreshReport()` rebuilds from a blank `FullReport()` and streams sections
    /// back in one by one, so calling it just to drop a deleted plist from the list
    /// makes the whole Автозагрузка card (and every other section) flash through its
    /// "collecting" placeholder before repopulating — a disproportionate, ugly
    /// reset for a change this narrow. A local, targeted mutation lets SwiftUI's
    /// own array diffing (and this card's `.animation(value: orphans)`) animate
    /// just the removed row instead.
    private func removeAutostartPlistsLocally(_ paths: Set<String>) {
        guard var auto = report.autostart, !paths.isEmpty else { return }
        auto.userAgents.removeAll { paths.contains($0.path) }
        auto.systemAgents.removeAll { paths.contains($0.path) }
        auto.systemDaemons.removeAll { paths.contains($0.path) }
        report.autostart = auto
        setAssessment(Assess.assess(report: report, live: live))
    }

    /// Publishes `paths` as "these were not deleted, put the rows back". Unions
    /// into whatever the card has not drained yet and always bumps `stamp`, so an
    /// identical failure set twice in a row is still two distinct signals.
    private func signalPlistsNotDeleted(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        plistDeleteRestore = PlistDeleteRestoreSignal(
            paths: plistDeleteRestore.paths.union(paths),
            stamp: plistDeleteRestore.stamp &+ 1)
    }

    /// Called by the Автозагрузка card once it has restored `paths` (or decided
    /// they are genuinely gone). Draining here rather than clearing on publish is
    /// what makes two deletes landing in one update cycle safe.
    func acknowledgePlistRestore(_ paths: Set<String>) {
        guard !paths.isEmpty, !plistDeleteRestore.paths.isEmpty else { return }
        plistDeleteRestore = PlistDeleteRestoreSignal(
            paths: plistDeleteRestore.paths.subtracting(paths),
            stamp: plistDeleteRestore.stamp &+ 1)
    }

    /// Deletes an orphaned launchd .plist detected by the Автозагрузка card's
    /// "check for outdated" flow. `isSystemLevel` selects the deletion path:
    /// user-level (~/Library/LaunchAgents) goes to Trash via FileManager (reversible);
    /// system-level (/Library/LaunchAgents|LaunchDaemons) is a permanent `rm` via
    /// PrivilegedRunner (Touch ID/admin password), since Trash semantics don't apply
    /// across privilege boundaries. Neither unloads a currently-running agent/daemon
    /// (no `launchctl bootout` in v1) — the UI confirmation dialog must say so; the
    /// change takes effect after relogin/reboot. Removes the deleted entry from
    /// `report.autostart` locally on success (see `removeAutostartPlistsLocally`)
    /// so it drops out of the list without a full report recollect.
    func deleteOrphanPlist(path: String, isSystemLevel: Bool) {
        // A delete for this path is already in flight and owns the outcome —
        // signalling here would restore a row whose delete may still succeed.
        guard !deletingPlistPaths.contains(path) else { return }
        guard LaunchdPlistInspector.isValidDeletionTarget(path: path, isSystemLevel: isSystemLevel) else {
            plistDeleteError = "invalid plist path"
            signalPlistsNotDeleted([path])
            return
        }
        deletingPlistPaths.insert(path)
        plistDeleteError = nil

        Task { [weak self] in
            guard let self else { return }
            defer { self.deletingPlistPaths.remove(path) }

            let outcome: PlistDeleteOutcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    if isSystemLevel {
                        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
                        switch PrivilegedRunner.run("/bin/rm -f \(quoted)") {
                        case .success: continuation.resume(returning: .success)
                        case .cancelled: continuation.resume(returning: .cancelled)
                        case .failed(let msg): continuation.resume(returning: .failed(msg))
                        }
                    } else {
                        do {
                            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                            continuation.resume(returning: .success)
                        } catch {
                            continuation.resume(returning: .failed(error.localizedDescription))
                        }
                    }
                }
            }
            // An unknown outcome must never read as "deleted": put the row back. If the
            // file op did land, the next report refresh drops it again — showing a row
            // that no longer exists is recoverable, hiding one that does is not.
            guard !Task.isCancelled else {
                self.signalPlistsNotDeleted([path])
                return
            }

            switch outcome {
            case .success:
                self.removeAutostartPlistsLocally([path])
            case .cancelled:
                // User dismissed Touch ID/admin prompt — no error banner, but the row
                // must come back (finding A3).
                self.signalPlistsNotDeleted([path])
            case .failed(let msg):
                self.plistDeleteError = msg
                self.signalPlistsNotDeleted([path])
            }
        }
    }

    /// Bulk variant of `deleteOrphanPlist` (Автозагрузка card's "select multiple,
    /// delete all" flow). Deletes user-level (~/Library) plists first, each
    /// independently via Trash, so one failure doesn't block the rest; THEN — if any
    /// system-level (/Library) paths survive validation — issues exactly one
    /// `PrivilegedRunner` call covering an `rm -f` of all of them together, so the
    /// whole batch costs a single Touch ID/admin prompt instead of one per path. A
    /// cancelled or failed system-level batch never overwrites or hides the outcome
    /// of the user-level paths that already succeeded — every row's spinner is
    /// cleared independently and a combined error (if any) is reported once.
    func deleteOrphanPlists(paths: [String]) {
        let batch = paths.filter { path in
            guard !deletingPlistPaths.contains(path) else { return false }
            let isSystemLevel = path.hasPrefix("/Library/")
            return LaunchdPlistInspector.isValidDeletionTarget(path: path, isSystemLevel: isSystemLevel)
        }
        // Paths the card already collapsed that this call will never touch:
        // validation rejected them. Paths excluded because a delete is already in
        // flight are NOT signalled — that call owns their outcome.
        let inFlight = paths.filter { deletingPlistPaths.contains($0) }
        signalPlistsNotDeleted(Set(paths).subtracting(batch).subtracting(inFlight))
        guard !batch.isEmpty else { return }

        for path in batch { deletingPlistPaths.insert(path) }
        plistDeleteError = nil

        let userPaths = batch.filter { !$0.hasPrefix("/Library/") }
        let systemPaths = batch.filter { $0.hasPrefix("/Library/") }

        Task { [weak self] in
            guard let self else { return }
            defer {
                for path in batch { self.deletingPlistPaths.remove(path) }
            }

            var results: [(path: String, outcome: PlistDeleteOutcome)] = []

            // Everything in the batch whose delete is not a recorded success yet —
            // an unknown outcome must not read as "deleted" (same reasoning as the
            // single-path variant).
            func notRecordedAsDeleted() -> Set<String> {
                let succeeded = Set(results.compactMap { $0.outcome == .success ? $0.path : nil })
                return Set(batch).subtracting(succeeded)
            }

            for path in userPaths {
                let outcome: PlistDeleteOutcome = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                            continuation.resume(returning: .success)
                        } catch {
                            continuation.resume(returning: .failed(error.localizedDescription))
                        }
                    }
                }
                guard !Task.isCancelled else { self.signalPlistsNotDeleted(notRecordedAsDeleted()); return }
                results.append((path, outcome))
            }

            if !systemPaths.isEmpty {
                let command = "/bin/rm -f " + systemPaths.map { path in
                    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
                }.joined(separator: " ")

                let systemOutcome: PlistDeleteOutcome = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        switch PrivilegedRunner.run(command) {
                        case .success: continuation.resume(returning: .success)
                        case .cancelled: continuation.resume(returning: .cancelled)
                        case .failed(let msg): continuation.resume(returning: .failed(msg))
                        }
                    }
                }
                guard !Task.isCancelled else { self.signalPlistsNotDeleted(notRecordedAsDeleted()); return }
                for path in systemPaths { results.append((path, systemOutcome)) }
            }

            let failures = results.compactMap { result -> String? in
                if case .failed(let msg) = result.outcome { return msg }
                return nil
            }
            if let firstFailure = failures.first {
                self.plistDeleteError = failures.count > 1
                    ? "\(failures.count) of \(results.count) failed: \(firstFailure)"
                    : firstFailure
            }

            let succeededPaths = Set(results.compactMap { result -> String? in
                if case .success = result.outcome { return result.path }
                return nil
            })
            if !succeededPaths.isEmpty {
                self.removeAutostartPlistsLocally(succeededPaths)
            }
            self.signalPlistsNotDeleted(LaunchdPlistInspector.pathsNotDeleted(results: results))
        }
    }

    // MARK: - App-activity pause/resume (SPEC §1.4)

    /// Recomputes `isPaused` from `NSApp.isActive` plus whether at least one relevant
    /// (non-`NSPanel`) window is effectively visible (`isVisible` and occlusion state
    /// contains `.visible`). See doc comment on `isPaused` for the full rationale.
    private func recomputeIsPaused() {
        let hasVisibleWindow = NSApp.windows.contains { window in
            !(window is NSPanel) && window.isVisible && window.occlusionState.contains(.visible)
        }
        let paused = !(NSApp.isActive && hasVisibleWindow)
        if isPaused != paused { isPaused = paused }
    }

    private func observeActivity() {
        guard activityObservers.isEmpty else { return }
        let resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recomputeIsPaused() }
        }
        let become = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recomputeIsPaused() }
        }
        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Deferred one runloop turn: at the moment this notification fires,
                // the closing window is still in NSApp.windows and still reports
                // isVisible == true, so a synchronous recompute here would see stale
                // state.
                DispatchQueue.main.async { self?.recomputeIsPaused() }
            }
        }
        let miniaturize = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recomputeIsPaused() }
        }
        let deminiaturize = NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recomputeIsPaused() }
        }
        let occlusion = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recomputeIsPaused() }
        }
        activityObservers = [resign, become, willClose, miniaturize, deminiaturize, occlusion]
    }

    // MARK: - Report path

    /// Documented, narrowly-scoped `@unchecked Sendable` crossing for a type that is
    /// genuinely single-threaded-by-contract but not marked Sendable. See usage above.
    private final class UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    /// Mutable counterpart to `UncheckedSendableBox`, used by
    /// `installSmartmontoolsNow()` to capture the last non-empty `onLine` output while
    /// `CommandRunner.runStreaming` blocks synchronously on its own utility queue —
    /// there's no concurrent access since the mutation and the read-back both happen
    /// serially within that one blocking call.
    private final class LastLineBox: @unchecked Sendable {
        var value: String = ""
    }

    /// Suppresses redundant @Observable notifications when the new assessment
    /// is value-equal to the current one (e.g. repeated live ticks with no
    /// change in severity/tips/problems).
    private func setAssessment(_ n: Assessment) { if assessment != n { assessment = n } }

    /// Probes `findSmartctl()`/`findBrew()` fresh (cheap `isExecutableFile` checks,
    /// no process spawn) and maps them through `ReportCollector.smartToolsAvailability`.
    private static func recomputeSmartToolsState() -> ReportCollector.SmartToolsAvailability {
        ReportCollector.smartToolsAvailability(smartctl: ReportCollector.findSmartctl(),
                                                brew: ReportCollector.findBrew())
    }

    private static func defaultReportURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MacDashboard", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mac_report.txt")
    }
}
