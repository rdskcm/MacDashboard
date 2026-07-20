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
        let sudoResult = runProcess("/usr/bin/sudo", ["sh", "-c", command], timeout: 120)
        if sudoResult.exitCode == 0 { return .success }

        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let osaResult = runProcess("/usr/bin/osascript", ["-e", script], timeout: 120)
        if osaResult.exitCode == 0 { return .success }

        let stderrText = osaResult.stderr
        if stderrText.contains("-128") || stderrText.contains("User cancel") {
            return .cancelled
        }
        let trimmed = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = trimmed.isEmpty ? "unknown error" : String(trimmed.prefix(200))
        return .failed(capped)
    }

    private struct ProcessResult { let exitCode: Int32; let stderr: String }

    /// Runs `path` with `args`, waiting up to `timeout` seconds, and returns the
    /// exit code plus captured stderr (unlike `CommandRunner`, which discards exit
    /// codes — we need them here to distinguish success/cancel/failure).
    private static func runProcess(_ path: String, _ args: [String], timeout: TimeInterval) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice

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
            return ProcessResult(exitCode: -1, stderr: "launch failed: \(error.localizedDescription)")
        }

        let drainGroup = DispatchGroup()
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }
        var stderrData = Data()
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
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
            return ProcessResult(exitCode: -1, stderr: "timed out")
        }
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, stderr: stderrText)
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
