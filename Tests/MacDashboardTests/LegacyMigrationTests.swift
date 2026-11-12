// Tests/MacDashboardTests/LegacyMigrationTests.swift
// MOONPORT-RENAME: the first-launch move of the old app's data (Application Support folder, kept archives in Documents,
// IPSW partials), the defaults copy, the old-app detection and the notice rules. Temp dirs and isolated defaults suites
// only: nothing here reads or writes ~/Library/Application Support or ~/Documents (live constraint: user data is off-limits).
import Foundation
import Testing
@testable import MacDashboard

private var fm: FileManager { .default }

/// A fresh `<tmp>/<UUID>` root. Refuses any path that could be the user's real data.
private func makeRoot() -> URL {
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    precondition(!root.path.contains("/Library/Application Support/"), "LegacyMigrationTests: temp root must never be App Support")
    precondition(root.path.hasPrefix(fm.temporaryDirectory.path)
                 || !(root.path.contains("/Documents/MacDashboard") || root.path.contains("/Documents/Moonport")),
                 "LegacyMigrationTests: temp root must never be the real Documents folders")
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func put(_ url: URL, _ text: String) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: url.path, contents: Data(text.utf8))
}

/// Relative path → bytes of every regular file under `root`, dotfiles included.
private func tree(_ root: URL) -> [String: Data] {
    guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
    let base = root.standardizedFileURL.path
    var out: [String: Data] = [:]
    for case let u as URL in en where (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
        out[String(u.standardizedFileURL.path.dropFirst(base.count + 1))] = fm.contents(atPath: u.path)
    }
    return out
}

private func mode(_ url: URL) -> Int {
    ((try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

/// The six named files of the data folder + a legacy archive + `.DS_Store` = 8 regular files.
private let dataFiles = ["mac_report.txt", "mac_check_state.json", "iphones.json", "iphone-log-types.json",
                         "updates_cache.json", "folder_sizes_cache.json", "iphones/k/sysdiagnose/a.tar.gz", ".DS_Store"]

private func makeDataFolder(_ dir: URL) {
    for f in dataFiles { put(dir.appendingPathComponent(f), "old:" + f) }
}

@Suite struct LegacyMigrationTests {

    // MARK: Data folder (D2)

    @Test func t1FreshInstallDoesNothing() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let new = root.appendingPathComponent("new")
        #expect(LegacyDataMigration.run(old: root.appendingPathComponent("old"), new: new, lockURL: root.appendingPathComponent("l")) == .nothing)
        #expect(!exists(new))
    }

    @Test func t2RenameMovesTheWholeTree() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(old)
        let before = tree(old)
        #expect(LegacyDataMigration.run(old: old, new: new, lockURL: root.appendingPathComponent("l")) == .moved(files: 8, parked: 0, failed: 0))
        #expect(tree(new) == before)
        #expect(!exists(old))
        #expect(mode(new) == 0o700)
    }

    @Test func t3BothPresentIdenticalBytes() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(old); makeDataFolder(new)
        let before = tree(new)
        let outcome = LegacyDataMigration.run(old: old, new: new, lockURL: root.appendingPathComponent("l"))
        guard case .moved(_, let parked, let failed) = outcome else { Issue.record("expected .moved, got \(outcome)"); return }
        #expect(parked == 0 && failed == 0)
        #expect(!exists(old))
        #expect(tree(new) == before)
    }

    @Test func t4BothPresentDifferentBytesParksTheOldFile() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(old); makeDataFolder(new)
        put(new.appendingPathComponent("mac_check_state.json"), "NEWER history")
        let outcome = LegacyDataMigration.run(old: old, new: new, lockURL: root.appendingPathComponent("l"))
        guard case .moved(_, let parked, let failed) = outcome else { Issue.record("expected .moved, got \(outcome)"); return }
        #expect(parked == 1 && failed == 0)
        #expect(!exists(old))
        #expect(fm.contents(atPath: new.appendingPathComponent("mac_check_state.json").path) == Data("NEWER history".utf8))
        let park = try #require(try fm.contentsOfDirectory(atPath: new.path).first { $0.hasPrefix("old-app-data-") })
        #expect(fm.contents(atPath: new.appendingPathComponent(park).appendingPathComponent("mac_check_state.json").path)
                == Data("old:mac_check_state.json".utf8))
    }

    @Test func t5ForceCopyVerifiesBeforeRemovingSources() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(old)
        let before = tree(old)
        #expect(LegacyDataMigration.run(old: old, new: new, lockURL: root.appendingPathComponent("l"), forceCopy: true)
                == .moved(files: 8, parked: 0, failed: 0))
        #expect(tree(new) == before)
        #expect(!exists(old))
    }

    @Test func t6StaleScratchFileFromAnInterruptedCopyIsReplaced() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(old)
        put(new.appendingPathComponent(".mac_report.txt.part"), "junk from a crashed copy")
        let before = tree(old)
        #expect(LegacyDataMigration.run(old: old, new: new, lockURL: root.appendingPathComponent("l"), forceCopy: true)
                == .moved(files: 8, parked: 0, failed: 0))
        #expect(tree(new) == before, "the scratch file is gone and every file is correct")
        #expect(!exists(old))
    }

    @Test func t7UnreadableSourceStaysAndIsCounted() {
        guard geteuid() != 0 else { return }
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(old)
        let locked = old.appendingPathComponent("updates_cache.json")
        try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: locked.path) }
        #expect(LegacyDataMigration.run(old: old, new: new, lockURL: root.appendingPathComponent("l"), forceCopy: true)
                == .moved(files: 7, parked: 0, failed: 1))
        #expect(exists(locked), "the unreadable file stays in the old folder")
        #expect(exists(old), "the old folder is not empty")
        #expect(tree(new).keys.sorted() == dataFiles.filter { $0 != "updates_cache.json" }.sorted())
    }

    @Test func t8UnwritableDestinationLosesNothingAndRecovers() {
        guard geteuid() != 0 else { return }
        let root = makeRoot(); defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent("new").path); try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(old)
        let before = tree(old)
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: new.path)
        let lock = root.appendingPathComponent("l")
        #expect(LegacyDataMigration.run(old: old, new: new, lockURL: lock) == .moved(files: 0, parked: 0, failed: 8))
        #expect(tree(old) == before, "the old folder is intact byte for byte")
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: new.path)
        #expect(LegacyDataMigration.run(old: old, new: new, lockURL: lock) == .moved(files: 8, parked: 0, failed: 0))
        #expect(tree(new) == before)
        #expect(!exists(old))
    }

    @Test func t9SecondRunChangesNothing() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(old)
        let lock = root.appendingPathComponent("l")
        _ = LegacyDataMigration.run(old: old, new: new, lockURL: lock)
        let after = tree(new)
        #expect(LegacyDataMigration.run(old: old, new: new, lockURL: lock) == .nothing)
        #expect(tree(new) == after)
    }

    @Test func t10TwoRunsInParallelMoveOnce() async {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new"), lock = root.appendingPathComponent("l")
        makeDataFolder(old)
        let before = tree(old)
        let a = Task.detached { LegacyDataMigration.run(old: old, new: new, lockURL: lock) }
        let b = Task.detached { LegacyDataMigration.run(old: old, new: new, lockURL: lock) }
        let results = [await a.value, await b.value]
        #expect(results.filter { $0 == .moved(files: 8, parked: 0, failed: 0) }.count == 1)
        #expect(results.filter { $0 == .nothing }.count == 1)
        #expect(tree(new) == before)
    }

    @Test func t11OldFolderThatIsASymlinkToNewIsLeftAlone() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        makeDataFolder(new)
        let before = tree(new)
        try fm.createSymbolicLink(at: old, withDestinationURL: new)
        #expect(LegacyDataMigration.run(old: old, new: new, lockURL: root.appendingPathComponent("l")) == .nothing)
        #expect(tree(new) == before)
        #expect(exists(old))
    }

    @Test func t12PlanTreeKeepsDotfilesAndRelativePaths() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let from = root.appendingPathComponent("from"), to = root.appendingPathComponent("to")
        for f in ["z.txt", ".hidden", "a/b/c.bin", "a/.DS_Store", "m/n.json"] { put(from.appendingPathComponent(f), f) }
        try? fm.createDirectory(at: from.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let plan = ArchiveMigration.planTree(from: from, to: to)
        let base = from.standardizedFileURL.path
        let rel = plan.map { String($0.source.standardizedFileURL.path.dropFirst(base.count + 1)) }
        #expect(rel == [".hidden", "a/.DS_Store", "a/b/c.bin", "m/n.json", "z.txt"], "sorted by source path, empty directories are not files")
        #expect(plan.allSatisfy { $0.destination.standardizedFileURL.path == to.standardizedFileURL.path + "/" + String($0.source.standardizedFileURL.path.dropFirst(base.count + 1)) })
    }

    // MARK: IPSW partials (D15)

    @Test func t19IPSWPartialsMoveOnceAndNeverOverwrite() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old/ipsw"), new = root.appendingPathComponent("new/ipsw")
        let names = [IPSWData.stagingPrefix + UUID().uuidString + ".json", IPSWData.stagingPrefix + UUID().uuidString + ".part"]
        for n in names { put(old.appendingPathComponent(n), "bytes of " + n) }
        let before = tree(old)
        #expect(LegacyDataMigration.moveIPSWPartials(oldRoot: old, newRoot: new))
        #expect(tree(new) == before)
        #expect(!exists(old))
        // New root present: both trees stay.
        put(old.appendingPathComponent(names[0]), "again")
        let oldTree = tree(old), newTree = tree(new)
        #expect(!LegacyDataMigration.moveIPSWPartials(oldRoot: old, newRoot: new))
        #expect(tree(old) == oldTree && tree(new) == newTree)
        // Old root absent.
        #expect(!LegacyDataMigration.moveIPSWPartials(oldRoot: root.appendingPathComponent("none"), newRoot: root.appendingPathComponent("other")))
    }

    @Test func t19bIPSWPartialsMoveIntoAnEmptyNewRootOnly() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old/ipsw"), new = root.appendingPathComponent("new/ipsw")
        let name = IPSWData.stagingPrefix + UUID().uuidString + ".part"
        put(old.appendingPathComponent(name), "bytes")
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        #expect(LegacyDataMigration.moveIPSWPartials(oldRoot: old, newRoot: new))
        #expect(tree(new) == [name: Data("bytes".utf8)])
        #expect(!exists(old))
    }

    @Test func t19cMigrationRunsOnlyInTheMoonportBundle() {
        #expect(LegacyDataMigration.runsMigrationHere(bundleID: AppInfo.bundleID))
        #expect(!LegacyDataMigration.runsMigrationHere(bundleID: AppInfo.bundleID + ".bench"))
        #expect(!LegacyDataMigration.runsMigrationHere(bundleID: AppInfo.legacyBundleID))
        #expect(!LegacyDataMigration.runsMigrationHere(bundleID: nil))
    }

    // MARK: Kept archives (D4)

    private struct Docs {
        let root = makeRoot()
        var base: URL { root.appendingPathComponent("docs", isDirectory: true) }
        var oldParent: URL { base.appendingPathComponent("MacDashboard", isDirectory: true) }
        var old: URL { oldParent.appendingPathComponent("iPhone", isDirectory: true) }
        var new: URL { base.appendingPathComponent("Moonport/iPhone", isDirectory: true) }
        var lock: URL { root.appendingPathComponent("l") }
        func cleanUp() { try? fm.removeItem(at: root) }
    }

    private func isolated<T>(_ body: (UserDefaults) -> T) -> T {
        let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
        return body(d)
    }

    @Test func t14bRenameMovesTheRootAndRemovesTheOldFolder() {
        let t = Docs(); defer { t.cleanUp() }
        put(t.old.appendingPathComponent("k1/a.tar.gz"), "a"); put(t.old.appendingPathComponent("k2/b.tar.gz"), "b")
        put(t.oldParent.appendingPathComponent(".DS_Store"), "ds")
        let outcome = LegacyArchiveMove.run(oldRoot: t.old, newRoot: t.new, lockURL: t.lock)
        #expect(outcome == .moved(files: 2, kept: 0, failed: 0))
        #expect(tree(t.new) == ["k1/a.tar.gz": Data("a".utf8), "k2/b.tar.gz": Data("b".utf8)])
        #expect(!exists(t.oldParent))
        isolated { d in LegacyArchiveMove.finish(outcome, defaults: d); #expect(d.bool(forKey: LegacyArchiveMove.markerKey)) }
    }

    @Test func t14cMergeIntoAnExistingRoot() {
        let t = Docs(); defer { t.cleanUp() }
        put(t.new.appendingPathComponent("k1/a.tar.gz"), "a"); put(t.new.appendingPathComponent("k3/x.tar.gz"), "x")
        put(t.old.appendingPathComponent("k1/a.tar.gz"), "a"); put(t.old.appendingPathComponent("k1/d.tar.gz"), "d")
        put(t.old.appendingPathComponent("k2/b.tar.gz"), "b")
        let outcome = LegacyArchiveMove.run(oldRoot: t.old, newRoot: t.new, lockURL: t.lock)
        guard case .moved(_, let kept, let failed) = outcome else { Issue.record("expected .moved, got \(outcome)"); return }
        #expect(kept == 0 && failed == 0)
        #expect(tree(t.new).keys.sorted() == ["k1/a.tar.gz", "k1/d.tar.gz", "k2/b.tar.gz", "k3/x.tar.gz"])
        #expect(!exists(t.old))
    }

    @Test func t14dConflictKeepsBothFiles() {
        let t = Docs(); defer { t.cleanUp() }
        put(t.new.appendingPathComponent("k1/a.tar.gz"), "NEW"); put(t.old.appendingPathComponent("k1/a.tar.gz"), "OLD")
        put(t.old.appendingPathComponent("k2/b.tar.gz"), "b")
        let outcome = LegacyArchiveMove.run(oldRoot: t.old, newRoot: t.new, lockURL: t.lock)
        #expect(outcome == .moved(files: 1, kept: 1, failed: 0))
        #expect(fm.contents(atPath: t.new.appendingPathComponent("k1/a.tar.gz").path) == Data("NEW".utf8))
        #expect(fm.contents(atPath: t.old.appendingPathComponent("k1/a.tar.gz").path) == Data("OLD".utf8))
        #expect(exists(t.oldParent))
        isolated { d in LegacyArchiveMove.finish(outcome, defaults: d); #expect(d.bool(forKey: LegacyArchiveMove.markerKey)) }
    }

    @Test func t14eDeniedMovesNothingAndRetries() {
        let t = Docs(); defer { t.cleanUp() }
        put(t.old.appendingPathComponent("k1/a.tar.gz"), "a"); put(t.old.appendingPathComponent("k2/b.tar.gz"), "b")
        let before = tree(t.old)
        let outcome = LegacyArchiveMove.run(oldRoot: t.old, newRoot: t.new, lockURL: t.lock, state: { _ in .denied })
        #expect(outcome == .denied)
        #expect(tree(t.old) == before)
        #expect(!exists(t.new))
        isolated { d in LegacyArchiveMove.finish(outcome, defaults: d); #expect(d.object(forKey: LegacyArchiveMove.markerKey) == nil) }
        #expect(LegacyArchiveMove.run(oldRoot: t.old, newRoot: t.new, lockURL: t.lock) == .moved(files: 2, kept: 0, failed: 0), "the next launch moves everything")
        #expect(tree(t.new) == before)
    }

    @Test func t14fAbsentOldRootNeedsNothing() {
        let t = Docs(); defer { t.cleanUp() }
        let outcome = LegacyArchiveMove.run(oldRoot: t.old, newRoot: t.new, lockURL: t.lock)
        #expect(outcome == .notNeeded)
        #expect(!exists(t.new))
        isolated { d in LegacyArchiveMove.finish(outcome, defaults: d); #expect(d.bool(forKey: LegacyArchiveMove.markerKey)) }
    }

    @Test func t14gForceCopyEndsInTheSameTree() {
        let t = Docs(); defer { t.cleanUp() }
        put(t.old.appendingPathComponent("k1/a.tar.gz"), "a"); put(t.old.appendingPathComponent("k2/b.tar.gz"), "b")
        put(t.oldParent.appendingPathComponent(".DS_Store"), "ds")
        #expect(LegacyArchiveMove.run(oldRoot: t.old, newRoot: t.new, lockURL: t.lock, forceCopy: true) == .moved(files: 2, kept: 0, failed: 0))
        #expect(tree(t.new) == ["k1/a.tar.gz": Data("a".utf8), "k2/b.tar.gz": Data("b".utf8)])
        #expect(!exists(t.oldParent))
    }

    @Test func t14hUserFileKeepsTheOldParent() {
        let t = Docs(); defer { t.cleanUp() }
        put(t.old.appendingPathComponent("k1/a.tar.gz"), "a"); put(t.oldParent.appendingPathComponent("notes.txt"), "mine")
        #expect(LegacyArchiveMove.run(oldRoot: t.old, newRoot: t.new, lockURL: t.lock) == .moved(files: 1, kept: 0, failed: 0))
        #expect(tree(t.oldParent) == ["notes.txt": Data("mine".utf8)])
        #expect(tree(t.new) == ["k1/a.tar.gz": Data("a".utf8)])
    }

    @Test func t14iCustomFolderIsNeverTouched() {
        let t = Docs(); defer { t.cleanUp() }
        put(t.old.appendingPathComponent("k1/a.tar.gz"), "a")
        let before = tree(t.base)
        isolated { d in
            #expect(!LegacyArchiveMove.needsMove(archiveFolder: "/x/y", records: [keeping("k1")], defaults: d))
            #expect(d.bool(forKey: LegacyArchiveMove.markerKey))
        }
        #expect(tree(t.base) == before)
    }

    @Test func t14jIncompleteDataMoveKeepsTheArchiveMoveForALaterLaunch() {
        isolated { d in
            #expect(!LegacyArchiveMove.needsMove(archiveFolder: nil, records: [], defaults: d, dataMoveIncomplete: true))
            #expect(!d.bool(forKey: LegacyArchiveMove.markerKey), "no marker while the records may still be in the old folder")
            #expect(LegacyArchiveMove.needsMove(archiveFolder: nil, records: [keeping("k1")], defaults: d))
        }
    }

    @Test func t14kRootState() throws {
        let t = Docs(); defer { t.cleanUp() }
        put(t.old.appendingPathComponent("k1/a.tar.gz"), "a")
        #expect(LegacyArchiveMove.rootState(t.old) == .present)
        #expect(LegacyArchiveMove.rootState(t.base.appendingPathComponent("missing")) == .absent)
        #expect(LegacyArchiveMove.rootState(t.old.appendingPathComponent("k1/a.tar.gz/below")) == .absent, "ENOTDIR")
    }

    private func keeping(_ name: String, _ kept: [String] = ["a.tar.gz"]) -> IPhoneDeviceRecord {
        IPhoneDeviceRecord(id: name, name: name, lastSeen: Date(), battery: [], keptArchives: kept)
    }

    @Test @MainActor func t14jReadersFindTheFileInEitherRoot() throws {
        let t = Docs(); defer { t.cleanUp() }
        let legacy = t.root.appendingPathComponent("support/iphones")
        func resolve(_ key: String, _ name: String) -> URL? {
            IPhoneModel.resolveKeptArchive(archiveRoot: t.new, oldDefaultRoot: t.old, legacyRoot: legacy, deviceKey: key, name: name)
        }
        put(t.new.appendingPathComponent("k1/both.tar.gz"), "new"); put(t.old.appendingPathComponent("k1/both.tar.gz"), "old")
        put(t.old.appendingPathComponent("k1/onlyold.tar.gz"), "old")
        put(legacy.appendingPathComponent("k1/sysdiagnose/onlylegacy.tar.gz"), "legacy")
        #expect(resolve("k1", "both.tar.gz") == t.new.appendingPathComponent("k1/both.tar.gz"))
        #expect(resolve("k1", "onlyold.tar.gz") == t.old.appendingPathComponent("k1/onlyold.tar.gz"))
        #expect(resolve("k1", "onlylegacy.tar.gz") == legacy.appendingPathComponent("k1/sysdiagnose/onlylegacy.tar.gz"))
        #expect(resolve("k1", "nowhere.tar.gz") == nil)

        let model = IPhoneModel(store: IPhoneStore(url: t.root.appendingPathComponent("iphones.json")),
                                archiveRoot: t.new, oldDefaultArchiveRoot: t.old,
                                logTypeStore: IPhoneLogTypeStore(url: t.root.appendingPathComponent(IPhoneLogTypeStore.fileName)))
        model.devices = [keeping("k1", ["onlyold.tar.gz"])]
        let url = try #require(model.keptArchiveURL(deviceKey: "k1", name: "onlyold.tar.gz"))
        var trashed: [URL] = []
        model.trashKeptArchive(deviceKey: "k1", name: "onlyold.tar.gz", url: url, trash: { trashed.append($0) })
        #expect(trashed == [url])
        #expect(model.devices[0].keptArchives.isEmpty, "the name is dropped from the record")
    }

    // MARK: Old app (D5, D6)

    private func makeApp(in dir: URL, id: String?) {
        let app = dir.appendingPathComponent("\(AppInfo.legacyAppName).app", isDirectory: true)
        try? fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        guard let id, let data = try? PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0) else { return }
        try? data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    }

    @Test func t15DetectionReadsThePlistNotTheName() {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let good = root.appendingPathComponent("a"), other = root.appendingPathComponent("b"), noPlist = root.appendingPathComponent("c")
        makeApp(in: good, id: AppInfo.legacyBundleID); makeApp(in: other, id: "com.example.other"); makeApp(in: noPlist, id: nil)
        let goodApp = LegacyApp.bundleURL(in: good)
        #expect(LegacyApp.detect(candidates: [good], excluding: nil) == LegacyApp.Found(url: goodApp))
        #expect(LegacyApp.detect(candidates: [other], excluding: nil) == nil)
        #expect(LegacyApp.detect(candidates: [noPlist], excluding: nil) == nil)
        #expect(LegacyApp.detect(candidates: [root.appendingPathComponent("missing")], excluding: nil) == nil)
        #expect(LegacyApp.detect(candidates: [other, good], excluding: nil) == LegacyApp.Found(url: goodApp), "the first real match wins")
        #expect(LegacyApp.detect(candidates: [good], excluding: goodApp) == nil, "never the running bundle itself")
    }

    /// A temp directory standing in for the Trash: tests never touch the user's real `~/.Trash`.
    private func fakeTrash(in root: URL) throws -> (dir: URL, move: (URL) throws -> URL) {
        let dir = root.appendingPathComponent("FakeTrash", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, { url in
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        })
    }

    @Test func t16bTrashRefusesABundleWithAnotherID() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        makeApp(in: root, id: AppInfo.legacyBundleID)
        let found = try #require(LegacyApp.detect(candidates: [root], excluding: nil))
        try? fm.removeItem(at: root.appendingPathComponent("\(AppInfo.legacyAppName).app"))
        makeApp(in: root, id: "com.example.other")   // replaced after detection
        let trash = try fakeTrash(in: root)
        #expect(throws: (any Error).self) { try LegacyApp.trash(found, move: trash.move) }
        #expect(exists(found.url))
    }

    @Test func t16TrashMovesTheBundleAway() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        makeApp(in: root, id: AppInfo.legacyBundleID)
        let found = try #require(LegacyApp.detect(candidates: [root], excluding: nil))
        let trash = try fakeTrash(in: root)
        let trashed = try LegacyApp.trash(found, move: trash.move)
        #expect(!exists(found.url))
        #expect(exists(trashed))
        #expect(trashed.deletingLastPathComponent() == trash.dir)
    }

    // MARK: Identity (R2)

    @Test func identityComesFromAppInfoAndDerivesEveryPath() {
        #expect(AppInfo.bundleID == "app.moonport" && SnapshotDeletion.appBundleID == AppInfo.bundleID)
        #expect(AppInfo.supportFolderURL.lastPathComponent == AppInfo.supportFolderName)
        #expect(AppInfo.legacySupportFolderURL.lastPathComponent == AppInfo.legacySupportFolderName)
        #expect(AppInfo.supportFolderURL.deletingLastPathComponent() == AppInfo.legacySupportFolderURL.deletingLastPathComponent())
        #expect(IPhoneStore.legacyArchiveRoot().deletingLastPathComponent() == AppInfo.supportFolderURL)
        #expect(IPhoneStore.defaultArchiveRoot().path.hasSuffix("/Documents/Moonport/iPhone"))
        #expect(IPhoneStore.legacyDocumentsArchiveRoot().path.hasSuffix("/\(AppInfo.legacySupportFolderName)/iPhone"))
        #expect(IPhoneStore.defaultArchiveRoot().deletingLastPathComponent().deletingLastPathComponent()
                == IPhoneStore.legacyDocumentsArchiveRoot().deletingLastPathComponent().deletingLastPathComponent())
        #expect(IPSWSources.userAgent.hasPrefix(AppInfo.supportFolderName + "/"))
    }

    // MARK: Notice (D7)

    /// D-W1: a notice only when the shown flag is unset AND this launch's data migration moved, parked or left a file.
    @Test func t17NoticeTruthTable() {
        let app = LegacyApp.Found(url: URL(fileURLWithPath: "/Applications/Old.app"))
        func make(_ o: LegacyDataMigration.Outcome, moving: Bool = false, app: LegacyApp.Found? = nil, running: Bool = false,
                  dismissed: Bool = false, shown: Bool = false, archiveCount: Int = 0,
                  record: LegacyDataMigration.MoveRecord = .init(), parkedFolder: URL? = nil) -> LegacyNotice? {
            LegacyNotice.make(outcome: o, archivesMoving: moving, oldApp: app, running: running, dismissed: dismissed,
                              parkedFolder: parkedFolder, shown: shown, archiveCount: archiveCount, record: record)
        }
        let moved = LegacyDataMigration.Outcome.moved(files: 7, parked: 1, failed: 2)
        #expect(make(.nothing) == nil, "a fresh install shows nothing")
        #expect(make(.nothing, app: app) == nil, "nothing moved: Settings › About offers the old app, the panel would claim a move")
        #expect(make(.nothing, moving: true) == nil, "a pending archive move alone never opens the panel")
        #expect(make(moved, shown: true) == nil && make(moved, app: app, shown: true) == nil, "shown once: never again")
        #expect(make(moved) == LegacyNotice(moved: 7, parked: 1, failed: 2, archivesMoving: false, oldApp: nil, oldAppRunning: false))
        #expect(make(moved, app: app, running: true)?.oldApp == app.url)
        #expect(make(moved, app: app, running: true)?.oldAppRunning == true)
        #expect(make(moved, app: app, dismissed: true)?.oldApp == nil, "Keep it hides the offer, the rest stays")
        #expect(make(moved, moving: true, archiveCount: 3)?.archivesMoving == true)
        #expect(make(moved, moving: true, archiveCount: 3)?.archiveCount == 3)
        #expect(make(moved, moving: false, archiveCount: 3)?.archiveCount == 0, "no move started: no archive count")
        let folder = URL(fileURLWithPath: "/x/old-app-data-1"), arg = URL(fileURLWithPath: "/y/old-app-data-2")
        let record = LegacyDataMigration.MoveRecord(parkFolder: folder, parked: ["a.json"], failed: ["b.json", "c/d.json"])
        let n = make(moved, record: record, parkedFolder: arg)
        #expect(n?.parkedFiles == ["a.json"] && n?.failedFiles == ["b.json", "c/d.json"])
        #expect(n?.parkedFolder == folder, "the record's folder wins")
        #expect(make(moved, parkedFolder: arg)?.parkedFolder == arg, "no record: the scanned folder")
        #expect(make(.moved(files: 7, parked: 0, failed: 0), record: record, parkedFolder: arg)?.parkedFolder == nil)
    }

    @Test func newestParkedFolderPicksLatestStamp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lm-parked-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LegacyDataMigration.newestParkedFolder(in: root) == nil)
        for name in ["old-app-data-20260101-120000", "old-app-data-20261112-093000", "report.txt"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        #expect(LegacyDataMigration.newestParkedFolder(in: root)?.lastPathComponent == "old-app-data-20261112-093000")
    }

    /// Counts are plural-correct: no "1 files" in EN, the Russian one/few/many forms (and the verb) in RU.
    @Test func legacyCountPlurals() {
        let en = StringsEN(), ru = StringsRU()
        #expect(en.legacyFilesTag(1) == "1 file" && en.legacyFilesTag(7) == "7 files")
        #expect(en.legacyParkedTitle(1) == "Both versions of a file kept" && en.legacyParkedTitle(2) == "Both versions of 2 files kept")
        #expect(en.legacyFailedTitle(2) == "2 files could not be moved")
        #expect(ru.legacyFilesTag(1) == "1 файл" && ru.legacyFilesTag(3) == "3 файла" && ru.legacyFilesTag(7) == "7 файлов" && ru.legacyFilesTag(21) == "21 файл")
        #expect(ru.legacyParkedTitle(1) == "Сохранены обе версии файла" && ru.legacyParkedTitle(2) == "Сохранены обе версии 2 файлов")
        #expect(ru.legacyParkedTitle(21) == "Сохранены обе версии 21 файла")
        #expect(ru.legacyFailedTitle(2) == "2 файла не удалось перенести")
        #expect(ru.legacyArchivesTag(1) == "1 архив" && ru.legacyArchivesTag(3) == "3 архива"
                && ru.legacyArchivesTag(5) == "5 архивов" && ru.legacyArchivesTag(21) == "21 архив")
        #expect(en.legacyArchivesTag(1) == "1 archive" && en.legacyArchivesTag(3) == "3 archives")
        #expect(ru.legacyArchivesLeftSub(1) == "1 файл остался в старой папке. Перенесите вручную.")
        #expect(ru.legacyArchivesLeftSub(3) == "3 файла остались в старой папке. Перенесите вручную.")
        #expect(ru.legacyArchivesLeftSub(5) == "5 файлов остались в старой папке. Перенесите вручную.")
        #expect(en.legacyArchivesLeftSub(1) == "1 file stayed in the old folder. Move it manually.")
        #expect(en.legacyArchivesLeftSub(3) == "3 files stayed in the old folder. Move them manually.")
        #expect(ru.legacyStepsLeft(1) == "Остался 1 шаг" && ru.legacyStepsLeft(2) == "Осталось 2 шага"
                && ru.legacyStepsLeft(5) == "Осталось 5 шагов" && ru.legacyStepsLeft(21) == "Остался 21 шаг")
        #expect(en.legacyStepsLeft(1) == "1 step left" && en.legacyStepsLeft(2) == "2 steps left")
        #expect(en.legacyDoneProgress(done: 1, total: 2) == "1 of 2" && ru.legacyDoneProgress(done: 1, total: 2) == "1 из 2")
    }

    /// T18: the 52 keys of the Welcome strings exist in EN and RU, the two differ, no value holds a semicolon.
    @Test func t18LegacyStrings() {
        func pairs(_ t: any LegacyStrings) -> [(String, String)] {
            [("legacyNoticeTitle", t.legacyNoticeTitle),
             ("legacySubtitle", t.legacySubtitle),
             ("legacySectionDone", t.legacySectionDone),
             ("legacySectionTodo", t.legacySectionTodo),
             ("legacyDoneAllInPlace", t.legacyDoneAllInPlace),
             ("legacyDoneWithNotes", t.legacyDoneWithNotes),
             ("legacyDoneProgress", t.legacyDoneProgress(done: 1, total: 2)),
             ("legacyDataMovedTitle", t.legacyDataMovedTitle),
             ("legacyDataMovedSub", t.legacyDataMovedSub),
             ("legacyFilesTag", t.legacyFilesTag(7)),
             ("legacyArchivesMovingTitle", t.legacyArchivesMovingTitle),
             ("legacyArchivesMovingTag", t.legacyArchivesMovingTag),
             ("legacyArchivesMovedTitle", t.legacyArchivesMovedTitle),
             ("legacyArchivesDeniedTitle", t.legacyArchivesDeniedTitle),
             ("legacyArchivesDeniedSub", t.legacyArchivesDeniedSub),
             ("legacyArchivesDeniedAgainSub", t.legacyArchivesDeniedAgainSub),
             ("legacyArchivesTag", t.legacyArchivesTag(3)),
             ("legacyArchivesLeftSub", t.legacyArchivesLeftSub(3)),
             ("legacyParkedTitle", t.legacyParkedTitle(2)),
             ("legacyParkedSub", t.legacyParkedSub),
             ("legacyShowButton", t.legacyShowButton),
             ("legacyFailedTitle", t.legacyFailedTitle(2)),
             ("legacyFailedSub", t.legacyFailedSub),
             ("legacyPermsTitle", t.legacyPermsTitle),
             ("legacyPermsSub", t.legacyPermsSub),
             ("legacyOpenButton", t.legacyOpenButton),
             ("legacyCheckingLabel", t.legacyCheckingLabel),
             ("legacyGrantedLabel", t.legacyGrantedLabel),
             ("legacyOptionalTag", t.legacyOptionalTag),
             ("legacyLoginSub", t.legacyLoginSub),
             ("legacyOldAppTitle", t.legacyOldAppTitle),
             ("legacyInApplications", t.legacyInApplications),
             ("legacyOldAppNoneSub", t.legacyOldAppNoneSub),
             ("legacyOldAppKeptSub", t.legacyOldAppKeptSub),
             ("legacyOldAppTrashedSub", t.legacyOldAppTrashedSub),
             ("legacyNoticeOldAppRunning", t.legacyNoticeOldAppRunning),
             ("legacyTrashButton", t.legacyTrashButton),
             ("legacyKeepButton", t.legacyKeepButton),
             ("legacyKeptLabel", t.legacyKeptLabel),
             ("legacyInTrashLabel", t.legacyInTrashLabel),
             ("legacyUndoButton", t.legacyUndoButton),
             ("legacyQuitRefused", t.legacyQuitRefused),
             ("legacyTrashFailed", t.legacyTrashFailed(reason: "r")),
             ("legacyRestoreOccupied", t.legacyRestoreOccupied),
             ("legacyRestoreGone", t.legacyRestoreGone),
             ("legacyRestoreFailed", t.legacyRestoreFailed),
             ("settingsOldAppLabel", t.settingsOldAppLabel),
             ("settingsOldAppSub", t.settingsOldAppSub),
             ("legacyLaterButton", t.legacyLaterButton),
             ("legacyDoneButton", t.legacyDoneButton),
             ("legacyAllDone", t.legacyAllDone),
             ("legacyStepsLeft", t.legacyStepsLeft(2))]
        }
        let en = pairs(StringsEN()), ru = pairs(StringsRU())
        #expect(en.count == 52 && ru.count == 52)
        let sameAllowed: Set<String> = []
        for (e, r) in zip(en, ru) {
            #expect(!e.1.isEmpty && !r.1.isEmpty, "\(e.0) is non-empty in EN and RU")
            #expect(!e.1.contains(";") && !r.1.contains(";"), "\(e.0) has no semicolon")
            if !sameAllowed.contains(e.0) { #expect(e.1 != r.1, "\(e.0) differs between EN and RU") }
        }
    }

    // MARK: Moonport Welcome (amendment 3)

    @Test func t19MoveRecordListsParkedAndLeftovers() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        put(old.appendingPathComponent("a.txt"), "old a")
        put(old.appendingPathComponent("b.txt"), "only in old")
        put(new.appendingPathComponent("a.txt"), "new a")
        let (outcome, record) = LegacyDataMigration.runRecorded(old: old, new: new, lockURL: root.appendingPathComponent("l"))
        #expect(outcome == .moved(files: 1, parked: 1, failed: 0))
        #expect(record.parked == ["a.txt"] && record.failed.isEmpty)
        let park = try #require(record.parkFolder)
        #expect(exists(park.appendingPathComponent("a.txt")) && exists(new.appendingPathComponent("a.txt")))
        #expect(exists(new.appendingPathComponent("b.txt")))

        let three = root.appendingPathComponent("three")
        for f in ["x.txt", "y/z.txt", "w.txt"] { put(three.appendingPathComponent(f), f) }
        let two = LegacyDataMigration.leftoverFiles(under: three, limit: 2)
        #expect(two.count == 2 && Set(two).isSubset(of: ["x.txt", "y/z.txt", "w.txt"]))
        #expect(LegacyDataMigration.leftoverFiles(under: three, limit: 50).count == 3)
    }

    @Test func t20RestorePutsTheBundleBack() throws {
        let root = makeRoot(); defer { try? fm.removeItem(at: root) }
        makeApp(in: root, id: AppInfo.legacyBundleID)
        let found = try #require(LegacyApp.detect(candidates: [root], excluding: nil))
        let trash = try fakeTrash(in: root)
        let trashed = try LegacyApp.trash(found, move: trash.move)
        try LegacyApp.restore(trashed: trashed, to: found.url)
        #expect(exists(found.url) && !exists(trashed))

        let trashed2 = try LegacyApp.trash(found, move: trash.move)
        makeApp(in: root, id: AppInfo.legacyBundleID)   // the user put something at the original place
        #expect(throws: LegacyApp.RestoreError.originalOccupied) { try LegacyApp.restore(trashed: trashed2, to: found.url) }
        #expect(exists(trashed2), "nothing was moved")

        try fm.removeItem(at: found.url)
        try fm.removeItem(at: trashed2)
        #expect(throws: LegacyApp.RestoreError.notInTrash) { try LegacyApp.restore(trashed: trashed2, to: found.url) }
    }

    @Test func welcomeProgressRules() {
        typealias W = WelcomeProgress
        #expect(W.archiveRow(nil) == .busy)
        #expect(W.archiveRow(.notNeeded) == .done)
        #expect(W.archiveRow(.moved(files: 3, kept: 0, failed: 0)) == .done)
        #expect(W.archiveRow(.moved(files: 3, kept: 1, failed: 2)) == .left(3))
        #expect(W.archiveRow(.denied) == .denied)
        #expect(W.doneCaption(dataShown: true, archive: .busy, failed: 0) == .progress(done: 1, total: 2))
        #expect(W.doneCaption(dataShown: true, archive: .denied, failed: 2) == .progress(done: 1, total: 2))
        #expect(W.doneCaption(dataShown: false, archive: .busy, failed: 0) == .progress(done: 0, total: 1))
        #expect(W.doneCaption(dataShown: true, archive: .done, failed: 2) == .withNotes)
        #expect(W.doneCaption(dataShown: true, archive: .left(1), failed: 0) == .withNotes)
        #expect(W.doneCaption(dataShown: true, archive: .done, failed: 0) == .allInPlace)
        #expect(W.doneCaption(dataShown: true, archive: nil, failed: 0) == .allInPlace)
        #expect(W.doneCaption(dataShown: true, archive: nil, failed: 1) == .withNotes)
        #expect(W.remaining(fdaGranted: false, hasOldApp: true, oldAppDecided: false) == 2)
        #expect(W.remaining(fdaGranted: true, hasOldApp: true, oldAppDecided: false) == 1)
        #expect(W.remaining(fdaGranted: false, hasOldApp: false, oldAppDecided: false) == 1)
        #expect(W.remaining(fdaGranted: true, hasOldApp: true, oldAppDecided: true) == 0)
        #expect(W.remaining(fdaGranted: true, hasOldApp: false, oldAppDecided: false) == 0)
        #expect(W.shouldRetryArchives(fdaGranted: true, outcome: .denied, retried: false))
        #expect(!W.shouldRetryArchives(fdaGranted: false, outcome: .denied, retried: false))
        #expect(!W.shouldRetryArchives(fdaGranted: true, outcome: .denied, retried: true))
        #expect(!W.shouldRetryArchives(fdaGranted: true, outcome: nil, retried: false))
        #expect(!W.shouldRetryArchives(fdaGranted: true, outcome: .moved(files: 1, kept: 0, failed: 0), retried: false))
    }

    @Test func fullDiskAccessFromProbe() {
        func state(_ answers: [String: DirAccess]) -> (FullDiskAccessState, [String]) {
            var asked: [String] = []
            let r = ProtectedLocations.fullDiskAccess(home: "/h") { path in asked.append(path); return answers[path] ?? .missing }
            return (r, asked)
        }
        #expect(ProtectedLocations.fdaOnlyRows == ["Library/Safari", "Library/Mail"])
        let (granted, asked) = state(["/h/Library/Safari": .readable])
        #expect(granted == .granted)
        #expect(Set(asked) == ["/h/Library/Safari", "/h/Library/Mail"], "only the two FDA-only rows are probed")
        #expect(state(["/h/Library/Safari": .denied]).0 == .notGranted)
        #expect(state(["/h/Library/Safari": .readable, "/h/Library/Mail": .denied]).0 == .notGranted)
        #expect(state([:]).0 == .unknown)
    }
}

// MARK: - Process-wide state (UserDefaults suites): inside the serialized root suite

extension SerialTests {
    struct LegacyDefaultsTests {
        @Test func t13DefaultsCopyFillsOnlyAbsentKeys() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            d.set("dark", forKey: "appearance")
            let source: [String: Any] = ["appearance": "light", "fastInterval": 10, "AppleLanguages": ["ru"], "iphoneWifi": false]
            #expect(LegacyDefaultsMigration.copy(from: AppInfo.legacyBundleID, into: d, ownDomain: name, source: source) == 3)
            #expect(d.string(forKey: "appearance") == "dark", "a key the new domain has is kept")
            #expect(d.integer(forKey: "fastInterval") == 10)
            #expect(d.stringArray(forKey: "AppleLanguages") == ["ru"], "the menu language survives although the global domain has a value")
            #expect(d.object(forKey: "iphoneWifi") as? Bool == false)
            #expect(d.string(forKey: LegacyDefaultsMigration.markerKey) == AppInfo.legacyBundleID)
            #expect(LegacyDefaultsMigration.copy(from: AppInfo.legacyBundleID, into: d, ownDomain: name, source: source) == 0, "once")
        }

        @Test @MainActor func legacyAppOfferDismissedPersists() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            #expect(AppSettings(defaults: d).legacyAppOfferDismissed == false)
            AppSettings(defaults: d).legacyAppOfferDismissed = true
            #expect(d.bool(forKey: AppSettings.legacyAppOfferDismissedKey))
            #expect(AppSettings(defaults: d).legacyAppOfferDismissed)
        }

        @Test @MainActor func welcomeShownPersists() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            #expect(AppSettings(defaults: d).welcomeShown == false)
            AppSettings(defaults: d).welcomeShown = true
            #expect(d.bool(forKey: AppSettings.welcomeShownKey))
            #expect(AppSettings(defaults: d).welcomeShown)
        }

        @Test func t14aGate() {
            let kept = IPhoneDeviceRecord(id: "k", name: "k", lastSeen: Date(), battery: [], keptArchives: ["a.tar.gz"])
            let none = IPhoneDeviceRecord(id: "n", name: "n", lastSeen: Date(), battery: [], keptArchives: [])
            func fresh(_ body: (UserDefaults) -> Void) { let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }; body(d) }
            fresh { d in   // marker set: false, records never evaluated
                d.set(true, forKey: LegacyArchiveMove.markerKey)
                var evaluated = false
                let needs = LegacyArchiveMove.needsMove(archiveFolder: nil, records: { evaluated = true; return [kept] }(), defaults: d)   // not inside #expect: the macro would evaluate the argument first
                #expect(!needs)
                #expect(!evaluated)
            }
            fresh { d in   // custom folder: false, marker set, records never evaluated
                var evaluated = false
                let needs = LegacyArchiveMove.needsMove(archiveFolder: "/x/y", records: { evaluated = true; return [kept] }(), defaults: d)
                #expect(!needs)
                #expect(d.bool(forKey: LegacyArchiveMove.markerKey) && !evaluated)
            }
            fresh { d in   // default folder, nothing kept: false, marker set
                #expect(!LegacyArchiveMove.needsMove(archiveFolder: nil, records: [none], defaults: d))
                #expect(d.bool(forKey: LegacyArchiveMove.markerKey))
            }
            fresh { d in   // default folder, one kept archive: true, marker still unset
                #expect(LegacyArchiveMove.needsMove(archiveFolder: nil, records: [none, kept], defaults: d))
                #expect(d.object(forKey: LegacyArchiveMove.markerKey) == nil)
            }
        }
    }
}
