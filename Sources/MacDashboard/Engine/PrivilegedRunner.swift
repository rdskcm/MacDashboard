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

    /// Runs `command` as root. Tries plain `sudo` first (Touch ID via pam_tid),
    /// then falls back to an osascript admin-privileges password dialog if `sudo`
    /// failed (Touch ID cancelled/unavailable). Never resets the sudo timestamp
    /// itself (`sudo -k`) — a cached grant making this prompt-less is a feature.
    /// `command` is a raw shell string, not argv — callers MUST quote every
    /// embedded value themselves (see DashboardModel's `'...'` + `'\''` pattern).
    static func run(_ command: String) -> Outcome {
        // Absolute /bin/sh, never the bare name `sh`: sudo resolves a bare command
        // name through the CALLER's PATH (macOS sudoers sets no secure_path), and a
        // shell-launched build inherits group-writable prefixes like /opt/homebrew/bin.
        let sudoResult = runProcess("/usr/bin/sudo", ["/bin/sh", "-c", command], timeout: 120)
        if sudoResult.exitCode == 0 { return .success }

        // The privileged command RAN and failed (or sudo timed out / could not launch).
        // Re-running the same failing command as root behind a password dialog just fails
        // again after an unnecessary prompt (V2-SECURITY-AUDIT N1).
        guard Self.isSudoOwnFailure(exitCode: sudoResult.exitCode, stderr: sudoResult.stderr) else {
            return Self.failure(from: sudoResult)
        }

        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let osaResult = runProcess("/usr/bin/osascript", ["-e", script], timeout: 120)
        if osaResult.exitCode == 0 { return .success }

        if Self.isUserCancellation(exitCode: osaResult.exitCode, stderr: osaResult.stderr) {
            return .cancelled
        }
        return Self.failure(from: osaResult)
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

    private struct ProcessResult { let exitCode: Int32; let stderr: String; let stdout: String }

    /// Runs `path` with `args`, waiting up to `timeout` seconds, and returns the
    /// exit code plus captured stdout/stderr (unlike `CommandRunner`, which discards
    /// exit codes — we need them here to distinguish success/cancel/failure).
    private static func runProcess(_ path: String, _ args: [String], timeout: TimeInterval) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
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
        timer.schedule(deadline: .now() + timeout)
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
    /// path, mirroring `CommandRunner`'s `KillGate` (private there, so duplicated here).
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
