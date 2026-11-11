// Tests/MacDashboardTests/IPSWLiveCanaryTests.swift
// IPHONE-IPSW opt-in live canary: the only test that touches the network, and only when asked.
//   MACDASH_LIVE=1 swift test --filter ipswLiveCanary
// Skipped in CI and by default. For iPhone18,2 it checks that the live catalogue and ipsw.me
// still have the shapes the fixtures record, that both agree on Apple's build, and that a HEAD
// on Apple's URL answers 200 with ipsw.me's size, every redirect hop on the allowlist. Then the
// resume probe (Decision 8): download, stop, relaunch (a new IPSWDownloader), resume, stop, and a
// resume with a wrong If-Range that the CDN must refuse. It downloads at most ~40 MB of one
// firmware, then deletes it; writes only in temp dirs.
//   MACDASH_LIVE=1 swift test --filter liveCanaryIPSWSpace
// needs no network: it reads the Downloads volume's free and total space (read-only) and compares
// them with `df`, the figures the confirm sheet's space check and low-space warning use.
import Foundation
import Testing
@testable import MacDashboard

private final class HopLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _hops: [(URL, Bool)] = []
    func add(_ url: URL, _ ok: Bool) { lock.lock(); _hops.append((url, ok)); lock.unlock() }
    var hops: [(URL, Bool)] { lock.lock(); defer { lock.unlock() }; return _hops }
}

private final class ByteCount: @unchecked Sendable {
    private let lock = NSLock()
    private var _last = 0
    func set(_ n: Int) { lock.lock(); _last = n; lock.unlock() }
    var last: Int { lock.lock(); defer { lock.unlock() }; return _last }
}

struct IPSWLiveCanaryTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
    func ipswLiveCanary() async throws {
        let id = "iPhone18,2"
        let hops = HopLog()
        let bytes = ByteCount()
        let session = IPSWSources.makeSession(redirectGuard: RedirectGuard(onHop: { hops.add($0, $1) }))
        let base = IPSWSources.liveFetch(using: session)
        let sources = IPSWSources(fetch: { request in
            let (data, response) = try await base(request)
            bytes.set(data.count)
            return (data, response)
        })

        var t0 = Date()
        let appleResult = await sources.appleTarget(identifier: id)
        print("ipsw canary: catalogue  \(ms(since: t0)) ms  \(bytes.last) bytes  \(appleResult)".prefix(300))
        let target = try #require(try appleResult.get(), "Apple's catalogue lists \(id)")
        #expect(IPSWData.downloadPolicy(target.firmware.url) == nil, "Apple's URL passes the allowlist")

        t0 = Date()
        let list = try await sources.ipswMe(identifier: id).get()
        print("ipsw canary: ipsw.me    \(ms(since: t0)) ms  \(bytes.last) bytes  \(list.firmwares.count) builds, signed: "
              + list.firmwares.filter { $0.signed == true }.map(\.buildID).joined(separator: ","))
        #expect(list.firmwares.contains { $0.signed == true }, "ipsw.me lists at least one signed build")
        let same = try #require(list.firmwares.first { $0.buildID == target.firmware.buildID },
                                "Apple's build \(target.firmware.buildID) is on ipsw.me")
        #expect(same.sha1 == target.firmware.sha1, "both sources publish the same SHA-1")

        t0 = Date()
        let length = try await sources.head(target.firmware.url).get()
        let hopText = hops.hops.map { "\($0.0.host(percentEncoded: false) ?? "?")\($0.1 ? "" : " REFUSED")" }
        print("ipsw canary: CDN HEAD   \(ms(since: t0)) ms  Content-Length \(length.map { "\($0)" } ?? "none")"
              + "  hops: \(hopText.isEmpty ? "none" : hopText.joined(separator: " → "))")
        #expect(length == same.fileSize, "HEAD Content-Length equals ipsw.me filesize")
        #expect(hops.hops.allSatisfy { $0.1 }, "every redirect hop is on the allowlist")

        let build = try #require(IPSWData.merge(apple: target, ipswMe: list).first { $0.buildID == target.firmware.buildID })
        try await resumeProbe(build: build, identifier: id, sources: sources)
    }

    /// Start → stop at ≥ 16 MiB → new downloader → restore → resume (206) → stop at +16 MiB → wrong
    /// `If-Range` must end in `.resumeRejected` with an empty root, whatever status the server sends (Apple's CDN
    /// answers 206: the downloader compares the validator itself). Only the two staging dirs below are written.
    @MainActor
    private func resumeProbe(build: IPSWBuild, identifier: String, sources: IPSWSources) async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("MacDashboardTests-ipsw-live-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("caches", isDirectory: true)
        let downloads = base.appendingPathComponent("Downloads", isDirectory: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let downloaders = [IPSWDownloader(stagingRoot: root), IPSWDownloader(stagingRoot: root), IPSWDownloader(stagingRoot: root)]
        defer {
            for d in downloaders { d.forget(identifier: identifier) }   // stops a transfer, deletes the files
            try? fm.removeItem(at: base)
        }
        func names() -> [String] { ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() }
        func record() -> IPSWPartialRecord? {
            names().first { $0.hasSuffix(".json") }.flatMap { IPSWPartialStore.read(root.appendingPathComponent($0)) }
        }
        func partLength() -> Int64 {
            guard let n = names().first(where: { $0.hasSuffix(".part") }),
                  let size = (try? fm.attributesOfItem(atPath: root.appendingPathComponent(n).path))?[.size] as? NSNumber
            else { return -1 }
            return size.int64Value
        }
        let mib: Int64 = 1 << 20

        // 1. Start, stop at >= 16 MiB.
        let p1 = LivePhases()
        downloaders[0].start(build, downloadsDir: downloads, sources: sources, onPhase: p1.handler)
        let big = await p1.wait(seconds: 120) { if case .downloading(let w, _) = $0 { return w >= 16 * mib }; return false }
        _ = try #require(big, "16 MiB arrived within 120 s: \(p1.all.suffix(3))")
        downloaders[0].cancel()
        let first = await p1.wait(seconds: 15) { if case .paused = $0 { return true }; return false }
        guard case .paused(let w1, let total, let why1)? = first else {
            Issue.record("first stop did not pause: \(p1.all.suffix(3))"); return
        }
        #expect(why1 == nil && w1 >= 16 * mib)
        let r1 = try #require(record())
        #expect(partLength() == w1 && r1.checkpoint == w1, ".part length == checkpoint == w1")
        let validator = try #require(r1.validator, "the first response carried an ETag or Last-Modified")
        #expect(r1.stoppedAt != nil && total == r1.size)

        // What the CDN says to the request a resume sends (headers only, then cancelled).
        let ranged = try #require(await StatusProbe.answer(IPSWDownloader.transferRequest(r1.url, from: w1, validator: validator)))

        // 2. A new downloader stands in for a relaunch.
        let p2 = LivePhases()
        let restored = downloaders[1].restore(knownIdentifiers: [identifier], onPhase: p2.handler)
        #expect(restored?.id == r1.id && p2.all.isEmpty)
        downloaders[1].resume(downloadsDir: downloads)
        let enough = await p2.wait(seconds: 120) { if case .downloading(let w, _) = $0 { return w >= w1 + 16 * mib }; return false }
        _ = try #require(enough, "16 MiB more arrived after the resume: \(p2.all.suffix(3))")
        #expect(p2.all.first(where: { if case .downloading = $0 { return true }; return false }) == .downloading(written: w1, total: total),
                "the first .downloading of the resume starts at w1")
        downloaders[1].cancel()
        let second = await p2.wait(seconds: 15) { if case .paused = $0 { return true }; return false }
        guard case .paused(let w2, _, _)? = second else { Issue.record("second stop did not pause: \(p2.all.suffix(3))"); return }
        #expect(w2 >= w1 + 16 * mib)
        let r2 = try #require(record())
        #expect(partLength() == w2 && r2.checkpoint == w2)

        // 3. A wrong validator: the CDN must not honour the range, the downloader must refuse.
        var bogus = r2
        bogus.validator = "\"bogus\""
        try IPSWPartialStore.write(bogus, root: root)
        let refused = try #require(await StatusProbe.answer(IPSWDownloader.transferRequest(r2.url, from: w2, validator: "\"bogus\"")))
        let p3 = LivePhases()
        #expect(downloaders[2].restore(knownIdentifiers: [identifier], onPhase: p3.handler) != nil)
        downloaders[2].resume(downloadsDir: downloads)
        let end = await p3.wait(seconds: 30) { $0.isTerminal }
        #expect(end == .failed(.resumeRejected), "bogus If-Range ends in resumeRejected: \(p3.all.suffix(3))")
        #expect(names().isEmpty, "the temp root is empty after the rejection")

        let kind = (validator.hasPrefix("\"") || validator.hasPrefix("W/")) ? "ETag" : "Last-Modified"
        print("ipsw canary: resume probe: paused at \(w1), validator \(kind): \(validator), resumed with "
              + "\(ranged.status) \(ranged.contentRange ?? "no Content-Range"), second pause \(w2), "
              + "bogus If-Range -> server \(refused.status), client rejected")
    }

    private func ms(since t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }
}

/// Collects the phases the downloader delivers on the main actor.
@MainActor
private final class LivePhases {
    var all: [IPSWDownloadPhase] = []
    var handler: IPSWDownloader.PhaseHandler { { [self] p in all.append(p) } }

    func wait(seconds: Double, _ match: (IPSWDownloadPhase) -> Bool) async -> IPSWDownloadPhase? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let p = all.first(where: match) { return p }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return all.first(where: match)
    }
}

/// Sends one request, reports the status and `Content-Range` of the first response, then cancels
/// (so a 200 for a 12 GB file costs nothing). Redirects follow `RedirectGuard`.
private final class StatusProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Answer { var status: Int; var contentRange: String? }
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Answer?, Never>?

    static func answer(_ request: URLRequest) async -> Answer? {
        let probe = StatusProbe()
        let session = URLSession(configuration: .ephemeral, delegate: probe, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return await withCheckedContinuation { c in
            probe.lock.lock(); probe.continuation = c; probe.lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    private func finish(_ a: Answer?) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: a)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        if let from = task.originalRequest?.url, let to = request.url, RedirectGuard.allows(from: from, to: to) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        finish(http.map { Answer(status: $0.statusCode, contentRange: $0.value(forHTTPHeaderField: "Content-Range")) })
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(nil)
    }

    /// The confirm step's volume figures against `df` (read-only, no network, nothing written to ~/Downloads).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1")) @MainActor
    func liveCanaryIPSWSpace() throws {
        let downloads = try #require(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        let info = IPSWDownloader.volumeInfo(downloads)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/df")
        process.arguments = ["-k", downloads.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let fields = try #require(output.split(separator: "\n").dropFirst().first).split(separator: " ", omittingEmptySubsequences: true)
        let dfSize = try #require(Int64(fields[1])), dfAvail = try #require(Int64(fields[3]))

        let available = try #require(info.available), total = try #require(info.total)
        let lowPercent = AppSettings.shared.lowSpacePercent
        let level = IPSWData.lowSpaceAfter(size: 9_400_000_000, available: available, total: total, lowPercent: lowPercent)
        print("downloads=\(downloads.path) available=\(available) total=\(total) df_size=\(dfSize) df_avail=\(dfAvail) "
              + "lowSpacePercent=\(lowPercent) lowSpaceAfter(9.4 GB)=\(level.map { "\($0)" } ?? "ok")")

        let dfTotal = Double(dfSize) * 1024
        #expect(abs(Double(total) - dfTotal) <= dfTotal * 0.02, "total within 2 % of df")
        #expect(available >= dfAvail * 1024 - 2_000_000_000, "important-usage capacity is never meaningfully below df")
        #expect(available <= total)
    }
}
