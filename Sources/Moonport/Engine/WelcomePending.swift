// Engine/WelcomePending.swift
// MOONPORT-RENAME amendment 4 (item 2): the Welcome panel's content of the launch that decided to show it, kept in
// `Application Support/Moonport/welcome-pending.json` until the user closes the panel («Later», «Done», Esc). The shown
// flag is written only then. Any other end of the process (a Full Disk Access relaunch, Cmd-Q, a crash) leaves the file,
// and the next launch shows the panel again from it, with the live state (FDA probe, old-app detection, archive move).
// Foundation only; every function takes its URL, tests pass a temp one and never the real file.
import Foundation
import os

struct WelcomePending: Codable, Equatable, Sendable {
    /// Bumped when a field changes meaning. A file of another version reads as absent.
    static let currentVersion = 1
    /// Small on purpose: counts, two capped relative-path lists and the park folder. Nothing about the old app (re-detected live).
    var version = WelcomePending.currentVersion
    var moved: Int
    var parked: Int
    var failed: Int
    var archivesMoving: Bool
    var archiveCount: Int
    /// The archive move's outcome once known; filled in by `updateArchive` when the move ends after the panel was decided.
    var archive: LegacyArchiveMove.Outcome?
    var parkedFolderPath: String?
    var parkedFiles: [String]
    var failedFiles: [String]

    init(_ notice: LegacyNotice) {
        moved = notice.moved
        parked = notice.parked
        failed = notice.failed
        archivesMoving = notice.archivesMoving
        archiveCount = notice.archiveCount
        archive = notice.archiveKnown
        parkedFolderPath = notice.parkedFolder?.path
        parkedFiles = notice.parkedFiles
        failedFiles = notice.failedFiles
    }

    static var defaultURL: URL { AppInfo.supportFolderURL.appendingPathComponent("welcome-pending.json") }

    // MARK: File

    /// Paths already reported as unreadable, so one launch logs a bad file once (both `willShowAtLaunch` and `atLaunch` read it).
    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Absent → nil, silently. Unreadable, not JSON, another version → nil and one log line per path and process. Never throws.
    static func load(_ url: URL) -> WelcomePending? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let value = try JSONDecoder().decode(WelcomePending.self, from: Data(contentsOf: url))
            if value.version == currentVersion { return value }
            report(url, "version \(value.version)")
        } catch {
            report(url, "\(error)")
        }
        return nil
    }

    private static func report(_ url: URL, _ why: String) {
        let first = reported.withLock { $0.insert(url.path).inserted }
        if first { NSLog("[Moonport] welcome-pending.json ignored (\(why))") }
    }

    /// Replaces the file atomically. A failure is logged and swallowed: the panel then simply does not come back after a relaunch.
    @discardableResult
    func write(to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("[Moonport] welcome-pending.json not written: \(error)")
            return false
        }
    }

    static func delete(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch { NSLog("[Moonport] welcome-pending.json not deleted: \(error)") }
    }

    /// The archive move ended after the file was written: record its outcome. No file (the panel was already closed) → no-op.
    static func updateArchive(_ outcome: LegacyArchiveMove.Outcome, at url: URL) {
        guard var value = load(url) else { return }
        value.archive = outcome
        value.write(to: url)
    }

    // MARK: Re-show

    /// The notice of a later launch, with the live state laid over the stored one.
    /// - Conflict and failed rows keep only the files that still exist (`parkedFolderPath/<rel>`, `legacySupport/<rel>`); each
    ///   file gone from a recorded list lowers the count by one (the lists are complete up to 50 entries), and a row with none
    ///   left disappears. A park folder that is gone drops the conflict row.
    /// - Archive row: when this launch started an archive move (`liveArchiveMove`) the panel follows that move (busy, then its
    ///   outcome); otherwise the stored outcome. A move that was running when the app went away has no stored outcome and, with
    ///   no live move either, finished and set its marker: shown as done.
    func notice(oldApp: URL?, oldAppRunning: Bool, liveArchiveMove: Bool, liveArchiveCount: Int, legacySupport: URL,
                fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> LegacyNotice {
        var parkedLeft = parked
        var parkedKept = parkedFiles
        var folder = parkedFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if parked > 0, let f = folder {
            parkedKept = parkedFiles.filter { fileExists(f.appendingPathComponent($0)) }
            parkedLeft = max(0, parked - (parkedFiles.count - parkedKept.count))
            if !fileExists(f) { parkedLeft = 0; parkedKept = [] }
        }
        if parkedLeft == 0 { folder = nil; parkedKept = [] }

        let failedKept = failedFiles.filter { fileExists(legacySupport.appendingPathComponent($0)) }
        let failedLeft = max(0, failed - (failedFiles.count - failedKept.count))

        let moving = liveArchiveMove || archivesMoving
        let known: LegacyArchiveMove.Outcome? = liveArchiveMove ? nil : (archive ?? (archivesMoving ? .notNeeded : nil))
        return LegacyNotice(moved: moved, parked: parkedLeft, failed: failedLeft, archivesMoving: moving,
                            oldApp: oldApp, oldAppRunning: oldApp != nil && oldAppRunning,
                            parkedFolder: folder, parkedFiles: parkedKept, failedFiles: failedKept,
                            archiveCount: moving ? (liveArchiveMove ? liveArchiveCount : archiveCount) : 0,
                            archiveKnown: known)
    }
}
