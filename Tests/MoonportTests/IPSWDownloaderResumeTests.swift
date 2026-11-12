// Tests/MoonportTests/IPSWDownloaderResumeTests.swift
// IPHONE-IPSW Stage A: the ranged data task, the persisted partial, pause / resume / restore, crash
// recovery, quit, forget, and the cleanup matrix. No network: `RangeStubProtocol` answers
// https://updates.cdn-apple.com/stub/x.ipsw in-process (it honours Range and If-Range) and the
// downloader gets it through `IPSWDownloader(protocolClasses:)`. Every directory is a fresh temp dir.
import CryptoKit
import Foundation
import os
import Testing
@testable import Moonport

// MARK: - the stub server

/// What the stub serves and how it misbehaves. One instance at a time (the suite is serialized).
final class RangeStubState: @unchecked Sendable {
    struct Seen: Equatable { var range: String?; var ifRange: String?; var method: String? }
    private let lock = NSLock()
    private var _body = Data()
    private var _etag: String? = "\"v1\""
    private var _holdAt: Int?
    private var _dropAt: Int?
    private var _answer416 = false
    private var _ignoreIfRange = false
    private var _omitETag = false
    private var _seen: [Seen] = []

    var body: Data { get { lock.withLock { _body } } set { lock.withLock { _body = newValue } } }
    var etag: String? { get { lock.withLock { _etag } } set { lock.withLock { _etag = newValue } } }
    /// Stop sending (and wait for the client to cancel) once this body offset is reached; one request only.
    var holdAt: Int? { get { lock.withLock { _holdAt } } set { lock.withLock { _holdAt = newValue } } }
    /// Fail with `networkConnectionLost` once this body offset is reached; one request only.
    var dropAt: Int? { get { lock.withLock { _dropAt } } set { lock.withLock { _dropAt = newValue } } }
    var answer416: Bool { get { lock.withLock { _answer416 } } set { lock.withLock { _answer416 = newValue } } }
    /// Answer 206 whatever `If-Range` says, like Apple's CDN.
    var ignoreIfRange: Bool { get { lock.withLock { _ignoreIfRange } } set { lock.withLock { _ignoreIfRange = newValue } } }
    /// Send no ETag header (a 206 that lacks the validator).
    var omitETag: Bool { get { lock.withLock { _omitETag } } set { lock.withLock { _omitETag = newValue } } }
    var seen: [Seen] { lock.withLock { _seen } }
    func record(_ s: Seen) { lock.withLock { _seen.append(s) } }
    func takeHold() -> Int? { lock.withLock { let v = _holdAt; _holdAt = nil; return v } }
    func takeDrop() -> Int? { lock.withLock { let v = _dropAt; _dropAt = nil; return v } }

    func reset(body: Data) {
        lock.withLock {
            _body = body; _etag = "\"v1\""; _holdAt = nil; _dropAt = nil; _answer416 = false; _ignoreIfRange = false; _omitETag = false; _seen = []
        }
    }
}

final class RangeStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = RangeStubState()
    static let chunk = 64 * 1024
    private let stopLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host(percentEncoded: false) == "updates.cdn-apple.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        DispatchQueue.global().async { [self] in serve(request) }
    }

    override func stopLoading() {
        stopLock.lock(); stopped = true; stopLock.unlock()
    }

    private var isStopped: Bool { stopLock.lock(); defer { stopLock.unlock() }; return stopped }

    private func serve(_ request: URLRequest) {
        let state = Self.state
        let range = request.value(forHTTPHeaderField: "Range")
        let ifRange = request.value(forHTTPHeaderField: "If-Range")
        state.record(.init(range: range, ifRange: ifRange, method: request.httpMethod))
        let body = state.body, etag = state.etag, ignoreIfRange = state.ignoreIfRange, omitETag = state.omitETag
        var start = 0
        var status = 200
        if let range {
            if state.answer416 { return respond(request, 416, [:], Data()) }
            let digits = range.replacingOccurrences(of: "bytes=", with: "").replacingOccurrences(of: "-", with: "")
            if (ifRange == nil || ifRange == etag || ignoreIfRange), let n = Int(digits), n < body.count { start = n; status = 206 }
        }
        var headers = ["Accept-Ranges": "bytes", "Content-Length": "\(body.count - start)"]
        if let etag, !omitETag { headers["ETag"] = etag }
        if status == 206 { headers["Content-Range"] = "bytes \(start)-\(body.count - 1)/\(body.count)" }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        let hold = state.takeHold(), drop = state.takeDrop()
        var offset = start
        while offset < body.count {
            if isStopped { return }
            if let hold, offset >= hold {
                for _ in 0..<6000 where !isStopped { Thread.sleep(forTimeInterval: 0.005) }   // 30 s at most
                return
            }
            if let drop, offset >= drop {
                Thread.sleep(forTimeInterval: 0.1)   // like a real drop: the bytes already sent reach the client first
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
            var end = min(offset + Self.chunk, body.count)
            if let hold, offset < hold { end = min(end, hold) }
            if let drop, offset < drop { end = min(end, drop) }
            client?.urlProtocol(self, didLoad: body.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private func respond(_ request: URLRequest, _ status: Int, _ headers: [String: String], _ body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - helpers

private let stubURL = URL(string: "https://updates.cdn-apple.com/stub/x.ipsw")!
private let stubModel = "iPhone18,2"

/// A deterministic body: a 1 MiB block of pseudo-random bytes, repeated with the block number stamped in.
private func makeBody(mib: Int) -> Data {
    var block = [UInt8](repeating: 0, count: 1 << 20)
    var x: UInt64 = 0x9E37_79B9_7F4A_7C15
    for i in 0..<block.count {
        x = x &* 6364136223846793005 &+ 1442695040888963407
        block[i] = UInt8(truncatingIfNeeded: x >> 33)
    }
    var out = Data(capacity: mib << 20)
    for n in 0..<mib {
        block[0] = UInt8(truncatingIfNeeded: n)
        out.append(contentsOf: block)
    }
    return out
}

private func digests(of body: Data) -> (sha256: String, sha1: String) {
    (IPSWData.hex(SHA256.hash(data: body)), IPSWData.hex(Insecure.SHA1.hash(data: body)))
}

private func makeBuild(_ body: Data) -> IPSWBuild {
    let d = digests(of: body)
    func fw(_ source: IPSWSource, sha256: String?, size: Int64?) -> IPSWFirmware {
        IPSWFirmware(source: source, identifier: stubModel, version: "27.0.1", buildID: "STUB1", sha256: sha256, sha1: d.sha1,
                     fileSize: size, url: stubURL, releaseDate: nil, signed: nil)
    }
    return IPSWData.merge(apple: IPSWAppleTarget(identifier: stubModel, firmware: fw(.apple, sha256: nil, size: nil)),
                          ipswMe: IPSWThirdParty(name: "stub", identifier: stubModel,
                                                 firmwares: [fw(.ipswMe, sha256: d.sha256, size: Int64(body.count))]))[0]
}

private func makeRecord(_ body: Data, checkpoint: Int64, stoppedAt: Date?, reason: IPSWStopReason? = nil,
                        url: URL = stubURL, withDigests: Bool = true, validator: String? = "\"v1\"") -> IPSWPartialRecord {
    let d = digests(of: body)
    return IPSWPartialRecord(
        version: IPSWPartialRecord.currentVersion, id: UUID(), identifier: stubModel, productVersion: "27.0.1",
        buildID: "STUB1", url: url, size: Int64(body.count), sha256: withDigests ? d.sha256 : nil,
        sha1: withDigests ? d.sha1 : nil, sha1Sources: withDigests ? [.apple, .ipswMe] : [], fileName: "x.ipsw",
        validator: validator, checkpoint: checkpoint, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
        stoppedAt: stoppedAt, reason: reason, partInDownloads: false)
}

private func tempDir(_ label: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("MoonportTests-ipsw-resume-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func names(_ dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
}

private func partFile(_ root: URL) -> URL? {
    names(root).first { $0.hasSuffix(".part") }.map { root.appendingPathComponent($0) }
}

private func partLength(_ root: URL) -> Int64 {
    guard let f = partFile(root),
          let n = (try? FileManager.default.attributesOfItem(atPath: f.path))?[.size] as? NSNumber else { return -1 }
    return n.int64Value
}

private func diskRecord(_ root: URL) -> IPSWPartialRecord? {
    names(root).first { $0.hasSuffix(".json") }.flatMap { IPSWPartialStore.read(root.appendingPathComponent($0)) }
}

/// Writes a record and (optionally) a partial holding the first `partBytes` of `body` into `root`.
@discardableResult
private func seed(_ record: IPSWPartialRecord, body: Data, partBytes: Int?, root: URL) throws -> URL {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try IPSWPartialStore.write(record, root: root)
    let part = IPSWPartialStore.partURL(record.id, in: root)
    if let partBytes { try body.prefix(partBytes).write(to: part) }
    return part
}

@MainActor
private final class Phases {
    var all: [IPSWDownloadPhase] = []
    var handler: IPSWDownloader.PhaseHandler { { [self] p in all.append(p) } }

    /// Polls (yielding to the main queue) for the first phase at or after `from` that matches.
    @discardableResult
    func wait(from: Int = 0, seconds: Double = 20, _ match: (IPSWDownloadPhase) -> Bool) async -> IPSWDownloadPhase? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let p = all.dropFirst(from).first(where: match) { return p }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return nil
    }

    func waitPaused(from: Int = 0) async -> IPSWDownloadPhase? {
        await wait(from: from) { if case .paused = $0 { return true }; return false }
    }
    func waitFinished(from: Int = 0) async -> IPSWDownloadPhase? { await wait(from: from) { $0.isTerminal } }
}

/// Polls a condition off the main actor's busy loop.
@MainActor
private func eventually(seconds: Double = 20, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

private struct Rig {
    let root: URL, downloads: URL, body: Data, build: IPSWBuild
    var size: Int64 { Int64(body.count) }

    @MainActor static func make(mib: Int = 3, label: String) throws -> Rig {
        let body = makeBody(mib: mib)
        RangeStubProtocol.state.reset(body: body)
        let base = try tempDir(label)
        let downloads = base.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        return Rig(root: base.appendingPathComponent("caches/ipsw", isDirectory: true), downloads: downloads,
                   body: body, build: makeBuild(body))
    }

    var base: URL { downloads.deletingLastPathComponent() }

    func downloader(checkpoint: Int64 = 256 << 10, capacity: @escaping @Sendable (URL) -> Int64? = { _ in 100 << 30 })
        -> IPSWDownloader {
        IPSWDownloader(stagingRoot: root, protocolClasses: [RangeStubProtocol.self], checkpointBytes: checkpoint,
                       capacity: capacity, tempDirectory: base.appendingPathComponent("tmp", isDirectory: true))
    }

    /// The HEAD never happens: ipsw.me gave the size.
    var sources: IPSWSources { IPSWSources(fetch: { _ in throw IPSWError.transfer("no request expected") }) }

    func cleanUp() { try? FileManager.default.removeItem(at: base) }
}

// MARK: - transfer, stop, resume

@Suite(.serialized)
@MainActor
struct IPSWDownloaderResumeTests {

    @Test func freshDownloadFinishesAndLeavesNoStaging() async throws {
        let rig = try Rig.make(label: "fresh")
        defer { rig.cleanUp() }
        let phases = Phases()
        let d = rig.downloader()
        d.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        let end = await phases.waitFinished()
        guard case .finished(let url, let verified)? = end else { Issue.record("not finished: \(String(describing: end))"); return }
        #expect(url == rig.downloads.appendingPathComponent("x.ipsw"))
        #expect(try Data(contentsOf: url) == rig.body)
        #expect(verified == [VerifiedDigest(algorithm: .sha256, sources: [.ipswMe]),
                             VerifiedDigest(algorithm: .sha1, sources: [.apple, .ipswMe])])
        #expect(names(rig.root).isEmpty, "root is empty after a finished download")
        #expect(names(rig.downloads) == ["x.ipsw"])
        #expect(phases.all.first == .preparing)
        #expect(RangeStubProtocol.state.seen == [.init(range: nil, ifRange: nil, method: "GET")])
        #expect(!d.isBusy)
    }

    @Test func stopKeepsThePartialAndANewInstanceResumesIt() async throws {
        let rig = try Rig.make(label: "stop")
        defer { rig.cleanUp() }
        RangeStubProtocol.state.holdAt = 1 << 20
        let phases = Phases()
        let d1 = rig.downloader()
        d1.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        #expect(await eventually { diskRecord(rig.root)?.checkpoint == 1 << 20 }, "checkpoints are rewritten while downloading")
        #expect(diskRecord(rig.root)?.validator == "\"v1\"")
        #expect(diskRecord(rig.root)?.stoppedAt == nil, "a running download has no stoppedAt")
        d1.cancel()
        guard case .paused(let w, let total, let why)? = await phases.waitPaused() else { Issue.record("no pause"); return }
        #expect(w >= 1 << 20 && total == rig.size && why == nil)
        let stopped = try #require(diskRecord(rig.root))
        #expect(partLength(rig.root) == w && stopped.checkpoint == w, ".part length == checkpoint == w")
        #expect(stopped.stoppedAt != nil && stopped.reason == nil)
        #expect(d1.isBusy, "a stopped download keeps the downloader busy")
        d1.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        #expect(await phases.wait { $0 == .failed(.busy) } != nil, "no new start while stopped")

        // A new instance stands in for a relaunch: restore reads the disk only, resume is a click.
        RangeStubProtocol.state.holdAt = nil
        let before = RangeStubProtocol.state.seen.count
        let phases2 = Phases()
        let d2 = rig.downloader()
        let restored = d2.restore(knownIdentifiers: [stubModel], onPhase: phases2.handler)
        #expect(restored == stopped)
        #expect(RangeStubProtocol.state.seen.count == before, "restore sends no request")
        #expect(phases2.all.isEmpty)
        d2.resume(downloadsDir: rig.downloads)
        guard case .finished(let url, let verified)? = await phases2.waitFinished() else { Issue.record("no finish"); return }
        let ranged = try #require(RangeStubProtocol.state.seen.last)
        #expect(ranged.range == "bytes=\(w)-" && ranged.ifRange == "\"v1\"")
        #expect(phases2.all.contains(.downloading(written: w, total: rig.size)), "the bar continues from w")
        #expect(try Data(contentsOf: url) == rig.body)
        #expect(verified.count == 2)
        #expect(names(rig.root).isEmpty)
    }

    @Test func aDroppedConnectionPausesWithTheReasonAndResumeWorks() async throws {
        let rig = try Rig.make(label: "drop")
        defer { rig.cleanUp() }
        RangeStubProtocol.state.dropAt = 1 << 20
        let phases = Phases()
        let d = rig.downloader()
        d.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        guard case .paused(let w, _, let why)? = await phases.waitPaused() else { Issue.record("no pause \(phases.all) \(RangeStubProtocol.state.seen)"); return }
        #expect(why == .offline && w == 1 << 20)
        let rec = try #require(diskRecord(rig.root))
        #expect(rec.reason == .offline && rec.stoppedAt != nil && rec.checkpoint == w && partLength(rig.root) == w)
        d.resume(downloadsDir: rig.downloads)
        guard case .finished(let url, _)? = await phases.waitFinished() else { Issue.record("no finish"); return }
        #expect(try Data(contentsOf: url) == rig.body)
        #expect(names(rig.root).isEmpty)
    }

    @Test func aChangedFileIsRejectedAndTheFilesAreDeleted() async throws {
        let rig = try Rig.make(label: "changed")
        defer { rig.cleanUp() }
        RangeStubProtocol.state.holdAt = 1 << 20
        let phases = Phases()
        let d1 = rig.downloader()
        d1.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        #expect(await eventually { partLength(rig.root) >= 1 << 20 })
        d1.cancel()
        #expect(await phases.waitPaused() != nil)

        // The file changed on the server: another validator and another body.
        RangeStubProtocol.state.etag = "\"v2\""
        RangeStubProtocol.state.body = Data("v2".utf8)
        let phases2 = Phases()
        let d2 = rig.downloader()
        #expect(d2.restore(knownIdentifiers: [stubModel], onPhase: phases2.handler) != nil)
        d2.resume(downloadsDir: rig.downloads)
        #expect(await phases2.waitFinished() == .failed(.resumeRejected))
        #expect(RangeStubProtocol.state.seen.last?.ifRange == "\"v1\"")
        #expect(names(rig.root).isEmpty, ".part and .json are gone")
        #expect(names(rig.downloads).isEmpty)
        #expect(!d2.isBusy)
    }

    /// Stops a download at 1 MiB and returns a new downloader restored from disk, ready for `resume`.
    private func stoppedThenRestored(_ rig: Rig) async throws -> (IPSWDownloader, Phases) {
        RangeStubProtocol.state.holdAt = 1 << 20
        let first = Phases()
        let d1 = rig.downloader()
        d1.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: first.handler)
        #expect(await eventually { partLength(rig.root) >= 1 << 20 })
        d1.cancel()
        #expect(await first.waitPaused() != nil)
        let phases = Phases()
        let d2 = rig.downloader()
        #expect(d2.restore(knownIdentifiers: [stubModel], onPhase: phases.handler) != nil)
        return (d2, phases)
    }

    @Test func a206WithAnotherETagIsRejectedEvenThoughTheServerIgnoresIfRange() async throws {
        let rig = try Rig.make(label: "etag-differs")
        defer { rig.cleanUp() }
        let (d, phases) = try await stoppedThenRestored(rig)
        RangeStubProtocol.state.etag = "\"v2\""
        RangeStubProtocol.state.ignoreIfRange = true      // answers 206 to the stale If-Range, like Apple's CDN
        d.resume(downloadsDir: rig.downloads)
        #expect(await phases.waitFinished() == .failed(.resumeRejected))
        #expect(RangeStubProtocol.state.seen.last?.ifRange == "\"v1\"", "If-Range stays on the request")
        #expect(names(rig.root).isEmpty && names(rig.downloads).isEmpty && !d.isBusy)
    }

    @Test func a206WithoutTheValidatorHeaderIsRejected() async throws {
        let rig = try Rig.make(label: "etag-missing")
        defer { rig.cleanUp() }
        let (d, phases) = try await stoppedThenRestored(rig)
        RangeStubProtocol.state.omitETag = true
        d.resume(downloadsDir: rig.downloads)
        #expect(await phases.waitFinished() == .failed(.resumeRejected))
        #expect(names(rig.root).isEmpty && !d.isBusy)
    }

    @Test func a206WithTheMatchingETagIsAcceptedAlsoWhenTheServerIgnoresIfRange() async throws {
        let rig = try Rig.make(label: "etag-matches")
        defer { rig.cleanUp() }
        let (d, phases) = try await stoppedThenRestored(rig)
        RangeStubProtocol.state.ignoreIfRange = true
        d.resume(downloadsDir: rig.downloads)
        guard case .finished(let url, _)? = await phases.waitFinished() else { Issue.record("no finish"); return }
        #expect(try Data(contentsOf: url) == rig.body)
        #expect(names(rig.root).isEmpty)
    }

    @Test func a416AnswerIsRejectedToo() async throws {
        let rig = try Rig.make(label: "416")
        defer { rig.cleanUp() }
        let record = makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: Date(), reason: nil)
        try seed(record, body: rig.body, partBytes: 512 << 10, root: rig.root)
        RangeStubProtocol.state.answer416 = true
        let phases = Phases()
        let d = rig.downloader()
        #expect(d.restore(knownIdentifiers: [stubModel], onPhase: phases.handler) != nil)
        d.resume(downloadsDir: rig.downloads)
        #expect(await phases.waitFinished() == .failed(.resumeRejected))
        #expect(names(rig.root).isEmpty)
    }

    @Test func aCrashedRunIsRestoredAsInterruptedAndTruncatedOnResume() async throws {
        let rig = try Rig.make(label: "crash")
        defer { rig.cleanUp() }
        // The app died mid-transfer: no stoppedAt, checkpoint 512 KiB, 900 KiB on disk.
        let record = makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: nil)
        let part = try seed(record, body: rig.body, partBytes: 900 << 10, root: rig.root)
        let phases = Phases()
        let d = rig.downloader()
        let restored = try #require(d.restore(knownIdentifiers: [stubModel], onPhase: phases.handler))
        #expect(restored.reason == .appQuit)
        let stoppedAt = try #require(restored.stoppedAt)
        let modified = try #require((try FileManager.default.attributesOfItem(atPath: part.path))[.modificationDate] as? Date)
        #expect(abs(stoppedAt.timeIntervalSince(modified)) < 1, "stoppedAt is the partial's modification date")
        #expect(diskRecord(rig.root)?.stoppedAt != nil && diskRecord(rig.root)?.reason == .appQuit, "persisted")
        #expect(RangeStubProtocol.state.seen.isEmpty)

        d.resume(downloadsDir: rig.downloads)
        guard case .finished(let url, _)? = await phases.waitFinished() else { Issue.record("no finish"); return }
        #expect(RangeStubProtocol.state.seen.map(\.range) == ["bytes=524288-"])
        #expect(try Data(contentsOf: url) == rig.body, "the unflushed tail was cut off and the rest re-fetched")
        #expect(names(rig.root).isEmpty)
    }

    @Test func aRecordThatFailsRevalidationIsRejectedWithoutARequest() async throws {
        let rig = try Rig.make(label: "reject")
        defer { rig.cleanUp() }
        let cases: [(String, IPSWPartialRecord, Int?)] = [
            ("not allowlisted", makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: Date(),
                                           url: URL(string: "https://evil.example/stub/x.ipsw")!), 512 << 10),
            ("http url", makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: Date(),
                                    url: URL(string: "http://updates.cdn-apple.com/stub/x.ipsw")!), 512 << 10),
            ("no digests", makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: Date(), withDigests: false), 512 << 10),
            ("partial shorter than checkpoint", makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: Date()), 100 << 10),
            ("no partial file", makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: Date()), nil),
        ]
        for (label, record, partBytes) in cases {
            // `restore` itself drops a record without a partial (cleanup), so that case is seeded with a
            // 1-byte partial and the file is removed after the restore (the user deleted the caches folder).
            try seed(record, body: rig.body, partBytes: partBytes ?? 1, root: rig.root)
            let phases = Phases()
            let d = rig.downloader()
            #expect(d.restore(knownIdentifiers: [stubModel], onPhase: phases.handler) != nil, Comment(rawValue: label))
            if partBytes == nil { try FileManager.default.removeItem(at: IPSWPartialStore.partURL(record.id, in: rig.root)) }
            d.resume(downloadsDir: rig.downloads)
            #expect(await phases.waitFinished() == .failed(.resumeRejected), Comment(rawValue: label))
            #expect(names(rig.root).isEmpty, Comment(rawValue: label))
        }
        #expect(RangeStubProtocol.state.seen.isEmpty, "no request for any refused record")
    }

    @Test func freeSpaceCountsThePartialAlreadyOnDisk() async throws {
        let rig = try Rig.make(label: "space")
        defer { rig.cleanUp() }
        let checkpoint: Int64 = 512 << 10
        let enoughForResume = rig.size - checkpoint + IPSWData.spaceMargin
        let record = makeRecord(rig.body, checkpoint: checkpoint, stoppedAt: Date())
        try seed(record, body: rig.body, partBytes: Int(checkpoint), root: rig.root)

        // A fresh start needs size + 1 GiB: the same capacity is not enough for it.
        let fresh = Phases()
        let other = try Rig.make(label: "space-fresh")
        defer { other.cleanUp() }
        let d0 = other.downloader(capacity: { _ in enoughForResume })
        d0.start(other.build, downloadsDir: other.downloads, sources: other.sources, onPhase: fresh.handler)
        guard case .failed(.notEnoughSpace)? = await fresh.waitFinished() else { Issue.record("fresh start was not refused"); return }

        // The resume needs size - checkpoint + 1 GiB, which is exactly there.
        RangeStubProtocol.state.reset(body: rig.body)
        let phases = Phases()
        let d = rig.downloader(capacity: { _ in enoughForResume })
        #expect(d.restore(knownIdentifiers: [stubModel], onPhase: phases.handler) != nil)
        d.resume(downloadsDir: rig.downloads)
        guard case .finished? = await phases.waitFinished() else { Issue.record("resume was refused"); return }
    }

    @Test func tooLittleSpaceKeepsTheFilesAndOffersResumeAgain() async throws {
        let rig = try Rig.make(label: "nospace")
        defer { rig.cleanUp() }
        let checkpoint: Int64 = 512 << 10
        let record = makeRecord(rig.body, checkpoint: checkpoint, stoppedAt: Date())
        try seed(record, body: rig.body, partBytes: Int(checkpoint), root: rig.root)
        let phases = Phases()
        let d = rig.downloader(capacity: { _ in IPSWData.spaceMargin })
        #expect(d.restore(knownIdentifiers: [stubModel], onPhase: phases.handler) != nil)
        d.resume(downloadsDir: rig.downloads)
        let needed = rig.size - checkpoint + IPSWData.spaceMargin
        let paused = await phases.waitPaused()
        #expect(paused == .paused(written: checkpoint, total: rig.size,
                                  interruption: .notEnoughSpace(needed: needed, available: IPSWData.spaceMargin)))
        #expect(names(rig.root).count == 2 && d.isBusy, "partial and record kept, still parked")
        #expect(RangeStubProtocol.state.seen.isEmpty)

        d.discard()
        #expect(await phases.waitFinished() == .failed(.cancelled))
        #expect(names(rig.root).isEmpty && !d.isBusy)
    }

    @Test func suspendForQuitSavesTheExactByteCount() async throws {
        let rig = try Rig.make(label: "quit")
        defer { rig.cleanUp() }
        RangeStubProtocol.state.holdAt = 1 << 20
        let phases = Phases()
        // A checkpoint interval larger than the transfer: only the quit hook can write the exact count.
        let d = rig.downloader(checkpoint: 64 << 20)
        d.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        #expect(await eventually { partLength(rig.root) >= 1 << 20 })
        #expect(diskRecord(rig.root)?.checkpoint == 0)
        d.suspendForQuit()
        let rec = try #require(diskRecord(rig.root))
        #expect(rec.stoppedAt != nil && rec.reason == .appQuit)
        #expect(rec.checkpoint == partLength(rig.root) && rec.checkpoint >= 1 << 20)
        guard case .paused(_, _, let why)? = await phases.waitPaused() else { Issue.record("no pause"); return }
        #expect(why == .appQuit)
    }

    @Test func stopWhileVerifyingKeepsTheCompletePartialAndResumeReverifiesWithoutARequest() async throws {
        let rig = try Rig.make(mib: 64, label: "verify")
        defer { rig.cleanUp() }
        let phases = Phases()
        let d = rig.downloader(checkpoint: 16 << 20)
        d.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        #expect(await phases.wait(seconds: 60) { if case .verifying = $0 { return true }; return false } != nil)
        d.cancel()
        let paused = await phases.waitPaused()
        #expect(paused == .paused(written: rig.size, total: rig.size, interruption: nil))
        let rec = try #require(diskRecord(rig.root))
        #expect(rec.checkpoint == rig.size && partLength(rig.root) == rig.size)

        let requests = RangeStubProtocol.state.seen.count
        d.resume(downloadsDir: rig.downloads)
        guard case .finished(let url, let verified)? = await phases.waitFinished(from: phases.all.count) else {
            Issue.record("no finish"); return
        }
        #expect(RangeStubProtocol.state.seen.count == requests, "re-verification sends nothing")
        #expect(verified.count == 2)
        #expect(try Data(contentsOf: url) == rig.body)
        #expect(names(rig.root).isEmpty)
    }

    @Test func forgetAndDiscardDeleteBothFiles() async throws {
        let rig = try Rig.make(label: "forget")
        defer { rig.cleanUp() }
        // Stopped download of this model.
        let record = makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: Date())
        try seed(record, body: rig.body, partBytes: 512 << 10, root: rig.root)
        let phases = Phases()
        let d = rig.downloader()
        #expect(d.restore(knownIdentifiers: [stubModel], onPhase: phases.handler) != nil)
        d.forget(identifier: "iPhone17,1")
        #expect(names(rig.root).count == 2 && d.isBusy, "another model: nothing happens")
        d.forget(identifier: stubModel)
        #expect(names(rig.root).isEmpty && !d.isBusy)
        #expect(await phases.waitFinished() == .failed(.cancelled))

        // A running download of this model.
        RangeStubProtocol.state.holdAt = 1 << 20
        let running = Phases()
        d.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: running.handler)
        #expect(await eventually { partLength(rig.root) >= 1 << 20 })
        d.forget(identifier: stubModel)
        #expect(names(rig.root).isEmpty && !d.isBusy)
        #expect(await running.waitFinished() == .failed(.cancelled))
        #expect(running.all.last == .failed(.cancelled), "nothing is delivered after the terminal phase")

        // Discard of a stopped one.
        let again = makeRecord(rig.body, checkpoint: 512 << 10, stoppedAt: Date())
        try seed(again, body: rig.body, partBytes: 512 << 10, root: rig.root)
        let p3 = Phases()
        let d3 = rig.downloader()
        #expect(d3.restore(knownIdentifiers: [stubModel], onPhase: p3.handler) != nil)
        d3.discard()
        #expect(names(rig.root).isEmpty && !d3.isBusy)
        #expect(await p3.waitFinished() == .failed(.cancelled))
    }

    @Test func forgetDuringResumeRevalidationDeletesBothFiles() async throws {
        let rig = try Rig.make(label: "forget-resume")
        defer { rig.cleanUp() }
        let checkpoint: Int64 = 512 << 10
        let record = makeRecord(rig.body, checkpoint: checkpoint, stoppedAt: Date())
        try seed(record, body: rig.body, partBytes: Int(checkpoint), root: rig.root)
        // The space check runs during re-validation: hold it there while the model is unlinked.
        let entered = OSAllocatedUnfairLock(initialState: false), gate = DispatchSemaphore(value: 0)
        let phases = Phases()
        let d = rig.downloader(capacity: { _ in entered.withLock { $0 = true }; gate.wait(); return 100 << 30 })
        #expect(d.restore(knownIdentifiers: [stubModel], onPhase: phases.handler) != nil)
        d.resume(downloadsDir: rig.downloads)
        #expect(await eventually { entered.withLock { $0 } }, "the resume reached its space check")
        d.forget(identifier: stubModel)
        #expect(names(rig.root).isEmpty && !d.isBusy)
        gate.signal()                                  // the resume goes on and finds its run gone
        #expect(await phases.waitFinished() == .failed(.cancelled))
        try await Task.sleep(nanoseconds: 300_000_000)  // it may have rewritten the record meanwhile
        #expect(names(rig.root).isEmpty && !d.isBusy, "no file is left behind")
        #expect(RangeStubProtocol.state.seen.isEmpty)
        #expect(phases.all.last == .failed(.cancelled))
    }

    @Test func stopBeforeTheFirstByteParksZeroBytes() async throws {
        let rig = try Rig.make(label: "first-byte")
        defer { rig.cleanUp() }
        RangeStubProtocol.state.holdAt = 0
        let phases = Phases()
        let d = rig.downloader()
        d.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        #expect(await phases.wait { $0 == .downloading(written: 0, total: rig.size) } != nil)
        d.cancel()
        // Zero bytes are stopped as a paused download of 0 bytes: Resume restarts from the beginning.
        #expect(await phases.waitPaused() == .paused(written: 0, total: rig.size, interruption: nil))
        d.discard()
        #expect(names(rig.root).isEmpty)
    }

    @Test func aDropBeforeTheFirstByteFailsAndDeletesTheFiles() async throws {
        let rig = try Rig.make(label: "drop-zero")
        defer { rig.cleanUp() }
        RangeStubProtocol.state.dropAt = 0
        let phases = Phases()
        let d = rig.downloader()
        d.start(rig.build, downloadsDir: rig.downloads, sources: rig.sources, onPhase: phases.handler)
        #expect(await phases.waitFinished() == .failed(.offline))
        #expect(names(rig.root).isEmpty && !d.isBusy)
    }
}

// MARK: - pure pieces

@Suite(.serialized)
@MainActor
struct IPSWPartialStoreTests {

    @Test func acceptsResumeTable() {
        let size: Int64 = 3_145_728
        func ok(_ status: Int, _ range: String?, _ written: Int64 = 1_048_576) -> Bool {
            IPSWDownloader.acceptsResume(status: status, contentRange: range, written: written, size: size)
        }
        #expect(ok(206, "bytes 1048576-3145727/3145728"))
        #expect(ok(206, " bytes 1048576-3145727/3145728 "))
        #expect(!ok(200, nil), "If-Range mismatch or no range support")
        #expect(!ok(200, "bytes 1048576-3145727/3145728"))
        #expect(!ok(416, nil))
        #expect(!ok(206, nil))
        #expect(!ok(206, "bytes 0-3145727/3145728"), "wrong start")
        #expect(!ok(206, "bytes 1048576-3145726/3145728"), "wrong end")
        #expect(!ok(206, "bytes 1048576-3145727/3145729"), "wrong total")
        #expect(!ok(206, "bytes 1048576-3145727/*"))
        #expect(!ok(206, "bytes 3145728-3145727/3145728", 3_145_728), "nothing left to resume")
    }

    @Test func acceptsResumeComparesTheStoredValidator() {
        let range = "bytes 1048576-3145727/3145728"
        func ok(_ response: String?, stored: String?) -> Bool {
            IPSWDownloader.acceptsResume(status: 206, contentRange: range, written: 1_048_576, size: 3_145_728,
                                         responseValidator: response, storedValidator: stored)
        }
        #expect(ok("\"v1\"", stored: "\"v1\""), "same ETag")
        #expect(!ok("\"v2\"", stored: "\"v1\""), "another ETag")
        #expect(!ok(nil, stored: "\"v1\""), "header missing")
        #expect(ok("Tue, 10 Nov 2026 10:00:00 GMT", stored: "Tue, 10 Nov 2026 10:00:00 GMT"), "same Last-Modified")
        #expect(!ok("Wed, 11 Nov 2026 10:00:00 GMT", stored: "Tue, 10 Nov 2026 10:00:00 GMT"))
        #expect(ok(nil, stored: nil) && ok("\"v9\"", stored: nil), "no stored validator: unchanged")
        #expect(!IPSWDownloader.acceptsResume(status: 200, contentRange: range, written: 1_048_576, size: 3_145_728,
                                              responseValidator: "\"v1\"", storedValidator: "\"v1\""))
        #expect(IPSWDownloader.validatorIsETag("\"abc-1\"") && IPSWDownloader.validatorIsETag("W/\"abc\""))
        #expect(!IPSWDownloader.validatorIsETag("Tue, 10 Nov 2026 10:00:00 GMT"))
    }

    @Test func recordRoundTripAndReconstruction() throws {
        let root = try tempDir("record")
        defer { try? FileManager.default.removeItem(at: root) }
        let body = makeBody(mib: 1)
        for sources: [IPSWSource] in [[.apple, .ipswMe], [.apple], [.ipswMe]] {
            var r = makeRecord(body, checkpoint: 123_456, stoppedAt: Date(timeIntervalSince1970: 1_800_100_000),
                               reason: .transfer("boom"))
            r.sha1Sources = sources
            try IPSWPartialStore.write(r, root: root)
            #expect(IPSWPartialStore.read(IPSWPartialStore.recordURL(r.id, in: root)) == r)

            let build = r.build
            #expect(IPSWData.expectedDigests(build) == .success(r.digests))
            #expect(IPSWData.expectedSize(build, headLength: nil) == .success(r.size))
            #expect(IPSWData.availability(build) == .available(r.url))
            #expect(build.buildID == r.buildID && build.version == r.productVersion && build.isAppleTarget)
            #expect(build.apple?.identifier == r.identifier)
            #expect(IPSWData.fileName(for: build) == r.fileName)
        }
        // Running (no stoppedAt, no reason) round-trips as nil.
        let running = makeRecord(body, checkpoint: 0, stoppedAt: nil)
        try IPSWPartialStore.write(running, root: root)
        #expect(IPSWPartialStore.read(IPSWPartialStore.recordURL(running.id, in: root))?.stoppedAt == nil)
    }

    @Test func stopReasonMapping() throws {
        #expect(IPSWStopReason(.offline) == .offline && IPSWStopReason(.timedOut) == .timedOut)
        #expect(IPSWStopReason(.transfer("x")) == .transfer("x"))
        #expect(IPSWStopReason(.cancelled) == nil && IPSWStopReason(.http(500)) == nil && IPSWStopReason(.busy) == nil)
        for reason: IPSWStopReason in [.offline, .timedOut, .transfer("detail"), .appQuit] {
            let data = try JSONEncoder().encode(reason)
            #expect(try JSONDecoder().decode(IPSWStopReason.self, from: data) == reason)
        }
        #expect(IPSWStopReason.appQuit.error == .appQuit && IPSWStopReason.offline.error == .offline)
        #expect(IPSWStopReason.transfer("d").error == .transfer("d"))
    }

    @Test func transferRequestHeaders() {
        let fresh = IPSWDownloader.transferRequest(stubURL, from: 0, validator: "\"v1\"")
        #expect(fresh.value(forHTTPHeaderField: "Range") == nil && fresh.value(forHTTPHeaderField: "If-Range") == nil)
        let resumed = IPSWDownloader.transferRequest(stubURL, from: 1_048_576, validator: "\"v1\"")
        #expect(resumed.value(forHTTPHeaderField: "Range") == "bytes=1048576-")
        #expect(resumed.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
        let bare = IPSWDownloader.transferRequest(stubURL, from: 1_048_576, validator: nil)
        #expect(bare.value(forHTTPHeaderField: "Range") == "bytes=1048576-" && bare.value(forHTTPHeaderField: "If-Range") == nil)
    }

    @Test func volumeInfoOfATempDirectory() throws {
        let dir = try tempDir("volume")
        defer { try? FileManager.default.removeItem(at: dir) }
        let v = IPSWDownloader.volumeInfo(dir)
        let available = try #require(v.available), total = try #require(v.total)
        #expect(available > 0 && total >= available)
    }

    // MARK: cleanup matrix

    private func clean(_ root: URL, known: Set<String>? = [stubModel], now: Date = Date(timeIntervalSince1970: 1_800_000_000 + 3600))
        -> (record: IPSWPartialRecord, part: URL)? {
        IPSWPartialStore.cleanup(root: root, knownIdentifiers: known, now: now)
    }

    @Test func cleanupDeletesOrphansAndKeepsAGoodRecord() throws {
        let root = try tempDir("cleanup")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let body = makeBody(mib: 1)
        let prefix = IPSWData.stagingPrefix

        // A good one.
        let good = makeRecord(body, checkpoint: 100, stoppedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let goodPart = try seed(good, body: body, partBytes: 200, root: root)
        // A partial without a record.
        let orphanPart = root.appendingPathComponent(prefix + UUID().uuidString + ".part")
        try Data(count: 10).write(to: orphanPart)
        // A record without a partial.
        let noPart = makeRecord(body, checkpoint: 0, stoppedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try seed(noPart, body: body, partBytes: nil, root: root)
        // Bad JSON with its partial.
        let badID = UUID()
        try Data("{not json".utf8).write(to: root.appendingPathComponent(prefix + badID.uuidString + ".json"))
        try Data(count: 10).write(to: IPSWPartialStore.partURL(badID, in: root))
        // Another record version, with its partial.
        var v2 = makeRecord(body, checkpoint: 0, stoppedAt: Date(timeIntervalSince1970: 1_800_000_000))
        v2.version = 2
        let v2Part = try seed(v2, body: body, partBytes: 10, root: root)
        // A staged file of the shipped engine, and a file that is not ours.
        let legacy = root.appendingPathComponent(prefix + UUID().uuidString + ".ipsw")
        try Data(count: 10).write(to: legacy)
        let stranger = root.appendingPathComponent("keep-me.part")
        try Data(count: 10).write(to: stranger)

        let survivor = try #require(clean(root))
        #expect(survivor.record == good && survivor.part == goodPart)
        let left = names(root)
        #expect(left == [goodPart.lastPathComponent, IPSWPartialStore.recordURL(good.id, in: root).lastPathComponent,
                         "keep-me.part"].sorted())
        for gone in [orphanPart, legacy, v2Part, IPSWPartialStore.recordURL(noPart.id, in: root),
                     IPSWPartialStore.recordURL(v2.id, in: root), IPSWPartialStore.partURL(badID, in: root)] {
            #expect(!fm.fileExists(atPath: gone.path), Comment(rawValue: gone.lastPathComponent))
        }
    }

    @Test func cleanupAppliesTheSevenDayLimitAndTheKnownModels() throws {
        let body = makeBody(mib: 1)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        // 6 days: kept. 8 days: deleted. Running (no stoppedAt): its startedAt counts.
        for (label, age, expectKept) in [("6 days", 6.0, true), ("8 days", 8.0, false)] {
            let root = try tempDir("age")
            defer { try? FileManager.default.removeItem(at: root) }
            let r = makeRecord(body, checkpoint: 10, stoppedAt: now.addingTimeInterval(-age * day))
            try seed(r, body: body, partBytes: 10, root: root)
            #expect((clean(root, now: now) != nil) == expectKept, Comment(rawValue: label))
            #expect(names(root).isEmpty == !expectKept, Comment(rawValue: label))
        }
        do {
            let root = try tempDir("age-running")
            defer { try? FileManager.default.removeItem(at: root) }
            var r = makeRecord(body, checkpoint: 10, stoppedAt: nil)
            r.startedAt = now.addingTimeInterval(-8 * day)
            try seed(r, body: body, partBytes: 10, root: root)
            #expect(clean(root, now: now) == nil && names(root).isEmpty)
        }
        // A model no remembered phone has: deleted. With `knownIdentifiers == nil` (download start) it stays.
        do {
            let root = try tempDir("unknown")
            defer { try? FileManager.default.removeItem(at: root) }
            let r = makeRecord(body, checkpoint: 10, stoppedAt: now)
            try seed(r, body: body, partBytes: 10, root: root)
            #expect(clean(root, known: nil, now: now)?.record == r)
            #expect(clean(root, known: ["iPhone1,1"], now: now) == nil && names(root).isEmpty)
        }
    }

    @Test func cleanupKeepsOnlyTheNewestOfTwo() throws {
        let root = try tempDir("two")
        defer { try? FileManager.default.removeItem(at: root) }
        let body = makeBody(mib: 1)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var older = makeRecord(body, checkpoint: 10, stoppedAt: now)
        older.startedAt = now.addingTimeInterval(-3600)
        var newer = makeRecord(body, checkpoint: 10, stoppedAt: now)
        newer.startedAt = now.addingTimeInterval(-60)
        try seed(older, body: body, partBytes: 10, root: root)
        try seed(newer, body: body, partBytes: 10, root: root)
        #expect(clean(root, now: now)?.record == newer)
        #expect(names(root).count == 2)
        #expect(!FileManager.default.fileExists(atPath: IPSWPartialStore.partURL(older.id, in: root).path))
    }

    @Test func cleanupNeverTouchesAPartialInDownloads() throws {
        let root = try tempDir("in-downloads-root")
        let downloads = try tempDir("in-downloads-dl")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: downloads) }
        let body = makeBody(mib: 1)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hidden = downloads.appendingPathComponent(IPSWData.hiddenStagingName, isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)

        // Good record, partial only in the hidden Downloads dir: the missing-partial rule is skipped.
        var good = makeRecord(body, checkpoint: 10, stoppedAt: now)
        good.partInDownloads = true
        let goodPart = IPSWPartialStore.partURL(good.id, in: hidden)
        try Data(count: 10).write(to: goodPart)
        try seed(good, body: body, partBytes: nil, root: root)
        #expect(clean(root, now: now)?.record == good)

        // Expired record of that kind: only the .json goes, the partial in Downloads is left for the next start.
        var old = makeRecord(body, checkpoint: 10, stoppedAt: now.addingTimeInterval(-9 * 86_400))
        old.partInDownloads = true
        let oldPart = IPSWPartialStore.partURL(old.id, in: hidden)
        try Data(count: 10).write(to: oldPart)
        try seed(old, body: body, partBytes: nil, root: root)
        #expect(clean(root, now: now)?.record == good)
        #expect(!FileManager.default.fileExists(atPath: IPSWPartialStore.recordURL(old.id, in: root).path))
        #expect(FileManager.default.fileExists(atPath: oldPart.path) && FileManager.default.fileExists(atPath: goodPart.path))

        // The sweep at the next download start removes what is stale there and spares the kept one.
        let legacyTemp = try tempDir("in-downloads-tmp")
        defer { try? FileManager.default.removeItem(at: legacyTemp) }
        let legacy = legacyTemp.appendingPathComponent(IPSWData.stagingPrefix + "old.ipsw")
        let other = legacyTemp.appendingPathComponent("unrelated.ipsw")
        try Data(count: 10).write(to: legacy); try Data(count: 10).write(to: other)
        IPSWDownloader.sweepStaleStaging(downloadsDir: downloads, spare: good.id, tempDirectory: legacyTemp)
        #expect(!FileManager.default.fileExists(atPath: legacy.path) && FileManager.default.fileExists(atPath: other.path),
                "the temp directory sweep is injectable and touches only our prefix")
        #expect(!FileManager.default.fileExists(atPath: oldPart.path))
        #expect(FileManager.default.fileExists(atPath: goodPart.path))
    }

    @Test func cleanupOfAMissingFolderIsNil() throws {
        let base = try tempDir("missing")
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(clean(base.appendingPathComponent("nope")) == nil)
    }
}
