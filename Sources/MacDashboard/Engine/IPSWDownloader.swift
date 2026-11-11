// Engine/IPSWDownloader.swift
// IPHONE-IPSW: downloads ONE verified .ipsw into ~/Downloads, only on the user's click.
// Every rule of specs/IPHONE-IPSW.md § Download security is enforced here or in the pure
// helpers it calls (IPSWData): Apple's URL only (decision 5), https + exact host allowlist
// on the URL and on every redirect hop (network-stance), checksums cross-checked before a
// byte is fetched, size + free space + Downloads access before starting, staging on the
// Downloads volume, every digest verified after, an atomic no-overwrite move, cleanup on
// any failure, one download at a time, cancel in every phase.
// Rules 8 and 10 name the caches root (~/Library/Caches/<bundle id>/ipsw/, `IPSWPartialStore`),
// not $TMPDIR: the partial file and its record survive quit, crash and force-quit.
// Rule 12 (Decision 8): the transfer is a ranged data task appending to the app's own `.part`
// file. A resume sends `Range: bytes=<n>-` and `If-Range: <validator>` and accepts only a 206
// whose `Content-Range` is exactly `bytes <n>-<size-1>/<size>`; any other answer deletes the
// partial (`.resumeRejected`). The partial is flushed and its record rewritten every
// `checkpointBytes`, and a resume truncates the partial back to the last checkpoint.

import Foundation
import Darwin

enum IPSWDownloadPhase: Equatable {
    case preparing                                      // HEAD, probes
    case downloading(written: Int64, total: Int64)
    case verifying(hashed: Int64, total: Int64)
    /// Stopped by the user or interrupted: the partial file is kept on disk. `interruption` is nil for a user stop.
    case paused(written: Int64, total: Int64, interruption: IPSWError?)
    case finished(URL, verified: Set<VerifiedDigest>)   // decision 3: the UI prints exactly this set
    case failed(IPSWError)

    var isTerminal: Bool {
        switch self {
        case .finished, .failed: return true
        default: return false
        }
    }
}

/// What `IPSWModel` needs from the downloader (D16). Two conformers: `IPSWDownloader` and a test stub.
protocol IPSWDownloading: AnyObject {
    func start(_ b: IPSWBuild, downloadsDir: URL, sources: IPSWSources, onPhase: @escaping IPSWDownloader.PhaseHandler)
    func cancel()
    func resume(downloadsDir: URL)
    func discard()
    func restore(knownIdentifiers: Set<String>, onPhase: @escaping IPSWDownloader.PhaseHandler) -> IPSWPartialRecord?
    func suspendForQuit()
    func forget(identifier: String)
}

/// Own ephemeral session with a serial delegate queue. State lives behind `lock`; phases are
/// delivered on the main queue in the order they were produced. Every file operation on a
/// running transfer (write, flush, close) happens on the delegate queue, so they never race.
final class IPSWDownloader: NSObject, URLSessionDataDelegate, IPSWDownloading, @unchecked Sendable {
    typealias PhaseHandler = @MainActor (IPSWDownloadPhase) -> Void

    static let progressInterval: TimeInterval = 0.25
    static let transferTimeout: TimeInterval = 60       // idle timeout per request

    private struct Run {
        let id: UUID
        let onPhase: PhaseHandler
        let downloadsDir: URL
        var identifier = ""
        var digests = ExpectedDigests(sha256: nil, sha1: nil, sha1Sources: [])
        var fileName = ""
        var size: Int64 = 0
        var staging: URL?
        var record: IPSWPartialRecord?
        var partURL: URL?
        var handle: FileHandle?
        var written: Int64 = 0
        var task: URLSessionDataTask?
        var transferring = false
        var verifying = false
        var pausing = false
        var resumed = false
        var pendingError: IPSWError?
        var cancelled = false
        var lastProgress = Date.distantPast
    }

    private struct Parked {
        var record: IPSWPartialRecord
        var partURL: URL
        let onPhase: PhaseHandler
    }

    private let lock = NSLock()
    private var run: Run?
    private var parked: Parked?
    private var session: URLSession!
    private let queue: OperationQueue
    private let stagingRoot: URL
    private let checkpointBytes: Int64
    private let capacity: @Sendable (URL) -> Int64?
    private let now: @Sendable () -> Date
    private let tempDirectory: URL

    init(stagingRoot: URL = IPSWPartialStore.defaultRoot(), protocolClasses: [AnyClass] = [],
         checkpointBytes: Int64 = IPSWPartialStore.checkpointBytes,
         capacity: @escaping @Sendable (URL) -> Int64? = IPSWDownloader.availableCapacity,
         now: @escaping @Sendable () -> Date = { Date() },
         tempDirectory: URL = FileManager.default.temporaryDirectory) {
        self.tempDirectory = tempDirectory
        self.stagingRoot = stagingRoot
        self.checkpointBytes = checkpointBytes
        self.capacity = capacity
        self.now = now
        queue = OperationQueue()
        super.init()
        queue.maxConcurrentOperationCount = 1
        queue.name = "MacDashboard.IPSWDownloader"
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        if !protocolClasses.isEmpty { config.protocolClasses = protocolClasses + (config.protocolClasses ?? []) }
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }

    /// A running or a stopped (parked) download: no other one may start (rule 11, D9).
    var isBusy: Bool { locked { run != nil || parked != nil } }

    // MARK: control

    /// Order: busy → availability (Apple's URL only) → downloadPolicy → digests cross-check →
    /// HEAD if ipsw.me gave no size → size → Downloads access → free space → transfer →
    /// staging → finalize. Every refusal before the transfer happens before any firmware byte.
    func start(_ b: IPSWBuild, downloadsDir: URL, sources: IPSWSources, onPhase: @escaping PhaseHandler) {
        let id = UUID()
        let claimed: Bool = locked {
            guard run == nil, parked == nil else { return false }
            run = Run(id: id, onPhase: onPhase, downloadsDir: downloadsDir)
            return true
        }
        guard claimed else { return Self.deliver(.failed(.busy), to: onPhase) }

        guard case .available(let url) = IPSWData.availability(b) else {
            let e = b.apple.flatMap { IPSWData.downloadPolicy($0.url) } ?? .notDownloadable(IPSWSources.ipswMeHost)
            return finish(id, .failed(e))
        }
        if let e = IPSWData.downloadPolicy(url) { return finish(id, .failed(e)) }
        let digests: ExpectedDigests
        switch IPSWData.expectedDigests(b) {
        case .success(let d): digests = d
        case .failure(let e): return finish(id, .failed(e))
        }
        let name = IPSWData.fileName(for: b)
        locked {
            run?.digests = digests
            run?.fileName = name
            run?.identifier = b.apple?.identifier ?? ""
        }
        emit(id, .preparing)
        Task.detached(priority: .userInitiated) { [self] in
            await self.prepare(id: id, build: b, url: url, downloadsDir: downloadsDir, sources: sources)
        }
    }

    /// «Stop». Works in every phase. Before the transfer a fresh run ends at once; during the
    /// transfer the task is cancelled and the completion parks the partial; while hashing
    /// `finalize` sees the flag and the completion parks the complete partial. A resume that has
    /// not started its transfer yet returns to the parked state at its next step.
    func cancel() {
        var endNow: UUID?
        let task: URLSessionDataTask? = locked {
            guard var r = run else { return nil }
            defer { run = r }
            if r.verifying {
                r.pausing = true
                r.cancelled = true
            } else if r.transferring, let t = r.task {
                r.pausing = true
                return t
            } else if r.task == nil {
                r.cancelled = true
                if !r.resumed { endNow = r.id }
            } else {
                // Between the end of the transfer and the start of hashing: hash nothing, keep the part.
                r.pausing = true
                r.cancelled = true
            }
            return nil
        }
        if let id = endNow { return finish(id, .failed(.cancelled)) }
        task?.cancel()
    }

    /// «Resume» (a click). The record is re-validated first (R17), then the transfer continues
    /// from the last checkpoint. Nothing here runs without that click.
    func resume(downloadsDir: URL) {
        let id = UUID()
        let taken: IPSWPartialRecord? = locked {
            guard run == nil, let p = parked else { return nil }
            parked = nil
            var r = Run(id: id, onPhase: p.onPhase, downloadsDir: downloadsDir)
            r.record = p.record
            r.identifier = p.record.identifier
            r.digests = p.record.digests
            r.fileName = p.record.fileName
            r.size = p.record.size
            r.resumed = true
            run = r
            return p.record
        }
        guard let record = taken else { return }
        emit(id, .preparing)
        Task.detached(priority: .userInitiated) { [self] in
            self.runResume(id: id, record: record, downloadsDir: downloadsDir)
        }
    }

    /// «Discard»: deletes the partial and its record.
    func discard() {
        let p: Parked? = locked {
            let p = parked
            parked = nil
            return p
        }
        guard let p else { return }
        deleteFiles(record: p.record, partURL: p.partURL)
        Self.deliver(.failed(.cancelled), to: p.onPhase)
    }

    /// Launch (called once from the model): cleanup, then the surviving record becomes the parked
    /// download. A record still marked running is a crash or force-quit (D22). Disk only, never the network.
    func restore(knownIdentifiers: Set<String>, onPhase: @escaping PhaseHandler) -> IPSWPartialRecord? {
        guard !isBusy else { return nil }
        guard let survivor = IPSWPartialStore.cleanup(root: stagingRoot, knownIdentifiers: knownIdentifiers, now: now())
        else { return nil }
        var record = survivor.record
        // A partial in Downloads is resolved by path only here (no access): launch never touches Downloads.
        var partURL = survivor.part
        if record.partInDownloads {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            partURL = IPSWPartialStore.partURL(record.id, in: (downloads ?? stagingRoot)
                .appendingPathComponent(IPSWData.hiddenStagingName, isDirectory: true))
        }
        if record.stoppedAt == nil {
            let modified = record.partInDownloads ? nil
                : (try? FileManager.default.attributesOfItem(atPath: partURL.path))?[.modificationDate] as? Date
            record.stoppedAt = modified ?? record.startedAt
            record.reason = .appQuit
            try? IPSWPartialStore.write(record, root: stagingRoot)
        }
        let kept = record
        let claimed: Bool = locked {
            guard run == nil, parked == nil else { return false }
            parked = Parked(record: kept, partURL: partURL, onPhase: onPhase)
            return true
        }
        return claimed ? record : nil
    }

    /// Quit (D11), called synchronously from `willTerminate`: the running transfer is flushed and
    /// its record saved as stopped with `.appQuit`. It runs on the delegate queue so it never races
    /// `didReceive data`. Parked: already on disk. Preparing: no file yet.
    func suspendForQuit() {
        onQueue { [self] in
            guard let r = locked({ run }) else { return }
            if r.verifying {
                guard var record = r.record else { return }
                record.checkpoint = record.size
                record.stoppedAt = now()
                record.reason = .appQuit
                try? IPSWPartialStore.write(record, root: stagingRoot)
                locked {
                    guard run?.id == r.id else { return }
                    run?.record = record
                    run?.pausing = false
                    run?.cancelled = true
                }
            } else if r.transferring, let task = r.task {
                try? r.handle?.synchronize()
                guard var record = locked({ run?.id == r.id ? run?.record : nil }) else { return }
                record.checkpoint = locked { run?.written } ?? record.checkpoint
                record.stoppedAt = now()
                record.reason = .appQuit
                try? IPSWPartialStore.write(record, root: stagingRoot)
                locked { if run?.id == r.id { run?.record = record } }
                task.cancel()
            }
        }
    }

    /// Unlinking the last phone of a model (D26): a parked or running download of that model is
    /// cancelled and both of its files are deleted.
    func forget(identifier: String) {
        onQueue { [self] in
            enum Hit { case running(Run), stopped(Parked) }
            let hit: Hit? = locked {
                if let r = run, r.identifier == identifier { run = nil; return .running(r) }
                if let p = parked, p.record.identifier == identifier { parked = nil; return .stopped(p) }
                return nil
            }
            switch hit {
            case .running(let r)?:
                r.task?.cancel()
                try? r.handle?.close()
                // A resume still re-validating has a record but no partURL yet: derive it the way `runResume` does.
                if let record = r.record {
                    let dir = record.partInDownloads
                        ? r.downloadsDir.appendingPathComponent(IPSWData.hiddenStagingName, isDirectory: true) : stagingRoot
                    deleteFiles(record: record, partURL: r.partURL ?? IPSWPartialStore.partURL(record.id, in: dir))
                }
                if let staging = r.staging, staging.lastPathComponent == IPSWData.hiddenStagingName { _ = rmdir(staging.path) }
                Self.deliver(.failed(.cancelled), to: r.onPhase)
            case .stopped(let p)?:
                deleteFiles(record: p.record, partURL: p.partURL)
                Self.deliver(.failed(.cancelled), to: p.onPhase)
            case nil:
                break
            }
        }
    }

    // MARK: preparation (off the main actor)

    private func prepare(id: UUID, build b: IPSWBuild, url: URL, downloadsDir: URL, sources: IPSWSources) async {
        var headLength: Int64?
        if (b.ipswMe?.fileSize ?? 0) <= 0 {
            switch await sources.head(url) {
            case .success(let n): headLength = n
            case .failure(let e): return finish(id, .failed(e))
            }
        }
        guard !isCancelled(id) else { return finish(id, .failed(.cancelled)) }

        let size: Int64
        switch IPSWData.expectedSize(b, headLength: headLength) {
        case .success(let s): size = s
        case .failure(let e): return finish(id, .failed(e))
        }

        // Rule 7 — at click time, so the macOS Files & Folders prompt (if any) appears now.
        switch DirectoryAccess.probe(downloadsDir.path) {
        case .readable: break
        case .denied: return finish(id, .failed(.downloadsDenied))
        case .missing: return finish(id, .failed(.fileSystem(downloadsDir.path)))
        }

        // Nothing touches Downloads once this run was cancelled or has ended.
        guard !isCancelled(id) else { return finish(id, .failed(.cancelled)) }
        // R18, at every download start: orphans in the caches root, leftovers of the shipped engine.
        // A valid record that is not tracked here is kept (never destroy a partial without a click).
        let untracked = IPSWPartialStore.cleanup(root: stagingRoot, knownIdentifiers: nil, now: now())
        Self.sweepStaleStaging(downloadsDir: downloadsDir, spare: untracked?.record.id, tempDirectory: tempDirectory)
        let staging: URL
        do {
            staging = try Self.stagingDirectory(for: downloadsDir, root: stagingRoot)
        } catch {
            return finish(id, .failed(Self.fileSystemError(error)))
        }
        // Recorded at once, so finish removes the empty hidden dir on cancel or any later failure.
        locked { if run?.id == id { run?.staging = staging } }
        guard !isCancelled(id) else { return finish(id, .failed(.cancelled)) }

        var volumes = [staging]
        if !Self.sameVolume(staging, downloadsDir) { volumes.append(downloadsDir) }
        for v in volumes {
            if let e = IPSWData.spaceCheck(needed: size, available: capacity(v)) {
                return finish(id, .failed(e))
            }
        }

        // The partial and its record exist from here on (D21).
        let digests = locked { run?.digests } ?? ExpectedDigests(sha256: nil, sha1: nil, sha1Sources: [])
        let record = IPSWPartialRecord(
            version: IPSWPartialRecord.currentVersion, id: UUID(), identifier: b.apple?.identifier ?? "",
            productVersion: b.version, buildID: b.buildID, url: url, size: size, sha256: digests.sha256,
            sha1: digests.sha1, sha1Sources: digests.sha1Sources.sorted { $0.rawValue < $1.rawValue },
            fileName: IPSWData.fileName(for: b), validator: nil, checkpoint: 0, startedAt: now(), stoppedAt: nil,
            reason: nil, partInDownloads: staging.standardizedFileURL != stagingRoot.standardizedFileURL)
        let part = IPSWPartialStore.partURL(record.id, in: staging)
        let handle: FileHandle
        do {
            guard FileManager.default.createFile(atPath: part.path, contents: nil, attributes: [.posixPermissions: 0o600])
            else { throw IPSWError.fileSystem(part.lastPathComponent) }
            try IPSWPartialStore.write(record, root: stagingRoot)
            handle = try FileHandle(forWritingTo: part)
        } catch {
            deleteFiles(record: record, partURL: part)
            return finish(id, .failed(Self.fileSystemError(error)))
        }

        let task = session.dataTask(with: Self.transferRequest(url, from: 0, validator: nil))
        let go: Bool = locked {
            guard run?.id == id, run?.cancelled == false else { return false }
            run?.task = task
            run?.size = size
            run?.staging = staging
            run?.record = record
            run?.partURL = part
            run?.handle = handle
            run?.transferring = true
            return true
        }
        guard go else {
            try? handle.close()
            deleteFiles(record: record, partURL: part)
            return finish(id, .failed(.cancelled))
        }
        emit(id, .downloading(written: 0, total: size))
        task.resume()
    }

    /// `Range` and `If-Range` only when resuming. `Accept-Encoding: identity` so byte offsets mean file offsets.
    static func transferRequest(_ url: URL, from written: Int64, validator: String?) -> URLRequest {
        var r = IPSWSources.request(url, timeout: transferTimeout)
        r.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if written > 0 {
            r.setValue("bytes=\(written)-", forHTTPHeaderField: "Range")
            if let validator { r.setValue(validator, forHTTPHeaderField: "If-Range") }
        }
        return r
    }

    /// Resume re-validation (R17) and the transfer start. Off the main actor; runs only after the click.
    private func runResume(id: UUID, record: IPSWPartialRecord, downloadsDir: URL) {
        let fm = FileManager.default
        let partDir = record.partInDownloads
            ? downloadsDir.appendingPathComponent(IPSWData.hiddenStagingName, isDirectory: true) : stagingRoot
        let part = IPSWPartialStore.partURL(record.id, in: partDir)

        // Refusals that delete: nothing can resume this partial any more.
        let partSize = (try? fm.attributesOfItem(atPath: part.path))?[.size] as? NSNumber
        let valid = IPSWData.downloadPolicy(record.url) == nil
            && (record.sha256 != nil || record.sha1 != nil)
            && record.size > 0 && record.checkpoint >= 0 && record.checkpoint <= record.size
            && !record.fileName.isEmpty && !record.fileName.contains("/") && !record.fileName.hasPrefix(".")
            && (partSize?.int64Value ?? -1) >= record.checkpoint
            && Self.sameVolume(partDir, downloadsDir)
        guard valid else {
            deleteFiles(record: record, partURL: part)
            return finish(id, .failed(.resumeRejected))
        }

        // Refusals that keep the partial parked: the user can fix the cause and click Resume again.
        guard !isCancelled(id) else { return unpark(id, record: record, partURL: part, interruption: nil) }
        switch DirectoryAccess.probe(downloadsDir.path) {
        case .readable: break
        case .denied: return unpark(id, record: record, partURL: part, interruption: .downloadsDenied)
        case .missing: return unpark(id, record: record, partURL: part, interruption: .fileSystem(downloadsDir.path))
        }
        if let e = IPSWData.spaceCheck(needed: record.size - record.checkpoint, available: capacity(partDir)) {
            return unpark(id, record: record, partURL: part, interruption: e)
        }
        guard !isCancelled(id) else { return unpark(id, record: record, partURL: part, interruption: nil) }

        var running = record
        running.stoppedAt = nil
        running.reason = nil
        let handle: FileHandle
        do {
            handle = try FileHandle(forUpdating: part)
            try handle.truncate(atOffset: UInt64(record.checkpoint))
            try handle.seek(toOffset: UInt64(record.checkpoint))
            try IPSWPartialStore.write(running, root: stagingRoot)
        } catch {
            return unpark(id, record: record, partURL: part, interruption: Self.fileSystemError(error))
        }

        if record.checkpoint == record.size {
            try? handle.close()
            let ok: Bool = locked {
                guard run?.id == id, run?.cancelled == false else { return false }
                run?.record = running
                run?.partURL = part
                run?.staging = partDir
                run?.written = running.checkpoint
                return true
            }
            guard ok else { return unpark(id, record: record, partURL: part, interruption: nil) }
            return beginVerify(id)
        }

        let task = session.dataTask(with: Self.transferRequest(record.url, from: record.checkpoint, validator: record.validator))
        let go: Bool = locked {
            guard run?.id == id, run?.cancelled == false else { return false }
            run?.task = task
            run?.record = running
            run?.partURL = part
            run?.staging = partDir
            run?.handle = handle
            run?.written = running.checkpoint
            run?.transferring = true
            return true
        }
        guard go else {
            try? handle.close()
            return unpark(id, record: record, partURL: part, interruption: nil)
        }
        emit(id, .downloading(written: running.checkpoint, total: running.size))
        task.resume()
    }

    /// A resume that stopped before its transfer: back to the parked state, files untouched
    /// (deleted when the run was forgotten meanwhile).
    private func unpark(_ id: UUID, record: IPSWPartialRecord, partURL: URL, interruption: IPSWError?) {
        let gone: Bool = locked {
            guard let r = run, r.id == id else { return true }
            parked = Parked(record: record, partURL: partURL, onPhase: r.onPhase)
            run = nil
            Self.deliver(.paused(written: record.checkpoint, total: record.size, interruption: interruption), to: r.onPhase)
            return false
        }
        // The run was forgotten (last phone of the model unlinked) while this resume was re-validating; it may
        // have rewritten the record since, so its files go now.
        if gone { deleteFiles(record: record, partURL: partURL) }
    }

    // MARK: URLSession delegate (serial queue)

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        if let original = task.originalRequest?.url, let target = request.url,
           RedirectGuard.allows(from: original, to: target) {
            completionHandler(request)
            return
        }
        let host = request.url?.host(percentEncoded: false) ?? ""
        locked {
            if run?.task?.taskIdentifier == task.taskIdentifier { run?.pendingError = .notDownloadable(host) }
        }
        completionHandler(nil)
        task.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let r = current(dataTask), r.pendingError == nil else { return completionHandler(.cancel) }
        var failure: IPSWError?
        var validator: String?
        if let original = dataTask.originalRequest?.url, let final = response.url,
           !RedirectGuard.allows(from: original, to: final) {
            failure = .notDownloadable(final.host(percentEncoded: false) ?? "")
        } else if let http = response as? HTTPURLResponse {
            if r.resumed {
                // Apple's CDN ignores If-Range (live probe, 2026-11-11), so the client compares the validator itself.
                let stored = r.record?.validator
                let header = stored.map { Self.validatorIsETag($0) ? "ETag" : "Last-Modified" }
                if !Self.acceptsResume(status: http.statusCode, contentRange: http.value(forHTTPHeaderField: "Content-Range"),
                                       written: r.written, size: r.size,
                                       responseValidator: header.flatMap { http.value(forHTTPHeaderField: $0) },
                                       storedValidator: stored) {
                    failure = .resumeRejected
                }
            } else if http.statusCode != 200 {
                failure = .http(http.statusCode)
            } else if http.expectedContentLength != -1, http.expectedContentLength != r.size {
                failure = .sizeMismatch(expected: r.size, actual: http.expectedContentLength)
            } else {
                validator = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Last-Modified")
            }
        } else {
            failure = .badResponse
        }
        if let failure {
            locked { if run?.id == r.id { run?.pendingError = failure } }
            return completionHandler(.cancel)
        }
        if let validator, var record = r.record {
            record.validator = validator
            do {
                try IPSWPartialStore.write(record, root: stagingRoot)
                locked { if run?.id == r.id { run?.record = record } }
            } catch {
                locked { if run?.id == r.id { run?.pendingError = Self.fileSystemError(error) } }
                return completionHandler(.cancel)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let r = current(dataTask), r.pendingError == nil, let handle = r.handle, let record = r.record else { return }
        let written = r.written + Int64(data.count)
        if written > r.size {
            // More bytes than both sources promised: stop now rather than fill the disk.
            locked { if run?.id == r.id { run?.pendingError = .sizeMismatch(expected: r.size, actual: written) } }
            return dataTask.cancel()
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            locked { if run?.id == r.id { run?.pendingError = Self.fileSystemError(error) } }
            return dataTask.cancel()
        }

        var checkpointed: IPSWPartialRecord?
        if written - record.checkpoint >= checkpointBytes {
            try? handle.synchronize()
            var updated = record
            updated.checkpoint = written
            try? IPSWPartialStore.write(updated, root: stagingRoot)
            checkpointed = updated
        }
        var progress: IPSWDownloadPhase?
        locked {
            guard run?.id == r.id else { return }
            run?.written = written
            if let checkpointed { run?.record = checkpointed }
            let at = Date()
            if at.timeIntervalSince(r.lastProgress) >= Self.progressInterval || written == r.size {
                run?.lastProgress = at
                progress = .downloading(written: written, total: r.size)
            }
        }
        if let progress { emit(r.id, progress) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let r = current(task) else { return }
        if let handle = r.handle {
            try? handle.synchronize()
            try? handle.close()
        }
        locked { if run?.id == r.id { run?.handle = nil; run?.transferring = false } }
        let id = r.id

        if let e = r.pendingError {
            discardFiles(of: r)
            return finish(id, .failed(e))
        }
        if r.pausing { return park(id, reason: nil) }
        if let error {
            let mapped = IPSWSources.mapError(error)
            if r.written == 0 {
                discardFiles(of: r)
                return finish(id, .failed(mapped))
            }
            // A cancelled task nobody asked to stop is the quit hook (`suspendForQuit`).
            if mapped == .cancelled { return park(id, reason: .appQuit) }
            return park(id, reason: IPSWStopReason(mapped) ?? .transfer(error.localizedDescription))
        }
        guard r.written == r.size else {
            discardFiles(of: r)
            return finish(id, .failed(.sizeMismatch(expected: r.size, actual: r.written)))
        }
        beginVerify(id)
    }

    /// Transfer finished (or the partial was already complete on resume): hash and move.
    private func beginVerify(_ id: UUID) {
        let snapshot: Run? = locked {
            guard var r = run, r.id == id else { return nil }
            r.verifying = true
            r.transferring = false
            r.record?.checkpoint = r.size
            run = r
            return r
        }
        guard let r = snapshot, var record = r.record, let part = r.partURL else { return }
        record.checkpoint = record.size
        do {
            try IPSWPartialStore.write(record, root: stagingRoot)
        } catch {
            discardFiles(of: r)
            return finish(id, .failed(Self.fileSystemError(error)))
        }
        emit(id, .verifying(hashed: 0, total: r.size))
        let size = r.size, digests = r.digests, dir = r.downloadsDir, name = r.fileName
        Task.detached(priority: .utility) { [self] in
            var last = Date.distantPast
            do {
                let (url, verified) = try IPSWDownloader.finalize(
                    staged: part, size: size, digests: digests, downloadsDir: dir, fileName: name,
                    progress: { n in
                        let now = Date()
                        guard now.timeIntervalSince(last) >= IPSWDownloader.progressInterval || n == size else { return }
                        last = now
                        self.emit(id, .verifying(hashed: n, total: size))
                    },
                    isCancelled: { self.isCancelled(id) })
                try? FileManager.default.removeItem(at: IPSWPartialStore.recordURL(record.id, in: self.stagingRoot))
                self.finish(id, .finished(url, verified: verified))
            } catch IPSWError.cancelled {
                // The complete partial is kept (finalize did not delete it): Resume re-verifies.
                self.park(id, reason: self.locked { self.run?.pausing == true } ? nil : .appQuit)
            } catch {
                // finalize already removed the partial.
                try? FileManager.default.removeItem(at: IPSWPartialStore.recordURL(record.id, in: self.stagingRoot))
                self.finish(id, .failed(IPSWSources.mapError(error)))
            }
        }
    }

    /// Keeps the partial: record `checkpoint`, `stoppedAt` and `reason` are saved, the run becomes the parked
    /// download and `.paused` is delivered. Only for the run `id`.
    private func park(_ id: UUID, reason: IPSWStopReason?) {
        locked {
            guard let r = run, r.id == id, var record = r.record, let part = r.partURL else { return }
            record.checkpoint = r.verifying ? record.size : r.written
            record.stoppedAt = now()
            record.reason = reason
            try? IPSWPartialStore.write(record, root: stagingRoot)
            parked = Parked(record: record, partURL: part, onPhase: r.onPhase)
            run = nil
            Self.deliver(.paused(written: record.checkpoint, total: record.size, interruption: reason?.error), to: r.onPhase)
        }
    }

    // MARK: finalize (pure-ish: temp files in tests)

    /// Rules 3, 5, 9, 10: size first, then every expected digest in one pass, then an atomic
    /// no-overwrite move into `downloadsDir`. The staged file is gone afterwards whatever happens,
    /// except when the work was cancelled: then the caller parks the complete partial.
    /// Returns the final URL and exactly the digests that were verified.
    static func finalize(staged: URL, size: Int64, digests: ExpectedDigests, downloadsDir: URL, fileName: String,
                         progress: (Int64) -> Void, isCancelled: () -> Bool) throws -> (URL, Set<VerifiedDigest>) {
        var moved = false
        var keep = false
        defer { if !moved && !keep { try? FileManager.default.removeItem(at: staged) } }

        let attrs = try? FileManager.default.attributesOfItem(atPath: staged.path)
        guard let actual = (attrs?[.size] as? NSNumber)?.int64Value else {
            throw IPSWError.fileSystem(staged.lastPathComponent)
        }
        guard actual == size else { throw IPSWError.sizeMismatch(expected: size, actual: actual) }

        var want = Set<DigestAlgorithm>()
        if digests.sha256 != nil { want.insert(.sha256) }
        if digests.sha1 != nil { want.insert(.sha1) }
        guard !want.isEmpty else { throw IPSWError.noChecksum }

        let got: [DigestAlgorithm: String]
        do {
            got = try IPSWData.digests(of: staged, want: want, progress: progress, isCancelled: isCancelled)
        } catch IPSWError.cancelled {
            keep = true
            throw IPSWError.cancelled
        }
        var verified = Set<VerifiedDigest>()
        if let expected = digests.sha256 {
            guard got[.sha256] == expected else { throw IPSWError.checksumMismatch }
            verified.insert(VerifiedDigest(algorithm: .sha256, sources: [.ipswMe]))
        }
        if let expected = digests.sha1 {
            guard got[.sha1] == expected else { throw IPSWError.checksumMismatch }
            verified.insert(VerifiedDigest(algorithm: .sha1, sources: digests.sha1Sources))
        }
        if isCancelled() {
            keep = true
            throw IPSWError.cancelled
        }

        let final = try moveNoOverwrite(staged, into: downloadsDir, fileName: fileName)
        moved = true
        return (final, verified)
    }

    /// Rule 9: `renamex_np(RENAME_EXCL)` — atomic, and never replaces an existing file.
    static func moveNoOverwrite(_ src: URL, into dir: URL, fileName: String) throws -> URL {
        for attempt in 1...1000 {
            let dst = dir.appendingPathComponent(IPSWData.nextName(fileName, attempt: attempt), isDirectory: false)
            let (rc, err) = src.withUnsafeFileSystemRepresentation { s in
                dst.withUnsafeFileSystemRepresentation { d -> (Int32, Int32) in
                    guard let s, let d else { return (-1, EINVAL) }
                    let rc = renamex_np(s, d, UInt32(RENAME_EXCL))
                    return (rc, rc == 0 ? 0 : errno)
                }
            }
            if rc == 0 { return dst }
            if err == EEXIST { continue }
            if err == EPERM || err == EACCES { throw IPSWError.downloadsDenied }
            throw IPSWError.fileSystem(String(cString: strerror(err)))
        }
        throw IPSWError.fileSystem(fileName)
    }

    /// Rule 12: only a 206 whose `Content-Range` names exactly the rest of the file counts as a resume.
    /// 200 (`If-Range` mismatch or no range support), 416 and every other range are refused.
    /// With a stored validator the 206 must also carry the same kind of header (`responseValidator` is the
    /// value of the ETag header when `storedValidator` came from ETag, else of Last-Modified) with an
    /// identical value: the CDN answers 206 to any `If-Range`, so the client enforces it. No stored validator:
    /// the range check and the final size and digests protect the file.
    static func acceptsResume(status: Int, contentRange: String?, written: Int64, size: Int64,
                              responseValidator: String? = nil, storedValidator: String? = nil) -> Bool {
        guard status == 206, written >= 0, written < size, let contentRange,
              contentRange.trimmingCharacters(in: .whitespaces) == "bytes \(written)-\(size - 1)/\(size)" else { return false }
        guard let storedValidator else { return true }
        return responseValidator?.trimmingCharacters(in: .whitespaces) == storedValidator.trimmingCharacters(in: .whitespaces)
    }

    /// A stored validator is an entity tag (`"…"` or `W/"…"`) or else an HTTP date from Last-Modified.
    static func validatorIsETag(_ v: String) -> Bool {
        let t = v.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("\"") || t.hasPrefix("W/")
    }

    // MARK: staging + volumes

    /// `root` (the caches folder, created 0700) when it is on the Downloads volume, else a hidden
    /// 0700 directory inside Downloads. Same volume keeps the final rename atomic.
    static func stagingDirectory(for downloadsDir: URL, root: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        if sameVolume(root, downloadsDir) { return root }
        let hidden = downloadsDir.appendingPathComponent(IPSWData.hiddenStagingName, isDirectory: true)
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: hidden.path, isDirectory: &isDir) {
            try fileManager.createDirectory(at: hidden, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
        } else if !isDir.boolValue {
            throw IPSWError.fileSystem(hidden.path)
        }
        return hidden
    }

    /// Rule 10: stale `MacDashboard-ipsw-*` of the shipped engine in the temp dir and in the hidden
    /// Downloads directory (a partial left there by a stopped download goes here, at the next start);
    /// the files of `spare` stay. The hidden directory itself goes when empty (`rmdir` refuses a non-empty one).
    static func sweepStaleStaging(downloadsDir: URL, spare: UUID? = nil,
                                  tempDirectory: URL = FileManager.default.temporaryDirectory,
                                  fileManager: FileManager = .default) {
        let hidden = downloadsDir.appendingPathComponent(IPSWData.hiddenStagingName, isDirectory: true)
        for dir in [tempDirectory, hidden] {
            guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasPrefix(IPSWData.stagingPrefix) {
                if let spare, name.contains(spare.uuidString) { continue }
                try? fileManager.removeItem(at: dir.appendingPathComponent(name, isDirectory: false))
            }
        }
        _ = rmdir(hidden.path)
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        guard let x = (try? a.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject,
              let y = (try? b.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        else { return false }
        return x.isEqual(y)
    }

    static func availableCapacity(_ url: URL) -> Int64? {
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let n = v?.volumeAvailableCapacityForImportantUsage, n > 0 { return n }
        return v?.volumeAvailableCapacity.map { Int64($0) }
    }

    /// The volume's free and total bytes (the confirm step shows them; reads system data, so off the main thread).
    static func volumeInfo(_ url: URL) -> (available: Int64?, total: Int64?) {
        let total = (try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity
        return (availableCapacity(url), total.map { Int64($0) })
    }

    static func fileSystemError(_ error: Error) -> IPSWError {
        if let e = error as? IPSWError { return e }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteNoPermissionError { return .downloadsDenied }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) || ns.code == Int(EACCES) { return .downloadsDenied }
        return .fileSystem(ns.localizedDescription)
    }

    // MARK: state helpers

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Runs `body` on the delegate queue and waits, so it is ordered with every delegate callback.
    private func onQueue(_ body: @escaping @Sendable () -> Void) {
        queue.addOperations([BlockOperation(block: body)], waitUntilFinished: true)
    }

    private func current(_ task: URLSessionTask) -> Run? {
        locked { run?.task?.taskIdentifier == task.taskIdentifier ? run : nil }
    }

    /// True once the run was cancelled or has already ended.
    private func isCancelled(_ id: UUID) -> Bool {
        locked { run?.id != id || run?.cancelled == true }
    }

    private func emit(_ id: UUID, _ phase: IPSWDownloadPhase) {
        // Id check and enqueue in one critical section: `finish` clears `run` under the same lock,
        // so nothing for this run can be enqueued after its terminal phase.
        locked {
            guard let r = run, r.id == id else { return }
            Self.deliver(phase, to: r.onPhase)
        }
    }

    private func deleteFiles(record: IPSWPartialRecord, partURL: URL) {
        try? FileManager.default.removeItem(at: partURL)
        try? FileManager.default.removeItem(at: IPSWPartialStore.recordURL(record.id, in: stagingRoot))
        if partURL.deletingLastPathComponent().lastPathComponent == IPSWData.hiddenStagingName {
            _ = rmdir(partURL.deletingLastPathComponent().path)
        }
    }

    private func discardFiles(of r: Run) {
        if let record = r.record, let part = r.partURL { deleteFiles(record: record, partURL: part) }
    }

    /// Ends the run (once; later calls for the same id are no-ops), cleans staging, delivers.
    private func finish(_ id: UUID, _ phase: IPSWDownloadPhase) {
        let ended: Run? = locked {
            guard run?.id == id else { return nil }
            let r = run
            run = nil
            return r
        }
        guard let r = ended else { return }
        try? r.handle?.close()
        if let staging = r.staging, staging.lastPathComponent == IPSWData.hiddenStagingName {
            _ = rmdir(staging.path)
        }
        if !phase.isFinished { r.task?.cancel() }
        Self.deliver(phase, to: r.onPhase)   // run is already nil: no emit can enqueue after this
    }

    private static func deliver(_ phase: IPSWDownloadPhase, to handler: @escaping PhaseHandler) {
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(phase) } }
    }
}

private extension IPSWDownloadPhase {
    var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
}
