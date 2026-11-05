// Tests/MacDashboardTests/IPhoneUnlinkTests.swift
// IPHONE-UNLINK Stage A: the unlink operation, the busy gate, the ignore set, the key check and the strings.
// Temp paths and an injected trash closure only: neither the real Trash nor App Support is touched.
import Foundation
import Testing
@testable import MacDashboard

@Suite struct IPhoneUnlinkTests {
    private struct Boom: Error {}
    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func add(_ n: String) { lock.lock(); list.append(n); lock.unlock() }
        var names: [String] { lock.lock(); defer { lock.unlock() }; return list }
    }
    private let k = "0123456789abcdef"
    private let o = "fedcba9876543210"

    private func record(_ id: String, name: String, kept: [String]) -> IPhoneDeviceRecord {
        IPhoneDeviceRecord(id: id, name: name, lastSeen: Date(), battery: [], keptArchives: kept)
    }

    /// Two records (`k` keeps a.tar.gz and b.tar.gz, `o` none), both files on disk, a log-type cache for both.
    @MainActor
    private func makeModel(kept: [String] = ["a.tar.gz", "b.tar.gz"], files: [String] = ["a.tar.gz", "b.tar.gz"],
                           storeURL: URL? = nil) throws -> (IPhoneModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-unlink-\(UUID().uuidString)")
        let folder = dir.appendingPathComponent("archive").appendingPathComponent(k)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("archive"), withIntermediateDirectories: true)
        if !files.isEmpty {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for f in files { FileManager.default.createFile(atPath: folder.appendingPathComponent(f).path, contents: Data("x".utf8)) }
        }
        let url = storeURL ?? dir.appendingPathComponent("iphones.json")
        let typeStore = IPhoneLogTypeStore(url: dir.appendingPathComponent(IPhoneLogTypeStore.fileName))
        let devices = [record(k, name: "Kay", kept: kept), record(o, name: "Oh", kept: [])]
        if storeURL == nil { try IPhoneStore(url: url).save(devices) }
        try typeStore.save([k: [:], o: [:]])
        let m = IPhoneModel(store: IPhoneStore(url: url), archiveRoot: dir.appendingPathComponent("archive"),
                            logTypeStore: typeStore)
        m.devices = devices
        m.headerCache = [k: [:], o: [:]]
        return (m, dir)
    }

    private func fakeTrash(_ dir: URL, failing: Set<String> = []) -> @Sendable (URL) throws -> Void {
        { url in
            if failing.contains(url.lastPathComponent) { throw Boom() }
            let t = dir.appendingPathComponent("trash")
            try FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: t.appendingPathComponent(url.lastPathComponent))
        }
    }

    private func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }
    private func entry() -> IPhoneLogEntry {
        IPhoneLogEntry(path: "/x/y.ips", size: 1, modified: nil, bugType: nil, category: .pending, source: .live)
    }

    @Test @MainActor func unlinkSkipsNamesThatAreNotPlainFileNames() async throws {
        let bad = ["../../outside", "a/b", "", "..", "good.tar.gz"]
        let (m, dir) = try makeModel(kept: bad, files: ["good.tar.gz"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let outside = dir.appendingPathComponent("outside")   // where archive/<key>/../../outside points
        FileManager.default.createFile(atPath: outside.path, contents: Data("x".utf8))
        let seen = Seen()
        let inner = fakeTrash(dir)
        await m.unlink(deviceKey: k, trash: { url in seen.add(url.lastPathComponent); try inner(url) })
        #expect(seen.names == ["good.tar.gz"])
        #expect(exists(outside))
        #expect(m.unlinkNotice == nil)
    }

    @Test @MainActor func rememberedPhoneIsRemovedEverywhere() async throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.status[k] = .remembered
        await m.unlink(deviceKey: k, trash: fakeTrash(dir))
        #expect(IPhoneStore(url: dir.appendingPathComponent("iphones.json")).load().map(\.id) == [o])
        #expect(m.devices.map(\.id) == [o])
        #expect(m.status[k] == nil && m.lastSnapshot[k] == nil && m.logs[k] == nil && m.identity[k] == nil)
        #expect(exists(dir.appendingPathComponent("trash/a.tar.gz")) && exists(dir.appendingPathComponent("trash/b.tar.gz")))
        #expect(!exists(dir.appendingPathComponent("archive/\(k)")))
        #expect(exists(dir.appendingPathComponent("archive")))
        #expect(m.unlinkNotice == nil)
        let types = IPhoneLogTypeStore(url: dir.appendingPathComponent(IPhoneLogTypeStore.fileName)).load(keeping: [k, o])
        #expect(types[k] == nil)
    }

    @Test @MainActor func selectionClearsOnlyForTheUnlinkedPhone() async throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.selectedDeviceKey = k
        await m.unlink(deviceKey: k, trash: fakeTrash(dir))
        #expect(m.selectedDeviceKey == nil)
        let (m2, dir2) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir2) }
        m2.selectedDeviceKey = o
        await m2.unlink(deviceKey: k, trash: fakeTrash(dir2))
        #expect(m2.selectedDeviceKey == o)
    }

    @Test @MainActor func connectedPhoneIsIgnoredUntilItDetaches() async throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = IPhoneHandle(raw: 7)
        m.connected[k] = h
        m.status[k] = .connected
        m.sysdiagnoseRequest[k] = .waiting
        m.setRequestPanelShown(deviceKey: k, true)
        #expect(m.isPolling(deviceKey: k))
        await m.unlink(deviceKey: k, trash: fakeTrash(dir))
        #expect(m.connected[k] == nil)
        #expect(m.sysdiagnoseRequest[k] == nil)
        #expect(!m.isPolling(deviceKey: k))
        #expect(m.isIgnored(h))
        m.handle(.detached(h))
        #expect(!m.isIgnored(h))
    }

    @Test @MainActor func busyStatesBlockUnlink() async throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let logKey = IPhoneModel.logActionKey(deviceKey: k, entry: entry())
        let busy: [(String, () -> Void, () -> Void)] = [
            ("importing", { m.importing[self.k] = .parsing }, { m.importing[self.k] = nil }),
            ("question", {
                m.importQuestion[self.k] = ImportIdentityQuestion(archiveName: "a", archiveMAh: [1], deviceMAh: 2,
                                                                  targetName: "Kay", ownerName: nil)
            }, { m.importQuestion[self.k] = nil }),
            ("deleting", { m.phoneCleanup[self.k] = .deleting }, { m.phoneCleanup[self.k] = .deleted }),
            ("logAction", { m.logAction[logKey] = .copying(.save, done: 0, total: 1) }, { m.logAction[logKey] = .saved }),
        ]
        for (label, set, clear) in busy {
            set()
            #expect(!m.canUnlink(k), Comment(rawValue: label))
            await m.unlink(deviceKey: k, trash: fakeTrash(dir))
            #expect(m.devices.map(\.id) == [k, o], Comment(rawValue: label))
            #expect(IPhoneStore(url: dir.appendingPathComponent("iphones.json")).load().count == 2)
            #expect(exists(dir.appendingPathComponent("archive/\(k)/a.tar.gz")))
            clear()
            #expect(m.canUnlink(k), Comment(rawValue: label))
        }
    }

    @Test @MainActor func saveFailureChangesNothing() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-unlink-blk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let blocker = base.appendingPathComponent("blocker")
        FileManager.default.createFile(atPath: blocker.path, contents: Data("x".utf8))
        let (m, dir) = try makeModel(storeURL: blocker.appendingPathComponent("iphones.json"))
        defer { try? FileManager.default.removeItem(at: dir) }
        await m.unlink(deviceKey: k, trash: fakeTrash(dir))
        #expect(m.unlinkNotice == .saveFailed(name: "Kay"))
        #expect(m.devices.map(\.id) == [k, o])
        #expect(exists(dir.appendingPathComponent("archive/\(k)/a.tar.gz")))
    }

    @Test @MainActor func trashFailureKeepsFolderAndShowsNotice() async throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("archive/\(k)")
        await m.unlink(deviceKey: k, trash: fakeTrash(dir, failing: ["a.tar.gz"]))
        #expect(m.unlinkNotice == .trashFailed(count: 1, folder: folder.path))
        #expect(IPhoneStore(url: dir.appendingPathComponent("iphones.json")).load().map(\.id) == [o])
        #expect(exists(dir.appendingPathComponent("trash/b.tar.gz")))
        #expect(exists(folder) && exists(folder.appendingPathComponent("a.tar.gz")))
    }

    @Test @MainActor func noKeptArchivesNeverCallsTrash() async throws {
        let (m, dir) = try makeModel(kept: [], files: [])
        defer { try? FileManager.default.removeItem(at: dir) }
        final class Flag: @unchecked Sendable { var called = false }
        let flag = Flag()
        await m.unlink(deviceKey: k, trash: { _ in flag.called = true })
        #expect(m.devices.map(\.id) == [o])
        #expect(!flag.called)
        #expect(m.unlinkNotice == nil)
    }

    @Test @MainActor func folderWithOtherContentStays() async throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("archive/\(k)")
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".DS_Store").path, contents: Data("x".utf8))
        await m.unlink(deviceKey: k, trash: fakeTrash(dir))
        #expect(exists(dir.appendingPathComponent("trash/a.tar.gz")) && exists(dir.appendingPathComponent("trash/b.tar.gz")))
        #expect(exists(folder.appendingPathComponent(".DS_Store")))
    }

    @Test @MainActor func missingNamedFileIsNotAFailure() async throws {
        let (m, dir) = try makeModel(kept: ["a.tar.gz", "gone.tar.gz"], files: ["a.tar.gz"])
        defer { try? FileManager.default.removeItem(at: dir) }
        await m.unlink(deviceKey: k, trash: fakeTrash(dir))
        #expect(exists(dir.appendingPathComponent("trash/a.tar.gz")))
        #expect(m.unlinkNotice == nil)
        #expect(!exists(dir.appendingPathComponent("archive/\(k)")))
    }

    @Test @MainActor func crashLogStateIsClearedPerPhone() async throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.logAction["\(k)|live|x"] = .saved
        m.logAction["\(o)|live|y"] = .saved
        await m.unlink(deviceKey: k, trash: fakeTrash(dir))
        #expect(Set(m.logAction.keys) == ["\(o)|live|y"])
    }

    @Test @MainActor func unknownAndMalformedKeysDoNothing() async throws {
        let (m, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        for bad in ["1111111111111111", "", "../x", "0123456789ABCDEF"] {
            await m.unlink(deviceKey: bad, trash: fakeTrash(dir))
            #expect(m.devices.map(\.id) == [k, o])
        }
        #expect(m.unlinkNotice == nil)
        #expect(IPhoneData.isDeviceKey(k))
        for bad in ["", "../x", "0123456789ABCDEF", "0123456789abcde", "0123456789abcdef0"] {
            #expect(!IPhoneData.isDeviceKey(bad))
        }
    }

    @Test func stringsMatchTheSpec() {
        let en = StringsEN(), ru = StringsRU()
        #expect(en.iphoneUnlinkArchives(1) == "1 kept archive moves to the Trash.")
        #expect(en.iphoneUnlinkArchives(2) == "2 kept archives move to the Trash.")
        #expect(ru.iphoneUnlinkArchives(1) == "1 сохранённый архив будет перемещён в Корзину.")
        #expect(ru.iphoneUnlinkArchives(2) == "2 сохранённых архива будут перемещены в Корзину.")
        #expect(ru.iphoneUnlinkArchives(5) == "5 сохранённых архивов будут перемещены в Корзину.")
        #expect(ru.iphoneUnlinkArchives(21) == "21 сохранённый архив будет перемещён в Корзину.")
        #expect(ru.iphoneUnlinkTitle("Alex’s iPhone") == "Отвязать Alex’s iPhone?")
        var all: [String] = []
        func add<S: AppStrings>(_ s: S) {
            all += [s.iphoneTileOpen, s.iphoneUnlinkDevice, s.iphoneUnlinkTitle("x"), s.iphoneUnlinkBody,
                    s.iphoneUnlinkConfirm, s.iphoneUnlinkCancel, s.iphoneTileActionsA11y("x"),
                    s.iphoneUnlinkConfirmA11y("x"), s.iphoneUnlinkBusyHelp, s.iphoneUnlinkSaveFailed("x")]
            for n in [1, 2] { all += [s.iphoneUnlinkArchives(n), s.iphoneUnlinkTrashFailed(n, "/f")] }
        }
        add(en); add(ru)
        #expect(all.count == 28)
        #expect(!all.contains { $0.contains(";") })
    }
}
