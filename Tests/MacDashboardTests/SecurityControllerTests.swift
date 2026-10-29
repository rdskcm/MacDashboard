// Tests/MacDashboardTests/SecurityControllerTests.swift
// ARCH-MODEL-SPLIT block 6, stage B: the privileged enable and the page Refresh through injected closures — no Touch ID,
// no collector, no crash feature, no coordinator. Host fake: ControllerTestSupport.swift.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeSecurity {
    var state = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)
    var outcome: PrivilegedRunner.Outcome = .success
    /// When set, the privileged call / the collect parks until released (not cancellation-aware, like Touch ID).
    var holdPrivileged = false
    var holdCollect = false
    private(set) var commands: [String] = []
    private(set) var collectCalls = 0
    private(set) var rescanCalls = 0
    private(set) var checkUpdatesCalls = 0
    private var privilegedGate: CheckedContinuation<Void, Never>?
    private var collectGates: [CheckedContinuation<Void, Never>] = []

    func releasePrivileged() { privilegedGate?.resume(); privilegedGate = nil }
    func releaseCollect() { for g in collectGates { g.resume() }; collectGates = [] }

    var deps: SecurityController.Dependencies {
        SecurityController.Dependencies(
            collect: {
                self.collectCalls += 1
                if self.holdCollect { await withCheckedContinuation { self.collectGates.append($0) } }
                return self.state
            },
            runPrivileged: { command in
                self.commands.append(command)
                if self.holdPrivileged { await withCheckedContinuation { self.privilegedGate = $0 } }
                return self.outcome
            },
            rescanCrashes: { self.rescanCalls += 1 },
            checkUpdates: { self.checkUpdatesCalls += 1 })
    }
}

extension SerialTests {
    @MainActor struct SecurityControllerTests {
        private func make() -> (SecurityController, FakeHost, FakeSecurity) {
            let host = FakeHost(), fake = FakeSecurity()
            return (SecurityController(host: host.host, deps: fake.deps), host, fake)
        }

        /// 1. (R8, R11) a successful enable writes after the pass wait and re-assesses through the host.
        @Test func enableSuccessWritesAfterPassWait() async {
            let (c, host, fake) = make()
            c.enableNow(.firewall)
            #expect(c.action == .enabling(.firewall) && c.firewallApplying)
            await c.enableTask?.value
            #expect(fake.commands == [SecurityPageModel.privilegedEnableCommand(.firewall)])
            #expect(host.awaitCalls == 1)
            #expect(host.report.security == fake.state)
            #expect(host.reassessCalls == 1)
            #expect(c.action == .idle && c.adviceError == nil)
            #expect(fake.rescanCalls == 0)
        }

        /// 2. (R11) outcomes.
        @Test func enableOutcomes() async {
            let (c, host, fake) = make()
            fake.outcome = .cancelled
            c.enableNow(.firewall)
            await c.enableTask?.value
            #expect(c.action == .failed(.firewall, .cancelled) && c.adviceError == nil)
            #expect(host.updateCalls == 0 && host.reassessCalls == 0)
            fake.outcome = .timedOut
            c.enableNow(.gatekeeper)
            await c.enableTask?.value
            #expect(c.action == .failed(.gatekeeper, .timedOut))
            fake.outcome = .failed("x")
            c.enableNow(.firewall)
            await c.enableTask?.value
            #expect(c.action == .failed(.firewall, .error("x")) && c.adviceError == L.adviceFirewallError)
            fake.outcome = .failed("y")
            c.enableNow(.gatekeeper)
            await c.enableTask?.value
            #expect(c.action == .failed(.gatekeeper, .error("y")) && c.adviceError == L.secGatekeeperError)
            fake.outcome = .cancelled; fake.holdPrivileged = true
            c.enableNow(.firewall)
            #expect(c.adviceError == nil)               // cleared when the next enable starts
            await settle { fake.commands.count == 5 }
            fake.releasePrivileged()
            await c.enableTask?.value
        }

        /// 3. (R11) guards.
        @Test func enableGuards() async {
            let (c, _, fake) = make()
            c.enableNow(.fileVault); c.enableNow(.sip)
            #expect(fake.commands.isEmpty && c.action == .idle)
            fake.holdPrivileged = true
            c.enableNow(.gatekeeper)
            #expect(c.gatekeeperApplying && !c.firewallApplying)
            c.enableNow(.firewall)
            await settle { fake.commands.count == 1 }
            #expect(fake.commands.count == 1 && c.action == .enabling(.gatekeeper))
            fake.releasePrivileged()
            await c.enableTask?.value
        }

        /// 4. (R7, R8, R10) Refresh.
        @Test func refreshWritesAndRescansCrashes() async {
            let (c, host, fake) = make()
            c.refreshNow()
            #expect(fake.checkUpdatesCalls == 1 && c.refreshing)
            await c.refreshTask?.value
            #expect(host.awaitCalls == 1 && host.report.security == fake.state)
            #expect(host.reassessCalls == 1 && fake.rescanCalls == 1 && !c.refreshing)

            fake.holdCollect = true
            c.refreshNow()
            c.refreshNow()
            #expect(fake.checkUpdatesCalls == 3)        // 1 + the two presses; only one collect runs
            await settle { fake.collectCalls == 2 }
            #expect(fake.collectCalls == 2)
            fake.releaseCollect()
            await c.refreshTask?.value
        }

        /// 5. (R10) Refresh clears only a failure.
        @Test func refreshClearsOnlyFailed() async {
            let (c, _, fake) = make()
            c.applyFixture(action: .failed(.firewall, .timedOut))
            c.refreshNow()
            #expect(c.action == .idle)
            await c.refreshTask?.value

            fake.holdPrivileged = true
            c.enableNow(.gatekeeper)
            c.refreshNow()
            #expect(c.action == .enabling(.gatekeeper))
            await c.refreshTask?.value
            #expect(c.action == .enabling(.gatekeeper))
            fake.releasePrivileged()
            await c.enableTask?.value
        }

        /// 6. (R9) stop() cancels the enable and the Refresh.
        @Test func stopCancelsEnableAndRefresh() async {
            let (c, host, fake) = make()
            fake.holdPrivileged = true
            c.enableNow(.firewall)
            await settle { fake.commands.count == 1 }
            let enable = c.enableTask
            c.stop()
            #expect(c.enableTask == nil)
            fake.releasePrivileged()
            await enable?.value
            await settle { c.action == .idle }
            #expect(c.action == .idle && fake.commands.count == 1 && fake.collectCalls == 0)
            #expect(host.updateCalls == 0 && host.reassessCalls == 0)

            let (d, host2, fake2) = make()
            fake2.holdCollect = true
            d.refreshNow()
            await settle { fake2.collectCalls == 1 }
            let refresh = d.refreshTask
            d.stop()
            fake2.releaseCollect()
            await refresh?.value
            #expect(!d.refreshing)
            #expect(host2.updateCalls == 0 && host2.reassessCalls == 0 && fake2.rescanCalls == 0)
        }

        /// 7. (R8) when the pass wait gives up the controller still re-assesses only through the host.
        @Test func writesAndReassessesThroughHostWhenWaitGivesUp() async {
            let (c, host, fake) = make()
            host.passEnds = false
            c.enableNow(.firewall)
            await c.enableTask?.value
            #expect(host.report.security == fake.state)
            #expect(host.reassessCalls == 1)
        }

        /// 8. (R6) fixture setter.
        @Test func fixtureSetsBoth() {
            let (c, _, _) = make()
            c.applyFixture(action: .enabling(.firewall), refreshing: true)
            #expect(c.action == .enabling(.firewall) && c.refreshing)
        }

        // Opt-in: MACDASH_LIVE=1 swift test --filter liveCanarySecurityController
        // Reads only: never calls runPrivileged.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanarySecurityController() async {
            let live = SecurityController.Dependencies.live(rescanCrashes: {}, checkUpdates: {})
            let s = await live.collect()
            print("liveCanary security fileVault=\(String(describing: s.fileVault)) gatekeeper=\(String(describing: s.gatekeeper)) sip=\(String(describing: s.sip)) firewall=\(String(describing: s.firewall))")

            func read(_ path: String, _ args: [String]) async -> (first: String, text: String) {
                let out = await CommandRunner.run(path, args, timeout: 15)
                let text = out.stdout
                return (text.split(separator: "\n").first.map(String.init) ?? "", text)
            }
            func report(_ name: String, _ raw: (first: String, text: String), _ actual: Bool?, _ decision: Bool?) {
                print("liveCanary raw \(name): \(raw.first) -> \(decision.map { $0 ? "on" : "off" } ?? "undecided")")
                if let decision { #expect(actual == decision, "\(name) disagrees with the raw reading") }
            }
            let fv = await read("/usr/bin/fdesetup", ["status"])
            report("fdesetup", fv, s.fileVault, fv.text.contains("FileVault is On.") ? true : fv.text.contains("FileVault is Off.") ? false : nil)
            let gk = await read("/usr/sbin/spctl", ["--status"])
            report("spctl", gk, s.gatekeeper, gk.text.contains("assessments enabled") ? true : gk.text.contains("assessments disabled") ? false : nil)
            let sip = await read("/usr/bin/csrutil", ["status"])
            let sipLow = sip.text.lowercased()
            report("csrutil", sip, s.sip, sipLow.contains("enabled.") ? true : sipLow.contains("disabled.") ? false : nil)
            let fw = await read("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
            let fwLow = fw.text.lowercased()
            report("socketfilterfw", fw, s.firewall, fwLow.contains("enabled") ? true : fwLow.contains("disabled") ? false : nil)
            #expect([s.fileVault, s.gatekeeper, s.sip, s.firewall].compactMap { $0 }.count >= 2)
        }
    }
}
