// Tests/MacDashboardTests/IPhoneLoadLiveCanaryTests.swift
// IPHONE-LOAD-SPEED R13 opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanaryIPhoneLoad
// Runs the changed transport code against the attached phone and prints what it read. Reads only:
// no stores, no file writes. Never prints serials, IMEIs, part ids or the UDID.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    @MainActor
    final class IPhoneLoadLiveBox {
        var handle: IPhoneHandle?
        var snapshot: Result<IPhoneSnapshot, IPhoneReadError>?
        var listing: Result<IPhoneLogListing, IPhoneReadError>?
        var batches: [IPhoneLogTypeBatch] = []
        var identity: Result<[IPhoneIdentityField], IPhoneReadError>?
        var storage: Result<Int64?, IPhoneReadError>?
    }

    struct IPhoneLoadLiveCanaryTests {
        /// Polls `done` every 20 ms; false after `seconds`.
        @MainActor
        static func wait(_ seconds: Double, until done: () -> Bool) async -> Bool {
            let t0 = ContinuousClock.now
            while !done() {
                if ContinuousClock.now - t0 > .seconds(seconds) { return false }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return true
        }

        static func ms(_ since: ContinuousClock.Instant) -> Int {
            let d = ContinuousClock.now - since
            return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
        }

        static func key(_ e: IPhoneLogEntry) -> String {
            IPhoneData.logCacheKey(path: e.path, size: e.size, modified: e.modified)
        }

        /// Runs one listing to the end: the listing, then batches until no entry is `.pending`.
        @MainActor
        static func runListing(_ h: IPhoneHandle, known: [String: String], box: IPhoneLoadLiveBox)
            async -> (initial: [IPhoneLogEntry], settled: [IPhoneLogEntry], batch: IPhoneLogTypeBatch, listMs: Int, typesMs: Int)? {
            box.listing = nil
            box.batches = []
            let t0 = ContinuousClock.now
            MobileDeviceTransport.shared.listLogs(h, knownHeaders: known, onListing: { box.listing = $0 },
                                                  onTypes: { box.batches.append($0) })
            guard await wait(30, until: { box.listing != nil }), case .success(let listing)? = box.listing else {
                Issue.record("listing did not arrive or failed: \(String(describing: box.listing))")
                return nil
            }
            let listMs = ms(t0)
            var entries = listing.entries
            var total = IPhoneLogTypeBatch()
            var applied = 0
            func absorb() {
                while applied < box.batches.count {
                    let b = box.batches[applied]
                    applied += 1
                    entries = IPhoneLogTypes.merge(entries, b)
                    total.read.merge(b.read) { $1 }
                    total.failed.formUnion(b.failed)
                }
            }
            let settledOK = await wait(30) { absorb(); return !entries.contains { $0.category == .pending } }
            absorb()
            #expect(settledOK, "entries still pending after 30 s")
            return (listing.entries, entries, total, listMs, ms(t0))
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        @MainActor
        func liveCanaryIPhoneLoad() async {
            let transport = MobileDeviceTransport.shared
            let box = IPhoneLoadLiveBox()
            transport.start { event in
                if case .attached(let h) = event, box.handle == nil { box.handle = h }
            }
            guard await Self.wait(10, until: { box.handle != nil }), let h = box.handle else {
                Issue.record("attach an unlocked, trusted iPhone over USB")
                return
            }

            // 1. snapshot
            transport.readSnapshot(h, includeBattery: false) { box.snapshot = $0 }
            guard await Self.wait(30, until: { box.snapshot != nil }), case .success(let snap)? = box.snapshot else {
                Issue.record("snapshot failed: \(String(describing: box.snapshot))")
                return
            }
            print("liveCanary snapshot os=\(snap.osVersion ?? "nil")")

            // 2. cold listing
            guard let cold = await Self.runListing(h, known: [:], box: box) else { return }
            let p = cold.initial.filter { $0.category == .pending }.count
            print("liveCanary listing entries=\(cold.initial.count) pending=\(p) ms=\(cold.listMs)")
            print("liveCanary types read=\(cold.batch.read.count) failed=\(cold.batch.failed.count) ms=\(cold.typesMs)")
            #expect(p == cold.initial.count, "empty cache: every file must be pending")
            #expect(!cold.settled.contains { $0.category == .pending })

            // 3. warm listing with the cache built from the cold one
            let cache = IPhoneLogTypes.updatedCache([:], entries: cold.settled, batch: cold.batch)
            guard let warm = await Self.runListing(h, known: cache, box: box) else { return }
            let p2 = warm.initial.filter { $0.category == .pending }.count
            print("liveCanary warm entries=\(warm.initial.count) pending=\(p2)")
            let unknown = warm.initial.filter { cache[Self.key($0)] == nil }.count
            #expect(p2 == unknown)
            let coldCategory = Dictionary(cold.settled.map { (Self.key($0), $0.category) }, uniquingKeysWith: { a, _ in a })
            for e in warm.initial where e.category != .pending {
                if let c = coldCategory[Self.key(e)] { #expect(e.category == c, "category differs between cold and warm listing") }
            }

            // 4. identity
            transport.readIdentity(h) { box.identity = $0 }
            guard await Self.wait(30, until: { box.identity != nil }), case .success(let fields)? = box.identity else {
                Issue.record("identity failed: \(String(describing: box.identity))")
                return
            }
            print("liveCanary identity fields=\(fields.count)")
            #expect(!fields.contains { $0.label == .storage }, "identity must not read storage any more")
            if let os = snap.osVersion, let ios = fields.first(where: { $0.label == .ios }) {
                #expect(ios.value.hasPrefix(os))
            } else {
                Issue.record("no .ios field or snapshot osVersion")
            }

            // 5. storage
            let t0 = ContinuousClock.now
            transport.readStorage(h, onStart: {}, completion: { box.storage = $0 })
            guard await Self.wait(30, until: { box.storage != nil }), case .success(let bytes)? = box.storage else {
                Issue.record("storage failed: \(String(describing: box.storage))")
                return
            }
            print("liveCanary storage bytes=\(bytes.map(String.init) ?? "nil") ms=\(Self.ms(t0))")
            if let b = bytes {
                let near = (0...5).contains { k in
                    let ref = 64e9 * pow(2.0, Double(k))
                    return abs(Double(b) - ref) / ref <= 0.02
                }
                #expect(near, "capacity is not within 2 % of 64e9*2^k")
            } else {
                Issue.record("no TotalDiskCapacity")
            }
        }
    }
}
