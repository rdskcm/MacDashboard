// Engine/AppSettings.swift
// Non-language app settings. Foundation + Observation only — covered by Tests/MacDashboardTests.
import Foundation
import Observation

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
        defaults.removeObject(forKey: legacyProcessLimitKey)
    }

    static let ignoredWakeHoldersKey = "ignoredWakeHolders"

    /// BACKUP-AGE: stale limit (hours) for the Claude backup age; any other stored value resolves to the default.
    static let backupStaleHoursKey = "backupStaleHours"
    static let allowedBackupStaleHours = [24, 48, 72, 168]
    static let defaultBackupStaleHours = 48
    static func resolveBackupStaleHours(raw: Int) -> Int {
        allowedBackupStaleHours.contains(raw) ? raw : defaultBackupStaleHours
    }

    /// REDESIGN-STORAGE: amber low-space line (% free); any other stored value resolves to the default.
    static let lowSpacePercentKey = "lowSpacePercent"
    static let allowedLowSpacePercents = [10, 15, 20]
    static let defaultLowSpacePercent = 20
    static func resolveLowSpacePercent(raw: Int) -> Int {
        allowedLowSpacePercents.contains(raw) ? raw : defaultLowSpacePercent
    }

    /// SLEEP-IGNORE-APP codec, exposed for Checks. Missing or unreadable data is an empty
    /// list: failing toward "warn" is the safe direction for this setting. Duplicate keys
    /// (only a hand-edited defaults value can hold them) are dropped, first occurrence kept,
    /// so Settings' `ForEach(id: \.self)` never sees a repeated ID.
    static func decodeIgnoredWakeHolders(_ data: Data?) -> [WakeHolderKey] {
        let stored = data.flatMap { try? JSONDecoder().decode([WakeHolderKey].self, from: $0) } ?? []
        var seen = Set<WakeHolderKey>()
        return stored.filter { seen.insert($0).inserted }
    }
    static func encodeIgnoredWakeHolders(_ list: [WakeHolderKey]) -> Data? {
        try? JSONEncoder().encode(list)
    }

    /// Sleep interval of DashboardModel's fast task (native CPU/RAM/disk/battery
    /// gauges). Read by the loop on every iteration, so a change applies on the
    /// next tick without restarting the task.
    var fastIntervalSeconds: Int {
        didSet { UserDefaults.standard.set(fastIntervalSeconds, forKey: Self.fastIntervalKey) }
    }

    /// Wake holders the Sleep attention item no longer warns about (SLEEP-IGNORE-APP),
    /// in the order the user added them. Mutate through `DashboardModel.setWakeHolderIgnored`
    /// so the assessment updates at once.
    var ignoredWakeHolders: [WakeHolderKey] {
        didSet { UserDefaults.standard.set(Self.encodeIgnoredWakeHolders(ignoredWakeHolders), forKey: Self.ignoredWakeHoldersKey) }
    }

    /// BACKUP-AGE: warn when the newest Claude backup is older than this many hours.
    /// Mutate through `DashboardModel.setBackupStaleHours` so the assessment updates at once.
    var backupStaleHours: Int {
        didSet { UserDefaults.standard.set(backupStaleHours, forKey: Self.backupStaleHoursKey) }
    }

    /// REDESIGN-STORAGE: amber low-space line, % free. The Settings control arrives in REDESIGN-SETTINGS.
    var lowSpacePercent: Int {
        didSet { UserDefaults.standard.set(lowSpacePercent, forKey: Self.lowSpacePercentKey) }
    }

    private init() {
        Self.migrateLegacyValues(in: .standard)
        fastIntervalSeconds = Self.resolveFastInterval(raw: UserDefaults.standard.integer(forKey: Self.fastIntervalKey)) // 0 if unset
        ignoredWakeHolders = Self.decodeIgnoredWakeHolders(UserDefaults.standard.data(forKey: Self.ignoredWakeHoldersKey))
        backupStaleHours = Self.resolveBackupStaleHours(raw: UserDefaults.standard.integer(forKey: Self.backupStaleHoursKey))
        lowSpacePercent = Self.resolveLowSpacePercent(raw: UserDefaults.standard.integer(forKey: Self.lowSpacePercentKey)) // 0 if unset
    }
}
