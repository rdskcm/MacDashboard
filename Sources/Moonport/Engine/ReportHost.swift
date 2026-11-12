// Engine/ReportHost.swift
// ARCH-MODEL-SPLIT step 0: how a feature controller reaches the coordinator's report without a back-reference.
// Every section cluster does the same things: read the report, land its own section after the in-flight pass
// has committed (`afterPass`), and (some) re-assess. The coordinator builds one ReportHost; controllers keep it as a `let`.
// One struct, grown per block of the series; never a protocol.
import Foundation

struct ReportHost {
    /// The current `report` — a partial while a pass is in flight; never assess it (assessment-complete-collect).
    var read: @MainActor () -> FullReport
    /// Mutates the current `report` in place. Fires an observation mutation even if nothing changed:
    /// prefer `write(_:_:)` for a single field; use this only for multi-field writes.
    var update: @MainActor ((inout FullReport) -> Void) -> Void
    /// True while a `refreshReport()` pass is in flight (`isCollectingReport`).
    var isCollecting: @MainActor () -> Bool
    /// Runs `work` at once when no pass is in flight; otherwise queues it to run synchronously at the end of the
    /// in-flight pass — after its commit (`report = final` and the commit assessment), before a coalesced pending
    /// pass starts — in the order queued. Dropped, never run, when the pass is cancelled (`AppModel.stop()`).
    /// `work` is an updater's whole landing — its section write, its `reassess()` and its stamps — so they apply
    /// together or not at all (PASS-WAIT-PARTIAL). `work` must not start a report pass.
    var afterPass: @MainActor (_ work: @escaping @MainActor () -> Void) -> Void
    /// Re-assesses the committed report (`homeReport`), never a partial.
    var reassess: @MainActor () -> Void
    /// True while no effectively visible window is frontmost (`AppModel.isPaused`, set by AppActivityMonitor):
    /// loops skip spawning commands (`no-unseen-work`).
    var isPaused: @MainActor () -> Bool
    /// Re-reads the Claude backup log (`AppModel.refreshClaudeBackup()`); the Backups page shows both backups.
    var refreshClaudeBackup: @MainActor () async -> Void
    /// IDLE-WORK-TRIM: the next fast tick re-reads free space (`AppModel.requestDiskRead()`); a controller calls it after
    /// an action of its own changed free space (TimeMachineController's snapshot deletion).
    var requestDiskRead: @MainActor () -> Void

    /// Re-applies the background overlays (update check, folder sizes) to the shown report — and, mid-pass, to the
    /// committed one — and re-assesses the committed report (`AppModel.mergeBackgroundIntoCommitted()`, V2-HEADER-CHURN).
    var mergeBackgroundIntoCommitted: @MainActor () -> Void
    /// Starts an attempt of a data block (`AppModel.beginBlock`). `armsWatchdog`: arm the block's `id.timeout`
    /// watchdog; false = mark the attempt with no watchdog and leave an armed one alone (REDESIGN-STORAGE D5).
    var beginBlock: @MainActor (_ id: BlockID, _ showsLoading: Bool, _ armsWatchdog: Bool) -> Void
    /// Ends the attempt with a success now and disarms its watchdog.
    var succeedBlock: @MainActor (_ id: BlockID) -> Void
    /// Ends the attempt with `failure` and disarms its watchdog.
    var failBlock: @MainActor (_ id: BlockID, _ failure: BlockFailure) -> Void

    /// Publishes a user-facing error message on the coordinator (`lastError`). The history save reports a failed write
    /// through it (ARCH-MODEL-SPLIT block 8).
    var reportError: @MainActor (String) -> Void

    /// Writes one field only when it differs from the current value, so an unchanged re-read costs no
    /// observation mutation (the guard every section writer has today, e.g. `if report.energy != settings`).
    @MainActor
    func write<T: Equatable>(_ keyPath: WritableKeyPath<FullReport, T>, _ value: T) {
        if read()[keyPath: keyPath] != value { update { $0[keyPath: keyPath] = value } }
    }
}

/// Lets closures created inside the coordinator's `init` reach it once it exists: Swift forbids capturing `self`
/// before every stored property is initialised, and the controllers are stored properties.
@MainActor
final class CoordinatorLink {
    weak var model: AppModel?
    init() {}
}
