// Engine/HistoryStore.swift
// Report agent owns this file (SPEC §3, §7).
//
// Legacy-compatible JSON history store (~/Library/Application Support/MacDashboard/
// mac_check_state.json). Loads/decodes the known schema (last_run, mac_history) while
// separately keeping the full raw JSON object, so unknown legacy keys the current
// Models.swift doesn't model (nvme_history, nvme_skip_streak, nvme_rate_baseline, and
// any future additions) survive a load→mutate→save round-trip untouched.
// The mac_history array is also kept exactly as parsed (rawEntries): save() writes that
// array, so entries this version cannot decode and unknown fields inside an entry survive.
// A file that exists but cannot be parsed as a history object is never overwritten: the
// next save() renames it to <name>.unreadable-<yyyyMMdd-HHmmss> first (HISTORY-DECODE-LOSS).
// The backup's name is recorded in the new file (unreadable_backup) until the user hides the
// History-restarted notice (HISTORY-UNREADABLE-NOTICE).

import Foundation

final class HistoryStore {

    private let url: URL

    /// Full JSON object as last loaded from disk (or [:] if missing/corrupt/never
    /// loaded). Holds every key, known or not; `save()` overwrites only the keys that
    /// HistoryState itself encodes and passes everything else through unchanged.
    private var raw: [String: Any] = [:]

    /// Every element of the file's mac_history array exactly as parsed — decodable or not,
    /// every field known or not. save() writes this array; `state.mac_history` is its
    /// decodable subset in the same order.
    private var rawEntries: [Any] = []

    /// true when load() found a file it could not read as a history object. The next
    /// save() renames that file aside before writing, so its bytes are never overwritten.
    private var loadedUnreadableFile = false

    private(set) var state: HistoryState = HistoryState()

    init(url: URL) {
        self.url = url
    }

    /// Missing file ⇒ empty state. A file that exists but cannot be read as a history
    /// object (bytes unreadable, not JSON, top level not an object, mac_history present
    /// but not an array) ⇒ empty state, and the next save() renames it aside first.
    /// Inside a valid mac_history, an element that does not decode is left out of `state`
    /// but kept in rawEntries, so save() writes it back unchanged. Never writes, never throws.
    /// A valid stored unreadable_backup name is loaded into state (storedBackupName).
    @discardableResult
    func load() -> HistoryState {
        raw = [:]
        rawEntries = []
        state = HistoryState()
        loadedUnreadableFile = false
        guard FileManager.default.fileExists(atPath: url.path) else { return state }
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            loadedUnreadableFile = true
            return state
        }
        raw = obj
        if let history = obj["mac_history"], !(history is [Any]) {
            loadedUnreadableFile = true
            return state
        }
        state.unreadable_backup = Self.storedBackupName(obj[Self.unreadableBackupKey], historyFile: url)
        rawEntries = obj["mac_history"] as? [Any] ?? []
        state.last_run = obj["last_run"] as? String
        state.mac_history = Self.decodeEntries(rawEntries)
        return state
    }

    /// Upsert TODAY's MacHistoryEntry from report+live (replace every stored same-date element, decodable or not),
    /// keep every other day (no cap — the history runs from the first day the app ran),
    /// keep entries sorted by date, set last_run. Pure in-memory mutation — call save()
    /// afterward to persist.
    func upsertToday(from report: FullReport, live: LiveSnapshot) {
        let today = Self.dayFormatter.string(from: Date())
        let battery = report.battery ?? live.battery

        var entry = MacHistoryEntry(date: today)

        if let disk = live.disk {
            // GiB (÷2^30), not decimal GB: verified against legacy references —
            // mac_report.txt's df output shows "96Gi .. 108Gi" for /System/Volumes/Data
            // and mac_check_state.json's matching entry stores disk_used_gb: 96,
            // disk_free_gb: 108 — the legacy numbers ARE binary GiB, not 10^9 decimal GB.
            // Prefer the more precise dataUsed (df "Used" for /System/Volumes/Data) when
            // the collector populates it; otherwise fall back to the derived
            // usedTotal = size - avail (LiveCollector per SPEC §5.1 only uses
            // volumeTotalCapacity/volumeAvailableCapacityForImportantUsage, so dataUsed
            // may legitimately stay nil — this is the best available signal either way).
            let used = disk.dataUsed ?? disk.usedTotal
            entry.disk_used_gb = Self.roundedGiB(used)
            entry.disk_free_gb = Self.roundedGiB(disk.avail)
        }

        entry.battery_pct = battery?.maxCapacity
        entry.cycles = battery?.cycles

        if let swap = live.swap {
            entry.swap = "\(Self.roundedMiB(swap.used))MB/\(Self.roundedMiB(swap.total))MB"
        }

        if let sys = report.system {
            if let v = sys.osVersion, let b = sys.osBuild {
                entry.macos = "\(v) (\(b))"
            } else if let v = sys.osVersion {
                entry.macos = v
            }
        }

        let freshData = (try? JSONEncoder().encode(entry)) ?? Data()
        let fresh = (try? JSONSerialization.jsonObject(with: freshData)) as? [String: Any] ?? ["date": today]
        rawEntries.removeAll { Self.dateKey($0) == today }
        rawEntries.append(fresh)
        rawEntries.sort { Self.dateKey($0) < Self.dateKey($1) }   // "yyyy-MM-dd" sorts chronologically as text
        state.mac_history = Self.decodeEntries(rawEntries)
        state.last_run = today
    }

    /// Atomic; PRESERVES unknown top-level keys and every stored mac_history element as
    /// parsed (raw ← known-encoded keys overwrite, mac_history ← rawEntries). If load() found
    /// an unreadable file, renames it aside first and records the backup's name in the new file
    /// (unreadable_backup); a failed rename throws before any write and records nothing.
    func save() throws {
        // Chosen before encoding, so the new file names the backup it is about to make.
        let backup: URL? = loadedUnreadableFile && FileManager.default.fileExists(atPath: url.path)
            ? unreadableBackupURL() : nil
        var next = state
        if let backup { next.unreadable_backup = backup.lastPathComponent }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let knownData = try encoder.encode(next)
        let knownObj = try JSONSerialization.jsonObject(with: knownData) as? [String: Any] ?? [:]

        var merged = raw
        for (key, value) in knownObj {
            merged[key] = value
        }
        // The encoder omits a nil optional, so without this a hidden notice's key would survive from raw.
        if next.unreadable_backup == nil { merged.removeValue(forKey: Self.unreadableBackupKey) }
        merged["mac_history"] = rawEntries   // every stored element, not only the decodable ones

        let outData = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])

        let dir = url.deletingLastPathComponent()
        // 0700/0600, same reasoning as ReportWriter.write: this file is a day-by-day series of
        // the machine's disk/battery/memory state and sits next to the report.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        if loadedUnreadableFile {
            if let backup {
                try FileManager.default.moveItem(at: url, to: backup)
                state.unreadable_backup = backup.lastPathComponent   // only after a successful rename
            }
            loadedUnreadableFile = false   // only after a successful rename (or nothing left to rename)
        }
        try outData.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        raw = merged
    }

    /// The user hid the History-restarted notice: forget the backup's name. Pure in-memory;
    /// the next save() removes the key from the file. The backup file itself is never touched.
    func clearUnreadableBackup() {
        state.unreadable_backup = nil
    }

    // MARK: - Helpers

    /// The elements of `items` that decode as MacHistoryEntry, in order. Everything else
    /// stays only in rawEntries and is saved unchanged.
    private static func decodeEntries(_ items: [Any]) -> [MacHistoryEntry] {
        let decoder = JSONDecoder()
        return items.compactMap { item in
            guard let dict = item as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(MacHistoryEntry.self, from: data)
        }
    }

    /// The element's "date" string, or "" when it has none (such elements sort first).
    private static func dateKey(_ item: Any) -> String {
        ((item as? [String: Any])?["date"] as? String) ?? ""
    }

    /// JSON key of HistoryState.unreadable_backup — must equal that property's name (the
    /// synthesized Codable key); save() removes the key by this name once the notice is hidden.
    static let unreadableBackupKey = "unreadable_backup"

    /// `value` if it is a plain `<history file name>.unreadable-…` name in the same folder;
    /// anything else (not a string, a path, another prefix) ⇒ nil, so the notice's Finder
    /// button can only ever point next to the history file.
    static func storedBackupName(_ value: Any?, historyFile: URL) -> String? {
        guard let name = value as? String,
              name.hasPrefix(historyFile.lastPathComponent + ".unreadable-"),
              !name.contains("/") else { return nil }
        return name
    }

    /// `<file name>.unreadable-<yyyyMMdd-HHmmss>` next to the history file.
    private func unreadableBackupURL() -> URL {
        url.deletingLastPathComponent().appendingPathComponent(
            url.lastPathComponent + ".unreadable-" + Self.backupStampFormatter.string(from: Date()))
    }

    private static func roundedGiB(_ bytes: Int64) -> Int {
        Int((Double(bytes) / 1_073_741_824.0).rounded())   // ÷ 2^30
    }

    private static func roundedMiB(_ bytes: Int64) -> Int {
        Int((Double(bytes) / 1_048_576.0).rounded())        // ÷ 2^20
    }

    private static var dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static var backupStampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df
    }()
}
