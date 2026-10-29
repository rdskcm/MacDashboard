// Tests/MacDashboardTests/ReportHostTests.swift
// ARCH-MODEL-SPLIT step 0: the seam every feature controller reaches the coordinator through. Models run on an
// isolated AppSettings, a temp data directory and a virtual clock — never the real defaults, App Support or wall clock.
// Writes `model.report` / `model.isCollectingReport` directly: the series keeps both settable.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    @MainActor struct ReportHostTests {
        private func makeModel(configure: (AppSettings, URL) -> Void = { _, _ in }) -> (AppModel, AppSettings, VirtualClock, () -> Void) {
            let (d, name) = makeIsolatedDefaults()
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-report-host-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let s = AppSettings(defaults: d)
            configure(s, dir)
            let clock = VirtualClock()
            let m = AppModel(dataDirectory: dir, settings: s, time: clock.source)
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

        @Test func awaitPassEndReturnsAtOnceWhenNoPassIsInFlight() async {
            let (m, _, clock, cleanup) = makeModel(); defer { cleanup() }
            #expect(m.isCollectingReport == false)
            let ended = await m.reportHost.awaitPassEnd()
            #expect(ended == true)
            #expect(clock.sleeps.isEmpty)
        }

        @Test func awaitPassEndReturnsTrueWhenThePassEnds() async {
            let (m, _, clock, cleanup) = makeModel(); defer { cleanup() }
            m.isCollectingReport = true
            clock.onSleep = { n in if n == 15 { m.isCollectingReport = false } }   // the pass ends after 3 s
            let ended = await m.reportHost.awaitPassEnd()
            #expect(ended == true)
            #expect(clock.sleeps.count == 15)
            #expect(clock.sleeps.allSatisfy { $0 == .milliseconds(200) })
        }

        /// Suspected defect 1 (ARCH-MODEL-SPLIT, 2026-10-29): the wait gives up after 15 s with the pass still in
        /// flight and the caller's write lands in the partial `report`. Every controller that writes after this wait
        /// (TimeMachineController since block 4, SecurityController and CrashReportsController since block 6) re-assesses
        /// through host.reassess, so the partial is never assessed; the write itself still lands in it (PASS-WAIT-PARTIAL). This test pins
        /// the seam's current contract; the fix row adds the assess-site test and flips the expectations below.
        @Test func awaitPassEndGivesUpAfter15s() async {
            let (m, _, clock, cleanup) = makeModel(); defer { cleanup() }
            m.isCollectingReport = true
            let ended = await m.reportHost.awaitPassEnd()
            #expect(ended == false)                   // gave up: 75 polls × 200 ms = 15 s of virtual time
            #expect(clock.sleeps.count == 75)
            #expect(clock.now == clock.base.addingTimeInterval(15))
            #expect(m.isCollectingReport == true)
            m.reportHost.write(\.energy, energy)
            #expect(m.report.energy == energy)        // the write landed in the partial…
            #expect(m.homeReport.energy == nil)       // …not in the committed report the views and the assessment use
        }

        // 6 (R12: a cancelled caller does not spin through the 15 s bound)
        @Test func awaitPassEndEndsAtOnceWhenCancelled() async {
            let (m, _, clock, cleanup) = makeModel(); defer { cleanup() }
            m.isCollectingReport = true
            let t = Task { await m.reportHost.awaitPassEnd() }
            t.cancel()
            let ended = await t.value
            #expect(ended == false)
            #expect(clock.sleeps.isEmpty)
        }

        @Test func reassessUsesTheCommittedReport() {
            let (m, s, _, cleanup) = makeModel(); defer { cleanup() }
            // Part 1: reassess runs at all (no automatic reassess on a plain field write).
            s.lowSpacePercent = 15                     // reassesses now, with no disk reading: no warning
            m.disk = DiskInfo(size: 100 * GIB, avail: 12 * GIB)
            #expect(m.assessment.diskSev != .warn)
            m.reportHost.reassess()
            #expect(m.assessment.diskSev == .warn)
            // Part 2 (M4): while a pass is in flight it assesses the committed report, not the partial.
            func downloadsTip() -> Bool { m.assessment.tips.contains { $0.text.contains("Загрузки") } }   // AssessmentTests:337
            m.isCollectingReport = true
            m.report.homeDirs = [DirSize(path: "/Users/x/Downloads", bytes: 11 * GIB)]
            m.reportHost.reassess()
            #expect(!downloadsTip())                   // lastCommittedReport is still blank
            m.isCollectingReport = false
            m.reportHost.reassess()
            #expect(downloadsTip())
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
