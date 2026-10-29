// ARCH-MODEL-SPLIT block 8: the History feature over a temp folder — never the real App Support folder (user-data rule). Host and clock fakes: ControllerTestSupport.swift.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeHistorySchedule {
    var minutes = 0
    var last: Date? = nil
    private(set) var stamps: [Date] = []
    func deps(_ url: URL) -> HistoryController.Dependencies {
        HistoryController.Dependencies(fileURL: url, snapshotMinutes: { self.minutes }, lastSnapshotAt: { self.last },
                                       setLastSnapshotAt: { self.last = $0; self.stamps.append($0) })
    }
}

extension SerialTests {
    @MainActor struct HistoryControllerTests {
        private static let twoDays = #"{"last_run":"2026-01-02","mac_history":[{"date":"2026-01-01","disk_used_gb":90},{"date":"2026-01-02","disk_used_gb":91}]}"#
        private let fileName = "mac_check_state.json"

        private func tempDir() -> URL {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-history-ctl-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            #expect(!dir.path.contains("/Library/Application Support/MacDashboard"))
            return dir
        }
        private func write(_ text: String, _ url: URL) {
            try? Data(text.utf8).write(to: url)
        }
        private func make(_ url: URL, _ host: FakeHost, _ clock: VirtualClock, _ sched: FakeHistorySchedule) -> HistoryController {
            HistoryController(host: host.host, time: clock.source, deps: sched.deps(url))
        }

        @Test func initLoadsTheFileAndTheDigest() {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent(fileName)
            write(Self.twoDays, url)
            let c = make(url, FakeHost(), VirtualClock(), FakeHistorySchedule())
            #expect(c.state.mac_history.count == 2)
            #expect(c.homeDigest == HomeModel.historyDigest(c.state.mac_history))
            #expect(c.homeDigest.count == 2)
            #expect(c.unreadable == false)
            #expect(c.refreshing == false)
            #expect(c.filePath.hasSuffix("/mac_check_state.json"))
        }

        @Test func initOnAnUnreadableFileShowsTheErrorState() throws {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent(fileName)
            write("not json", url)
            let before = try Data(contentsOf: url)
            let c = make(url, FakeHost(), VirtualClock(), FakeHistorySchedule())
            #expect(c.unreadable == true)
            #expect(c.state.mac_history.isEmpty)
            #expect(try Data(contentsOf: url) == before)
        }

        @Test func passWritesTodayAndStampsWhenDue() {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent(fileName)
            let host = FakeHost(), clock = VirtualClock(), sched = FakeHistorySchedule()
            let c = make(url, host, clock, sched)
            c.passCommitted(FullReport(), live: LiveSnapshot())
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(c.state.mac_history.count == 1)
            #expect(c.state.last_run != nil)
            #expect(c.homeDigest.count == 1)
            #expect(sched.stamps == [clock.now])
            #expect(host.errors.isEmpty)
        }

        @Test func passWritesNothingWhenNotDue() {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent(fileName)
            let host = FakeHost(), clock = VirtualClock(), sched = FakeHistorySchedule()
            sched.minutes = 0; sched.last = clock.now
            let c = make(url, host, clock, sched)
            c.passCommitted(FullReport(), live: LiveSnapshot())
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(sched.stamps.isEmpty)
            #expect(c.state.mac_history.isEmpty)
        }

        @Test func passSaveFailureReportsTheErrorAndStillStamps() {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let blocker = dir.appendingPathComponent("blocker")
            write("x", blocker)
            let url = blocker.appendingPathComponent(fileName)
            let host = FakeHost(), clock = VirtualClock(), sched = FakeHistorySchedule()
            let c = make(url, host, clock, sched)
            c.passCommitted(FullReport(), live: LiveSnapshot())
            #expect(host.errors.count == 1)
            #expect(sched.stamps.count == 1)
            #expect(c.state.mac_history.count == 1)
        }

        @Test func passRenamesAnUnreadableFileAsideAndClearsTheErrorState() {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent(fileName)
            write("not json", url)
            let c = make(url, FakeHost(), VirtualClock(), FakeHistorySchedule())
            #expect(c.unreadable == true)
            c.passCommitted(FullReport(), live: LiveSnapshot())
            #expect(c.unreadable == false)
            let name = c.state.unreadable_backup
            #expect(name != nil)
            #expect(name?.hasPrefix("mac_check_state.json.unreadable-") == true)
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name ?? "-").path))
            #expect(c.state.mac_history.count == 1)
            #expect(HistoryStore(url: url).load().mac_history.count == 1)
        }

        @Test func refreshNowRereadsTheFileAndNeverWrites() throws {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent(fileName)
            let c = make(url, FakeHost(), VirtualClock(), FakeHistorySchedule())
            write(Self.twoDays, url)
            let before = try Data(contentsOf: url)
            c.refreshNow()
            #expect(c.state.mac_history.count == 2)
            #expect(c.refreshing == false)
            #expect(c.unreadable == false)
            #expect(try Data(contentsOf: url) == before)
        }

        @Test func restartNoticeRevealPathAndDismiss() {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent(fileName)
            let name = "mac_check_state.json.unreadable-20260115-103000"
            write(#"{"mac_history":[],"unreadable_backup":"\#(name)"}"#, url)
            let host = FakeHost()
            let c = make(url, host, VirtualClock(), FakeHistorySchedule())
            #expect(c.state.unreadable_backup == name)
            #expect(c.restartRevealPath == dir.path)
            let backup = dir.appendingPathComponent(name)
            write("", backup)
            #expect(c.restartRevealPath == backup.path)
            c.dismissRestartNotice()
            #expect(c.state.unreadable_backup == nil)
            #expect(c.restartRevealPath == nil)
            #expect(host.errors.isEmpty)
            #expect(HistoryStore(url: url).load().unreadable_backup == nil)
            #expect(FileManager.default.fileExists(atPath: backup.path))
        }

        @Test func applyFixtureSetsStateDigestAndFlags() throws {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent(fileName)
            let c = make(url, FakeHost(), VirtualClock(), FakeHistorySchedule())
            c.applyFixture(HistoryState(last_run: "2026-01-02", mac_history: [MacHistoryEntry(date: "2026-01-01"), MacHistoryEntry(date: "2026-01-02")]))
            #expect(c.homeDigest.count == 2)
            c.applyFixture(unreadable: true, refreshing: true)
            #expect(c.unreadable == true)
            #expect(c.refreshing == true)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        }

        @Test func coordinatorBuildsHistoryOverItsDataFolderAndReportsErrors() {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            write(Self.twoDays, dir.appendingPathComponent(fileName))
            let m = DashboardModel(dataDirectory: dir, settings: AppSettings(defaults: d), time: VirtualClock().source)
            #expect(m.history.state.mac_history.count == 2)
            #expect(m.history.filePath.hasSuffix(dir.lastPathComponent + "/mac_check_state.json"))
            m.reportHost.reportError("x")
            #expect(m.lastError == "x")
        }
    }
}
