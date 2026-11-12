// Tests/MoonportTests/WelcomePendingTests.swift
// MOONPORT-RENAME amendment 4: the Welcome panel comes back after a launch that ended without the user closing it
// (`welcome-pending.json`, shown flag written only on close), and no test touches the real launch locks.
// Temp dirs and isolated defaults suites only: the real Application Support, Trash and defaults are never read or written.
import Foundation
import Observation
import Synchronization
import Testing
@testable import Moonport

extension SerialTests {
    @MainActor struct WelcomePendingTests {
        private let fm = FileManager.default

        private func tempDir() -> URL {
            let dir = fm.temporaryDirectory.appendingPathComponent("wp-\(UUID().uuidString)", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        private func touch(_ url: URL) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }

        private let moved = LegacyDataMigration.Outcome.moved(files: 7, parked: 2, failed: 2)
        private let app = LegacyApp.Found(url: URL(fileURLWithPath: "/Applications/Old.app"))

        /// A first-launch notice with every list filled, as `LegacyNotice.make` builds it.
        private func firstNotice(parkFolder: URL, archivesMoving: Bool = true) -> LegacyNotice {
            let record = LegacyDataMigration.MoveRecord(parkFolder: parkFolder, parked: ["a.json", "b/c.json"], failed: ["x.json", "y/z.json"])
            return LegacyNotice.make(outcome: moved, archivesMoving: archivesMoving, oldApp: app, running: false, dismissed: false,
                                     archiveCount: 3, record: record)!
        }

        // MARK: Appearance truth table (flag, pending file, outcome)

        @Test func flagUnsetAndPendingPresentShowsAgain() throws {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let s = AppSettings(defaults: d)
            let url = dir.appendingPathComponent("welcome-pending.json")
            #expect(WelcomePending(firstNotice(parkFolder: dir)).write(to: url))
            #expect(LegacyNotice.willShowAtLaunch(settings: s, pendingURL: url), "outcome .nothing, flag unset, file present: the panel returns")
            let n = LegacyNotice.make(outcome: .nothing, archivesMoving: false, oldApp: app, running: false, dismissed: false,
                                      pending: WelcomePending.load(url))
            #expect(n?.moved == 7 && n?.oldApp == app.url)
        }

        @Test func flagSetNeverShowsEvenWithAPendingFile() throws {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let s = AppSettings(defaults: d)
            let url = dir.appendingPathComponent("welcome-pending.json")
            WelcomePending(firstNotice(parkFolder: dir)).write(to: url)
            s.welcomeShown = true
            #expect(!LegacyNotice.willShowAtLaunch(settings: s, pendingURL: url))
            #expect(LegacyNotice.make(outcome: .nothing, archivesMoving: false, oldApp: nil, running: false, dismissed: false,
                                      shown: true, pending: WelcomePending.load(url)) == nil)
            #expect(LegacyNotice.make(outcome: moved, archivesMoving: false, oldApp: nil, running: false, dismissed: false,
                                      shown: true, pending: WelcomePending.load(url)) == nil)
        }

        @Test func noPendingAndNothingMovedShowsNoPanel() {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let url = dir.appendingPathComponent("welcome-pending.json")
            #expect(!LegacyNotice.willShowAtLaunch(settings: AppSettings(defaults: d), pendingURL: url))
            #expect(LegacyNotice.make(outcome: .nothing, archivesMoving: true, oldApp: app, running: false, dismissed: false,
                                      pending: WelcomePending.load(url)) == nil, "old app alone or a running archive move never opens it")
        }

        @Test func aFreshMovedOutcomeBeatsTheStoredOne() {
            let stored = WelcomePending(firstNotice(parkFolder: URL(fileURLWithPath: "/nowhere")))
            let n = LegacyNotice.make(outcome: .moved(files: 1, parked: 0, failed: 0), archivesMoving: false, oldApp: nil,
                                      running: false, dismissed: false, pending: stored)
            #expect(n?.moved == 1, "this launch moved something new: its own numbers, not the stored ones")
        }

        // MARK: Round trip and the file

        @Test func pendingRoundTripsAndStaysSmall() throws {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let url = dir.appendingPathComponent("sub/welcome-pending.json")   // the folder is created
            var notice = firstNotice(parkFolder: dir.appendingPathComponent("old-app-data-1"))
            notice.archiveKnown = .moved(files: 4, kept: 1, failed: 0)
            let p = WelcomePending(notice)
            #expect(p.write(to: url))
            #expect(WelcomePending.load(url) == p)
            #expect(p.archive == .moved(files: 4, kept: 1, failed: 0))
            #expect(try Data(contentsOf: url).count < 2048)
            #expect(try fm.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == ["welcome-pending.json"], "atomic write leaves no temp file")
        }

        @Test func updateArchiveRecordsTheOutcomeOnlyWhileTheFileExists() {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let url = dir.appendingPathComponent("welcome-pending.json")
            WelcomePending.updateArchive(.denied, at: url)
            #expect(!fm.fileExists(atPath: url.path), "panel already closed: nothing is recreated")
            WelcomePending(firstNotice(parkFolder: dir)).write(to: url)
            #expect(WelcomePending.load(url)?.archive == nil)
            WelcomePending.updateArchive(.denied, at: url)
            #expect(WelcomePending.load(url)?.archive == .denied)
            WelcomePending.delete(url)
            WelcomePending.delete(url)   // a second delete is harmless
            #expect(!fm.fileExists(atPath: url.path))
        }

        // MARK: Live state over the stored one

        @Test func staleConflictAndFailedRowsDropOut() {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let park = dir.appendingPathComponent("park"), legacy = dir.appendingPathComponent("legacy")
            let p = WelcomePending(firstNotice(parkFolder: park))
            func show() -> LegacyNotice {
                p.notice(oldApp: nil, oldAppRunning: false, liveArchiveMove: false, liveArchiveCount: 0, legacySupport: legacy)
            }
            let none = show()
            #expect(none.parked == 0 && none.parkedFolder == nil && none.parkedFiles.isEmpty, "park folder gone: the row goes")
            #expect(none.failed == 0 && none.failedFiles.isEmpty, "no failed file left: the row goes")
            #expect(none.moved == 7, "the moved count is history and stays")

            touch(park.appendingPathComponent("a.json")); touch(legacy.appendingPathComponent("y/z.json"))
            let some = show()
            #expect(some.parked == 1 && some.parkedFiles == ["a.json"] && some.parkedFolder?.path == park.path)
            #expect(some.failed == 1 && some.failedFiles == ["y/z.json"])

            touch(park.appendingPathComponent("b/c.json")); touch(legacy.appendingPathComponent("x.json"))
            let all = show()
            #expect(all.parked == 2 && all.failed == 2, "nothing resolved: the stored counts")
        }

        @Test func oldAppAndArchiveRowFollowTheLiveState() {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            var stored = firstNotice(parkFolder: dir)
            stored.archiveKnown = .moved(files: 4, kept: 1, failed: 0)
            let p = WelcomePending(stored)
            func show(live: Bool, count: Int = 0, oldApp: URL? = nil, running: Bool = false) -> LegacyNotice {
                p.notice(oldApp: oldApp, oldAppRunning: running, liveArchiveMove: live, liveArchiveCount: count, legacySupport: dir)
            }
            let gone = show(live: false)
            #expect(gone.oldApp == nil && !gone.oldAppRunning, "old app gone: no step")
            #expect(gone.archivesMoving && gone.archiveKnown == .moved(files: 4, kept: 1, failed: 0) && gone.archiveCount == 3, "stored outcome")
            #expect(show(live: false, oldApp: app.url, running: true).oldAppRunning, "re-detected live")
            let retry = show(live: true, count: 5)
            #expect(retry.archivesMoving && retry.archiveKnown == nil && retry.archiveCount == 5, "a move running now: the panel follows it")

            var unknown = stored; unknown.archiveKnown = nil
            #expect(WelcomePending(unknown).notice(oldApp: nil, oldAppRunning: false, liveArchiveMove: false, liveArchiveCount: 0,
                                                   legacySupport: dir).archiveKnown == .notNeeded,
                    "the move ended while the app was away: done, never busy forever")
            let noMove = WelcomePending(firstNotice(parkFolder: dir, archivesMoving: false))
            let n = noMove.notice(oldApp: nil, oldAppRunning: false, liveArchiveMove: false, liveArchiveCount: 0, legacySupport: dir)
            #expect(!n.archivesMoving && n.archiveKnown == nil && n.archiveCount == 0, "no archive row when no move ever started")
        }

        // MARK: Corrupt file

        @Test func corruptOrUnreadablePendingReadsAsAbsent() throws {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let s = AppSettings(defaults: d)
            let url = dir.appendingPathComponent("welcome-pending.json")
            try Data("{ not json".utf8).write(to: url)
            #expect(WelcomePending.load(url) == nil)
            #expect(!LegacyNotice.willShowAtLaunch(settings: s, pendingURL: url), "a corrupt file never holds the launch gate")
            try Data("{\"version\":1}".utf8).write(to: url)   // valid JSON, fields missing
            #expect(WelcomePending.load(url) == nil)
            var future = WelcomePending(firstNotice(parkFolder: dir)); future.version = 99
            future.write(to: url)
            #expect(WelcomePending.load(url) == nil, "another version")
            try fm.removeItem(at: url)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)   // a directory in its place
            #expect(WelcomePending.load(url) == nil)
            #expect(LegacyNotice.make(outcome: .nothing, archivesMoving: false, oldApp: app, running: false, dismissed: false,
                                      pending: WelcomePending.load(url)) == nil)
        }

        // MARK: Claim release (review a4 finding 2)

        /// A second window seeded while the first held the claim observes the release (no polling) and re-asks.
        @Test func releasingTheClaimIsObservable() throws {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let s = AppSettings(defaults: d)
            let url = dir.appendingPathComponent("welcome-pending.json")
            WelcomePending(firstNotice(parkFolder: dir)).write(to: url)
            let first = LegacyNotice.atLaunch(settings: s, pendingURL: url)
            #expect(first != nil && WelcomeClaim.shared.claimed)
            #expect(LegacyNotice.atLaunch(settings: s, pendingURL: url) == nil, "the second window gets none while claimed")
            let fired = Mutex(false)
            withObservationTracking { _ = WelcomeClaim.shared.claimed } onChange: { fired.withLock { $0 = true } }
            LegacyNotice.releaseClaim()
            #expect(fired.withLock { $0 } && !WelcomeClaim.shared.claimed)
            #expect(LegacyNotice.atLaunch(settings: s, pendingURL: url) != nil, "after the release the next window claims it")
            LegacyNotice.releaseClaim()
        }

        // MARK: Closing the panel

        @Test func closingWritesTheFlagAndDeletesThePendingFile() {
            let dir = tempDir(); defer { try? fm.removeItem(at: dir) }
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let s = AppSettings(defaults: d)
            let url = dir.appendingPathComponent("welcome-pending.json")
            WelcomePending(firstNotice(parkFolder: dir)).write(to: url)
            #expect(!s.welcomeShown && fm.fileExists(atPath: url.path), "decided but not closed: flag unset, file kept")
            LegacyNotice.markShown(settings: s, pendingURL: url)
            #expect(s.welcomeShown && AppSettings(defaults: d).welcomeShown)
            #expect(!fm.fileExists(atPath: url.path))
            #expect(!LegacyNotice.willShowAtLaunch(settings: s, pendingURL: url))
        }

        // MARK: Test isolation of the launch locks (item 3)

        /// The two launch lock URLs of `LegacyLock` live in the shared temp directory, where a running Moonport holds them. A
        /// test that reaches them blocks in `flock` for as long as the app's move runs. Every test passes its own lock URL.
        @Test func noTestUsesTheRealLaunchLocks() throws {
            let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            let hook = try NSRegularExpression(pattern: #"LegacyLock\.(launch|archive)URL|moonport-(migration|archive-move)\.lock"#)
            var offenders: [String] = []
            for name in try fm.contentsOfDirectory(atPath: testsDir.path) where name.hasSuffix(".swift") {
                let text = try String(contentsOf: testsDir.appendingPathComponent(name), encoding: .utf8)
                if hook.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { offenders.append(name) }
            }
            #expect(offenders.isEmpty, "tests must inject their own lock URL: \(offenders)")
        }
    }
}
