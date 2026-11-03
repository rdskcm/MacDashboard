// Engine/TimeMachineStatus.swift
// REDESIGN-BACKUPS: `tmutil status` → TMBackupProgress. Foundation only; covered by Tests/MacDashboardTests.
// tmutil(8): "status [-X] — Display status information about the current backup (if any)". The output is an
// XML plist with -X, or the OpenStep-style dictionary description after a "Backup session status:" line;
// PropertyListSerialization reads both, and in the OpenStep form every number is a string, hence `num`.
import Foundation

/// One `tmutil status` sample. `percent` is 0…1 or nil when tmutil reports -1 / nothing yet.
struct TMBackupProgress: Equatable, Sendable {
    var running: Bool
    var stopping: Bool
    // Optionals default to nil so the synthesized memberwise init takes just `running:` and
    // `stopping:` when that is all a caller has; the parser fills all eleven fields.
    var phase: String? = nil
    var percent: Double? = nil
    var bytesDone: Int64? = nil
    var bytesTotal: Int64? = nil
    var secondsRemaining: Int? = nil
    var destinationMountPoint: String? = nil
    /// FindingChanges only: top-level `ChangedItemCount` and the scan's own `FractionDone` (0…1).
    var changedItems: Int? = nil
    var scanFraction: Double? = nil
    /// `FractionOfProgressBar`: this phase's share of the whole bar (live: 0.1 in FindingChanges, 0.9 in Copying).
    var barShare: Double? = nil

    /// What the page assumes when tmutil could not be run at all.
    static let idle = TMBackupProgress(running: false, stopping: false)
}

enum TimeMachineStatus {
    /// nil when the text holds no dictionary with a `Running` key (undecodable).
    static func parse(text: String) -> TMBackupProgress? {
        // Strip the "Backup session status:" header (plain form) — keep from the first "{" or "<?xml".
        let start = text.range(of: "<?xml")?.lowerBound ?? text.firstIndex(of: "{") ?? text.startIndex
        let data = Data(text[start...].utf8)
        guard let any = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = any as? [String: Any], let running = num(root["Running"]) else { return nil }
        let progress = root["Progress"] as? [String: Any]
        let pct = num(progress?["Percent"] ?? root["Percent"]).flatMap { $0 < 0 ? nil : min(max($0, 0), 1) }
        return TMBackupProgress(
            running: running != 0,
            stopping: (num(root["Stopping"]) ?? 0) != 0,
            phase: root["BackupPhase"] as? String,
            percent: pct,
            bytesDone: progress.flatMap { num($0["bytes"]) }.map { Int64($0) },
            bytesTotal: progress.flatMap { num($0["totalBytes"]) }.map { Int64($0) },
            secondsRemaining: progress.flatMap { num($0["TimeRemaining"]) }.map { Int($0) },
            destinationMountPoint: root["DestinationMountPoint"] as? String,
            changedItems: num(root["ChangedItemCount"]).map { Int($0) },
            scanFraction: num(root["FractionDone"]).map { min(max($0, 0), 1) },
            barShare: num(root["FractionOfProgressBar"]).flatMap { $0 > 0 && $0 <= 1 ? $0 : nil })
    }

    /// Shares used when tmutil omits `FractionOfProgressBar` (the values every live sample carries).
    static let scanShare = 0.1, copyShare = 0.9

    /// The whole backup's progress, as the macOS Time Machine menu shows it. tmutil gives each phase's share but no
    /// offset, so only the two phases that carry the key have a figure. Copying is confirmed against the menu (2026-11-03:
    /// `Percent` 0.34509 → 41.06 %, menu 41.1 %). FindingChanges follows the same key; it was not compared with the menu.
    /// Any other phase: nil, the moving line.
    static func overallFraction(_ b: TMBackupProgress) -> Double? {
        switch b.phase {
        case "FindingChanges"?:
            let share = b.barShare ?? scanShare
            return b.scanFraction.map { share * $0 }
        case "Copying"?:
            let share = b.barShare ?? copyShare
            return b.percent.map { (1 - share) + share * $0 }
        default:
            return nil
        }
    }

    /// Lenient number: Int / Double / Bool / NSNumber / numeric String (OpenStep form quotes numbers).
    static func num(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let b as Bool: return b ? 1 : 0
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}
