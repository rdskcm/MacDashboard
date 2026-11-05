// Engine/IPhoneModel.swift
// App-only (talks to MobileDeviceTransport, which is app-only). Owns the iPhone
// mode state: remembered devices (persisted via IPhoneStore, R13), live connections and
// per-device status. Everything here runs on the main actor; the transport completes
// its callbacks on main.

import Foundation
import Observation

@MainActor @Observable
final class IPhoneModel {
    static let shared = IPhoneModel()

    enum DeviceStatus: Equatable {
        case connected
        case reading
        case needsTrust
        case readFailed(String)
        case remembered
    }

    var devices: [IPhoneDeviceRecord] = []
    /// deviceKey → handle of the phone currently attached over USB.
    var connected: [String: IPhoneHandle] = [:]
    var status: [String: DeviceStatus] = [:]
    /// Attached handles not yet identified (waiting for trust, or the read failed).
    var pendingHandles: Set<IPhoneHandle> = []
    /// Status of each pending handle (`.needsTrust` or `.readFailed`).
    var pendingStatus: [IPhoneHandle: DeviceStatus] = [:]
    var lastSnapshot: [String: IPhoneSnapshot] = [:]
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
    /// Last import result per device: the archive name with its summary, or the error.
    var importResult: [String: Result<(name: String, summary: ImportSummary), ImportError>] = [:]
    /// IPHONE-HISTORY-MIXUP: an import paused on an archive that looks like another phone's;
    /// the device's import card shows it as a dialog. Memory only.
    var importQuestion: [String: ImportIdentityQuestion] = [:]
    /// The paused import's continuation per device, resumed by `answerImportQuestion`.
    @ObservationIgnored private var importAnswer: [String: CheckedContinuation<Bool, Never>] = [:]

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

    /// «Найти iPhone» → restart of the connection service (Stage 7).
    var restartingService = false
    var restartError: String?
    /// The open device page (nil = tiles). Memory only; survives a Mac↔iPhone switch.
    var selectedDeviceKey: String?
    /// REDESIGN-IPHONE: where kept archives live (`<archiveRoot>/<deviceKey>/<name>`); resolved from
    /// `AppSettings.iphoneArchiveFolder`, changed only through `setArchiveFolder`.
    private(set) var archiveRoot: URL
    enum ArchiveFolderError: Equatable { case couldNotMove(Int) }
    /// Why the last «Choose…» left the folder unchanged; cleared by the next successful change.
    var archiveFolderError: ArchiveFolderError?
    var archiveFolderBusy = false
    enum ReadTrigger: Equatable { case attach, user }
    /// Per device: when the last automatic crash-log listing started (memory only).
    @ObservationIgnored private var autoReadAt: [String: Date] = [:]

    private let store: IPhoneStore
    private let logTypeStore: IPhoneLogTypeStore
    private let transport: MobileDeviceTransport
    private var started = false
    /// Every handle the transport reported attached and has not detached yet. A read that
    /// lands after its handle detached is dropped (the detach wins).
    private var attached: Set<IPhoneHandle> = []

    init(store: IPhoneStore = IPhoneStore(url: IPhoneStore.defaultURL()),
         transport: MobileDeviceTransport = .shared,
         archiveRoot: URL? = nil,
         logTypeStore: IPhoneLogTypeStore = IPhoneLogTypeStore(
            url: AppInfo.supportFolderURL.appendingPathComponent(IPhoneLogTypeStore.fileName))) {
        self.store = store
        self.logTypeStore = logTypeStore
        self.transport = transport
        self.archiveRoot = archiveRoot ?? AppSettings.resolveArchiveFolder(
            raw: AppSettings.shared.iphoneArchiveFolder, defaultRoot: IPhoneStore.defaultArchiveRoot())
    }

    func start() {
        guard !started else { return }
        started = true
        // Before any import can start (D7).
        IPhoneData.removeStaleImportRoots(in: FileManager.default.temporaryDirectory)
        // IPHONE-CRASHLOG-ACTIONS (Decision 3): crash-log copies of the previous run.
        IPhoneData.removeStaleImportRoots(in: FileManager.default.temporaryDirectory, prefix: IPhoneCrashLog.tempPrefix)
        devices = store.load()
        headerCache = logTypeStore.load(keeping: Set(devices.map(\.id)))
        for d in devices { status[d.id] = .remembered }
        migrateLegacyArchivesIfNeeded()
        transportAvailable = transport.isAvailable
        guard transportAvailable else { return }
        transport.start { [weak self] event in self?.handle(event) }
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

    /// The kept file, wherever it is: the archive folder first, then the legacy App Support place; nil when gone.
    func keptArchiveURL(deviceKey: String, name: String) -> URL? {
        let fm = FileManager.default
        let current = archiveRoot.appendingPathComponent(deviceKey, isDirectory: true).appendingPathComponent(name)
        if fm.fileExists(atPath: current.path) { return current }
        let legacy = IPhoneStore.legacyArchiveRoot().appendingPathComponent(deviceKey, isDirectory: true)
            .appendingPathComponent("sysdiagnose", isDirectory: true).appendingPathComponent(name)
        return fm.fileExists(atPath: legacy.path) ? legacy : nil
    }

    /// Settings › iPhone › Choose…: moves every kept archive to `url`, then stores the setting. All or nothing:
    /// a skipped or failed file moves the moved ones back and reports the count.
    func setArchiveFolder(_ url: URL) async {
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

    func handle(_ event: IPhoneTransportEvent) {
        switch event {
        case .attached(let h):
            attached.insert(h)
            restartError = nil
            refresh(handle: h, trigger: .attach)
        case .detached(let h):
            attached.remove(h)
            logsLoading.detach(h)
            identityLoading.detach(h)
            storageLoading.detach(h)
            pendingHandles.remove(h)
            pendingStatus[h] = nil
            for (key, handle) in connected where handle == h {
                connected[key] = nil
                status[key] = .remembered
                identity[key] = nil
                storage[key] = nil
                identityFailed.remove(key)
                lastSnapshot[key] = nil
                logs[key] = nil
                logsFailed.remove(key)
                for k in logAction.keys where k.hasPrefix(key + "|live|") { logAction[k] = nil }
            }
        }
    }

    func refresh(handle h: IPhoneHandle, trigger: ReadTrigger = .user) {
        if let key = connected.first(where: { $0.value == h })?.key {
            status[key] = .reading
        }
        let battery = trigger == .user || AppSettings.shared.iphoneAutoRead
        transport.readSnapshot(h, includeBattery: battery) { [weak self] result in
            self?.apply(result, for: h, trigger: trigger)
        }
    }

    /// The page's «Обновить».
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
        transport.readIdentity(h) { [weak self] result in
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
    /// 2 s after the read started on the transport thread.
    private func loadStorage(deviceKey: String, handle h: IPhoneHandle) {
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

    /// Runs one import. `keep` = «Разобрать и сохранить». Merges the derived battery points
    /// into the stored history and fills `archiveLogs` only on success. One import per
    /// device at a time.
    func importArchive(deviceKey: String, source: SysdiagnoseImporter.Source, keep: Bool) {
        guard importing[deviceKey] == nil, devices.contains(where: { $0.id == deviceKey }) else { return }
        if case .phone(_, _, let size) = source {
            importing[deviceKey] = .copying(done: 0, total: size)
        } else {
            importing[deviceKey] = .extracting
        }
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
            self?.finishImport(deviceKey: deviceKey, keep: keep, result: result)
        }
    }

    private func finishImport(deviceKey: String, keep: Bool, result: Result<ImportOutput, ImportError>) {
        importing[deviceKey] = nil
        switch result {
        case .failure(let e):
            importResult[deviceKey] = .failure(e)
        case .success(let out):
            if let i = devices.firstIndex(where: { $0.id == deviceKey }) {
                devices[i].battery = IPhoneData.mergeImported(devices[i].battery, out.points)
                if let kept = out.summary.keptPath { devices[i].keptArchives.append(kept.lastPathComponent) }
                try? store.save(devices)
            }
            archiveLogs[deviceKey] = out.logs
            importResult[deviceKey] = .success((out.archiveName, out.summary))
        }
    }

    /// Called by the importer after parsing, before keeping or merging. Answers at once on a
    /// match or an unknown identity; on a mismatch publishes `importQuestion` and waits.
    private func confirmIdentity(deviceKey: String, archiveName: String, archiveMAh: Set<Int>) async -> Bool {
        guard case .mismatch(let q) = IPhoneData.archiveIdentity(archiveName: archiveName, archiveMAh: archiveMAh,
                                                                 deviceKey: deviceKey, devices: devices) else { return true }
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

    private func apply(_ result: Result<IPhoneSnapshot, IPhoneReadError>, for h: IPhoneHandle, trigger: ReadTrigger) {
        guard attached.contains(h) else { return }
        switch result {
        case .success(let snap):
            let key = IPhoneData.deviceKey(udid: snap.udid)
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
            if let b = snap.battery, b.healthPercent != nil || b.cycleCount != nil {
                let point = BatteryPoint(day: IPhoneData.historyDay(now),
                                         cycles: b.cycleCount,
                                         healthPercent: b.healthPercent,
                                         maxCapacityMAh: b.maxCapacityMAh,
                                         designCapacityMAh: b.designCapacityMAh,
                                         source: "live")
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
            status[key] = .connected
            lastSnapshot[key] = snap
            if trigger == .attach, AppSettings.shared.iphoneAutoRead,
               IPhoneData.autoReadDue(last: autoReadAt[key], now: now) {
                autoReadAt[key] = now
                loadLogs(deviceKey: key)
            }
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

    // MARK: Find iPhone (Stage 7)

    func searchAgain() {
        restartError = nil
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
