// Engine/HistoryStore.swift
// Report agent owns this file (SPEC §3, §7).
//
// Legacy-compatible JSON history store (~/Library/Application Support/MacDashboard/
// mac_check_state.json). Loads/decodes the known schema (last_run, mac_history) while
// separately keeping the full raw JSON object, so unknown legacy keys the current
// Models.swift doesn't model (nvme_history, nvme_skip_streak, nvme_rate_baseline, and
// any future additions) survive a load→mutate→save round-trip untouched.

import Foundation

final class HistoryStore {

    private let url: URL

    /// Full JSON object as last loaded from disk (or [:] if missing/corrupt/never
    /// loaded). Holds every key, known or not; `save()` overwrites only the keys that
    /// HistoryState itself encodes and passes everything else through unchanged.
    private var raw: [String: Any] = [:]

    private(set) var state: HistoryState = HistoryState()

    init(url: URL) {
        self.url = url
    }

    /// Missing/corrupt file ⇒ empty state, never throws.
    @discardableResult
    func load() -> HistoryState {
        guard let data = try? Data(contentsOf: url) else {
            raw = [:]
            state = HistoryState()
            return state
        }
        raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        state = (try? JSONDecoder().decode(HistoryState.self, from: data)) ?? HistoryState()
        return state
    }

    /// Upsert TODAY's MacHistoryEntry from report+live (replace same-date entry),
    /// cap 60 (drop oldest), set last_run. Pure in-memory mutation — call save()
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

        state.mac_history.removeAll { $0.date == today }
        state.mac_history.append(entry)
        Self.sortAndCap(&state.mac_history)
        state.last_run = today
    }

    /// Atomic; PRESERVES unknown legacy JSON keys (raw ← known-encoded keys overwrite,
    /// everything else passes through untouched).
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let knownData = try encoder.encode(state)
        let knownObj = try JSONSerialization.jsonObject(with: knownData) as? [String: Any] ?? [:]

        var merged = raw
        for (key, value) in knownObj {
            merged[key] = value
        }

        let outData = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try outData.write(to: url, options: [.atomic])

        raw = merged
    }

    // MARK: - Helpers

    private static func sortAndCap(_ entries: inout [MacHistoryEntry]) {
        entries.sort { $0.date < $1.date }   // "yyyy-MM-dd" sorts chronologically as text
        if entries.count > 60 {
            entries.removeFirst(entries.count - 60)
        }
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
}
