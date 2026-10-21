// Tests/MacDashboardTests/TimeMachineStatusTests.swift
// REDESIGN-BACKUPS: `tmutil status` parser (XML plist and OpenStep forms) over the idle capture and a synthetic
// Copying-phase fixture. No test here runs tmutil.
import Foundation
import Testing
@testable import MacDashboard

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
