// Tests/MacDashboardTests/ArchiveMigrationTests.swift
// REDESIGN-IPHONE: ArchiveMigration on temp dirs only. Never touches App Support or ~/Documents.
import Foundation
import Testing
@testable import MacDashboard

@Suite struct ArchiveMigrationTests {
    private let fm = FileManager.default

    private func makeRoot() -> URL {
        fm.temporaryDirectory.appendingPathComponent("md-archmig-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ url: URL, bytes: Int, seed: UInt8) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ Int(seed)) })
        fm.createFile(atPath: url.path, contents: data)
    }

    private func mode(_ url: URL) -> Int {
        ((try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func legacyTree(_ root: URL) -> URL {
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        write(legacy.appendingPathComponent("a/sysdiagnose/x.tar.gz"), bytes: 100, seed: 1)
        write(legacy.appendingPathComponent("a/sysdiagnose/y.tar.gz"), bytes: 200, seed: 2)
        write(legacy.appendingPathComponent("b/sysdiagnose/z.tar.gz"), bytes: 300, seed: 3)
        return legacy
    }

    @Test func planLegacyLists() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = legacyTree(root)
        write(legacy.appendingPathComponent("a/sysdiagnose/.DS_Store"), bytes: 4, seed: 9)
        write(legacy.appendingPathComponent("a/stray.tar.gz"), bytes: 4, seed: 9)
        try fm.createDirectory(at: legacy.appendingPathComponent("c"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: legacy.appendingPathComponent("a/sysdiagnose/link"),
                                  withDestinationURL: legacy.appendingPathComponent("a/sysdiagnose/x.tar.gz"))
        let dest = root.appendingPathComponent("new", isDirectory: true)
        let plan = ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: dest)
        #expect(plan.count == 3)
        #expect(plan.map { $0.source.lastPathComponent } == ["x.tar.gz", "y.tar.gz", "z.tar.gz"])
        #expect(plan.map { $0.destination.path } == [
            dest.appendingPathComponent("a/x.tar.gz").path,
            dest.appendingPathComponent("a/y.tar.gz").path,
            dest.appendingPathComponent("b/z.tar.gz").path])
    }

    @Test func planCurrentLists() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let from = root.appendingPathComponent("from", isDirectory: true)
        write(from.appendingPathComponent("a/x.tar.gz"), bytes: 10, seed: 1)
        write(from.appendingPathComponent("b/z.tar.gz"), bytes: 10, seed: 2)
        write(from.appendingPathComponent("loose.tar.gz"), bytes: 10, seed: 3)
        write(from.appendingPathComponent("a/.hidden"), bytes: 10, seed: 4)
        let to = root.appendingPathComponent("to", isDirectory: true)
        let plan = ArchiveMigration.plan(from: from, to: to)
        #expect(plan.map { $0.destination.path } == [to.appendingPathComponent("a/x.tar.gz").path,
                                                     to.appendingPathComponent("b/z.tar.gz").path])
    }

    private func runMove(forceCopy: Bool) {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = legacyTree(root)
        let dest = root.appendingPathComponent("new", isDirectory: true)
        let plan = ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: dest)
        let originals = plan.map { try? Data(contentsOf: $0.source) }
        let out = ArchiveMigration.execute(plan, forceCopy: forceCopy)
        #expect(out.moved.count == 3)
        #expect(out.clean)
        for (m, data) in zip(plan, originals) {
            #expect(!fm.fileExists(atPath: m.source.path))
            #expect((try? Data(contentsOf: m.destination)) == data)
            #expect(mode(m.destination) == 0o600)
            #expect(mode(m.destination.deletingLastPathComponent()) == 0o700)
            let leftovers = (try? fm.contentsOfDirectory(atPath: m.destination.deletingLastPathComponent().path))?
                .filter { $0.hasSuffix(".part") } ?? []
            #expect(leftovers.isEmpty)
        }
    }

    @Test func executeMovesOnOneVolume() { runMove(forceCopy: false) }
    @Test func executeCopyPath() { runMove(forceCopy: true) }

    @Test func duplicateAndConflict() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = legacyTree(root)
        let dest = root.appendingPathComponent("new", isDirectory: true)
        let x = dest.appendingPathComponent("a/x.tar.gz"), y = dest.appendingPathComponent("a/y.tar.gz")
        write(x, bytes: 100, seed: 1)   // identical to the legacy x
        write(y, bytes: 200, seed: 99)  // same size, other bytes
        let yBefore = try? Data(contentsOf: y)
        let ySrc = legacy.appendingPathComponent("a/sysdiagnose/y.tar.gz")
        let ySrcBefore = try? Data(contentsOf: ySrc)
        let out = ArchiveMigration.execute(ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: dest))
        #expect(out.moved.count == 2)       // x (duplicate) and z
        #expect(out.skipped.count == 1)
        #expect(!fm.fileExists(atPath: legacy.appendingPathComponent("a/sysdiagnose/x.tar.gz").path))
        #expect((try? Data(contentsOf: y)) == yBefore)
        #expect((try? Data(contentsOf: ySrc)) == ySrcBefore)
    }

    @Test func idempotent() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = legacyTree(root)
        let dest = root.appendingPathComponent("new", isDirectory: true)
        let out = ArchiveMigration.execute(ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: dest))
        #expect(out.clean)
        #expect(ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: dest).isEmpty)
        #expect(ArchiveMigration.execute([]) == ArchiveMigration.Outcome())
    }

    @Test func failureLeavesSourceIntact() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = legacyTree(root)
        let blocker = root.appendingPathComponent("blocker")
        write(blocker, bytes: 1, seed: 0)   // a regular file where the destination root should be
        let plan = ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: blocker)
        let before = plan.map { try? Data(contentsOf: $0.source) }
        let out = ArchiveMigration.execute(plan)
        #expect(out.failed.count == 3)
        #expect(out.moved.isEmpty)
        #expect(plan.map { try? Data(contentsOf: $0.source) } == before)

        // Unreadable source on the copy path.
        let dest = root.appendingPathComponent("new", isDirectory: true)
        let one = ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: dest)
        let src = one[0].source
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: src.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: src.path) }
        let out2 = ArchiveMigration.execute([one[0]], forceCopy: true)
        #expect(out2.failed.count == 1)
        #expect(fm.fileExists(atPath: src.path))
        let leftovers = (try? fm.contentsOfDirectory(atPath: one[0].destination.deletingLastPathComponent().path))?
            .filter { $0.hasSuffix(".part") } ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func rollbackRestoresTree() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = legacyTree(root)
        let dest = root.appendingPathComponent("new", isDirectory: true)
        let plan = ArchiveMigration.planLegacy(legacyRoot: legacy, archiveRoot: dest)
        let originals = plan.map { try? Data(contentsOf: $0.source) }
        let out = ArchiveMigration.execute(plan)
        let back = ArchiveMigration.execute(ArchiveMigration.reversed(out))
        #expect(back.moved.count == 3)
        for (m, data) in zip(plan, originals) {
            #expect((try? Data(contentsOf: m.source)) == data)
            #expect(!fm.fileExists(atPath: m.destination.path))
        }
        for dir in ["a", "b"] {
            let items = (try? fm.contentsOfDirectory(atPath: dest.appendingPathComponent(dir).path)) ?? []
            #expect(items.isEmpty)
        }
    }

    @Test func removeEmptyDirectories() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        let aInner = legacy.appendingPathComponent("a/sysdiagnose", isDirectory: true)
        let a = legacy.appendingPathComponent("a", isDirectory: true)
        try? fm.createDirectory(at: aInner, withIntermediateDirectories: true)
        let keepDir = root.appendingPathComponent("keep", isDirectory: true)
        write(keepDir.appendingPathComponent(".DS_Store"), bytes: 2, seed: 1)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("md-archmig-outside-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }

        ArchiveMigration.removeEmptyDirectories([a, aInner, legacy, keepDir, outside, root], stopAt: root)
        #expect(!fm.fileExists(atPath: aInner.path))
        #expect(!fm.fileExists(atPath: a.path))
        #expect(!fm.fileExists(atPath: legacy.path))
        #expect(fm.fileExists(atPath: keepDir.path))   // holds .DS_Store
        #expect(fm.fileExists(atPath: root.path))      // stopAt itself
        #expect(fm.fileExists(atPath: outside.path))   // outside stopAt
    }

    @Test func sameContent() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        let c = root.appendingPathComponent("c"), d = root.appendingPathComponent("d")
        write(a, bytes: 2_500_000, seed: 1); write(b, bytes: 2_500_000, seed: 1)
        write(c, bytes: 2_500_000, seed: 2); write(d, bytes: 10, seed: 1)
        #expect(ArchiveMigration.sameContent(a, b))
        #expect(!ArchiveMigration.sameContent(a, c))
        #expect(!ArchiveMigration.sameContent(a, d))
        #expect(!ArchiveMigration.sameContent(a, root.appendingPathComponent("missing")))
    }

    @Test func sameFileViaSymlinkIsKept() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let src = root.appendingPathComponent("src", isDirectory: true)
        write(src.appendingPathComponent("a/x.tar.gz"), bytes: 100, seed: 1)
        let original = try Data(contentsOf: src.appendingPathComponent("a/x.tar.gz"))
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: src)
        let plan = ArchiveMigration.plan(from: src, to: alias)
        #expect(plan.count == 1)
        let out = ArchiveMigration.execute(plan)
        #expect(out.moved.count == 1 && out.skipped.isEmpty && out.failed.isEmpty)
        #expect(try Data(contentsOf: src.appendingPathComponent("a/x.tar.gz")) == original)
    }

    @Test func sameFileViaCaseDifferenceIsKept() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let src = root.appendingPathComponent("src", isDirectory: true)
        write(src.appendingPathComponent("a/x.tar.gz"), bytes: 100, seed: 1)
        let original = try Data(contentsOf: src.appendingPathComponent("a/x.tar.gz"))
        let upper = root.appendingPathComponent("SRC", isDirectory: true)
        // On a case-sensitive temp volume "SRC" is a different (missing) folder; nothing to check there.
        guard fm.fileExists(atPath: upper.path) else { return }
        let out = ArchiveMigration.execute(ArchiveMigration.plan(from: src, to: upper))
        #expect(out.moved.count == 1 && out.skipped.isEmpty && out.failed.isEmpty)
        #expect(try Data(contentsOf: src.appendingPathComponent("a/x.tar.gz")) == original)
    }
}
