// Engine/ProcessInspector.swift
// On-demand per-process detail (libproc) + signal sending. Unprivileged:
// path works for all processes; thread count falls back to `ps -M` for
// other users' processes; signals succeed only for same-user processes.
import Foundation
import Darwin

struct ProcDetail: Equatable {
    var path: String?      // full executable path, nil if unavailable
    var threads: Int?      // nil if unavailable
}

enum ProcessInspector {

    // `PROC_PIDPATHINFO_MAXSIZE` (4*MAXPATHLEN) isn't importable as a Swift
    // constant on this SDK ("structure not supported" — a function-like macro
    // the Clang importer refuses), so its value is inlined here (MAXPATHLEN
    // is the POSIX-standard 1024).
    private static let maxPathSize = 4 * 1024

    /// Fetches path + thread count for `pid`. Never throws; every field degrades
    /// to nil independently rather than failing the whole call.
    static func detail(pid: Int32) -> ProcDetail {
        ProcDetail(path: path(for: pid), threads: threadCount(for: pid))
    }

    private static func path(for pid: Int32) -> String? {
        var buffer = [Int8](repeating: 0, count: maxPathSize)
        let n = proc_pidpath(pid, &buffer, UInt32(maxPathSize))
        guard n > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func threadCount(for pid: Int32) -> Int? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let n = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        // Success is an EXACT match on the expected struct size (empirically:
        // same-user processes return `size`; other users' processes return ≤0
        // with errno == EPERM rather than a short read, but the exact-size
        // check is the documented libproc success contract either way).
        if n == size {
            return Int(info.pti_threadnum)
        }
        return threadCountViaPS(for: pid)
    }

    /// Fallback for other-user processes: `/bin/ps -M -p <pid>` prints a header
    /// line plus one line per thread (verified: WindowServer → 21 lines = 20
    /// threads). Returns nil if `ps` itself fails (timeout/launch error/no output).
    private static func threadCountViaPS(for pid: Int32) -> Int? {
        guard let out = CommandRunner.run("/bin/ps", ["-M", "-p", "\(pid)"], timeout: 3) else { return nil }
        let lines = out.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return max(lines.count - 1, 0)
    }

    /// Sends `sig` to `pid`. Succeeds (same-user process) or fails (-1/EPERM,
    /// e.g. another user's or root's process) exactly per `kill(2)` semantics.
    @discardableResult
    static func sendSignal(_ sig: Int32, to pid: Int32) -> Bool {
        kill(pid, sig) == 0
    }

    /// Finder-reveal target: if `path` contains ".app/", trim to the bundle
    /// (".../Foo.app"); else the binary itself unchanged.
    static func revealTarget(for path: String) -> String {
        if path.hasSuffix(".app") { return path }
        guard let range = path.range(of: ".app/") else { return path }
        return String(path[path.startIndex..<range.lowerBound]) + ".app"
    }
}
