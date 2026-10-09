// Engine/PrivilegedRunner.swift
// Runs a shell command as root: first via plain `sudo` (pam_tid on this machine
// pops the native Touch ID dialog even without a TTY), falling back to an
// osascript administrator-privileges password dialog when sudo fails (Touch ID
// cancelled/unavailable). Synchronous — call off the main actor.

import Foundation

enum PrivilegedRunner {
    enum Outcome: Equatable {
        case success
        case cancelled
        case failed(String)
    }

    /// One child launch: absolute executable, argv without argv[0], timeout. Built by the
    /// pure `*Invocation` functions below and executed by `runProcess` — split so Checks can
    /// verify every argument without running sudo or osascript.
    struct Invocation: Equatable {
        let path: String
        let args: [String]
        let timeout: TimeInterval
    }

    /// Exit code plus captured output of one `Invocation`; exit code -1 = launch failure or timeout.
    struct ProcessResult: Equatable { let exitCode: Int32; let stderr: String; let stdout: String }

    /// Runs `command` as root. Tries plain `sudo` first (Touch ID via pam_tid),
    /// then falls back to an osascript admin-privileges password dialog if `sudo`
    /// failed (Touch ID cancelled/unavailable). Never resets the sudo timestamp
    /// itself (`sudo -k`) — a cached grant making this prompt-less is a feature.
    /// `command` is a raw shell string, not argv — callers MUST quote every
    /// embedded value themselves (use `shellQuoted(_:)` / `removeCommand(paths:)`).
    static func run(_ command: String) -> Outcome {
        run(command, executor: runProcess)
    }

    /// `run(_:)` with the process launcher injected — Checks pass a fake so no real sudo or
    /// osascript ever runs. This is the whole decision flow; `run(_:)` only binds `runProcess`.
    static func run(_ command: String, executor: (Invocation) -> ProcessResult) -> Outcome {
        let sudoResult = executor(sudoInvocation(command))
        if sudoResult.exitCode == 0 { return .success }

        // The privileged command RAN and failed (or sudo timed out / could not launch).
        // Re-running the same failing command as root behind a password dialog just fails
        // again after an unnecessary prompt (V2-SECURITY-AUDIT N1).
        guard Self.isSudoOwnFailure(exitCode: sudoResult.exitCode, stderr: sudoResult.stderr) else {
            return Self.failure(from: sudoResult)
        }

        let osaResult = executor(osascriptInvocation(command))
        if osaResult.exitCode == 0 { return .success }

        if Self.isUserCancellation(exitCode: osaResult.exitCode, stderr: osaResult.stderr) {
            return .cancelled
        }
        return Self.failure(from: osaResult)
    }

    /// `sudo /bin/sh -c <command>`, command passed verbatim as ONE argv element.
    static func sudoInvocation(_ command: String) -> Invocation {
        // Absolute /bin/sh, never the bare name `sh`: sudo resolves a bare command
        // name through the CALLER's PATH (macOS sudoers sets no secure_path), and a
        // shell-launched build inherits group-writable prefixes like /opt/homebrew/bin.
        Invocation(path: "/usr/bin/sudo", args: ["/bin/sh", "-c", command], timeout: 120)
    }

    /// The admin-password fallback: `osascript -e 'do shell script "<command>" with administrator privileges'`.
    static func osascriptInvocation(_ command: String) -> Invocation {
        let script = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        return Invocation(path: "/usr/bin/osascript", args: ["-e", script], timeout: 120)
    }

    /// Body of an AppleScript string literal that decodes back to exactly `s`: backslashes are
    /// doubled FIRST, then double quotes escaped — the reverse order would double the backslash
    /// just placed in front of each quote.
    static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// `s` as one POSIX single-quoted shell word: every `'` becomes `'\''`. Safe for any
    /// content, including newlines and `$`/backticks; it does NOT stop a word that starts
    /// with `-` from being read as an option — end the options with `--` first, as `removeCommand(paths:)` does.
    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `/bin/rm -f -- <paths>` for `run(_:)`, each path one single-quoted word. The `--` ends
    /// rm's option parsing, so a path that starts with `-` is always an operand, never an option.
    static func removeCommand(paths: [String]) -> String {
        "/bin/rm -f -- " + paths.map(shellQuoted).joined(separator: " ")
    }

    /// True when osascript reported the ADMIN-PASSWORD DIALOG being dismissed, i.e.
    /// AppleEvent error -128. Anchored on the trailing `(-128)` error-number field of
    /// osascript's error line, never a bare substring: the command we ran is embedded
    /// in that same text and carries user-controlled file paths, so a plist named
    /// `com.foo-128.plist` whose delete genuinely FAILED used to be reported as a
    /// cancel — no error banner, row restored, user told nothing went wrong.
    /// `do shell script` failures report the shell's exit status (0…255, never
    /// negative) in that field, so `(-128)` is unambiguous. The error number, not the
    /// message, is also what makes this locale-independent.
    static func isUserCancellation(exitCode: Int32, stderr: String) -> Bool {
        guard exitCode == 1 else { return false }
        guard let last = stderr.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }) else { return false }
        return last.hasSuffix("(-128)")
    }

    /// True when SUDO ITSELF refused, as opposed to the privileged command running and
    /// exiting non-zero. sudo exits 1 for its own errors and writes them as `sudo: …`
    /// stderr lines ("a password is required", "a terminal is required to read the
    /// password", "Sorry, try again", "<user> is not in the sudoers file"); a command sudo
    /// actually ran keeps its own exit status and its own stderr. macOS ships sudo
    /// unlocalized, so the prefix is stable across UI languages.
    static func isSudoOwnFailure(exitCode: Int32, stderr: String) -> Bool {
        guard exitCode == 1 else { return false }
        return stderr.split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("sudo:") }
    }

    /// stderr first, then stdout (socketfilterfw and pmset report failures on stdout), then
    /// a last-resort literal — `.failed("")` would render as a blank error banner.
    private static func failure(from result: ProcessResult) -> Outcome {
        for candidate in [result.stderr, result.stdout] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return .failed(String(trimmed.prefix(200))) }
        }
        return .failed("unknown error")
    }

    /// Runs `invocation`, waiting up to its timeout, and returns the
    /// exit code plus captured stdout/stderr (unlike `CommandRunner`, which discards
    /// exit codes — we need them here to distinguish success/cancel/failure).
    static func runProcess(_ invocation: Invocation) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.path)
        process.arguments = invocation.args
        process.standardInput = FileHandle.nullDevice
        // Pinned, like every CommandRunner child: the inherited environment would put
        // an attacker-writable PATH (and vars such as BASH_ENV) in front of a process
        // that is about to become root.
        process.environment = CommandRunner.defaultEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let killGate = KillGate()
        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            killGate.fire(.exited)
            exitSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: -1, stderr: "launch failed: \(error.localizedDescription)", stdout: "")
        }

        let stdoutBox = DataBox()
        let drainGroup = DispatchGroup()
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBox.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }
        let stderrBox = DataBox()
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }

        let timeoutQueue = DispatchQueue(label: "MacDashboard.PrivilegedRunner.timeout")
        let timer = DispatchSource.makeTimerSource(queue: timeoutQueue)
        timer.schedule(deadline: .now() + invocation.timeout)
        timer.setEventHandler { [pid = process.processIdentifier] in
            guard killGate.fire(.timeout) else { return }
            kill(pid, SIGKILL)
        }
        timer.resume()

        exitSemaphore.wait()
        timer.cancel()
        _ = drainGroup.wait(timeout: .now() + 3)

        if killGate.winner == .timeout {
            return ProcessResult(exitCode: -1, stderr: "timed out", stdout: "")
        }
        let stdoutText = String(data: stdoutBox.value, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrBox.value, encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, stderr: stderrText, stdout: stdoutText)
    }

    /// stderr is written on a background reader and read on the calling thread after a
    /// BOUNDED wait — on the timeout branch the reader is still running, so the buffer
    /// needs a lock. Mirrors CommandRunner's own box.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        var value: Data { lock.lock(); defer { lock.unlock() }; return data }
    }

    /// Single-fire gate shared between the timeout timer and the termination-handler
    /// path: whichever side calls `fire()` first records itself as `winner`; every
    /// later call (from either side) is a no-op. This class runs Foundation `Process`
    /// (needed for the sudo/password flow), unlike `CommandRunner`'s posix_spawn-based
    /// process-group kill, so it keeps its own single-fire gate rather than sharing one.
    private final class KillGate: @unchecked Sendable {
        enum Winner { case timeout, exited }

        private let lock = NSLock()
        private var _winner: Winner?

        var winner: Winner? {
            lock.lock()
            defer { lock.unlock() }
            return _winner
        }

        @discardableResult
        func fire(_ who: Winner) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _winner != nil { return false }
            _winner = who
            return true
        }
    }
}
