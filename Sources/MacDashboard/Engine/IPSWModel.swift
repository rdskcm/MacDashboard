// Engine/IPSWModel.swift
// IPHONE-IPSW: main-actor state for the firmware card (the UI step adds the call sites;
// this block adds none). Two independent lookups, each started only by its own click
// (network-stance): «Check with Apple» never asks ipsw.me and «Ask ipsw.me» never asks
// Apple. Results live in memory for this launch only; nothing is persisted.

import Foundation
import Observation

@MainActor @Observable
final class IPSWModel {
    static let shared = IPSWModel()

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
    var download: (build: IPSWBuild, phase: IPSWDownloadPhase)?

    @ObservationIgnored private let sources: IPSWSources
    @ObservationIgnored private let downloader: IPSWDownloader
    @ObservationIgnored private let downloadsDir: () -> URL?
    @ObservationIgnored private let now: () -> Date
    /// Phases from an older run are ignored once a newer one started.
    @ObservationIgnored private var downloadRun = UUID()

    init(sources: IPSWSources = .live, downloader: IPSWDownloader = IPSWDownloader(),
         downloadsDir: @escaping () -> URL? = { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first },
         now: @escaping () -> Date = { Date() }) {
        self.sources = sources
        self.downloader = downloader
        self.downloadsDir = downloadsDir
        self.now = now
    }

    // MARK: lookups

    /// «Check with Apple». Returns the request's task (nil when nothing was started) so tests can await it.
    @discardableResult
    func checkApple(productType: String?, force: Bool = false) -> Task<Void, Never>? {
        guard let pt = productType, !pt.isEmpty else {
            apple[""] = .failed(.noIdentifier)
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

    // MARK: download

    func startDownload(_ b: IPSWBuild) {
        if let d = download, !d.phase.isTerminal { return }   // one at a time; the UI disables the button
        let run = UUID()
        downloadRun = run
        guard let dir = downloadsDir() else {
            download = (b, .failed(.fileSystem("Downloads")))
            return
        }
        download = (b, .preparing)
        downloader.start(b, downloadsDir: dir, sources: sources) { [weak self] phase in
            guard let self, self.downloadRun == run else { return }
            self.download = (b, phase)
        }
    }

    func cancelDownload() {
        downloader.cancel()
    }
}
