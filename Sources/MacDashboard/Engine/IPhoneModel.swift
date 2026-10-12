// Engine/IPhoneModel.swift
// App-only (talks to MobileDeviceTransport, which is not in Checks). Owns the iPhone
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
    /// Per device: "<path>|<size>|<mtime>" → bug_type ("" = none), replaced by each successful
    /// listing (files gone from the phone drop out). Memory only; never written to disk.
    var headerCache: [String: [String: String]] = [:]
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

    /// Identity and parts per connected device. Memory only (R13, D10); cleared on detach.
    var identity: [String: [IPhoneIdentityField]] = [:]
    var identityLoading = InFlightReads<IPhoneHandle>()
    /// Devices whose last identity read failed; cleared by a successful read or detach.
    var identityFailed: Set<String> = []

    /// «Найти iPhone» → restart of the connection service (Stage 7).
    var restartingService = false
    var restartError: String?
    /// The open device page (nil = tiles). Memory only; survives a Mac↔iPhone switch.
    var selectedDeviceKey: String?

    private let store: IPhoneStore
    private let transport: MobileDeviceTransport
    private var started = false
    /// Every handle the transport reported attached and has not detached yet. A read that
    /// lands after its handle detached is dropped (the detach wins).
    private var attached: Set<IPhoneHandle> = []

    init(store: IPhoneStore = IPhoneStore(url: IPhoneStore.defaultURL()),
         transport: MobileDeviceTransport = .shared) {
        self.store = store
        self.transport = transport
    }

    func start() {
        guard !started else { return }
        started = true
        // Before any import can start (D7).
        IPhoneData.removeStaleImportRoots(in: FileManager.default.temporaryDirectory)
        devices = store.load()
        for d in devices { status[d.id] = .remembered }
        transportAvailable = transport.isAvailable
        guard transportAvailable else { return }
        transport.start { [weak self] event in self?.handle(event) }
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
            refresh(handle: h)
        case .detached(let h):
            attached.remove(h)
            logsLoading.detach(h)
            identityLoading.detach(h)
            pendingHandles.remove(h)
            pendingStatus[h] = nil
            for (key, handle) in connected where handle == h {
                connected[key] = nil
                status[key] = .remembered
                identity[key] = nil
                identityFailed.remove(key)
                lastSnapshot[key] = nil
                logs[key] = nil
                logsFailed.remove(key)
            }
        }
    }

    func refresh(handle h: IPhoneHandle) {
        if let key = connected.first(where: { $0.value == h })?.key {
            status[key] = .reading
        }
        transport.readSnapshot(h) { [weak self] result in
            self?.apply(result, for: h)
        }
    }

    /// The page's «Обновить».
    func refresh(deviceKey: String) {
        guard let h = connected[deviceKey] else { return }
        refresh(handle: h)
    }

    /// Lists the phone's crash logs (headers already in `headerCache` are not re-read).
    /// No-op when the phone is not connected or a listing over the current connection is already running.
    func loadLogs(deviceKey: String) {
        guard let h = connected[deviceKey], let id = logsLoading.begin(deviceKey, handle: h) else { return }
        transport.listLogs(h, knownHeaders: headerCache[deviceKey] ?? [:]) { [weak self] result in
            guard let self else { return }
            // A listing superseded by a newer one, or whose phone detached, is dropped.
            guard logsLoading.finish(deviceKey, id: id), attached.contains(h) else { return }
            switch result {
            case .success(let (entries, cache)):
                logs[deviceKey] = entries
                headerCache[deviceKey] = cache
                logsFailed.remove(deviceKey)
            case .failure:
                logsFailed.insert(deviceKey)
            }
        }
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
        Task { [weak self] in
            let importer = SysdiagnoseImporter()
            let result = await importer.run(source: source, deviceKey: deviceKey, keep: keep,
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

    private func apply(_ result: Result<IPhoneSnapshot, IPhoneReadError>, for h: IPhoneHandle) {
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
        }
        return outcome
    }
}
