// Engine/StorageController.swift
// ARCH-MODEL-SPLIT block 7: the background macOS update check (COLLECT-FASTPATH), the folder-size count
// (SIZES-BACKGROUND: hourly schedule, Storage page Refresh / Try again, failure back-off, Trash bookkeeping) and the
// Full Disk Access state (REDESIGN-STORAGE D13/D14), moved out of the coordinator unchanged in behaviour. Owns both
// caches, the overlay of their results onto a report and the Task handles; reaches the coordinator's overlay merge and
// the folders block only through ReportHost.
import Foundation
import Observation

@MainActor
@Observable
final class StorageController {
    struct Dependencies {
        /// One `softwareupdate -l` (`ReportCollector().checkUpdates()`) at utility QoS; nil = failed.
        var checkUpdates: @MainActor () async -> UpdatesCache?
        /// One folder-size count (`ReportCollector().countFolderSizes()`) at the trigger's command QoS; nil = failed.
        var countFolderSizes: @MainActor (CollectTrigger) async -> FolderSizes?
        /// Protected locations that refuse a read (`ProtectedLocations.denied` over `DirectoryAccess.probe`).
        var deniedLocations: @MainActor () -> [ProtectedLocation]
        /// Opens a System Settings pane by URL; the coordinator passes `AppActions.openSettingsPane`.
        var openSettingsPane: @MainActor (String) -> Void
        /// The two JSON caches in the app's data folder (`updates_cache.json`, `folder_sizes_cache.json`).
        var loadUpdates: @MainActor () -> UpdatesCache?
        var saveUpdates: @MainActor (UpdatesCache) -> Void
        var loadFolderSizes: @MainActor () -> FolderSizes?
        var saveFolderSizes: @MainActor (FolderSizes) -> Void

        /// A function, not a `static let`: the data folder and the pane opener come from the coordinator.
        static func live(directory: URL, openSettingsPane: @escaping @MainActor (String) -> Void) -> Dependencies {
            let updatesURL = directory.appendingPathComponent("updates_cache.json")
            let sizesURL = directory.appendingPathComponent("folder_sizes_cache.json")
            return Dependencies(
                checkUpdates: { await CommandRunner.$qos.withValue(.utility) { await ReportCollector().checkUpdates() } },
                countFolderSizes: { trigger in
                    await CommandRunner.$qos.withValue(trigger.commandQoS) { await ReportCollector().countFolderSizes() }
                },
                deniedLocations: { ProtectedLocations.denied(home: NSHomeDirectory(), probe: DirectoryAccess.probe) },
                openSettingsPane: openSettingsPane,
                loadUpdates: { UpdatesCacheStore.load(from: updatesURL) },
                // A failed write costs one re-check next launch; not surfaced.
                saveUpdates: { try? UpdatesCacheStore.save($0, to: updatesURL) },
                loadFolderSizes: { FolderSizesCacheStore.load(from: sizesURL) },
                // A failed write costs one recount next launch.
                saveFolderSizes: { try? FolderSizesCacheStore.save($0, to: sizesURL) })
        }
    }

    /// The size schedule's poll (SIZES-BACKGROUND): cheap; the 1 h rule inside `startSizeCountIfNeeded` decides.
    static let schedulePoll: Duration = .seconds(60)

    // MARK: State — update check (COLLECT-FASTPATH)

    /// Last successful update check, persisted. Source of truth for report.updates/updatesCheckedAt/updatesCheckDuration.
    private var updatesCache: UpdatesCache?
    /// True while a check runs; the Security page's Refresh and Updates card read it.
    private(set) var isCheckingUpdates = false
    /// Bumped by every start and by `stop()`: a superseded check touches nothing when it returns.
    private var updateCheckGeneration = 0

    // MARK: State — folder sizes (SIZES-BACKGROUND)

    /// Last successful count, persisted. Source of truth for report.homeDirs/serviceDirs/…Unreadable/folderSizesCountedAt.
    private var folderSizes: FolderSizes?
    /// True while a count runs; the Storage page's Refresh and the Folders caption read it.
    private(set) var isCountingSizes = false
    /// REDESIGN-STORAGE: set by `trashWasEmptied()`, cleared by the next successful count. The Folders caption reads
    /// `trashFreedBytes`; nothing reads `trashEmptiedAt` today (moved unchanged, ARCH-MODEL-SPLIT block 7 D11).
    private(set) var trashFreedBytes: Int64?
    private(set) var trashEmptiedAt: Date?
    /// Bumped by every start and by `stop()`: a superseded count touches nothing when it returns.
    private var sizeCountGeneration = 0
    /// Time the last count finished without a result (SIZES-FAIL-BACKOFF). Automatic triggers wait the 1 h window after
    /// it; the button does not. In-memory only: a relaunch makes one fresh attempt. Cleared by a successful count.
    private var sizeCountFailedAt: Date?

    // MARK: State — Full Disk Access (REDESIGN-STORAGE D13/D14)

    /// Protected locations the last probe found refused.
    private(set) var fdaDenied: [ProtectedLocation] = []
    /// «Open Privacy settings…» was pressed and the app has not been re-activated yet.
    private(set) var fdaAwaitingReturn = false

    /// The in-flight update check; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var updateCheckTask: Task<Void, Never>?
    /// The in-flight folder count; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var sizeCountTask: Task<Void, Never>?
    /// The 60 s schedule `startSizeSchedule()` runs; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var scheduleTask: Task<Void, Never>?

    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies) {
        self.host = host; self.time = time; self.deps = deps
        updatesCache = deps.loadUpdates()
        folderSizes = deps.loadFolderSizes()
    }

    /// The saved count's time; the coordinator marks the folders block «last good» with it at launch.
    var folderSizesCountedAt: Date? { folderSizes?.countedAt }

    // MARK: - Overlay (coordinator → controller)

    /// Both background overlays; the coordinator runs every report it shows or commits through here, so a result
    /// landing mid-pass cannot be lost.
    func applyBackground(to r: inout FullReport) {
        applyUpdates(to: &r)
        applyFolderSizes(to: &r)
    }

    private func applyUpdates(to r: inout FullReport) {
        r.updates = updatesCache?.items
        r.updatesCheckedAt = updatesCache?.checkedAt
        r.updatesCheckDuration = updatesCache?.durationSeconds
        r.progress[ReportSection.updates.rawValue] = (updatesCache != nil) || !isCheckingUpdates
    }

    /// No saved count => nil sizes (assessment skips them) and progress false while a count is running.
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

    // MARK: - Update check

    /// Starts one background check unless one is in flight or (automatic triggers) the 6 h cache is fresh. Called by
    /// the coordinator's `refreshReport` and, through its `checkUpdates` closure, by the Security page's Refresh.
    func startUpdateCheckIfNeeded(trigger: CollectTrigger) {
        guard ReportCollector.shouldStartUpdateCheck(trigger: trigger, checkedAt: updatesCache?.checkedAt,
                                                     inFlight: isCheckingUpdates, now: time.now()) else { return }
        isCheckingUpdates = true
        updateCheckGeneration += 1
        let gen = updateCheckGeneration
        host.update { self.applyUpdates(to: &$0) }               // display only: spinner if no cache yet
        let check = deps.checkUpdates
        updateCheckTask = Task(priority: .utility) { [weak self] in
            let result = await check()
            guard let self, gen == self.updateCheckGeneration else { return }   // superseded by stop(): touch nothing
            self.isCheckingUpdates = false
            guard !Task.isCancelled else { return }
            if let result {
                self.updatesCache = result
                self.deps.saveUpdates(result)
            }
            self.host.mergeBackgroundIntoCommitted()             // also on failure: spinner -> "unavailable"
        }
    }

    // MARK: - Folder sizes

    /// `armsWatchdog`: Try again on a visible error — a Wait comes back, so the 10 s watchdog is armed even though a
    /// count exists. With no count at all the Wait is on screen and the watchdog is always armed; otherwise the list
    /// stays visible and no watchdog runs (REDESIGN-STORAGE D5).
    func startSizeCountIfNeeded(trigger: CollectTrigger, armsWatchdog: Bool = false) {
        guard ReportCollector.shouldStartSizeCount(trigger: trigger, countedAt: folderSizes?.countedAt,
                                                   failedAt: sizeCountFailedAt,
                                                   inFlight: isCountingSizes, now: time.now()) else { return }
        isCountingSizes = true
        let showsWait = folderSizes == nil || armsWatchdog
        host.beginBlock(.folders, showsWait, showsWait)          // Wait on screen: arm the 10 s watchdog (D5)
        sizeCountGeneration += 1
        let gen = sizeCountGeneration
        host.update { self.applyFolderSizes(to: &$0) }           // display only: spinner if no cache yet
        let count = deps.countFolderSizes
        sizeCountTask = Task(priority: trigger.taskPriority) { [weak self] in
            let result = await count(trigger)
            guard let self, gen == self.sizeCountGeneration else { return }
            self.isCountingSizes = false
            guard !Task.isCancelled else { return }
            if let result {
                self.host.succeedBlock(.folders)
                self.folderSizes = result
                self.sizeCountFailedAt = nil
                self.trashFreedBytes = nil; self.trashEmptiedAt = nil    // the new count includes the real Trash state
                self.deps.saveFolderSizes(result)
            } else {
                self.host.failBlock(.folders, .noReading)
                self.sizeCountFailedAt = self.time.now()          // automatic triggers back off 1 h; the button still forces
            }
            self.host.mergeBackgroundIntoCommitted()             // also on failure: spinner -> "unavailable" when no cache
            self.reprobeProtectedLocations()
        }
    }

    /// Hourly folder count (SIZES-BACKGROUND): polls every 60 s; nothing starts while paused (SPEC §1.4,
    /// `no-unseen-work`). Called by the coordinator's `start()`; replaces a running schedule.
    func startSizeSchedule() {
        scheduleTask?.cancel()
        let time = self.time, poll = Self.schedulePoll
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                await time.sleep(poll)
                guard let self, !Task.isCancelled else { return }
                if !self.host.isPaused() { self.startSizeCountIfNeeded(trigger: .automatic) }
            }
        }
    }

    /// REDESIGN-STORAGE D22: the Storage page's Refresh = a folder recount with the `.button` trigger. Live disk figures
    /// already tick every interval; SMART has its own button.
    func refreshNow() { startSizeCountIfNeeded(trigger: .button) }

    /// REDESIGN-STORAGE: Try again on the folder-count error. A count still in flight is not restarted: the Wait and a
    /// fresh 10 s watchdog come back and the running count's result still lands.
    func retryFolderCount() {
        if isCountingSizes {
            host.beginBlock(.folders, true, true)
        } else {
            startSizeCountIfNeeded(trigger: .button, armsWatchdog: true)
        }
    }

    /// REDESIGN-STORAGE D12: the Trash was emptied through Finder. Drops the `.Trash` entry from the saved count,
    /// records what it held, saves the cache (same write a count does) and merges, so Home's chip and the Disk note
    /// lose the Trash too.
    func trashWasEmptied() {
        let trash = FileManager.default.homeDirectoryForCurrentUser.path + "/.Trash"
        if var sizes = folderSizes, let entry = sizes.homeDirs.first(where: { $0.path == trash }) {
            trashFreedBytes = entry.bytes
            sizes.homeDirs.removeAll { $0.path == trash }
            folderSizes = sizes
            deps.saveFolderSizes(sizes)
        }
        trashEmptiedAt = time.now()
        host.mergeBackgroundIntoCommitted()
    }

    // MARK: - Full Disk Access

    /// REDESIGN-STORAGE D13/D14: re-reads which protected locations are refused. If fewer are refused than before
    /// (access was just granted), a `.button` recount starts so the sizes include the newly readable folders.
    func reprobeProtectedLocations() {
        let next = deps.deniedLocations()
        if next.count < fdaDenied.count && !fdaDenied.isEmpty { startSizeCountIfNeeded(trigger: .button) }
        if next != fdaDenied { fdaDenied = next }
    }

    /// REDESIGN-STORAGE D14: opens the Full Disk Access pane; busy until the app is re-activated.
    func openFullDiskAccessSettings() {
        fdaAwaitingReturn = true
        deps.openSettingsPane(AdvicePanes.fullDiskAccess)
    }

    /// The app became active (the coordinator's `appDidBecomeActive()`): the Full Disk Access wait ends and the
    /// protected locations are re-probed.
    func appDidBecomeActive() {
        fdaAwaitingReturn = false
        reprobeProtectedLocations()
    }

    // MARK: - Fixture, teardown

    /// Visual fixture only (REDESIGN-SECURITY): the update-check flag the Security page's Refresh and Updates card read.
    func applyFixture(checkingUpdates: Bool) { isCheckingUpdates = checkingUpdates }

    /// Visual fixture only (REDESIGN-STORAGE): the saved count, overlaid onto the shown report (folder fields only).
    func applyFixture(folderSizes sizes: FolderSizes?) {
        folderSizes = sizes
        host.update { self.applyFolderSizes(to: &$0) }
    }

    /// Visual fixture only (REDESIGN-STORAGE): the protected locations the Full Disk Access probe found refused.
    func applyFixture(fdaDenied denied: [ProtectedLocation]) { fdaDenied = denied }

    /// Cancels the update check, the count and the schedule; the coordinator's `stop()` calls it. A cancelled check or
    /// count no longer counts as in flight, and its result (if the command still returns) is dropped by the generation.
    func stop() {
        updateCheckTask?.cancel(); updateCheckTask = nil
        updateCheckGeneration += 1; isCheckingUpdates = false
        sizeCountTask?.cancel(); sizeCountTask = nil
        scheduleTask?.cancel(); scheduleTask = nil
        sizeCountGeneration += 1; isCountingSizes = false
    }
}
