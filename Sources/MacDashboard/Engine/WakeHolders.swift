// Engine/WakeHolders.swift
// WAKE-HOLDERS: which non-system program keeps the Mac awake. Parses `pmset -g assertions`
// (the only source that reports an assertion's age and its on-behalf-of PID — neither is a
// public key of IOPMCopyAssertionsByProcess), keeps sleep-preventing assertions held for at
// least `minimumAgeSeconds`, and attributes each one to its real requester. "System" is
// decided by WHERE the executable lives (the sealed, SIP-protected OS locations), never by a
// name list. Pure except `processRecord(pid:)` / `sample()`; symlinked into Checks.
import Foundation
import Darwin

struct PowerAssertion: Equatable {
    var pid: Int32
    var processName: String      // as pmset prints it: "pid 349(powerd)" -> "powerd"
    var ageSeconds: Int          // pmset's hh:mm:ss column
    var type: String             // "PreventUserIdleSystemSleep"
    var name: String             // the quoted `named:` value
    var onBehalfOfPID: Int32? = nil   // "Created for PID: N"
}

/// What the classifier needs to know about a pid. nil fields = unreadable.
struct ProcRecord: Equatable {
    var path: String?
    var ppid: Int32?
    var name: String? = nil      // argv[0]'s last path component, the display name of the process
}

struct WakeHolder: Equatable {
    var owner: String            // process that holds the assertion
    var requester: String?       // program it holds it for; nil when that is the owner itself
    var ageSeconds: Int
}

enum WakeHolders {
    /// Assertion types that keep the system or the display from idle-sleeping (IOPMLib.h
    /// kIOPMAssertionType* plus the two legacy names). `UserIsActive` is the user's own input.
    static let sleepPreventingTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventUserIdleDisplaySleep",
        "NoIdleSleepAssertion", "NoDisplaySleepAssertion",
    ]
    /// Holders younger than this are not shown (flicker from short bursts; see spec).
    static let minimumAgeSeconds = 300
    private static let maxParentHops = 8

    private static let assertionLine = try! NSRegularExpression(
        pattern: #"^\s*pid (\d+)\((.*?)\): \[0x[0-9A-Fa-f]+\] (\d+):(\d{2}):(\d{2}) (\S+) named: "(.*)"\s*$"#)
    private static let createdFor = try! NSRegularExpression(pattern: #"Created for PID: (\d+)"#)

    /// nil when the "Listed by owning process:" header is absent (not assertion output).
    /// Lines that match neither shape are skipped, never a failure.
    static func parseAssertions(_ text: String) -> [PowerAssertion]? {
        var inList = false
        var sawHeader = false
        var out: [PowerAssertion] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Listed by owning process:" { inList = true; sawHeader = true; continue }
            if trimmed.hasPrefix("Kernel Assertions:") { inList = false; continue }
            guard inList else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let m = assertionLine.firstMatch(in: line, range: range) {
                func g(_ i: Int) -> String { String(line[Range(m.range(at: i), in: line)!]) }
                guard let pid = Int32(g(1)), let h = Int(g(3)), let mi = Int(g(4)), let s = Int(g(5)) else { continue }
                out.append(PowerAssertion(pid: pid, processName: g(2), ageSeconds: h * 3600 + mi * 60 + s,
                                          type: g(6), name: g(7)))
            } else if !out.isEmpty, let m = createdFor.firstMatch(in: line, range: range),
                      let r = Range(m.range(at: 1), in: line), let pid = Int32(line[r]) {
                out[out.count - 1].onBehalfOfPID = pid
            }
        }
        return sawHeader ? out : nil
    }

    /// Code shipped with macOS: the sealed/SIP-protected system locations. /usr/local is the
    /// user's (Homebrew on Intel), so it is excluded.
    static func isOSExecutable(_ path: String) -> Bool {
        if path.hasPrefix("/usr/local/") { return false }
        return ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    /// Ordinary = a user app (same rule the memory item uses: /System/Applications and the
    /// Safari cryptex count, /System/Library does not) or anything outside the OS locations.
    static func isOrdinary(_ path: String) -> Bool {
        Parsers.appBundleName(fromCommandPath: path) != nil || !isOSExecutable(path)
    }

    private static func programName(path: String, name: String?) -> String {
        if let bundle = Parsers.appBundleName(fromCommandPath: path) { return bundle }
        guard let name, !name.isEmpty else { return (path as NSString).lastPathComponent }
        return name
    }

    static func holders(from assertions: [PowerAssertion],
                        lookup: (Int32) -> ProcRecord?,
                        minimumAge: Int = minimumAgeSeconds) -> [WakeHolder] {
        var best: [String: WakeHolder] = [:]
        for a in assertions where sleepPreventingTypes.contains(a.type) && a.ageSeconds >= minimumAge {
            let ownerPath = lookup(a.pid)?.path
            let ownerName = ownerPath.flatMap { Parsers.appBundleName(fromCommandPath: $0) } ?? a.processName

            // Walk from the declared requester up through OS helpers (caffeinate, zsh, login…)
            // to the first program that is not part of the OS, stopping at launchd.
            var pid = a.onBehalfOfPID ?? a.pid
            var path = lookup(pid)?.path
            var hops = 0
            while let p = path, !isOrdinary(p), hops < maxParentHops,
                  let parent = lookup(pid)?.ppid, parent > 1, let parentPath = lookup(parent)?.path {
                pid = parent; path = parentPath; hops += 1
            }

            let holder: WakeHolder
            if let p = path, isOrdinary(p) {
                let requester = programName(path: p, name: lookup(pid)?.name)
                holder = WakeHolder(owner: ownerName,
                                    requester: (pid == a.pid || requester == ownerName) ? nil : requester,
                                    ageSeconds: a.ageSeconds)
            } else if let op = ownerPath, isOrdinary(op) {
                holder = WakeHolder(owner: ownerName, requester: nil, ageSeconds: a.ageSeconds)
            } else {
                continue   // system, or unreadable: silent
            }
            let key = holder.owner + "\u{1}" + (holder.requester ?? "")
            if let prev = best[key], prev.ageSeconds >= holder.ageSeconds { continue }
            best[key] = holder
        }
        return best.values.sorted {
            $0.ageSeconds != $1.ageSeconds ? $0.ageSeconds > $1.ageSeconds
                : label(for: $0) < label(for: $1)
        }
    }

    /// "caffeinate (от claude)" / "Zoom" in the current language.
    static func label(for h: WakeHolder) -> String {
        h.requester.map { L.wakeHolderOnBehalf(h.owner, $0) } ?? h.owner
    }

    /// pmset's own age, floored to minutes: "21 мин", "1 ч 21 мин".
    static func ageText(_ seconds: Int) -> String {
        let totalMinutes = max(0, seconds) / 60
        if totalMinutes < 60 { return "\(totalMinutes) \(L.uptimeUnitMinute)" }
        return L.uptimeHourMinuteCombo(totalMinutes / 60, totalMinutes % 60)
    }

    // MARK: - live

    private static let maxPathSize = 4 * 1024   // PROC_PIDPATHINFO_MAXSIZE, see ProcessInspector

    /// Pure parse of a raw `KERN_PROCARGS2` buffer: `Int32 argc`, then the NUL-terminated exec
    /// path, then NUL padding, then argv[0] (also NUL-terminated). Bounds-checked throughout;
    /// any malformed or truncated buffer yields nil rather than trapping.
    static func argv0Name(procargs: [UInt8]) -> String? {
        guard procargs.count >= 4 else { return nil }
        let argc = Int32(procargs[0]) | (Int32(procargs[1]) << 8)
                 | (Int32(procargs[2]) << 16) | (Int32(procargs[3]) << 24)
        guard argc > 0 else { return nil }

        var i = 4
        while i < procargs.count, procargs[i] != 0 { i += 1 }
        guard i < procargs.count else { return nil }        // exec path never NUL-terminated
        while i < procargs.count, procargs[i] == 0 { i += 1 } // NUL padding after exec path
        guard i < procargs.count else { return nil }         // no argv[0] present

        var j = i
        while j < procargs.count, procargs[j] != 0 { j += 1 }
        guard j < procargs.count else { return nil }         // argv[0] truncated, no NUL

        guard let raw = String(bytes: procargs[i..<j], encoding: .utf8), !raw.isEmpty else { return nil }
        var name = (raw as NSString).lastPathComponent
        if name.hasPrefix("-") { name = String(name.dropFirst()) }
        return name.isEmpty ? nil : name
    }

    /// argv[0] via `sysctl [CTL_KERN, KERN_PROCARGS2, pid]`, sized from `KERN_ARGMAX`. Fails
    /// (nil) for another user's process when not root, same as it fails for `ps`.
    private static func argv0(forPid pid: Int32) -> String? {
        var argMax: Int32 = 0
        var argMaxSize = MemoryLayout<Int32>.size
        var argMaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argMaxMib, 2, &argMax, &argMaxSize, nil, 0) == 0, argMax > 0 else { return nil }

        var procArgsMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = Int(argMax)
        var buffer = [UInt8](repeating: 0, count: size)
        let ok = buffer.withUnsafeMutableBytes { raw in
            sysctl(&procArgsMib, u_int(procArgsMib.count), raw.baseAddress, &size, nil, 0) == 0
        }
        guard ok, size > 0, size <= buffer.count else { return nil }
        return argv0Name(procargs: Array(buffer[0..<size]))
    }

    /// proc_pidpath (allowed for every pid) + ppid from sysctl KERN_PROC_PID (what ps uses) +
    /// argv[0] from KERN_PROCARGS2 (what `ps -o comm=` prints; the kernel's own p_comm is the
    /// resolved exec file name and carries no more information than the path).
    static func processRecord(pid: Int32) -> ProcRecord? {
        var buffer = [Int8](repeating: 0, count: maxPathSize)
        let n = proc_pidpath(pid, &buffer, UInt32(maxPathSize))
        let path: String? = n > 0 ? String(cString: buffer) : nil

        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let ok = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 && size > 0
        let ppid: Int32? = ok ? info.kp_eproc.e_ppid : nil
        let name = argv0(forPid: pid)

        if path == nil && ppid == nil { return nil }
        return ProcRecord(path: path, ppid: ppid, name: name)
    }

    /// One `pmset -g assertions` run, parsed and classified. Total: a launch failure or a
    /// timeout is `([], nil)`; unparsable output is `([], failure)`.
    static func sample() async -> (holders: [WakeHolder], failure: ParseFailure?) {
        guard let out = await ParsedCommand.pmsetAssertions.run().text else { return ([], nil) }
        guard let assertions = parseAssertions(out) else {
            return ([], ParseFailure(.pmsetAssertions, stdout: out))
        }
        return (holders(from: assertions, lookup: processRecord(pid:)), nil)
    }
}
