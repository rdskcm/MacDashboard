// Tests/MoonportTests/IPhoneLoadLiveCanaryTests.swift
// IPHONE-LOAD-SPEED R13 opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanaryIPhoneLoad
// Runs the changed transport code against the attached phone and prints what it read. Reads only:
// no stores, no file writes. Never prints serials, IMEIs, part ids or the UDID.
import Foundation
import Testing
@testable import Moonport

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
        /// One box for the whole suite: `MobileDeviceTransport.start` keeps only the first handler, so a box
        /// made by a later test would never receive the attach event.
        @MainActor static let liveBox = IPhoneLoadLiveBox()

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
        static func runListing(_ h: IPhoneHandle, known: [String: IPhoneLogHeader], box: IPhoneLoadLiveBox)
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
            let box = Self.liveBox
            transport.start { event in
                if case .attached(let h, _) = event, box.handle == nil { box.handle = h }
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
            // IPHONE-CRASHLOG-ACTIONS: the parser on this phone. Process names and counts only, no identifier.
            let withProcess = cold.settled.filter { $0.process != nil }.count
            let fromHeader = cold.settled.filter { e in
                guard let c = e.created else { return false }
                let name = (e.path as NSString).lastPathComponent
                return c != IPhoneCrashLog.fileNameTimestamp(name) && c != e.modified
            }.count
            let appCrash = cold.settled.filter { $0.category == .appCrash }.count
            print("liveCanary headers process=\(withProcess) timestamp=\(fromHeader) appCrash=\(appCrash)")
            #expect(cold.settled.filter { $0.category == .appCrash || $0.category == .exceptionFault }.allSatisfy { $0.process != nil })
            #expect(cold.settled.allSatisfy { $0.created != nil })

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
            transport.readIdentity(h, language: .en) { box.identity = $0 }
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

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        @MainActor
        func liveCanaryCrashLogCopy() async throws {
            let transport = MobileDeviceTransport.shared
            let box = Self.liveBox
            transport.start { event in
                if case .attached(let h, _) = event, box.handle == nil { box.handle = h }
            }
            guard await Self.wait(10, until: { box.handle != nil }), let h = box.handle else {
                Issue.record("attach an unlocked, trusted iPhone over USB")
                return
            }
            guard let cold = await Self.runListing(h, known: [:], box: box) else { return }
            guard let entry = cold.settled.filter({ $0.path.hasSuffix(".ips") && $0.size > 0 }).min(by: { $0.size < $1.size }) else {
                Issue.record("no .ips file on the phone")
                return
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-crashlog-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let dest = dir.appendingPathComponent((entry.path as NSString).lastPathComponent)
            var ok: Bool?
            var progressCalls = 0
            let t0 = ContinuousClock.now
            transport.copyFile(h, remotePath: entry.path, size: entry.size, to: dest,
                               progress: { _ in progressCalls += 1 }, completion: { ok = $0 })
            let finished = await Self.wait(30, until: { ok != nil })
            print("liveCanary copy bytes=\(entry.size) ms=\(Self.ms(t0)) progressCalls=\(progressCalls)")
            #expect(finished && ok == true)
            #expect(IPhoneCrashLog.fileSize(dest) == entry.size)
            let head = try Data(contentsOf: dest).prefix(4096)
            #expect(IPhoneCrashLog.logHeader(fromHeader: Data(head)).bugType == entry.bugType)

            let tmp = FileManager.default.temporaryDirectory
            let free = IPhoneCrashLog.availableBytes(at: tmp)
            let total = (try? tmp.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity.map { Int64($0) }
            print("liveCanary free=\(free.map(String.init) ?? "nil")")
            #expect(free != nil && total != nil && free! > 0 && free! < total!)
        }

        /// BATTERY-HEALTH-UNIFY fix wave 1: MACDASH_LIVE=1 swift test --filter liveCanaryIPhoneHealth (a phone attached).
        /// Prints the reply's capacities and the rule-P1 estimate. Reads only; no stores, no identifiers.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        @MainActor
        func liveCanaryIPhoneHealth() async {
            let transport = MobileDeviceTransport.shared
            let box = Self.liveBox
            transport.start { event in
                if case .attached(let h, _) = event, box.handle == nil { box.handle = h }
            }
            guard await Self.wait(10, until: { box.handle != nil }), let h = box.handle else {
                Issue.record("attach an unlocked, trusted iPhone over USB")
                return
            }
            var read: Result<IPhoneSnapshot, IPhoneReadError>?
            transport.readSnapshot(h, includeBattery: true) { read = $0 }
            guard await Self.wait(30, until: { read != nil }), case .success(let snap)? = read, let b = snap.battery else {
                Issue.record("battery snapshot failed: \(String(describing: read))")
                return
            }
            let estimate = IPhoneData.estimatedHealthPercent(b)
            print("liveCanary iphone productType=\(snap.productType ?? "nil") os=\(snap.osVersion ?? "nil") nominalChargeMAh=\(String(describing: b.nominalChargeMAh)) designCapacityMAh=\(String(describing: b.designCapacityMAh)) maxCapacityMAh=\(String(describing: b.maxCapacityMAh))")
            print("liveCanary iphone estimate=\(String(describing: estimate)) rawRatio=\(String(describing: IPhoneData.preciseLiveHealth(b))) healthPercent=\(String(describing: b.healthPercent))")
            guard let nom = b.nominalChargeMAh, let design = b.designCapacityMAh, design > 0, let e = estimate else {
                Issue.record("the reply carries no NominalChargeCapacity + DesignCapacity")
                return
            }
            #expect(e == min(100, (nom * 100 + design - 1) / design), "estimate = ceil(Nominal / Design) in integer arithmetic")
            #expect(nom <= design + design / 10, "nominal capacity is at most 10 % above design")
            if let raw = IPhoneData.preciseLiveHealth(b) {
                #expect(abs(Double(e) - raw) <= 5, "the estimate is within 5 points of the raw ratio from the same reply")
            }
        }

        /// IPHONE-LIVE-BATTERY: MACDASH_LIVE=1 swift test --filter liveCanaryIPhoneLiveBattery (a phone attached).
        /// Reads only; no stores, no identifiers.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        @MainActor
        func liveCanaryIPhoneLiveBattery() async {
            let transport = MobileDeviceTransport.shared
            let box = Self.liveBox
            transport.start { event in
                if case .attached(let h, _) = event, box.handle == nil { box.handle = h }
            }
            guard await Self.wait(10, until: { box.handle != nil }), let h = box.handle else {
                Issue.record("attach an unlocked, trusted iPhone over USB")
                return
            }
            var snapRead: Result<IPhoneSnapshot, IPhoneReadError>?
            transport.readSnapshot(h, includeBattery: true) { snapRead = $0 }
            guard await Self.wait(30, until: { snapRead != nil }), case .success(let snap)? = snapRead, let ref = snap.battery else {
                Issue.record("reference snapshot failed: \(String(describing: snapRead))"); return
            }
            var times: [Int] = []
            for i in 0..<3 {
                if i > 0 { try? await Task.sleep(for: .seconds(2)) }
                var read: Result<BatteryDetail?, IPhoneReadError>?
                let t0 = ContinuousClock.now
                transport.readBattery(h) { read = $0 }
                guard await Self.wait(30, until: { read != nil }), case .success(let b?)? = read else {
                    Issue.record("live battery read \(i) failed: \(String(describing: read))"); return
                }
                let ms = Self.ms(t0)
                times.append(ms)
                print("liveCanary liveBattery i=\(i) ms=\(ms) percent=\(String(describing: b.percent)) charging=\(b.isCharging) external=\(b.externalConnected) mV=\(String(describing: b.voltageMV)) tempC=\(String(describing: b.temperatureC)) cycles=\(String(describing: b.cycleCount)) design=\(String(describing: b.designCapacityMAh))")
                #expect(b.percent.map { (0...100).contains($0) } == true, "charge is a percentage")
                #expect(abs((b.percent ?? -99) - (ref.percent ?? 99)) <= 2, "charge within 2 points of the snapshot read seconds earlier")
                #expect(b.cycleCount == ref.cycleCount, "cycle count equals the snapshot's")
                #expect(b.designCapacityMAh == ref.designCapacityMAh, "design capacity equals the snapshot's")
                #expect(b.voltageMV.map { (3000...4600).contains($0) } == true, "Li-ion cell voltage range")
                #expect(b.temperatureC.map { $0 > 0 && $0 < 60 } == true, "battery temperature 0-60 °C")
                #expect(!b.isCharging || b.externalConnected, "charging implies external power")
            }
            print("liveCanary liveBattery msSorted=\(times.sorted())")
            #expect(times.allSatisfy { $0 < 2000 }, "a lone battery read takes well under 2 s (measured 105-230 ms, findings C2)")
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        @MainActor
        func liveCanarySysdiagnoseDir() async {
            let transport = MobileDeviceTransport.shared
            let box = Self.liveBox
            transport.start { event in
                if case .attached(let h, _) = event, box.handle == nil { box.handle = h }
            }
            guard await Self.wait(10, until: { box.handle != nil }), let h = box.handle else {
                Issue.record("attach an unlocked, trusted iPhone over USB")
                return
            }
            var listed: Result<[IPhoneAFCEntry], IPhoneReadError>?
            let t0 = ContinuousClock.now
            transport.listSysdiagnoseDir(h) { listed = $0 }
            guard await Self.wait(30, until: { listed != nil }), case .success(let entries)? = listed else {
                Issue.record("sysdiagnose listing failed: \(String(describing: listed))")
                return
            }
            let ms = Self.ms(t0)
            let names = entries.map { ($0.path as NSString).lastPathComponent }
            let inProgress = names.filter { $0.hasPrefix(SysdiagnoseDir.inProgressPrefix) }.count
            let parsable = names.filter { $0.hasSuffix(".tar.gz") && SysdiagnoseDir.startDate(ofArchive: $0) != nil }.count
            print("liveCanary sysdiagnoseDir entries=\(entries.count) inProgress=\(inProgress) parsableNames=\(parsable) ms=\(ms)")
            for e in entries {
                #expect(e.path.hasPrefix(SysdiagnoseDir.path + "/") && !e.path.dropFirst(SysdiagnoseDir.path.count + 1).contains("/"))
                let n = (e.path as NSString).lastPathComponent
                if n.hasSuffix(".tar.gz"), !n.hasPrefix(SysdiagnoseDir.inProgressPrefix) {
                    #expect(SysdiagnoseDir.startDate(ofArchive: n) != nil, "unparsable archive name")
                }
            }
            #expect(!IPhoneData.sysdiagnoseArchives(in: entries).contains {
                ($0.path as NSString).lastPathComponent.hasPrefix(SysdiagnoseDir.inProgressPrefix)
            })

            // The file does not exist, so the session and `info` path run and the remove itself is never reached.
            var outcome: PhoneCleanup?
            transport.removeOwnArchive(h, path: SysdiagnoseDir.remotePath("sysdiagnose_2000.01.01_00-00-00+0000_canary.tar.gz"),
                                       expectedSize: 1) { outcome = $0 }
            let done = await Self.wait(30, until: { outcome != nil })
            print("liveCanary removeProbe=\(outcome.map { String(describing: $0) } ?? "nil")")
            #expect(done && outcome == .alreadyGone)
        }
    }
}
