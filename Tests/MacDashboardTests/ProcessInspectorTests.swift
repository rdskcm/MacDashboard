// Tests/MacDashboardTests/ProcessInspectorTests.swift
// REDESIGN-CPU: owner lookup, signal result mapping, privileged command, the signal flow with injected closures.
// No test signals a real process other than signal 0 (existence check) to its own pid.
import Foundation
import Darwin
import Testing
@testable import MacDashboard

struct ProcessInspectorTests {
    @Test func ownerLookup() {
        #expect(ProcessInspector.owner(for: getpid()) == NSUserName())
        #expect(ProcessInspector.owner(for: 1) == "root")
        #expect(ProcessInspector.userName(uid: 0) == "root")
        #expect(ProcessInspector.userName(uid: 4_000_000) == "4000000")
    }

    @Test func detailOfSelf() {
        let d = ProcessInspector.detail(pid: getpid())
        #expect(d.path != nil)
        #expect(d.owner == NSUserName())
    }

    @Test func sendSignalMapping() {
        #expect(ProcessInspector.sendSignal(0, to: getpid()) == .sent, "signal 0 only checks existence")
        #expect(ProcessInspector.sendSignal(SIGKILL, to: 0) == .refused, "pid 0 would signal the whole process group")
        #expect(ProcessInspector.sendSignal(SIGKILL, to: 1) == .refused, "pid 1 is launchd")
        #expect(ProcessInspector.sendSignal(SIGKILL, to: -5) == .refused)
    }

    @Test func privilegedCommand() {
        #expect(ProcessInspector.privilegedSignalCommand(15, pid: 1234) == "/bin/kill -15 1234")
        #expect(ProcessInspector.privilegedSignalCommand(9, pid: 1) == nil)
        #expect(ProcessInspector.privilegedSignalCommand(9, pid: 0) == nil)
    }

    @Test func pathMismatchIsGone() {
        var sends = 0
        let r = ProcessInspector.signal(15, pid: 500, expectedPath: "/a/b",
                                        send: { _, _ in sends += 1; return .sent },
                                        pathOf: { _ in "/other" },
                                        privileged: { _ in .success })
        #expect(r == .gone)
        #expect(sends == 0, "no signal after a path change")
    }

    @Test func nilExpectedPathSkipsGuard() {
        let r = ProcessInspector.signal(15, pid: 500, expectedPath: nil,
                                        send: { _, _ in .sent },
                                        pathOf: { _ in nil },
                                        privileged: { _ in .failed("unused") })
        #expect(r == .sent)
    }

    @Test func notPermittedRetriesPrivileged() {
        func run(_ outcome: PrivilegedRunner.Outcome) -> (ProcessInspector.SignalOutcome, [String]) {
            var commands: [String] = []
            let r = ProcessInspector.signal(9, pid: 500, expectedPath: "/a",
                                            send: { _, _ in .notPermitted },
                                            pathOf: { _ in "/a" },
                                            privileged: { commands.append($0); return outcome })
            return (r, commands)
        }
        let ok = run(.success)
        #expect(ok.0 == .sent && ok.1 == ["/bin/kill -9 500"])
        #expect(run(.cancelled).0 == .cancelled)
        #expect(run(.failed("x")).0 == .failed)
    }

    @Test func otherResultsNeverPrivileged() {
        func run(_ result: ProcessInspector.SignalResult) -> (ProcessInspector.SignalOutcome, Int) {
            var calls = 0
            let r = ProcessInspector.signal(15, pid: 500, expectedPath: "/a",
                                            send: { _, _ in result },
                                            pathOf: { _ in "/a" },
                                            privileged: { _ in calls += 1; return .success })
            return (r, calls)
        }
        #expect(run(.sent) == (.sent, 0))
        #expect(run(.gone) == (.gone, 0))
        #expect(run(.refused) == (.failed, 0))
        #expect(run(.failed) == (.failed, 0))
    }

    @Test func notPermittedOnLowPidFails() {
        var calls = 0
        let r = ProcessInspector.signal(15, pid: 1, expectedPath: nil,
                                        send: { _, _ in .notPermitted },
                                        pathOf: { _ in nil },
                                        privileged: { _ in calls += 1; return .success })
        #expect(r == .failed)
        #expect(calls == 0, "no privileged command is built for pid <= 1")
    }
}
