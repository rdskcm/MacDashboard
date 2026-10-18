// Engine/IPSWDownloader.swift
// IPHONE-IPSW: downloads ONE verified .ipsw into ~/Downloads, only on the user's click.
// Every rule of specs/IPHONE-IPSW.md § Download security is enforced here or in the pure
// helpers it calls (IPSWData): Apple's URL only (decision 5), https + exact host allowlist
// on the URL and on every redirect hop (network-stance), checksums cross-checked before a
// byte is fetched, size + free space + Downloads access before starting, staging on the
// Downloads volume, every digest verified after, an atomic no-overwrite move, cleanup on
// any failure, one download at a time, cancel in every phase.

import Foundation
import Darwin

enum IPSWDownloadPhase: Equatable {
    case preparing                                      // HEAD, probes
    case downloading(written: Int64, total: Int64)
    case verifying(hashed: Int64, total: Int64)
    case finished(URL, verified: Set<VerifiedDigest>)   // decision 3: the UI prints exactly this set
    case failed(IPSWError)

    var isTerminal: Bool {
        switch self {
        case .finished, .failed: return true
        default: return false
        }
    }
}

/// Own ephemeral session with a serial delegate queue. State lives behind `lock`; phases are
/// delivered on the main queue in the order they were produced.
final class IPSWDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias PhaseHandler = @MainActor (IPSWDownloadPhase) -> Void

    static let progressInterval: TimeInterval = 0.25
    static let transferTimeout: TimeInterval = 60       // idle timeout per request

    private struct Run {
        let id: UUID
        let onPhase: PhaseHandler
        let downloadsDir: URL
        var digests = ExpectedDigests(sha256: nil, sha1: nil, sha1Sources: [])
        var fileName = ""
        var size: Int64 = 0
        var staging: URL?
        var task: URLSessionDownloadTask?
        var staged: URL?
        var pendingError: IPSWError?
        var cancelled = false
        var lastProgress = Date.distantPast
    }

    private let lock = NSLock()
    private var run: Run?
    private var session: URLSession!

    override init() {
        super.init()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "MacDashboard.IPSWDownloader"
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }

    var isBusy: Bool { locked { run != nil } }

    // MARK: control

    /// Order: busy → availability (Apple's URL only) → downloadPolicy → digests cross-check →
    /// HEAD if ipsw.me gave no size → size → Downloads access → free space → transfer →
    /// staging → finalize. Every refusal before the transfer happens before any firmware byte.
    func start(_ b: IPSWBuild, downloadsDir: URL, sources: IPSWSources, onPhase: @escaping PhaseHandler) {
        let id = UUID()
        let claimed: Bool = locked {
            guard run == nil else { return false }
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
        }
        emit(id, .preparing)
        Task.detached(priority: .userInitiated) { [self] in
            await self.prepare(id: id, build: b, url: url, downloadsDir: downloadsDir, sources: sources)
        }
    }

    /// Works in every phase: before the transfer the run ends at once; during it the task is
    /// cancelled; while hashing `finalize` sees the flag and stops.
    func cancel() {
        var endNow: UUID?
        let task: URLSessionDownloadTask? = locked {
            run?.cancelled = true
            if let r = run, r.task == nil { endNow = r.id }
            return run?.task
        }
        if let id = endNow { return finish(id, .failed(.cancelled)) }
        task?.cancel()
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

        Self.sweepStaleStaging(downloadsDir: downloadsDir)
        let staging: URL
        do {
            staging = try Self.stagingDirectory(for: downloadsDir)
        } catch {
            return finish(id, .failed(Self.fileSystemError(error)))
        }

        var volumes = [staging]
        if !Self.sameVolume(staging, downloadsDir) { volumes.append(downloadsDir) }
        for v in volumes {
            if let e = IPSWData.spaceCheck(needed: size, available: Self.availableCapacity(v)) {
                locked { if run?.id == id { run?.staging = staging } }   // so finish removes an empty hidden dir
                return finish(id, .failed(e))
            }
        }

        let task = session.downloadTask(with: IPSWSources.request(url, timeout: Self.transferTimeout))
        let go: Bool = locked {
            guard run?.id == id, run?.cancelled == false else { return false }
            run?.task = task
            run?.size = size
            run?.staging = staging
            return true
        }
        guard go else { return finish(id, .failed(.cancelled)) }
        emit(id, .downloading(written: 0, total: size))
        task.resume()
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

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        var progress: (UUID, IPSWDownloadPhase)?
        var tooLong = false
        locked {
            guard var r = run, r.task?.taskIdentifier == downloadTask.taskIdentifier else { return }
            if totalBytesWritten > r.size {
                // More bytes than both sources promised: stop now rather than fill the disk.
                r.pendingError = .sizeMismatch(expected: r.size, actual: totalBytesWritten)
                tooLong = true
            } else {
                let now = Date()
                if now.timeIntervalSince(r.lastProgress) >= Self.progressInterval || totalBytesWritten == r.size {
                    r.lastProgress = now
                    progress = (r.id, .downloading(written: totalBytesWritten, total: r.size))
                }
            }
            run = r
        }
        if tooLong { downloadTask.cancel() }
        if let p = progress { emit(p.0, p.1) }
    }

    /// The temp file vanishes when this returns, so it is moved into staging here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let r = current(downloadTask), r.pendingError == nil, let staging = r.staging else { return }
        var failure: IPSWError?
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            failure = .http(http.statusCode)
        } else if let final = downloadTask.response?.url, let original = downloadTask.originalRequest?.url,
                  !RedirectGuard.allows(from: original, to: final) {
            failure = .notDownloadable(final.host(percentEncoded: false) ?? "")
        }
        let dst = staging.appendingPathComponent(IPSWData.stagingPrefix + UUID().uuidString + ".ipsw", isDirectory: false)
        if failure == nil {
            do { try FileManager.default.moveItem(at: location, to: dst) } catch { failure = Self.fileSystemError(error) }
        }
        let kept: Bool = locked {
            guard run?.id == r.id else { return false }
            if let failure { run?.pendingError = failure } else { run?.staged = dst }
            return true
        }
        if !kept && failure == nil { try? FileManager.default.removeItem(at: dst) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let r = current(task) else { return }
        if let e = r.pendingError { return finish(r.id, .failed(e)) }
        if r.cancelled { return finish(r.id, .failed(.cancelled)) }
        if let error { return finish(r.id, .failed(IPSWSources.mapError(error))) }
        guard let staged = r.staged else { return finish(r.id, .failed(.transfer("no file was received"))) }

        let id = r.id, size = r.size, digests = r.digests, dir = r.downloadsDir, name = r.fileName
        emit(id, .verifying(hashed: 0, total: size))
        Task.detached(priority: .utility) { [self] in
            var last = Date.distantPast
            do {
                let (url, verified) = try IPSWDownloader.finalize(
                    staged: staged, size: size, digests: digests, downloadsDir: dir, fileName: name,
                    progress: { n in
                        let now = Date()
                        guard now.timeIntervalSince(last) >= IPSWDownloader.progressInterval || n == size else { return }
                        last = now
                        self.emit(id, .verifying(hashed: n, total: size))
                    },
                    isCancelled: { self.isCancelled(id) })
                self.finish(id, .finished(url, verified: verified))
            } catch {
                self.finish(id, .failed(IPSWSources.mapError(error)))
            }
        }
    }

    // MARK: finalize (pure-ish: temp files in tests)

    /// Rules 3, 5, 9, 10: size first, then every expected digest in one pass, then an atomic
    /// no-overwrite move into `downloadsDir`. The staged file is gone afterwards whatever happens.
    /// Returns the final URL and exactly the digests that were verified.
    static func finalize(staged: URL, size: Int64, digests: ExpectedDigests, downloadsDir: URL, fileName: String,
                         progress: (Int64) -> Void, isCancelled: () -> Bool) throws -> (URL, Set<VerifiedDigest>) {
        var moved = false
        defer { if !moved { try? FileManager.default.removeItem(at: staged) } }

        let attrs = try? FileManager.default.attributesOfItem(atPath: staged.path)
        guard let actual = (attrs?[.size] as? NSNumber)?.int64Value else {
            throw IPSWError.fileSystem(staged.lastPathComponent)
        }
        guard actual == size else { throw IPSWError.sizeMismatch(expected: size, actual: actual) }

        var want = Set<DigestAlgorithm>()
        if digests.sha256 != nil { want.insert(.sha256) }
        if digests.sha1 != nil { want.insert(.sha1) }
        guard !want.isEmpty else { throw IPSWError.noChecksum }

        let got = try IPSWData.digests(of: staged, want: want, progress: progress, isCancelled: isCancelled)
        var verified = Set<VerifiedDigest>()
        if let expected = digests.sha256 {
            guard got[.sha256] == expected else { throw IPSWError.checksumMismatch }
            verified.insert(VerifiedDigest(algorithm: .sha256, sources: [.ipswMe]))
        }
        if let expected = digests.sha1 {
            guard got[.sha1] == expected else { throw IPSWError.checksumMismatch }
            verified.insert(VerifiedDigest(algorithm: .sha1, sources: digests.sha1Sources))
        }
        if isCancelled() { throw IPSWError.cancelled }

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

    // MARK: staging + volumes

    /// The temp dir when it is on the Downloads volume (so the final rename is atomic), else a
    /// hidden 0700 directory inside Downloads.
    static func stagingDirectory(for downloadsDir: URL, fileManager: FileManager = .default) throws -> URL {
        let tmp = fileManager.temporaryDirectory
        if sameVolume(tmp, downloadsDir) { return tmp }
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

    /// Rule 10: stale `MacDashboard-ipsw-*` from a crash or quit, in both staging locations;
    /// the hidden directory itself goes when empty (`rmdir` refuses a non-empty one).
    static func sweepStaleStaging(downloadsDir: URL, fileManager: FileManager = .default) {
        IPSWData.removeStaleStaging(in: fileManager.temporaryDirectory, fileManager: fileManager)
        let hidden = downloadsDir.appendingPathComponent(IPSWData.hiddenStagingName, isDirectory: true)
        IPSWData.removeStaleStaging(in: hidden, fileManager: fileManager)
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

    private func current(_ task: URLSessionTask) -> Run? {
        locked { run?.task?.taskIdentifier == task.taskIdentifier ? run : nil }
    }

    /// True once the run was cancelled or has already ended.
    private func isCancelled(_ id: UUID) -> Bool {
        locked { run?.id != id || run?.cancelled == true }
    }

    private func emit(_ id: UUID, _ phase: IPSWDownloadPhase) {
        guard let handler: PhaseHandler = locked({ run?.id == id ? run?.onPhase : nil }) else { return }
        Self.deliver(phase, to: handler)
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
        if case .finished = phase {} else if let staged = r.staged {
            try? FileManager.default.removeItem(at: staged)
        }
        if let staging = r.staging, staging.lastPathComponent == IPSWData.hiddenStagingName {
            _ = rmdir(staging.path)
        }
        if !phase.isFinished { r.task?.cancel() }
        Self.deliver(phase, to: r.onPhase)
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
