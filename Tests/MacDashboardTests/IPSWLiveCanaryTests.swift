// Tests/MacDashboardTests/IPSWLiveCanaryTests.swift
// IPHONE-IPSW opt-in live canary: the only test that touches the network, and only when asked.
//   MACDASH_LIVE=1 swift test --filter ipswLiveCanary
// Skipped in CI and by default. For iPhone18,2 it checks that the live catalogue and ipsw.me
// still have the shapes the fixtures record, that both agree on Apple's build, and that a HEAD
// on Apple's URL answers 200 with ipsw.me's size, every redirect hop on the allowlist. It never
// downloads a firmware body and writes nothing.
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
    }

    private func ms(since t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }
}
