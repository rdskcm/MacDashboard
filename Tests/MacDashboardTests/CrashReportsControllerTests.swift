// Tests/MacDashboardTests/CrashReportsControllerTests.swift
// ARCH-MODEL-SPLIT block 6, stage A: hide / unhide / delete and the re-scan ordering through injected closures — no
// DiagnosticReports folder, no real hidden list, no coordinator. Host and clock fakes: ControllerTestSupport.swift.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeCrash {
    var hidden: [HiddenCrashReport] = []
    var scanResult = CrashScan(visible: [], hidden: [])
    var deleteResult = CrashDeleteResult()
    /// When set, `scan` / `delete` park until released (not cancellation-aware, like a running process).
    var holdScan = false
    var holdDelete = false
    private(set) var scanCalls: [Set<String>] = []
    private(set) var deleteCalls: [[String]] = []
    private(set) var setCalls: [[HiddenCrashReport]] = []
    /// One gate per scan call, so a test can release them individually.
    private(set) var scanGates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var deleteGate: CheckedContinuation<Void, Never>?

    func releaseScan(_ index: Int) { scanGates.removeValue(forKey: index)?.resume() }
    func releaseScans(reversed: Bool = false) {
        let keys = scanGates.keys.sorted()
        for k in reversed ? keys.reversed() : keys { releaseScan(k) }
    }
    func releaseDelete() { deleteGate?.resume(); deleteGate = nil }

    var deps: CrashReportsController.Dependencies {
        CrashReportsController.Dependencies(
            scan: { hidden in
                let index = self.scanCalls.count
                self.scanCalls.append(hidden)
                if self.holdScan { await withCheckedContinuation { self.scanGates[index] = $0 } }
                return self.scanResult
            },
            delete: { paths in
                self.deleteCalls.append(paths)
                if self.holdDelete { await withCheckedContinuation { self.deleteGate = $0 } }
                return self.deleteResult
            },
            hiddenReports: { self.hidden },
            setHiddenReports: { self.setCalls.append($0); self.hidden = $0 })
    }
}

extension SerialTests {
    @MainActor struct CrashReportsControllerTests {
        private static let dir = "/Users/test/Library/Logs/DiagnosticReports"
        private let a = CrashGroup(process: "a", count: 2, directory: CrashReportsControllerTests.dir,
                                   reportPaths: ["\(CrashReportsControllerTests.dir)/a-1.ips", "\(CrashReportsControllerTests.dir)/a-2.ips"])
        private let b = CrashGroup(process: "b", count: 1, directory: CrashReportsControllerTests.dir,
                                   reportPaths: ["\(CrashReportsControllerTests.dir)/b-1.ips"])

        private func make() -> (CrashReportsController, FakeHost, FakeCrash, VirtualClock) {
            let host = FakeHost(), fake = FakeCrash(), clock = VirtualClock()
            host.report.crashes = [a, b]
            fake.scanResult = CrashScan(visible: [b], hidden: [a])
            return (CrashReportsController(host: host.host, time: clock.source, deps: fake.deps), host, fake, clock)
        }

        /// 1. (R1, R3) hide writes the list, scans with it, lands, re-assesses once.
        @Test func hideWritesListScansAndLands() async {
            let (c, host, fake, clock) = make()
            c.hide("a")
            #expect(fake.setCalls.count == 1)
            #expect(fake.setCalls[0].map(\.name) == ["a-1.ips", "a-2.ips"])
            #expect(fake.setCalls[0].allSatisfy { $0.hiddenAt == clock.now })
            #expect(c.action == .working(.hide, groupID: "a"))
            await settle { c.scanTasks.isEmpty }
            #expect(fake.scanCalls == [["a-1.ips", "a-2.ips"]])
            #expect(host.report.crashes == [b])
            #expect(host.report.crashesHidden == [a])
            #expect(host.reassessCalls == 1)
            #expect(c.action == .idle)
            #expect(c.scanTasks.isEmpty)
        }

        /// 2. (R1) guards.
        @Test func guardsDoNothing() async {
            let (c, host, fake, _) = make()
            host.report.crashesHidden = [a]
            host.report.crashes = [CrashGroup(process: "empty", count: 0, directory: Self.dir), b]
            c.hide("nope"); c.hide("empty"); c.unhide("b")   // unknown, no paths, unhide reads crashesHidden only
            #expect(fake.setCalls.isEmpty && fake.scanCalls.isEmpty)
            #expect(c.action == .idle)
            c.applyFixture(.working(.delete, groupID: "b"))
            c.hide("b"); c.unhide("a"); c.delete("b")
            #expect(fake.setCalls.isEmpty && fake.scanCalls.isEmpty && fake.deleteCalls.isEmpty)
            c.applyFixture(.idle)
            c.unhide("a")
            #expect(fake.setCalls.count == 1)
            #expect(c.action == .working(.unhide, groupID: "a"))
            await settle { c.scanTasks.isEmpty }
        }

        /// 3. (R2) a request during a pass is parked; passEnded makes it once.
        @Test func requestDuringPassIsParked() async {
            let (c, host, fake, _) = make()
            host.collecting = true
            c.hide("a")
            for _ in 0..<1000 { await Task.yield() }   // deliberate: nothing may happen, so no condition to settle on
            #expect(fake.scanCalls.isEmpty && c.scanTasks.isEmpty)
            #expect(c.action == .working(.hide, groupID: "a"))
            host.collecting = false
            c.passEnded()
            await settle { c.scanTasks.isEmpty && c.action == .idle }
            #expect(fake.scanCalls.count == 1)
            #expect(c.action == .idle)
            c.passEnded()
            for _ in 0..<1000 { await Task.yield() }   // deliberate: nothing may happen, so no condition to settle on
            #expect(fake.scanCalls.count == 1)
        }

        /// 4. (R2) a landing during a pass writes nothing; passEnded scans again and writes.
        @Test func landingDuringPassIsParked() async {
            let (c, host, fake, _) = make()
            fake.holdScan = true
            c.rescan()
            await settle { fake.scanGates.count == 1 }
            fake.holdScan = false
            host.collecting = true
            let task = c.scanTasks.values.first
            fake.releaseScans()
            await task?.value
            #expect(host.updateCalls == 0 && host.reassessCalls == 0)
            host.collecting = false
            c.passEnded()
            await settle { c.scanTasks.isEmpty && host.updateCalls > 0 }
            #expect(fake.scanCalls.count == 2)
            #expect(host.report.crashes == [b])
            #expect(host.reassessCalls == 1)
        }

        /// 5. (R2) only the newest request writes, and it delivers the older request's waiting outcome.
        @Test func onlyNewestWritesAndDeliversOutcome() async {
            let (c, host, fake, _) = make()
            fake.holdScan = true
            c.hide("a")                       // request 1, outcome .idle
            c.rescan()                        // request 2, no outcome
            await settle { fake.scanGates.count == 2 }
            #expect(fake.scanGates.count == 2)
            fake.releaseScan(1)
            await settle { c.action == .idle }
            #expect(c.action == .idle)
            #expect(host.updateCalls == 2 && host.reassessCalls == 1)
            fake.releaseScan(0)
            await settle { c.scanTasks.isEmpty }
            #expect(host.updateCalls == 2 && host.reassessCalls == 1)
        }

        /// 6. (R1, R3) delete: paths go to the fake, the outcome lands with the re-scan.
        @Test func deleteOutcomeLandsWithRescan() async {
            let (c, host, fake, _) = make()
            fake.deleteResult = CrashDeleteResult(removed: [], failure: .cancelled)
            c.delete("b")
            #expect(c.action == .working(.delete, groupID: "b"))
            await c.deleteTask?.value
            await settle { c.scanTasks.isEmpty }
            #expect(fake.deleteCalls == [b.reportPaths])
            #expect(c.action == .failed(.cancelled))
            #expect(host.reassessCalls == 1)

            let (c2, _, fake2, _) = make()
            c2.delete("b")
            await c2.deleteTask?.value
            await settle { c2.scanTasks.isEmpty }
            #expect(fake2.deleteCalls == [b.reportPaths])
            #expect(c2.action == .idle)
        }

        /// 7. (R4) stop() cancels re-scans and the delete, drops parked requests.
        @Test func stopCancelsScansAndDelete() async {
            let (c, host, fake, _) = make()
            fake.holdScan = true
            c.hide("a")
            await settle { fake.scanGates.count == 1 }
            let scan = c.scanTasks.values.first
            c.stop()
            #expect(c.scanTasks.isEmpty && c.deleteTask == nil && c.action == .idle)
            fake.releaseScans()
            await scan?.value
            #expect(host.updateCalls == 0 && host.reassessCalls == 0)

            let (d, host2, fake2, _) = make()
            fake2.holdDelete = true
            d.delete("b")
            await settle { fake2.deleteCalls.count == 1 }
            let del = d.deleteTask
            d.stop()
            #expect(d.scanTasks.isEmpty && d.deleteTask == nil && d.action == .idle)
            fake2.releaseDelete()
            await del?.value
            #expect(fake2.scanCalls.isEmpty && host2.reassessCalls == 0)

            let (e, host3, fake3, _) = make()
            host3.collecting = true
            e.rescan()
            e.stop()
            host3.collecting = false
            e.passEnded()
            for _ in 0..<1000 { await Task.yield() }   // deliberate: nothing may happen, so no condition to settle on
            #expect(fake3.scanCalls.isEmpty)
        }

        /// 8. (R1) hiddenNames, fixture setter.
        @Test func hiddenNamesAndFixture() {
            let (c, _, fake, clock) = make()
            fake.hidden = [HiddenCrashReport(name: "x.ips", hiddenAt: clock.now), HiddenCrashReport(name: "y.ips", hiddenAt: clock.now)]
            #expect(c.hiddenNames == ["x.ips", "y.ips"])
            c.applyFixture(.failed(.timedOut))
            #expect(c.action == .failed(.timedOut))
        }

        /// 9. (R1, R5 wiring) the coordinator's controller reads the settings' hidden list.
        @Test func coordinatorWiringReadsSettings() {
            let (d, name) = makeIsolatedDefaults()
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-crash-ctl-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { removeIsolatedDefaults(d, name); try? FileManager.default.removeItem(at: dir) }
            let s = AppSettings(defaults: d)
            let clock = VirtualClock()
            let m = AppModel(dataDirectory: dir, settings: s, time: clock.source)
            s.hiddenCrashReports = [HiddenCrashReport(name: "x.ips", hiddenAt: clock.now)]
            #expect(m.crashReports.hiddenNames == ["x.ips"])
        }

        // Opt-in: MACDASH_LIVE=1 swift test --filter liveCanaryCrashReportsController
        // Reads only: never deletes, never writes the real hidden list (isolated defaults).
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryCrashReportsController() async {
            let (d, name) = makeIsolatedDefaults()
            defer { removeIsolatedDefaults(d, name) }
            let host = FakeHost()
            let c = CrashReportsController(host: host.host, time: .live, deps: .live(settings: AppSettings(defaults: d)))
            c.rescan()
            let tasks = Array(c.scanTasks.values)
            for t in tasks { await t.value }
            let visible = host.report.crashes ?? []
            let hidden = host.report.crashesHidden ?? []
            let groups = visible.map { "\($0.process):\($0.count)" }.joined(separator: " ")
            print("liveCanary visible=\(visible.count) hidden=\(hidden.count) groups=\(groups)")
            var found = Set<String>()
            for dir in [CrashDismiss.userDirectory, CrashDismiss.systemDirectory] {
                let out = await CommandRunner.run("/usr/bin/find", [dir, "-maxdepth", "1", "-type", "f", "(", "-name", "*.ips", "-o", "-name", "*.crash", "-o", "-name", "*.panic", ")", "-mmin", "-10080"], timeout: 15)
                found.formUnion(out.stdout.split(separator: "\n").map(String.init))
            }
            print("liveCanary find count=\(found.count)")
            #expect(host.report.crashes != nil)
            #expect(hidden.isEmpty)
            for g in visible { for p in g.reportPaths { #expect(found.contains(p), "scanned report not listed by find: \(p)") } }
            if found.isEmpty { #expect(visible.isEmpty) }
        }
    }
}
