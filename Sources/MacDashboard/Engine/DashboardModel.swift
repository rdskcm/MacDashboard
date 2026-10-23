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
    var battery: BatteryInfo? = nil   // Home battery tile / Now cell (falls back to report.battery)
    /// Block N7: rounded SOC die temperature (°C), max over valid PMU tdie sensors,
    /// sampled by the fast task via ThermalHIDReader (app-only private API). nil =
    /// unavailable (Intel / API failure) — the CPU page shows «—» (honest-empty).
    /// Stored pre-rounded to Int so the equality guard suppresses sub-degree jitter.
    var socTempC: Int? = nil
    var topCPU: [ProcEntry] = []
    var topMem: [ProcEntry] = []
    /// REDESIGN-HOME: rows of the last full ps snapshot (Home CPU tile «Processes»); nil before the first slow sample.
    var processCount: Int? = nil
    /// REDESIGN-CPU: start of the current run of CPU samples >= CPULoad.highUsagePct; nil when the latest sample is below it.
    private(set) var cpuHighSince: Date? = nil
    @ObservationIgnored private var lastCPUSampleAt: Date? = nil
    var lastSampleAt: Date = .init()
    /// REDESIGN-FOUNDATION: per-block loading / ok / failed state (Engine/BlockState.swift), read
    /// through `blockState(_:)`. One property per block so a view observing one is not
    /// re-rendered by another. Not rendered yet — the page stages consume it.
    private(set) var cpuBlock = BlockState(.cpu)
    private(set) var memoryBlock = BlockState(.memory)
    private(set) var foldersBlock = BlockState(.folders)
    private(set) var scanBlock = BlockState(.scan)
    private(set) var batteryBlock = BlockState(.battery)
    /// REDESIGN-BATTERY: the last successful `ioreg` read; kept through failures (the page's «last saved values», D5).
    /// nil until the Battery page's first successful read.
    var batteryDetail: BatteryDetail? = nil
    /// True while `readBatteryNow` awaits ioreg (re-entrancy guard, D2).
    private(set) var batteryReading = false
    let ncpu = ProcessInfo.processInfo.activeProcessorCount   // constant → not tracked

    /// Timestamp of the last SMART collection — launch report, manual refresh, or the
    /// periodic sampler, whichever most recently landed a `.smart` section — so the
    /// Диски card can show "обновлено HH:MM" from app start onward.
    var smartUpdatedAt: Date? = nil

    /// BACKUP-AGE: newest successful Claude backup per its log; nil = no log on this Mac (show nothing). Refreshed on the SMART cadence.
    var claudeBackup: ClaudeBackupStatus? = nil

    /// VISUAL-HARNESS-STALE: visual fixture only — the instant that backup-age displays and
    /// assessments treat as "now", so fixture captures do not depend on the wall clock. nil = wall clock.
    var fixtureNow: Date? = nil

    /// REDESIGN-BACKUPS: last `tmutil status` sample while the Backups page polls; nil = not probed on this visit.
    private(set) var tmBackup: TMBackupProgress? = nil
    /// REDESIGN-BACKUPS: in-flight / last-failed Back up now / Stop.
    private(set) var tmAction: TMActionState = .idle
    /// REDESIGN-BACKUPS: when the Time Machine destination was last (re)collected — the card's «updated HH:MM».
    var tmUpdatedAt: Date? = nil
    /// REDESIGN-BACKUPS: a page asks the Settings window to open on this section; SettingsView consumes and clears it.
    var settingsSectionRequest: SettingsSection? = nil
    private var tmRefreshing = false

    /// Re-entrancy guard for `refreshSmartNow()` (SPEC Block H follow-up): true while a
    /// manual SMART refresh is in flight, so the card's «Обновить» button can disable
    /// itself and avoid overlapping ReportCollector instances.
    var smartRefreshing = false

    /// Re-entrancy guard for `refreshEnergyNow()` (SPEC Block K), true while a
    /// manual energy (pmset) refresh is in flight — mirrors `smartRefreshing`.
    var energyRefreshing = false
    /// Set by a `refreshEnergy()` call that arrives while a read is in flight; the in-flight call reads again.
    private var energyReadNeeded = false

    /// Re-entrancy guard for `refreshProcessesNow()`, true while a manual process-list
    /// refresh is in flight — mirrors `smartRefreshing`.
    var processesRefreshing = false

    /// True while refreshCPUNow() runs (CPU page «Try again»).
    private(set) var cpuRefreshing = false

    /// REDESIGN-MEMORY: Memory page Refresh / Try again in flight.
    private(set) var memoryRefreshing = false

    /// Re-entrancy guard for `upgradeBrewNow()`, true while an in-app `brew upgrade`
    /// is in flight — mirrors `smartRefreshing`.
    var brewUpgrading = false

    /// Set when the last `upgradeBrewNow()` run failed; cleared at the start of the
    /// next run. Shown as an inline error under the Homebrew sub-section of the
    /// Обслуживание card and in the Рекомендации (Advice) card's error area.
    var brewUpgradeError: String? = nil

    /// Live `brew upgrade` progress while `brewUpgrading` is true; nil otherwise.
    var brewProgress: BrewProgress? = nil

    /// True only while the `brew upgrade` process itself runs (BREW-CANCEL): the one window in
    /// which Stop can act. False during the re-check that follows.
    var brewUpgradeStoppable = false

    /// Set by `stopBrewUpgrade()`; cleared when the run ends.
    var brewStopRequested = false

    /// Neutral outcome line of the last run the user stopped (BREW-CANCEL); cleared at the next
    /// run's start. Not an error: shown in muted ink under the Homebrew section.
    var brewUpgradeNotice: String? = nil

    /// Whether the SMART CLI toolchain (`smartctl`) is installed, installable via
    /// Homebrew, or blocked on Homebrew itself missing (Block N8). Recomputed
    /// whenever a fresh report lands and again after `installSmartmontoolsNow()`.
    var smartToolsState: ReportCollector.SmartToolsAvailability = .needsHomebrew

    /// Re-entrancy guard for `installSmartmontoolsNow()`, true while an in-app
    /// `brew install smartmontools` is in flight — mirrors `brewUpgrading`.
    var smartInstalling = false

    /// Set when the last `installSmartmontoolsNow()` run failed; cleared at the
    /// start of the next run. Typed so the page words it (exit code, language) at render time.
    private(set) var smartInstallFailure: SmartInstallFailure? = nil

    /// REDESIGN-SECURITY: the one in-flight or last-failed privileged enable (firewall / Gatekeeper).
    /// One state is also the re-entrancy guard of `enableProtectionNow(_:)`.
    private(set) var securityAction: SecurityActionState = .idle
    var firewallApplying: Bool { if case .enabling(.firewall) = securityAction { return true }; return false }
    var gatekeeperApplying: Bool { if case .enabling(.gatekeeper) = securityAction { return true }; return false }
    /// REDESIGN-SECURITY: true while the page's Refresh re-collects security + crashes.
    private(set) var securityRefreshing = false

    /// Set when the last advice-card action (currently only `enableFirewallNow()`)
    /// failed; cleared at the start of the next run. Shown as an inline error on
    /// the Рекомендации card.
    var adviceActionError: String? = nil

    /// Paths of orphaned launchd plists currently being deleted (Автозагрузка card's
    /// "check for outdated" flow) — lets a per-row delete button show a spinner and
    /// stay disabled while its own delete is in flight, without blocking other rows.
    var deletingPlistPaths: Set<String> = []

    /// Set when the last `deleteOrphanPlist()` run failed, was cancelled or timed out; cleared at
    /// the start of the next run. Shown as an inline note on the Startup items card.
    private(set) var plistDeleteFailure: PrivilegedActionFailure? = nil

    /// REDESIGN-SYSTEM «Check for stale»: a re-scan of the startup items is running.
    private(set) var startupChecking = false
    /// When the last «Check for stale» finished; stale marks are shown only once this is set.
    private(set) var startupCheckedAt: Date? = nil
    /// Items removed on the Startup items card since the last check.
    private(set) var startupRemovedCount = 0

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
        s.parseFailures = procParseFailures + wakeParseFailures
        return s
    }

    /// Values for the short report (ReportWriter.render). `report` is the pass being committed; `assessment` must
    /// already be the one computed from it.
    private func reportSummaryInput(report: FullReport, generatedAt: Date) -> ReportSummaryInput {
        let merged = BatteryInfo.merged(live: battery, report: report.battery)
        let tasks = HomeModel.tasks(assessment, report: report, disk: disk, battery: battery)
        return ReportSummaryInput(
            generatedAt: generatedAt, system: report.system ?? lastKnownSystem,
            status: HomeModel.status(scan: HomeModel.scan(scanBlock), tasks: tasks), tasks: tasks,
            cpu: cpu, load: load, ncpu: ncpu, socTempC: socTempC,
            mem: mem, memPressure: memPressure, swap: swap, disk: disk,
            hasBattery: merged != nil, battery: merged,
            security: report.security, claudeBackup: claudeBackup, snapshotCount: report.snapshots?.count,
            now: fixtureNow ?? Date(), parseFailures: report.parseFailures + live.parseFailures,
            details: ReportDetails(report: report, live: live))
    }

    /// Renders, writes `mac_report.txt` and publishes the text. `reportUpdatedAt` is the caller's business.
    private func commitReportText(_ input: ReportSummaryInput) {
        let text = ReportWriter.render(input)
        do { try ReportWriter.write(text: text, to: reportURL) }
        catch { lastError = L.errorReportWriteFailed(error.localizedDescription) }
        reportText = text
    }

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

    /// What Home derives its wording from: the report the current assessment was computed from
    /// (`assessed(isCollectingReport ? lastCommittedReport : report)`), so task text and tile figures
    /// do not blank out while a pass wipes `report` section by section (`assessment-complete-collect`).
    var homeReport: FullReport { isCollectingReport ? lastCommittedReport : report }

    /// The report as it stood when the current collect started — i.e. the last fully
    /// collected one plus any out-of-band section writes (SMART task, firewall action).
    /// `refreshReport()` rebuilds from a blank FullReport, so `report` itself is a partial
    /// for most of a pass and must never be assessed (V2-HEADER-CHURN); the fast tick
    /// assesses THIS instead while a pass is in flight, so the report-derived checks stay
    /// frozen while the live-derived ones (disk, swap) keep updating (V2-HONEST-READINGS).
    /// Blank before the very first collect — which is correct: `Assess.assess` is total and
    /// stays silent on absent sections.
    private var lastCommittedReport = FullReport()
    /// ps/top output the parser rejected on the most recent process sample (R3-FIXTURES).
    private var procParseFailures: [ParseFailure] = []
    /// The system's own memory-pressure verdict (TIPS-MEMORY), read on the fast tick.
    private(set) var memPressure: MemoryPressureLevel? = nil
    /// False until the fast task's first sample after start(): that sample only primes the CPU
    /// tick delta (`cpu == nil` by design), so it is no verdict on the cpu block.
    @ObservationIgnored private var fastSamplePrimed = false
    /// Top apps by memory footprint, from the most recent process sample (TIPS-MEMORY).
    private var topApps: [AppMemory] = []
    /// Non-system programs holding a sleep assertion ≥ 5 min, from the slow task (WAKE-HOLDERS).
    private(set) var wakeHolders: [WakeHolder] = []
    /// OS services holding a sleep assertion ≥ 5 min (REDESIGN-SYSTEM): listed on the System page, never warned about.
    private(set) var systemWakeHolders: [WakeHolder] = []
    /// True after the first `pmset -g assertions` sample returned, whatever its result.
    private(set) var wakeSampled = false
    /// pmset-assertions output the parser rejected on the last slow tick. Separate from
    /// procParseFailures so refreshProcessesNow() (which overwrites that) cannot drop it.
    private var wakeParseFailures: [ParseFailure] = []

    var assessment: Assessment
    var history: HistoryState {
        didSet { homeHistoryDigest = HomeModel.historyDigest(history.mac_history) }
    }
    /// History figures for the Home History tile, recomputed only when `history` changes (not on live ticks).
    private(set) var homeHistoryDigest = HomeHistoryDigest.empty
    /// REDESIGN-HISTORY: the last load found a file that exists but cannot be read as a history object
    /// (`HistoryStore.fileUnreadable`); the History page shows its error block until a reload or a save clears it.
    private(set) var historyUnreadable = false
    /// REDESIGN-HISTORY: `refreshHistoryNow()` in flight (the read takes milliseconds; the flag exists for the
    /// button's swap-in-place label and the visual fixture).
    private(set) var historyRefreshing = false
    var reportText: String?           // rendered text report (for the Report sheet)

    /// Timestamp of the report currently shown in the Report sheet: the on-disk file's
    /// mtime when a cached report was loaded at launch, or the completion time of the
    /// last successful collect(). Drives the «обновлено HH:MM» staleness caption.
    var reportUpdatedAt: Date? = nil

    var reportURL: URL                // fixed file path
    var isCollectingReport: Bool
    var lastError: String?

    /// Sibling of reportURL in the same App Support dir (SPEC §2).
    private let historyURL: URL
    /// The app is the only writer of the history file; this in-memory instance is loaded at init and
    /// re-read only by `refreshHistoryNow()` (the History page's Refresh / Try again).
    private let historyStore: HistoryStore

    // Two independent live cadences (SPEC §5.1 decoupling): the fast task samples the
    // all-native gauges (~2s) while the slow task samples the `top` process tables
    // (~6s), so the responsive gauges no longer pay the ~1s `top` cost every tick.
    private var fastTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?
    private var smartTask: Task<Void, Never>?
    private var brewUpgradeTask: Task<Void, Never>?
    private var brewUpgradeRun: Task<String?, Never>?   // the `brew upgrade` step only; user Stop cancels this
    /// One watchdog per armed block (`beginBlock`); cancelled when the block gets a verdict.
    @ObservationIgnored private var blockWatchdogs: [BlockID: Task<Void, Never>] = [:]

    /// Session cache for the brew section (Block N5): last collected
    /// snapshot (status, outdated, versions, count) and when. Reused by refreshReport() within
    /// ReportCollector.brewCacheWindow so a manual «Обновить отчёт» doesn't pay
    /// the `brew update` + `brew outdated` cost every time. In-memory only.
    private var lastBrewInfo: BrewSnapshot?
    /// When the cache was filled; also the System page's «Checked today at HH:MM».
    private(set) var brewCheckedAt: Date?
    /// True while `refreshBrewNow()` re-checks brew on its own (System page «Try again»).
    private(set) var brewRefreshing = false

    /// Set when refreshReport() is requested while a collect is already in flight
    /// (e.g. a language switch during the launch collect). The in-flight pass kicks
    /// off exactly one follow-up refresh on completion instead of silently dropping
    /// the request. Not a counter: N coalesced requests → one follow-up. nil = none;
    /// `.button` wins when merged (CollectTrigger.merged).
    private var reportRefreshPending: CollectTrigger? = nil

    /// Last successful macOS update check, persisted (COLLECT-FASTPATH). Source of truth for
    /// report.updates/updatesCheckedAt/updatesCheckDuration — applied by applyUpdates(to:).
    private var updatesCache: UpdatesCache?
    private let updatesCacheURL: URL
    private var updateCheckTask: Task<Void, Never>?
    private(set) var isCheckingUpdates = false
    private var updateCheckGeneration = 0
    /// Last successful background folder-size count (SIZES-BACKGROUND). Source of truth for
    /// report.homeDirs/serviceDirs/…Unreadable/folderSizesCountedAt — applied by applyFolderSizes(to:).
    private var folderSizes: FolderSizes?
    private let folderSizesURL: URL
    private var sizeCountTask: Task<Void, Never>?
    private var sizeScheduleTask: Task<Void, Never>?
    private(set) var isCountingSizes = false
    /// REDESIGN-STORAGE: set by `trashWasEmptied()`, cleared by the next successful count. The page caption reads them.
    private(set) var trashFreedBytes: Int64?
    private(set) var trashEmptiedAt: Date?
    /// REDESIGN-STORAGE D13: protected locations the last probe found refused (no Full Disk Access).
    private(set) var fdaDenied: [ProtectedLocation] = []
    /// REDESIGN-STORAGE D14: «Open Privacy settings…» was pressed and the user has not come back yet.
    private(set) var fdaAwaitingReturn = false
    private var sizeCountGeneration = 0
    /// Wall time the last folder-size count finished without a result (SIZES-FAIL-BACKOFF).
    /// Automatic triggers wait the 1 h window after it; the button does not. In-memory only:
    /// a relaunch makes one fresh attempt. Cleared by a successful count.
    private var sizeCountFailedAt: Date?

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
    /// Read only inside this model (the collector loops skip their work while it is true).
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
        let loadedHistory = historyStore.load()
        history = loadedHistory
        homeHistoryDigest = HomeModel.historyDigest(loadedHistory.mac_history)
        historyUnreadable = historyStore.fileUnreadable
        updatesCacheURL = url.deletingLastPathComponent().appendingPathComponent("updates_cache.json")
        updatesCache = UpdatesCacheStore.load(from: updatesCacheURL)
        folderSizesURL = url.deletingLastPathComponent().appendingPathComponent("folder_sizes_cache.json")
        folderSizes = FolderSizesCacheStore.load(from: folderSizesURL)
        smartToolsState = Self.recomputeSmartToolsState()
        if let countedAt = folderSizes?.countedAt { foldersBlock.succeed(at: countedAt) }   // cached count = last good
    }

    // MARK: - History restart notice (HISTORY-UNREADABLE-NOTICE)

    /// Where the notice's Finder button points: the kept unreadable file, or the folder it was
    /// kept in if the user has since moved or deleted it. nil when there is no notice. Stats
    /// the disk — call it from the button action only, never from a view body.
    var historyRestartRevealPath: String? {
        guard let name = history.unreadable_backup else { return nil }
        let dir = historyURL.deletingLastPathComponent()
        let file = dir.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: file) ? file : dir.path
    }

    /// The user hid the notice: forget it and persist that now, so it stays hidden after a
    /// relaunch. If the write fails the notice is still hidden for this session, and the next
    /// completed pass's save() persists the change.
    func dismissHistoryRestartNotice() {
        historyStore.clearUnreadableBackup()
        do {
            try historyStore.save()
        } catch {
            lastError = L.errorHistorySaveFailed(error.localizedDescription)
        }
        history = historyStore.state
    }

    /// REDESIGN-HISTORY: the History page's Refresh and the error block's Try again. Re-reads the file
    /// synchronously (the store is main-actor state; the file is ~50 KB) — a file restored from a backup or
    /// made readable again shows at once. Never writes.
    func refreshHistoryNow() {
        guard !historyRefreshing else { return }
        historyRefreshing = true
        history = historyStore.load()
        historyUnreadable = historyStore.fileUnreadable
        historyRefreshing = false
    }

    /// Display path of the history file for the error block («~/Library/Application Support/MacDashboard/mac_check_state.json»).
    var historyFilePath: String { (historyURL.path as NSString).abbreviatingWithTildeInPath }

    /// Visual fixture only (REDESIGN-HISTORY): the unreadable-file and reload-in-flight flags.
    func applyFixtureHistory(unreadable: Bool, refreshing: Bool) { historyUnreadable = unreadable; historyRefreshing = refreshing }

    /// BACKUP-AGE: re-read the backup log off the main actor; guarded so an unchanged status notifies nobody.
    func refreshClaudeBackup() async {
        let s = await BackupLog.readStatus()
        if claudeBackup != s { claudeBackup = s }
    }

    /// BACKUP-AGE: change the stale limit and re-assess now (same report choice as the fast tick).
    func setBackupStaleHours(_ hours: Int) {
        guard AppSettings.allowedBackupStaleHours.contains(hours),
              AppSettings.shared.backupStaleHours != hours else { return }
        AppSettings.shared.backupStaleHours = hours
        setAssessment(assessed(isCollectingReport ? lastCommittedReport : report))
    }

    /// SLEEP-IGNORE-APP: add (`ignored: true`) or remove a holder from the Sleep item's
    /// ignore list and re-assess now rather than on the next fast tick (which does not run
    /// while paused). Same report choice as the fast tick: never a partial (V2-HEADER-CHURN).
    func setWakeHolderIgnored(_ key: WakeHolderKey, ignored: Bool) {
        var list = AppSettings.shared.ignoredWakeHolderEntries
        if ignored {
            guard !list.contains(where: { $0.key == key }) else { return }
            list.append(IgnoredWakeHolder(key: key, since: Date()))
        } else {
            guard list.contains(where: { $0.key == key }) else { return }
            list.removeAll { $0.key == key }
        }
        AppSettings.shared.ignoredWakeHolderEntries = list
        setAssessment(assessed(isCollectingReport ? lastCommittedReport : report))
    }

    // MARK: - Block states (REDESIGN-FOUNDATION)

    /// Loading / ok / failed state of one data block (handoff 00 §4.16).
    func blockState(_ id: BlockID) -> BlockState {
        switch id {
        case .cpu: return cpuBlock
        case .memory: return memoryBlock
        case .folders: return foldersBlock
        case .scan: return scanBlock
        case .battery: return batteryBlock
        }
    }

    /// Applies `change` and assigns only when the state actually changed (one notification per change).
    private func updateBlock(_ id: BlockID, _ change: (inout BlockState) -> Void) {
        var next = blockState(id)
        change(&next)
        guard next != blockState(id) else { return }
        switch id {
        case .cpu: cpuBlock = next
        case .memory: memoryBlock = next
        case .folders: foldersBlock = next
        case .scan: scanBlock = next
        case .battery: batteryBlock = next
        }
    }

    /// Visual fixture only (DashboardModel+VisualFixture, tools/visual/content_states.swift): sets the scan block directly; live code never calls this.
    func applyFixtureScan(_ state: BlockState) { scanBlock = state }

    /// Visual fixture only: sets the CPU block and the high-load start.
    func applyFixtureCPU(_ state: BlockState, highSince: Date?) { cpuBlock = state; cpuHighSince = highSince }

    /// Visual fixture only: sets the memory-pressure level the Now card's Memory chip reads.
    func applyFixturePressure(_ p: MemoryPressureLevel?) { memPressure = p }

    /// Visual fixture only: sets the memory block.
    func applyFixtureMemory(_ state: BlockState) { memoryBlock = state }
    /// Visual fixture only (REDESIGN-BATTERY): the detail the Battery page shows and its block.
    func applyFixtureBattery(_ detail: BatteryDetail?, block: BlockState) { batteryDetail = detail; batteryBlock = block }

    /// Visual fixture only (REDESIGN-SYSTEM): the Sleep card's holders.
    func applyFixtureWakeHolders(user: [WakeHolder], system: [WakeHolder], sampled: Bool) {
        wakeHolders = user; systemWakeHolders = system; wakeSampled = sampled
    }

    /// Visual fixture only (REDESIGN-SECURITY): the privileged-action state, Refresh busy flag and update-check flag.
    func applyFixtureSecurity(action: SecurityActionState, refreshing: Bool = false, checkingUpdates: Bool = false) {
        securityAction = action; securityRefreshing = refreshing; isCheckingUpdates = checkingUpdates
    }

    /// REDESIGN-BACKUPS: snapshot states (backing, stopping, failed start).
    func applyFixtureTimeMachine(backup: TMBackupProgress?, action: TMActionState) { tmBackup = backup; tmAction = action }

    /// Visual fixture only (REDESIGN-STORAGE): smartmontools state, install-in-flight flag and typed failure.
    func applyFixtureSmartTools(_ state: ReportCollector.SmartToolsAvailability, installing: Bool, failure: SmartInstallFailure?) {
        smartToolsState = state; smartInstalling = installing; smartInstallFailure = failure
    }

    /// Visual fixture only (REDESIGN-STORAGE): the folder-count result and its block, re-applied to the shown report
    /// (nil sizes = no count yet, the Folders card shows its Wait / error state).
    func applyFixtureFolders(_ sizes: FolderSizes?, block: BlockState) {
        folderSizes = sizes
        foldersBlock = block
        applyFolderSizes(to: &report)
    }

    /// Visual fixture only (REDESIGN-STORAGE): the protected locations the Full Disk Access probe found refused.
    func applyFixtureFDA(denied: [ProtectedLocation]) { fdaDenied = denied }

    /// Starts an attempt and arms its watchdog: still in flight after `id.timeout` → `.failed(.timedOut)`.
    private func beginBlock(_ id: BlockID, showsLoading: Bool = false) {
        updateBlock(id) { $0.begin(at: Date(), showsLoading: showsLoading) }
        blockWatchdogs[id]?.cancel()
        let timeout = id.timeout
        blockWatchdogs[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self else { return }
            self.updateBlock(id) { $0.expire(now: Date()) }
        }
    }

    private func succeedBlock(_ id: BlockID) {
        disarmBlockWatchdog(id)
        updateBlock(id) { $0.succeed(at: Date()) }
    }

    private func failBlock(_ id: BlockID, _ failure: BlockFailure) {
        disarmBlockWatchdog(id)
        updateBlock(id) { $0.fail(failure) }
    }

    private func endBlockWithoutVerdict(_ id: BlockID) {
        disarmBlockWatchdog(id)
        updateBlock(id) { $0.endWithoutVerdict() }
    }

    private func disarmBlockWatchdog(_ id: BlockID) {
        blockWatchdogs[id]?.cancel()
        blockWatchdogs[id] = nil
    }

    /// REDESIGN-CPU: advances the high-load run (CPULoad.nextHighSince) with one successful CPU sample.
    private func recordCPUSample(_ cpu: CPUUsage, at t: Date) {
        let next = CPULoad.nextHighSince(previous: cpuHighSince, previousSampleAt: lastCPUSampleAt,
                                         usage: CPULoad.usage(cpu), at: t)
        if next != cpuHighSince { cpuHighSince = next }
        lastCPUSampleAt = t
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
        fastSamplePrimed = false   // a new fastBox collector primes again
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
                self.beginBlock(.cpu)
                self.beginBlock(.memory)
                let (snap, socTempC, pressure): (LiveSnapshot, Int?, MemoryPressureLevel?) = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let s = fastBox.value.collectFast()
                        // Block N7: same background hop — one HID pass costs ~50 ms.
                        let soc = ThermalSensors.socTemperature(
                            from: ThermalHIDReader.readTemperatureSensors())
                        let pressure = LiveCollector.readMemoryPressure()
                        continuation.resume(returning: (s, soc.map { Int($0.rounded()) }, pressure))
                    }
                }
                guard !Task.isCancelled else { return }
                // Block verdicts. A failed read never blanks the last good value below (keep-last-good);
                // the block's phase is what says the value is stale.
                if snap.cpu != nil { self.succeedBlock(.cpu) }
                else if self.fastSamplePrimed { self.failBlock(.cpu, .noReading) }
                else { self.endBlockWithoutVerdict(.cpu) }
                self.fastSamplePrimed = true
                if snap.mem != nil { self.succeedBlock(.memory) } else { self.failBlock(.memory, .noReading) }

                // Guarded per-field assignment: skip the set (and its @Observable
                // notification) when the field is unchanged, so a card observing only
                // one field re-renders only when THAT field actually changed.
                if self.load    != snap.load    { self.load    = snap.load }
                if let cpu = snap.cpu, self.cpu != cpu { self.cpu = cpu }
                if let mem = snap.mem, self.mem != mem { self.mem = mem }
                if self.swap    != snap.swap    { self.swap    = snap.swap }
                if self.disk    != snap.disk    { self.disk    = snap.disk }
                if self.battery != snap.battery { self.battery = snap.battery }
                if self.socTempC != socTempC { self.socTempC = socTempC }
                if self.memPressure != pressure { self.memPressure = pressure }
                self.lastSampleAt = snap.t
                if let cpu = snap.cpu {
                    self.recordCPUSample(cpu, at: snap.t)
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
                self.setAssessment(self.assessed(assessedReport))

                try? await Task.sleep(for: .seconds(AppSettings.shared.fastIntervalSeconds))
            }
        }

        // Slow task (~6s): the process tables and wake holders (via `ps` + `top` + `pmset`).
        // No setAssessment here — the next fast tick assesses with the new topApps.
        slowTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                if self.isPaused {
                    try? await Task.sleep(for: .seconds(6))
                    continue
                }

                // sampleProcesses() is async and suspends while `/bin/ps` and `/usr/bin/top`
                // run (and, on the FIRST tick only, while it sleeps 0.6 s to prime its CPU
                // baseline) — it runs on the global executor, not the main thread.
                let procs = await CommandRunner.$qos.withValue(.utility) { await procBox.value.sampleProcesses(limit: LiveCollector.topProcessCount) }
                guard !Task.isCancelled else { return }
                let wake = await CommandRunner.$qos.withValue(.utility) { await WakeHolders.sample() }
                guard !Task.isCancelled else { return }

                if self.topCPU != procs.topCPU { self.topCPU = procs.topCPU }
                if self.topMem != procs.topMem { self.topMem = procs.topMem }
                if procs.processCount > 0, self.processCount != procs.processCount { self.processCount = procs.processCount }
                if self.topApps != procs.topApps { self.topApps = procs.topApps }
                if self.procParseFailures != procs.parseFailures { self.procParseFailures = procs.parseFailures }
                if self.wakeHolders != wake.holders { self.wakeHolders = wake.holders }
                if self.systemWakeHolders != wake.system { self.systemWakeHolders = wake.system }
                if !self.wakeSampled { self.wakeSampled = true }
                let wakeFailures = wake.failure.map { [$0] } ?? []
                if self.wakeParseFailures != wakeFailures { self.wakeParseFailures = wakeFailures }

                try? await Task.sleep(for: .seconds(6))
            }
        }

        // SMART task (~5 min): periodic re-check of disk health, independent of the
        // report/fast/slow cadences. Own ReportCollector instance — collectors aren't
        // shared across tasks (see fastBox/procBox comment above).
        let smartBox = UncheckedSendableBox(ReportCollector())
        smartTask = Task(priority: .utility) { [weak self] in
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

                let (disks, tmDest) = await CommandRunner.$qos.withValue(.utility) {
                    let disks = await smartBox.value.collectSmartDisks()
                    let tmDest = await smartBox.value.collectTMDestInfo()
                    return (disks, tmDest)
                }
                guard !Task.isCancelled else { return }

                // Assessment (smartSev) is recomputed every ~2s by the fast task above,
                // which assesses `lastCommittedReport` while a collect is in flight (:290) —
                // so `report.smart` must already be committed before that next tick, which
                // is why this path awaits `waitForReportRefreshToFinish()` first. No
                // explicit setAssessment() call needed here.
                await self.waitForReportRefreshToFinish()
                guard !Task.isCancelled else { return }
                if self.report.smart != disks { self.report.smart = disks }
                if self.report.tmDest != tmDest { self.report.tmDest = tmDest }
                self.tmUpdatedAt = Date()
                await self.refreshClaudeBackup()
                self.smartUpdatedAt = Date()
            }
        }

        loadCachedReportFromDisk()
        reprobeProtectedLocations()
        refreshReport(trigger: .automatic)
        Task { [weak self] in await self?.refreshClaudeBackup() }

        // Hourly folder-size count (SIZES-BACKGROUND): a cheap poll; the 1 h rule inside
        // startSizeCountIfNeeded decides (last success or last failed attempt, SIZES-FAIL-BACKOFF).
        // Skipped while paused (SPEC §1.4 energy rule).
        sizeScheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                if !self.isPaused { self.startSizeCountIfNeeded(trigger: .automatic) }
            }
        }
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
        brewUpgradeTask?.cancel()
        brewUpgradeTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
        updateCheckGeneration += 1; isCheckingUpdates = false   // a cancelled check no longer counts as in flight
        sizeCountTask?.cancel(); sizeCountTask = nil
        sizeScheduleTask?.cancel(); sizeScheduleTask = nil
        sizeCountGeneration += 1; isCountingSizes = false
        for watchdog in blockWatchdogs.values { watchdog.cancel() }
        blockWatchdogs.removeAll()
        for observer in activityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        activityObservers.removeAll()
    }

    /// Public entry. `.button` only from the «Обновить отчёт» button.
    func refreshReport(trigger: CollectTrigger) {
        // Fixture mode shows a fixed dataset and must write nothing: no pass, no update check,
        // no size count (the same predicate MacDashboardApp uses to skip start()).
        guard !VisualFixture.isRequested else { return }
        startUpdateCheckIfNeeded(trigger: trigger)      // before the in-flight guard: a press mid-pass still gets a check
        startSizeCountIfNeeded(trigger: trigger)        // before the in-flight guard
        guard !isCollectingReport else {
            reportRefreshPending = CollectTrigger.merged(reportRefreshPending, trigger); return
        }
        beginPass(trigger: trigger)
    }

    private func beginPass(trigger: CollectTrigger) {
        reportTask?.cancel()
        // Snapshot BEFORE the collect wipes `report` section by section: this is what the
        // fast tick assesses for the duration of the pass (V2-HONEST-READINGS).
        lastCommittedReport = report
        isCollectingReport = true
        beginBlock(.scan, showsLoading: trigger == .button)

        reportTask = Task(priority: trigger.taskPriority) { [weak self] in
            guard let self else { return }
            defer {
                self.isCollectingReport = false   // always clear, incl. cancellation
                if let pending = self.reportRefreshPending {
                    self.reportRefreshPending = nil
                    // Don't relaunch from a cancelled task (stop() during shutdown). beginPass, not
                    // refreshReport: the update check for that request was decided when it was requested.
                    if !Task.isCancelled { self.beginPass(trigger: pending) }
                }
            }

            let cachedBrew: BrewSnapshot? =
                ReportCollector.isBrewCacheFresh(collectedAt: self.brewCheckedAt, now: Date())
                    ? self.lastBrewInfo : nil
            let collected = await CommandRunner.$qos.withValue(trigger.commandQoS) {
                await ReportCollector().collect(skipSlow: false, cachedBrew: cachedBrew) { partial in
                    // onSection is @MainActor; we're already isolated here. Detect the
                    // .smart section's arrival by its progress-flag transition (false/absent
                    // -> true) BEFORE overwriting self.report, so smartUpdatedAt reflects the
                    // launch/manual report too, not only the periodic sampler.
                    if partial.progress["smart"] == true, self.report.progress["smart"] != true {
                        self.smartUpdatedAt = Date()
                    }
                    // REDESIGN-BACKUPS: the Time Machine destination section's arrival stamps the Backups card's «updated HH:MM».
                    let tmKey = ReportSection.tmDest.rawValue
                    if partial.progress[tmKey] == true, self.report.progress[tmKey] != true {
                        self.tmUpdatedAt = Date()
                    }
                    // Scan block (D14): decided by the system section — system_profiler — of this pass.
                    let systemKey = ReportSection.system.rawValue
                    if partial.progress[systemKey] == true, self.report.progress[systemKey] != true {
                        if partial.system?.modelName != nil { self.succeedBlock(.scan) }
                        else { self.failBlock(.scan, .noReading) }
                    }
                    var shown = partial
                    self.applyBackground(to: &shown)
                    self.report = shown
                    if let sys = partial.system { self.lastKnownSystem = sys }
                    // Deliberately NOT recomputed here: `partial` has most sections nil during
                    // a collect, so assessing it makes "not collected yet" and "nothing is
                    // wrong" the same value and the header thrashes between them. The verdict
                    // updates once the pass completes, at the `final` assessment below.
                    self.smartToolsState = Self.recomputeSmartToolsState()
                }
            }
            guard !Task.isCancelled else { return }
            var final = collected
            self.applyBackground(to: &final)

            if cachedBrew == nil {
                // brew actually ran this pass — refill the session cache, but never with a failed brew
                // check (BREW-OUTDATED-FAIL, BREW-VERSION-FAIL): the next refresh must retry it.
                let failed = ReportCollector.brewCheckFailed(status: final.brewStatus, outdated: final.brewOutdated)
                if !failed, let status = final.brewStatus {
                    self.lastBrewInfo = BrewSnapshot(status: status, outdated: final.brewOutdated,
                                                     outdatedDetail: final.brewOutdatedDetail,
                                                     installedCount: final.brewInstalledCount)
                    self.brewCheckedAt = Date()
                } else {
                    self.lastBrewInfo = nil
                    self.brewCheckedAt = nil
                }
            }

            self.historyStore.upsertToday(from: final, live: self.live)
            do {
                try self.historyStore.save()
            } catch {
                self.lastError = L.errorHistorySaveFailed(error.localizedDescription)
            }
            self.history = self.historyStore.state
            self.historyUnreadable = self.historyStore.fileUnreadable

            self.report = final
            if let sys = final.system { self.lastKnownSystem = sys }
            self.setAssessment(self.assessed(final))
            // A pass whose system section came back empty (scan block failed, D7) keeps the previous report:
            // the sheet shows «not updated · showing the HH:MM report» over the old text (02-home §4 failed).
            if final.system?.modelName != nil {
                let now = Date()
                self.commitReportText(self.reportSummaryInput(report: final, generatedAt: final.createdAt ?? now))
                self.reportUpdatedAt = now
            }
            self.smartToolsState = Self.recomputeSmartToolsState()
        }
    }

    /// Both background overlays; every report the model shows or commits goes through here.
    private func applyBackground(to r: inout FullReport) {
        applyUpdates(to: &r)
        applyFolderSizes(to: &r)
    }

    /// Single overlay point for the update-check result: every report the model shows or
    /// commits goes through here, so a check finishing mid-pass cannot be lost.
    private func applyUpdates(to r: inout FullReport) {
        r.updates = updatesCache?.items
        r.updatesCheckedAt = updatesCache?.checkedAt
        r.updatesCheckDuration = updatesCache?.durationSeconds
        r.progress[ReportSection.updates.rawValue] = (updatesCache != nil) || !isCheckingUpdates
    }

    /// Single overlay point for the folder-size result (SIZES-BACKGROUND). No cache => nil
    /// sizes (assessment skips them) and progress false while a count is running.
    private func applyFolderSizes(to r: inout FullReport) {
        r.homeDirs = folderSizes?.homeDirs
        r.homeDirsUnreadable = folderSizes?.homeDirsUnreadable ?? []
        r.serviceDirs = folderSizes?.serviceDirs
        r.homeCaches = folderSizes?.homeCaches
        r.serviceDirsUnreadable = folderSizes?.serviceDirsUnreadable ?? []
        r.homeDirsNotMeasured = folderSizes?.homeDirsNotMeasured ?? []
        r.serviceDirsNotMeasured = folderSizes?.serviceDirsNotMeasured ?? []
        r.folderSizesCountedAt = folderSizes?.countedAt
        r.folderSizesCountDuration = folderSizes?.durationSeconds
        let done = (folderSizes != nil) || !isCountingSizes
        r.progress[ReportSection.homeDirs.rawValue] = done
        r.progress[ReportSection.serviceDirs.rawValue] = done
    }

    private func startUpdateCheckIfNeeded(trigger: CollectTrigger) {
        guard ReportCollector.shouldStartUpdateCheck(trigger: trigger, checkedAt: updatesCache?.checkedAt,
                                                     inFlight: isCheckingUpdates, now: Date()) else { return }
        isCheckingUpdates = true
        updateCheckGeneration += 1; let gen = updateCheckGeneration
        applyUpdates(to: &report)                       // display only: spinner if no cache yet
        updateCheckTask = Task(priority: .utility) { [weak self] in
            let result = await CommandRunner.$qos.withValue(.utility) { await ReportCollector().checkUpdates() }
            guard let self, gen == self.updateCheckGeneration else { return }   // superseded by stop(): touch nothing
            self.isCheckingUpdates = false
            guard !Task.isCancelled else { return }
            if let result {
                self.updatesCache = result
                try? UpdatesCacheStore.save(result, to: self.updatesCacheURL)   // a failed write costs one re-check next launch; not surfaced
            }
            self.mergeBackgroundIntoCommitted()         // also on failure: spinner -> "unavailable"
        }
    }

    /// `armsWatchdog`: Try again on a visible error — a Wait comes back, so the 10 s watchdog is armed even
    /// though a count exists. With no count at all the Wait is on screen and the watchdog is always armed;
    /// otherwise the list stays visible and no watchdog runs (REDESIGN-STORAGE D5).
    private func startSizeCountIfNeeded(trigger: CollectTrigger, armsWatchdog: Bool = false) {
        guard ReportCollector.shouldStartSizeCount(trigger: trigger, countedAt: folderSizes?.countedAt,
                                                   failedAt: sizeCountFailedAt,
                                                   inFlight: isCountingSizes, now: Date()) else { return }
        isCountingSizes = true
        if folderSizes == nil || armsWatchdog {
            beginBlock(.folders, showsLoading: true)                       // a Wait is on screen: arm the 10 s watchdog (D5)
        } else {
            updateBlock(.folders) { $0.begin(at: Date(), showsLoading: false) }   // list stays visible; no watchdog
        }
        sizeCountGeneration += 1
        let gen = sizeCountGeneration
        applyFolderSizes(to: &report)                   // display only: spinner if no cache yet
        sizeCountTask = Task(priority: trigger.taskPriority) { [weak self] in
            let result = await CommandRunner.$qos.withValue(trigger.commandQoS) { await ReportCollector().countFolderSizes() }
            guard let self, gen == self.sizeCountGeneration else { return }
            self.isCountingSizes = false
            guard !Task.isCancelled else { return }
            if let result {
                self.succeedBlock(.folders)
                self.folderSizes = result
                self.sizeCountFailedAt = nil
                self.trashFreedBytes = nil; self.trashEmptiedAt = nil            // the new count includes the real Trash state
                try? FolderSizesCacheStore.save(result, to: self.folderSizesURL)   // a failed write costs one recount next launch
            } else {
                self.failBlock(.folders, .noReading)
                self.sizeCountFailedAt = Date()          // automatic triggers back off 1 h; the button still forces
            }
            self.mergeBackgroundIntoCommitted()         // also on failure: spinner -> "unavailable" when no cache
            self.reprobeProtectedLocations()
        }
    }

    /// V2-HEADER-CHURN: assess only a committed report.
    private func mergeBackgroundIntoCommitted() {
        if isCollectingReport {
            applyBackground(to: &lastCommittedReport)   // what the fast tick assesses mid-pass
            applyBackground(to: &report)                // display of the partial; NOT assessed
            setAssessment(assessed(lastCommittedReport))
            // The pass commit calls applyBackground on `final`, so it picks this result up too.
        } else {
            applyBackground(to: &report)
            setAssessment(assessed(report))
            // Re-render only when a report has been committed (a background result after a failed first pass
            // must not produce a summary of a half-collected report). reportUpdatedAt unchanged: it is the pass time.
            if reportText != nil {
                commitReportText(reportSummaryInput(report: report, generatedAt: reportUpdatedAt ?? Date()))
            }
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
            let disks = await collectorBox.value.collectSmartDisks()
            let tmDest = await collectorBox.value.collectTMDestInfo()
            guard !Task.isCancelled else { return }

            await self.waitForReportRefreshToFinish()
            guard !Task.isCancelled else { return }
            if self.report.smart != disks { self.report.smart = disks }
            if self.report.tmDest != tmDest { self.report.tmDest = tmDest }
            self.tmUpdatedAt = Date()
            await self.refreshClaudeBackup()
            self.smartUpdatedAt = Date()
        }
    }

    /// Manual, on-demand energy (pmset) re-check (SPEC Block K), triggered after a
    /// batched `pmset` apply from the Energy card, so the table shows what the
    /// system actually accepted rather than the values we merely requested.
    /// Mirrors `refreshSmartNow()` exactly — a fresh ReportCollector instance is
    /// created per call, one-shot only (no sampler loop).
    func refreshEnergyNow() {
        Task { [weak self] in await self?.refreshEnergy() }
    }

    /// The body of `refreshEnergyNow()`, awaitable so an apply can show its result only after the
    /// table has been re-read. Guarded by `energyRefreshing`.
    func refreshEnergy() async {
        if energyRefreshing {
            // A read is in flight and may have started before the caller's change: request one more
            // read and return only once the loop below has finished it.
            energyReadNeeded = true
            while energyRefreshing { try? await Task.sleep(for: .milliseconds(50)) }
            return
        }
        energyRefreshing = true
        defer { energyRefreshing = false }

        repeat {
            energyReadNeeded = false
            let collectorBox = UncheckedSendableBox(ReportCollector())
            let settings = await collectorBox.value.collectEnergySettings()
            guard !Task.isCancelled else { return }

            await waitForReportRefreshToFinish()
            guard !Task.isCancelled else { return }
            if report.energy != settings { report.energy = settings }
        } while energyReadNeeded
    }

    /// Last result of `applyEnergyChanges(_:)` (REDESIGN-SYSTEM); the page bar reads it for the tag.
    private(set) var energyApply: EnergyApplyState = .idle

    /// Applies the staged pmset edits through one privileged call (Touch ID / admin password, 30 s),
    /// then re-reads the table. Outcomes: applied / failed(cancelled | timedOut | error).
    func applyEnergyChanges(_ changes: [EnergyChange]) {
        guard energyApply != .applying, let command = SystemPageModel.pmsetCommand(changes) else { return }
        energyApply = .applying
        Task { [weak self] in
            let outcome = await Task.detached { PrivilegedRunner.run(command) }.value
            guard let self else { return }
            switch outcome {
            case .success:
                await self.refreshEnergy()
                self.energyApply = .applied
            case .cancelled: self.energyApply = .failed(.cancelled)
            case .timedOut:
                // `pmset -b … && pmset -c …` may have applied the first half: show what the system holds.
                await self.refreshEnergy()
                self.energyApply = .failed(.timedOut)
            case .failed(let msg):
                await self.refreshEnergy()
                self.energyApply = .failed(.error(msg))
            }
        }
    }

    /// Clears the apply result (OK on the banner; also when the user edits again after «Applied ✓»).
    func dismissEnergyApplyResult() { energyApply = .idle }

    /// Visual fixture only (REDESIGN-SYSTEM): the Energy card's apply state.
    func applyFixtureEnergyApply(_ s: EnergyApplyState) { energyApply = s }

    /// REDESIGN-CPU: CPU page «Try again» (the page-bar Refresh button was removed in CPU-REFRESH-REMOVE). One user-initiated sample on a fresh LiveCollector
    /// (its own 0.5 s delta window, independent of the fast loop's baseline) plus a process re-sample.
    func refreshCPUNow() {
        guard !cpuRefreshing else { return }
        cpuRefreshing = true
        beginBlock(.cpu, showsLoading: true)
        refreshProcessesNow()
        Task { [weak self] in
            let (snap, soc): (LiveSnapshot, Int?) = await withCheckedContinuation { c in
                DispatchQueue.global(qos: .userInitiated).async {
                    let collector = LiveCollector()
                    _ = collector.collectFast()
                    Thread.sleep(forTimeInterval: 0.5)
                    let s = collector.collectFast()
                    let t = ThermalSensors.socTemperature(from: ThermalHIDReader.readTemperatureSensors())
                    c.resume(returning: (s, t.map { Int($0.rounded()) }))
                }
            }
            guard let self else { return }
            defer { self.cpuRefreshing = false }
            guard let cpu = snap.cpu else { self.failBlock(.cpu, .noReading); return }
            if self.cpu != cpu { self.cpu = cpu }
            if self.load != snap.load { self.load = snap.load }
            if self.socTempC != soc { self.socTempC = soc }
            self.recordCPUSample(cpu, at: snap.t)
            self.succeedBlock(.cpu)
        }
    }

    /// REDESIGN-BACKUPS: Time Machine destination + local snapshots now (after a backup ends; after Stop).
    func refreshTimeMachineNow() {
        guard !tmRefreshing else { return }
        tmRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.tmRefreshing = false }
            let box = UncheckedSendableBox(ReportCollector())
            let tmDest = await box.value.collectTMDestInfo()
            let snaps = await box.value.collectLocalSnapshotNames()
            guard !Task.isCancelled else { return }
            await self.waitForReportRefreshToFinish()
            if let tmDest, self.report.tmDest != tmDest { self.report.tmDest = tmDest }   // nil = tmutil failed: keep the old value
            if let snaps, self.report.snapshots != snaps { self.report.snapshots = snaps }
            self.tmUpdatedAt = Date()
            await self.refreshClaudeBackup()
            self.setAssessment(self.assessed(self.report))
        }
    }

    /// REDESIGN-BACKUPS D2/D3: awaited by BackupsPage's `.task`; cancelled when the page leaves. Spawns
    /// `tmutil status` only for the first probe, while a backup runs, or while a start/stop is in flight,
    /// and never while the window is hidden (`isPaused`). 2 s between samples.
    func observeTimeMachineStatus() async {
        defer {
            tmBackup = nil
            if case .failed = tmAction { tmAction = .idle }
        }
        var pollsSinceStart = 0
        while !Task.isCancelled {
            let needed = tmBackup == nil || tmBackup?.running == true || tmAction == .starting || tmAction == .stopping
            if needed && !isPaused {
                let outcome = await ParsedCommand.tmutilStatus.run()
                guard !Task.isCancelled else { return }
                let wasRunning = tmBackup?.running == true
                let sample = outcome.nonEmptyText.flatMap { TimeMachineStatus.parse(text: $0) } ?? .idle
                if tmBackup != sample { tmBackup = sample }
                switch tmAction {
                case .starting:
                    if sample.running { tmAction = .idle; pollsSinceStart = 0 }
                    else { pollsSinceStart += 1; if pollsSinceStart >= 5 { tmAction = .failed(L.bkStartDidNotBegin); pollsSinceStart = 0 } }
                case .stopping:
                    if !sample.running { tmAction = .idle }
                default: break
                }
                if wasRunning && !sample.running { refreshTimeMachineNow() }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// REDESIGN-BACKUPS R3: `tmutil startbackup` (no root per tmutil(8)); the poll loop above confirms it began.
    func startTimeMachineBackupNow() {
        switch tmAction { case .idle, .failed: break; case .starting, .stopping: return }   // a failed attempt may be retried
        guard case .some(.some(let dest)) = report.tmDest, dest.mountPoint != nil else { return }
        tmAction = .starting
        Task { [weak self] in
            guard let self else { return }
            let outcome = await CommandRunner.run("/usr/bin/tmutil", ["startbackup"], timeout: 15)
            guard !Task.isCancelled else { return }
            if case .exited(0) = outcome.termination { return }   // the poll loop takes over (.starting → .idle / .failed)
            self.tmAction = .failed(L.bkStartFailed(Self.firstLine(outcome.stderrHead)))
        }
    }

    /// REDESIGN-BACKUPS R3: `tmutil stopbackup`; the poll loop clears `.stopping` once Running == 0.
    func stopTimeMachineBackupNow() {
        switch tmAction { case .idle, .failed: break; case .starting, .stopping: return }   // a failed action is cleared by a new stop
        guard tmBackup?.running == true else { return }
        tmAction = .stopping
        Task { [weak self] in
            guard let self else { return }
            let outcome = await CommandRunner.run("/usr/bin/tmutil", ["stopbackup"], timeout: 15)
            guard !Task.isCancelled else { return }
            if case .exited(0) = outcome.termination { return }
            self.tmAction = .failed(L.bkStopFailed(Self.firstLine(outcome.stderrHead)))
        }
    }

    /// First non-blank line of a command's stderr, or a generic reason.
    private static func firstLine(_ s: String) -> String {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? L.bkFailedNoReason
    }

    /// REDESIGN-STORAGE D22: Storage page Refresh = a folder recount with the `.button` trigger. Live disk figures
    /// already tick every interval; SMART has its own button.
    func refreshStorageNow() { startSizeCountIfNeeded(trigger: .button) }

    /// REDESIGN-SECURITY D7: the page's Refresh — protections + crash folders now, plus a forced update check.
    func refreshSecurityNow() {
        startUpdateCheckIfNeeded(trigger: .button)
        guard !securityRefreshing else { return }
        securityRefreshing = true
        securityAction = .idle
        Task { [weak self] in
            guard let self else { return }
            defer { self.securityRefreshing = false }
            let box = UncheckedSendableBox(ReportCollector())
            let sec = await box.value.collectSecurityInfo()
            let crashes = await Task.detached(priority: .utility) { box.value.collectCrashGroups() }.value
            guard !Task.isCancelled else { return }
            await self.waitForReportRefreshToFinish()
            self.report.security = sec
            self.report.crashes = crashes
            self.setAssessment(self.assessed(self.report))
        }
    }

    /// REDESIGN-STORAGE: Try again on the folder-count error. A count still in flight is not restarted: the Wait
    /// and a fresh 10 s watchdog come back and the running count's result still lands.
    func retryFolderCount() {
        if isCountingSizes {
            beginBlock(.folders, showsLoading: true)
        } else {
            startSizeCountIfNeeded(trigger: .button, armsWatchdog: true)
        }
    }

    /// REDESIGN-STORAGE D12: the Trash was emptied through Finder. Drops the `.Trash` entry from the in-memory
    /// count, records what it held, saves the cache (same write a count does) and re-assesses so Home's chip and
    /// the Disk note lose the Trash too.
    func trashWasEmptied() {
        let trash = FileManager.default.homeDirectoryForCurrentUser.path + "/.Trash"
        if var sizes = folderSizes {
            if let entry = sizes.homeDirs.first(where: { $0.path == trash }) {
                trashFreedBytes = entry.bytes
                sizes.homeDirs.removeAll { $0.path == trash }
                folderSizes = sizes
                try? FolderSizesCacheStore.save(sizes, to: folderSizesURL)
            }
        }
        trashEmptiedAt = Date()
        mergeBackgroundIntoCommitted()
    }

    /// REDESIGN-STORAGE D13/D14: re-reads which protected locations are refused. If fewer are refused than
    /// before (access was just granted), a `.button` recount starts so the sizes include the newly readable folders.
    func reprobeProtectedLocations() {
        let next = ProtectedLocations.denied(home: NSHomeDirectory(), probe: DirectoryAccess.probe)
        if next.count < fdaDenied.count && !fdaDenied.isEmpty { startSizeCountIfNeeded(trigger: .button) }
        if next != fdaDenied { fdaDenied = next }
    }

    /// REDESIGN-STORAGE D14: opens the Full Disk Access pane; busy until the app is re-activated.
    func openFullDiskAccessSettings() {
        fdaAwaitingReturn = true
        AdviceActionRunner.openPane(AdvicePanes.fullDiskAccess)
    }

    /// REDESIGN-MEMORY: Memory page Refresh / Try again. One native memory + swap + pressure read off the
    /// main actor plus a process re-sample. `showsLoading: false` (D4): the read takes milliseconds, so a
    /// loading phase would only flash; the button's «Refreshing…» is the feedback.
    func refreshMemoryNow() {
        guard !memoryRefreshing else { return }
        memoryRefreshing = true
        beginBlock(.memory)
        refreshProcessesNow()
        Task { [weak self] in
            let (snap, pressure): (LiveSnapshot, MemoryPressureLevel?) = await withCheckedContinuation { c in
                DispatchQueue.global(qos: .userInitiated).async {
                    c.resume(returning: (LiveCollector().collectFast(), LiveCollector.readMemoryPressure()))
                }
            }
            guard let self else { return }
            defer { self.memoryRefreshing = false }
            guard let mem = snap.mem else { self.failBlock(.memory, .noReading); return }
            if self.mem != mem { self.mem = mem }
            if self.swap != snap.swap { self.swap = snap.swap }
            if self.memPressure != pressure { self.memPressure = pressure }
            self.succeedBlock(.memory)
        }
    }

    /// REDESIGN-BATTERY: one ioreg read for the Battery page (the page's `.task` calls it every
    /// `BatteryPageModel.refreshSeconds`; «Try again» calls it with `showsLoading: true`). Awaits the read, so a
    /// loop never overlaps itself. A call while a read is in flight only re-arms the block (same shape as
    /// `retryFolderCount`): the Wait and a fresh 5 s watchdog come back, the running read's result still lands.
    func readBatteryNow(showsLoading: Bool) async {
        if batteryReading {
            if showsLoading { beginBlock(.battery, showsLoading: true) }
            return
        }
        batteryReading = true
        defer { batteryReading = false }
        beginBlock(.battery, showsLoading: showsLoading)
        let result = await BatteryInspector.read()
        switch result {
        case .detail(let d):
            if batteryDetail != d { batteryDetail = d }
            succeedBlock(.battery)
        case .timedOut:
            failBlock(.battery, .timedOut)
        case .unavailable:
            failBlock(.battery, .noReading)
        }
    }

    /// Manual, on-demand process-list re-sample (V2-SETTINGS-PROCLIMIT follow-up).
    /// Its callers are `refreshCPUNow()`, `refreshMemoryNow()` and the Processes card's Quit flow (REDESIGN-CPU);
    /// the «Применить» button of the retired process-limit setting was removed in
    /// REDESIGN-FOUNDATION. One-shot, independent of the periodic slowTask sampler — a fresh
    /// LiveCollector instance is created per call, never shared with a concurrent
    /// sampler pass (see the fastBox/procBox/smartBox comment in start()). Because
    /// this path builds a fresh LiveCollector (and therefore a fresh ProcessSampler)
    /// per press, its CPU% is measured over the sampler's 0.6 s priming window
    /// rather than the periodic ~6 s one; that is deliberate (a manual re-sample
    /// must not make the user wait 6 s) and is the only place where the window is
    /// not the display cadence.
    func refreshProcessesNow() {
        guard !processesRefreshing else { return }
        processesRefreshing = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.processesRefreshing = false }

            let collectorBox = UncheckedSendableBox(LiveCollector())
            let procs = await collectorBox.value.sampleProcesses(limit: LiveCollector.topProcessCount)
            guard !Task.isCancelled else { return }

            if self.topCPU != procs.topCPU { self.topCPU = procs.topCPU }
            if self.topMem != procs.topMem { self.topMem = procs.topMem }
            if procs.processCount > 0, self.processCount != procs.processCount { self.processCount = procs.processCount }
            if self.topApps != procs.topApps { self.topApps = procs.topApps }
            if self.procParseFailures != procs.parseFailures { self.procParseFailures = procs.parseFailures }
        }
    }

    /// In-app Homebrew package upgrade, triggered by the «Обновить пакеты» button
    /// on the Обслуживание системы card. Runs `brew upgrade` off-main, then
    /// re-collects a fresh Homebrew snapshot so the card reflects the outcome
    /// regardless of success or failure. Mirrors `refreshSmartNow()`.
    /// The `brew upgrade` step runs in its own Task so Stop (`stopBrewUpgrade()`) can end just that process; the re-check still runs.
    func upgradeBrewNow() {
        guard !brewUpgrading else { return }
        brewUpgrading = true
        brewUpgradeError = nil
        brewUpgradeNotice = nil
        brewStopRequested = false
        brewProgress = nil

        let before = report.brewOutdated ?? []
        let total = before.count

        let run = Task {
            await BrewUpgrader.upgradeAll(totalOutdated: total, onProgress: { progress in
                DispatchQueue.main.async { [weak self] in self?.brewProgress = progress }
            })
        }
        brewUpgradeRun = run
        brewUpgradeStoppable = true

        brewUpgradeTask = Task { [weak self] in
            guard let self else { run.cancel(); return }
            defer {
                self.brewUpgrading = false
                self.brewProgress = nil
                self.brewStopRequested = false
                self.brewUpgradeStoppable = false
                self.brewUpgradeRun = nil
            }

            // stop() cancels this task; forward that to the brew step (the user's Stop cancels only `run`).
            let error = await withTaskCancellationHandler { await run.value } onCancel: { run.cancel() }
            self.brewUpgradeStoppable = false
            // A Stop counts only if brew had not already exited 0 before the signal landed.
            let stoppedByUser = self.brewStopRequested && error != nil
            guard !Task.isCancelled else { return }        // global teardown: no re-check, no write-back

            guard let info = await self.recollectBrew() else { return }
            self.brewUpgradeError = stoppedByUser ? nil : error
            self.brewUpgradeNotice = stoppedByUser
                ? BrewUpgrader.stoppedNotice(before: before, after: info.outdated) : nil
        }
    }

    /// Re-checks brew on its own (System page «Try again» after a failed check), without a full report
    /// pass: `refreshReport()` rebuilds every section blank for 10-30 s (assessment-complete-collect).
    func refreshBrewNow() {
        guard !brewUpgrading, !brewRefreshing else { return }
        brewRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.brewRefreshing = false }
            _ = await self.recollectBrew()
        }
    }

    /// The re-check tail shared by `upgradeBrewNow()` and `refreshBrewNow()`: collect a fresh brew
    /// snapshot (no index update), wait for any report pass, write the four report fields and refill
    /// the session cache. nil = cancelled (teardown): nothing written.
    private func recollectBrew() async -> BrewSnapshot? {
        let collectorBox = UncheckedSendableBox(ReportCollector())
        let info = await collectorBox.value.collectBrewInfo(refreshIndex: false)
        guard !Task.isCancelled else { return nil }

        // The collect that starts while `brew upgrade` runs captures the PRE-upgrade
        // cachedBrew and would write it over these values (`self.report = final`).
        // Same reason the three sibling updaters wait — see
        // waitForReportRefreshToFinish()'s doc comment.
        await waitForReportRefreshToFinish()
        guard !Task.isCancelled else { return nil }

        report.brewStatus = info.status
        report.brewOutdated = info.outdated
        report.brewOutdatedDetail = info.outdatedDetail
        report.brewInstalledCount = info.installedCount
        let failed = ReportCollector.brewCheckFailed(status: info.status, outdated: info.outdated)
        lastBrewInfo = failed ? nil : info
        brewCheckedAt = failed ? nil : Date()
        return info
    }

    /// Visual fixture only (REDESIGN-SYSTEM): the Homebrew card's transient state.
    func applyFixtureBrew(checkedAt: Date?, upgrading: Bool, progress: BrewProgress?, error: String?,
                          notice: String?, stoppable: Bool) {
        brewCheckedAt = checkedAt; brewUpgrading = upgrading; brewProgress = progress
        brewUpgradeError = error; brewUpgradeNotice = notice; brewUpgradeStoppable = stoppable
    }

    /// User Stop (BREW-CANCEL). Interrupts only the running `brew upgrade`: SIGINT to its process
    /// group, SIGKILL after BrewUpgrader's grace. `upgradeBrewNow()`'s flow then re-checks brew so
    /// the card shows what really changed. No-op outside the brew step or after a first press.
    func stopBrewUpgrade() {
        guard brewUpgradeStoppable, !brewStopRequested, let run = brewUpgradeRun else { return }
        brewStopRequested = true
        run.cancel()
    }

    /// In-app `smartmontools` install, triggered by the install button on the Диски
    /// card when Homebrew is present but `smartctl` isn't (Block N8). Runs
    /// `brew install smartmontools` off-main (unprivileged — brew runs as the user,
    /// never via PrivilegedRunner), then re-probes `findSmartctl()`: on success,
    /// flips `smartToolsState` to `.installed` and re-collects external SMART via
    /// `refreshSmartNow()`; on failure, records a typed `SmartInstallFailure` (exit code, 300 s timeout, no brew).
    /// Mirrors `upgradeBrewNow()`.
    func installSmartmontoolsNow() {
        guard !smartInstalling else { return }
        smartInstalling = true
        smartInstallFailure = nil

        Task { [weak self] in
            guard let self else { return }
            defer { self.smartInstalling = false }

            guard let brew = ReportCollector.findBrew() else {
                self.smartInstallFailure = .noBrew
                return
            }

            // brew is a Homebrew-prefix script that shells out to its own helper
            // binaries (ruby, git, curl, …) inside that prefix — same reason
            // BrewUpgrader.upgradeAll and collectBrewInfo() build this env
            // (V2-POLISH B1). `brew install` is the heaviest of the three and was
            // the one call site that never got it.
            var installEnv = CommandRunner.environment(
                prependingPATH: [(brew as NSString).deletingLastPathComponent])
            // Formerly `/usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 brew …`; same variable, set directly (R0(c)).
            installEnv["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            let outcome = await CommandRunner.run(brew, ["install", "smartmontools"], timeout: 300,
                                                  environment: installEnv)
            guard !Task.isCancelled else { return }

            if ReportCollector.findSmartctl() != nil {
                self.smartToolsState = .installed
                self.smartInstallFailure = nil
                self.refreshSmartNow()
            } else {
                switch outcome.termination {
                case .timedOut: self.smartInstallFailure = .timedOut
                case .exited(let code): self.smartInstallFailure = .exitCode(code)
                case .signaled, .launchFailed, .cancelled: self.smartInstallFailure = .exitCode(-1)
                }
            }
        }
    }

    /// In-app firewall enable, triggered by the confirmation dialog on the
    /// Рекомендации card's `.enableFirewall` advice row. Runs
    /// `socketfilterfw --setglobalstate on` via `PrivilegedRunner` (Touch ID / admin
    /// password) off-main, then re-collects security state so the row disappears the
    /// instant success lands, without waiting for the next fast tick. Mirrors
    /// `refreshSmartNow()`/`upgradeBrewNow()`.
    func enableFirewallNow() { enableProtectionNow(.firewall) }

    /// REDESIGN-SECURITY: the same flow for the firewall and Gatekeeper (Touch ID, 30 s budget). The outcome is
    /// kept in `securityAction` so the Security page can show a banner per failure kind.
    func enableProtectionNow(_ p: SecurityProtection) {
        guard p == .firewall || p == .gatekeeper else { return }
        if case .enabling = securityAction { return }
        securityAction = .enabling(p)
        adviceActionError = nil
        let command = SecurityPageModel.privilegedEnableCommand(p)

        Task { [weak self] in
            guard let self else { return }

            let outcome: PrivilegedRunner.Outcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: PrivilegedRunner.run(command))
                }
            }
            guard !Task.isCancelled else { self.securityAction = .idle; return }

            switch outcome {
            case .success:
                let collectorBox = UncheckedSendableBox(ReportCollector())
                let s = await collectorBox.value.collectSecurityInfo()
                guard !Task.isCancelled else { self.securityAction = .idle; return }
                await self.waitForReportRefreshToFinish()
                guard !Task.isCancelled else { self.securityAction = .idle; return }
                self.report.security = s
                self.setAssessment(self.assessed(self.report))
                self.securityAction = .idle
            case .cancelled:
                self.securityAction = .failed(p, .cancelled)
            case .timedOut:
                self.securityAction = .failed(p, .timedOut)
            case .failed(let msg):
                self.securityAction = .failed(p, .error(msg))
                self.adviceActionError = p == .firewall ? L.adviceFirewallError : L.secGatekeeperError
            }
        }
    }

    /// Removes `paths` from `report.autostart`'s three plist arrays in place,
    /// WITHOUT a full `refreshReport()` recollect. `refreshReport()` rebuilds from
    /// a blank `FullReport()` and streams sections
    /// back in one by one, so calling it just to drop a deleted plist from the list
    /// makes the whole Автозагрузка card (and every other section) flash through its
    /// "collecting" placeholder before repopulating — a disproportionate, ugly
    /// reset for a change this narrow. A local, targeted mutation lets SwiftUI's
    /// own array diffing (and this card's `.animation(value: orphans)`) animate
    /// just the removed row instead.
    private func removeAutostartPlistsLocally(_ paths: Set<String>) {
        guard var auto = report.autostart, !paths.isEmpty else { return }
        let before = auto.userAgents.count + auto.systemAgents.count + auto.systemDaemons.count
        auto.userAgents.removeAll { paths.contains($0.path) }
        auto.systemAgents.removeAll { paths.contains($0.path) }
        auto.systemDaemons.removeAll { paths.contains($0.path) }
        startupRemovedCount += (before - (auto.userAgents.count + auto.systemAgents.count + auto.systemDaemons.count))
        report.autostart = auto
        // Deliberately NO setAssessment here: `report` is a PARTIAL for most of a collect
        // and a partial must never be assessed (V2-HEADER-CHURN) — a delete landing
        // mid-collect would recompute the verdict from mostly-nil sections and flash the
        // header to "all good" until the next fast tick. Nothing is lost: `Assess.assess`
        // reads nothing from `report.autostart` (verified — no `autostart` reference in
        // Assessment.swift), so this recompute could never change the verdict anyway.
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

    /// Clears the delete banner. It is otherwise only ever cleared by STARTING the next
    /// delete, so a failure message stayed pinned under the card long after the row it
    /// referred to was gone.
    func clearPlistDeleteFailure() { plistDeleteFailure = nil }

    /// «Check for stale» (REDESIGN-SYSTEM): re-collects the autostart section, then reveals the stale marks.
    /// A second press while a check runs is ignored.
    func checkStaleStartupItemsNow() {
        guard !startupChecking else { return }
        startupChecking = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.startupChecking = false }
            let info = await UncheckedSendableBox(ReportCollector()).value.collectAutostartInfo()
            guard !Task.isCancelled else { return }
            await self.waitForReportRefreshToFinish()
            guard !Task.isCancelled else { return }
            self.report.autostart = info
            self.startupCheckedAt = Date()
            self.startupRemovedCount = 0
        }
    }

    /// Visual fixture only (REDESIGN-SYSTEM): the Startup items card's transient state.
    func applyFixtureStartup(checkedAt: Date?, removed: Int, checking: Bool, deleting: Set<String>,
                             failure: PrivilegedActionFailure?) {
        startupCheckedAt = checkedAt; startupRemovedCount = removed; startupChecking = checking
        deletingPlistPaths = deleting; plistDeleteFailure = failure
    }

    /// Deletes an orphaned launchd .plist detected by the System page's startup-items re-scan. `isSystemLevel` selects the deletion path:
    /// user-level (~/Library/LaunchAgents) goes to Trash via FileManager (reversible);
    /// system-level (/Library/LaunchAgents|LaunchDaemons) is a permanent `rm` via
    /// PrivilegedRunner (Touch ID/admin password), since Trash semantics don't apply
    /// across privilege boundaries. The system-level command first runs `launchctl bootout`
    /// (errors ignored, see `PrivilegedRunner.removeStartupItemsCommand`) and then `rm`; the
    /// user-level path only trashes the file and does not unload an already-loaded job,
    /// which stays until relogin/reboot. Removes the deleted entry from
    /// `report.autostart` locally on success (see `removeAutostartPlistsLocally`)
    /// so it drops out of the list without a full report recollect.
    func deleteOrphanPlist(path: String, isSystemLevel: Bool) {
        // A delete for this path is already in flight and owns the outcome —
        // signalling here would restore a row whose delete may still succeed.
        guard !deletingPlistPaths.contains(path) else { return }
        guard LaunchdPlistInspector.isValidDeletionTarget(path: path, isSystemLevel: isSystemLevel) else {
            plistDeleteFailure = .error(L.autostartDeleteInvalidPath)
            signalPlistsNotDeleted([path])
            return
        }
        deletingPlistPaths.insert(path)
        plistDeleteFailure = nil

        Task { [weak self] in
            guard let self else { return }
            defer { self.deletingPlistPaths.remove(path) }

            let outcome: PlistDeleteOutcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    if isSystemLevel {
                        switch PrivilegedRunner.run(PrivilegedRunner.removeStartupItemsCommand(paths: [path], uid: getuid())) {
                        case .success: continuation.resume(returning: .success)
                        case .cancelled: continuation.resume(returning: .cancelled)
                        case .failed(let msg): continuation.resume(returning: .failed(msg))
                        case .timedOut: continuation.resume(returning: .timedOut)
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
                self.plistDeleteFailure = .cancelled
                self.signalPlistsNotDeleted([path])
            case .timedOut:
                self.plistDeleteFailure = .timedOut
                self.signalPlistsNotDeleted([path])
            case .failed(let msg):
                self.plistDeleteFailure = .error(msg)
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
        let rejected = Set(paths).subtracting(batch).subtracting(inFlight)
        signalPlistsNotDeleted(rejected)
        guard !batch.isEmpty else {
            // Never a silent no-op: if nothing survived validation the button looked
            // broken — rows flicked back and no message appeared (V2-POLISH B7). Paths
            // skipped only because a delete is already in flight are NOT an error;
            // that call owns their outcome, so a batch that is empty for that reason
            // alone stays quiet and leaves any existing error text as it was.
            if !rejected.isEmpty { plistDeleteFailure = .error(L.autostartDeleteInvalidPath) }
            return
        }

        for path in batch { deletingPlistPaths.insert(path) }
        plistDeleteFailure = nil

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
                let command = PrivilegedRunner.removeStartupItemsCommand(paths: systemPaths, uid: getuid())

                let systemOutcome: PlistDeleteOutcome = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        switch PrivilegedRunner.run(command) {
                        case .success: continuation.resume(returning: .success)
                        case .cancelled: continuation.resume(returning: .cancelled)
                        case .failed(let msg): continuation.resume(returning: .failed(msg))
                        case .timedOut: continuation.resume(returning: .timedOut)
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
                self.plistDeleteFailure = .error(failures.count > 1
                    ? L.autostartDeleteBulkFailure(failures.count, results.count, firstFailure)
                    : firstFailure)
            } else if results.contains(where: { $0.outcome == .timedOut }) {
                self.plistDeleteFailure = .timedOut
            } else if results.contains(where: { $0.outcome == .cancelled }) {
                self.plistDeleteFailure = .cancelled
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
            Task { @MainActor [weak self] in
                self?.recomputeIsPaused()
                self?.fdaAwaitingReturn = false
                self?.reprobeProtectedLocations()
            }
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

    /// Suppresses redundant @Observable notifications when the new assessment
    /// is value-equal to the current one (e.g. repeated live ticks with no
    /// change in severity/tips/problems).
    private func setAssessment(_ n: Assessment) { if assessment != n { assessment = n } }

    /// The model's only way to build an `Assessment` (SLEEP-IGNORE-APP): every path passes
    /// the current ignore list, so an ignored wake holder cannot re-warn through a path that
    /// forgot it.
    private func assessed(_ r: FullReport) -> Assessment {
        Assess.assess(report: r, live: live, memPressure: memPressure, topApps: topApps,
                      wakeHolders: wakeHolders, ignoredWakeHolders: AppSettings.shared.ignoredWakeHolders,
                      claudeBackup: claudeBackup, backupStaleHours: AppSettings.shared.backupStaleHours,
                      lowSpacePercent: AppSettings.shared.lowSpacePercent,
                      now: fixtureNow ?? Date())
    }

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
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("mac_report.txt")
    }
}
