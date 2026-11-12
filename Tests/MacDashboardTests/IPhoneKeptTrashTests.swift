// Tests/MacDashboardTests/IPhoneKeptTrashTests.swift
// DEVICE-ARCHIVE-CLEANUP D14: moving a kept archive to the Trash. The trash call is injected and temp paths only,
// so neither the real Trash nor App Support is touched.
import Foundation
import Testing
@testable import MacDashboard

@Suite struct IPhoneKeptTrashTests {
    private struct Boom: Error {}
    private let key = "dev1"
    private let name = "sysdiagnose_test.tar.gz"

    /// A model with one device that keeps `name`; the file exists in `<dir>/archive/<key>/`.
    @MainActor
    private func makeModel(createFile: Bool = true) throws -> (IPhoneModel, URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-kept-trash-\(UUID().uuidString)")
        let folder = dir.appendingPathComponent("archive").appendingPathComponent(key)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        if createFile { FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8)) }
        let m = IPhoneModel(store: IPhoneStore(url: dir.appendingPathComponent("iphones.json")),
                            archiveRoot: dir.appendingPathComponent("archive"),
                            oldDefaultArchiveRoot: dir.appendingPathComponent("archive-old"),
                            logTypeStore: IPhoneLogTypeStore(url: dir.appendingPathComponent(IPhoneLogTypeStore.fileName)))
        m.devices = [IPhoneDeviceRecord(id: key, name: "T", lastSeen: Date(), battery: [], keptArchives: [name])]
        return (m, dir, file)
    }

    /// Stands in for the Trash: moves the file into a sibling folder.
    private func fakeTrash(_ dir: URL) -> (URL) throws -> Void {
        { url in
            let t = dir.appendingPathComponent("trash")
            try FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: t.appendingPathComponent(url.lastPathComponent))
        }
    }

    @Test @MainActor func successRemovesNameAndMovesFile() throws {
        let (m, dir, file) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.trashKeptArchive(deviceKey: key, name: name, url: file, trash: fakeTrash(dir))
        #expect(m.devices[0].keptArchives.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(m.keptTrashFailed[key] == nil)
    }

    @Test @MainActor func alreadyGoneRemovesName() throws {
        let (m, dir, file) = try makeModel(createFile: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        m.trashKeptArchive(deviceKey: key, name: name, url: file, trash: { _ in throw Boom() })
        #expect(m.devices[0].keptArchives.isEmpty)
        #expect(m.keptTrashFailed[key] == nil)
    }

    @Test @MainActor func failureKeepsNameAndPublishes() throws {
        let (m, dir, file) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.trashKeptArchive(deviceKey: key, name: name, url: file, trash: { _ in throw Boom() })
        #expect(m.devices[0].keptArchives == [name])
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(m.keptTrashFailed[key] == name)
        m.trashKeptArchive(deviceKey: key, name: name, url: file, trash: fakeTrash(dir))
        #expect(m.keptTrashFailed[key] == nil, "the next attempt clears the failure")
        #expect(m.devices[0].keptArchives.isEmpty)
    }

    @Test @MainActor func urlOutsideRowFolderDoesNothing() throws {
        let (m, dir, file) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let other = dir.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let stray = other.appendingPathComponent(name)
        FileManager.default.createFile(atPath: stray.path, contents: Data())
        var called = false
        m.trashKeptArchive(deviceKey: key, name: name, url: stray, trash: { _ in called = true })
        m.trashKeptArchive(deviceKey: key, name: "other.tar.gz", url: file, trash: { _ in called = true })
        #expect(!called)
        #expect(m.devices[0].keptArchives == [name])
        #expect(FileManager.default.fileExists(atPath: stray.path))
    }
}
