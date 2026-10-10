// Engine/BackupLog.swift
// BACKUP-AGE: parses and reads ~/Library/Logs/claude-backup.log (written by backup_auto.sh)
// to find the newest successful snapshot. Foundation only; compiled into Checks.
import Foundation

/// What the Claude backup log says about the newest successful snapshot (BACKUP-AGE).
enum ClaudeBackupStatus: Equatable {
    case lastSuccess(Date)
    case noSuccessFound
    case unreadable
}

/// Plain enum, NOT @MainActor: its async func runs on the global executor.
enum BackupLog {
    static let logURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/claude-backup.log")
    static let rotatedURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/claude-backup.log.1")
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

    /// Newest success time in `text`: max over `…  OK` event lines and `Snapshot done: …/YYYY-MM-DD_HHMMSS` lines.
    static func latestSuccess(in text: String, timeZone: TimeZone = .current) -> Date? {
        let eventFmt = formatter("yyyy-MM-dd HH:mm:ss", timeZone)
        let stampFmt = formatter("yyyy-MM-dd_HHmmss", timeZone)
        let eventRE = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}  OK$")
        let stampRE = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}_\\d{6}$")
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

    static func readStatus() async -> ClaudeBackupStatus? { status() }

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
