// Checks/CommandRunnerCoreChecks.swift
// RUNNER-CORE: coverage for the posix_spawn/process-group runner and its CommandOutcome
// contract. Real check code (NOT a symlink — see README.md).

import Foundation
#if canImport(Darwin)
import Darwin
#endif

func runCommandRunnerCoreChecks() {
    // MARK: - CommandOutcome.termination(killReason:waitStatus:outputCut:)

    check(CommandOutcome.termination(killReason: nil, waitStatus: 0) == .exited(0),
          "CommandOutcome.termination: (nil, exit 0) ⇒ .exited(0)")
    check(CommandOutcome.termination(killReason: nil, waitStatus: 3 << 8) == .exited(3),
          "CommandOutcome.termination: (nil, exit 3) ⇒ .exited(3)")
    check(CommandOutcome.termination(killReason: nil, waitStatus: 9) == .signaled(9),
          "CommandOutcome.termination: (nil, signal 9) ⇒ .signaled(9)")
    check(CommandOutcome.termination(killReason: nil, waitStatus: 0x80 | 11) == .signaled(11),
          "CommandOutcome.termination: (nil, signal 11 + core-dump bit) ⇒ .signaled(11), core-dump bit ignored")
    check(CommandOutcome.termination(killReason: nil, waitStatus: nil) == .signaled(0),
          "CommandOutcome.termination: (nil, nil status) ⇒ .signaled(0)")
    // RUNNER-HANG C-M2c regression: a kill reason no longer overrides a clean exit whose output is complete.
    check(CommandOutcome.termination(killReason: .timedOut, waitStatus: 0) == .exited(0),
          "CommandOutcome.termination: (.timedOut, clean exit 0, output complete) ⇒ .exited(0) — C-M2c")
    check(CommandOutcome.termination(killReason: .cancelled, waitStatus: 3 << 8) == .exited(3),
          "CommandOutcome.termination: (.cancelled, exit 3, output complete) ⇒ .exited(3)")
    check(CommandOutcome.termination(killReason: .cancelled, waitStatus: 0x80 | 11) == .signaled(11),
          "CommandOutcome.termination: (.cancelled, its own signal 11) ⇒ .signaled(11)")
    check(CommandOutcome.termination(killReason: .timedOut, waitStatus: 9) == .timedOut,
          "CommandOutcome.termination: (.timedOut, SIGKILL) ⇒ .timedOut")
    check(CommandOutcome.termination(killReason: .cancelled, waitStatus: 9) == .cancelled,
          "CommandOutcome.termination: (.cancelled, SIGKILL) ⇒ .cancelled")
    check(CommandOutcome.termination(killReason: .timedOut, waitStatus: nil) == .timedOut,
          "CommandOutcome.termination: (.timedOut, status unknown) ⇒ .timedOut")
    check(CommandOutcome.termination(killReason: .timedOut, waitStatus: 0, outputCut: true) == .timedOut,
          "CommandOutcome.termination: (.timedOut, exit 0, output cut) ⇒ .timedOut")
    check(CommandOutcome.termination(killReason: .cancelled, waitStatus: 3 << 8, outputCut: true) == .cancelled,
          "CommandOutcome.termination: (.cancelled, exit 3, output cut) ⇒ .cancelled")

    // MARK: - CommandOutcome.text

    check(CommandOutcome(termination: .exited(0), stdout: "", stdoutTruncated: false, stderrHead: "").text == "",
          "CommandOutcome.text: exited(0) + \"\" ⇒ \"\"")
    check(CommandOutcome(termination: .exited(3), stdout: "", stdoutTruncated: false, stderrHead: "").text == nil,
          "CommandOutcome.text: exited(3) + \"\" ⇒ nil")
    check(CommandOutcome(termination: .exited(3), stdout: "x", stdoutTruncated: false, stderrHead: "").text == "x",
          "CommandOutcome.text: exited(3) + \"x\" ⇒ \"x\"")
    check(CommandOutcome(termination: .signaled(9), stdout: "", stdoutTruncated: false, stderrHead: "").text == nil,
          "CommandOutcome.text: signaled(9) + \"\" ⇒ nil")
    check(CommandOutcome(termination: .signaled(9), stdout: "x", stdoutTruncated: false, stderrHead: "").text == "x",
          "CommandOutcome.text: signaled(9) + \"x\" ⇒ \"x\"")
    check(CommandOutcome(termination: .timedOut, stdout: "x", stdoutTruncated: false, stderrHead: "").text == nil,
          "CommandOutcome.text: timedOut + \"x\" ⇒ nil")
    check(CommandOutcome(termination: .cancelled, stdout: "x", stdoutTruncated: false, stderrHead: "").text == nil,
          "CommandOutcome.text: cancelled + \"x\" ⇒ nil")
    check(CommandOutcome.launchFailed(2).text == nil,
          "CommandOutcome.text: launchFailed(2) ⇒ nil")

    // MARK: - CommandOutcome.nonEmptyText

    check(CommandOutcome(termination: .exited(0), stdout: " \n", stdoutTruncated: false, stderrHead: "").nonEmptyText == nil,
          "CommandOutcome.nonEmptyText: exited(0) + \" \\n\" ⇒ nil")
    check(CommandOutcome(termination: .exited(0), stdout: "hi\n", stdoutTruncated: false, stderrHead: "").nonEmptyText == "hi\n",
          "CommandOutcome.nonEmptyText: exited(0) + \"hi\\n\" ⇒ \"hi\\n\"")

    // MARK: - CappedBuffer

    do {
        var buf = CappedBuffer(cap: 4)
        buf.append(Data("ab".utf8))
        buf.append(Data("cd".utf8))
        check(buf.data == Data("abcd".utf8) && !buf.truncated,
              "CappedBuffer: \"ab\" then \"cd\" (cap 4) ⇒ \"abcd\", truncated false")
        buf.append(Data("e".utf8))
        check(buf.data == Data("abcd".utf8) && buf.truncated,
              "CappedBuffer: then \"e\" ⇒ data unchanged, truncated true")
    }
    do {
        var buf = CappedBuffer(cap: 4)
        buf.append(Data("abcdef".utf8))
        check(buf.data == Data("abcd".utf8) && buf.truncated,
              "CappedBuffer: fresh buffer fed \"abcdef\" (cap 4) ⇒ \"abcd\", truncated true")
    }

    // MARK: - LineSplitter

    do {
        var s = LineSplitter()
        check(s.feed(Data("a\nb".utf8)) == ["a"], "LineSplitter: feed(\"a\\nb\") ⇒ [\"a\"]")
        check(s.finish() == "b", "LineSplitter: finish() ⇒ \"b\"")
        check(s.finish() == nil, "LineSplitter: finish() again ⇒ nil")
    }
    do {
        var s = LineSplitter()
        check(s.feed(Data("x\r\n".utf8)) == ["x"], "LineSplitter: feed(\"x\\r\\n\") ⇒ [\"x\"] (trailing \\r stripped)")
    }
    do {
        var s = LineSplitter()
        check(s.feed(Data("\n".utf8)) == [""], "LineSplitter: feed(\"\\n\") ⇒ [\"\"]")
    }
    do {
        var s = LineSplitter()
        check(s.feed(Data("ab".utf8)) == [], "LineSplitter: feed(\"ab\") ⇒ []")
        check(s.feed(Data("c\nd\n".utf8)) == ["abc", "d"], "LineSplitter: then feed(\"c\\nd\\n\") ⇒ [\"abc\", \"d\"]")
        check(s.finish() == nil, "LineSplitter: finish() ⇒ nil (nothing pending)")
    }
    do {
        var s = LineSplitter(cap: 4)
        check(s.feed(Data("abcdef".utf8)) == ["abcdef"],
              "LineSplitter(cap: 4): feed(\"abcdef\") ⇒ [\"abcdef\"] (over cap, delivered whole)")
        check(s.finish() == nil, "LineSplitter(cap: 4): finish() ⇒ nil")
    }

    // MARK: - Real processes

    // Process group on timeout (R3): the grandchild is killed with its group.
    do {
        let start = Date()
        let outcome = runCommand("/bin/sh", ["-c", "sleep 30 & echo $!; wait"], timeout: 1)
        let elapsed = Date().timeIntervalSince(start)
        check(outcome.termination == .timedOut, "process group on timeout: termination == .timedOut")
        check(elapsed < 3, "process group on timeout: elapsed < 3 s (was \(elapsed))")
        let pid = pid_t(outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        check(pid > 0, "process group on timeout: a pid was parsed from stdout")
        var reaped = false
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH { reaped = true; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        check(reaped, "process group on timeout: the grandchild was killed with its group")
    }

    // Post-exit sweep (R3): a leftover background child is swept when the leader exits.
    do {
        let start = Date()
        let outcome = runCommand("/bin/sh", ["-c", "sleep 30 & echo $!"], timeout: 10)
        let elapsed = Date().timeIntervalSince(start)
        check(outcome.termination == .exited(0), "post-exit sweep: termination == .exited(0)")
        check(elapsed < 3, "post-exit sweep: elapsed < 3 s (was \(elapsed)) — no fixed 3 s drain bound")
        let pid = pid_t(outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        check(pid > 0, "post-exit sweep: a pid was parsed from stdout")
        var reaped = false
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH { reaped = true; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        check(reaped, "post-exit sweep: the leftover background child was killed")
    }

    // Cancellation, plain run (R4).
    do {
        let start = Date()
        let task = Task { await CommandRunner.run("/bin/sleep", ["10"], timeout: 30) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { task.cancel() }
        let o = runAsyncBlocking { await task.value }
        let elapsed = Date().timeIntervalSince(start)
        check(o.termination == .cancelled, "cancellation, plain run: termination == .cancelled")
        check(o.text == nil, "cancellation, plain run: text == nil")
        check(elapsed < 3, "cancellation, plain run: elapsed < 3 s (was \(elapsed))")
    }

    // Pre-cancelled run spawns nothing (R4).
    do {
        let marker = NSTemporaryDirectory() + "macdashboard-precancel-\(getpid())"
        unlink(marker)
        let o = runAsyncBlocking { () async -> CommandOutcome in
            withUnsafeCurrentTask { $0?.cancel() }
            return await CommandRunner.run("/usr/bin/touch", [marker], timeout: 5)
        }
        check(o.termination == .cancelled, "pre-cancelled run: termination == .cancelled")
        check(!FileManager.default.fileExists(atPath: marker), "pre-cancelled run: nothing was spawned (marker absent)")
        unlink(marker)
    }

    // Streaming cancellation (R0(a)/R4).
    do {
        let lines = LockedLines()
        let start = Date()
        let task = Task {
            await CommandRunner.run("/bin/sh", ["-c", "while :; do echo tick; sleep 0.1; done"], timeout: 30,
                                    onLine: { l, e in lines.append(l, e) })
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { task.cancel() }
        let o = runAsyncBlocking { await task.value }
        let elapsed = Date().timeIntervalSince(start)
        check(o.termination == .cancelled, "streaming cancellation: termination == .cancelled")
        check(lines.lines.count >= 2, "streaming cancellation: at least 2 lines delivered (got \(lines.lines.count))")
        check(lines.lines.allSatisfy { $0.0 == "tick" }, "streaming cancellation: every delivered line == \"tick\"")
        check(elapsed < 3, "streaming cancellation: elapsed < 3 s (was \(elapsed))")
    }

    // Unaffected run.
    check(runCommand("/bin/echo", ["hi"], timeout: 5).text?.trimmingCharacters(in: .whitespacesAndNewlines) == "hi",
          "unaffected run: /bin/echo hi ⇒ \"hi\"")

    // stderrHead (R2).
    do {
        let o = runCommand("/bin/sh", ["-c", "echo oops >&2; exit 2"], timeout: 5)
        check(o.termination == .exited(2), "stderrHead: exit 2 ⇒ .exited(2)")
        check(o.stderrHead == "oops\n", "stderrHead: captured \"oops\\n\"")
        check(o.text == nil, "stderrHead: text == nil (empty stdout, non-zero exit)")
    }
    do {
        let o = runCommand("/bin/sh", ["-c", "head -c 5000 /dev/zero | tr '\\0' e >&2"], timeout: 5)
        check(o.stderrHead.utf8.count == CommandRunner.stderrHeadCap,
              "stderrHead: capped at CommandRunner.stderrHeadCap bytes")
        check(o.text == "", "stderrHead: text == \"\" (empty stdout, clean exit)")
    }

    // R6: relative path.
    do {
        let marker2 = NSTemporaryDirectory() + "macdashboard-r6-\(getpid())"
        unlink(marker2)
        let o = runCommand("touch", [marker2], timeout: 5)
        check(o.termination == .launchFailed(EINVAL), "R6: a relative path ⇒ .launchFailed(EINVAL)")
        check(!FileManager.default.fileExists(atPath: marker2), "R6: nothing was spawned (marker absent)")
        unlink(marker2)
    }

    // Fast-exit reaping: a missed reap would show up as .timedOut.
    do {
        let start = Date()
        var allExited = true
        for _ in 0..<30 {
            if runCommand("/usr/bin/true", [], timeout: 5).termination != .exited(0) { allExited = false }
        }
        let elapsed = Date().timeIntervalSince(start)
        check(allExited, "fast-exit reaping: 30 sequential runs all give .exited(0)")
        check(elapsed < 15, "fast-exit reaping: total elapsed < 15 s (was \(elapsed))")
    }

    // MARK: - COLLECT-FASTPATH: QoS plumbing
    check(CommandQoS.utility.spawnQoSClass == QOS_CLASS_UTILITY, "CommandQoS.utility.spawnQoSClass == QOS_CLASS_UTILITY")
    check(CommandQoS.userInitiated.spawnQoSClass == nil, "CommandQoS.userInitiated.spawnQoSClass == nil")
    check(CommandQoS.utility.threadQoS == .utility, "CommandQoS.utility.threadQoS == .utility")
    check(CommandQoS.userInitiated.threadQoS == .userInitiated, "CommandQoS.userInitiated.threadQoS == .userInitiated")
    do {
        // Runtime proof (R9): the child reports its own scheduling priority.
        let u = runAsyncBlocking { await CommandRunner.$qos.withValue(.utility) {
            await CommandRunner.run("/bin/sh", ["-c", "/bin/ps -o pri= -p $$"], timeout: 10) } }
        let d = runAsyncBlocking {
            await CommandRunner.run("/bin/sh", ["-c", "/bin/ps -o pri= -p $$"], timeout: 10) }
        let uv = Int(u.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        let dv = Int(d.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        check(uv != nil && dv != nil, "QoS runtime: both children report a priority (u=\(String(describing: uv)), d=\(String(describing: dv)))")
        if let uv, let dv {
            check(uv <= 20, "QoS runtime: utility child runs in the utility band (u=\(uv), d=\(dv))")
            // A CI runner starts this process at utility, so an unclamped child reads 20 there too and the comparison says nothing.
            if dv > 20 {
                check(uv < dv, "QoS runtime: unclamped child runs above the utility child (u=\(uv), d=\(dv))")
            } else {
                check(true, "QoS runtime: ambient QoS is already utility (d=\(dv)), comparison skipped (u=\(uv))")
            }
        }
    }
}
