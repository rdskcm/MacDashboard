// Engine/CrashReportsController.swift
// ARCH-MODEL-SPLIT block 6: the Security page's Crashes card actions (CRASH-REPORT-DISMISS), moved out of the
// coordinator unchanged in behaviour. Owns hide / unhide / delete, the ordering of every crash re-scan outside a pass
// (`CrashScanSequencer`), the action state and their Task handles. The report pass still scans crashes itself: it reads
// `hiddenNames` when it starts and calls `passEnded()` when it ends.
import Foundation
import Observation

@MainActor
@Observable
final class CrashReportsController {
    struct Dependencies {
        /// One scan of the crash folders with this hidden list (`ReportCollector.collectCrashScan`), off the main actor.
        var scan: @MainActor (_ hidden: Set<String>) async -> CrashScan
        /// `CrashDismiss.delete(paths:)`; it blocks on Touch ID, so it runs on a GCD thread, never the cooperative pool.
        var delete: @MainActor (_ paths: [String]) async -> CrashDeleteResult
        /// The persisted hidden list (`AppSettings.hiddenCrashReports`) and its setter.
        var hiddenReports: @MainActor () -> [HiddenCrashReport]
        var setHiddenReports: @MainActor ([HiddenCrashReport]) -> Void

        /// A function, not a `static let`: the hidden list lives in the coordinator's settings.
        static func live(settings: AppSettings) -> Dependencies {
            Dependencies(
                scan: { hidden in
                    await Task.detached(priority: .userInitiated) {
                        ReportCollector(hiddenCrashReports: hidden).collectCrashScan()
                    }.value
                },
                delete: { paths in
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            continuation.resume(returning: CrashDismiss.delete(paths: paths))
                        }
                    }
                },
                hiddenReports: { settings.hiddenCrashReports },
                setHiddenReports: { settings.hiddenCrashReports = $0 })
        }
    }

    /// The crash action in flight, or the last delete that did not fully succeed. Also the re-entrancy guard.
    private(set) var action: CrashActionState = .idle
    /// Orders every re-scan outside a pass (CRASH-REPORT-DISMISS fix wave 2).
    @ObservationIgnored private var sequencer = CrashScanSequencer()
    /// In-flight re-scans keyed by start order; each removes its own entry, `stop()` cancels all. Tests read it.
    @ObservationIgnored private(set) var scanTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextScanID = 0
    /// The in-flight delete; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var deleteTask: Task<Void, Never>?

    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies) {
        self.host = host; self.time = time; self.deps = deps
    }

    /// The hidden report file names; the coordinator's pass reads them when it starts.
    var hiddenNames: Set<String> { Set(deps.hiddenReports().map(\.name)) }

    // MARK: - Actions

    /// «Hide» on a crash row: every report of the group joins the hidden list, then the folders are re-scanned.
    func hide(_ id: String) {
        guard !action.isWorking, let g = host.read().crashes?.first(where: { $0.id == id }), !g.reportPaths.isEmpty
        else { return }
        deps.setHiddenReports(CrashDismiss.hiding(g, in: deps.hiddenReports(), now: time.now()))
        action = .working(.hide, groupID: id)
        request(completing: .idle)
    }

    /// «Show again» on a hidden row.
    func unhide(_ id: String) {
        guard !action.isWorking, let g = host.read().crashesHidden?.first(where: { $0.id == id }) else { return }
        deps.setHiddenReports(CrashDismiss.unhiding(g, in: deps.hiddenReports(), now: time.now()))
        action = .working(.unhide, groupID: id)
        request(completing: .idle)
    }

    /// «Delete» confirmed on a crash row; the outcome lands with the re-scan that follows.
    func delete(_ id: String) {
        guard !action.isWorking, let g = host.read().crashes?.first(where: { $0.id == id }), !g.reportPaths.isEmpty
        else { return }
        action = .working(.delete, groupID: id)
        let paths = g.reportPaths
        deleteTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.deps.delete(paths)
            guard !Task.isCancelled else { return }
            self.request(completing: result.failure.map { .failed($0) } ?? .idle)
        }
    }

    /// The Security page's Refresh (through `SecurityController`'s `rescanCrashes`): re-scan, keep a waiting outcome.
    func rescan() { request(completing: nil) }

    /// The coordinator's pass ended, completed or cancelled: a request parked during it is made again now.
    func passEnded() { if sequencer.passEnded() { request(completing: nil) } }

    /// The single owner of re-scans outside a pass. Call it AFTER the input changed (hidden list written, delete
    /// returned). `outcome` = what `action` becomes once the newest scan lands; nil keeps an outcome already waiting.
    /// Only the newest request's scan writes; while a pass collects, the request (or the landing) is parked and
    /// `passEnded()` requests again (`assessment-complete-collect`).
    private func request(completing outcome: CrashActionState?) {
        guard let ticket = sequencer.request(completing: outcome, collecting: host.isCollecting()) else { return }
        let hidden = hiddenNames   // read now: after the change this request follows
        let id = nextScanID
        nextScanID += 1
        scanTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.scanTasks[id] = nil }
            let scan = await self.deps.scan(hidden)
            guard !Task.isCancelled else { return }
            let landing = self.sequencer.landed(ticket: ticket, collecting: self.host.isCollecting())
            guard landing.write else { return }
            self.host.write(\.crashes, .some(scan.visible))
            self.host.write(\.crashesHidden, .some(scan.hidden))
            self.host.reassess()                                   // the committed report, never a partial
            if let outcome = landing.outcome { self.action = outcome }
        }
    }

    // MARK: - Fixture, teardown

    /// Visual fixture only (CRASH-REPORT-DISMISS): the spinner and failure-note states.
    func applyFixture(_ action: CrashActionState) { self.action = action }

    /// Cancels every re-scan and the delete; drops parked requests and a waiting outcome (a cancelled scan never
    /// lands, so a working action would stay); the coordinator's `stop()` calls it.
    func stop() {
        for task in scanTasks.values { task.cancel() }
        scanTasks = [:]
        deleteTask?.cancel()
        deleteTask = nil
        sequencer = CrashScanSequencer()
        if action.isWorking { action = .idle }
    }
}
