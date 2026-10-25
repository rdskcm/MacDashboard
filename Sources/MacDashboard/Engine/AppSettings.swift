// Engine/AppSettings.swift
// Non-language app settings (interval, wake-holder ignore list, hidden crash reports, backup-stale days, low-space %, notify categories, appearance, orbs,
// keep-archives, snapshot time, claude log path). Foundation + Observation only — covered by Tests/MacDashboardTests.
import Foundation
import Observation

enum AppAppearance: String, CaseIterable { case system, light, dark }

/// User-tunable settings backed by UserDefaults. Mirrors L10nStore's pattern.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let fastIntervalKey = "fastIntervalSeconds"
    /// Allowed fast-loop polling intervals, seconds (handoff 11:23). 1 and 3 were retired in
    /// REDESIGN-FOUNDATION; `migrateLegacyValues` moves a stored 1 or 3 to the default.
    static let allowedIntervals = [2, 5, 10]
    static let defaultInterval = 2

    /// Pure resolution rule used by `init()`: any value outside `allowedIntervals` is the default.
    static func resolveFastInterval(raw: Int) -> Int {
        allowedIntervals.contains(raw) ? raw : defaultInterval
    }

    /// Key of the retired process-count setting (the process lists are a fixed top 8,
    /// `LiveCollector.topProcessCount`). Kept only so the migration can remove it.
    static let legacyProcessLimitKey = "processListLimit"

    /// REDESIGN-FOUNDATION migration, run first in `init()`. Idempotent: after one run there is
    /// no 1 s / 3 s interval and no process-count key, so a later run changes nothing. Any other
    /// stored interval is left to `resolveFastInterval`.
    static func migrateLegacyValues(in defaults: UserDefaults) {
        if let raw = defaults.object(forKey: fastIntervalKey) as? Int, raw == 1 || raw == 3 {
            defaults.set(defaultInterval, forKey: fastIntervalKey)
        }
        if let h = defaults.object(forKey: legacyBackupStaleHoursKey) as? Int {
            if defaults.object(forKey: backupStaleDaysKey) == nil { defaults.set(daysFromLegacyHours(h), forKey: backupStaleDaysKey) }
            defaults.removeObject(forKey: legacyBackupStaleHoursKey)
        }
        defaults.removeObject(forKey: legacyProcessLimitKey)
    }

    static let ignoredWakeHoldersKey = "ignoredWakeHolders"
    static let hiddenCrashReportsKey = "hiddenCrashReports"

    /// REDESIGN-SETTINGS: stale limit (days) for the Claude backup age; out-of-range values resolve to the default.
    static let backupStaleDaysKey = "backupStaleDays"
    static let legacyBackupStaleHoursKey = "backupStaleHours"
    static let backupStaleDaysRange = 1...30
    static let defaultBackupStaleDays = 2
    static func resolveBackupStaleDays(raw: Int) -> Int { backupStaleDaysRange.contains(raw) ? raw : defaultBackupStaleDays }
    /// Hours → days for the one-time migration: round(h / 24) clamped to the range (24→1, 48→2, 72→3, 168→7, 30→1, 1000→30).
    static func daysFromLegacyHours(_ hours: Int) -> Int { min(max(Int((Double(hours) / 24).rounded()), backupStaleDaysRange.lowerBound), backupStaleDaysRange.upperBound) }

    /// REDESIGN-SETTINGS: theme choice, applied app-wide through `NSApp.appearance`.
    static let appearanceKey = "appearance"
    static func resolveAppearance(raw: String?) -> AppAppearance { raw.flatMap(AppAppearance.init(rawValue:)) ?? .system }

    static let orbsEnabledKey = "backgroundOrbs"
    static let keepImportedArchivesKey = "keepImportedArchives"

    /// Daily snapshot time, minutes since midnight (default 03:00). 0 = 00:00 is valid, so raw is optional.
    static let snapshotMinutesKey = "snapshotMinutes"
    static let defaultSnapshotMinutes = 180
    static func resolveSnapshotMinutes(raw: Int?) -> Int { raw.map { (0..<1440).contains($0) ? $0 : defaultSnapshotMinutes } ?? defaultSnapshotMinutes }
    static let lastSnapshotAtKey = "lastSnapshotAt"
    static let claudeLogPathKey = "claudeLogPath"

    /// REDESIGN-STORAGE: amber low-space line (% free); any other stored value resolves to the default.
    static let lowSpacePercentKey = "lowSpacePercent"
    static let allowedLowSpacePercents = [10, 15, 20]
    static let defaultLowSpacePercent = 20
    static func resolveLowSpacePercent(raw: Int) -> Int {
        allowedLowSpacePercents.contains(raw) ? raw : defaultLowSpacePercent
    }

    /// REDESIGN-NOTIFY: one Bool key per category; a missing key means the category's default (five on, crashes off).
    static func resolveNotifyEnabled(in defaults: UserDefaults) -> Set<NotifyCategory> {
        Set(NotifyCategory.allCases.filter { (defaults.object(forKey: $0.defaultsKey) as? Bool) ?? $0.defaultOn })
    }

    /// SLEEP-IGNORE-APP codec, exposed for tests. Missing or unreadable data is an empty
    /// list: failing toward "warn" is the safe direction for this setting. Duplicate keys
    /// (only a hand-edited defaults value can hold them) are dropped, first occurrence kept,
    /// so no `ForEach` ever sees a repeated ID. A legacy entry `{owner, requester}` decodes
    /// with `since == nil` (REDESIGN-SYSTEM): nothing is lost and no date is invented.
    static func decodeIgnoredWakeHolders(_ data: Data?) -> [IgnoredWakeHolder] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = data.flatMap { try? decoder.decode([IgnoredWakeHolder].self, from: $0) } ?? []
        var seen = Set<WakeHolderKey>()
        return stored.filter { seen.insert($0.key).inserted }
    }
    static func encodeIgnoredWakeHolders(_ list: [IgnoredWakeHolder]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(list)
    }

    /// Sleep interval of DashboardModel's fast task (native CPU/RAM/disk/battery
    /// gauges). Read by the loop on every iteration, so a change applies on the
    /// next tick without restarting the task.
    var fastIntervalSeconds: Int {
        didSet { UserDefaults.standard.set(fastIntervalSeconds, forKey: Self.fastIntervalKey) }
    }

    /// Wake holders the Sleep attention item no longer warns about (SLEEP-IGNORE-APP),
    /// in the order the user added them, each with the date it was added (nil for legacy entries).
    /// Mutate through `DashboardModel.setWakeHolderIgnored` so the assessment updates at once.
    var ignoredWakeHolderEntries: [IgnoredWakeHolder] {
        didSet { UserDefaults.standard.set(Self.encodeIgnoredWakeHolders(ignoredWakeHolderEntries), forKey: Self.ignoredWakeHoldersKey) }
    }
    /// Read-only keys of the entries, for the assessment and Home.
    var ignoredWakeHolders: [WakeHolderKey] { ignoredWakeHolderEntries.map(\.key) }

    /// CRASH-REPORT-DISMISS: crash report files hidden on the Security page. Mutate through
    /// `DashboardModel.hideCrashGroup` / `unhideCrashGroup` so the list and the assessment update.
    var hiddenCrashReports: [HiddenCrashReport] {
        didSet { UserDefaults.standard.set(CrashDismiss.encode(hiddenCrashReports), forKey: Self.hiddenCrashReportsKey) }
    }

    /// BACKUP-AGE: warn when the newest Claude backup is older than this many days.
    /// Mutate through `DashboardModel.setBackupStaleDays` so the assessment updates at once.
    var backupStaleDays: Int {
        didSet { UserDefaults.standard.set(backupStaleDays, forKey: Self.backupStaleDaysKey) }
    }
    /// Read-only bridge for the hour-based consumers (assessment, Backups page model).
    var backupStaleHours: Int { backupStaleDays * 24 }

    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    var orbsEnabled: Bool {
        didSet { UserDefaults.standard.set(orbsEnabled, forKey: Self.orbsEnabledKey) }
    }
    /// No reader until REDESIGN-IPHONE.
    var keepImportedArchives: Bool {
        didSet { UserDefaults.standard.set(keepImportedArchives, forKey: Self.keepImportedArchivesKey) }
    }
    var snapshotMinutes: Int {
        didSet { UserDefaults.standard.set(snapshotMinutes, forKey: Self.snapshotMinutesKey) }
    }
    var lastSnapshotAt: Date? {
        didSet {
            if let d = lastSnapshotAt { UserDefaults.standard.set(d, forKey: Self.lastSnapshotAtKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.lastSnapshotAtKey) }
        }
    }
    /// nil = the default `~/Library/Logs/claude-backup.log`; an empty string is stored as nil.
    var claudeLogPath: String? {
        didSet {
            if let p = claudeLogPath, !p.isEmpty { UserDefaults.standard.set(p, forKey: Self.claudeLogPathKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.claudeLogPathKey); if claudeLogPath == "" { claudeLogPath = nil } }
        }
    }

    /// REDESIGN-STORAGE: amber low-space line, % free. The Settings control arrives in REDESIGN-SETTINGS.
    var lowSpacePercent: Int {
        didSet { UserDefaults.standard.set(lowSpacePercent, forKey: Self.lowSpacePercentKey) }
    }

    /// REDESIGN-NOTIFY: categories whose attention kinds may post a macOS notification (read by the edge detector at every commit).
    var notifyEnabled: Set<NotifyCategory> {
        didSet { for c in NotifyCategory.allCases { UserDefaults.standard.set(notifyEnabled.contains(c), forKey: c.defaultsKey) } }
    }

    private init() {
        Self.migrateLegacyValues(in: .standard)
        fastIntervalSeconds = Self.resolveFastInterval(raw: UserDefaults.standard.integer(forKey: Self.fastIntervalKey)) // 0 if unset
        ignoredWakeHolderEntries = Self.decodeIgnoredWakeHolders(UserDefaults.standard.data(forKey: Self.ignoredWakeHoldersKey))
        hiddenCrashReports = CrashDismiss.decode(UserDefaults.standard.data(forKey: Self.hiddenCrashReportsKey))
        let d = UserDefaults.standard
        backupStaleDays = Self.resolveBackupStaleDays(raw: d.integer(forKey: Self.backupStaleDaysKey))
        appearance = Self.resolveAppearance(raw: d.string(forKey: Self.appearanceKey))
        orbsEnabled = d.object(forKey: Self.orbsEnabledKey) as? Bool ?? true
        keepImportedArchives = d.object(forKey: Self.keepImportedArchivesKey) as? Bool ?? true
        snapshotMinutes = Self.resolveSnapshotMinutes(raw: d.object(forKey: Self.snapshotMinutesKey) as? Int)
        lastSnapshotAt = d.object(forKey: Self.lastSnapshotAtKey) as? Date
        let storedPath = d.string(forKey: Self.claudeLogPathKey)
        claudeLogPath = (storedPath?.isEmpty ?? true) ? nil : storedPath
        lowSpacePercent = Self.resolveLowSpacePercent(raw: UserDefaults.standard.integer(forKey: Self.lowSpacePercentKey)) // 0 if unset
        notifyEnabled = Self.resolveNotifyEnabled(in: d)
    }
}
