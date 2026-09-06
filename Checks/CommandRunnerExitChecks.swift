// Checks/CommandRunnerExitChecks.swift
// V21-HONEST-EXITS: coverage for CommandRunner's exit-status-driven empty-stdout rule.
// Real check code (NOT a symlink — see README.md); `check()` is main.swift's
// top-level helper, visible here because both files compile into the same module.

import Foundation

func runCommandRunnerExitChecks() {
    check(CommandRunner.run("/bin/sh", ["-c", "exit 0"], timeout: 5) == "",
          "CommandRunner.run: exit 0, empty stdout ⇒ \"\" (an empty answer, not a failure)")
    check(CommandRunner.run("/bin/sh", ["-c", "exit 3"], timeout: 5) == nil,
          "CommandRunner.run: non-zero exit, empty stdout ⇒ nil")
    check(CommandRunner.run("/bin/sh", ["-c", "echo x; exit 3"], timeout: 5) == "x\n",
          "CommandRunner.run: non-zero exit WITH stdout ⇒ the stdout text (unchanged)")
    check(CommandRunner.run("/bin/sh", ["-c", "kill -9 $$"], timeout: 5) == nil,
          "CommandRunner.run: death by signal ⇒ nil, not \"\" (not a clean exit)")
    check(CommandRunner.run("/no/such/binary-macdashboard", [], timeout: 5) == nil,
          "CommandRunner.run: launch failure ⇒ nil")

    check(CommandRunner.runNonEmpty("/bin/sh", ["-c", "exit 0"], timeout: 5) == nil,
          "CommandRunner.runNonEmpty: exit 0, empty stdout ⇒ nil (an empty answer supports no claim)")
    check(CommandRunner.runNonEmpty("/bin/sh", ["-c", "printf ' \\n'"], timeout: 5) == nil,
          "CommandRunner.runNonEmpty: whitespace-only stdout ⇒ nil")
    check(CommandRunner.runNonEmpty("/bin/echo", ["hi"], timeout: 5) == "hi\n",
          "CommandRunner.runNonEmpty: non-empty stdout ⇒ the stdout text")

    check(CommandRunner.runStreaming("/bin/sh", ["-c", "exit 0"], timeout: 5, onLine: { _, _ in }) == "",
          "CommandRunner.runStreaming: exit 0, empty stdout ⇒ \"\" (same rule as run)")
    check(CommandRunner.runStreaming("/bin/sh", ["-c", "exit 1"], timeout: 5, onLine: { _, _ in }) == nil,
          "CommandRunner.runStreaming: non-zero exit, empty stdout ⇒ nil")
}
