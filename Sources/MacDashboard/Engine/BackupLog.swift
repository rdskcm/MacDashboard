// Engine/BackupLog.swift
// BACKUP-AGE: parses and reads ~/Library/Logs/claude-backup.log (written by backup_auto.sh)
// to find the newest successful snapshot and the last attempt (BACKUP-CARD-FAILURE). Foundation only; covered by Tests/MacDashboardTests.
import Foundation

/// What the Claude backup log says about the newest successful snapshot (BACKUP-AGE).
enum ClaudeBackupStatus: Equatable {
    case lastSuccess(Date)
    case noSuccessFound
    case unreadable
}

/// The last real backup run in the log (BACKUP-CARD-FAILURE). SKIP lines are not attempts.
struct ClaudeBackupAttempt: Equatable, Sendable {
    enum Reason: Int, Equatable, Sendable { case other, filesChanged, diskError, noPermission, noSpace, diskDisconnected }   // rawValue = priority (D13)
    enum Result: Equatable, Sendable { case running, interrupted, ok, failed(exit: Int, reason: Reason) }
    var at: Date          // the START time for running/interrupted, else the time on the OK/FAILED line
    var result: Result
    var mount: String?    // from the last START seen; nil when that START is not in the text read
}

/// The `SIZE:` line backup_auto.sh writes after a successful run (bytes; the log holds KiB).
struct ClaudeBackupSize: Equatable, Sendable { var snapshotBytes: Int64; var addedBytes: Int64; var totalBytes: Int64 }

/// What a forced run logged instead of starting (only SKIP lines; a started run shows as an attempt).
enum ClaudeBackupClickOutcome: Equatable, Sendable { case diskNotConnected, alreadyRunning }

/// Plain enum, NOT @MainActor: its async func runs on the global executor.
enum BackupLog {
    static let logURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/claude-backup.log")
    static let rotatedURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/claude-backup.log.1")
    /// The log pair for a user override (`AppSettings.claudeLogPath`, `~` expanded); nil or empty → the defaults.
    static func resolvedURLs(custom: String?) -> (log: URL, rotated: URL) {
        guard let custom, !custom.isEmpty else { return (logURL, rotatedURL) }
        let log = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        return (log, URL(fileURLWithPath: log.path + ".1"))
    }
    /// Tail windows tried in order: 64 KiB, then 2 MiB (twice the rotation threshold).
    static let windows = [64 * 1024, 2 * 1024 * 1024]

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        f.isLenient = false
        return f
    }

    // BACKUP-LOG-TIDY: built once. NSRegularExpression is immutable and thread-safe; the two
    // formatters are shared mutable state (their zone follows each call, and readStatus runs
    // on the global executor, so calls can overlap), so every use of them is under formatterLock.
    private static let eventRE = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}  OK$")
    private static let sizeRE = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}  SIZE: snapshot=(\\d+) added=(\\d+) total=(\\d+)$")
    private static let stampRE = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}_\\d{6}$")
    private static let eventFmt = formatter("yyyy-MM-dd HH:mm:ss", .current)
    private static let stampFmt = formatter("yyyy-MM-dd_HHmmss", .current)
    private static let formatterLock = NSLock()

    /// Newest success time in `text`: max over `…  OK` event lines and `Snapshot done: …/YYYY-MM-DD_HHMMSS` lines.
    static func latestSuccess(in text: String, timeZone: TimeZone = .current) -> Date? {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        // Re-zoning rebuilds a formatter's internals, so only on an actual change; a spurious
        // "unequal" merely re-assigns, results never depend on this comparison.
        if eventFmt.timeZone != timeZone {
            eventFmt.timeZone = timeZone
            stampFmt.timeZone = timeZone
        }
        func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
            re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        var best: Date? = nil
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            var found: Date? = nil
            if matches(eventRE, line) {
                found = eventFmt.date(from: String(line.prefix(19)))
            } else if line.hasPrefix("Snapshot done: ") {
                let last = (line as NSString).lastPathComponent
                if matches(stampRE, last) { found = stampFmt.date(from: last) }
            }
            if let d = found, best == nil || d > best! { best = d }
        }
        return best
    }

    /// Last `maxBytes` of a file as text; a window starting mid-file drops its first (partial) line.
    static func tailText(of url: URL, maxBytes: Int) throws -> (text: String, coversWholeFile: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try handle.seek(toOffset: offset)
        var data = try handle.readToEnd() ?? Data()
        if offset > 0 {
            if let nl = data.firstIndex(of: 0x0A) {
                data = data.subdata(in: data.index(after: nl)..<data.endIndex)
            } else {
                data = Data()
            }
        }
        return (String(decoding: data, as: UTF8.self), offset == 0)
    }

    static func status(logURL: URL = BackupLog.logURL, rotatedURL: URL = BackupLog.rotatedURL) -> ClaudeBackupStatus? {
        let existing = [logURL, rotatedURL].filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.isEmpty { return nil }
        var unreadableCount = 0
        for url in existing {
            var failed = false
            for window in windows {
                guard let tail = try? tailText(of: url, maxBytes: window) else { failed = true; break }
                if let d = latestSuccess(in: tail.text) { return .lastSuccess(d) }
                if tail.coversWholeFile { break }
            }
            if failed { unreadableCount += 1 }
        }
        return unreadableCount == existing.count ? .unreadable : .noSuccessFound
    }

    static func readStatus(logURL: URL = BackupLog.logURL, rotatedURL: URL = BackupLog.rotatedURL) async -> ClaudeBackupStatus? { status(logURL: logURL, rotatedURL: rotatedURL) }

    static func isStale(_ s: ClaudeBackupStatus, thresholdHours: Int, now: Date) -> Bool {
        switch s {
        case .lastSuccess(let d): return max(0, now.timeIntervalSince(d)) >= Double(thresholdHours) * 3600
        case .noSuccessFound: return true
        case .unreadable: return false
        }
    }

    static func durationText(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 3600 { return "\(s / 60) \(L.uptimeUnitMinute)" }
        if s < 86_400 { return "\(s / 3600) \(L.uptimeUnitHour)" }
        let d = s / 86_400, h = (s % 86_400) / 3600
        return h > 0 ? "\(d) \(L.uptimeUnitDay) \(h) \(L.uptimeUnitHour)" : "\(d) \(L.uptimeUnitDay)"
    }
}

extension BackupLog {
    /// 64 KiB, 2 MiB, then 32 MiB: one failure block can outgrow the rotation threshold (real block: 4 490 lines).
    static let attemptWindows = [64 * 1024, 2 * 1024 * 1024, 32 * 1024 * 1024]
    /// Written by backup_auto.sh (`$LOCK/pid`); holds the running script's pid.
    static let lockPIDURL = URL(fileURLWithPath: "/tmp/.claude-backup.lock/pid")
    /// Written by backup_auto.sh (`$LOCK/progress`): "<KiB written> <KiB of the previous snapshot>".
    static let progressURL = URL(fileURLWithPath: "/tmp/.claude-backup.lock/progress")
    /// Longest real run: 16 min. Past this a live pid is taken as recycled (D1).
    static let maxRunSeconds: TimeInterval = 3 * 3600

    /// One output line → its failure class; nil = says nothing about the cause.
    static func reason(forOutputLine line: Substring) -> ClaudeBackupAttempt.Reason? {
        if line.contains("Volume not mounted") || line.contains("Device not configured") { return .diskDisconnected }
        if line.contains("No space left on device") { return .noSpace }
        if line.contains("Operation not permitted") || line.contains("Permission denied") { return .noPermission }
        if line.contains("Input/output error") { return .diskError }
        if line.contains("hard link") { return nil }   // D14
        if line.contains("No such file or directory") || line.contains("vanished") { return .filesChanged }
        return nil
    }

    /// The last START / OK / FAILED in `text`; a START with nothing after it comes back as `.running` (see `settled`).
    static func lastAttempt(in text: String, timeZone: TimeZone = .current) -> ClaudeBackupAttempt? {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if eventFmt.timeZone != timeZone { eventFmt.timeZone = timeZone; stampFmt.timeZone = timeZone }
        var attempt: ClaudeBackupAttempt? = nil
        var mount: String? = nil
        var inFailedBlock = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if raw.first == " " {
                if inFailedBlock, case .failed(let exit, let current)? = attempt?.result,
                   let r = reason(forOutputLine: raw), r.rawValue > current.rawValue {
                    attempt?.result = .failed(exit: exit, reason: r)
                }
                continue
            }
            guard raw.dropFirst(19).hasPrefix("  "), let date = eventFmt.date(from: String(raw.prefix(19))) else { continue }
            inFailedBlock = false                     // every event line ends a failure's output block
            let tail = raw.dropFirst(21)
            if tail.hasPrefix("START: ") {
                mount = String(tail.dropFirst(7))
                attempt = ClaudeBackupAttempt(at: date, result: .running, mount: mount)
            } else if tail == "OK" {
                attempt = ClaudeBackupAttempt(at: date, result: .ok, mount: mount)
            } else if tail.hasPrefix("FAILED (exit "), let exit = Int(tail.dropFirst(13).prefix { $0.isNumber }) {
                attempt = ClaudeBackupAttempt(at: date, result: .failed(exit: exit, reason: .other), mount: mount)
                inFailedBlock = true
            }
        }
        return attempt
    }

    /// Whether a `.running` attempt is really running (D1). Other results pass through.
    static func settled(_ a: ClaudeBackupAttempt, lockPIDAlive: Bool, now: Date) -> ClaudeBackupAttempt {
        guard a.result == .running else { return a }
        if lockPIDAlive && now.timeIntervalSince(a.at) < maxRunSeconds { return a }
        var out = a
        out.result = .interrupted
        return out
    }

    static func lockPID(at url: URL) -> Int32? {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Int32(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// EPERM = someone else's process, so not our script.
    static func isProcessAlive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }

    /// The LAST well-formed `SIZE:` line in `text`, in bytes. Malformed lines and overflowing numbers are no match.
    static func latestSize(in text: String) -> ClaudeBackupSize? {
        var out: ClaudeBackupSize? = nil
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            let range = NSRange(line.startIndex..., in: line)
            guard let m = sizeRE.firstMatch(in: line, range: range), m.numberOfRanges == 4 else { continue }
            var v: [Int64] = []
            for i in 1...3 {
                guard let r = Range(m.range(at: i), in: line), let n = Int64(line[r]) else { break }
                let (b, overflow) = n.multipliedReportingOverflow(by: 1024)
                if overflow { break }
                v.append(b)
            }
            if v.count == 3 { out = ClaudeBackupSize(snapshotBytes: v[0], addedBytes: v[1], totalBytes: v[2]) }
        }
        return out
    }

    /// The newest size across the pair (a later failed run keeps it: it describes the last successful snapshot).
    static func size(logURL: URL = BackupLog.logURL, rotatedURL: URL = BackupLog.rotatedURL) -> ClaudeBackupSize? {
        for url in [logURL, rotatedURL] where FileManager.default.fileExists(atPath: url.path) {
            for window in attemptWindows {
                guard let tail = try? tailText(of: url, maxBytes: window) else { break }
                if let s = latestSize(in: tail.text) { return s }
                if tail.coversWholeFile { break }
            }
        }
        return nil
    }

    /// The newest attempt across the pair: the main log wins as soon as it holds any attempt line.
    static func attempt(logURL: URL = BackupLog.logURL, rotatedURL: URL = BackupLog.rotatedURL) -> ClaudeBackupAttempt? {
        for url in [logURL, rotatedURL] where FileManager.default.fileExists(atPath: url.path) {
            for window in attemptWindows {
                guard let tail = try? tailText(of: url, maxBytes: window) else { break }
                if let a = lastAttempt(in: tail.text) { return a }
                if tail.coversWholeFile { break }
            }
        }
        return nil
    }

    /// Off the main actor, like `readStatus`.
    static func readAttempt(logURL: URL = BackupLog.logURL, rotatedURL: URL = BackupLog.rotatedURL,
                            lockPIDURL: URL = BackupLog.lockPIDURL, now: Date) async -> ClaudeBackupAttempt? {
        guard let a = attempt(logURL: logURL, rotatedURL: rotatedURL) else { return nil }
        let alive = lockPID(at: lockPIDURL).map(isProcessAlive) ?? false
        return settled(a, lockPIDAlive: alive, now: now)
    }

    static func readSize(logURL: URL = BackupLog.logURL, rotatedURL: URL = BackupLog.rotatedURL) async -> ClaudeBackupSize? {
        size(logURL: logURL, rotatedURL: rotatedURL)
    }

    /// The sampler's "<current> <total>" line as a fraction. Capped below 1: copying is not done until the log says OK.
    static func progressFraction(in text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2, let cur = Int64(parts[0]), let total = Int64(parts[1]), total > 0, cur >= 0 else { return nil }
        return min(Double(cur) / Double(total), 0.99)
    }

    static func readProgress(at url: URL = BackupLog.progressURL) async -> Double? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return progressFraction(in: text)
    }

    /// The newest disk-absent / already-running SKIP stamped at or after `since` (log stamps are whole seconds).
    static func clickOutcome(in text: String, since: Date, timeZone: TimeZone = .current) -> ClaudeBackupClickOutcome? {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if eventFmt.timeZone != timeZone { eventFmt.timeZone = timeZone; stampFmt.timeZone = timeZone }
        let floorSince = Date(timeIntervalSince1970: floor(since.timeIntervalSince1970))
        var out: ClaudeBackupClickOutcome? = nil
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) where raw.first != " " {
            guard raw.dropFirst(19).hasPrefix("  "), let date = eventFmt.date(from: String(raw.prefix(19))), date >= floorSince else { continue }
            let tail = raw.dropFirst(21)
            if tail.hasPrefix("SKIP: disk not connected") { out = .diskNotConnected }
            else if tail.hasPrefix("SKIP: another run is in progress") { out = .alreadyRunning }
        }
        return out
    }

    static func readClickOutcome(logURL: URL = BackupLog.logURL, since: Date) async -> ClaudeBackupClickOutcome? {
        guard let tail = try? tailText(of: logURL, maxBytes: windows[0]) else { return nil }
        return clickOutcome(in: tail.text, since: since)
    }

    /// Stat off the main actor (D7).
    static func pathExists(_ path: String) async -> Bool { FileManager.default.fileExists(atPath: path) }

    static func reasonText(_ r: ClaudeBackupAttempt.Reason, exit: Int) -> String {
        switch r {
        case .diskDisconnected: return L.bkClaudeReasonDiskGone
        case .diskError: return L.bkClaudeReasonDiskError
        case .noSpace: return L.bkClaudeReasonNoSpace
        case .noPermission: return L.bkClaudeReasonNoPermission
        case .filesChanged: return L.bkClaudeReasonFilesChanged
        case .other: return L.bkClaudeReasonOther(exit)
        }
    }
}
