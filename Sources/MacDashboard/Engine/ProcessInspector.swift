// Engine/ProcessInspector.swift
// On-demand per-process detail (libproc + sysctl) and signal sending. Path and owner work for all
// processes; an unprivileged signal succeeds only for same-user processes, EPERM is retried as root
// through an always-prompting administrator dialog (REDESIGN-CPU D13).
import Foundation
import Darwin

struct ProcDetail: Equatable {
    var path: String?      // full executable path, nil if unavailable
    var owner: String?     // user name of the process owner (numeric uid when no passwd entry), nil if unavailable
}

enum ProcessInspector {

    // `PROC_PIDPATHINFO_MAXSIZE` (4*MAXPATHLEN) isn't importable as a Swift
    // constant on this SDK ("structure not supported" — a function-like macro
    // the Clang importer refuses), so its value is inlined here (MAXPATHLEN
    // is the POSIX-standard 1024).
    private static let maxPathSize = 4 * 1024

    /// Fetches path + owner for `pid`. Never throws; every field degrades to nil independently
    /// rather than failing the whole call. Synchronous: call off the main actor.
    static func detail(pid: Int32) -> ProcDetail {
        ProcDetail(path: path(for: pid), owner: owner(for: pid))
    }

    static func path(for pid: Int32) -> String? {
        var buffer = [Int8](repeating: 0, count: maxPathSize)
        let n = proc_pidpath(pid, &buffer, UInt32(maxPathSize))
        guard n > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Owner via `sysctl(KERN_PROC_PID)` → effective uid → passwd name. Unlike
    /// `proc_pidinfo(PROC_PIDTASKINFO)` this works for other users' processes.
    static func owner(for pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return userName(uid: info.kp_eproc.e_ucred.cr_uid)
    }

    /// passwd name for `uid`, or the numeric uid when there is no entry.
    static func userName(uid: uid_t) -> String {
        var bufSize = 1024
        while true {
            var pw = passwd()
            var result: UnsafeMutablePointer<passwd>? = nil
            var buffer = [Int8](repeating: 0, count: bufSize)
            let rc = getpwuid_r(uid, &pw, &buffer, bufSize, &result)
            if rc == ERANGE, bufSize < 16 * 1024 {
                bufSize *= 2
                continue
            }
            if rc == 0, result != nil { return String(cString: pw.pw_name) }
            return "\(uid)"
        }
    }

    /// Result of one `kill(2)` attempt.
    enum SignalResult: Equatable { case sent, gone, notPermitted, refused, failed }
    /// Result of the whole signal flow (reuse guard, kill, privileged retry).
    enum SignalOutcome: Equatable { case sent, gone, cancelled, failed }

    /// Never signals pid <= 1: kill(0) hits the caller's process group, pid 1 is launchd.
    static func sendSignal(_ sig: Int32, to pid: Int32) -> SignalResult {
        guard pid > 1 else { return .refused }
        if kill(pid, sig) == 0 { return .sent }
        switch errno {
        case ESRCH: return .gone
        case EPERM: return .notPermitted
        default: return .failed
        }
    }

    /// Shell command for the privileged retry; the pid is an Int32 so nothing needs quoting.
    static func privilegedSignalCommand(_ sig: Int32, pid: Int32) -> String? {
        guard pid > 1 else { return nil }
        return "/bin/kill -\(sig) \(pid)"
    }

    /// D13: always shows the administrator dialog (never the silent cached-sudo path of PrivilegedRunner.run).
    static func runPrompting(_ command: String) -> PrivilegedRunner.Outcome {
        let r = PrivilegedRunner.runProcess(PrivilegedRunner.osascriptInvocation(command))
        if r.exitCode == 0 { return .success }
        if PrivilegedRunner.isUserCancellation(exitCode: r.exitCode, stderr: r.stderr) { return .cancelled }
        let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(msg.isEmpty ? "unknown error" : String(msg.prefix(200)))
    }

    /// Full flow, synchronous (call off the main actor): reuse guard → kill → on .notPermitted the privileged retry.
    static func signal(_ sig: Int32, pid: Int32, expectedPath: String?,
                       send: (Int32, Int32) -> SignalResult = { sendSignal($0, to: $1) },
                       pathOf: (Int32) -> String? = { path(for: $0) },
                       privileged: (String) -> PrivilegedRunner.Outcome = { runPrompting($0) }) -> SignalOutcome {
        // Pid-reuse guard (D15): the pid must still run the executable the panel was opened for.
        if let expected = expectedPath, pathOf(pid) != expected { return .gone }
        switch send(sig, pid) {
        case .sent: return .sent
        case .gone: return .gone
        case .refused, .failed: return .failed
        case .notPermitted:
            guard let cmd = privilegedSignalCommand(sig, pid: pid) else { return .failed }
            switch privileged(cmd) {
            case .success: return .sent
            case .cancelled: return .cancelled
            case .failed: return .failed
            }
        }
    }
}
