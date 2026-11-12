// Engine/AppModel.swift
// Integration phase (SPEC §3, §4): wires the real collectors (LiveCollector,
// ReportCollector, Assess, ReportWriter, HistoryStore) behind the observable
// contract the UI depends on. Starts empty/honest — no fabricated data — and
// fills in as collection completes, exactly like the on-disk report/history
// files behave.

import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    /// Fast-task history window: the last 61 samples (SOC-DETAILS D5).
    nonisolated static let historyLimit = 61
    /// SAMPLER-OCCLUSION-GATE D3/D5: the one slow clock — the hidden assessment tick and the daily History point.
    nonisolated static let schedulerIntervalSeconds = 60

    /// Appends one sample and keeps only the last `historyLimit`.
    nonisolated static func appendTrimmed<V>(_ history: inout [(Date, V)], _ sample: (Date, V)) {
        history.append(sample)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
    }

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
    /// IDLE-WORK-TRIM: when `disk` was last read (visible or hidden tick); the Storage disk card's caption. nil until the first read.
    var diskSampledAt: Date? = nil
    var battery: BatteryInfo? = nil   // Home battery tile / Now cell (falls back to report.battery)
    /// Block N7: rounded SOC die temperature (°C), max over valid PMU tdie sensors,
    /// sampled by the fast task via ThermalHIDReader (app-only private API). nil =
    /// unavailable (Intel / API failure) — the CPU page shows «—» (honest-empty).
    /// Stored pre-rounded to Int so the equality guard suppresses sub-degree jitter.
    var socTempC: Int? = nil
    /// GPU-UTILIZATION: whole-machine GPU load %, `Device Utilization %` of the IOAccelerator entry (undocumented key),
    /// sampled by the fast task next to socTempC. nil = unavailable — the SoC page and the Home SoC cell show «—».
    var gpuUtil: Int? = nil
    /// SOC-DETAILS D6: the GPU load kept next to `cpuHistory` for the SoC page's 2-minute chart. Appended on every fast
    /// tick (nil allowed: a nil reading breaks only the GPU line), trimmed to 61 samples (D5).
    var gpuHistory: [(Date, Int?)] = []
    /// THERMAL-STATE: macOS thermal state from ProcessInfo, updated by thermalStateDidChangeNotification (no polling).
    private(set) var thermal: ThermalLevel? = nil
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

    /// BACKUP-AGE: newest successful Claude backup per its log; nil = no log on this Mac (show nothing). Refreshed on the SMART cadence.
    var claudeBackup: ClaudeBackupStatus? = nil

    /// VISUAL-HARNESS-STALE: visual fixture only — the instant that backup-age displays and
    /// assessments treat as "now", so fixture captures do not depend on the wall clock. nil = wall clock.
    var fixtureNow: Date? = nil
    /// The clock the views render with: the fixture's frozen date under -visualFixture (set by `applyVisualFixture`
    /// and by the snapshot tests), else `fallback`. Views call `now()` / `now(or: ctx.date)` and never read
    /// `fixtureNow` themselves (ARCH-ENGINE-GUARD, EngineBoundaryTests).
    func now(or fallback: Date = Date()) -> Date { fixtureNow ?? fallback }

    /// Re-entrancy guard for `refreshProcessesNow()`, true while a manual process-list
    /// refresh is in flight — mirrors `smart.refreshNow()`'s guard.
    var processesRefreshing = false

    /// HIDDEN-CONTENT-WORK: Home's attention-card action state (`AdviceActionDispatch`, a Views type) must outlive the
    /// card, because Home is unmounted while a page is open and an empty-Trash may still be running in Finder; the model
    /// gives it this lifetime. The typed accessor `homeAdviceDispatch` is an extension in Views/AdviceActionDispatch.swift
    /// so this file names no Views type (ARCH-ENGINE-GUARD). Storage keeps its own per-card dispatch.
    @ObservationIgnored var homeAdviceDispatchStorage: AnyObject?

    /// Assembled on demand for the imperative report/assess/history code paths ONLY.
    /// MUST stay `private` — a VIEW reading this would re-register a dependency on every
    /// field and defeat the per-field observation split. (Views read the individual
    /// properties above instead.)
    private var live: LiveSnapshot {
        var s = LiveSnapshot()
        s.t = lastSampleAt; s.load = load; s.cpu = cpu
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
            thermal: thermal,
            mem: mem, memPressure: memPressure, swap: swap, disk: disk,
            hasBattery: merged != nil, battery: merged, batteryShown: assessment.battShownPercent,
            security: report.security, claudeBackup: claudeBackup, claudeAttempt: claudeRun.attempt, snapshotCount: report.snapshots?.count,
            now: fixtureNow ?? Date(), parseFailures: report.parseFailures + live.parseFailures,
            details: ReportDetails(report: report, live: live))
    }

    /// Renders, writes `mac_report.txt` and publishes the text. `reportUpdatedAt` is the caller's business.
    private func commitReportText(_ input: ReportSummaryInput) {
        let text = ReportWriter.render(input, language: L10nStore.shared.language)
        do { try ReportWriter.write(text: text, to: reportURL) }
        catch { lastError = L.errorReportWriteFailed(error.localizedDescription) }
        reportText = text
    }

    var cpuHistory: [(Date, Double)]  // last 61 points of user+sys (SOC-DETAILS D5: the chart's 2 minutes at the 2 s setting)
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
    /// REDESIGN-NOTIFY: edge detector over committed assessments; armed by the first completed pass (R2, D11).
    @ObservationIgnored private var notifyEdges = NotificationEdgeDetector()
    @ObservationIgnored private var hasCompletedPass = false
    /// REDESIGN-NOTIFY: a destination requested from outside the view tree (a notification click); MainDashboardView consumes it.
    private(set) var externalDestination: Destination? = nil
    private(set) var externalDestinationSerial = 0
    var reportText: String?           // rendered text report (for the Report sheet)

    /// Timestamp of the report currently shown in the Report sheet: the on-disk file's
    /// mtime when a cached report was loaded at launch, or the completion time of the
    /// last successful collect(). Drives the "updated HH:MM" staleness caption.
    var reportUpdatedAt: Date? = nil

    var reportURL: URL                // fixed file path
    var isCollectingReport: Bool
    var lastError: String?

    // Two independent live cadences (SPEC §5.1 decoupling): the fast task samples the
    // all-native gauges (~2s) while the slow task samples the `top` process tables
    // (~6s), so the responsive gauges no longer pay the ~1s `top` cost every tick.
    private var fastTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?   // SAMPLER-OCCLUSION-GATE: the 60 s scheduler
    /// One watchdog per armed block (`beginBlock`); cancelled when the block gets a verdict.
    @ObservationIgnored private var blockWatchdogs: [BlockID: Task<Void, Never>] = [:]
    /// IDLE-WORK-TRIM: decides per fast tick whether the collector reads disk (`DiskReadSchedule`).
    @ObservationIgnored private var diskSchedule = DiskReadSchedule()

    /// Set when refreshReport() is requested while a collect is already in flight
    /// (e.g. a language switch during the launch collect). The in-flight pass kicks
    /// off exactly one follow-up refresh on completion instead of silently dropping
    /// the request. Not a counter: N coalesced requests → one follow-up. nil = none;
    /// `.button` wins when merged (CollectTrigger.merged).
    /// Internal, not private: ReportHostTests sets it to chain a pending pass (PASS-WAIT-PARTIAL).
    var reportRefreshPending: CollectTrigger? = nil
    /// PASS-WAIT-PARTIAL: updater landings queued by `runAfterPass(_:)` while a pass is in flight. The pass's `defer`
    /// runs them after its commit; a cancelled pass and `stop()` drop them.
    @ObservationIgnored private var afterPassQueue: [@MainActor () -> Void] = []

    /// SAMPLER-OCCLUSION-GATE: the one owner of window visibility (AppActivityMonitor feeds it through
    /// `applyVisibility`). The fast, slow and Battery loops park on it; everything else reads `isPaused`.
    let gate = VisibilityGate()
    /// True while the gate is hidden: the app is not frontmost or has no visible, non-panel window on screen. The
    /// controllers read it through ReportHost.isPaused, the SoC sampler through its closure, the banner rule (D13)
    /// and BackupsPage directly. Computed, so every reader follows the gate (D13 of SAMPLER-OCCLUSION-GATE).
    var isPaused: Bool { gate.state == .hidden }
    /// ARCH-SETTINGS-PATH: the settings this model assesses with and its pages read (`model.settings`).
    /// The app passes `.shared`; tests pass an isolated instance.
    let settings: AppSettings
    /// MOONPORT-RENAME: held while the Welcome panel is up; launch work that can raise a permission prompt waits on it.
    let welcome = WelcomeGate()
    private let actions: AppActions
    /// ARCH-MODEL-SPLIT: the clock/sleep the pass wait and the controllers use; tests inject a virtual one.
    private let time: TimeSource
    /// PASS-WAIT-PARTIAL: one report pass's collect — the hidden crash names and the brew session cache in, the final
    /// report out, every snapshot through `onSection`. The app uses ReportCollector; tests inject a fake (no process spawned).
    typealias PassCollect = @MainActor (_ hiddenCrashReports: Set<String>, _ cachedBrew: BrewSnapshot?,
                                        _ onSection: @escaping @MainActor (FullReport) -> Void) async -> FullReport
    private let passCollect: PassCollect
    /// ARCH-MODEL-SPLIT: how controllers reach `report` / the pass / the assessment without a back-reference.
    private let link = CoordinatorLink()
    /// The one host every controller gets; tests drive it directly.
    let reportHost: ReportHost
    /// ARCH-MODEL-SPLIT: the Energy (pmset) feature; views read `model.energy.<member>`.
    let energy: EnergyController
    /// ARCH-MODEL-SPLIT: the Homebrew feature (upgrade, Stop, re-check, session cache); views read `model.brew.<member>`.
    let brew: BrewController
    /// ARCH-MODEL-SPLIT block 3: the Startup items feature («Check for stale», orphan-plist deletes);
    /// views read `model.startupItems.<member>`.
    let startupItems: StartupItemsController
    /// ARCH-MODEL-SPLIT block 4: the Time Machine feature (status poll, Back up now / Stop, destination re-read,
    /// «updated» stamp); views read `model.timeMachine.<member>`.
    let timeMachine: TimeMachineController
    /// BACKUP-CARD-FAILURE: the Claude backup card's live state (job, last attempt, disk, Back up now); views read `model.claudeRun.<member>`.
    let claudeRun: ClaudeBackupController
    /// ARCH-MODEL-SPLIT block 5: the disk-health feature (300 s SMART sampler, smartmontools install, tools state,
    /// «updated» stamp); views read `model.smart.<member>`.
    let smart: SmartToolsController
    /// ARCH-MODEL-SPLIT block 6: the Crashes card actions (hide / unhide / delete, re-scan ordering); views read `model.crashReports.<member>`.
    let crashReports: CrashReportsController
    /// ARCH-MODEL-SPLIT block 6: the protections feature (Touch ID enable, page Refresh, advice error); views read `model.security.<member>`.
    let security: SecurityController
    /// ARCH-MODEL-SPLIT block 7: the background update check, the folder-size count (schedule, Refresh / Try again,
    /// Trash bookkeeping) and the Full Disk Access state; views read `model.storage.<member>`.
    let storage: StorageController
    /// ARCH-MODEL-SPLIT block 8: the History feature (history file, daily snapshot, History page Refresh, restart notice,
    /// Home History digest); views read `model.history.<member>`.
    let history: HistoryController

    /// SOC-DETAILS D22: the SoC page tick (per-core load, frequency, whole-Mac power, top GPU processes). Idle until the
    /// SoC page's `.task` runs `socLive.run()`; it reads nothing while the page is closed, the app is in the background
    /// or the window is hidden.
    let socLive: SocLiveSampler

    /// `dataDirectory`: tests pass a temporary folder so the model never touches the real Application Support folder; the app passes nothing.
    /// `passCollect`: tests pass a fake pass; the app passes nothing.
    init(dataDirectory: URL? = nil, actions: AppActions = .none, settings: AppSettings? = nil, time: TimeSource = .live,
         passCollect: PassCollect? = nil) {
        let settings = settings ?? .shared
        self.settings = settings
        self.actions = actions
        self.time = time
        let livePassCollect: PassCollect = { hidden, cachedBrew, onSection in
            await ReportCollector(hiddenCrashReports: hidden).collect(skipSlow: false, cachedBrew: cachedBrew, onSection: onSection)
        }
        self.passCollect = passCollect ?? livePassCollect
        cpuHistory = []
        report = FullReport()
        assessment = Assessment()
        reportText = nil
        isCollectingReport = false
        lastError = nil

        let url = dataDirectory.map { $0.appendingPathComponent("mac_report.txt") } ?? Self.defaultReportURL()
        reportURL = url
        // ARCH-MODEL-SPLIT: controllers are built before `self` is usable; `link` is pointed at `self` last.
        let link = self.link
        reportHost = ReportHost(
            read: { link.model?.report ?? FullReport() },
            update: { mutate in if let m = link.model { mutate(&m.report) } },
            isCollecting: { link.model?.isCollectingReport ?? false },
            afterPass: { work in link.model?.runAfterPass(work) },
            reassess: { link.model?.reassessCommitted() },
            isPaused: { link.model?.isPaused ?? true },
            refreshClaudeBackup: { await link.model?.refreshClaudeBackup() },
            requestDiskRead: { link.model?.requestDiskRead() },
            mergeBackgroundIntoCommitted: { link.model?.mergeBackgroundIntoCommitted() },
            beginBlock: { id, showsLoading, armsWatchdog in
                link.model?.beginBlock(id, showsLoading: showsLoading, armsWatchdog: armsWatchdog) },
            succeedBlock: { link.model?.succeedBlock($0) },
            failBlock: { link.model?.failBlock($0, $1) },
            reportError: { link.model?.lastError = $0 })
        energy = EnergyController(host: reportHost, time: time)
        brew = BrewController(host: reportHost, time: time)
        startupItems = StartupItemsController(host: reportHost, time: time)
        let tm = TimeMachineController(host: reportHost, time: time)
        timeMachine = tm
        claudeRun = ClaudeBackupController(host: reportHost, time: time, deps: .live(settings: settings))
        // Controller→controller write (series convention): SMART's destination reads stamp Time Machine.
        smart = SmartToolsController(host: reportHost, time: time,
                                     deps: .live(markTMUpdated: { tm.recordDestination($0) }))
        let crash = CrashReportsController(host: reportHost, time: time, deps: .live(settings: settings))
        crashReports = crash
        let st = StorageController(host: reportHost, time: time,
                                   deps: .live(directory: url.deletingLastPathComponent(),
                                               openSettingsPane: actions.openSettingsPane))
        storage = st
        // Controller→controller (series convention): Security re-scans crashes through Crash and forces the update
        // check through Storage.
        security = SecurityController(host: reportHost, deps: .live(rescanCrashes: { crash.rescan() },
                                                                     checkUpdates: { st.startUpdateCheckIfNeeded(trigger: .button) }))
        history = HistoryController(host: reportHost, time: time,
                                    deps: .live(directory: url.deletingLastPathComponent(), settings: settings))
        socLive = SocLiveSampler(interval: { settings.fastIntervalSeconds },
                                 isPaused: { link.model?.isPaused ?? true }, time: time)
        if let countedAt = st.folderSizesCountedAt { foldersBlock.succeed(at: countedAt) }   // cached count = last good
        // ARCH-SETTINGS-PATH: the one write path — any change of an assessment setting re-assesses this model.
        settings.onAssessmentSettingsChange = { [weak self] old in self?.assessmentSettingsChanged(from: old) }
        link.model = self
    }

    /// BACKUP-AGE: re-read the backup log off the main actor; guarded so an unchanged status notifies nobody.
    func refreshClaudeBackup() async {
        let urls = BackupLog.resolvedURLs(custom: settings.claudeLogPath)
        let s = await BackupLog.readStatus(logURL: urls.log, rotatedURL: urls.rotated)
        if claudeBackup != s { claudeBackup = s }
        await claudeRun.refreshAttempt()
    }

    /// The Claude backup log currently read (the user's override or the default).
    var claudeLogPath: String { BackupLog.resolvedURLs(custom: settings.claudeLogPath).log.path }
    /// False when the user points the card at another log: the job always writes the default one (D16).
    var claudeUsesDefaultLog: Bool { BackupLog.resolvedURLs(custom: settings.claudeLogPath).log.path == BackupLog.logURL.path }

    /// ARCH-SETTINGS-PATH: the one reaction to a change of any assessment setting, called synchronously by
    /// `AppSettings.assessmentSettings.didSet` whoever wrote it (a Settings binding, the System page, Home's menu,
    /// a test). Re-assesses now, rather than on the next fast tick (which does not run while paused). A new Claude
    /// log path is re-read first, so the assessment never pairs the new path with the old file's status.
    private func assessmentSettingsChanged(from old: AssessmentSettings) {
        // BATTERY-HEALTH-UNIFY D5: the raw switch turned on with no ioreg read yet starts one; its result re-assesses
        // (readBatteryNow). Never under the visual fixture (the fixture detail must stay).
        if settings.assessmentSettings.batteryShowsRawMac, !old.batteryShowsRawMac, batteryDetail == nil, !VisualFixture.isRequested {
            Task { await readBatteryNow() }
        }
        if settings.assessmentSettings.claudeLogPath != old.claudeLogPath {
            Task { await refreshClaudeBackup(); reassessCommitted() }
            return
        }
        reassessCommitted()
    }

    /// Same report choice as the fast tick: never a partial (V2-HEADER-CHURN).
    private func reassessCommitted() {
        setAssessment(assessed(homeReport))
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

    /// Visual fixture only (AppModel+VisualFixture,
    /// Tests/MacDashboardTests/ContentSnapshotTests.swift): sets the scan block directly; live code never calls this.
    func applyFixtureScan(_ state: BlockState) { scanBlock = state }

    /// Visual fixture only: sets the CPU block and the high-load start.
    func applyFixtureCPU(_ state: BlockState, highSince: Date?) { cpuBlock = state; cpuHighSince = highSince }

    /// Visual fixture only: sets the memory-pressure level the Now card's Memory chip reads.
    func applyFixturePressure(_ p: MemoryPressureLevel?) { memPressure = p }

    /// Visual fixture only: sets the macOS thermal state the CPU page's SoC tile note reads.
    func applyFixtureThermal(_ t: ThermalLevel?) { thermal = t }

    /// Visual fixture only: sets the memory block.
    func applyFixtureMemory(_ state: BlockState) { memoryBlock = state }
    /// Visual fixture only (REDESIGN-BATTERY): the detail the Battery page shows and its block.
    func applyFixtureBattery(_ detail: BatteryDetail?, block: BlockState) { batteryDetail = detail; batteryBlock = block }

    /// Visual fixture only (REDESIGN-SYSTEM): the Sleep card's holders.
    func applyFixtureWakeHolders(user: [WakeHolder], system: [WakeHolder], sampled: Bool) {
        wakeHolders = user; systemWakeHolders = system; wakeSampled = sampled
    }

    /// Visual fixture only (REDESIGN-STORAGE): the folder-count result and its block, re-applied to the shown report
    /// (nil sizes = no count yet, the Folders card shows its Wait / error state). The block is coordinator state;
    /// the sizes are the storage controller's.
    func applyFixtureFolders(_ sizes: FolderSizes?, block: BlockState) {
        foldersBlock = block
        storage.applyFixture(folderSizes: sizes)
    }

    /// Starts an attempt. `armsWatchdog` (default): still in flight after `id.timeout` → `.failed(.timedOut)`.
    /// false: marks the attempt with no watchdog and leaves an armed one alone (the folder list stays visible, REDESIGN-STORAGE D5).
    private func beginBlock(_ id: BlockID, showsLoading: Bool = false, armsWatchdog: Bool = true) {
        updateBlock(id) { $0.begin(at: Date(), showsLoading: showsLoading) }
        guard armsWatchdog else { return }
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

    @ObservationIgnored private var thermalObserver: NSObjectProtocol?

    // MARK: - Lifecycle (SPEC §4 contract)

    func start() {
        // A restart builds a new collector with no cached disk value, so its first tick must read.
        diskSchedule.requestRead()
        guard fastTask == nil else { return }
        observeThermalState()
        gate.logsTransitions = ProcessInfo.processInfo.arguments.contains("-visibilityProbe")   // D11
        // REDESIGN-NOTIFY: banners only while the gate is hidden — the app not frontmost or no window on screen (D13 of REDESIGN-NOTIFY; `isPaused` mirrors the gate); a click parks a destination for the view (R5).
        NotificationCenterClient.shared.shouldPresentBanner = { [weak self] in self?.isPaused ?? true }
        NotificationCenterClient.shared.onOpen = { [weak self] page in self?.requestNavigation(to: Destination(page)) }
        NotificationCenterClient.shared.install()

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
        // Disk is read every 30 s or on request (`DiskReadSchedule`, IDLE-WORK-TRIM).
        fastSamplePrimed = false   // a new fastBox collector primes again
        fastTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // SAMPLER-OCCLUSION-GATE: park with no wake-ups while hidden; on resume sample at once (D6). After a
                // gap over 30 s the CPU delta is an average nobody watched: forget the baseline and let this sample
                // prime again (D6a) — `fastSamplePrimed = false` turns its nil CPU into "no verdict".
                let reprime: Bool
                if self.gate.state == .hidden {
                    let hiddenFor = await self.gate.waitUntilVisible()
                    guard !Task.isCancelled else { return }
                    reprime = ResumePolicy.reprimesDeltas(hiddenFor: hiddenFor)
                    if reprime { self.fastSamplePrimed = false }
                    self.diskSchedule.requestRead()   // IDLE-WORK-TRIM: a resumed window reads at once (R2)
                } else {
                    reprime = false
                }

                // collectFast() blocks briefly on syscalls — hop off the main actor for
                // it, then resume back on the main actor (this Task inherited MainActor
                // isolation from start(), so resuming the continuation lands here).
                let readsDisk = self.diskSchedule.shouldRead(now: self.time.now())
                self.beginBlock(.cpu)
                self.beginBlock(.memory)
                let (snap, socTempC, gpuUtil, pressure): (LiveSnapshot, Int?, Int?, MemoryPressureLevel?) = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let sp = PerfSignposts.begin(PerfSignposts.liveFastRead)
                        if reprime { fastBox.value.resetDeltaBaselines() }
                        let s = fastBox.value.collectFast(readsDisk: readsDisk)
                        // Block N7: same background hop — one HID pass costs ~50 ms.
                        let soc = ThermalSensors.socTemperature(
                            from: ThermalHIDReader.readTemperatureSensors())
                        let gpu = GPUStats.readDeviceUtilization()
                        let pressure = LiveCollector.readMemoryPressure()
                        sp.end()
                        continuation.resume(returning: (s, soc.map { Int($0.rounded()) }, gpu, pressure))
                    }
                }
                guard !Task.isCancelled else { return }
                let apply = PerfSignposts.begin(PerfSignposts.liveFastApply)
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
                if readsDisk { self.diskSampledAt = snap.t; if self.gate.logsTransitions { print("disk: read at \(snap.t)") } }
                if self.battery != snap.battery { self.battery = snap.battery }
                if self.socTempC != socTempC { self.socTempC = socTempC }
                if self.gpuUtil != gpuUtil { self.gpuUtil = gpuUtil }
                if self.memPressure != pressure { self.memPressure = pressure }
                self.lastSampleAt = snap.t
                if let cpu = snap.cpu {
                    self.recordCPUSample(cpu, at: snap.t)
                    Self.appendTrimmed(&self.cpuHistory, (snap.t, cpu.user + cpu.sys))
                }
                // SOC-DETAILS D6: one memory append, no new system call. A failed GPU read is kept as nil (a gap).
                Self.appendTrimmed(&self.gpuHistory, (snap.t, gpuUtil))
                apply.end()
                // `self.report` is a partial during a collect and a partial must never be
                // assessed — it would resurrect the header churn (V2-HEADER-CHURN). But the
                // live disk/swap readings are ready every tick, so instead of freezing the
                // whole verdict for the 10–30 s of a pass, assess the LAST COMMITTED report
                // together with the FRESH live snapshot: report-derived checks stay exactly
                // as they were when the pass started, live-derived ones keep moving
                // (V2-HONEST-READINGS, A11).
                // `homeReport` is that choice (ARCH-MODEL-SPLIT, P5).
                let assess = PerfSignposts.begin(PerfSignposts.liveFastAssess)
                self.setAssessment(self.assessed(self.homeReport))
                assess.end()

                try? await Task.sleep(for: .seconds(self.settings.fastIntervalSeconds))
            }
        }

        // Slow task (~6s): the process tables and wake holders (via `ps` + `top` + `pmset`).
        // No setAssessment here — the next fast tick assesses with the new topApps.
        slowTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // SAMPLER-OCCLUSION-GATE: park while hidden; the process delta is re-primed after a gap over 30 s (D6a)
                let reprime: Bool
                if self.gate.state == .hidden {
                    let hiddenFor = await self.gate.waitUntilVisible()
                    guard !Task.isCancelled else { return }
                    reprime = ResumePolicy.reprimesDeltas(hiddenFor: hiddenFor)
                } else {
                    reprime = false
                }

                // sampleProcesses() is async and suspends while `/bin/ps` and `/usr/bin/top`
                // run (and, on the FIRST tick only, while it sleeps 0.6 s to prime its CPU
                // baseline) — it runs on the global executor, not the main thread.
                let procsSp = PerfSignposts.begin(PerfSignposts.liveSlowProcs)
                let procs = await CommandRunner.$qos.withValue(.utility) {
                    if reprime { procBox.value.resetDeltaBaselines() }
                    return await procBox.value.sampleProcesses(limit: LiveCollector.topProcessCount)
                }
                procsSp.end()
                guard !Task.isCancelled else { return }
                let wakeSp = PerfSignposts.begin(PerfSignposts.liveSlowWake)
                let wake = await CommandRunner.$qos.withValue(.utility) { await WakeHolders.sample() }
                wakeSp.end()
                guard !Task.isCancelled else { return }

                let apply = PerfSignposts.begin(PerfSignposts.liveSlowApply)
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
                apply.end()

                try? await Task.sleep(for: .seconds(6))
            }
        }

        // SMART sampler (~5 min): SmartToolsController owns it (ARCH-MODEL-SPLIT block 5).
        smart.startSampling()

        loadCachedReportFromDisk()
        Task { [weak self] in await self?.refreshClaudeBackup(); await self?.claudeRun.refreshJob() }

        // MOONPORT-RENAME: everything below can raise a macOS prompt (the report pass asks System Events for the login
        // items and its folder count walks Desktop, Documents and Downloads; the probes open protected folders), so it
        // waits while the Welcome panel is up. With no panel it runs here, as before.
        welcome.whenOpen { [weak self] in
            guard let self, self.fastTask != nil else { return }   // stop() ran while the panel was up
            self.storage.reprobeProtectedLocations()
            self.refreshReport(trigger: .automatic)
            // Hourly folder-size count (SIZES-BACKGROUND): StorageController owns the 60 s poll; skipped while paused.
            self.storage.startSizeSchedule()
        }

        // SAMPLER-OCCLUSION-GATE: the one slow clock. Hidden: the assessment tick for notifications (D3). Always, once a
        // pass has completed: the daily History point (D5), whether or not another pass ever runs. Own LiveCollector
        // (one instance per task, see the fastBox/procBox comment above); it never reads CPU (collectFast(readsCPU: false)).
        let bgBox = UncheckedSendableBox(LiveCollector())
        schedulerTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.schedulerIntervalSeconds))
                guard let self, !Task.isCancelled else { return }
                if self.gate.state == .hidden { await self.backgroundTick(using: bgBox) }
                guard !Task.isCancelled, self.hasCompletedPass, self.homeReport.system != nil else { continue }
                self.history.snapshotIfDue(self.homeReport, live: self.live)
            }
        }
    }

    /// Cold-launch disk cache (Block N5): if a report from a previous run exists on
    /// disk, show it in the Report sheet (ReportSheet) immediately (with a staleness caption) while
    /// the background collect() refreshes it. Raw text only — FullReport is not
    /// serialized, so the Overview cards still fill in progressively from the live
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
        schedulerTask?.cancel()
        schedulerTask = nil
        afterPassQueue.removeAll()   // PASS-WAIT-PARTIAL: queued landings never run after stop()
        smart.stop()
        brew.stop()
        energy.stop()
        startupItems.stop()
        timeMachine.stop()
        claudeRun.stop()
        crashReports.stop()
        security.stop()
        storage.stop()
        for watchdog in blockWatchdogs.values { watchdog.cancel() }
        blockWatchdogs.removeAll()
        if let o = thermalObserver { NotificationCenter.default.removeObserver(o); thermalObserver = nil }
    }

    /// THERMAL-STATE: Apple requires reading `thermalState` before registering, or the notification is not delivered.
    private func observeThermalState() {
        guard thermalObserver == nil else { return }
        applyThermalState(ProcessInfo.processInfo.thermalState)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyThermalState(ProcessInfo.processInfo.thermalState) }
        }
    }

    private func applyThermalState(_ s: ProcessInfo.ThermalState) {
        let level = ThermalLevel(s)
        if thermal != level { thermal = level }
    }

    /// Public entry. `.button` only from the "Refresh report" button.
    func refreshReport(trigger: CollectTrigger) {
        // Fixture mode shows a fixed dataset and must write nothing: no pass, no update check,
        // no size count (the same predicate MacDashboardApp uses to skip start()).
        guard !VisualFixture.isRequested else { return }
        storage.startUpdateCheckIfNeeded(trigger: trigger)      // before the in-flight guard: a press mid-pass still gets a check
        storage.startSizeCountIfNeeded(trigger: trigger)        // before the in-flight guard
        guard !isCollectingReport else {
            reportRefreshPending = CollectTrigger.merged(reportRefreshPending, trigger); return
        }
        beginPass(trigger: trigger)
    }

    /// Starts one pass. Internal, not private: ReportHostTests starts a pass on a fake collect without `refreshReport`'s update check and folder count (PASS-WAIT-PARTIAL).
    func beginPass(trigger: CollectTrigger) {
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
                // PASS-WAIT-PARTIAL: updater landings queued during this pass run now — after the commit below has
                // set `report = final` and assessed it, before a pending pass starts — so this pass cannot overwrite
                // them. A cancelled pass (stop()) drops them.
                let landings = self.afterPassQueue
                self.afterPassQueue = []
                if !Task.isCancelled {
                    for work in landings {
                        work()
                        assert(!self.isCollectingReport, "an afterPass landing must not start a pass (ReportHost contract)")
                    }
                }
                // CRASH-REPORT-DISMISS: a hide / unhide / delete / Refresh parked during this pass re-scans now, so this
                // pass's crash section (taken with the hidden list it started with) does not stand. Deliberately NOT
                // guarded by `!Task.isCancelled` (fix wave 2, C3): a cancelled pass must not leave `crashReports.action` working.
                self.crashReports.passEnded()
                if let pending = self.reportRefreshPending {
                    self.reportRefreshPending = nil
                    // Don't relaunch from a cancelled task (stop() during shutdown). beginPass, not
                    // refreshReport: the update check for that request was decided when it was requested.
                    if !Task.isCancelled { self.beginPass(trigger: pending) }
                }
            }

            let cachedBrew = self.brew.cachedSnapshot(now: self.time.now())
            let hiddenCrashes = self.crashReports.hiddenNames
            let pass = PerfSignposts.begin(PerfSignposts.reportPass)
            let collected = await CommandRunner.$qos.withValue(trigger.commandQoS) {
                await self.passCollect(hiddenCrashes, cachedBrew) { partial in
                    let section = PerfSignposts.begin(PerfSignposts.reportSection)
                    defer { section.end() }
                    // onSection is @MainActor; we're already isolated here. Detect the
                    // .smart section's arrival by its progress-flag transition (false/absent
                    // -> true) BEFORE overwriting self.report, so `smart.updatedAt` reflects the
                    // launch/manual report too, not only the periodic sampler.
                    if partial.progress["smart"] == true, self.report.progress["smart"] != true {
                        self.smart.markUpdated()
                    }
                    // REDESIGN-BACKUPS: the Time Machine destination section's arrival stamps the Backups card's «updated HH:MM».
                    let tmKey = ReportSection.tmDest.rawValue
                    if partial.progress[tmKey] == true, self.report.progress[tmKey] != true {
                        self.timeMachine.markUpdated()
                    }
                    // Scan block (D14): decided by the system section — system_profiler — of this pass.
                    let systemKey = ReportSection.system.rawValue
                    if partial.progress[systemKey] == true, self.report.progress[systemKey] != true {
                        if partial.system?.modelName != nil { self.succeedBlock(.scan) }
                        else { self.failBlock(.scan, .noReading) }
                    }
                    var shown = partial
                    self.storage.applyBackground(to: &shown)
                    self.report = shown
                    if let sys = partial.system { self.lastKnownSystem = sys }
                    // Deliberately NOT recomputed here: `partial` has most sections nil during
                    // a collect, so assessing it makes "not collected yet" and "nothing is
                    // wrong" the same value and the header thrashes between them. The verdict
                    // updates once the pass completes, at the `final` assessment below.
                    self.smart.recomputeToolsState()
                }
            }
            pass.end()
            guard !Task.isCancelled else { return }
            let commit = PerfSignposts.begin(PerfSignposts.reportCommit)
            var final = collected
            self.storage.applyBackground(to: &final)

            // brew actually ran this pass — refill the session cache (never with a failed check; see BrewController.record).
            if cachedBrew == nil { self.brew.record(final) }

            // Daily History snapshot when due (REDESIGN-SETTINGS), from the committed report — before it is shown and assessed.
            self.history.passCommitted(final, live: self.live)

            self.report = final
            if let sys = final.system { self.lastKnownSystem = sys }
            self.hasCompletedPass = true
            self.setAssessment(self.assessed(final))
            // BATTERY-HEALTH-UNIFY: with the raw switch on, Home needs a fresh ioreg read once per pass (the Battery page
            // reads on its own every 3 s while open; readBatteryNow drops a call that overlaps a read in flight).
            if self.settings.assessmentSettings.batteryShowsRawMac, !VisualFixture.isRequested { Task { await self.readBatteryNow() } }
            // A pass whose system section came back empty (scan block failed, D7) keeps the previous report:
            // the sheet shows «not updated · showing the HH:MM report» over the old text (02-home §4 failed).
            if final.system?.modelName != nil {
                let now = Date()
                self.commitReportText(self.reportSummaryInput(report: final, generatedAt: final.createdAt ?? now))
                self.reportUpdatedAt = now
            }
            self.smart.recomputeToolsState()
            commit.end()
        }
    }

    /// V2-HEADER-CHURN: assess only a committed report.
    private func mergeBackgroundIntoCommitted() {
        if isCollectingReport {
            storage.applyBackground(to: &lastCommittedReport)   // what the fast tick assesses mid-pass
            storage.applyBackground(to: &report)                // display of the partial; NOT assessed
            setAssessment(assessed(lastCommittedReport))
            // The pass commit calls storage.applyBackground on `final`, so it picks this result up too.
        } else {
            storage.applyBackground(to: &report)
            setAssessment(assessed(report))
            // Re-render only when a report has been committed (a background result after a failed first pass
            // must not produce a summary of a half-collected report). reportUpdatedAt unchanged: it is the pass time.
            if reportText != nil {
                commitReportText(reportSummaryInput(report: report, generatedAt: reportUpdatedAt ?? Date()))
            }
        }
    }

    /// ARCH-TEXT-EDGE: a language switch re-derives every text the model caches from the data already collected.
    /// No pass, no command: the assessment comes from `homeReport` (the committed report, as the fast tick does), the
    /// report text is re-rendered only when no pass is in flight (the pass commit re-renders it otherwise).
    /// Fixture mode is a no-op, as in `refreshReport`: the fixture never sets the fields `assessed` reads.
    func relocalize() {
        guard !VisualFixture.isRequested else { return }
        setAssessment(assessed(homeReport))
        guard !isCollectingReport, reportText != nil else { return }
        commitReportText(reportSummaryInput(report: report, generatedAt: reportUpdatedAt ?? Date()))
    }

    /// `ReportHost.afterPass` (PASS-WAIT-PARTIAL): `work` now when no pass is in flight, else queued for the pass's
    /// `defer` (see `afterPassQueue`). Replaces the bounded 15 s poll, whose give-up wrote into the partial (findings C1–C3).
    func runAfterPass(_ work: @escaping @MainActor () -> Void) {
        guard isCollectingReport else { work(); return }
        afterPassQueue.append(work)
    }

    /// REDESIGN-BATTERY: the Battery page's ioreg loop, awaited by the page's `.task` and cancelled by SwiftUI when the
    /// page unmounts. Never under the visual fixture: it would overwrite the fixture detail with live data
    /// (HIDDEN-CONTENT-WORK; the guard used to sit in BatteryPage). Parked on the gate while the window is hidden
    /// (SAMPLER-OCCLUSION-GATE): no `ioreg` spawns with nobody watching; the first read after resume is immediate.
    func runBatteryLoop() async {
        guard !VisualFixture.isRequested else { return }
        while !Task.isCancelled {
            if gate.state == .hidden {               // SAMPLER-OCCLUSION-GATE: no ioreg while the window is hidden
                _ = await gate.waitUntilVisible()
                guard !Task.isCancelled else { return }
            }
            let read = PerfSignposts.begin(PerfSignposts.batteryRead)
            await readBatteryNow()
            read.end()
            try? await Task.sleep(for: .seconds(BatteryPageModel.refreshSeconds))
        }
    }

    /// REDESIGN-BATTERY: one ioreg read for the Battery page (the page's `.task` calls it every
    /// `BatteryPageModel.refreshSeconds`). Awaits the read, so the loop never overlaps itself; a call that arrives
    /// while an earlier read is still in flight (the page re-mounted before it returned) returns at once.
    func readBatteryNow() async {
        guard !batteryReading else { return }
        batteryReading = true
        defer { batteryReading = false }
        beginBlock(.battery)
        let result = await BatteryInspector.read()
        switch result {
        case .detail(let d):
            if batteryDetail != d {
                let rawMoved = batteryDetail?.rawHealthOneDecimal != d.rawHealthOneDecimal
                batteryDetail = d
                // BATTERY-HEALTH-UNIFY D5: with the raw switch on the verdict depends on this read.
                if rawMoved, settings.assessmentSettings.batteryShowsRawMac { reassessCommitted() }
            }
            succeedBlock(.battery)
        case .timedOut:
            failBlock(.battery, .timedOut)
        case .unavailable:
            failBlock(.battery, .noReading)
        }
    }

    /// MOCKUP-CONSISTENCY S6: one ioreg read for the Home Battery tile's «Maximum» when no detail exists yet. Awaited
    /// by HomeView's `.task`, cancelled with it when Home unmounts; Home re-mounts each time it is shown, so the guard
    /// keeps this to one read per app run unless the Battery page never ran. Nothing under the visual fixture (the
    /// fixture detail must stay; same guard as `runBatteryLoop`), nothing on a Mac without a battery.
    func readBatteryOnceForHome() async {
        guard !VisualFixture.isRequested, batteryDetail == nil,
              battery != nil || homeReport.battery != nil else { return }
        await readBatteryNow()
    }

    /// Manual, on-demand process-list re-sample (V2-SETTINGS-PROCLIMIT follow-up).
    /// Its caller is the Processes card's Quit flow (REDESIGN-CPU); the CPU and Memory «Try again» callers were removed in REFRESH-BUTTONS-AUDIT, and
    /// the "Apply" button of the retired process-limit setting was removed in
    /// REDESIGN-FOUNDATION. One-shot, independent of the periodic slowTask sampler — a fresh
    /// LiveCollector instance is created per call, never shared with a concurrent
    /// sampler pass (see the fastBox/procBox comment in start()). Because
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

    // MARK: - Window visibility (SAMPLER-OCCLUSION-GATE) — fed by AppActivityMonitor (AppShell.swift)

    /// The monitor's facts go to the gate; a hidden → visible transition runs the one resume hook that is not a
    /// loop's own: the SMART controller's deferred volume read (DISK-MOUNT-LIVE).
    func applyVisibility(windows: [WindowFacts], appActive: Bool) {
        if gate.update(windows: windows, appActive: appActive) != nil { smart.resumeVolumeRead() }
    }

    /// App became active: the storage controller ends the Full Disk Access wait and re-probes the protected locations (REDESIGN-STORAGE D14).
    func appDidBecomeActive() {
        // MOONPORT-RENAME: the probes open protected folders; the launch work re-probes once the Welcome panel is closed.
        guard !welcome.isHolding else { return }
        storage.appDidBecomeActive()
    }

    // MARK: - Process actions (ARCH-ENGINE-GUARD: moved from ProcessCards)

    /// D8/D15/D16 of REDESIGN-CPU: the full signal flow off the main actor (a privileged retry blocks on the
    /// administrator dialog); the pid-reuse guard compares `expectedPath` with the pid's current executable.
    func signalProcess(_ sig: Int32, pid: Int32, expectedPath: String?) async -> ProcessInspector.SignalOutcome {
        await Task.detached { ProcessInspector.signal(sig, pid: pid, expectedPath: expectedPath) }.value
    }

    /// proc_pidpath and the owner sysctl are cheap syscalls, but nothing here may ever block the UI.
    func processDetail(pid: Int32) async -> ProcDetail {
        await Task.detached { ProcessInspector.detail(pid: pid) }.value
    }

    // MARK: - Report path

    /// Documented, narrowly-scoped `@unchecked Sendable` crossing for a type that is
    /// genuinely single-threaded-by-contract but not marked Sendable. See usage above.
    private final class UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    /// SAMPLER-OCCLUSION-GATE D3: while the gate is hidden, one native read per minute keeps the assessment current for
    /// REDESIGN-NOTIFY (disk, swap, battery and memory pressure are its live inputs). No CPU % (this collector's delta
    /// would span 60 s), no thermal pass, no GPU read, no block verdict, no history point: those belong to the visible
    /// cadence. Assesses `homeReport`, never a partial (assessment-complete-collect).
    private func backgroundTick(using box: UncheckedSendableBox<LiveCollector>) async {
        let (snap, pressure): (LiveSnapshot, MemoryPressureLevel?) = await withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async {
                c.resume(returning: (box.value.collectFast(readsCPU: false), LiveCollector.readMemoryPressure()))
            }
        }
        guard !Task.isCancelled else { return }
        if load != snap.load { load = snap.load }
        if let mem = snap.mem, self.mem != mem { self.mem = mem }
        if swap != snap.swap { swap = snap.swap }
        if disk != snap.disk { disk = snap.disk }
        diskSampledAt = snap.t
        if battery != snap.battery { battery = snap.battery }
        if memPressure != pressure { memPressure = pressure }
        lastSampleAt = snap.t
        setAssessment(assessed(homeReport))
        if gate.logsTransitions { print("gate: tick hidden at \(snap.t)") }
    }

    /// Suppresses redundant @Observable notifications when the new assessment
    /// is value-equal to the current one (e.g. repeated live ticks with no
    /// change in the attention items).
    private func setAssessment(_ n: Assessment) {
        if assessment != n { assessment = n }
        guard hasCompletedPass else { return }
        let fresh = notifyEdges.update(items: n.items, enabled: settings.notifyEnabled, now: now())
        if !fresh.isEmpty { notify(fresh) }
    }

    /// REDESIGN-NOTIFY: posts one notification per freshly appeared item; asks for authorization lazily (R6, D3).
    private func notify(_ items: [AttentionItem]) {
        let client = NotificationCenterClient.shared
        func post() {
            for item in items {
                guard let cat = NotifyCategory.category(for: item.kind) else { continue }
                client.deliver(identifier: "attention.\(item.kind.rawValue)", title: L.settingsNotifyLabel(cat),
                               body: item.fullTextWithWhy, page: cat.page)
            }
        }
        client.status { status in
            switch status {
            case .authorized: post()
            case .notDetermined: client.requestAuthorization { granted in if granted { post() } }
            case .denied: break
            }
        }
    }

    /// REDESIGN-NOTIFY: called by the notification client on a click (R5); the view navigates and consumes it.
    /// IDLE-WORK-TRIM: the next fast tick re-reads free space. Called after the app itself changed it (snapshot deletion
    /// through ReportHost, Trash emptied by AdviceActionDispatch) and on a relevant volume mount/unmount (VolumeMountMonitor).
    func requestDiskRead() { diskSchedule.requestRead() }

    func requestNavigation(to destination: Destination) {
        externalDestination = destination
        externalDestinationSerial += 1
        actions.ensureWindowShown()
    }
    func consumeExternalDestination() -> Destination? { defer { externalDestination = nil }; return externalDestination }

    /// The model's only way to build an `Assessment` (SLEEP-IGNORE-APP): every path passes
    /// the current ignore list, so an ignored wake holder cannot re-warn through a path that
    /// forgot it. Reads settings ONLY through `settings.assessmentSettings` (ARCH-SETTINGS-PATH; EngineBoundaryTests enforces it).
    private func assessed(_ r: FullReport) -> Assessment {
        let s = settings.assessmentSettings
        return Assess.assess(report: r, live: live, language: L10nStore.shared.language, memPressure: memPressure, topApps: topApps,
                             wakeHolders: wakeHolders, ignoredWakeHolders: s.ignoredWakeHolders,
                             claudeBackup: claudeBackup, claudeAttempt: claudeRun.attempt, backupStaleHours: s.backupStaleHours,
                             lowSpacePercent: s.lowSpacePercent,
                             claudeLogPath: BackupLog.resolvedURLs(custom: s.claudeLogPath).log.path,
                             batteryRawPercent: batteryDetail?.rawHealthOneDecimal, batteryPrefersRaw: s.batteryShowsRawMac,
                             now: fixtureNow ?? Date())
    }

    private static func defaultReportURL() -> URL {
        AppInfo.supportFolderURL(create: true).appendingPathComponent("mac_report.txt")
    }
}
