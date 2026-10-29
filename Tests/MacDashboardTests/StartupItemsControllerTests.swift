// Tests/MacDashboardTests/StartupItemsControllerTests.swift
// ARCH-MODEL-SPLIT block 3: the Startup items state machine through injected closures — no file is trashed, no privileged call, no collector, no coordinator. Host and clock fakes: ControllerTestSupport.swift.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeStartup {
    var info = AutostartInfo(loginItems: ["Mail"])
    /// Per-path trash outcome; a path not listed succeeds.
    var trashResults: [String: PlistDeleteOutcome] = [:]
    var privilegedResult: PlistDeleteOutcome = .success
    /// When set, `collect` parks until `releaseCollect()`.
    var holdCollect = false
    /// When set, every `trash` call parks until `releaseTrash()` (not cancellation-aware, like the real GCD hop).
    var holdTrash = false
    private(set) var collectCalls = 0
    private(set) var trashed: [String] = []
    private(set) var privileged: [[String]] = []
    private(set) var collectParked = false
    private(set) var trashParked = false
    private var collectGate: CheckedContinuation<Void, Never>?
    private var trashGate: CheckedContinuation<Void, Never>?

    func releaseCollect() { collectGate?.resume(); collectGate = nil }
    func releaseTrash() { trashGate?.resume(); trashGate = nil }

    var deps: StartupItemsController.Dependencies {
        StartupItemsController.Dependencies(
            collect: {
                self.collectCalls += 1
                if self.holdCollect {
                    await withCheckedContinuation { self.collectGate = $0; self.collectParked = true }
                }
                return self.info
            },
            trash: { path in
                self.trashed.append(path)
                if self.holdTrash {
                    await withCheckedContinuation { self.trashGate = $0; self.trashParked = true }
                }
                return self.trashResults[path] ?? .success
            },
            removePrivileged: { paths in
                self.privileged.append(paths)
                return self.privilegedResult
            })
    }
}

extension SerialTests {
    @MainActor struct StartupItemsControllerTests {
        private let u1 = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/com.test.one.plist")
        private let u2 = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/com.test.two.plist")
        private let sa = "/Library/LaunchAgents/com.test.agent.plist"
        private let sd = "/Library/LaunchDaemons/com.test.daemon.plist"
        private func orphan(_ path: String) -> LaunchdPlistInfo {
            LaunchdPlistInfo(path: path, label: nil, executablePath: nil, isOrphan: true, description: nil)
        }
        private func make() -> (StartupItemsController, FakeHost, FakeStartup, VirtualClock) {
            let host = FakeHost(), fake = FakeStartup(), clock = VirtualClock()
            host.report.autostart = AutostartInfo(loginItems: [], userAgents: [orphan(u1), orphan(u2)],
                                                  systemAgents: [orphan(sa)], systemDaemons: [orphan(sd)])
            return (StartupItemsController(host: host.host, time: clock.source, deps: fake.deps), host, fake, clock)
        }
        /// Snapshot the delete handles right after the call (before any suspension), then await them.
        private func drain(_ c: StartupItemsController) async { for t in Array(c.deleteTasks.values) { await t.value } }
        private func remaining(_ host: FakeHost) -> [String] {
            guard let a = host.report.autostart else { return [] }
            return (a.userAgents + a.systemAgents + a.systemDaemons).map(\.path)
        }

        // 1 (R2, R6)
        @Test func checkStaleWritesTheSectionAfterThePass() async {
            let (c, host, fake, clock) = make()
            c.checkStaleNow()
            #expect(c.checking && c.checkTask != nil)
            await c.checkTask?.value
            #expect(fake.collectCalls == 1 && host.awaitCalls == 1 && host.updateCalls == 1)
            #expect(host.report.autostart == fake.info)
            #expect(c.checkedAt == clock.now && c.removedCount == 0 && !c.checking)
            #expect(host.reassessCalls == 0)
        }
        // 2
        @Test func checkStaleIsIgnoredWhileChecking() async {
            let (c, host, fake, _) = make()
            fake.holdCollect = true
            c.checkStaleNow()
            await settle { fake.collectParked }
            c.checkStaleNow()
            fake.releaseCollect(); await c.checkTask?.value
            #expect(fake.collectCalls == 1)
            #expect(host.reassessCalls == 0)
        }
        // 3 (D8)
        @Test func checkStaleResetsTheRemovedCountAndSkipsAnUnchangedWrite() async {
            let (c, host, fake, clock) = make()
            c.applyFixture(checkedAt: nil, removed: 3, checking: false, deleting: [], failure: nil)
            fake.info = host.report.autostart!
            c.checkStaleNow()
            await c.checkTask?.value
            #expect(c.removedCount == 0 && c.checkedAt == clock.now && host.updateCalls == 0)
            #expect(host.reassessCalls == 0)
        }
        // 4 (R4)
        @Test func stopCancelsTheCheckAndNothingIsWritten() async {
            let (c, host, fake, _) = make()
            fake.holdCollect = true
            c.checkStaleNow()
            await settle { fake.collectParked }
            let task = c.checkTask
            c.stop()
            #expect(c.checkTask == nil)
            fake.releaseCollect()
            await task?.value
            #expect(host.updateCalls == 0 && host.awaitCalls == 0)
            #expect(c.checkedAt == nil && !c.checking)
            #expect(host.reassessCalls == 0)
        }
        // 5 (R2, R6, D9)
        @Test func userLevelDeleteTrashesAndDropsTheRowLocally() async {
            let (c, host, fake, _) = make()
            c.deleteOrphan(path: u1, isSystemLevel: false)
            #expect(c.deletingPaths == [u1] && c.deleteTasks.count == 1)
            await drain(c)
            #expect(fake.trashed == [u1] && fake.privileged.isEmpty)
            #expect(host.report.autostart?.userAgents.map(\.path) == [u2])
            #expect(c.removedCount == 1 && c.deletingPaths.isEmpty && c.deleteFailure == nil)
            #expect(c.deleteRestore.paths.isEmpty && c.deleteTasks.isEmpty && host.awaitCalls == 0)
            #expect(host.reassessCalls == 0)
        }
        // 6
        @Test func systemLevelDeleteMakesOnePrivilegedCall() async {
            let (c, host, fake, _) = make()
            c.deleteOrphan(path: sd, isSystemLevel: true)
            await drain(c)
            #expect(fake.privileged == [[sd]] && fake.trashed.isEmpty)
            #expect(host.report.autostart?.systemDaemons.isEmpty == true && c.removedCount == 1)
            #expect(host.reassessCalls == 0)
        }
        // 7
        @Test func failedDeleteKeepsTheRowAndSetsTheNote() async {
            let cases: [(PlistDeleteOutcome, PrivilegedActionFailure)] = [
                (.cancelled, .cancelled), (.timedOut, .timedOut),
                (.failed("permission denied"), .error("permission denied"))]
            for (outcome, expected) in cases {
                let (c, host, fake, _) = make()
                fake.privilegedResult = outcome
                c.deleteOrphan(path: sa, isSystemLevel: true)
                await drain(c)
                #expect(c.deleteFailure == expected)
                #expect(c.deleteRestore.paths == [sa] && c.deleteRestore.stamp == 1)
                #expect(host.report.autostart?.systemAgents.map(\.path) == [sa])
                #expect(c.removedCount == 0 && c.deletingPaths.isEmpty)
                #expect(host.reassessCalls == 0)
            }
        }
        // 8
        @Test func invalidPathIsRejectedWithoutATask() {
            let (c, host, fake, _) = make()
            c.deleteOrphan(path: "/etc/com.test.plist", isSystemLevel: true)
            #expect(c.deleteFailure == .error(L.autostartDeleteInvalidPath))
            #expect(c.deleteRestore.paths == ["/etc/com.test.plist"])
            #expect(c.deleteTasks.isEmpty && fake.privileged.isEmpty)
            c.deleteOrphan(path: "/tmp/x.plist", isSystemLevel: false)
            #expect(c.deleteFailure == .error(L.autostartDeleteInvalidPath))
            #expect(c.deleteRestore.paths == ["/etc/com.test.plist", "/tmp/x.plist"])
            #expect(c.deleteRestore.stamp == 2 && c.deleteTasks.isEmpty && fake.trashed.isEmpty)
            #expect(host.reassessCalls == 0)
        }
        // 9
        @Test func secondDeleteOfAnInFlightPathIsIgnored() async {
            let (c, host, fake, _) = make()
            fake.holdTrash = true
            c.deleteOrphan(path: u1, isSystemLevel: false)
            let tasks = Array(c.deleteTasks.values)
            await settle { fake.trashParked }
            c.deleteOrphan(path: u1, isSystemLevel: false)
            #expect(fake.trashed == [u1] && c.deleteTasks.count == 1 && c.deleteRestore.paths.isEmpty)
            fake.releaseTrash()
            for t in tasks { await t.value }
            #expect(host.report.autostart?.userAgents.map(\.path) == [u2])
            #expect(host.reassessCalls == 0)
        }
        // 10
        @Test func bulkDeleteTrashesUserPathsThenMakesOnePrivilegedCall() async {
            let (c, host, fake, _) = make()
            c.deleteOrphans(paths: [u1, sa, u2, sd])
            #expect(c.deletingPaths == [u1, sa, u2, sd])
            await drain(c)
            #expect(fake.trashed == [u1, u2] && fake.privileged == [[sa, sd]])
            #expect(remaining(host).isEmpty && c.removedCount == 4)
            #expect(c.deleteFailure == nil && c.deleteRestore.paths.isEmpty && c.deletingPaths.isEmpty)
            #expect(host.reassessCalls == 0)
        }
        // 11
        @Test func bulkPartialFailureKeepsOnlyTheFailedRows() async {
            let (c, host, fake, _) = make()
            fake.trashResults[u2] = .failed("boom")
            c.deleteOrphans(paths: [u1, u2, sa, sd])
            await drain(c)
            #expect(c.deleteFailure == .error("boom") && c.deleteRestore.paths == [u2])
            #expect(remaining(host) == [u2] && c.removedCount == 3)
            #expect(host.reassessCalls == 0)

            let (c2, host2, fake2, _) = make()
            fake2.trashResults[u2] = .failed("boom")
            fake2.privilegedResult = .failed("denied")
            c2.deleteOrphans(paths: [u1, u2, sa, sd])
            await drain(c2)
            #expect(c2.deleteFailure == .error(L.autostartDeleteBulkFailure(3, 4, "boom")))
            #expect(c2.deleteRestore.paths == [u2, sa, sd])
            #expect(host2.reassessCalls == 0)
        }
        // 12
        @Test func bulkWithNothingToDo() async {
            let (c, host, _, _) = make()
            c.deleteOrphans(paths: ["/etc/a.plist"])
            #expect(c.deleteFailure == .error(L.autostartDeleteInvalidPath))
            #expect(c.deleteRestore.paths == ["/etc/a.plist"] && c.deleteTasks.isEmpty)
            #expect(host.reassessCalls == 0)

            let (c2, host2, fake2, _) = make()
            fake2.holdTrash = true
            c2.deleteOrphan(path: u1, isSystemLevel: false)
            let tasks = Array(c2.deleteTasks.values)
            await settle { fake2.trashParked }
            c2.deleteOrphans(paths: [u1])
            #expect(fake2.trashed == [u1] && c2.deleteFailure == nil)
            #expect(c2.deleteRestore.paths.isEmpty && c2.deleteTasks.count == 1)
            fake2.releaseTrash()
            for t in tasks { await t.value }
            #expect(host2.reassessCalls == 0)
        }
        // 13 (R4, D7)
        @Test func stopCancelsAnInFlightDeleteAndRestoresTheRow() async {
            let (c, host, fake, _) = make()
            fake.holdTrash = true
            c.deleteOrphan(path: u1, isSystemLevel: false)
            let tasks = Array(c.deleteTasks.values)
            await settle { fake.trashParked }
            c.stop()
            #expect(c.deleteTasks.isEmpty)
            fake.releaseTrash()
            for t in tasks { await t.value }
            #expect(host.report.autostart?.userAgents.map(\.path) == [u1, u2])
            #expect(c.removedCount == 0 && c.deleteRestore.paths == [u1])
            #expect(c.deletingPaths.isEmpty && c.deleteFailure == nil && host.updateCalls == 0)
            #expect(host.reassessCalls == 0)
        }
        // 14 (R4)
        @Test func stopCancelsABulkDeleteBeforeThePrivilegedCall() async {
            let (c, host, fake, _) = make()
            fake.holdTrash = true
            c.deleteOrphans(paths: [u1, sd])
            let tasks = Array(c.deleteTasks.values)
            await settle { fake.trashParked }
            c.stop()
            fake.releaseTrash()
            for t in tasks { await t.value }
            #expect(fake.privileged.isEmpty && c.deleteRestore.paths == [u1, sd])
            #expect(remaining(host).count == 4 && c.deletingPaths.isEmpty && host.updateCalls == 0)
            #expect(host.reassessCalls == 0)
        }
        // 15
        @Test func acknowledgeRestoreDrainsAndClearDeleteFailureClears() {
            let (c, host, _, _) = make()
            c.deleteOrphan(path: "/etc/com.test.plist", isSystemLevel: true)
            c.acknowledgeRestore(["/etc/com.test.plist"])
            #expect(c.deleteRestore.paths.isEmpty && c.deleteRestore.stamp == 2)
            c.acknowledgeRestore([])
            #expect(c.deleteRestore.stamp == 2)
            c.clearDeleteFailure()
            #expect(c.deleteFailure == nil)
            #expect(host.reassessCalls == 0)
        }
        // 16
        @Test func fixtureSetsTheState() {
            let (c, host, _, clock) = make()
            c.applyFixture(checkedAt: clock.now, removed: 2, checking: true, deleting: [u1], failure: .cancelled)
            #expect(c.checkedAt == clock.now && c.removedCount == 2 && c.checking)
            #expect(c.deletingPaths == [u1] && c.deleteFailure == .cancelled)
            #expect(host.reassessCalls == 0)
        }
        // 17 (R8)
        @Test func privilegedOutcomeMapsCaseForCase() {
            #expect(StartupItemsController.plistOutcome(.success) == .success)
            #expect(StartupItemsController.plistOutcome(.cancelled) == .cancelled)
            #expect(StartupItemsController.plistOutcome(.timedOut) == .timedOut)
            #expect(StartupItemsController.plistOutcome(.failed("x")) == .failed("x"))
        }
    }
}
