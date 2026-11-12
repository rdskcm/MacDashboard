// Tests/MoonportTests/TimeMachineStatusTests.swift
// REDESIGN-BACKUPS: `tmutil status` parser (XML plist and OpenStep forms) over the idle capture and a synthetic
// Copying-phase fixture. No test here runs tmutil.
import Foundation
import Testing
@testable import Moonport

struct TimeMachineStatusTests {
    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: fixturesRoot.appendingPathComponent("tmutil-status/" + name), encoding: .utf8)
    }

    @Test func idleCapture() throws {
        let p = try #require(TimeMachineStatus.parse(text: try fixture("tmutil-status-macos27.0.txt")))
        #expect(p.running == false)
        #expect(p.stopping == false)
        #expect(p.percent == nil, "Percent -1 means unknown")
        #expect(p.bytesTotal == nil)
    }

    @Test func backingSynthetic() throws {
        let p = try #require(TimeMachineStatus.parse(text: try fixture("tmutil-status-backing-synthetic.txt")))
        #expect(p.running == true)
        #expect(p.stopping == false)
        #expect(p.phase == "Copying")
        #expect(p.percent == 0.140625)
        #expect(p.bytesDone == 1_800_000_000)
        #expect(p.bytesTotal == 12_800_000_000)
        #expect(p.secondsRemaining == 600)
        #expect(p.destinationMountPoint == "/Volumes/Backup")
    }

    @Test func copyingLiveCapture() throws {
        let p = try #require(TimeMachineStatus.parse(text: try fixture("tmutil-status-macos27.0-copying.txt")))
        #expect(p.running == true)
        #expect(p.phase == "Copying")
        #expect(abs(try #require(p.percent) - 0.2664) < 0.0005)
        #expect(p.bytesDone == 16_728_473_600)
        #expect(p.bytesTotal == 113_784_774_656)
        #expect(p.secondsRemaining == 371)
    }

    @Test func findingChangesLiveCapture() throws {
        let p = try #require(TimeMachineStatus.parse(text: try fixture("tmutil-status-macos27.0-findingchanges.txt")))
        #expect(p.running == true)
        #expect(p.phase == "FindingChanges")
        #expect(p.changedItems == 4)
        #expect(p.scanFraction == 0)
        #expect(p.percent == nil)
    }

    @Test func barShareIsReadInBothForms() throws {
        let copying = try #require(TimeMachineStatus.parse(text: try fixture("tmutil-status-macos27.0-copying.txt")))
        #expect(abs((copying.barShare ?? -1) - 0.9) < 1e-9)
        let scan = try #require(TimeMachineStatus.parse(text: try fixture("tmutil-status-macos27.0-findingchanges.txt")))
        #expect(abs((scan.barShare ?? -1) - 0.1) < 1e-9)
        #expect(TimeMachineStatus.parse(text: try fixture("tmutil-status-backing-synthetic.txt"))?.barShare == nil)
        #expect(TimeMachineStatus.parse(text: "{ Running = 1; FractionOfProgressBar = \"0\"; }")?.barShare == nil)
        #expect(TimeMachineStatus.parse(text: "{ Running = 1; FractionOfProgressBar = \"1.5\"; }")?.barShare == nil)
    }

    @Test func overallFractionPerPhase() {
        func p(_ phase: String?, percent: Double? = nil, scan: Double? = nil, share: Double? = nil) -> TMBackupProgress {
            TMBackupProgress(running: true, stopping: false, phase: phase, percent: percent, scanFraction: scan, barShare: share)
        }
        func near(_ a: Double?, _ b: Double) -> Bool { abs((a ?? -1) - b) < 1e-4 }
        // The live sample compared with the macOS menu: 41.1 %.
        #expect(near(TimeMachineStatus.overallFraction(p("Copying", percent: 0.34509, share: 0.9)), 0.41058))
        #expect(near(TimeMachineStatus.overallFraction(p("FindingChanges", scan: 0.5411, share: 0.1)), 0.05411))
        // The key is what decides, and the constants apply when it is absent.
        #expect(near(TimeMachineStatus.overallFraction(p("Copying", percent: 0.5, share: 0.8)), 0.6))
        #expect(near(TimeMachineStatus.overallFraction(p("Copying", percent: 0.34509)), 0.41058))
        #expect(near(TimeMachineStatus.overallFraction(p("FindingChanges", scan: 1)), 0.1))
        // Every other phase, and a missing input: the moving line.
        for phase in ["PreparingSourceVolumes", "Finishing", "ThinningPostBackup", "Stopping"] {
            #expect(TimeMachineStatus.overallFraction(p(phase, percent: 0.5, scan: 0.5, share: 0.9)) == nil, "\(phase)")
        }
        #expect(TimeMachineStatus.overallFraction(p(nil, percent: 0.5)) == nil)
        #expect(TimeMachineStatus.overallFraction(p("Copying")) == nil)
        #expect(TimeMachineStatus.overallFraction(p("FindingChanges")) == nil)
    }

    /// The samples around the transition in inputs/DISK-MOUNT-LIVE-rig/tmstatus.log (16:18:13 to 16:18:37).
    @Test func theBarDoesNotFallWhenCopyingStarts() {
        let samples = [
            TMBackupProgress(running: true, stopping: false, phase: "FindingChanges", scanFraction: 0.5411460430169746, barShare: 0.1),
            TMBackupProgress(running: true, stopping: false, phase: "FindingChanges", scanFraction: 1, barShare: 0.1),
            TMBackupProgress(running: true, stopping: false, phase: "Copying", percent: 4.224406603789782e-05, barShare: 0.9),
            TMBackupProgress(running: true, stopping: false, phase: "Copying", percent: 0.1647264620475237, barShare: 0.9),
        ]
        let bars = samples.compactMap(TimeMachineStatus.overallFraction)
        #expect(bars.count == 4)
        #expect(bars == bars.sorted())
    }

    @Test func topLevelPercentFallback() {
        #expect(TimeMachineStatus.parse(text: "{ Running = 1; Percent = \"0.25\"; }")?.percent == 0.25)
        #expect(TimeMachineStatus.parse(text: "{ Running = 1; Percent = \"0.25\"; Progress = { Percent = \"0.5\"; }; }")?.percent == 0.5)
    }

    @Test func openStepForm() {
        let text = "Backup session status:\n{\n    ClientID = \"com.apple.backupd\";\n    Percent = \"-1\";\n    Running = 0;\n}\n"
        let p = TimeMachineStatus.parse(text: text)
        #expect(p?.running == false)
        #expect(p?.percent == nil)
        let half = "Backup session status:\n{\n    Percent = \"0.5\";\n    Running = 1;\n}\n"
        #expect(TimeMachineStatus.parse(text: half)?.percent == 0.5, "a quoted number is read")
        #expect(TimeMachineStatus.parse(text: half)?.running == true)
    }

    @Test func rejectsUndecodable() throws {
        #expect(TimeMachineStatus.parse(text: try fixture("neg-truncated.txt")) == nil)
        #expect(TimeMachineStatus.parse(text: "") == nil)
        #expect(TimeMachineStatus.parse(text: "{ ClientID = \"x\"; }") == nil, "a dictionary without Running")
    }

    @Test func lenientNumbers() {
        #expect(TimeMachineStatus.num(3) == 3)
        #expect(TimeMachineStatus.num(1.5) == 1.5)
        #expect(TimeMachineStatus.num(true) == 1)
        #expect(TimeMachineStatus.num(false) == 0)
        #expect(TimeMachineStatus.num("1") == 1)
        #expect(TimeMachineStatus.num(" 2.5 ") == 2.5)
        #expect(TimeMachineStatus.num("x") == nil)
        #expect(TimeMachineStatus.num(nil) == nil)
    }

    @Test func percentIsClamped() {
        #expect(TimeMachineStatus.parse(text: "{ Running = 1; Percent = \"1.7\"; }")?.percent == 1)
    }
}
