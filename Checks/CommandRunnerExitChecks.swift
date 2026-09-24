// Checks/CommandRunnerExitChecks.swift
// V21-HONEST-EXITS: coverage for CommandRunner's exit-status-driven empty-stdout rule.
// Real check code (NOT a symlink — see README.md); `check()` is main.swift's
// top-level helper, visible here because both files compile into the same module.

import Foundation

/// Synchronous bridge for checks: one CommandRunner.run, awaited via runAsyncBlocking.
func runCommand(_ path: String, _ args: [String], timeout: TimeInterval,
                environment: [String: String] = CommandRunner.defaultEnvironment,
                onLine: ((String, Bool) -> Void)? = nil) -> CommandOutcome {
    runAsyncBlocking { await CommandRunner.run(path, args, timeout: timeout, environment: environment, onLine: onLine) }
}

func runCommandRunnerExitChecks() {
    check(runCommand("/bin/sh", ["-c", "exit 0"], timeout: 5).text == "",
          "CommandRunner.run(...).text: exit 0, empty stdout ⇒ \"\" (an empty answer, not a failure)")
    check(runCommand("/bin/sh", ["-c", "exit 3"], timeout: 5).text == nil,
          "CommandRunner.run(...).text: non-zero exit, empty stdout ⇒ nil")
    check(runCommand("/bin/sh", ["-c", "echo x; exit 3"], timeout: 5).text == "x\n",
          "CommandRunner.run(...).text: non-zero exit WITH stdout ⇒ the stdout text (unchanged)")
    check(runCommand("/bin/sh", ["-c", "kill -9 $$"], timeout: 5).text == nil,
          "CommandRunner.run(...).text: death by signal ⇒ nil, not \"\" (not a clean exit)")
    check(runCommand("/no/such/binary-macdashboard", [], timeout: 5).text == nil,
          "CommandRunner.run(...).text: launch failure ⇒ nil")
    check(runCommand("/no/such/binary-macdashboard", [], timeout: 5).termination == .launchFailed(ENOENT),
          "CommandRunner.run: launch failure ⇒ .launchFailed(ENOENT)")

    check(runCommand("/bin/sh", ["-c", "exit 0"], timeout: 5).nonEmptyText == nil,
          "CommandRunner.run(...).nonEmptyText: exit 0, empty stdout ⇒ nil (an empty answer supports no claim)")
    check(runCommand("/bin/sh", ["-c", "printf ' \\n'"], timeout: 5).nonEmptyText == nil,
          "CommandRunner.run(...).nonEmptyText: whitespace-only stdout ⇒ nil")
    check(runCommand("/bin/echo", ["hi"], timeout: 5).nonEmptyText == "hi\n",
          "CommandRunner.run(...).nonEmptyText: non-empty stdout ⇒ the stdout text")

    check(runCommand("/bin/sh", ["-c", "exit 0"], timeout: 5, onLine: { _, _ in }).text == "",
          "CommandRunner.run(onLine) .text: exit 0, empty stdout ⇒ \"\" (same rule as run)")
    check(runCommand("/bin/sh", ["-c", "exit 1"], timeout: 5, onLine: { _, _ in }).text == nil,
          "CommandRunner.run(onLine) .text: non-zero exit, empty stdout ⇒ nil")
}
