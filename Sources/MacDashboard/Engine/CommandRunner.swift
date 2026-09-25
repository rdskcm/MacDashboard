// Engine/CommandRunner.swift
// Collectors agent owns this file (SPEC §3, §5).
//
// posix_spawn-based runner: every child is spawned as the leader of its own
// process group, so a timeout, a cancellation, or the leader's own exit can
// kill the whole group (`killpg`) instead of racing a single pid. `run` is
// async and reports a `CommandOutcome` (termination reason, stdout, whether it
// was truncated, and a capped head of stderr) rather than collapsing five
// distinct outcomes into `String?`.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum CommandRunner {
    /// QoS for commands spawned by the current task (COLLECT-FASTPATH). Automatic work
    /// wraps itself in `CommandRunner.$qos.withValue(.utility) { … }`; user actions keep
    /// the default. Read once per `run`, in the calling task.
    @TaskLocal static var qos: CommandQoS = .userInitiated

    /// Environment pinned into every child process by default (see F4 discussion
    /// on `run`). A dev run from an interactive shell and the shipped
    /// `.app` under launchd otherwise see different `PATH`/locale, and locale is
    /// unpinned entirely for non-English systems without this.
    ///
    /// NOTE: `system_profiler` takes its language from `AppleLanguages` in
    /// CFPreferences, **not** from `LC_ALL`, so pinning this does not de-localize
    /// its output. Hardware info therefore uses `-json`, whose keys are not localised.
    /// `SPPowerDataType` (battery) is still read as text and stays localised: known gap.
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

    /// Cap on how many stdout bytes a single command's `CommandOutcome.stdout`
    /// keeps (see F2 discussion there). 8 MiB.
    static let outputCap = 8 * 1024 * 1024

    /// Cap on a single un-newline-terminated line buffer while streaming. A stream
    /// that never emits '\n' would otherwise grow the buffer without limit; past this
    /// many bytes the pending bytes are delivered to `onLine` as one line and the
    /// buffer is cleared. 1 MiB.
    static let lineBufferCap = 1024 * 1024

    /// Cap on how many stderr bytes `CommandOutcome.stderrHead` keeps. 2 KiB.
    static let stderrHeadCap = 2 * 1024

    /// Runs the executable at the ABSOLUTE `path` (no PATH lookup, no /usr/bin/env) with
    /// `args`, stdin /dev/null, the pinned `environment`, as leader of its own process group.
    /// `onLine` (optional) receives every stdout and stderr line, on a private serial queue,
    /// all of them before this function returns. Cancelling the awaiting Task kills the
    /// group (or skips the spawn). Never blocks the caller or the Swift concurrency pool: each running child has one
    /// dedicated waiter thread that blocks until it exits.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval,
                    environment: [String: String] = defaultEnvironment,
                    onLine: ((_ line: String, _ isStderr: Bool) -> Void)? = nil) async -> CommandOutcome {
        guard path.hasPrefix("/") else { return .launchFailed(EINVAL) }   // R0(c)
        let job = CommandJob(onLine: onLine, qos: CommandRunner.qos)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<CommandOutcome, Never>) in
                job.start(path: path, args: args, environment: environment, timeout: timeout) {
                    cont.resume(returning: $0)
                }
            }
        } onCancel: {
            job.cancel()
        }
    }

    /// posix_spawn: own process group (pgid = child pid), stdin /dev/null, stdout/stderr to
    /// the given pipe write ends, every other fd closed in the child (CLOEXEC_DEFAULT),
    /// signal mask empty, dispositions default. Returns 0 or an errno (posix_spawn's return).
    fileprivate static func spawn(_ path: String, _ args: [String], _ environment: [String: String],
                                  stdoutFD: Int32, stderrFD: Int32, qosClass: qos_class_t?,
                                  pid: inout pid_t) -> Int32 {
        var fa: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fa); defer { posix_spawn_file_actions_destroy(&fa) }
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&fa, stdoutFD, 1)
        posix_spawn_file_actions_adddup2(&fa, stderrFD, 2)
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr); defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setpgroup(&attr, 0)
        var noSignals = sigset_t(); sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attr, &noSignals)
        var defaults = sigset_t(); sigfillset(&defaults); sigdelset(&defaults, SIGKILL); sigdelset(&defaults, SIGSTOP)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK
                                              | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT))
        if let qosClass { let r = posix_spawnattr_set_qos_class_np(&attr, qosClass); if r != 0 { return r } }
        let argv: [UnsafeMutablePointer<CChar>?] = ([path] + args).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        return posix_spawn(&pid, path, &fa, &attr, argv, envp)
    }
}

/// How much CPU priority a spawned command gets. `.utility` spawns the child with
/// QOS_CLASS_UTILITY (posix_spawnattr_set_qos_class_np); `.userInitiated` sets no spawn
/// QoS — that API accepts only utility/background, so "no attribute" is today's behaviour.
enum CommandQoS: Sendable, Equatable {
    case userInitiated, utility
    var dispatchQoS: DispatchQoS { self == .utility ? .utility : .userInitiated }
    var threadQoS: QualityOfService { self == .utility ? .utility : .userInitiated }
    var spawnQoSClass: qos_class_t? { self == .utility ? QOS_CLASS_UTILITY : nil }
}

/// Result of one `CommandRunner.run`. Pure value; see `text` for the legacy String? view.
struct CommandOutcome: Equatable, Sendable {
    enum Termination: Equatable, Sendable {
        case exited(Int32)        // leader exited normally with this status
        case signaled(Int32)      // leader died by a signal WE did not send (0 = status unknown, see below)
        case launchFailed(Int32)  // nothing ran; errno (posix_spawn/pipe), EINVAL for a non-absolute path
        case timedOut             // we killed the group at the deadline, or output was still unread at it
        case cancelled            // the awaiting Task was cancelled; group killed or never spawned
    }
    enum KillReason: Equatable, Sendable { case timedOut, cancelled }

    var termination: Termination
    var stdout: String            // lossy UTF-8 of at most CommandRunner.outputCap bytes
    var stdoutTruncated: Bool
    var stderrHead: String        // lossy UTF-8 of at most CommandRunner.stderrHeadCap bytes

    static func launchFailed(_ err: Int32) -> CommandOutcome {
        CommandOutcome(termination: .launchFailed(err), stdout: "", stdoutTruncated: false, stderrHead: "")
    }

    /// Exactly the old `run` -> String? contract (V21-HONEST-EXITS): nil for launch failure,
    /// timeout, cancellation, and for empty stdout unless the leader exited cleanly with 0.
    var text: String? {
        switch termination {
        case .launchFailed, .timedOut, .cancelled: return nil
        case .exited(let code): return (stdout.isEmpty && code != 0) ? nil : stdout
        case .signaled: return stdout.isEmpty ? nil : stdout
        }
    }

    /// Exactly the old "non-empty" contract: `text`, but whitespace-only counts as nothing learned.
    var nonEmptyText: String? {
        guard let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return t
    }

    /// Pure (Checks-tested). The wait(2) status decides the outcome, unless OUR kill is what ended
    /// the run: a kill reason counts only when the leader died of SIGKILL, its status is unknown,
    /// or reading was stopped with output still unread (`outputCut`). A leader that exited on its
    /// own before our kill landed is reported by its real status (RUNNER-HANG C-M2c).
    /// `outputCut` defaults to false: nothing was cut unless the job says so.
    /// WIFEXITED & co. are C macros Swift cannot import, hence the bit math.
    /// `waitStatus == nil`: the status was unavailable (child reaped elsewhere — not
    /// expected in this app); reported as `.signaled(0)` so only non-empty stdout counts.
    static func termination(killReason: KillReason?, waitStatus: Int32?, outputCut: Bool = false) -> Termination {
        if let reason = killReason {
            let killedBySIGKILL = waitStatus.map { ($0 & 0x7f) == SIGKILL } ?? true
            if killedBySIGKILL || outputCut { return reason == .timedOut ? .timedOut : .cancelled }
        }
        guard let s = waitStatus else { return .signaled(0) }
        let low = s & 0x7f
        return low == 0 ? .exited((s >> 8) & 0xff) : .signaled(low)
    }
}

/// Keeps at most `cap` bytes; later bytes are dropped and `truncated` is set. Pure.
struct CappedBuffer {
    let cap: Int
    private(set) var data = Data()
    private(set) var truncated = false
    init(cap: Int) { self.cap = cap }
    mutating func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        let room = cap - data.count
        if chunk.count <= room { data.append(chunk) }
        else { data.append(chunk.prefix(max(room, 0))); truncated = true }
    }
}

/// Splits a byte stream into lines for `onLine`. Pure. Same rules as the old streaming path:
/// split on "\n", strip one trailing "\r", an empty line is delivered as "", a pending
/// partial line longer than `cap` is delivered whole and cleared, `finish()` returns the
/// trailing partial line at EOF. Consumed bytes are removed ONCE per feed (not per line).
struct LineSplitter {
    let cap: Int
    private var pending = Data()
    init(cap: Int = CommandRunner.lineBufferCap) { self.cap = cap }
    mutating func feed(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        var start = pending.startIndex
        while let nl = pending[start...].firstIndex(of: 0x0A) {
            var end = nl
            if end > start, pending[pending.index(before: end)] == 0x0D { end = pending.index(before: end) }
            lines.append(String(decoding: pending[start..<end], as: UTF8.self))
            start = pending.index(after: nl)
        }
        pending.removeSubrange(pending.startIndex..<start)
        if pending.count > cap {
            lines.append(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
        return lines
    }
    mutating func finish() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}

/// One run's state machine. EVERY stored property is read and written only on `queue`
/// (both DispatchIO channels, the deadline timer, the cancel hop and the waiter's reap hop all target it;
/// the waiter thread itself reads no stored property except the immutable `queue`; `qos` is immutable, like `queue`), which is what makes
/// `@unchecked Sendable` sound without a lock.
/// Invariant: a signal is sent only in phase `.running`, i.e. before the leader is reaped,
/// so the pgid (= leader pid) cannot have been reused.
private final class CommandJob: @unchecked Sendable {
    private enum Phase { case idle, running(pid_t), reaped(Int32?), done }
    private let queue: DispatchQueue
    private let qos: CommandQoS
    private let onLine: ((String, Bool) -> Void)?
    private var phase = Phase.idle
    private var killReason: CommandOutcome.KillReason?
    private var completion: ((CommandOutcome) -> Void)?
    private var stdoutBuf = CappedBuffer(cap: CommandRunner.outputCap)
    private var stderrBuf = CappedBuffer(cap: CommandRunner.stderrHeadCap)
    private var stdoutLines = LineSplitter()
    private var stderrLines = LineSplitter()
    private var channels: [DispatchIO] = []
    private var openStreams = 0
    private var outputCut = false          // stopReading() ran while a stream was still open
    private var timer: DispatchSourceTimer?

    init(onLine: ((String, Bool) -> Void)?, qos: CommandQoS) {
        self.onLine = onLine
        self.qos = qos
        self.queue = DispatchQueue(label: "MacDashboard.CommandRunner.job", qos: qos.dispatchQoS)
    }

    func start(path: String, args: [String], environment: [String: String], timeout: TimeInterval,
               completion: @escaping (CommandOutcome) -> Void) {
        queue.async { self.launch(path, args, environment, timeout, completion) }
    }
    func cancel() { queue.async { self.requestKill(.cancelled) } }

    private func launch(_ path: String, _ args: [String], _ env: [String: String],
                        _ timeout: TimeInterval, _ completion: @escaping (CommandOutcome) -> Void) {
        self.completion = completion
        if killReason == .cancelled {                         // cancelled before spawn: spawn nothing
            finish(CommandOutcome(termination: .cancelled, stdout: "", stdoutTruncated: false, stderrHead: ""))
            return
        }
        var out: [Int32] = [-1, -1], err: [Int32] = [-1, -1]
        guard pipe(&out) == 0 else { finish(.launchFailed(errno)); return }
        guard pipe(&err) == 0 else {
            let e = errno; Darwin.close(out[0]); Darwin.close(out[1]); finish(.launchFailed(e)); return
        }
        for fd in out + err { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }   // never leak into other spawns
        var pid: pid_t = 0
        let rc = CommandRunner.spawn(path, args, env, stdoutFD: out[1], stderrFD: err[1],
                                   qosClass: qos.spawnQoSClass, pid: &pid)
        Darwin.close(out[1]); Darwin.close(err[1])                 // parent keeps only the read ends
        guard rc == 0 else { Darwin.close(out[0]); Darwin.close(err[0]); finish(.launchFailed(rc)); return }
        phase = .running(pid)
        channels = [makeReader(fd: out[0], isStderr: false), makeReader(fd: err[0], isStderr: true)]
        openStreams = 2
        startWaiter(pid)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + timeout)
        t.setEventHandler { self.requestKill(.timedOut) }   // the waiter reaps; the timer only kills
        t.resume(); timer = t
    }

    private func makeReader(fd: Int32, isStderr: Bool) -> DispatchIO {
        let io = DispatchIO(type: .stream, fileDescriptor: fd, queue: queue,
                            cleanupHandler: { _ in Darwin.close(fd) })
        io.setLimit(lowWater: 1)                          // deliver as soon as bytes arrive (streaming)
        io.read(offset: 0, length: Int.max, queue: queue) { done, data, _ in
            if let data, !data.isEmpty {
                var chunk = Data()
                data.enumerateBytes { buf, _, _ in chunk.append(buf) }
                self.consume(chunk, isStderr: isStderr)
            }
            if done { io.close(); self.streamEnded(isStderr: isStderr) }
        }
        return io
    }

    private func consume(_ chunk: Data, isStderr: Bool) {
        if isStderr { stderrBuf.append(chunk) } else { stdoutBuf.append(chunk) }
        guard let onLine else { return }
        let lines = isStderr ? stderrLines.feed(chunk) : stdoutLines.feed(chunk)
        for l in lines { onLine(l, isStderr) }
    }

    private func streamEnded(isStderr: Bool) {
        if let onLine, let rest = (isStderr ? stderrLines.finish() : stdoutLines.finish()) { onLine(rest, isStderr) }
        openStreams -= 1
        finishIfComplete()
    }

    private func requestKill(_ reason: CommandOutcome.KillReason) {
        switch phase {
        case .idle:
            if killReason == nil { killReason = reason }            // launch() will not spawn
        case .running(let pid):
            if killReason == nil { killReason = reason }
            _ = killpg(pid, SIGKILL)                                // leader unreaped: pgid is ours
        case .reaped:
            // Leader gone, but a pipe is still open (a holder outside the group). Stop reading;
            // the output is incomplete, so the outcome is timedOut/cancelled, not the exit status.
            if killReason == nil { killReason = reason }
            stopReading()
        case .done:
            break
        }
    }

    /// The only reaper. A dedicated thread (never `queue`, never the Swift pool) blocks in
    /// waitid(WEXITED|WNOWAIT) until the leader is a zombie, so its exit cannot be missed — unlike
    /// a one-shot non-blocking probe fired by an exit event or right after a kill (RUNNER-HANG C-M2a/b/c).
    /// WNOWAIT leaves the zombie in place: the pid (= pgid) stays reserved until `reap` collects
    /// it on `queue`, so `requestKill` may still signal the group until then.
    private func startWaiter(_ pid: pid_t) {
        let threadQoS = qos.threadQoS
        let t = Thread {
            var info = siginfo_t()
            var r: Int32
            repeat { r = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) } while r == -1 && errno == EINTR
            let exited = (r == 0)                   // r == -1 (ECHILD): reaped elsewhere, status unknown
            self.queue.async { self.reap(pid, exited: exited) }
        }
        t.name = "MacDashboard.CommandRunner.wait"
        t.qualityOfService = threadQoS
        t.start()
    }

    /// On `queue`, once the waiter saw the leader exit. `exited`: it is a zombie right now.
    private func reap(_ pid: pid_t, exited: Bool) {
        guard case .running(let p) = phase, p == pid else { return }
        var status: Int32? = nil
        if exited {
            // Still a zombie: its pid (= pgid) is reserved, so sweeping the group is safe.
            _ = killpg(pid, SIGKILL)
            var s: Int32 = 0
            var got: pid_t
            repeat { got = waitpid(pid, &s, 0) } while got == -1 && errno == EINTR   // zombie: returns at once
            if got == pid { status = s }
        }
        phase = .reaped(status)
        if killReason != nil { stopReading() }      // we killed it: do not wait on pipe holders outside the group
        finishIfComplete()
    }

    private func stopReading() {
        if openStreams > 0 { outputCut = true }     // output still unread: what we have is incomplete
        for io in channels { io.close(flags: .stop) }
    }

    private func finishIfComplete() {
        guard case .reaped(let status) = phase, openStreams == 0 else { return }
        finish(CommandOutcome(
            termination: CommandOutcome.termination(killReason: killReason, waitStatus: status, outputCut: outputCut),
            stdout: String(decoding: stdoutBuf.data, as: UTF8.self),
            stdoutTruncated: stdoutBuf.truncated,
            stderrHead: String(decoding: stderrBuf.data, as: UTF8.self)))
    }

    private func finish(_ outcome: CommandOutcome) {
        if case .done = phase { return }
        phase = .done
        timer?.cancel(); timer = nil
        channels = []
        let c = completion; completion = nil
        c?(outcome)
    }
}
