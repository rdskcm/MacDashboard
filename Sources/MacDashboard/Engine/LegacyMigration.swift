// Engine/LegacyMigration.swift
// MOONPORT-RENAME: what the first Moonport launch does about the old app's data: the Application Support folder, the
// IPSW partial-download cache, the defaults domain, the kept iPhone archives in ~/Documents, and the old app bundle.
// Foundation only; covered by Tests/MacDashboardTests/LegacyMigrationTests.swift on temp dirs and isolated suites.
// Every `run` below is pure of singletons: tests pass temp URLs, only the `runAtLaunch` entries touch real paths.
import Foundation

/// Two lock files (D2): `launchURL` serialises the launch-time data and IPSW moves of two Moonport instances
/// (`AppLifecycle.relaunch` starts a second one), `archiveURL` the background archive move, so a second instance's main
/// thread never waits for the long archive move. Blocking `flock`; an unopenable lock file means "run unlocked", never "skip".
enum LegacyLock {
    static var launchURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("moonport-migration.lock") }
    static var archiveURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("moonport-archive-move.lock") }

    static func withLock<T>(_ url: URL, _ body: () -> T) -> T {
        let fd = open(url.path, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        return body()
    }
}

/// Shared helpers of the three tree moves.
private enum LegacyTree {
    static func isDirectory(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    static func regularFileCount(under dir: URL) -> Int {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var n = 0
        for case let u as URL in en where (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { n += 1 }
        return n
    }

    static func directories(under dir: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [URL] = []
        for case let u as URL in en where (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { out.append(u) }
        return out
    }

    static func relativePath(_ url: URL, from root: URL) -> String {
        let r = root.standardizedFileURL.path, p = url.standardizedFileURL.path
        return p.hasPrefix(r + "/") ? String(p.dropFirst(r.count + 1)) : url.lastPathComponent
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        guard let x = ArchiveMigration.volume(of: a), let y = ArchiveMigration.volume(of: b) else { return false }
        return x.isEqual(y)
    }

    /// Per-file path of a tree move: every file of `old` to the same relative path under `new`. A same-name file with
    /// other bytes is a conflict; `parkConflicts` moves it to `new/old-app-data-<stamp>/` instead of leaving it.
    static func moveFiles(old: URL, new: URL, forceCopy: Bool, parkConflicts: Bool)
        -> (moved: Int, skipped: Int, parked: Int, failed: Int, parkFolder: URL?, parkedPaths: [String]) {
        try? FileManager.default.createDirectory(at: new, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let out = ArchiveMigration.execute(ArchiveMigration.planTree(from: old, to: new), forceCopy: forceCopy)
        var parked = 0
        var parkFolder: URL?
        var parkedPaths: [String] = []
        if parkConflicts, !out.skipped.isEmpty {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyyMMdd-HHmmss"
            let park = new.appendingPathComponent("old-app-data-" + df.string(from: Date()), isDirectory: true)
            let aside = out.skipped.map { ArchiveMove(source: $0.source, destination: park.appendingPathComponent(relativePath($0.destination, from: new))) }
            let executed = ArchiveMigration.execute(aside, forceCopy: forceCopy)
            parked = executed.moved.count
            parkFolder = park
            parkedPaths = executed.moved.map { relativePath($0.destination, from: park) }
        }
        return (out.moved.count, parkConflicts ? 0 : out.skipped.count, parked, out.failed.count, parkFolder, parkedPaths)
    }
}

// MARK: - Application Support folder (D2) and IPSW partials (D15)

enum LegacyDataMigration {
    enum Outcome: Equatable, Sendable {
        case nothing
        case moved(files: Int, parked: Int, failed: Int)
    }

    /// The newest `old-app-data-<stamp>` folder directly under `root` (the stamp sorts by time), nil when there is none.
    static func newestParkedFolder(in root: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasPrefix("old-app-data-") }.max().map { root.appendingPathComponent($0, isDirectory: true) }
    }

    /// What this launch did, for the one-time notice. Set once by `runAtLaunch`.
    @MainActor static private(set) var lastOutcome: Outcome = .nothing

    /// W6/D-W6: which files the Welcome panel's «Show» buttons point at. Relative paths, at most `cap` each; kept in
    /// memory for this launch only (the panel shows only on the launch whose migration produced them).
    struct MoveRecord: Equatable, Sendable {
        static let cap = 50
        var parkFolder: URL? = nil
        var parked: [String] = []   // relative paths, the same under `new` and under `parkFolder`
        var failed: [String] = []   // relative paths of the files still under `old`
    }
    @MainActor static private(set) var lastRecord = MoveRecord()

    /// Relative paths of the regular files under `dir`, enumeration order, at most `limit`.
    static func leftoverFiles(under dir: URL, limit: Int) -> [String] {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            out.append(LegacyTree.relativePath(url, from: dir))
            if out.count >= limit { break }
        }
        return out
    }

    /// Old folder absent (or the same folder) → `.nothing`. New absent on one volume → one `rename(2)`. Otherwise per file
    /// (`ArchiveMigration.planTree` + `execute`): identical bytes vanish from `old`, different bytes land in
    /// `new/old-app-data-<stamp>/`. `old` is removed only when empty. `failed` = files still in `old`, recounted from disk.
    static func run(old: URL, new: URL, lockURL: URL, forceCopy: Bool = false) -> Outcome {
        runRecorded(old: old, new: new, lockURL: lockURL, forceCopy: forceCopy).0
    }

    /// `run` plus the record of which files were parked and which are left (D-W6).
    static func runRecorded(old: URL, new: URL, lockURL: URL, forceCopy: Bool = false) -> (Outcome, MoveRecord) {
        LegacyLock.withLock(lockURL) {
            let fm = FileManager.default
            guard LegacyTree.isDirectory(old), !ArchiveMigration.isSameFile(old, new) else { return (.nothing, MoveRecord()) }
            let parent = new.deletingLastPathComponent()
            if !fm.fileExists(atPath: new.path), !forceCopy {
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
                if LegacyTree.sameVolume(old, parent), (try? fm.moveItem(at: old, to: new)) != nil {
                    try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: new.path)
                    let files = LegacyTree.regularFileCount(under: new)
                    return (files == 0 ? .nothing : .moved(files: files, parked: 0, failed: 0), MoveRecord())
                }
            }
            let r = LegacyTree.moveFiles(old: old, new: new, forceCopy: forceCopy, parkConflicts: true)
            ArchiveMigration.removeEmptyDirectories(LegacyTree.directories(under: old) + [old], stopAt: parent)
            let failed = LegacyTree.regularFileCount(under: old)
            let record = MoveRecord(parkFolder: r.parkFolder, parked: Array(r.parkedPaths.prefix(MoveRecord.cap)),
                                    failed: failed > 0 ? leftoverFiles(under: old, limit: MoveRecord.cap) : [])
            return (r.moved + r.parked + failed == 0 ? .nothing : .moved(files: r.moved, parked: r.parked, failed: failed), record)
        }
    }

    /// The IPSW partial-download cache of the old bundle ID → the new one (D15). Only when `newRoot` does not exist or is an
    /// empty directory (an earlier launch may have created it); a non-empty `newRoot` or an error leaves both, returns false.
    static func moveIPSWPartials(oldRoot: URL, newRoot: URL) -> Bool {
        let fm = FileManager.default
        guard LegacyTree.isDirectory(oldRoot) else { return false }
        if fm.fileExists(atPath: newRoot.path) {
            guard LegacyTree.isDirectory(newRoot), (try? fm.contentsOfDirectory(atPath: newRoot.path))?.isEmpty == true else { return false }
            guard (try? fm.removeItem(at: newRoot)) != nil else { return false }
        }
        do {
            try fm.createDirectory(at: newRoot.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.moveItem(at: oldRoot, to: newRoot)
            return true
        } catch { return false }
    }

    /// True only in the installed Moonport bundle: never for a bench copy, a test or `swift run` (the data folder is
    /// bundle-independent, so any other process would move the real folder). Gates every launch step of this file.
    static func runsMigrationHere(bundleID: String? = Bundle.main.bundleIdentifier) -> Bool { bundleID == AppInfo.bundleID }

    /// First statement of the app's `init` (never under `-visualFixture`, only where `runsMigrationHere`): before any store reads or creates the folder.
    @MainActor static func runAtLaunch() {
        let (outcome, record) = runRecorded(old: AppInfo.legacySupportFolderURL, new: AppInfo.supportFolderURL, lockURL: LegacyLock.launchURL)
        lastOutcome = outcome
        lastRecord = record
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let oldRoot = caches.appendingPathComponent(AppInfo.legacyBundleID, isDirectory: true).appendingPathComponent("ipsw", isDirectory: true)
        let newRoot = IPSWPartialStore.defaultRoot()
        let partials = LegacyLock.withLock(LegacyLock.launchURL) { moveIPSWPartials(oldRoot: oldRoot, newRoot: newRoot) }
        NSLog("[Moonport] data migration: \(outcome), ipsw partials moved: \(partials)")
    }
}

// MARK: - Defaults domain (D3)

enum LegacyDefaultsMigration {
    static let markerKey = "migratedDefaultsFrom"

    /// Copies every key of `source` (the old domain) that `defaults`' own domain does not hold, once: the marker
    /// `migratedDefaultsFrom` makes a second call copy nothing. `ownDomain` names the domain `defaults` writes to; the
    /// presence test reads that domain alone, because `object(forKey:)` also sees the global domain (`AppleLanguages` is
    /// always there, so the menu language would never be copied). The old plist is left untouched. Returns the key count.
    static func copy(from oldDomain: String, into defaults: UserDefaults, ownDomain: String, source: [String: Any]?) -> Int {
        let own = defaults.persistentDomain(forName: ownDomain) ?? [:]
        guard own[markerKey] == nil else { return 0 }
        var copied = 0
        for (key, value) in source ?? [:] where own[key] == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        defaults.set(oldDomain, forKey: markerKey)
        return copied
    }

    /// After the data move and before `AppSettings.shared` is first read.
    static func runAtLaunch() {
        // Only the bundled app has a domain of its own; `swift run` and `swift test` write to the executable's domain.
        guard let own = Bundle.main.bundleIdentifier else { return }
        let n = copy(from: AppInfo.legacyBundleID, into: .standard, ownDomain: own,
                     source: UserDefaults.standard.persistentDomain(forName: AppInfo.legacyBundleID))
        NSLog("[Moonport] defaults migration: \(n) keys copied")
    }
}

// MARK: - Kept archives in ~/Documents (D4)

enum LegacyArchiveMove {
    static let markerKey = "legacyArchivesMoved"
    enum RootState: Equatable { case present, absent, denied }
    enum Outcome: Equatable, Sendable, Codable {
        case notNeeded
        case denied
        case moved(files: Int, kept: Int, failed: Int)
    }

    /// True once the launch started a background move; `task` is that move (Choose… awaits it).
    @MainActor static private(set) var pending = false
    @MainActor static private(set) var task: Task<Outcome, Never>?
    /// D-W9: kept archives in this launch's iPhone records (what the Welcome panel's «N archives» counts).
    @MainActor static private(set) var archiveCount = 0

    /// `lstat`: `ENOENT`/`ENOTDIR` → absent, any other errno (`EPERM`/`EACCES`: Documents access refused) → denied.
    static func rootState(_ url: URL) -> RootState {
        var st = stat()
        if lstat(url.path, &st) == 0 { return .present }
        return errno == ENOENT || errno == ENOTDIR ? .absent : .denied
    }

    /// The synchronous gate: never touches ~/Documents. Marker set → false without evaluating `records`; a custom folder or
    /// no kept archive → false and the marker is set (nothing will ever need moving). `dataMoveIncomplete` (the data move
    /// left files, `iphones.json` among them, in the old folder): false, marker untouched, because the records are not
    /// complete yet and a later launch must still move the archives.
    static func needsMove(archiveFolder: String?, records: @autoclosure () -> [IPhoneDeviceRecord], defaults: UserDefaults,
                          dataMoveIncomplete: Bool = false) -> Bool {
        if defaults.bool(forKey: markerKey) { return false }
        if dataMoveIncomplete { return false }
        if let folder = archiveFolder, !folder.isEmpty { defaults.set(true, forKey: markerKey); return false }
        if !records().contains(where: { !$0.keptArchives.isEmpty }) { defaults.set(true, forKey: markerKey); return false }
        return true
    }

    /// `<Documents>/<old name>/iPhone` → `<Documents>/Moonport/iPhone`, merged per device key. One directory rename when the
    /// new root is absent and on the same volume (and it succeeds), else per file. A same-name file with other bytes stays
    /// in the old root (`kept`): records hold names only, so a renamed copy would be unreachable. `<Documents>/<old name>`
    /// is removed only when empty or holding only `.DS_Store`.
    static func run(oldRoot: URL, newRoot: URL, lockURL: URL, forceCopy: Bool = false,
                    state: (URL) -> RootState = rootState) -> Outcome {
        LegacyLock.withLock(lockURL) {
            switch state(oldRoot) {
            case .absent: return .notNeeded
            case .denied: return .denied
            case .present: break
            }
            let fm = FileManager.default
            guard !ArchiveMigration.isSameFile(oldRoot, newRoot) else { return .notNeeded }
            let parent = newRoot.deletingLastPathComponent()
            var outcome: Outcome?
            if !fm.fileExists(atPath: newRoot.path), !forceCopy {
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                if LegacyTree.sameVolume(oldRoot, parent), (try? fm.moveItem(at: oldRoot, to: newRoot)) != nil {
                    outcome = .moved(files: LegacyTree.regularFileCount(under: newRoot), kept: 0, failed: 0)
                }
            }
            if outcome == nil {
                let r = LegacyTree.moveFiles(old: oldRoot, new: newRoot, forceCopy: forceCopy, parkConflicts: false)
                ArchiveMigration.removeEmptyDirectories(LegacyTree.directories(under: oldRoot) + [oldRoot],
                                                        stopAt: oldRoot.deletingLastPathComponent())
                outcome = .moved(files: r.moved, kept: r.skipped, failed: r.failed)
            }
            removeOldFolderIfEmpty(oldRoot.deletingLastPathComponent())
            return outcome ?? .notNeeded
        }
    }

    private static func removeOldFolderIfEmpty(_ folder: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: folder.path), items.allSatisfy({ $0 == ".DS_Store" }) else { return }
        try? fm.removeItem(at: folder)   // a lone .DS_Store goes with it
    }

    /// Marker rule: set on `.notNeeded` and on `.moved` without failures (a kept conflict cannot be resolved by retrying);
    /// unset on `.denied` and on failures, so the next launch tries again. One log line per run.
    static func finish(_ outcome: Outcome, defaults: UserDefaults) {
        switch outcome {
        case .notNeeded: defaults.set(true, forKey: markerKey)
        case .moved(_, _, let failed): if failed == 0 { defaults.set(true, forKey: markerKey) }
        case .denied: break
        }
        NSLog("[Moonport] archive move: \(outcome)")
    }

    /// Third launch step, after the data folder and the defaults copy (it reads the moved `iphones.json` and the copied
    /// setting). The move itself runs in the background; the prompt for Documents comes from there, not from the main thread.
    @MainActor static func runAtLaunch() {
        let defaults = UserDefaults.standard
        var incomplete = false
        if case .moved(_, _, let failed) = LegacyDataMigration.lastOutcome, failed > 0 { incomplete = true }
        let oldRecords = AppInfo.legacySupportFolderURL.appendingPathComponent(IPhoneStore.defaultURL().lastPathComponent)
        if FileManager.default.fileExists(atPath: oldRecords.path) { incomplete = true }
        guard needsMove(archiveFolder: AppSettings.shared.iphoneArchiveFolder,
                        records: IPhoneStore(url: IPhoneStore.defaultURL()).load(), defaults: defaults,
                        dataMoveIncomplete: incomplete) else { return }
        archiveCount = IPhoneStore(url: IPhoneStore.defaultURL()).load().reduce(0) { $0 + $1.keptArchives.count }
        pending = true
        task = startMove()
    }

    /// The detached move shared by the launch and the retry: same lock, same marker rule.
    @MainActor private static func startMove() -> Task<Outcome, Never> {
        let old = IPhoneStore.legacyDocumentsArchiveRoot(), new = IPhoneStore.defaultArchiveRoot(), lock = LegacyLock.archiveURL
        return Task.detached(priority: .utility) {
            let outcome = run(oldRoot: old, newRoot: new, lockURL: lock)
            finish(outcome, defaults: .standard)
            return outcome
        }
    }

    /// W4/D-W5: once Full Disk Access is granted in the Welcome panel after the launch move ended `.denied`.
    /// Same lock, same marker rule; replaces `task`, so every reader awaits the newest move.
    @MainActor static func retryAfterAccessGranted() -> Task<Outcome, Never>? {
        guard pending, !UserDefaults.standard.bool(forKey: markerKey) else { return nil }
        let t = startMove()
        task = t
        return t
    }
}

// MARK: - The old app bundle (D5)

enum LegacyApp {
    struct Found: Equatable, Sendable { let url: URL }

    /// Where README and `ls-prune.sh` say the app is installed.
    static var candidateDirectories: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
    }

    static func bundleURL(in directory: URL) -> URL {
        directory.appendingPathComponent(AppInfo.legacyAppName + ".app", isDirectory: true)
    }

    /// `CFBundleIdentifier` of the bundle at `url`, read straight from `Contents/Info.plist` (no `Bundle`, no LaunchServices).
    static func bundleID(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    /// The first `<dir>/<old name>.app` among `candidates` (directories, in order) whose plist carries the old bundle ID and
    /// that is not `running` (the bundle this process runs from). Never by name alone.
    static func detect(candidates: [URL], excluding running: URL?) -> Found? {
        let own = running?.resolvingSymlinksInPath().path
        for dir in candidates {
            let app = bundleURL(in: dir)
            guard app.resolvingSymlinksInPath().path != own, bundleID(of: app) == AppInfo.legacyBundleID else { continue }
            return Found(url: app)
        }
        return nil
    }

    static func detect() -> Found? { detect(candidates: candidateDirectories, excluding: Bundle.main.bundleURL) }

    /// The real Trash move: `FileManager.trashItem`, returning the Trash location.
    static func systemTrash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    /// To the Trash, never `removeItem`; returns the Trash location. Throws what the move throws. `move` is
    /// injectable so tests use a temp directory as the "Trash" and never touch the user's real one.
    /// The bundle ID is re-read right before the move: the app may have been replaced since `detect`. Other ID → throws, moves nothing.
    static func trash(_ found: Found, move: (URL) throws -> URL = LegacyApp.systemTrash) throws -> URL {
        guard bundleID(of: found.url) == AppInfo.legacyBundleID else { throw CocoaError(.fileNoSuchFile) }
        return try move(found.url)
    }

    enum RestoreError: Error, Equatable { case originalOccupied, notInTrash }

    /// W5: the Welcome panel's «Undo». Never overwrites: anything at `original` → `.originalOccupied`, nothing moved.
    static func restore(trashed: URL, to original: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: original.path) { throw RestoreError.originalOccupied }
        do { try fm.moveItem(at: trashed, to: original) }
        catch let e as CocoaError where e.code == .fileNoSuchFile || e.code == .fileReadNoSuchFile { throw RestoreError.notInTrash }
    }
}

// MARK: - The one-time notice (D7)

/// What the Welcome panel shows, as a value (built once at launch, or taken from the visual fixture).
struct LegacyNotice: Equatable {
    var moved: Int
    var parked: Int
    var failed: Int
    var archivesMoving: Bool
    var oldApp: URL?
    var oldAppRunning: Bool
    /// The dated `old-app-data-<stamp>` folder this launch's conflicts were moved into (nil when none were).
    var parkedFolder: URL? = nil
    /// Relative paths of the parked conflicts / of the files left in the old folder (D-W6), for the «Show» buttons.
    var parkedFiles: [String] = []
    var failedFiles: [String] = []
    /// Kept archives of the launch's iPhone records (0 unless `archivesMoving`).
    var archiveCount = 0
    /// Amendment 4: the archive move's outcome when an earlier launch already knows it (a re-shown panel); nil = ask the live task.
    var archiveKnown: LegacyArchiveMove.Outcome? = nil

    /// D-W1, one line: a notice only when the panel was not shown before (`shown`) AND this launch's data migration moved,
    /// parked or left a file. `.nothing` shows it only from a `pending` file, never because of the old app alone (Settings › About offers the Trash).
    /// The old-app step is present when the old app exists and "Keep" was not chosen (`dismissed`).
    /// Amendment 4: with outcome `.nothing` and a `pending` file (an earlier launch showed the panel and the user never closed
    /// it) the panel shows again from that file with the live state laid over it (`WelcomePending.notice`).
    static func make(outcome: LegacyDataMigration.Outcome, archivesMoving: Bool, oldApp: LegacyApp.Found?,
                     running: Bool, dismissed: Bool, parkedFolder: URL? = nil, shown: Bool = false, archiveCount: Int = 0,
                     record: LegacyDataMigration.MoveRecord = .init(), pending: WelcomePending? = nil,
                     legacySupport: URL = AppInfo.legacySupportFolderURL) -> LegacyNotice? {
        guard !shown else { return nil }
        let app = dismissed ? nil : oldApp
        switch outcome {
        case .moved(let files, let parked, let failed):
            return LegacyNotice(moved: files, parked: parked, failed: failed, archivesMoving: archivesMoving,
                                oldApp: app?.url, oldAppRunning: app != nil && running,
                                parkedFolder: parked > 0 ? (record.parkFolder ?? parkedFolder) : nil,
                                parkedFiles: record.parked, failedFiles: record.failed,
                                archiveCount: archivesMoving ? archiveCount : 0)
        case .nothing:
            return pending?.notice(oldApp: app?.url, oldAppRunning: running, liveArchiveMove: archivesMoving,
                                   liveArchiveCount: archiveCount, legacySupport: legacySupport)
        }
    }
}

/// Pure rules of the Welcome panel's progress (W4, W7, D-W8), kept out of the view so tests reach them.
enum WelcomeProgress {
    enum ArchiveRow: Equatable { case busy, done, left(Int), denied }
    enum DoneCaption: Equatable { case progress(done: Int, total: Int), allInPlace, withNotes }

    /// D-W8: nil = the move has not answered yet.
    static func archiveRow(_ o: LegacyArchiveMove.Outcome?) -> ArchiveRow {
        switch o {
        case nil: return .busy
        case .notNeeded?: return .done
        case .denied?: return .denied
        case .moved(_, let kept, let failed)?: return kept + failed > 0 ? .left(kept + failed) : .done
        }
    }

    /// The caption right of the «Done automatically» label. `archive == nil` means no archive row.
    static func doneCaption(dataShown: Bool, archive: ArchiveRow?, failed: Int) -> DoneCaption {
        switch archive {
        case .busy?, .denied?:
            return .progress(done: dataShown ? 1 : 0, total: (dataShown ? 1 : 0) + 1)
        case .left?:
            return .withNotes
        default:
            return failed > 0 ? .withNotes : .allInPlace
        }
    }

    /// Required steps still open: Full Disk Access and, when the old app is offered, the decision about it.
    static func remaining(fdaGranted: Bool, hasOldApp: Bool, oldAppDecided: Bool) -> Int {
        (fdaGranted ? 0 : 1) + (hasOldApp && !oldAppDecided ? 1 : 0)
    }

    /// W4/D-W5: re-run the archive move once, when Full Disk Access arrives after a denied launch move.
    static func shouldRetryArchives(fdaGranted: Bool, outcome: LegacyArchiveMove.Outcome?, retried: Bool) -> Bool {
        fdaGranted && outcome == .denied && !retried
    }
}
