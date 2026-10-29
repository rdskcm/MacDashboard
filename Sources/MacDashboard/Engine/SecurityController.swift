// Engine/SecurityController.swift
// ARCH-MODEL-SPLIT block 6: the Security page's protections feature, moved out of the coordinator. Owns the privileged
// firewall / Gatekeeper enable (REDESIGN-SECURITY; Touch ID, 30 s), the page Refresh, the advice-card error line and
// their Task handles. Reaches the crash feature and the update check only through injected closures.
import Foundation
import Observation

@MainActor
@Observable
final class SecurityController {
    struct Dependencies {
        /// `ReportCollector().collectSecurityInfo()` — a fresh collector per call.
        var collect: @MainActor () async -> SecurityState
        /// `PrivilegedRunner.run(command)` on a GCD thread (it blocks on Touch ID / the admin password).
        var runPrivileged: @MainActor (_ command: String) async -> PrivilegedRunner.Outcome
        /// Re-scans the crash folders; the coordinator passes `crashReports.rescan()`.
        var rescanCrashes: @MainActor () -> Void
        /// Forced update check; the coordinator passes `storage.startUpdateCheckIfNeeded(trigger: .button)`.
        var checkUpdates: @MainActor () -> Void

        /// A function, not a `static let`: the crash and update closures come from the coordinator.
        static func live(rescanCrashes: @escaping @MainActor () -> Void,
                         checkUpdates: @escaping @MainActor () -> Void) -> Dependencies {
            Dependencies(
                collect: { await ReportCollector().collectSecurityInfo() },
                runPrivileged: { command in
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .utility).async {
                            continuation.resume(returning: PrivilegedRunner.run(command))
                        }
                    }
                },
                rescanCrashes: rescanCrashes,
                checkUpdates: checkUpdates)
        }
    }

    /// The one in-flight or last-failed privileged enable; also the re-entrancy guard of `enableNow(_:)`.
    private(set) var action: SecurityActionState = .idle
    var firewallApplying: Bool { if case .enabling(.firewall) = action { return true }; return false }
    var gatekeeperApplying: Bool { if case .enabling(.gatekeeper) = action { return true }; return false }
    /// True while the page's Refresh re-collects security + crashes.
    private(set) var refreshing = false
    /// Set when the last enable failed with an error; cleared when the next enable starts. Home's attention card shows it.
    private(set) var adviceError: String? = nil

    /// The in-flight enable; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var enableTask: Task<Void, Never>?
    /// The in-flight Refresh; `stop()` cancels it. Tests await it.
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?

    private let host: ReportHost
    private let deps: Dependencies

    init(host: ReportHost, deps: Dependencies) {
        self.host = host; self.deps = deps
    }

    /// The firewall or Gatekeeper enable (Touch ID, 30 s budget), from the Security page tiles and Home's advice actions.
    /// Success re-reads the protections so the row clears at once; a failure is kept in `action` per kind.
    func enableNow(_ p: SecurityProtection) {
        guard p == .firewall || p == .gatekeeper else { return }
        if case .enabling = action { return }
        action = .enabling(p)
        adviceError = nil
        let command = SecurityPageModel.privilegedEnableCommand(p)
        enableTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.deps.runPrivileged(command)
            guard !Task.isCancelled else { self.action = .idle; return }
            switch outcome {
            case .success:
                let s = await self.deps.collect()
                guard !Task.isCancelled else { self.action = .idle; return }
                _ = await self.host.awaitPassEnd()
                guard !Task.isCancelled else { self.action = .idle; return }
                self.host.write(\.security, .some(s))
                self.host.reassess()                               // the committed report, never a partial
                self.action = .idle
            case .cancelled:
                self.action = .failed(p, .cancelled)
            case .timedOut:
                self.action = .failed(p, .timedOut)
            case .failed(let msg):
                self.action = .failed(p, .error(msg))
                self.adviceError = p == .firewall ? L.adviceFirewallError : L.secGatekeeperError
            }
        }
    }

    /// REDESIGN-SECURITY D7: the page's Refresh — a forced update check, then protections + crash folders now.
    func refreshNow() {
        deps.checkUpdates()                                        // before the guard: a press mid-refresh still checks
        guard !refreshing else { return }
        refreshing = true
        if case .failed = action { action = .idle }                // an enable in flight keeps its state (D10)
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshing = false }
            let s = await self.deps.collect()
            guard !Task.isCancelled else { return }
            _ = await self.host.awaitPassEnd()
            guard !Task.isCancelled else { return }
            self.host.write(\.security, .some(s))
            self.host.reassess()
            // The crash folders go through the one crash re-scan owner, so this Refresh can never write a list older
            // than a hide / unhide / delete that finished meanwhile (CRASH-REPORT-DISMISS fix wave 2).
            self.deps.rescanCrashes()
        }
    }

    // MARK: - Fixture, teardown

    /// Visual fixture only (REDESIGN-SECURITY): the privileged-action state and the Refresh busy flag.
    func applyFixture(action: SecurityActionState, refreshing: Bool = false) {
        self.action = action; self.refreshing = refreshing
    }

    /// Cancels the enable and the Refresh; the coordinator's `stop()` calls it. A cancelled enable sets `.idle`
    /// when its privileged call returns (the Touch ID prompt itself cannot be withdrawn).
    func stop() {
        enableTask?.cancel()
        enableTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }
}
