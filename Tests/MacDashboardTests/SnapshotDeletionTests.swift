// Tests/MacDashboardTests/SnapshotDeletionTests.swift
// STORAGE-ACTIONS-COPY Stage 2: the pure parts of the deletion. Nothing here deletes anything.
import Foundation
import Testing
@testable import MacDashboard

struct SnapshotDeletionTests {
    private let name = "com.apple.TimeMachine.2026-11-03-043250.local"

    @Test func dateFromName() {
        #expect(SnapshotDeletion.date(fromName: name) == "2026-11-03-043250")
        for bad in ["", "2026-11-03-043250", "com.apple.TimeMachine.2026-11-03-043250", "com.apple.TimeMachine.2026-11-03-04325.local",
                    "com.apple.TimeMachine.2026-11-03-0432500.local", "com.apple.TimeMachine.2026-11-03_043250.local",
                    "com.apple.TimeMachine.-026-11-03-043250.local", "com.apple.TimeMachine.--all-------------.local",
                    "com.apple.TimeMachine.٢٠٢٦-11-03-043250.local", "com.apple.TimeMachine.2026-11-03-04 250.local",
                    "com.apple.other.2026-11-03-043250.local"] {
            #expect(SnapshotDeletion.date(fromName: bad) == nil, "\(bad)")
        }
    }

    @Test func argumentsAreTheTestedDateForm() {
        #expect(SnapshotDeletion.arguments(date: "2026-11-03-043250") == ["deletelocalsnapshots", "2026-11-03-043250"])
        #expect(SnapshotDeletion.timeoutSeconds == 60)
        #expect(SnapshotDeletion.tmutilPath == "/usr/bin/tmutil")
    }

    @Test func environmentKeepsLocalTimeZone() async {
        #expect(SnapshotDeletion.environment["TZ"] == nil)
        #expect(SnapshotDeletion.environment["LC_ALL"] == "C")
        let out = await CommandRunner.run("/bin/date", ["+%z"], timeout: 5, environment: SnapshotDeletion.environment)
        let secs = TimeZone.current.secondsFromGMT()
        let expected = "\(secs < 0 ? "-" : "+")\(String(format: "%02d", abs(secs) / 3600))\(String(format: "%02d", (abs(secs) % 3600) / 60))"
        #expect(out.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
    }

    @Test func planDeletesOnlyConfirmedNamesStillThere() {
        let a = "com.apple.TimeMachine.2026-11-03-043250.local", b = "com.apple.TimeMachine.2026-11-03-053250.local"
        let newer = "com.apple.TimeMachine.2026-11-03-063250.local"
        #expect(SnapshotDeletion.plan(confirmed: [a, b], current: [a, b, newer]) == .init(dates: ["2026-11-03-043250", "2026-11-03-053250"], unparsable: 0))
        #expect(SnapshotDeletion.plan(confirmed: [a, b], current: [b]) == .init(dates: ["2026-11-03-053250"], unparsable: 0))
        #expect(SnapshotDeletion.plan(confirmed: [a, b], current: []) == .init(dates: [], unparsable: 0))
        #expect(SnapshotDeletion.plan(confirmed: [a, b], current: nil) == .init(dates: ["2026-11-03-043250", "2026-11-03-053250"], unparsable: 0))
        #expect(SnapshotDeletion.plan(confirmed: [a, "com.apple.TimeMachine.bad.local"], current: nil) == .init(dates: ["2026-11-03-043250"], unparsable: 1))
    }

    private func outcome(_ t: CommandOutcome.Termination, stdout: String = "", stderr: String = "") -> CommandOutcome {
        CommandOutcome(termination: t, stdout: stdout, stdoutTruncated: false, stderrHead: stderr)
    }

    @Test func verdicts() {
        #expect(SnapshotDeletion.verdict(outcome(.exited(0), stdout: "Deleted local snapshot '2026-11-03-043250'\n")) == .deleted)
        let measured = outcome(.exited(70), stderr: "Failed to delete local snapshot '1999-01-01-000000'\nCommand exited with status 70 (EX_SOFTWARE).\n")
        #expect(SnapshotDeletion.verdict(measured) == .failed(.tool("Failed to delete local snapshot '1999-01-01-000000'"), stopsTheRun: false))
        #expect(SnapshotDeletion.verdict(outcome(.exited(1), stderr: "tmutil requires Full Disk Access privileges.\n")) == .failed(.permission, stopsTheRun: true))
        #expect(SnapshotDeletion.verdict(outcome(.exited(1), stdout: "Operation not permitted\n")) == .failed(.permission, stopsTheRun: true))
        #expect(SnapshotDeletion.verdict(outcome(.exited(1))) == .failed(.tool(nil), stopsTheRun: false))
        #expect(SnapshotDeletion.verdict(outcome(.signaled(9))) == .failed(.tool(nil), stopsTheRun: false))
        #expect(SnapshotDeletion.verdict(outcome(.timedOut)) == .failed(.timedOut, stopsTheRun: true))
        #expect(SnapshotDeletion.verdict(outcome(.launchFailed(2))) == .failed(.tool(nil), stopsTheRun: true))
        #expect(SnapshotDeletion.verdict(outcome(.cancelled)) == .failed(.tool(nil), stopsTheRun: true))
    }

    @Test func onlyTheAppItselfMayRunTheRealDelete() throws {
        #expect(SnapshotDeletion.mayRunRealDelete(bundleID: "app.moonport", visualFixture: false))
        #expect(!SnapshotDeletion.mayRunRealDelete(bundleID: "app.moonport", visualFixture: true))
        #expect(!SnapshotDeletion.mayRunRealDelete(bundleID: "app.moonport.bench", visualFixture: false))
        #expect(!SnapshotDeletion.mayRunRealDelete(bundleID: nil, visualFixture: false))
        #expect(!SnapshotDeletion.mayRunRealDelete(bundleID: Bundle.main.bundleIdentifier, visualFixture: false), "this test process is refused")
        // A renamed bundle id must fail here, not at the user's click.
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build_app.sh")
        #expect(try String(contentsOf: script, encoding: .utf8).contains("<string>\(SnapshotDeletion.appBundleID)</string>"))
    }
}
