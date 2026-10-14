// Tests/MacDashboardTests/CommandRunnerOnLineTests.swift
// Port of Checks/main.swift lines 1662-1735 (CHECKS-SWIFT-TESTING). CommandRunner.run(onLine:) streaming.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct CommandRunnerOnLineTests {
        @Test func runOnLine() async {
            // =====================================================================
            // MARK: - CommandRunner.run(onLine)
            // =====================================================================

            do {
                let collector = LockedLines()
                let result = await runCommand(
                    "/bin/sh", ["-c", "printf 'a\\nb\\n'; printf 'e\\n' >&2"], timeout: 10,
                    onLine: { line, isStderr in collector.append(line, isStderr) }
                ).text

                #expect(result == "a\nb\n", "CommandRunner.run(onLine): accumulated stdout == \"a\\nb\\n\"")
                let lines = collector.lines
                let stdoutLines = lines.filter { !$0.1 }.map { $0.0 }
                let stderrLines = lines.filter { $0.1 }.map { $0.0 }
                // Order is only asserted per-stream; stdout/stderr interleaving isn't guaranteed.
                #expect(stdoutLines == ["a", "b"], "CommandRunner.run(onLine): stdout lines delivered in order [a, b]")
                #expect(stderrLines == ["e"], "CommandRunner.run(onLine): stderr lines delivered == [e]")
            }

            do {
                let collector = LockedLines()
                let result = await runCommand(
                    "/bin/sh", ["-c", "printf 'no-newline'"], timeout: 10,
                    onLine: { line, isStderr in collector.append(line, isStderr) }
                ).text

                #expect(result == "no-newline", "CommandRunner.run(onLine): partial-line flush returns \"no-newline\"")
                #expect(collector.lines.map(\.0) == ["no-newline"],
                      "CommandRunner.run(onLine): partial-line flush delivers exactly one line")
            }

            do {
                let start = Date()
                let outcome = await runCommand("/bin/sh", ["-c", "sleep 5"], timeout: 1, onLine: { _, _ in })
                let elapsed = Date().timeIntervalSince(start)
                #expect(outcome.termination == .timedOut, "CommandRunner.run(onLine): timeout ⇒ termination == .timedOut")
                #expect(outcome.text == nil, "CommandRunner.run(onLine): timeout ⇒ text == nil")
                #expect(elapsed < 3, "CommandRunner.run(onLine): timeout wall time < 3s (got \(elapsed))")
            }

            do {
                // V2-POLISH B1: run(onLine) must pin the environment it is given, the way
                // the non-streaming calls do — this is what puts Homebrew's own prefix on PATH
                // for `brew upgrade`, not just for the short `--version`/`outdated` calls.
                let env = CommandRunner.environment(prependingPATH: ["/opt/homebrew/bin"])
                let result = await runCommand(
                    "/bin/sh", ["-c", "printf '%s\\n' \"$PATH\""], timeout: 10, environment: env, onLine: { _, _ in }
                ).text
                let path = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(path.hasPrefix("/opt/homebrew/bin:"),
                      "CommandRunner.run(onLine): honours the environment it is passed (PATH prefix), got \(path)")

                let defaulted = await runCommand(
                    "/bin/sh", ["-c", "printf '%s\\n' \"$LC_ALL\""], timeout: 10, onLine: { _, _ in }
                ).text
                #expect(defaulted?.trimmingCharacters(in: .whitespacesAndNewlines) == "C",
                      "CommandRunner.run(onLine): defaults to defaultEnvironment (LC_ALL=C)")
            }
        }
    }
}
