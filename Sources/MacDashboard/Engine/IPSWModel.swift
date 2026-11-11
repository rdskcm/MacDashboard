// Engine/IPSWModel.swift
// IPHONE-IPSW: main-actor state for the firmware card, owned by `IPhoneModel` for the process
// lifetime (one download app-wide, it survives page changes). Two independent lookups, each started only by its own click
// (network-stance): «Check with Apple» never asks ipsw.me and «Ask ipsw.me» never asks
// Apple. Results live in memory for this launch only; nothing is persisted.

import Foundation
import Observation

/// Decision 9: watches one file for delete, rename and revoke (a vnode `DispatchSource`, no polling, no timer).
/// `onGone` runs on the main actor, at most once, never after `cancel()`. The descriptor is closed on cancel.
@MainActor
final class IPSWFileWatch {
    private var source: DispatchSourceFileSystemObject?
    private var cancelled = false

    /// nil when the file cannot be opened (already gone).
    init?(url: URL, onGone: @escaping @MainActor () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.delete, .rename, .revoke],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, !self.cancelled else { return }
                self.cancel()
                onGone()
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func cancel() {
        cancelled = true
        source?.cancel()
        source = nil
    }

    deinit { source?.cancel() }
}

/// Everything the confirm sheet shows before any firmware byte (D5), computed by the model.
struct IPSWConfirm: Equatable {
    var build: IPSWBuild
    var fileName: String
    var host: String
    var size: Int64?
    var available: Int64?
    var total: Int64?
    var checks: Set<VerifiedDigest>
    var blocked: IPSWError?
    var lowSpace: SpaceLevel?
    var lowPercent: Int
    var destination: URL?
}

enum IPSWConfirmState: Equatable {
    case preparing(IPSWBuild)
    case ready(IPSWConfirm)
}

@MainActor @Observable
final class IPSWModel {
    enum Lookup<T: Equatable>: Equatable {
        case idle, loading, loaded(T, fetchedAt: Date), failed(IPSWError)
    }

    /// A repeated click within this window reuses the answer unless forced.
    static let cacheLifetime: TimeInterval = 10 * 60

    /// Keyed by productType («Check with Apple»). A nil productType fails under the key "".
    var apple: [String: Lookup<IPSWAppleTarget?>] = [:]
    /// Keyed by productType («Ask ipsw.me»).
    var ipswMe: [String: Lookup<IPSWThirdParty>] = [:]
    /// The one download (finished or failed ones stay until the next start).
    var download: (build: IPSWBuild, phase: IPSWDownloadPhase)? {
        didSet { watchFinishedFile() }
    }
    /// Decision 9: the finished download's file that was deleted, moved or renamed while the panel was shown.
    var goneFile: URL?
    /// The confirm step of the row's «Download» click (nil = no sheet).
    var confirm: IPSWConfirmState?
    /// When the shown paused download stopped (restored from the record, or the time its `.paused` phase arrived).
    var stoppedAt: Date?

    @ObservationIgnored private let sources: IPSWSources
    @ObservationIgnored private let downloader: any IPSWDownloading
    @ObservationIgnored private let downloadsDir: () -> URL?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let lowSpacePercent: @MainActor () -> Int
    @ObservationIgnored private let volumeInfo: @Sendable (URL) -> (available: Int64?, total: Int64?)
    /// false = the visual fixture: every click that would send a request ends in `.failed(.offline)` (D15).
    @ObservationIgnored let networkAllowed: Bool
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var fileWatch: IPSWFileWatch?
    @ObservationIgnored private var watchedFile: URL?
    /// Identifies the latest confirm request; a stale HEAD/volume task is dropped (like `downloadRun`).
    @ObservationIgnored private var confirmRun = UUID()
    /// Phases from an older run are ignored once a newer one started.
    @ObservationIgnored private var downloadRun = UUID()

    init(sources: IPSWSources = .live, downloader: any IPSWDownloading = IPSWDownloader(),
         downloadsDir: @escaping () -> URL? = { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first },
         now: @escaping () -> Date = { Date() },
         lowSpacePercent: @escaping @MainActor () -> Int = { AppSettings.shared.lowSpacePercent },
         volumeInfo: @escaping @Sendable (URL) -> (available: Int64?, total: Int64?) = IPSWDownloader.volumeInfo,
         networkAllowed: Bool = true) {
        self.sources = sources
        self.downloader = downloader
        self.downloadsDir = downloadsDir
        self.now = now
        self.lowSpacePercent = lowSpacePercent
        self.volumeInfo = volumeInfo
        self.networkAllowed = networkAllowed
    }

    // MARK: lookups

    /// «Check with Apple». Returns the request's task (nil when nothing was started) so tests can await it.
    @discardableResult
    func checkApple(productType: String?, force: Bool = false) -> Task<Void, Never>? {
        guard let pt = productType, !pt.isEmpty else {
            apple[""] = .failed(.noIdentifier)
            return nil
        }
        guard networkAllowed else {
            apple[pt] = .failed(.offline)
            return nil
        }
        guard shouldFetch(apple[pt], force: force) else { return nil }
        apple[pt] = .loading
        let sources = self.sources
        return Task { [weak self] in
            let result = await sources.appleTarget(identifier: pt)
            guard let self else { return }
            switch result {
            case .success(let target): self.apple[pt] = .loaded(target, fetchedAt: self.now())
            case .failure(let e): self.apple[pt] = .failed(e)
            }
        }
    }

    /// «Ask ipsw.me — sends the model identifier». Returns the request's task like `checkApple`.
    @discardableResult
    func askIPSWMe(productType: String?, force: Bool = false) -> Task<Void, Never>? {
        guard let pt = productType, !pt.isEmpty else {
            ipswMe[""] = .failed(.noIdentifier)
            return nil
        }
        guard networkAllowed else {
            ipswMe[pt] = .failed(.offline)
            return nil
        }
        guard shouldFetch(ipswMe[pt], force: force) else { return nil }
        ipswMe[pt] = .loading
        let sources = self.sources
        return Task { [weak self] in
            let result = await sources.ipswMe(identifier: pt)
            guard let self else { return }
            switch result {
            case .success(let list): self.ipswMe[pt] = .loaded(list, fetchedAt: self.now())
            case .failure(let e): self.ipswMe[pt] = .failed(e)
            }
        }
    }

    private func shouldFetch<T: Equatable>(_ state: Lookup<T>?, force: Bool) -> Bool {
        switch state {
        case .loading?: return false
        case .loaded(_, fetchedAt: let at)?: return force || now().timeIntervalSince(at) >= Self.cacheLifetime
        default: return true
        }
    }

    /// The merge of whatever was fetched for this model (either source, both, or neither).
    func builds(productType: String?) -> [IPSWBuild] {
        guard let pt = productType else { return [] }
        var target: IPSWAppleTarget?
        var list: IPSWThirdParty?
        if case .loaded(let t, fetchedAt: _)? = apple[pt] { target = t }
        if case .loaded(let l, fetchedAt: _)? = ipswMe[pt] { list = l }
        return IPSWData.merge(apple: target, ipswMe: list)
    }

    /// The installed build's status; nil until at least one source answered for this model.
    /// Installed build: `IPhoneModel.lastSnapshot[key]?.build` (connected) / `IPhoneDeviceRecord.osVersion`.
    func installedSigning(productType: String?, build: String?, version: String?) -> InstalledSigning? {
        let all = builds(productType: productType)
        guard !all.isEmpty else { return nil }
        return IPSWData.installedSigning(all, build: build, version: version)
    }

    /// The rows the card lists: Apple's target, every build ipsw.me marks signed and the installed build, in merge
    /// order. `hiddenUnsigned` counts the rest (older builds ipsw.me lists as not signed, D12).
    func visibleBuilds(productType: String?, installedBuild: String?, installedVersion: String?)
        -> (rows: [IPSWBuild], hiddenUnsigned: Int) {
        let all = builds(productType: productType)
        let rows = all.filter {
            $0.isAppleTarget || $0.signed == true || $0.buildID == installedBuild
                || (installedBuild == nil && $0.version == installedVersion)
        }
        return (rows, all.count - rows.count)
    }

    // MARK: download

    /// A download exists and has not finished or failed (the «Download» buttons are disabled meanwhile).
    var blocksStart: Bool {
        if let d = download, !d.phase.isTerminal { return true }
        return false
    }

    /// The download's phase when it belongs to this model (D2), else nil.
    func downloadPhase(for productType: String?) -> IPSWDownloadPhase? {
        guard let pt = productType, let d = download, d.build.apple?.identifier == pt else { return nil }
        return d.phase
    }

    /// The row's «Download» click: builds the confirm step, sends nothing unless the size is unknown (one HEAD).
    /// Returns the preparing task (nil when nothing was started) so tests can await it.
    @discardableResult
    func requestDownload(_ b: IPSWBuild, replacingConfirm: Bool = false) -> Task<Void, Never>? {
        guard replacingConfirm || confirm == nil, !blocksStart else { return nil }
        let run = UUID()
        confirmRun = run
        var base = IPSWConfirm(build: b, fileName: IPSWData.fileName(for: b),
                               host: b.apple?.url.host(percentEncoded: false) ?? "",
                               size: b.ipswMe?.fileSize.flatMap { $0 > 0 ? $0 : nil },
                               available: nil, total: nil, checks: [], blocked: nil, lowSpace: nil,
                               lowPercent: lowSpacePercent(), destination: downloadsDir())
        guard networkAllowed else {
            base.blocked = .offline
            confirm = .ready(base)
            return nil
        }
        guard case .available(let url) = IPSWData.availability(b) else {
            base.blocked = .notDownloadable(base.host)
            confirm = .ready(base)
            return nil
        }
        switch IPSWData.expectedDigests(b) {
        case .failure(let e):
            base.blocked = e
            confirm = .ready(base)
            return nil
        case .success(let digests):
            base.checks = IPSWData.plannedDigests(digests)
        }
        confirm = .preparing(b)
        let sources = self.sources
        let volumeInfo = self.volumeInfo
        let needsHead = (b.ipswMe?.fileSize ?? 0) <= 0
        return Task { [weak self] in
            var c = base
            var headLength: Int64?
            if needsHead {
                switch await sources.head(url) {
                case .success(let length): headLength = length
                case .failure(let e):
                    self?.finishConfirm(run, b, c, blocked: e)
                    return
                }
            }
            switch IPSWData.expectedSize(b, headLength: headLength) {
            case .failure(let e):
                self?.finishConfirm(run, b, c, blocked: e)
                return
            case .success(let size): c.size = size
            }
            guard let dir = self?.downloadsDir() else {
                self?.finishConfirm(run, b, c, blocked: .fileSystem("Downloads"))
                return
            }
            let info = await Task.detached { volumeInfo(dir) }.value
            guard let self, let size = c.size else { return }
            c.available = info.available
            c.total = info.total
            c.destination = dir
            c.lowPercent = self.lowSpacePercent()
            c.lowSpace = IPSWData.lowSpaceAfter(size: size, available: info.available, total: info.total,
                                                lowPercent: c.lowPercent)
            self.finishConfirm(run, b, c, blocked: IPSWData.spaceCheck(needed: size, available: info.available))
        }
    }

    /// Publishes the confirm facts unless the step was cancelled or replaced meanwhile.
    private func finishConfirm(_ run: UUID, _ b: IPSWBuild, _ facts: IPSWConfirm, blocked: IPSWError?) {
        guard confirmRun == run, confirm == .preparing(b) else { return }
        var c = facts
        c.blocked = blocked
        confirm = .ready(c)
    }

    /// The sheet's «Download» / «Download anyway».
    func confirmDownload() {
        guard case .ready(let c)? = confirm, c.blocked == nil else { return }
        confirm = nil
        startDownload(c.build)
    }

    func cancelConfirm() {
        confirmRun = UUID()
        confirm = nil
    }

    func startDownload(_ b: IPSWBuild) {
        if blocksStart { return }   // one at a time; the UI disables the button
        guard networkAllowed else {
            download = (b, .failed(.offline))
            stoppedAt = nil
            return
        }
        let run = UUID()
        downloadRun = run
        guard let dir = downloadsDir() else {
            download = (b, .failed(.fileSystem("Downloads")))
            stoppedAt = nil
            return
        }
        download = (b, .preparing)
        stoppedAt = nil
        downloader.start(b, downloadsDir: dir, sources: sources, onPhase: phaseHandler(build: b, run: run))
    }

    /// Phases from an older run are ignored once a newer one started. A parked download keeps its handler,
    /// so a resume passes the same `run` check.
    private func phaseHandler(build b: IPSWBuild, run: UUID) -> IPSWDownloader.PhaseHandler {
        { [weak self] phase in
            guard let self, self.downloadRun == run else { return }
            self.download = (b, phase)
            if case .paused = phase { self.stoppedAt = self.now() } else { self.stoppedAt = nil }
        }
    }

    /// «Stop». The downloader decides: preparing cancels, a transfer or verification parks as `.paused`.
    func cancelDownload() {
        downloader.cancel()
    }

    /// «Resume» (click only).
    func resumeDownload() {
        guard let d = download, case .paused = d.phase else { return }
        guard networkAllowed else {
            download = (d.build, .failed(.offline))
            stoppedAt = nil
            return
        }
        guard let dir = downloadsDir() else {
            download = (d.build, .failed(.fileSystem("Downloads")))
            stoppedAt = nil
            return
        }
        download = (d.build, .preparing)
        stoppedAt = nil
        downloader.resume(downloadsDir: dir)
    }

    /// «Discard» a paused download: deletes the partial and its record.
    func discardDownload() {
        guard let d = download, case .paused = d.phase else { return }
        downloader.discard()
    }

    /// «Close» on a finished or failed panel.
    func dismissDownload() {
        guard let d = download, d.phase.isTerminal else { return }
        download = nil
        stoppedAt = nil
    }

    /// True when the finished file `url` was seen gone (Decision 9).
    func fileIsGone(_ url: URL) -> Bool { goneFile == url }

    /// Decision 9: while a finished download is shown, one vnode watch on its file. A missing file at that moment
    /// counts as gone. Stops when the panel closes, another download starts or the model forgets it.
    /// Off in the visual fixture (`networkAllowed == false`): its file path does not exist.
    private func watchFinishedFile() {
        guard networkAllowed, case .finished(let url, _)? = download?.phase else {
            stopWatch()
            return
        }
        if watchedFile == url { return }
        stopWatch()
        watchedFile = url
        goneFile = nil
        fileWatch = IPSWFileWatch(url: url) { [weak self] in
            guard let self, self.watchedFile == url else { return }
            self.goneFile = url
        }
        if fileWatch == nil { goneFile = url }
    }

    private func stopWatch() {
        fileWatch?.cancel()
        fileWatch = nil
        watchedFile = nil
    }

    /// Quit hook (D11): saves a running download as stopped. No state change here.
    func stopForQuit() {
        stopWatch()
        downloader.suspendForQuit()
    }

    /// Launch (R14, R18): shows a download stopped in an earlier run. Disk only, never the network; once per process.
    func restoreParked(knownIdentifiers: Set<String>) {
        guard networkAllowed, !restored else { return }
        restored = true
        let run = UUID()
        downloadRun = run
        // The build is only known once the record is read, so the handler reads it from `download`.
        let handler: IPSWDownloader.PhaseHandler = { [weak self] phase in
            guard let self, self.downloadRun == run, let b = self.download?.build else { return }
            self.download = (b, phase)
            if case .paused = phase { self.stoppedAt = self.now() } else { self.stoppedAt = nil }
        }
        guard let record = downloader.restore(knownIdentifiers: knownIdentifiers, onPhase: handler) else { return }
        download = (record.build, .paused(written: record.checkpoint, total: record.size,
                                          interruption: record.reason?.error))
        stoppedAt = record.stoppedAt
    }

    /// D23: Apple's build when a lookup this launch names another build than the paused one.
    func outdatedNote(productType: String?) -> IPSWBuild? {
        guard let pt = productType, let d = download, case .paused = d.phase,
              d.build.apple?.identifier == pt,
              case .loaded(let target?, fetchedAt: _)? = apple[pt],
              target.firmware.buildID != d.build.buildID else { return nil }
        return builds(productType: pt).first { $0.isAppleTarget }
    }

    /// «Start over» after a rejected resume: the confirm step for the same build.
    func startOver() {
        guard let d = download, case .failed(.resumeRejected) = d.phase else { return }
        download = nil
        stoppedAt = nil
        requestDownload(d.build, replacingConfirm: true)   // an open confirm for another row is replaced, never left hiding the result
    }

    /// Unlinking the last phone of a model (D26): deletes that model's stopped or running download.
    func forgetModel(identifier: String) {
        downloader.forget(identifier: identifier)
        if download?.build.apple?.identifier == identifier {
            downloadRun = UUID()   // drops the cancel phase the downloader still delivers
            download = nil
            stoppedAt = nil
        }
    }
}
