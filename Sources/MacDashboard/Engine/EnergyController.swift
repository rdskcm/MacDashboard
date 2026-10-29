// Engine/EnergyController.swift
// ARCH-MODEL-SPLIT: the System page's Energy (pmset) state, moved out of the coordinator unchanged in behaviour.
// Owns the manual re-read (SPEC Block K), the batched privileged apply (REDESIGN-SYSTEM) and its Task handle.
import Foundation
import Observation

@MainActor
@Observable
final class EnergyController {
    struct Dependencies {
        /// `ReportCollector().collectEnergySettings()` — a fresh collector per call, never shared with a sampler.
        var collect: @MainActor () async -> EnergySettings?
        /// `PrivilegedRunner.run(command)` off the main actor (Touch ID / admin password, 30 s).
        var apply: @MainActor (String) async -> PrivilegedRunner.Outcome

        static let live = Dependencies(
            collect: { await ReportCollector().collectEnergySettings() },
            apply: { command in await Task.detached { PrivilegedRunner.run(command) }.value })
    }

    /// Re-entrancy guard for `refreshNow()`, true while a manual energy (pmset) refresh is in flight.
    private(set) var refreshing = false
    /// Set by a `refresh()` call that arrives while a read is in flight; the in-flight call reads again.
    @ObservationIgnored private var readNeeded = false
    /// Last result of `applyChanges(_:)`; the page bar reads it for the tag.
    private(set) var applyState: EnergyApplyState = .idle
    /// The in-flight apply; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var applyTask: Task<Void, Never>?

    private let host: ReportHost
    private let time: TimeSource
    private let deps: Dependencies

    init(host: ReportHost, time: TimeSource, deps: Dependencies = .live) {
        self.host = host; self.time = time; self.deps = deps
    }

    /// Manual, on-demand energy (pmset) re-check (SPEC Block K), triggered after a batched `pmset` apply so the
    /// table shows what the system actually accepted rather than the values we merely requested.
    func refreshNow() { Task { [weak self] in await self?.refresh() } }

    /// The body of `refreshNow()`, awaitable so an apply can show its result only after the table has been re-read.
    func refresh() async {
        if refreshing {
            // A read is in flight and may have started before the caller's change: request one more read and
            // return only once the loop below has finished it.
            readNeeded = true
            while refreshing && !Task.isCancelled { await time.sleep(.milliseconds(50)) }
            return
        }
        refreshing = true
        defer { refreshing = false }
        repeat {
            readNeeded = false
            let settings = await deps.collect()
            guard !Task.isCancelled else { return }
            _ = await host.awaitPassEnd()
            guard !Task.isCancelled else { return }
            host.write(\.energy, settings)
        } while readNeeded
    }

    /// Applies the staged pmset edits through one privileged call, then re-reads the table.
    /// Outcomes: applied / failed(cancelled | timedOut | error). Ignored while an apply is in flight.
    func applyChanges(_ changes: [EnergyChange]) {
        guard applyState != .applying, let command = SystemPageModel.pmsetCommand(changes) else { return }
        applyState = .applying
        applyTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.deps.apply(command)
            guard !Task.isCancelled else { self.applyState = .idle; return }
            switch outcome {
            case .success:
                await self.refresh()
                guard !Task.isCancelled else { self.applyState = .idle; return }
                self.applyState = .applied
            case .cancelled: self.applyState = .failed(.cancelled)
            case .timedOut:
                // `pmset -b … && pmset -c …` may have applied the first half: show what the system holds.
                await self.refresh()
                guard !Task.isCancelled else { self.applyState = .idle; return }
                self.applyState = .failed(.timedOut)
            case .failed(let msg):
                await self.refresh()
                guard !Task.isCancelled else { self.applyState = .idle; return }
                self.applyState = .failed(.error(msg))
            }
        }
    }

    /// Clears the apply result (OK on the banner; also when the user edits again after «Applied ✓»).
    func dismissApplyResult() { applyState = .idle }

    /// Visual fixture only (REDESIGN-SYSTEM): the Energy card's apply state.
    func applyFixture(_ s: EnergyApplyState) { applyState = s }

    /// Cancels an in-flight apply; the coordinator's `stop()` calls it.
    func stop() {
        applyTask?.cancel()
        applyTask = nil
    }
}
