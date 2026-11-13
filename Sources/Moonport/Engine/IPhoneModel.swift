// Engine/IPhoneModel.swift
// App-only (talks to MobileDeviceTransport, which is app-only). Owns the iPhone
// mode state: remembered devices (persisted via IPhoneStore, R13), live connections and
// per-device status. Everything here runs on the main actor; the transport completes
// its callbacks on main.

import Foundation
import Observation

@MainActor @Observable
final class IPhoneModel {
    /// Under `-visualFixture` every store lives in a temp folder (IPHONE-UNLINK D3): the fixture's tiles can be
    /// unlinked, their archives trashed or claims saved without touching the user's App Support or Documents.
    static let shared: IPhoneModel = {
        guard VisualFixture.isRequested else { return IPhoneModel(oldDefaultArchiveRoot: IPhoneStore.legacyDocumentsArchiveRoot()) }
        let tmp = FileManager.default.temporaryDirectory
        let pid = ProcessInfo.processInfo.processIdentifier
        removeStaleFixtureFolders(in: tmp, keeping: pid)
        let dir = tmp.appendingPathComponent("md-fixture-\(pid)", isDirectory: true)
        return IPhoneModel(store: IPhoneStore(url: dir.appendingPathComponent("iphones.json")),
                           archiveRoot: dir.appendingPathComponent("archive", isDirectory: true),
                           // Nor does it look into the user's Documents for the old app's archive folder (MOONPORT-RENAME D4).
                           oldDefaultArchiveRoot: dir.appendingPathComponent("archive-old", isDirectory: true),
                           logTypeStore: IPhoneLogTypeStore(url: dir.appendingPathComponent(IPhoneLogTypeStore.fileName)),
                           // The fixture never reads the user's caches root and never reaches the network (IPHONE-IPSW D15).
                           ipsw: IPSWModel(downloader: IPSWDownloader(stagingRoot: dir.appendingPathComponent("ipsw", isDirectory: true)),
                                           downloadsDir: { dir.appendingPathComponent("Downloads", isDirectory: true) },
                                           networkAllowed: false))
    }()

    /// Removes `md-fixture-<pid>` folders of processes that no longer run. Failures are ignored.
    private nonisolated static func removeStaleFixtureFolders(in tmp: URL, keeping own: Int32) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: tmp.path) else { return }
        for n in names where n.hasPrefix("md-fixture-") {
            guard let pid = Int32(n.dropFirst("md-fixture-".count)), pid > 0, pid != own else { continue }
            if kill(pid, 0) != 0 && errno == ESRCH { try? fm.removeItem(at: tmp.appendingPathComponent(n)) }
        }
    }

    enum DeviceStatus: Equatable {
        case connected
        case reading
        case needsTrust
        case readFailed(String)
        case remembered
    }

    var devices: [IPhoneDeviceRecord] = []
    /// deviceKey → handle of the phone's current connection (USB preferred, IPHONE-WIFI).
    var connected: [String: IPhoneHandle] = [:]
    /// Link of every attached handle (IPHONE-WIFI). Observed: the tile and page labels read it.
    var links: [IPhoneHandle: IPhoneLink] = [:]
    /// deviceKey → the Wi-Fi handle of a phone that is connected by USB at the same time (D4). Memory only.
    @ObservationIgnored private var standby: [String: IPhoneHandle] = [:]
    /// IPHONE-WIFI D15: device keys whose Wi-Fi connection dropped and did not come back within `wifiStallDelay`.
    /// Memory only. The device page shows the stall note for these.
    var wifiStalled: Set<String> = []
    /// D15: seconds after a Wi-Fi detach before the note shows (D15). Tests shorten it.
    /// 300 s (user 2026-11-11): a locked, sleeping phone drops off usbmuxd and comes back by itself within 9-164 s
    /// (6 drops in 12 min, V4), while a phone whose Wi-Fi was switched off and on never comes back without a restart.
    @ObservationIgnored var wifiStallDelay: TimeInterval = 300
    @ObservationIgnored private var wifiStallTasks: [String: Task<Void, Never>] = [:]
    /// D15: true while `applyWifiSetting(false)` drops handles. The user's own «off» arms no note.
    @ObservationIgnored private var droppingWifiBySetting = false
    var status: [String: DeviceStatus] = [:]
    /// Attached handles not yet identified (waiting for trust, or the read failed).
    var pendingHandles: Set<IPhoneHandle> = []
    /// True while the Devices list shows its empty notice, which carries its own «Search again».
    var listShowsEmptyNotice: Bool { transportAvailable && devices.isEmpty && visiblePending.isEmpty }
    /// Status of each pending handle (`.needsTrust` or `.readFailed`).
    var pendingStatus: [IPhoneHandle: DeviceStatus] = [:]
    var lastSnapshot: [String: IPhoneSnapshot] = [:]
    /// IPHONE-IPSW (D1): firmware lookups and the one download, owned for the process lifetime so a download survives page changes.
    let ipsw: IPSWModel
    var transportAvailable = true
    /// Crash-log listing per device (memory only).
    var logs: [String: [IPhoneLogEntry]] = [:]
    /// Per device: "<path>|<size>|<mtime ms>" → parsed header (bug_type, process, timestamp;
    /// `IPhoneLogHeader()` = none). Replaced by each successful listing (files gone from the
    /// phone drop out), extended by type batches, saved to `iphone-log-types.json` v2
    /// (IPHONE-LOAD-SPEED R3, IPHONE-CRASHLOG-ACTIONS D1).
    var headerCache: [String: [String: IPhoneLogHeader]] = [:]
    var logsLoading = InFlightReads<IPhoneHandle>()
    /// Devices whose last crash-log listing failed; cleared by a successful listing or detach.
    var logsFailed: Set<String> = []
    /// Sysdiagnose import (Stage 5). Archive entries are memory only; the latest import of
    /// a device replaces the previous list.
    var archiveLogs: [String: [IPhoneLogEntry]] = [:]
    var importing: [String: ImportProgress] = [:]
    /// DEVICE-ARCHIVE-CLEANUP D14: device key → name of the kept archive whose last move to the Trash failed
    /// (memory only; cleared at the next attempt and when an import starts).
    var keptTrashFailed: [String: String] = [:]
    /// Last import result per device: the archive name with its summary, or the error.
    var importResult: [String: Result<(name: String, summary: ImportSummary), ImportError>] = [:]
    /// IPHONE-HISTORY-MIXUP: an import paused on an archive that looks like another phone's;
    /// the device's import card shows it as a dialog. Memory only.
    var importQuestion: [String: ImportIdentityQuestion] = [:]
    /// The paused import's continuation per device, resumed by `answerImportQuestion`.
    @ObservationIgnored private var importAnswer: [String: CheckedContinuation<Bool, Never>] = [:]
    /// DEVICE-ARCHIVE-CLEANUP: the «Create new sysdiagnose» request per device (memory only; nil = none shown).
    var sysdiagnoseRequest: [String: SysdiagnoseRequestPhase] = [:]
    /// What happened on the phone after the last import per device (memory only; nil = not an own archive).
    var phoneCleanup: [String: PhoneCleanup] = [:]
    @ObservationIgnored private var openRequests: [String: SysdiagnoseRequest] = [:]
    /// The running poll loop per device; exists only while `SysdiagnoseDir.shouldPoll` is true (Decision 7).
    /// Tag of the latest `requestSysdiagnose` start per device; a listing callback of an older start does nothing.
    @ObservationIgnored private var requestStarts: [String: UUID] = [:]
    @ObservationIgnored private var requestTasks: [String: Task<Void, Never>] = [:]
    /// Devices whose import card is mounted (`IPhoneImportCard` onAppear/onDisappear).
    @ObservationIgnored private var requestPanelShown: Set<String> = []
    /// The gate's verdict
    /// (`AppModel.isPaused`, SAMPLER-OCCLUSION-GATE), handed over by AppShell.swift. Starts false: the
    /// monitor reports the first change; under -visualFixture it never exists and nothing polls anyway.
    @ObservationIgnored private var windowPaused = false
    /// IPHONE-LIVE-BATTERY: devices whose battery card is mounted (`IPhoneDeviceView` onAppear/onDisappear).
    @ObservationIgnored private var batteryCardShown: Set<String> = []
    /// The running live-battery loop per device; exists only while `IPhoneLiveBattery.shouldRun` holds (R2).
    @ObservationIgnored private var liveBatteryTasks: [String: Task<Void, Never>] = [:]
    /// Devices with a live battery read queued or running (R3).
    @ObservationIgnored private var liveBatteryInFlight: Set<String> = []
    /// When the last battery reading of each device ended (live read of any outcome, or a snapshot that read the battery) (D6).
    @ObservationIgnored private var batteryCheckedAt: [String: Date] = [:]
    /// Devices whose running import paused on the «another phone» question (Decision 3).
    @ObservationIgnored private var identityAsked: Set<String> = []

    // MARK: Crash-log actions (IPHONE-CRASHLOG-ACTIONS)

    enum LogAction: Equatable { case console, save }
    enum LogActionState: Equatable {
        case copying(LogAction, done: Int64, total: Int64)
        /// The local copy exists; writing it to the folder the user chose.
        case saving
        case saved
        case failed(IPhoneLogActionError)
    }
    /// Per `logActionKey` (memory only). Cleared for a device on detach.
    var logAction: [String: LogActionState] = [:]
    /// Live files already copied this run: "<deviceKey>|<logCacheKey>" → local file (memory only, Decision 3).
    @ObservationIgnored private var logCopies: [String: URL] = [:]
    /// Opens a local file and reports success on the main actor. The view passes the app's Console opener
    /// (ARCH-ENGINE-GUARD: the Engine names no view type, D4).
    typealias LogOpener = (URL, @escaping @MainActor (Bool) -> Void) -> Void

    static func logActionKey(deviceKey: String, entry: IPhoneLogEntry) -> String {
        let src: String
        switch entry.source { case .live: src = "live"; case .archive(let n): src = "a:" + n }
        return deviceKey + "|" + src + "|" + entry.id
    }

    func isLogActionBusy(_ key: String) -> Bool {
        switch logAction[key] {
        case .copying?, .saving?: return true
        default: return false
        }
    }

    /// The local file for `entry`: the archive copy (Decision 1), a copy made earlier this run, or a fresh
    /// read-only copy from the phone into its own temp folder. On failure sets `logAction[key]` and returns nil.
    /// Returns nil silently when the phone detached during the copy (its rows are gone, F12).
    private func localCopy(deviceKey: String, entry: IPhoneLogEntry, action: LogAction, key: String) async -> URL? {
        let fm = FileManager.default
        if case .archive = entry.source {
            guard let u = entry.localURL, fm.fileExists(atPath: u.path) else {
                logAction[key] = .failed(.gone); return nil
            }
            return u
        }
        let cacheKey = deviceKey + "|" + IPhoneData.logCacheKey(path: entry.path, size: entry.size, modified: entry.modified)
        if let u = logCopies[cacheKey], IPhoneCrashLog.fileSize(u) == entry.size { return u }
        logCopies[cacheKey] = nil
        guard let h = connected[deviceKey] else { logAction[key] = .failed(.disconnected); return nil }
        let tmp = fm.temporaryDirectory
        guard IPhoneCrashLog.hasRoom(available: IPhoneCrashLog.availableBytes(at: tmp), size: entry.size) else {
            logAction[key] = .failed(.noSpace); return nil
        }
        guard let dir = IPhoneCrashLog.makeCopyDir(in: tmp) else { logAction[key] = .failed(.copyFailed); return nil }
        let dest = dir.appendingPathComponent((entry.path as NSString).lastPathComponent)
        let total = entry.size
        logAction[key] = .copying(action, done: 0, total: total)
        let ok: Bool = await withCheckedContinuation { cont in
            transport.copyFile(h, remotePath: entry.path, size: total, to: dest,
                               progress: { [weak self] done in
                                   guard let self, case .copying(let a, _, _)? = self.logAction[key] else { return }
                                   self.logAction[key] = .copying(a, done: Int64(done), total: total)
                               },
                               completion: { cont.resume(returning: $0) })
        }
        guard attached.contains(h) else { try? fm.removeItem(at: dir); logAction[key] = nil; return nil }
        guard ok, IPhoneCrashLog.fileSize(dest) == total else {
            try? fm.removeItem(at: dir); logAction[key] = .failed(.copyFailed); return nil
        }
        logCopies[cacheKey] = dest
        return dest
    }

    /// «Open in Console». No-op while an action on the same row runs, or for a file Console is not offered for.
    /// `open` is the Console opener the view passes in; the Engine names no view type.
    func openLogInConsole(deviceKey: String, entry: IPhoneLogEntry, open: @escaping LogOpener) {
        let key = Self.logActionKey(deviceKey: deviceKey, entry: entry)
        guard !isLogActionBusy(key),
              IPhoneCrashLog.canOpenInConsole(name: (entry.path as NSString).lastPathComponent, size: entry.size)
        else { return }
        logAction[key] = .copying(.console, done: 0, total: entry.size)
        Task { [weak self] in
            guard let self, let url = await self.localCopy(deviceKey: deviceKey, entry: entry, action: .console, key: key)
            else { return }
            open(url) { [weak self] ok in
                self?.logAction[key] = ok ? nil : .failed(.consoleFailed)
            }
        }
    }

    /// «Save to Mac…» after the save panel returned `dest`.
    func saveLog(deviceKey: String, entry: IPhoneLogEntry, to dest: URL) {
        let key = Self.logActionKey(deviceKey: deviceKey, entry: entry)
        guard !isLogActionBusy(key) else { return }
        logAction[key] = .copying(.save, done: 0, total: entry.size)
        Task { [weak self] in
            guard let self, let url = await self.localCopy(deviceKey: deviceKey, entry: entry, action: .save, key: key)
            else { return }
            self.logAction[key] = .saving
            let ok = await Task.detached(priority: .userInitiated) { IPhoneCrashLog.writeSaved(from: url, to: dest) }.value
            // Decision 3: a big live copy made for a Save is not kept.
            if entry.source == .live, entry.size > IPhoneCrashLog.consoleMaxBytes {
                logCopies = logCopies.filter { $0.value != url }
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            guard ok else { self.logAction[key] = .failed(.saveFailed); return }
            self.logAction[key] = .saved
            try? await Task.sleep(nanoseconds: UInt64(IPhoneCrashLog.savedConfirmSeconds * 1_000_000_000))
            if self.logAction[key] == .saved { self.logAction[key] = nil }
        }
    }

    /// Collapse of a row: a finished state (saved / failed) is forgotten; a running copy is not touched.
    func clearLogActionResult(deviceKey: String, entry: IPhoneLogEntry) {
        let key = Self.logActionKey(deviceKey: deviceKey, entry: entry)
        if !isLogActionBusy(key) { logAction[key] = nil }
    }

    /// Identity and parts per connected device. Memory only (R13, D10); cleared on detach.
    var identity: [String: [IPhoneIdentityField]] = [:]
    var identityLoading = InFlightReads<IPhoneHandle>()
    /// Devices whose last identity read failed; cleared by a successful read or detach.
    var identityFailed: Set<String> = []
    /// Separate storage read per connected device (R5). Memory only; cleared on detach.
    var storage: [String: IPhoneStorageRead] = [:]
    var storageLoading = InFlightReads<IPhoneHandle>()

    /// The identity rows with the storage state applied.
    func identityRows(_ key: String) -> [IPhoneIdentityField]? {
        identity[key].map { IPhoneData.identityRows($0, storage: storage[key]) }
    }

    /// "Find iPhone" → restart of the connection service (Stage 7).
    var restartingService = false
    var restartError: String?
    /// The open device page (nil = tiles). Memory only; survives a Mac↔iPhone switch.
    var selectedDeviceKey: String?
    /// REDESIGN-IPHONE: where kept archives live (`<archiveRoot>/<deviceKey>/<name>`); resolved from
    /// `AppSettings.iphoneArchiveFolder`, changed only through `setArchiveFolder`.
    private(set) var archiveRoot: URL
    /// MOONPORT-RENAME D4: the old app's default archive folder (`~/Documents/<old name>/iPhone`). Readers look here after
    /// `archiveRoot`, so a row resolves before, during and after the first-launch archive move. Test seam, like `archiveRoot:`.
    let oldDefaultArchiveRoot: URL
    enum ArchiveFolderError: Equatable { case couldNotMove(Int) }
    /// Why the last «Choose…» left the folder unchanged; cleared by the next successful change.
    var archiveFolderError: ArchiveFolderError?
    var archiveFolderBusy = false
    /// BATTERY-HEALTH-UNIFY D9: Settings › Devices › «Raw battery health»; the tile and battery card take it as a parameter.
    var prefersRawHealth: Bool { AppSettings.shared.batteryShowsRawIPhone }
    enum ReadTrigger: Equatable { case attach, user }
    /// Per device: when the last automatic crash-log listing started (memory only).
    @ObservationIgnored private var autoReadAt: [String: Date] = [:]

    // MARK: Unlink (IPHONE-UNLINK)
    enum UnlinkNotice: Equatable {
        case saveFailed(name: String)
        case trashFailed(count: Int, folder: String)
    }
    /// Shown as a banner on the Devices list; cleared by the next unlink, «Search again» and a service restart.
    var unlinkNotice: UnlinkNotice?
    /// Connections of phones unlinked while attached: ignored until they detach (Decision 2). Memory only.
    @ObservationIgnored private var ignoredHandles: Set<IPhoneHandle> = []

    private let store: IPhoneStore
    private let logTypeStore: IPhoneLogTypeStore
    private let transport: MobileDeviceTransport
    private var started = false
    /// Every handle the transport reported attached and has not detached yet. A read that
    /// lands after its handle detached is dropped (the detach wins).
    private var attached: Set<IPhoneHandle> = []
    /// True while the transport reports a phone attached, even before its first read lands. Observed through `attached`.
    var hasAttachedPhone: Bool { !attached.isEmpty }

    init(store: IPhoneStore = IPhoneStore(url: IPhoneStore.defaultURL()),
         transport: MobileDeviceTransport = .shared,
         archiveRoot: URL? = nil,
         oldDefaultArchiveRoot: URL,
         logTypeStore: IPhoneLogTypeStore = IPhoneLogTypeStore(
            url: AppInfo.supportFolderURL.appendingPathComponent(IPhoneLogTypeStore.fileName)),
         ipsw: IPSWModel = IPSWModel()) {
        self.ipsw = ipsw
        self.store = store
        self.logTypeStore = logTypeStore
        self.transport = transport
        self.oldDefaultArchiveRoot = oldDefaultArchiveRoot
        self.archiveRoot = archiveRoot ?? AppSettings.resolveArchiveFolder(
            raw: AppSettings.shared.iphoneArchiveFolder, defaultRoot: IPhoneStore.defaultArchiveRoot())
    }

    /// GATE-TABLE-PROBE: only the installed app starts the live transport. A bench copy (tools/bench-app.sh,
    /// app.moonport.bench), `swift run` or a test process never does: the transport reads the system-wide
    /// usbmuxd/pairing state, which a synthetic CFFIXED_USER_HOME does not isolate, so a reachable real phone
    /// would join the bench's device list.
    nonisolated static func startsLiveTransport(bundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        bundleID == AppInfo.bundleID
    }

    func start() {
        guard !started else { return }
        started = true
        // Temp folders of imports a previous run left behind; removed before any import can start.
        IPhoneData.removeStaleImportRoots(in: FileManager.default.temporaryDirectory)
        // IPHONE-CRASHLOG-ACTIONS (Decision 3): crash-log copies of the previous run.
        IPhoneData.removeStaleImportRoots(in: FileManager.default.temporaryDirectory, prefix: IPhoneCrashLog.tempPrefix)
        devices = store.load()
        headerCache = logTypeStore.load(keeping: Set(devices.map(\.id)))
        for d in devices { status[d.id] = .remembered }
        // IPHONE-IPSW (R14, R18): a download stopped in an earlier run shows as stopped. Disk only, before the transport starts.
        ipsw.restoreParked(knownIdentifiers: Set(devices.compactMap(\.productType)))
        migrateLegacyArchivesIfNeeded()
        transportAvailable = transport.isAvailable
        guard transportAvailable else { return }
        guard Self.startsLiveTransport() else {
            NSLog("[Moonport] iPhone transport not started: bundle id \(Bundle.main.bundleIdentifier ?? "nil") is not \(AppInfo.bundleID)")
            return
        }
        transport.start(networkEnabled: AppSettings.shared.iphoneWifi) { [weak self] event in self?.handle(event) }
    }

    /// Settings › iPhone › «Connect over Wi-Fi» (the view's Binding setter, D10).
    func setWifiEnabled(_ on: Bool) {
        AppSettings.shared.iphoneWifi = on
        applyWifiSetting(on)
    }

    /// Off: every Wi-Fi handle is detached here at once (the transport's own detach events then find nothing); then the
    /// transport is told. Internal for tests (the model is not started there, so the transport is not called).
    func applyWifiSetting(_ on: Bool) {
        if !on {
            droppingWifiBySetting = true
            for (h, link) in links where link == .wifi { handle(.detached(h)) }
            droppingWifiBySetting = false
            for t in wifiStallTasks.values { t.cancel() }
            wifiStallTasks = [:]
            wifiStalled = []
        }
        if started, transportAvailable { transport.setNetworkEnabled(on) }
    }

    /// One-time move of archives kept before REDESIGN-IPHONE (Decision 5). Cheap when there is nothing to do:
    /// one `fileExists` on App Support, nothing under ~/Documents is touched unless legacy files exist.
    private func migrateLegacyArchivesIfNeeded() {
        let legacy = IPhoneStore.legacyArchiveRoot()
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let moves = ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: archiveRoot)
        guard !moves.isEmpty else { return }
        Task.detached(priority: .utility) {
            let outcome = ArchiveMigration.execute(moves)
            guard outcome.clean else { return }   // whatever stayed is still found through keptArchiveURL
            let dirs = Set(moves.map { $0.source.deletingLastPathComponent() })
            ArchiveMigration.removeEmptyDirectories(
                dirs.flatMap { [$0, $0.deletingLastPathComponent()] } + [legacy], stopAt: legacy.deletingLastPathComponent())
        }
    }

    /// The kept file, wherever it is: the archive folder first, then the old app's default folder in Documents, then the
    /// legacy App Support place; nil when gone.
    func keptArchiveURL(deviceKey: String, name: String) -> URL? {
        Self.resolveKeptArchive(archiveRoot: archiveRoot, oldDefaultRoot: oldDefaultArchiveRoot, legacyRoot: IPhoneStore.legacyArchiveRoot(),
                                deviceKey: deviceKey, name: name)
    }

    /// A name from `iphones.json` is a plain file name: not empty, `.`, `..`, and without a path separator.
    nonisolated static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name == (name as NSString).lastPathComponent
    }

    nonisolated static func resolveKeptArchive(archiveRoot: URL, oldDefaultRoot: URL, legacyRoot: URL, deviceKey: String, name: String) -> URL? {
        let fm = FileManager.default
        let current = archiveRoot.appendingPathComponent(deviceKey, isDirectory: true).appendingPathComponent(name)
        if fm.fileExists(atPath: current.path) { return current }
        let old = oldDefaultRoot.appendingPathComponent(deviceKey, isDirectory: true).appendingPathComponent(name)
        if fm.fileExists(atPath: old.path) { return old }
        let legacy = legacyRoot.appendingPathComponent(deviceKey, isDirectory: true)
            .appendingPathComponent("sysdiagnose", isDirectory: true).appendingPathComponent(name)
        return fm.fileExists(atPath: legacy.path) ? legacy : nil
    }

    /// DEVICE-ARCHIVE-CLEANUP D14: moves one kept archive (the Mac copy only, no phone call) to the Trash and drops
    /// its name from the record; battery history and logs stay. `url` is the one `keptArchiveURL` resolved for the
    /// row: its folder must be one of the three places that function looks in and its last component must be `name`,
    /// else nothing happens. A file already gone counts as removed. Any other failure keeps the row and sets
    /// `keptTrashFailed`. Never deletes outright: only the Trash move.
    func trashKeptArchive(deviceKey: String, name: String, url: URL,
                          trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        keptTrashFailed[deviceKey] = nil
        let folder = url.deletingLastPathComponent().standardizedFileURL
        let current = archiveRoot.appendingPathComponent(deviceKey, isDirectory: true).standardizedFileURL
        let oldDefault = oldDefaultArchiveRoot.appendingPathComponent(deviceKey, isDirectory: true).standardizedFileURL
        let legacy = IPhoneStore.legacyArchiveRoot().appendingPathComponent(deviceKey, isDirectory: true)
            .appendingPathComponent("sysdiagnose", isDirectory: true).standardizedFileURL
        guard name == url.lastPathComponent, folder == current || folder == oldDefault || folder == legacy,
              let i = devices.firstIndex(where: { $0.id == deviceKey }),
              devices[i].keptArchives.contains(name) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            do { try trash(url) } catch {
                keptTrashFailed[deviceKey] = name
                return
            }
        }
        devices[i].keptArchives.removeAll { $0 == name }
        try? store.save(devices)
    }

    /// Settings › Devices › Choose…: moves every kept archive to `url`, then stores the setting. All or nothing:
    /// a skipped or failed file moves the moved ones back and reports the count.
    func setArchiveFolder(_ url: URL) async {
        // MOONPORT-RENAME D4: Choose… never plans while the first-launch archive move runs.
        _ = await LegacyArchiveMove.task?.value
        let new = url.standardizedFileURL
        guard !archiveFolderBusy, new != archiveRoot.standardizedFileURL else { return }
        archiveFolderBusy = true
        defer { archiveFolderBusy = false }
        archiveFolderError = nil
        let old = archiveRoot
        let moves = ArchiveMigration.plan(from: old, to: new)
        let outcome = await Task.detached(priority: .userInitiated) { ArchiveMigration.execute(moves) }.value
        if outcome.clean {
            let def = IPhoneStore.defaultArchiveRoot().standardizedFileURL
            AppSettings.shared.iphoneArchiveFolder = new == def ? nil : new.path
            archiveRoot = new
            let dirs = Array(Set(moves.map { $0.source.deletingLastPathComponent() }))
            await Task.detached(priority: .utility) { ArchiveMigration.removeEmptyDirectories(dirs, stopAt: old) }.value
        } else {
            let back = ArchiveMigration.reversed(outcome)
            _ = await Task.detached(priority: .userInitiated) { ArchiveMigration.execute(back) }.value
            archiveFolderError = .couldNotMove(outcome.skipped.count + outcome.failed.count)
        }
    }

    /// Tiles order: connected first, then by `lastSeen` descending.
    var sortedDevices: [IPhoneDeviceRecord] {
        devices.sorted { a, b in
            let ac = connected[a.id] != nil, bc = connected[b.id] != nil
            if ac != bc { return ac }
            return a.lastSeen > b.lastSeen
        }
    }

    /// Pending tiles in a stable order.
    var sortedPending: [IPhoneHandle] {
        pendingHandles.sorted { $0.raw < $1.raw }
    }

    /// The link of a device's current connection; nil when not connected.
    func link(_ key: String) -> IPhoneLink? { connected[key].flatMap { links[$0] } }
    /// The link of a pending handle (USB when unknown).
    func pendingLink(_ h: IPhoneHandle) -> IPhoneLink { links[h] ?? .usb }
    /// Tests: the Wi-Fi handle kept for `key` while it is connected by USB.
    func standbyHandle(_ key: String) -> IPhoneHandle? { standby[key] }
    /// Pending tiles to show: a Wi-Fi handle is hidden while any device is connected by USB (D9).
    var visiblePending: [IPhoneHandle] {
        let usbConnected = connected.values.contains { links[$0] == .usb }
        return sortedPending.filter { !(usbConnected && links[$0] == .wifi) }
    }

    func handle(_ event: IPhoneTransportEvent) {
        switch event {
        case .attached(let h, let link):
            attached.insert(h)
            links[h] = link
            guard !ignoredHandles.contains(h) else { return }
            restartError = nil
            refresh(handle: h, trigger: .attach)
        case .detached(let h):
            guard attached.contains(h) || links[h] != nil || ignoredHandles.contains(h) else { return }   // already dropped (setting off) or unknown
            let link = links.removeValue(forKey: h)
            ignoredHandles.remove(h)
            attached.remove(h)
            let key = connected.first(where: { $0.value == h })?.key
            // Reads in flight over `h` for its device, measured before `detach` clears them (D5).
            let hadLogs = key.map { logsLoading.contains($0) } ?? false
            let hadIdentity = key.map { identityLoading.contains($0) || storageLoading.contains($0) } ?? false
            logsLoading.detach(h)
            identityLoading.detach(h)
            storageLoading.detach(h)
            pendingHandles.remove(h)
            pendingStatus[h] = nil
            for (k, s) in standby where s == h { standby[k] = nil }
            guard let key else { return }
            if let next = standby.removeValue(forKey: key), attached.contains(next), !ignoredHandles.contains(next) {
                promote(key, to: next,
                        reloadLogs: hadLogs && !logsLoading.contains(key),
                        reloadIdentity: hadIdentity && !identityLoading.contains(key) && !storageLoading.contains(key))
                return
            }
            connected[key] = nil
            updatePolling(key)
            status[key] = .remembered
            identity[key] = nil
            storage[key] = nil
            identityFailed.remove(key)
            lastSnapshot[key] = nil
            batteryCheckedAt[key] = nil
            updateLiveBattery(key)          // connected and snapshot are gone: the loop stops
            logs[key] = nil
            logsFailed.remove(key)
            for k in logAction.keys where k.hasPrefix(key + "|live|") { logAction[k] = nil }
            if link == .wifi, !droppingWifiBySetting { armWifiStall(key) }
            if link == .usb {
                for p in pendingHandles where links[p] == .wifi { refresh(handle: p, trigger: .attach) }   // R4
            }
        }
    }

    /// The cable went and the phone is still reachable over Wi-Fi: the Wi-Fi handle becomes the connection; memory-only
    /// page state stays (R3, D5).
    private func promote(_ key: String, to next: IPhoneHandle, reloadLogs: Bool, reloadIdentity: Bool) {
        connected[key] = next
        clearWifiStall(key)
        status[key] = .connected
        updatePolling(key)
        updateLiveBattery(key)
        if reloadLogs { loadLogs(deviceKey: key) }
        if reloadIdentity { loadIdentity(deviceKey: key) }
    }

    /// D15: one check per drop. The note shows if the key has no connection when the delay ends.
    private func armWifiStall(_ key: String) {
        wifiStallTasks[key]?.cancel()
        let delay = wifiStallDelay
        wifiStallTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            wifiStallTasks[key] = nil
            if connected[key] == nil { wifiStalled.insert(key) }
        }
    }

    /// Tests: returns once every armed D15 stall check has finished or been cancelled.
    func waitForWifiStallChecks() async {
        for task in Array(wifiStallTasks.values) { await task.value }
    }

    private func clearWifiStall(_ key: String) {
        wifiStallTasks.removeValue(forKey: key)?.cancel()
        wifiStalled.remove(key)
    }

    func refresh(handle h: IPhoneHandle, trigger: ReadTrigger = .user) {
        guard !ignoredHandles.contains(h) else { return }
        if let key = connected.first(where: { $0.value == h })?.key {
            status[key] = .reading
        }
        let battery = trigger == .user || AppSettings.shared.iphoneAutoRead
        transport.readSnapshot(h, includeBattery: battery) { [weak self] result in
            self?.apply(result, for: h, trigger: trigger)
        }
    }

    /// The page's "Refresh".
    func refresh(deviceKey: String) {
        guard let h = connected[deviceKey] else { return }
        refresh(handle: h)
    }

    /// Lists the phone's crash logs (headers already in `headerCache` are not re-read).
    /// The listing is published before any header is read; the types follow in batches.
    /// No-op when the phone is not connected or a listing over the current connection is already running.
    func loadLogs(deviceKey: String) {
        guard let h = connected[deviceKey], let id = logsLoading.begin(deviceKey, handle: h) else { return }
        transport.listLogs(h, knownHeaders: headerCache[deviceKey] ?? [:], onListing: { [weak self] result in
            guard let self else { return }
            // A listing superseded by a newer one, or whose phone detached, is dropped.
            guard logsLoading.finish(deviceKey, id: id), attached.contains(h) else { return }
            switch result {
            case .success(let listing):
                logs[deviceKey] = listing.entries
                setHeaderCache(deviceKey, listing.known)
                logsFailed.remove(deviceKey)
            case .failure:
                logsFailed.insert(deviceKey)
            }
        }, onTypes: { [weak self] batch in
            // No request-id check: batches are keyed by file, so a batch of an older listing applies correctly.
            guard let self, attached.contains(h), connected[deviceKey] == h, let current = logs[deviceKey] else { return }
            let merged = IPhoneLogTypes.merge(current, batch)
            if merged != current { logs[deviceKey] = merged }
            setHeaderCache(deviceKey, IPhoneLogTypes.updatedCache(headerCache[deviceKey] ?? [:],
                                                                  entries: merged, batch: batch))
        })
    }

    /// Updates the in-memory type cache of one device and saves the file when it changed.
    private func setHeaderCache(_ key: String, _ cache: [String: IPhoneLogHeader]) {
        guard headerCache[key] != cache else { return }
        headerCache[key] = cache
        try? logTypeStore.save(headerCache.filter { k, _ in devices.contains { $0.id == k } })
    }

    /// Reads identity and parts of a connected phone; the result is held in memory only.
    /// No-op when the phone is not connected or a read over the current connection is already running.
    func loadIdentity(deviceKey: String) {
        guard let h = connected[deviceKey], let id = identityLoading.begin(deviceKey, handle: h) else { return }
        transport.readIdentity(h, language: L10nStore.shared.language) { [weak self] result in
            guard let self else { return }
            // A read superseded by a newer one, or whose phone detached, is dropped.
            guard identityLoading.finish(deviceKey, id: id), attached.contains(h) else { return }
            switch result {
            case .success(let fields):
                identity[deviceKey] = fields
                identityFailed.remove(deviceKey)
            case .failure:
                identityFailed.insert(deviceKey)
            }
        }
        loadStorage(deviceKey: deviceKey, handle: h)
    }

    /// The storage value in its own last-priority read (R5); the card shows «…» until it lands or
    /// 2 s after the read started on the transport thread. A value already held for this connection
    /// is kept (R19: page opens do not repeat the read); detach clears it.
    private func loadStorage(deviceKey: String, handle h: IPhoneHandle) {
        if case .value = storage[deviceKey] { return }
        // A stalled read is still in flight: keep its state; its late result still lands.
        guard let id = storageLoading.begin(deviceKey, handle: h) else { return }
        storage[deviceKey] = .waiting
        transport.readStorage(h, onStart: { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(IPhoneStorageRead.deadlineSeconds))
                guard let self, storageLoading.isCurrent(deviceKey, id: id) else { return }
                storage[deviceKey] = storage[deviceKey]?.afterDeadline()
            }
        }) { [weak self] result in
            guard let self, storageLoading.finish(deviceKey, id: id), attached.contains(h) else { return }
            if case .success(let bytes) = result { storage[deviceKey] = .result(bytes: bytes) } else { storage[deviceKey] = .missing }
        }
    }

    /// Runs one import. `keep` = "Parse and keep". Merges the derived battery points
    /// into the stored history and fills `archiveLogs` only on success. One import per
    /// device at a time.
    func importArchive(deviceKey: String, source: SysdiagnoseImporter.Source, keep: Bool,
                       deletesFromPhone: Bool = false) {
        guard importing[deviceKey] == nil, devices.contains(where: { $0.id == deviceKey }) else { return }
        phoneCleanup[deviceKey] = nil
        keptTrashFailed[deviceKey] = nil
        identityAsked.remove(deviceKey)
        if case .ready = sysdiagnoseRequest[deviceKey] { sysdiagnoseRequest[deviceKey] = nil }
        if case .phone(_, _, let size) = source {
            importing[deviceKey] = .copying(done: 0, total: size)
        } else {
            importing[deviceKey] = .extracting
        }
        updatePolling(deviceKey)   // the list watch stops during an import
        importResult[deviceKey] = nil
        let keepRoot = archiveRoot
        Task { [weak self] in
            let importer = SysdiagnoseImporter()
            let result = await importer.run(source: source, deviceKey: deviceKey, keep: keep, keepRoot: keepRoot,
                                            confirm: { [weak self] name, mAh in
                                                await self?.confirmIdentity(deviceKey: deviceKey, archiveName: name,
                                                                            archiveMAh: mAh) ?? false
                                            }) { [weak self] p in
                self?.importing[deviceKey] = p
            }
            self?.finishImport(deviceKey: deviceKey, source: source, deletesFromPhone: deletesFromPhone,
                              result: result)
        }
    }

    private func finishImport(deviceKey: String, source: SysdiagnoseImporter.Source,
                              deletesFromPhone: Bool, result: Result<ImportOutput, ImportError>) {
        importing[deviceKey] = nil
        updatePolling(deviceKey)   // the list watch returns after the import
        switch result {
        case .failure(let e):
            // A copy cut by a detach (cable pulled, Wi-Fi lost or switched off) is named as such; the importer has
            // already removed its temp folder, so nothing partial is kept.
            if e == .copyFailed, case .phone(let h, _, _) = source, !attached.contains(h) {
                importResult[deviceKey] = .failure(.interrupted)
            } else {
                importResult[deviceKey] = .failure(e)
            }
        case .success(let out):
            if let i = devices.firstIndex(where: { $0.id == deviceKey }) {
                devices[i].battery = IPhoneData.mergeImported(devices[i].battery, out.points)
                if let kept = out.summary.keptPath { devices[i].keptArchives.append(kept.lastPathComponent) }
                try? store.save(devices)
            }
            archiveLogs[deviceKey] = out.logs
            importResult[deviceKey] = .success((out.archiveName, out.summary))
            if case .phone(_, let remotePath, let size) = source {
                cleanUpPhone(deviceKey: deviceKey, remotePath: remotePath, size: size, summary: out.summary,
                             deletesFromPhone: deletesFromPhone)
            }
        }
    }

    /// Deletes the imported archive from the phone when it is an own claim and the import was full (§ Ownership).
    /// `deletesFromPhone` is the decision the choice dialog showed; a setting changed during the import does not alter it.
    private func cleanUpPhone(deviceKey: String, remotePath: String, size: Int64, summary: ImportSummary,
                              deletesFromPhone: Bool) {
        let name = (remotePath as NSString).lastPathComponent
        guard remotePath == SysdiagnoseDir.remotePath(name),
              let own = devices.first(where: { $0.id == deviceKey })?.ownArchives?.first(where: { $0.name == name })
        else { return }   // not an own archive: nothing is done or said
        if !deletesFromPhone { phoneCleanup[deviceKey] = .keptBySetting; return }
        guard own.size == size, SysdiagnoseDir.importAllowsDelete(summary, identityAsked: identityAsked.contains(deviceKey)) else {
            phoneCleanup[deviceKey] = .keptIncomplete
            return
        }
        guard let h = connected[deviceKey] else { phoneCleanup[deviceKey] = .notConnected; return }
        phoneCleanup[deviceKey] = .deleting
        transport.removeOwnArchive(h, path: remotePath, expectedSize: own.size) { [weak self] outcome in
            guard let self else { return }
            // A new import or an unlink in the meantime owns the message now; the claim bookkeeping below still runs.
            if self.devices.contains(where: { $0.id == deviceKey }), self.importing[deviceKey] == nil {
                self.phoneCleanup[deviceKey] = outcome
            }
            switch outcome {
            case .deleted, .alreadyGone, .changed:
                self.dropClaim(name, deviceKey: deviceKey)
                self.loadLogs(deviceKey: deviceKey)
            default:
                break   // the claim stays: a later full import of the same archive retries the delete
            }
        }
    }

    /// Called by the importer after parsing, before keeping or merging. Answers at once on a
    /// match or an unknown identity; on a mismatch publishes `importQuestion` and waits. Internal for `IPhoneImportQuestionTests`.
    func confirmIdentity(deviceKey: String, archiveName: String, archiveMAh: Set<Int>) async -> Bool {
        guard case .mismatch(let q) = IPhoneData.archiveIdentity(archiveName: archiveName, archiveMAh: archiveMAh,
                                                                 deviceKey: deviceKey, devices: devices) else { return true }
        identityAsked.insert(deviceKey)
        return await withCheckedContinuation { cont in
            Task { @MainActor in
                self.importAnswer[deviceKey] = cont
                self.importQuestion[deviceKey] = q
            }
        }
    }

    /// The import card's answer to `importQuestion[deviceKey]`. A second call is a no-op.
    func answerImportQuestion(deviceKey: String, proceed: Bool) {
        importQuestion[deviceKey] = nil
        importAnswer.removeValue(forKey: deviceKey)?.resume(returning: proceed)
    }

    /// IPHONE-UNLINK: true while `h` is a connection of a phone unlinked during it (tests read this).
    func isIgnored(_ h: IPhoneHandle) -> Bool { ignoredHandles.contains(h) }

    /// IPHONE-UNLINK Decision 4: no unlink while the app is busy with this phone — an import (or its other-phone
    /// question), the post-import deletion on the phone, a crash-log copy or save, or the archive folder being moved.
    func canUnlink(_ key: String) -> Bool {
        importing[key] == nil && importQuestion[key] == nil && !archiveFolderBusy
            && phoneCleanup[key] != .deleting
            && !logAction.keys.contains { $0.hasPrefix(key + "|") && isLogActionBusy($0) }
    }

    /// «Unlink device…» → Unlink. Order: save the store without the record (a failure changes nothing and shows
    /// `.saveFailed`), cancel the sysdiagnose request, clear memory, then move the kept archives the record names to
    /// the Trash off the main actor (resolved there like `keptArchiveURL`; names that are not plain file names are skipped). Never calls the
    /// transport. No-op for an unknown or malformed key or when `canUnlink` is false. `trash` is injected by tests.
    func unlink(deviceKey key: String,
                trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) async {
        guard IPhoneData.isDeviceKey(key), let record = devices.first(where: { $0.id == key }), canUnlink(key) else { return }
        unlinkNotice = nil
        let remaining = devices.filter { $0.id != key }
        do { try store.save(remaining) } catch {
            unlinkNotice = .saveFailed(name: record.name)
            return
        }
        cancelSysdiagnoseRequest(deviceKey: key)          // before the record goes (DEVICE-ARCHIVE-CLEANUP)
        requestPanelShown.remove(key)
        batteryCardShown.remove(key)
        devices = remaining
        if let pt = record.productType, !remaining.contains(where: { $0.productType == pt }) {
            ipsw.forgetModel(identifier: pt)                // D26: the last phone of this model took its stopped download along
        }
        if let h = connected[key] {
            ignoredHandles.insert(h)
            logsLoading.detach(h)
            identityLoading.detach(h)
            storageLoading.detach(h)
        }
        if let s = standby.removeValue(forKey: key) { ignoredHandles.insert(s) }
        clearWifiStall(key)
        connected[key] = nil
        updatePolling(key)                                 // the list watch stops with the connection
        status[key] = nil
        lastSnapshot[key] = nil
        batteryCheckedAt[key] = nil
        updateLiveBattery(key)
        logs[key] = nil
        logsFailed.remove(key)
        archiveLogs[key] = nil
        importResult[key] = nil
        keptTrashFailed[key] = nil
        phoneCleanup[key] = nil
        identityAsked.remove(key)
        identity[key] = nil
        identityFailed.remove(key)
        storage[key] = nil
        autoReadAt[key] = nil
        for k in logAction.keys where k.hasPrefix(key + "|") { logAction[k] = nil }
        for (k, url) in logCopies where k.hasPrefix(key + "|") {
            logCopies[k] = nil
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        if headerCache[key] != nil {
            headerCache[key] = nil
            try? logTypeStore.save(headerCache)
        }
        if selectedDeviceKey == key { selectedDeviceKey = nil }

        // Only a record that lists kept archives touches the archive folders: a phone without any never makes the
        // app open ~/Documents (no Files & Folders prompt, REDESIGN-IPHONE Decision 5).
        guard !record.keptArchives.isEmpty else { return }
        let names = record.keptArchives.filter(Self.isPlainFileName)
        let root = archiveRoot, oldDefault = oldDefaultArchiveRoot, legacy = IPhoneStore.legacyArchiveRoot()
        let failed: [URL] = await Task.detached(priority: .utility) {
            var failed: [URL] = []
            let urls = names.compactMap { IPhoneModel.resolveKeptArchive(archiveRoot: root, oldDefaultRoot: oldDefault, legacyRoot: legacy, deviceKey: key, name: $0) }
            for u in urls { do { try trash(u) } catch { failed.append(u) } }
            guard failed.isEmpty else { return failed }
            let own = root.appendingPathComponent(key, isDirectory: true)
            let legacyDir = legacy.appendingPathComponent(key, isDirectory: true)
            ArchiveMigration.removeEmptyDirectories([own], stopAt: root)
            ArchiveMigration.removeEmptyDirectories([oldDefault.appendingPathComponent(key, isDirectory: true)], stopAt: oldDefault)
            ArchiveMigration.removeEmptyDirectories(
                [legacyDir.appendingPathComponent("sysdiagnose", isDirectory: true), legacyDir], stopAt: legacy)
            return failed
        }.value
        if let first = failed.first {
            unlinkNotice = .trashFailed(count: failed.count, folder: first.deletingLastPathComponent().path)
        }
    }

    /// Internal for tests (IPHONE-WIFI).
    func apply(_ result: Result<IPhoneSnapshot, IPhoneReadError>, for h: IPhoneHandle, trigger: ReadTrigger) {
        guard attached.contains(h), !ignoredHandles.contains(h) else { return }
        switch result {
        case .success(let snap):
            let key = IPhoneData.deviceKey(udid: snap.udid)
            if let current = connected[key], current != h, attached.contains(current) {
                guard IPhoneLinkPolicy.replaces(links[h] ?? .usb, links[current] ?? .usb) else {
                    standby[key] = links[h] == .wifi ? h : standby[key]   // only a Wi-Fi handle waits as standby
                    pendingHandles.remove(h)
                    pendingStatus[h] = nil
                    return
                }
                standby[key] = current   // the USB handle takes over; the Wi-Fi one waits for the cable to go
            }
            let now = Date()
            var record = devices.first(where: { $0.id == key })
                ?? IPhoneDeviceRecord(id: key, name: snap.name, marketingName: nil, productType: nil,
                                      enclosureColor: nil, osVersion: nil, lastSeen: now,
                                      battery: [], keptArchives: [])
            record.name = snap.name
            record.marketingName = snap.marketingName
            record.productType = snap.productType
            record.enclosureColor = snap.enclosureColor
            record.osVersion = snap.osVersion
            record.lastSeen = now
            if let b = snap.battery, let point = IPhoneLiveBattery.historyPoint(b, points: record.battery, now: now) {
                record.battery = IPhoneData.upsertLive(record.battery, point)
            }
            if let i = devices.firstIndex(where: { $0.id == key }) {
                devices[i] = record
            } else {
                devices.append(record)
            }
            try? store.save(devices)
            pendingHandles.remove(h)
            pendingStatus[h] = nil
            connected[key] = h
            clearWifiStall(key)
            status[key] = .connected
            updatePolling(key)
            lastSnapshot[key] = snap
            if snap.batteryRead { batteryCheckedAt[key] = now }
            updateLiveBattery(key)
            if trigger == .attach, AppSettings.shared.iphoneAutoRead,
               IPhoneData.autoReadDue(last: autoReadAt[key], now: now) {
                autoReadAt[key] = now
                loadLogs(deviceKey: key)
            }
            if trigger == .attach { loadStorage(deviceKey: key, handle: h) }   // R19: the tile's storage total is read at attach
        case .failure(let err):
            if let key = connected.first(where: { $0.value == h })?.key {
                // An already-identified phone keeps its tile; show the failure on it.
                status[key] = err == .needsTrust ? .needsTrust : .readFailed(L.iphoneStatusFailed)
            } else {
                pendingHandles.insert(h)
                pendingStatus[h] = err == .needsTrust ? .needsTrust : .readFailed(L.iphoneStatusFailed)
            }
        }
    }

    // MARK: Sysdiagnose request (DEVICE-ARCHIVE-CLEANUP)

    /// «Create new sysdiagnose…»: lists the phone's archive folder, then shows the button instruction and polls
    /// until one new archive is claimed, the request ends, or the user stops it. One request per device.
    func requestSysdiagnose(deviceKey: String) {
        guard let h = connected[deviceKey], sysdiagnoseRequest[deviceKey]?.isActive != true else { return }
        sysdiagnoseRequest[deviceKey] = .preparing
        let start = UUID()
        requestStarts[deviceKey] = start
        let requestedAt = Date()   // before the listing: an archive started during it still counts as new
        transport.listSysdiagnoseDir(h) { [weak self] result in
            guard let self, self.requestStarts[deviceKey] == start,
                  self.sysdiagnoseRequest[deviceKey] == .preparing else { return }   // stopped or restarted meanwhile
            guard case .success(let entries) = result else {
                self.sysdiagnoseRequest[deviceKey] = .failed
                return
            }
            let names = Set(entries.filter { !$0.isDirectory }.map { ($0.path as NSString).lastPathComponent })
            self.openRequests[deviceKey] = SysdiagnoseRequest(id: UUID(), requestedAt: requestedAt, baseline: names)
            self.sysdiagnoseRequest[deviceKey] = .waiting
            self.updatePolling(deviceKey)
        }
    }

    /// Stops a running request or closes a finished one's message. Also for IPHONE-UNLINK before it removes a record.
    func cancelSysdiagnoseRequest(deviceKey: String) {
        requestStarts[deviceKey] = nil
        openRequests[deviceKey] = nil
        sysdiagnoseRequest[deviceKey] = nil
        updatePolling(deviceKey)
    }

    /// `IPhoneImportCard` reports its mount state (onAppear / onDisappear): the panel is visible only while the card is.
    /// FIX-LEFTOVERS (IPHONE-MIXUP): the card leaving the screen with the «another phone» question open is that
    /// question's Cancel — its sheet went with the card, and an unanswered question would hold `importing` (folder
    /// chooser, unlink, list watch) with nothing on screen. A question published while the card is away waits for it.
    func setRequestPanelShown(deviceKey: String, _ shown: Bool) {
        if shown { requestPanelShown.insert(deviceKey) } else { requestPanelShown.remove(deviceKey) }
        if !shown, importQuestion[deviceKey] != nil { answerImportQuestion(deviceKey: deviceKey, proceed: false) }
        updatePolling(deviceKey)
    }

    /// `AppActivityMonitor` (AppShell.swift): true when the app is not frontmost or has no visible, unoccluded window.
    func setPaused(_ paused: Bool) {
        guard windowPaused != paused else { return }
        windowPaused = paused
        for key in Set(openRequests.keys).union(requestPanelShown).union(requestTasks.keys) { updatePolling(key) }
        for key in batteryCardShown.union(liveBatteryTasks.keys) { updateLiveBattery(key) }
    }

    /// True while the 10 s poll loop of `deviceKey` exists (tests, `no-unseen-work` check).
    func isPolling(deviceKey: String) -> Bool { requestTasks[deviceKey] != nil }

    /// Decision 7 and 13: the one loop per device. With a request open it polls that request; with none open and no
    /// import running it watches the phone's finished archives. True when the loop may run now.
    private func wantsPolling(_ deviceKey: String) -> Bool {
        let shown = requestPanelShown.contains(deviceKey), isConnected = connected[deviceKey] != nil
        if openRequests[deviceKey] != nil {
            return SysdiagnoseDir.shouldPoll(phase: sysdiagnoseRequest[deviceKey], panelShown: shown,
                                             windowPaused: windowPaused, connected: isConnected)
        }
        return SysdiagnoseDir.shouldWatchList(panelShown: shown, windowPaused: windowPaused, connected: isConnected,
                                              importing: importing[deviceKey] != nil)
    }

    /// Starts the loop when it may run and is not running; cancels it otherwise. This is the only place a poll task is
    /// created or cancelled. A started loop ticks at once (the first request poll after a pause applies the clock
    /// rules to what is on the phone) and then every 10 s.
    private func updatePolling(_ deviceKey: String) {
        let wants = wantsPolling(deviceKey)
        if wants, requestTasks[deviceKey] == nil {
            requestTasks[deviceKey] = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, await self.tick(deviceKey) else { return }
                    try? await Task.sleep(nanoseconds: UInt64(SysdiagnoseDir.pollInterval * 1_000_000_000))
                }
            }
        } else if !wants, let t = requestTasks.removeValue(forKey: deviceKey) {
            t.cancel()
        }
    }

    /// One tick in whichever mode applies. A request that ends here leaves the loop running in list mode when the
    /// list gate holds; otherwise the loop ends and removes itself (a cancelled loop was already removed).
    private func tick(_ deviceKey: String) async -> Bool {
        if openRequests[deviceKey] != nil {
            _ = await pollRequest(deviceKey)
        } else {
            await pollArchiveList(deviceKey)
        }
        guard !Task.isCancelled else { return false }
        if wantsPolling(deviceKey) { return true }
        requestTasks[deviceKey] = nil
        return false
    }

    /// List mode (Decision 13): lists the phone's sysdiagnose folder and compares the finished archives with the ones
    /// shown under «On the iPhone». On a difference the crash-log listing is reloaded once. Does nothing before the
    /// first load, and a failed listing is ignored until the next tick.
    private func pollArchiveList(_ deviceKey: String) async {
        guard let h = connected[deviceKey], let shown = logs[deviceKey], !Task.isCancelled else { return }
        let result: Result<[IPhoneAFCEntry], IPhoneReadError> = await withCheckedContinuation { cont in
            transport.listSysdiagnoseDir(h) { cont.resume(returning: $0) }
        }
        guard case .success(let entries) = result, !Task.isCancelled, connected[deviceKey] == h,
              importing[deviceKey] == nil, openRequests[deviceKey] == nil else { return }
        let current = logs[deviceKey] ?? shown   // loadLogs may have published meanwhile
        let showing = current.map { IPhoneAFCEntry(path: $0.path, isDirectory: false, size: $0.size, modified: $0.modified) }
        if SysdiagnoseDir.finishedArchives(entries) != SysdiagnoseDir.finishedArchives(showing) {
            loadLogs(deviceKey: deviceKey)
        }
    }

    /// One poll; false when polling stops (final phase, cancelled, or no longer allowed).
    private func pollRequest(_ deviceKey: String) async -> Bool {
        guard let r = openRequests[deviceKey], let h = connected[deviceKey], !Task.isCancelled else { return false }
        let result: Result<[IPhoneAFCEntry], IPhoneReadError> = await withCheckedContinuation { cont in
            transport.listSysdiagnoseDir(h) { cont.resume(returning: $0) }
        }
        guard openRequests[deviceKey]?.id == r.id, !Task.isCancelled else { return false }   // stopped during the listing
        guard case .success(let entries) = result else { return true }    // retried at the next tick
        let (next, phase) = SysdiagnoseDir.step(r, listing: entries, now: Date())
        openRequests[deviceKey] = next
        switch phase {
        case .ready(let own):
            claim(own, deviceKey: deviceKey)
            endRequest(deviceKey, phase)
            loadLogs(deviceKey: deviceKey)   // the archive appears under «On the iPhone»
            return false
        case .ambiguous, .expired, .timedOut, .failed:
            endRequest(deviceKey, phase)
            return false
        case .preparing, .waiting, .creating:
            sysdiagnoseRequest[deviceKey] = phase
            return true
        }
    }

    /// Final phase: polling ends, the message stays until closed or an import starts.
    private func endRequest(_ deviceKey: String, _ phase: SysdiagnoseRequestPhase) {
        openRequests[deviceKey] = nil
        sysdiagnoseRequest[deviceKey] = phase
    }

    private func claim(_ own: OwnSysdiagnose, deviceKey: String) {
        guard let i = devices.firstIndex(where: { $0.id == deviceKey }) else { return }
        var list = (devices[i].ownArchives ?? []).filter { $0.name != own.name }
        list.append(own)
        devices[i].ownArchives = Array(list.suffix(SysdiagnoseDir.maxOwnRecords))
        try? store.save(devices)
    }

    private func dropClaim(_ name: String, deviceKey: String) {
        guard let i = devices.firstIndex(where: { $0.id == deviceKey }) else { return }
        devices[i].ownArchives?.removeAll { $0.name == name }
        try? store.save(devices)
    }

    // MARK: Live battery (IPHONE-LIVE-BATTERY)

    /// `IPhoneDeviceView` reports the battery card's mount state: the loop runs only while the device page is on screen.
    func setBatteryCardShown(deviceKey: String, _ shown: Bool) {
        if shown { batteryCardShown.insert(deviceKey) } else { batteryCardShown.remove(deviceKey) }
        updateLiveBattery(deviceKey)
    }

    /// Re-checks the gate after a change the model does not observe itself (Settings, the automatic-read switch).
    func liveBatteryGateChanged(deviceKey: String) { updateLiveBattery(deviceKey) }

    /// The automatic-read switch, for the view's `onChange` (views read settings through the model).
    var autoReadEnabled: Bool { AppSettings.shared.iphoneAutoRead }

    /// True while the live-battery loop of `deviceKey` exists (tests, `no-unseen-work` check).
    func isLiveBatteryRunning(deviceKey: String) -> Bool { liveBatteryTasks[deviceKey] != nil }

    /// The only place a live-battery task is created or cancelled (R2).
    private func updateLiveBattery(_ key: String) {
        let wants = IPhoneLiveBattery.shouldRun(
            pageShown: batteryCardShown.contains(key), windowPaused: windowPaused,
            attached: connected[key].map { attached.contains($0) } ?? false,
            hasSnapshot: lastSnapshot[key] != nil, autoRead: AppSettings.shared.iphoneAutoRead)
        if wants, liveBatteryTasks[key] == nil {
            liveBatteryTasks[key] = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let every = IPhoneLiveBattery.interval(for: self.link(key) ?? .usb)
                    let wait = IPhoneLiveBattery.wait(lastChecked: batteryCheckedAt[key], now: Date(),
                                                      inFlight: liveBatteryInFlight.contains(key), interval: every)
                    if wait > 0 {
                        try? await Task.sleep(for: .seconds(wait))
                    } else if !(await readLiveBattery(key)) {
                        // Nothing was read (state changed under the loop): never spin.
                        try? await Task.sleep(for: .seconds(every))
                    }
                }
            }
        } else if !wants, let t = liveBatteryTasks.removeValue(forKey: key) {
            t.cancel()
        }
    }

    /// One live read; false when none was started. The result is applied even if the loop was cancelled meanwhile
    /// (the values are current; `applyLiveBattery` drops it when the phone left).
    private func readLiveBattery(_ key: String) async -> Bool {
        guard let h = connected[key], attached.contains(h), lastSnapshot[key] != nil,
              !liveBatteryInFlight.contains(key) else { return false }
        liveBatteryInFlight.insert(key)
        let t0 = ContinuousClock.now
        let result: Result<BatteryDetail?, IPhoneReadError> = await withCheckedContinuation { cont in
            transport.readBattery(h) { cont.resume(returning: $0) }
        }
        liveBatteryInFlight.remove(key)
        let outcome = applyLiveBattery(result, deviceKey: key, handle: h)
        // A dropped read (phone left mid-read) does not reset the clock: the next attach's snapshot sets it.
        if outcome != "dropped" { batteryCheckedAt[key] = Date() }
        let d = (ContinuousClock.now - t0).components
        let ms = Int(d.seconds * 1000 + d.attoseconds / 1_000_000_000_000_000)
        IPhoneLiveBattery.log.debug("battery live read \(outcome, privacy: .public) ms=\(ms, privacy: .public)")
        return true
    }

    /// Merges a live reading into the shown snapshot and, only when the day's point changes, into the stored history
    /// (R4-R7). Internal for tests. Returns the outcome word logged by `readLiveBattery`.
    @discardableResult
    func applyLiveBattery(_ result: Result<BatteryDetail?, IPhoneReadError>, deviceKey key: String,
                          handle h: IPhoneHandle) -> String {
        guard attached.contains(h), !ignoredHandles.contains(h), connected[key] == h,
              var snap = lastSnapshot[key] else { return "dropped" }
        guard case .success(let read) = result else { return "failed" }
        guard let detail = read else { return "nodata" }
        var outcome = "unchanged"
        if snap.battery != detail || !snap.batteryRead {
            snap.battery = detail
            snap.batteryRead = true
            lastSnapshot[key] = snap
            outcome = "changed"
        }
        let now = Date()
        if let i = devices.firstIndex(where: { $0.id == key }),
           let history = IPhoneLiveBattery.updatedHistory(devices[i].battery, battery: detail, now: now) {
            var record = devices[i]
            record.battery = history
            record.lastSeen = now
            devices[i] = record
            try? store.save(devices)
            outcome += "+saved"
        }
        return outcome
    }

    // MARK: Find iPhone (Stage 7)

    func searchAgain() {
        restartError = nil
        unlinkNotice = nil
        transport.restartDiscovery()
    }

    /// Restarts `usbmuxd` with admin rights (Touch ID, password dialog as fallback), off the
    /// main actor; a cancelled prompt is silent. Searches again 2 s after a success;
    /// `restartingService` stays true until that search has started.
    @discardableResult
    func restartConnectionService() async -> PrivilegedRunner.Outcome {
        guard !restartingService else { return .cancelled }
        restartingService = true
        defer { restartingService = false }
        restartError = nil
        unlinkNotice = nil
        let outcome = await Task.detached {
            PrivilegedRunner.run(IPhoneData.usbmuxdRestartCommand)
        }.value
        switch outcome {
        case .success:
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            searchAgain()
        case .cancelled:
            break
        case .failed(let msg):
            restartError = L.iphoneRestartFailed(msg)
        case .timedOut:
            restartError = L.iphoneRestartFailed(L.privilegedTimedOut)
        }
        return outcome
    }
}

extension IPhoneModel.UnlinkNotice {
    @MainActor var message: String {
        switch self {
        case .saveFailed(let name): return L.iphoneUnlinkSaveFailed(name)
        case .trashFailed(let n, let folder): return L.iphoneUnlinkTrashFailed(n, folder)
        }
    }
}
