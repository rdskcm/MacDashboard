// Tests/MacDashboardTests/IPhoneLoadSpeedTests.swift
// IPHONE-LOAD-SPEED Stage 1: job queue, type split/merge, saved type cache, storage state.
// Temp files only (temporaryDirectory/<UUID>); never touches ~/Library/Application Support/MacDashboard.
import Foundation
import Testing
@testable import MacDashboard

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

extension SerialTests {
    struct IPhoneLoadSpeedTests {
        private func file(_ path: String, dir: Bool = false, size: Int64 = 10, at: TimeInterval? = nil) -> IPhoneAFCEntry {
            IPhoneAFCEntry(path: path, isDirectory: dir, size: size, modified: at.map { Date(timeIntervalSince1970: $0) })
        }
        private func key(_ f: IPhoneAFCEntry) -> String {
            IPhoneData.logCacheKey(path: f.path, size: f.size, modified: f.modified)
        }

        @Test func queueOrder() {
            var q = IPhoneJobQueue<String>()
            let a = q.push(.user, "A")
            _ = q.push(.interactive, "B")
            _ = q.push(.last, "C")
            _ = q.push(.background, "D")
            _ = q.push(.interactive, "E")
            #expect(q.hasPending(moreUrgentThan: .background))
            var rem = q
            rem.remove(seq: a)
            #expect(rem.count == 4)
            var order: [String] = []
            while let j = q.pop() {
                order.append(j)
                if j == "A" { #expect(!q.hasPending(moreUrgentThan: .background)) }
            }
            #expect(order == ["B", "E", "A", "D", "C"])
            var rest: [String] = []
            while let j = rem.pop() { rest.append(j) }
            #expect(rest == ["B", "E", "D", "C"])
        }

        @Test func stalledStorageHoldsNothingElse() {
            let t = ParkedRunLoopThread(name: "test.iphone-jobs")
            let r = IPhoneJobRunner()
            let post: (@escaping () -> Void) -> Bool = { t.async($0) }
            let log = Log()
            let g = DispatchSemaphore(value: 0), s = DispatchSemaphore(value: 0)
            let started = DispatchSemaphore(value: 0)
            let idDone = DispatchSemaphore(value: 0), walkDone = DispatchSemaphore(value: 0)
            let fillDone = DispatchSemaphore(value: 0), stDone = DispatchSemaphore(value: 0)
            let t0 = Date()
            r.enqueue(.interactive, { started.signal(); _ = g.wait(timeout: .now() + 5) }, post: post)
            #expect(started.wait(timeout: .now() + 2) == .success)
            r.enqueue(.last, { _ = s.wait(timeout: .now() + 25); log.add("storage"); stDone.signal() }, post: post)
            r.enqueue(.interactive, { log.add("identity"); idDone.signal() }, post: post)
            r.enqueue(.user, { log.add("walk"); walkDone.signal() }, post: post)
            r.enqueue(.background, { log.add("fill"); fillDone.signal() }, post: post)
            g.signal()
            #expect(idDone.wait(timeout: .now() + 2) == .success)
            #expect(walkDone.wait(timeout: .now() + 2) == .success)
            #expect(fillDone.wait(timeout: .now() + 2) == .success)
            #expect(log.all == ["identity", "walk", "fill"])
            s.signal()
            #expect(stDone.wait(timeout: .now() + 2) == .success)
            #expect(log.all == ["identity", "walk", "fill", "storage"])
            #expect(Date().timeIntervalSince(t0) < 3)
        }

        @Test func typeLoopYields() {
            let t = ParkedRunLoopThread(name: "test.iphone-yield")
            let r = IPhoneJobRunner()
            let post: (@escaping () -> Void) -> Bool = { t.async($0) }
            let log = Log()
            let done = DispatchSemaphore(value: 0)
            r.enqueue(.user, {
                var stopped = 0
                for i in 0..<50 {
                    if i == 5 { r.enqueue(.interactive, { log.add("interactive"); done.signal() }, post: post) }
                    if r.hasPending(moreUrgentThan: .background) { stopped = i; break }
                    Thread.sleep(forTimeInterval: 0.001)
                    stopped = i + 1
                }
                log.add("stopped\(stopped)")
            }, post: post)
            #expect(done.wait(timeout: .now() + 3) == .success)
            let all = log.all
            #expect(all.count == 2 && all[1] == "interactive")
            #expect(all.first == "stopped5" || all.first == "stopped6")
        }

        @Test func split() {
            let f1 = file("/a", at: 100), f2 = file("/b", at: 300), f3 = file("/c"), f4 = file("/d", at: 200)
            let known = [key(f1): "309", key(f3): "", "/gone|1|0": "298"]
            let (listing, pending) = IPhoneLogTypes.split([file("/dir1", dir: true), f1, f2, file("/dir2", dir: true), f3, f4], known: known)
            #expect(listing.entries.map(\.path) == ["/a", "/b", "/c", "/d"])
            #expect(listing.entries.filter { $0.category == .pending }.count == 2)
            #expect(listing.entries[0].category == .appCrash && listing.entries[0].bugType == "309")
            #expect(listing.entries[2].category == .other && listing.entries[2].bugType == nil)
            #expect(Set(listing.known.keys) == [key(f1), key(f3)])
            #expect(listing.entries.allSatisfy { $0.source == .live })
            #expect(pending.map(\.path) == ["/b", "/d"])
            let (_, p2) = IPhoneLogTypes.split([file("/x"), file("/y", at: 5), file("/w", at: 9)], known: [:])
            #expect(p2.map(\.path) == ["/w", "/y", "/x"])
        }

        @Test func merge() {
            let a = file("/a", at: 1), b = file("/b", at: 2), c = file("/c", at: 3), d = file("/d", at: 4)
            let (listing, _) = IPhoneLogTypes.split([a, b, c, d], known: [:])
            var entries = listing.entries
            entries[3].category = .jetsam   // not pending, key present in the batch
            let batch = IPhoneLogTypeBatch(read: [key(a): "309", key(b): "", key(d): "309"], failed: [key(c)])
            let m = IPhoneLogTypes.merge(entries, batch)
            #expect(m[0].category == .appCrash && m[0].bugType == "309")
            #expect(m[1].category == .other && m[1].bugType == nil)
            #expect(m[2].category == .other && m[2].bugType == nil)
            #expect(m[3] == entries[3])
        }

        @Test func updatedCache() {
            let a = file("/a"), z = file("/z")
            let (listing, _) = IPhoneLogTypes.split([a], known: [:])
            let batch = IPhoneLogTypeBatch(read: [key(a): "309", key(z): "298"], failed: [])
            let c = IPhoneLogTypes.updatedCache(["old|1|1": "x"], entries: listing.entries, batch: batch)
            #expect(c == ["old|1|1": "x", key(a): "309"])
        }

        @Test func store() throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("sub").appendingPathComponent(IPhoneLogTypeStore.fileName)
            let store = IPhoneLogTypeStore(url: url)
            let cache = ["d1": ["/a|1|2": "309", "/b|3|4": ""], "d2": ["/c|5|6": "298"]]
            try store.save(cache)
            #expect(store.load(keeping: ["d1", "d2"]) == cache)
            func perms(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions]) as? Int) ?? -1 }
            #expect(perms(url) == 0o600)
            #expect(perms(url.deletingLastPathComponent()) == 0o700)
            #expect(store.load(keeping: ["d1"]) == ["d1": cache["d1"]!])
            try Data(#"{"version":2,"devices":{"d1":{"a":"b"}}}"#.utf8).write(to: url)
            #expect(store.load(keeping: ["d1"]).isEmpty)
            try Data([0xff, 0x00, 0x13, 0x37]).write(to: url)
            #expect(store.load(keeping: ["d1"]).isEmpty)
            try store.save(cache)
            #expect(store.load(keeping: ["d1", "d2"]) == cache)
        }

        @Test func storageRead() {
            #expect(IPhoneStorageRead.waiting.afterDeadline() == .missing)
            #expect(IPhoneStorageRead.value("x").afterDeadline() == .value("x"))
            #expect(IPhoneStorageRead.missing.afterDeadline() == .missing)
            #expect(IPhoneStorageRead.result(bytes: 256_000_000_000) == .value(fmtCapacity(256_000_000_000)))
            #expect(IPhoneStorageRead.result(bytes: nil) == .missing)
            #expect(IPhoneStorageRead.result(bytes: 0) == .missing)
            #expect(IPhoneStorageRead.deadlineSeconds == 2.0)
        }

        @Test func identityRows() {
            func f(_ l: IdentityLabel, _ v: String) -> IPhoneIdentityField {
                IPhoneIdentityField(id: l.rawValue, label: l, value: v, isSecret: l.isSecret)
            }
            let base = [f(.marketingName, "iPhone"), f(.ios, "18 (x)"), f(.colorCode, "1")]
            #expect(IPhoneData.identityRows(base, storage: nil) == base)
            let w = IPhoneData.identityRows(base, storage: .waiting)
            #expect(w.map(\.label) == [.marketingName, .ios, .storage, .colorCode])
            #expect(w[2].isPending && w[2].value == "…")
            let withStorage = [f(.ios, "18"), f(.storage, "old"), f(.colorCode, "1")]
            let v = IPhoneData.identityRows(withStorage, storage: .value("256 GB"))
            #expect(v.map(\.value) == ["18", "256 GB", "1"] && !v[1].isPending)
            #expect(IPhoneData.identityRows(withStorage, storage: .missing).map(\.label) == [.ios, .colorCode])
        }

        @Test func inFlightIsCurrent() {
            var r = InFlightReads<Int>()
            let id = r.begin("k", handle: 1)!
            #expect(r.isCurrent("k", id: id))
            let id2 = r.begin("k", handle: 2)!
            #expect(!r.isCurrent("k", id: id))
            #expect(r.isCurrent("k", id: id2))
            let fin = r.finish("k", id: id2)
            #expect(fin)
            #expect(!r.isCurrent("k", id: id2))
        }
    }
}
