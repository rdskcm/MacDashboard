// Tests/MacDashboardTests/ReportHostTests.swift
// ARCH-MODEL-SPLIT step 0: the seam every feature controller reaches the coordinator through. Models run on an
// isolated AppSettings, a temp data directory and a virtual clock — never the real defaults, App Support or wall clock.
// Writes `model.report` / `model.isCollectingReport` / `model.reportRefreshPending` directly and starts passes with `beginPass` on a `FakePass`.
import Foundation
import Testing
@testable import MacDashboard

/// A report pass the test drives (`AppModel.PassCollect`): sends the blank first snapshot, parks until `release()`,
/// then returns `final`. Not cancellation-aware (like a probe running to its timeout). Spawns no process.
@MainActor final class FakePass {
    var final = FullReport()
    private(set) var calls = 0
    private(set) var parked = false
    private var gate: CheckedContinuation<Void, Never>?
    func release() { parked = false; gate?.resume(); gate = nil }
    var collect: AppModel.PassCollect {
        { _, _, onSection in
            self.calls += 1
            onSection(FullReport())
            await withCheckedContinuation { self.gate = $0; self.parked = true }
            return self.final
        }
    }
}

extension SerialTests {
    @MainActor struct ReportHostTests {
        private func makeModel(pass: FakePass? = nil, configure: (AppSettings, URL) -> Void = { _, _ in }) -> (AppModel, AppSettings, VirtualClock, () -> Void) {
            let (d, name) = makeIsolatedDefaults()
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-report-host-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let s = AppSettings(defaults: d)
            configure(s, dir)
            if pass != nil { s.notifyEnabled = [] }   // a committed pass must post no notification
            let clock = VirtualClock()
            let m = AppModel(dataDirectory: dir, settings: s, time: clock.source, passCollect: pass?.collect)
            return (m, s, clock, { removeIsolatedDefaults(d, name); try? FileManager.default.removeItem(at: dir) })
        }
        private let energy = EnergySettings(battery: [("displaysleep", "2")], ac: [("displaysleep", "10")])

        @Test func readUpdateWriteAndIsCollecting() {
            let (m, _, _, cleanup) = makeModel(); defer { cleanup() }
            #expect(m.reportHost.read().energy == nil)
            #expect(m.reportHost.isCollecting() == false)
            m.reportHost.update { $0.energy = energy }
            #expect(m.report.energy == energy)
            #expect(m.reportHost.read().energy == energy)
            m.reportHost.write(\.energy, nil)
            #expect(m.report.energy == nil)
            m.isCollectingReport = true
            #expect(m.reportHost.isCollecting() == true)
        }

        // PASS-WAIT-PARTIAL R4: no pass in flight → the landing runs at once, inside the call.
        @Test func afterPassRunsAtOnceWhenNoPassIsInFlight() {
            let (m, _, _, cleanup) = makeModel(); defer { cleanup() }
            var ran = false
            m.reportHost.afterPass { ran = true }
            #expect(ran)
        }

        // R2, R3, R5: queued during a pass, run in order at its end — after `report = final` and the commit assessment.
        @Test func afterPassQueuesUntilThePassCommitsThenRunsInOrder() async {
            let pass = FakePass()
            pass.final.energy = energy
            pass.final.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
            let (m, _, _, cleanup) = makeModel(pass: pass); defer { cleanup() }
            let e = energy
            m.beginPass(trigger: .automatic)
            await settle { pass.parked }
            var order: [Int] = [], afterCommit: [Bool] = []
            for n in 1...2 {
                m.reportHost.afterPass {
                    order.append(n)
                    afterCommit.append(!m.isCollectingReport && m.report.energy == e
                                       && m.assessment.items.contains { $0.kind == .firewallOff })
                }
            }
            #expect(order.isEmpty)
            pass.release()
            await settle { !m.isCollectingReport }
            #expect(order == [1, 2])
            #expect(afterCommit == [true, true])
        }

        // R6: a landing queued during a pass runs before a coalesced pending pass starts.
        @Test func afterPassRunsBeforeAPendingPassStarts() async {
            let pass = FakePass()
            let (m, _, _, cleanup) = makeModel(pass: pass); defer { cleanup() }
            m.beginPass(trigger: .automatic)
            await settle { pass.parked }
            m.reportRefreshPending = .automatic                      // what refreshReport() records mid-pass
            var seenCollecting: Bool? = nil, seenCalls: Int? = nil
            m.reportHost.afterPass { seenCollecting = m.isCollectingReport; seenCalls = pass.calls }
            pass.release()
            await settle { pass.calls == 2 && pass.parked }          // the pending pass started and parked
            #expect(seenCollecting == false && seenCalls == 1)
            #expect(m.isCollectingReport)
            pass.release()
            await settle { !m.isCollectingReport }
        }

        // R7: stop() drops what is queued, a cancelled pass drops what was queued after stop(); nothing stays queued.
        @Test func afterPassDropsQueuedWorkWhenThePassIsCancelled() async {
            let pass = FakePass()
            let (m, _, _, cleanup) = makeModel(pass: pass); defer { cleanup() }
            m.beginPass(trigger: .automatic)
            await settle { pass.parked }
            var ran: [String] = []
            m.reportHost.afterPass { ran.append("before stop") }
            m.stop()
            m.reportHost.afterPass { ran.append("after stop") }      // the cancelled pass still collects: queued, then dropped
            pass.release()
            await settle { !m.isCollectingReport }
            #expect(ran.isEmpty)
            m.reportHost.afterPass { ran.append("idle") }
            #expect(ran == ["idle"])
        }

        @Test func reassessUsesTheCommittedReport() {
            let (m, s, _, cleanup) = makeModel(); defer { cleanup() }
            // Part 1: reassess runs at all (no automatic reassess on a plain field write).
            s.lowSpacePercent = 15                     // reassesses now, with no disk reading: no warning
            m.disk = DiskInfo(size: 100 * GIB, avail: 12 * GIB)
            #expect(!m.assessment.items.contains { $0.kind == .diskFullSoon })
            m.reportHost.reassess()
            #expect(m.assessment.items.contains { $0.kind == .diskFullSoon })
            // Part 2 (M4): while a pass is in flight it assesses the committed report, not the partial.
            func firewallItem() -> Bool { m.assessment.items.contains { $0.kind == .firewallOff } }
            m.isCollectingReport = true
            m.report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
            m.reportHost.reassess()
            #expect(!firewallItem())                   // lastCommittedReport is still blank
            m.isCollectingReport = false
            m.reportHost.reassess()
            #expect(firewallItem())
        }

        /// PASS-WAIT-PARTIAL R1, R10 (findings C3, P1): an updater's read that lands while a pass is in flight survives
        /// the pass's commit. Fails on 1ab1597: the wait gave up after 15 s of virtual time, the write went into the
        /// partial and `report = final` replaced it.
        @Test func anEnergyReadDuringAPassSurvivesTheCommit() async {
            let pass = FakePass()
            let (m, _, clock, cleanup) = makeModel(pass: pass); defer { cleanup() }
            let fake = FakeEnergy()
            let c = EnergyController(host: m.reportHost, time: clock.source, deps: fake.deps)
            m.beginPass(trigger: .automatic)
            await settle { pass.parked }
            await c.refresh()
            pass.release()
            await settle { !m.isCollectingReport }
            #expect(m.report.energy == fake.settings)
            #expect(m.homeReport.energy == fake.settings)
        }

        /// PASS-WAIT-PARTIAL R1, R2, R3, R10 (findings C3, the harmful class): the firewall is turned on while a pass
        /// that read it as off is in flight. After the commit the report, Home's report and the assessment show it on,
        /// and the enable ends only then. Fails on 1ab1597: the commit reverts it (firewall == false, item back).
        @Test func aFirewallEnableDuringAPassSurvivesTheCommitAndIsAssessed() async {
            let pass = FakePass()
            pass.final.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
            let (m, _, _, cleanup) = makeModel(pass: pass); defer { cleanup() }
            let fake = FakeSecurity()                              // its collect returns all four protections on
            let c = SecurityController(host: m.reportHost, deps: fake.deps)
            m.beginPass(trigger: .automatic)
            await settle { pass.parked }
            c.enableNow(.firewall)
            await c.enableTask?.value
            pass.release()
            await settle { !m.isCollectingReport }
            #expect(m.report.security == fake.state && m.homeReport.security == fake.state)
            #expect(!m.assessment.items.contains { $0.kind == .firewallOff })
            #expect(c.action == .idle)
        }

        // 17 (ARCH-MODEL-SPLIT block 4, R6)
        @Test func isPausedAndRefreshClaudeBackupReachTheCoordinator() async throws {
            var log: URL!
            let (m, _, _, cleanup) = makeModel { s, dir in
                log = dir.appendingPathComponent("claude.log")
                s.claudeLogPath = log.path
            }
            defer { cleanup() }
            #expect(m.reportHost.isPaused() == false)
            m.setPaused(true)
            #expect(m.reportHost.isPaused() == true)
            #expect(m.claudeBackup == nil)                        // no log file yet
            try Data().write(to: log)                             // present, no successful run in it
            await m.reportHost.refreshClaudeBackup()
            #expect(m.claudeBackup == .noSuccessFound)
        }
    }
}
