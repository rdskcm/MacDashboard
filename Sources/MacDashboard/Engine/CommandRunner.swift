// Engine/CommandRunner.swift
// Collectors agent owns this file (SPEC §3, §5).
//
// Thin, defensive wrapper around Foundation.Process for running read-only system
// binaries with a hard timeout. Mirrors the legacy `run_cmd()` helper from
// mac_live_server.py (capture stdout+stderr, swallow any launch error, return nil
// on empty stdout) but adds a real timeout with SIGKILL, which the Python version
// only had via `subprocess.run(..., timeout=...)`.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum CommandRunner {
    /// Environment pinned into every child process by default (see F4 discussion
    /// on `runCapturing`). A dev run from an interactive shell and the shipped
    /// `.app` under launchd otherwise see different `PATH`/locale, and locale is
    /// unpinned entirely for non-English systems without this.
    ///
    /// NOTE: `system_profiler` takes its language from `AppleLanguages` in
    /// CFPreferences, **not** from `LC_ALL`, so pinning this does not de-localize
    /// its output. The real fix there is `-json` output and belongs to a later
    /// block.
    static let defaultEnvironment: [String: String] = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LC_ALL": "C", "LANG": "C", "TZ": "UTC",
        "HOME": NSHomeDirectory(),
    ]

    /// `defaultEnvironment` with `dirs` prepended to PATH — for tools (Homebrew)
    /// that resolve helper binaries inside their own prefix.
    static func environment(prependingPATH dirs: [String]) -> [String: String] {
        var env = defaultEnvironment
        let prefix = dirs.joined(separator: ":")
        env["PATH"] = prefix + ":" + (defaultEnvironment["PATH"] ?? "")
        return env
    }

    /// Cap on how many stdout bytes `runCapturing` keeps for a single command (see
    /// F2 discussion there). 8 MiB.
    static let outputCap = 8 * 1024 * 1024

    /// Runs the binary at `path` (resolved via `/usr/bin/env` when `path` has no "/",
    /// i.e. is a bare command name rather than an absolute path) with `args`, waiting
    /// up to `timeout` seconds. Thin wrapper over `runCapturing` — see there for the
    /// full concurrency/safety notes and the truncation-cap behavior; this entry
    /// point just discards the `truncated` flag (its return type is deferred to
    /// stay `String?`).
    ///
    /// - Returns: captured stdout as a UTF-8 string, even if the process exited
    ///   non-zero (legacy `run_cmd` semantics: only emptiness of stdout matters, not
    ///   the exit code — many of these tools write useful data with a non-zero exit,
    ///   e.g. `softwareupdate -l`). Returns `nil` when the process could not be
    ///   launched, timed out (and was killed), or produced empty stdout.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval,
                    environment: [String: String] = defaultEnvironment,
                    scope: CommandCancellationScope? = nil) -> String? {
        runCapturing(path, args, timeout: timeout, environment: environment, scope: scope)?.text
    }

    /// Result of `runCapturing`: the captured stdout text plus whether it was
    /// capped at `outputCap` before decoding.
    struct CaptureResult {
        let text: String
        let truncated: Bool
    }

    /// Same contract as `run`, but also reports whether stdout was capped at
    /// `outputCap`. `run` is the thin wrapper over this; the extra shape exists so
    /// Checks can observe truncation without changing `run`'s deferred return type.
    ///
    /// Concurrency/safety notes:
    /// - stdin is `/dev/null` so nothing ever blocks on a read prompt (critical for
    ///   `sudo -n`, which must fail fast rather than hang on a password prompt).
    /// - stdout and stderr are drained concurrently on background queues, and only
    ///   *after* the process has successfully launched. Starting the drain before
    ///   launch would leak the reader threads forever (the pipe's write end would
    ///   never see a writer, so the read loop never sees EOF). Starting it after
    ///   waiting for exit instead of concurrently with it would deadlock the moment
    ///   a command writes more than one pipe-buffer's worth (~64 KiB) to stdout
    ///   *and* stderr, since the child would block on write() while we block on
    ///   wait().
    /// - Both drains accumulate into a `DrainBox` guarded by an `NSLock` rather than
    ///   a plain `var`, and the final read happens through that same lock after the
    ///   bounded drain wait below. A successful `DispatchGroup.wait` establishes
    ///   ordering with the drain closures, but the *timeout* path does not: the
    ///   drain closure can still be blocked inside `availableData` while the
    ///   calling thread reads the accumulated bytes, which is a data race on a
    ///   plain `var` (the bug this class fixes; `runStreaming`'s equivalent race is
    ///   avoided via `lineQueue.sync`). This also means a drain-wait timeout
    ///   returns whatever partial output was captured instead of losing it.
    /// - Exit detection uses `terminationHandler` (Foundation's own async
    ///   exit-monitoring callback) rather than `waitUntilExit()`, and a `KillGate`
    ///   ensures the timeout path and the natural-exit path race for a single
    ///   "who gets to act" token: whichever observes the process state first wins,
    ///   and the loser is a guaranteed no-op. This keeps the timer's `kill(2)` call
    ///   from ever firing after we've already learned (via the same Foundation
    ///   callback used for normal completion) that the child is gone — the pid
    ///   reuse window is as tight as Foundation's own bookkeeping, which is the best
    ///   available without dropping to a raw kqueue EVFILT_PROC watch.
    static func runCapturing(_ path: String, _ args: [String], timeout: TimeInterval,
                             environment: [String: String] = defaultEnvironment,
                             scope: CommandCancellationScope? = nil) -> CaptureResult? {
        if let scope, scope.isCancelled { return nil }
        let process = Process()
        if path.contains("/") {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
        } else {
            // Bare command name. Callers in this codebase pass absolute paths
            // resolved ahead of time; this branch exists for completeness/tests.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [path] + args
        }
        process.standardInput = FileHandle.nullDevice
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let killGate = KillGate()
        let exitSemaphore = DispatchSemaphore(value: 0)
        // Set BEFORE run() so an extremely fast-exiting child can't finish before
        // we've attached the callback.
        process.terminationHandler = { _ in
            killGate.fire(.exited)
            exitSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let scopeID = ObjectIdentifier(process)
        if let scope {
            let pid = process.processIdentifier
            let registered = scope.register(id: scopeID) {
                // Same guarded-kill idiom as the timeout timer: whoever fires the
                // gate first acts; reusing .timeout makes the "return nil" path
                // below cover cancellation with no KillGate changes.
                guard killGate.fire(.timeout) else { return }
                kill(pid, SIGKILL)
            }
            if !registered {
                // Scope cancelled between the early check and launch: kill now;
                // terminationHandler still fires, the wait below returns, and
                // killGate.winner == .timeout yields nil.
                if killGate.fire(.timeout) { kill(pid, SIGKILL) }
            }
        }

        // Drain BOTH pipes concurrently, starting immediately after a successful
        // launch (see doc comment above for why ordering matters here).
        let drainGroup = DispatchGroup()
        let stdoutBox = DrainBox()
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = stdoutPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                // Keep reading to EOF even once the cap is hit: if we stopped
                // draining the fd here, the child would block on write() to a
                // full pipe and never exit, so the timeout timer would SIGKILL
                // it — turning merely-large output into `nil`
                // (killGate.winner == .timeout), a worse bug than the unbounded
                // buffering this cap exists to fix. So the loop always drains to
                // EOF; only the *kept* bytes are capped.
                stdoutBox.append(chunk, cap: outputCap)
            }
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            // Content unused (legacy run_cmd only ever returns stdout) but MUST be
            // drained or the child can deadlock writing to a full stderr pipe.
            // Same "always read to EOF" reasoning as stdout above; nothing is kept.
            let handle = stderrPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
            }
            drainGroup.leave()
        }

        let timeoutQueue = DispatchQueue(label: "MacDashboard.CommandRunner.timeout")
        let timer = DispatchSource.makeTimerSource(queue: timeoutQueue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [pid = process.processIdentifier] in
            guard killGate.fire(.timeout) else { return }
            kill(pid, SIGKILL)
        }
        timer.resume()

        exitSemaphore.wait()
        timer.cancel()
        scope?.unregister(id: scopeID)
        // Bounded, not unconditional: if the target process forked a grandchild that
        // inherited the pipe fds (e.g. a shell wrapper running `sleep`), killing only
        // the direct child leaves that grandchild holding the write end open — so an
        // unconditional `drainGroup.wait()` could block us long past `timeout` even
        // though we already know the outcome. None of this codebase's call sites
        // shell-wrap, but this keeps the caller-facing latency bounded regardless of
        // what a target binary does under the hood (verified empirically: a killed
        // `sh -c "sleep 5"` otherwise stalled the return by the full remaining sleep).
        _ = drainGroup.wait(timeout: .now() + 3)

        if killGate.winner == .timeout {
            return nil
        }
        let (stdoutData, truncated) = stdoutBox.snapshot()
        if stdoutData.isEmpty {
            return nil
        }
        return CaptureResult(text: String(decoding: stdoutData, as: UTF8.self), truncated: truncated)
    }

    /// Like `run`, but additionally delivers each complete output line (stdout AND
    /// stderr) to `onLine` as it arrives. `onLine` is invoked on a private serial
    /// queue — callers must hop threads themselves. Returns accumulated stdout on
    /// normal exit (nil on launch failure, timeout, or empty stdout — same
    /// semantics as `run`).
    ///
    /// `environment` has the same meaning and default as in `run`/`runCapturing`:
    /// pinned rather than inherited, so a dev run and the shipped `.app` under
    /// launchd see the same PATH/locale. Callers running a tool that resolves
    /// helper binaries inside its own prefix (Homebrew) pass
    /// `environment(prependingPATH:)` here exactly as they already do for the
    /// short-lived calls (V2-POLISH B1).
    static func runStreaming(_ path: String, _ args: [String], timeout: TimeInterval,
                              environment: [String: String] = defaultEnvironment,
                              onLine: @escaping (_ line: String, _ isStderr: Bool) -> Void) -> String? {
        let process = Process()
        if path.contains("/") {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
        } else {
            // Bare command name. Callers in this codebase pass absolute paths
            // resolved ahead of time; this branch exists for completeness/tests.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [path] + args
        }
        process.standardInput = FileHandle.nullDevice
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let killGate = KillGate()
        let exitSemaphore = DispatchSemaphore(value: 0)
        // Set BEFORE run() so an extremely fast-exiting child can't finish before
        // we've attached the callback.
        process.terminationHandler = { _ in
            killGate.fire(.exited)
            exitSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        // Serializes both readabilityHandlers' buffer mutation and onLine delivery so
        // lines from stdout/stderr are never interleaved mid-line and there's no data
        // race on the byte buffers below.
        let lineQueue = DispatchQueue(label: "MacDashboard.CommandRunner.runStreaming.lines")
        var stdoutBuffer = Data()
        var stderrBuffer = Data()
        var stdoutData = Data()

        // Splits `buffer` on '\n', emitting each complete line (minus a trailing '\r'
        // if present) to `onLine`, and leaves the trailing partial chunk in `buffer`.
        func emitCompleteLines(from buffer: inout Data, isStderr: Bool) {
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                var lineData = buffer[buffer.startIndex..<newlineIndex]
                if lineData.last == 0x0D {
                    lineData = lineData[lineData.startIndex..<lineData.index(before: lineData.endIndex)]
                }
                let line = String(decoding: lineData, as: UTF8.self)
                onLine(line, isStderr)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
            }
        }

        // Flushes any remaining partial line (no trailing newline) to `onLine`.
        func flushRemainder(from buffer: inout Data, isStderr: Bool) {
            guard !buffer.isEmpty else { return }
            let line = String(decoding: buffer, as: UTF8.self)
            onLine(line, isStderr)
            buffer.removeAll()
        }

        // Drain BOTH pipes concurrently via readabilityHandler, starting immediately
        // after a successful launch (see `run`'s doc comment for why ordering matters).
        let drainGroup = DispatchGroup()
        drainGroup.enter()
        drainGroup.enter()

        // NOTE: `readabilityHandler` is level-triggered at EOF — if we deferred nil-ing
        // it out to `lineQueue.async`, the underlying dispatch source can fire the
        // closure again with more empty data before that async block runs, causing a
        // double `drainGroup.leave()` (observed empirically: `dispatch_group_leave`
        // over-release crash). So the handler is nil-ed out synchronously, on the
        // calling (internal Foundation) thread, as the very first thing on the EOF
        // path — before handing the actual flush+leave work to `lineQueue`.
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
            }
            lineQueue.async {
                if data.isEmpty {
                    flushRemainder(from: &stdoutBuffer, isStderr: false)
                    drainGroup.leave()
                } else {
                    stdoutData.append(data)
                    stdoutBuffer.append(data)
                    emitCompleteLines(from: &stdoutBuffer, isStderr: false)
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            }
            lineQueue.async {
                if data.isEmpty {
                    flushRemainder(from: &stderrBuffer, isStderr: true)
                    drainGroup.leave()
                } else {
                    stderrBuffer.append(data)
                    emitCompleteLines(from: &stderrBuffer, isStderr: true)
                }
            }
        }

        let timeoutQueue = DispatchQueue(label: "MacDashboard.CommandRunner.runStreaming.timeout")
        let timer = DispatchSource.makeTimerSource(queue: timeoutQueue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [pid = process.processIdentifier] in
            guard killGate.fire(.timeout) else { return }
            kill(pid, SIGKILL)
        }
        timer.resume()

        exitSemaphore.wait()
        timer.cancel()
        // Bounded, not unconditional — see `run`'s doc comment for the rationale.
        let drainOutcome = drainGroup.wait(timeout: .now() + 3)
        if drainOutcome == .timedOut {
            // Avoid leaking the handler closures/file handles if a grandchild is still
            // holding the write end open past the bounded wait.
            lineQueue.sync {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        if killGate.winner == .timeout {
            return nil
        }
        let finalStdout = lineQueue.sync { stdoutData }
        if finalStdout.isEmpty {
            return nil
        }
        return String(data: finalStdout, encoding: .utf8)
    }
}

/// Groups the live `Process`es spawned for one logical operation (e.g. one
/// ReportCollector.collect() run) so structured-concurrency cancellation can
/// actually SIGKILL them instead of just abandoning the blocking semaphore wait.
/// Thread-safe; `cancel()` is idempotent. After `cancel()`, any subsequent
/// `CommandRunner.run` given this scope returns nil without launching anything.
/// Each registered kill closure routes through that run's `KillGate`, so a
/// cancellation racing a natural exit (or the timeout timer) is a guaranteed
/// no-op on the losing side — same single-fire discipline as the timeout path.
final class CommandCancellationScope: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var kills: [ObjectIdentifier: () -> Void] = [:]

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Returns false if the scope was already cancelled — the caller must then
    /// invoke the kill closure itself (covers the check-then-launch race).
    fileprivate func register(id: ObjectIdentifier, kill: @escaping () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return false }
        kills[id] = kill
        return true
    }

    fileprivate func unregister(id: ObjectIdentifier) {
        lock.lock(); defer { lock.unlock() }
        kills[id] = nil
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let pending = Array(kills.values)
        kills.removeAll()
        lock.unlock()
        for kill in pending { kill() }   // outside the lock — kill() takes KillGate's lock
    }
}

/// Guards `runCapturing`'s stdout accumulation across the drain queue (which
/// writes) and the calling thread (which reads back after the bounded drain
/// wait) — see the "Concurrency/safety notes" on `runCapturing` for why a plain
/// `var` is unsafe here. Also owns the F2 cap: bytes beyond `cap` are dropped
/// (not kept) while the caller keeps reading the fd to EOF regardless.
private final class DrainBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false

    /// Appends `chunk`, keeping at most `cap` bytes total; anything beyond that
    /// is discarded and `truncated` is set. The caller is still expected to keep
    /// reading the underlying fd to EOF after this returns — see `runCapturing`.
    func append(_ chunk: Data, cap: Int) {
        lock.lock(); defer { lock.unlock() }
        guard data.count < cap else {
            truncated = true
            return
        }
        let remaining = cap - data.count
        if chunk.count > remaining {
            data.append(chunk.prefix(remaining))
            truncated = true
        } else {
            data.append(chunk)
        }
    }

    /// Snapshots the accumulated bytes and the truncation flag under the lock.
    func snapshot() -> (Data, truncated: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (data, truncated)
    }
}

/// Single-fire gate shared between the timeout timer and the termination-handler
/// path. Whichever side calls `fire()` first records itself as `winner`; every
/// later call (from either side) is a no-op and returns `false`.
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
