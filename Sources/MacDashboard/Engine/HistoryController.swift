// Engine/HistoryController.swift
// ARCH-MODEL-SPLIT block 8: the History feature, moved out of the coordinator unchanged in behaviour — the day-by-day
// history file (`mac_check_state.json`, HistoryStore), the daily snapshot a completed report pass writes
// (REDESIGN-SETTINGS schedule), the History page's Refresh / Try again, the «History started over» notice
// (HISTORY-UNREADABLE-NOTICE) and the Home History tile's digest. Owns no Task: every operation is synchronous
// main-actor work on a ~50 KB file, as before. Reaches the coordinator only through ReportHost.reportError.
import Foundation
import Observation

@MainActor
@Observable
final class HistoryController {
    struct Dependencies {
        /// The history file; the coordinator passes `mac_check_state.json` in its data folder, tests a temp-folder file.
        var fileURL: URL
        /// The daily snapshot time (`AppSettings.snapshotMinutes`) and the last snapshot's time (`AppSettings.lastSnapshotAt`).
        var snapshotMinutes: @MainActor () -> Int
        var lastSnapshotAt: @MainActor () -> Date?
        var setLastSnapshotAt: @MainActor (Date) -> Void

        /// A function, not a `static let`: the data folder and the settings come from the coordinator.
        static func live(directory: URL, settings: AppSettings) -> Dependencies {
            Dependencies(
                fileURL: directory.appendingPathComponent("mac_check_state.json"),
                snapshotMinutes: { settings.snapshotMinutes },
                lastSnapshotAt: { settings.lastSnapshotAt },
                setLastSnapshotAt: { settings.lastSnapshotAt = $0 })
        }
    }

    /// The history as last loaded or saved. The History page, the Battery page's capacity history and the fixtures read it.
    private(set) var state: HistoryState {
        didSet { homeDigest = HomeModel.historyDigest(state.mac_history) }
    }
    /// History figures for the Home History tile, recomputed only when `state` changes (not on live ticks).
    private(set) var homeDigest = HomeHistoryDigest.empty
    /// REDESIGN-HISTORY: the last load found a file that exists but cannot be read as a history object
    /// (`HistoryStore.fileUnreadable`); the History page shows its error block until a reload or a save clears it.
    private(set) var unreadable = false
    /// REDESIGN-HISTORY: `refreshNow()` in flight (the read takes milliseconds; the flag exists for the
    /// button's swap-in-place label and the visual fixture).
    private(set) var refreshing = false

    /// The app is the only writer of the history file; this instance is loaded at init and re-read only by `refreshNow()`.
    private let store: HistoryStore
    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies) {
        self.host = host; self.time = time; self.deps = deps
        // Loaded synchronously so the History card has data as soon as the window appears (an empty HistoryState on
        // first run is fine — HistoryStore.load() never throws).
        let store = HistoryStore(url: deps.fileURL)
        self.store = store
        let loaded = store.load()
        state = loaded
        homeDigest = HomeModel.historyDigest(loaded.mac_history)
        unreadable = store.fileUnreadable
    }

    // MARK: - Report pass (coordinator → controller)

    /// A report pass committed `report`: writes today's snapshot when the daily schedule is due, then republishes the
    /// store's state. A failed write is reported and the schedule is stamped anyway (unchanged behaviour); the next
    /// successful save persists the in-memory entry.
    func passCommitted(_ report: FullReport, live: LiveSnapshot) {
        let now = time.now()
        if SnapshotSchedule.isDue(now: now, last: deps.lastSnapshotAt(), minutesAfterMidnight: deps.snapshotMinutes()) {
            store.upsertToday(from: report, live: live)
            do { try store.save() } catch { host.reportError(L.errorHistorySaveFailed(error.localizedDescription)) }
            deps.setLastSnapshotAt(now)
        }
        state = store.state
        unreadable = store.fileUnreadable
    }

    // MARK: - History page

    /// REDESIGN-HISTORY: the History page's Refresh and the error block's Try again. Re-reads the file synchronously
    /// (the file is ~50 KB) — a file restored from a backup or made readable again shows at once. Never writes.
    func refreshNow() {
        guard !refreshing else { return }
        refreshing = true
        state = store.load()
        unreadable = store.fileUnreadable
        refreshing = false
    }

    /// Display path of the history file for the error block («~/Library/Application Support/MacDashboard/mac_check_state.json»).
    var filePath: String { (deps.fileURL.path as NSString).abbreviatingWithTildeInPath }

    // MARK: - History restart notice (HISTORY-UNREADABLE-NOTICE)

    /// Where the notice's Finder button points: the kept unreadable file, or the folder it was kept in if the user has
    /// since moved or deleted it. nil when there is no notice. Stats the disk — call it from the button action only,
    /// never from a view body.
    var restartRevealPath: String? {
        guard let name = state.unreadable_backup else { return nil }
        let dir = deps.fileURL.deletingLastPathComponent()
        let file = dir.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: file) ? file : dir.path
    }

    /// The user hid the notice: forget it and persist that now, so it stays hidden after a relaunch. If the write fails
    /// the notice is still hidden for this session, and the next completed pass's save persists the change.
    func dismissRestartNotice() {
        store.clearUnreadableBackup()
        do { try store.save() } catch { host.reportError(L.errorHistorySaveFailed(error.localizedDescription)) }
        state = store.state
    }

    // MARK: - Fixtures

    /// Visual fixture and snapshot tests only: replaces the shown history (the digest follows).
    func applyFixture(_ state: HistoryState) { self.state = state }
    /// Visual fixture only (REDESIGN-HISTORY): the unreadable-file and reload-in-flight flags.
    func applyFixture(unreadable: Bool, refreshing: Bool) { self.unreadable = unreadable; self.refreshing = refreshing }
}
