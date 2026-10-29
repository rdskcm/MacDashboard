// Engine/StartupItemsController.swift
// ARCH-MODEL-SPLIT block 3: the System page's Startup items (Автозагрузка) state, moved out of the coordinator
// unchanged in behaviour. Owns «Check for stale» (REDESIGN-SYSTEM), the single and bulk orphan-plist deletes
// (V2-DESTRUCTIVE-UX) and their Task handles.
import Foundation
import Observation

@MainActor
@Observable
final class StartupItemsController {
    struct Dependencies {
        /// `ReportCollector().collectAutostartInfo()` — a fresh collector per call, never shared with a sampler.
        var collect: @MainActor () async -> AutostartInfo
        /// Moves one user-level plist (~/Library/LaunchAgents) to the Trash: reversible, and an already-loaded job
        /// stays loaded until relogin/reboot.
        var trash: @MainActor (_ path: String) async -> PlistDeleteOutcome
        /// One privileged `launchctl bootout` (errors ignored) + `rm -f` of every system-level path
        /// (`PrivilegedRunner.removeStartupItemsCommand`; Touch ID / admin password, 30 s): one prompt per call.
        var removePrivileged: @MainActor (_ paths: [String]) async -> PlistDeleteOutcome

        static let live = Dependencies(
            collect: { await ReportCollector().collectAutostartInfo() },
            trash: { path in
                await StartupItemsController.onUtilityThread {
                    do {
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                        return .success
                    } catch {
                        return .failed(error.localizedDescription)
                    }
                }
            },
            removePrivileged: { paths in
                let command = PrivilegedRunner.removeStartupItemsCommand(paths: paths, uid: getuid())
                return await StartupItemsController.onUtilityThread {
                    StartupItemsController.plistOutcome(PrivilegedRunner.run(command))
                }
            })
    }

    /// «Check for stale»: a re-scan of the startup items is running. A second press while it runs is ignored.
    private(set) var checking = false
    /// When the last «Check for stale» finished; stale marks are shown only once this is set.
    private(set) var checkedAt: Date? = nil
    /// Items removed on the card since the last check.
    private(set) var removedCount = 0
    /// Paths of orphaned plists being deleted: a row's Delete button shows a spinner and stays disabled while its
    /// own delete is in flight, without blocking other rows.
    private(set) var deletingPaths: Set<String> = []
    /// Set when the last delete failed, was cancelled or timed out; cleared at the start of the next delete and by
    /// `clearDeleteFailure()`. Shown as an inline note on the card.
    private(set) var deleteFailure: PrivilegedActionFailure? = nil
    /// Paths whose most recent delete did NOT remove the file (prompt dismissed, file op failed, path rejected, or
    /// outcome unknown). Accumulates until `acknowledgeRestore(_:)` drains it — see `PlistDeleteRestoreSignal`.
    /// No view reads it today.
    private(set) var deleteRestore = PlistDeleteRestoreSignal()

    /// The in-flight «Check for stale»; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var checkTask: Task<Void, Never>?
    /// Every in-flight delete (single or bulk), keyed by start order. Each Task drops its own entry when it ends;
    /// `stop()` cancels them all. Tests snapshot and await them.
    @ObservationIgnored private(set) var deleteTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextDeleteID = 0

    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies = .live) {
        self.host = host; self.time = time; self.deps = deps
    }

    // MARK: - Check for stale

    /// «Check for stale» (REDESIGN-SYSTEM): re-collects the autostart section, waits for any report pass, writes it,
    /// then reveals the stale marks. A second press while a check runs is ignored.
    func checkStaleNow() {
        guard !checking else { return }
        checking = true
        checkTask = Task { [weak self] in
            guard let self else { return }
            defer { self.checking = false }
            let info = await self.deps.collect()
            guard !Task.isCancelled else { return }
            // A pass in flight would overwrite this section with its own (older) scan when it commits.
            _ = await self.host.awaitPassEnd()
            guard !Task.isCancelled else { return }
            self.host.write(\.autostart, info as AutostartInfo?)
            self.checkedAt = self.time.now()
            self.removedCount = 0
        }
    }

    // MARK: - Delete

    /// Deletes one orphaned launchd .plist found by «Check for stale». `isSystemLevel` selects the path:
    /// user level (~/Library/LaunchAgents) goes to the Trash (reversible, does not unload a loaded job);
    /// system level (/Library/LaunchAgents|LaunchDaemons) is a permanent `launchctl bootout` + `rm` through one
    /// privileged call. On success the row is dropped from `report.autostart` locally (`removeLocally`), without a
    /// full report recollect.
    func deleteOrphan(path: String, isSystemLevel: Bool) {
        // A delete for this path is already in flight and owns the outcome —
        // signalling here would restore a row whose delete may still succeed.
        guard !deletingPaths.contains(path) else { return }
        guard LaunchdPlistInspector.isValidDeletionTarget(path: path, isSystemLevel: isSystemLevel) else {
            deleteFailure = .error(L.autostartDeleteInvalidPath)
            signalNotDeleted([path])
            return
        }
        deletingPaths.insert(path)
        deleteFailure = nil

        track { [weak self] in
            guard let self else { return }
            defer { self.deletingPaths.remove(path) }

            let outcome = isSystemLevel ? await self.deps.removePrivileged([path]) : await self.deps.trash(path)
            // An unknown outcome must never read as "deleted": put the row back. If the
            // file op did land, the next report refresh drops it again — showing a row
            // that no longer exists is recoverable, hiding one that does is not.
            guard !Task.isCancelled else {
                self.signalNotDeleted([path])
                return
            }

            switch outcome {
            case .success:
                self.removeLocally([path])
            case .cancelled:
                self.deleteFailure = .cancelled
                self.signalNotDeleted([path])
            case .timedOut:
                self.deleteFailure = .timedOut
                self.signalNotDeleted([path])
            case .failed(let msg):
                self.deleteFailure = .error(msg)
                self.signalNotDeleted([path])
            }
        }
    }

    /// Bulk variant of `deleteOrphan` («Delete all»). Trashes user-level (~/Library) plists first, each on its own,
    /// so one failure does not block the rest; THEN — if any system-level (/Library) paths survive validation —
    /// makes exactly one privileged call for all of them, so the batch costs a single Touch ID/admin prompt.
    /// A cancelled or failed system-level call never hides the user-level paths that already succeeded: every
    /// row's spinner is cleared and a combined error (if any) is reported once.
    func deleteOrphans(paths: [String]) {
        let batch = paths.filter { path in
            guard !deletingPaths.contains(path) else { return false }
            let isSystemLevel = path.hasPrefix("/Library/")
            return LaunchdPlistInspector.isValidDeletionTarget(path: path, isSystemLevel: isSystemLevel)
        }
        // Paths the card already collapsed that this call will never touch:
        // validation rejected them. Paths excluded because a delete is already in
        // flight are NOT signalled — that call owns their outcome.
        let inFlight = paths.filter { deletingPaths.contains($0) }
        let rejected = Set(paths).subtracting(batch).subtracting(inFlight)
        signalNotDeleted(rejected)
        guard !batch.isEmpty else {
            // Never a silent no-op: if nothing survived validation the button looked
            // broken (V2-POLISH B7). A batch empty only because its paths are already
            // in flight stays quiet and leaves any existing error text as it was.
            if !rejected.isEmpty { deleteFailure = .error(L.autostartDeleteInvalidPath) }
            return
        }

        for path in batch { deletingPaths.insert(path) }
        deleteFailure = nil

        let userPaths = batch.filter { !$0.hasPrefix("/Library/") }
        let systemPaths = batch.filter { $0.hasPrefix("/Library/") }

        track { [weak self] in
            guard let self else { return }
            defer {
                for path in batch { self.deletingPaths.remove(path) }
            }

            var results: [(path: String, outcome: PlistDeleteOutcome)] = []

            // Everything in the batch whose delete is not a recorded success yet —
            // an unknown outcome must not read as "deleted".
            func notRecordedAsDeleted() -> Set<String> {
                let succeeded = Set(results.compactMap { $0.outcome == .success ? $0.path : nil })
                return Set(batch).subtracting(succeeded)
            }

            for path in userPaths {
                let outcome = await self.deps.trash(path)
                guard !Task.isCancelled else { self.signalNotDeleted(notRecordedAsDeleted()); return }
                results.append((path, outcome))
            }

            if !systemPaths.isEmpty {
                let systemOutcome = await self.deps.removePrivileged(systemPaths)
                guard !Task.isCancelled else { self.signalNotDeleted(notRecordedAsDeleted()); return }
                for path in systemPaths { results.append((path, systemOutcome)) }
            }

            let failures = results.compactMap { result -> String? in
                if case .failed(let msg) = result.outcome { return msg }
                return nil
            }
            if let firstFailure = failures.first {
                self.deleteFailure = .error(failures.count > 1
                    ? L.autostartDeleteBulkFailure(failures.count, results.count, firstFailure)
                    : firstFailure)
            } else if results.contains(where: { $0.outcome == .timedOut }) {
                self.deleteFailure = .timedOut
            } else if results.contains(where: { $0.outcome == .cancelled }) {
                self.deleteFailure = .cancelled
            }

            let succeededPaths = Set(results.compactMap { result -> String? in
                if case .success = result.outcome { return result.path }
                return nil
            })
            if !succeededPaths.isEmpty {
                self.removeLocally(succeededPaths)
            }
            self.signalNotDeleted(LaunchdPlistInspector.pathsNotDeleted(results: results))
        }
    }

    /// Called by the card once it has restored `paths` (or decided they are gone). Draining here rather than
    /// clearing on publish is what makes two deletes landing in one update cycle safe.
    func acknowledgeRestore(_ paths: Set<String>) {
        guard !paths.isEmpty, !deleteRestore.paths.isEmpty else { return }
        deleteRestore = PlistDeleteRestoreSignal(
            paths: deleteRestore.paths.subtracting(paths),
            stamp: deleteRestore.stamp &+ 1)
    }

    /// Clears the delete note; otherwise only starting the next delete clears it.
    func clearDeleteFailure() { deleteFailure = nil }

    // MARK: - Helpers

    /// Removes `paths` from `report.autostart`'s three plist arrays in place, WITHOUT a full `refreshReport()`:
    /// a recollect rebuilds every section blank and the whole card would flash through its "collecting" state.
    /// A local mutation lets the card animate just the removed rows.
    private func removeLocally(_ paths: Set<String>) {
        guard var auto = host.read().autostart, !paths.isEmpty else { return }
        let before = auto.userAgents.count + auto.systemAgents.count + auto.systemDaemons.count
        auto.userAgents.removeAll { paths.contains($0.path) }
        auto.systemAgents.removeAll { paths.contains($0.path) }
        auto.systemDaemons.removeAll { paths.contains($0.path) }
        removedCount += before - (auto.userAgents.count + auto.systemAgents.count + auto.systemDaemons.count)
        host.write(\.autostart, auto as AutostartInfo?)
        // Deliberately NO reassess: `report` is a PARTIAL for most of a collect and a partial must never be
        // assessed (assessment-complete-collect). Nothing is lost: `Assess.assess` reads nothing from
        // `report.autostart`, so a recompute could never change the verdict.
    }

    /// Publishes `paths` as "these were not deleted, put the rows back". Unions into whatever has not been drained
    /// yet and always bumps `stamp`, so an identical failure set twice in a row is still two distinct signals.
    private func signalNotDeleted(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        deleteRestore = PlistDeleteRestoreSignal(
            paths: deleteRestore.paths.union(paths),
            stamp: deleteRestore.stamp &+ 1)
    }

    /// Starts `body` as a delete Task this controller owns: `stop()` cancels it; it drops its own handle when done.
    private func track(_ body: @escaping @MainActor () async -> Void) {
        let id = nextDeleteID
        nextDeleteID += 1
        deleteTasks[id] = Task { [weak self] in
            await body()
            self?.deleteTasks[id] = nil
        }
    }

    /// Runs `work` on a utility GCD thread, never on the cooperative pool: the privileged branch blocks its thread
    /// on Touch ID for up to 30 s (same reason as the crash-report delete).
    nonisolated static func onUtilityThread(_ work: @escaping @Sendable () -> PlistDeleteOutcome) async -> PlistDeleteOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: work()) }
        }
    }

    /// `PrivilegedRunner.Outcome` → `PlistDeleteOutcome`, case for case.
    nonisolated static func plistOutcome(_ outcome: PrivilegedRunner.Outcome) -> PlistDeleteOutcome {
        switch outcome {
        case .success: return .success
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .failed(let msg): return .failed(msg)
        }
    }

    // MARK: - Fixture, teardown

    /// Visual fixture only (REDESIGN-SYSTEM): the Startup items card's transient state.
    func applyFixture(checkedAt: Date?, removed: Int, checking: Bool, deleting: Set<String>,
                      failure: PrivilegedActionFailure?) {
        self.checkedAt = checkedAt; removedCount = removed; self.checking = checking
        deletingPaths = deleting; deleteFailure = failure
    }

    /// Cancels an in-flight check and every in-flight delete; the coordinator's `stop()` calls it.
    func stop() {
        checkTask?.cancel()
        checkTask = nil
        for task in deleteTasks.values { task.cancel() }
        deleteTasks = [:]
    }
}
