// Engine/AppSettings.swift
// Non-language app settings (interval, wake-holder ignore list, hidden crash reports, backup-stale days, low-space %, notify categories, appearance, orbs,
// keep-archives, iPhone auto-read, archive folder, snapshot time, claude log path). Foundation + Observation only — covered by Tests/MacDashboardTests.
// `init(defaults:)` is injectable; the four assessment inputs live in `AssessmentSettings` (ARCH-SETTINGS-PATH).
import Foundation
import Observation

enum AppAppearance: String, CaseIterable { case system, light, dark }

/// RIM-GLOW-OPTICS: edge-light height. Raw values are the `RimLight.heights` keys (narrow 40 / medium 70 / wide 110 pt).
enum RimProfile: String, CaseIterable { case narrow = "1", medium = "2", wide = "3" }

/// ARCH-SETTINGS-PATH: every setting `Assess.assess` reads, stored as ONE value in `AppSettings` so one `didSet`
/// persists it and tells the owning model to re-assess, however it was written (binding, view action, code).
/// A setting that feeds the assessment is added HERE (a field, its key, its persistence line in `didSet`, its
/// load line in `init(defaults:)`, a case in SettingsPathTests) — never as a separate stored property.
/// EngineBoundaryTests and AppSettingsTests.assessmentSettingsFieldsAreCovered enforce it.
struct AssessmentSettings: Equatable {
    var ignoredWakeHolderEntries: [IgnoredWakeHolder]
    var backupStaleDays: Int
    var lowSpacePercent: Int
    /// nil = the default log; never an empty string.
    var claudeLogPath: String?

    var ignoredWakeHolders: [WakeHolderKey] { ignoredWakeHolderEntries.map(\.key) }
    var backupStaleHours: Int { backupStaleDays * 24 }
}

/// User-tunable settings backed by UserDefaults. Mirrors L10nStore's pattern.
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: .standard)
    /// The store every `didSet` writes to: `.standard` for `shared`, an isolated suite in tests.
    private let defaults: UserDefaults
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
    static let rimProfileKey = "rimProfile"
    static func resolveRimProfile(raw: String?) -> RimProfile { raw.flatMap(RimProfile.init(rawValue:)) ?? .medium }
    static let keepImportedArchivesKey = "keepImportedArchives"
    /// REDESIGN-IPHONE: read battery and crash logs on attach (true) or identify the phone only (false).
    static let iphoneAutoReadKey = "iphoneAutoRead"
    /// REDESIGN-IPHONE: folder for kept sysdiagnose archives; absent or empty = `IPhoneStore.defaultArchiveRoot()`.
    static let iphoneArchiveFolderKey = "iphoneArchiveFolder"
    /// Pure resolution: nil, empty or a non-absolute path → `defaultRoot`; otherwise the stored path as a directory URL.
    static func resolveArchiveFolder(raw: String?, defaultRoot: URL) -> URL {
        guard let raw, !raw.isEmpty, raw.hasPrefix("/") else { return defaultRoot }
        return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
    }

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

    /// Sleep interval of AppModel's fast task (native CPU/RAM/disk/battery
    /// gauges). Read by the loop on every iteration, so a change applies on the
    /// next tick without restarting the task.
    var fastIntervalSeconds: Int {
        didSet { defaults.set(fastIntervalSeconds, forKey: Self.fastIntervalKey) }
    }

    /// ARCH-SETTINGS-PATH: the four assessment inputs. Written only through the forwarders below (or
    /// `setWakeHolderIgnored`), so a whole-struct write cannot skip their validation.
    private(set) var assessmentSettings: AssessmentSettings {
        didSet {
            let new = assessmentSettings
            guard new != oldValue else { return }
            if new.ignoredWakeHolderEntries != oldValue.ignoredWakeHolderEntries {
                defaults.set(Self.encodeIgnoredWakeHolders(new.ignoredWakeHolderEntries), forKey: Self.ignoredWakeHoldersKey)
            }
            if new.backupStaleDays != oldValue.backupStaleDays { defaults.set(new.backupStaleDays, forKey: Self.backupStaleDaysKey) }
            if new.lowSpacePercent != oldValue.lowSpacePercent { defaults.set(new.lowSpacePercent, forKey: Self.lowSpacePercentKey) }
            if new.claudeLogPath != oldValue.claudeLogPath {
                if let p = new.claudeLogPath { defaults.set(p, forKey: Self.claudeLogPathKey) }
                else { defaults.removeObject(forKey: Self.claudeLogPathKey) }
            }
            if let hook = onAssessmentSettingsChange { MainActor.assumeIsolated { hook(oldValue) } }
        }
    }

    /// Called synchronously, on the main actor, after any change of `assessmentSettings`, with the OLD value.
    /// One slot: `AppModel.init` installs it (the app has one model); a later model on the same instance
    /// replaces it. Writing an assessment setting off the main thread while a hook is installed traps.
    @ObservationIgnored var onAssessmentSettingsChange: (@MainActor (AssessmentSettings) -> Void)?

    /// Wake holders the Sleep attention item no longer warns about (SLEEP-IGNORE-APP), in the order the user
    /// added them, each with the date it was added (nil for legacy entries).
    var ignoredWakeHolderEntries: [IgnoredWakeHolder] {
        get { assessmentSettings.ignoredWakeHolderEntries }
        set { assessmentSettings.ignoredWakeHolderEntries = newValue }
    }
    /// Read-only keys of the entries, for the assessment and Home.
    var ignoredWakeHolders: [WakeHolderKey] { assessmentSettings.ignoredWakeHolders }

    /// Adds (`ignored: true`, dated `now`) or removes a holder; a no-op when it is already in that state.
    func setWakeHolderIgnored(_ key: WakeHolderKey, ignored: Bool, now: Date = Date()) {
        var list = ignoredWakeHolderEntries
        if ignored {
            guard !list.contains(where: { $0.key == key }) else { return }
            list.append(IgnoredWakeHolder(key: key, since: now))
        } else {
            guard list.contains(where: { $0.key == key }) else { return }
            list.removeAll { $0.key == key }
        }
        ignoredWakeHolderEntries = list
    }

    /// BACKUP-AGE: warn when the newest Claude backup is older than this many days. Values outside
    /// `backupStaleDaysRange` are ignored.
    var backupStaleDays: Int {
        get { assessmentSettings.backupStaleDays }
        set { if Self.backupStaleDaysRange.contains(newValue) { assessmentSettings.backupStaleDays = newValue } }
    }
    /// Read-only bridge for the hour-based consumers (assessment, Backups page model).
    var backupStaleHours: Int { assessmentSettings.backupStaleHours }

    /// nil = the default `~/Library/Logs/claude-backup.log`; an empty string is stored as nil.
    var claudeLogPath: String? {
        get { assessmentSettings.claudeLogPath }
        set { assessmentSettings.claudeLogPath = (newValue?.isEmpty ?? true) ? nil : newValue }
    }

    /// REDESIGN-STORAGE: amber low-space line, % free. Values outside `allowedLowSpacePercents` are ignored.
    var lowSpacePercent: Int {
        get { assessmentSettings.lowSpacePercent }
        set { if Self.allowedLowSpacePercents.contains(newValue) { assessmentSettings.lowSpacePercent = newValue } }
    }

    /// CRASH-REPORT-DISMISS: crash report files hidden on the Security page. Mutate through
    /// `CrashReportsController.hide(_:)` / `unhide(_:)` so the list and the assessment update.
    var hiddenCrashReports: [HiddenCrashReport] {
        didSet { defaults.set(CrashDismiss.encode(hiddenCrashReports), forKey: Self.hiddenCrashReportsKey) }
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    var orbsEnabled: Bool {
        didSet { defaults.set(orbsEnabled, forKey: Self.orbsEnabledKey) }
    }
    var rimProfile: RimProfile {
        didSet { defaults.set(rimProfile.rawValue, forKey: Self.rimProfileKey) }
    }
    /// REDESIGN-IPHONE: default of the import choice sheet (parse and keep when true).
    var keepImportedArchives: Bool {
        didSet { defaults.set(keepImportedArchives, forKey: Self.keepImportedArchivesKey) }
    }
    var iphoneAutoRead: Bool {
        didSet { defaults.set(iphoneAutoRead, forKey: Self.iphoneAutoReadKey) }
    }
    /// nil = the default archive folder; an empty string is stored as nil (same contract as `claudeLogPath`).
    var iphoneArchiveFolder: String? {
        didSet {
            if let p = iphoneArchiveFolder, !p.isEmpty { defaults.set(p, forKey: Self.iphoneArchiveFolderKey) }
            else { defaults.removeObject(forKey: Self.iphoneArchiveFolderKey); if iphoneArchiveFolder == "" { iphoneArchiveFolder = nil } }
        }
    }
    var snapshotMinutes: Int {
        didSet { defaults.set(snapshotMinutes, forKey: Self.snapshotMinutesKey) }
    }
    var lastSnapshotAt: Date? {
        didSet {
            if let d = lastSnapshotAt { defaults.set(d, forKey: Self.lastSnapshotAtKey) }
            else { defaults.removeObject(forKey: Self.lastSnapshotAtKey) }
        }
    }

    /// REDESIGN-NOTIFY: categories whose attention kinds may post a macOS notification (read by the edge detector at every commit).
    var notifyEnabled: Set<NotifyCategory> {
        didSet { for c in NotifyCategory.allCases { defaults.set(notifyEnabled.contains(c), forKey: c.defaultsKey) } }
    }

    /// `shared` passes `.standard`; tests pass an isolated suite (TestSupport `makeIsolatedDefaults`).
    init(defaults: UserDefaults) {
        self.defaults = defaults
        Self.migrateLegacyValues(in: defaults)
        let d = defaults
        fastIntervalSeconds = Self.resolveFastInterval(raw: d.integer(forKey: Self.fastIntervalKey)) // 0 if unset
        hiddenCrashReports = CrashDismiss.decode(d.data(forKey: Self.hiddenCrashReportsKey))
        let storedPath = d.string(forKey: Self.claudeLogPathKey)
        assessmentSettings = AssessmentSettings(
            ignoredWakeHolderEntries: Self.decodeIgnoredWakeHolders(d.data(forKey: Self.ignoredWakeHoldersKey)),
            backupStaleDays: Self.resolveBackupStaleDays(raw: d.integer(forKey: Self.backupStaleDaysKey)),
            lowSpacePercent: Self.resolveLowSpacePercent(raw: d.integer(forKey: Self.lowSpacePercentKey)), // 0 if unset
            claudeLogPath: (storedPath?.isEmpty ?? true) ? nil : storedPath)
        appearance = Self.resolveAppearance(raw: d.string(forKey: Self.appearanceKey))
        orbsEnabled = d.object(forKey: Self.orbsEnabledKey) as? Bool ?? true
        rimProfile = Self.resolveRimProfile(raw: d.string(forKey: Self.rimProfileKey))
        keepImportedArchives = d.object(forKey: Self.keepImportedArchivesKey) as? Bool ?? true
        iphoneAutoRead = d.object(forKey: Self.iphoneAutoReadKey) as? Bool ?? true
        let storedFolder = d.string(forKey: Self.iphoneArchiveFolderKey)
        iphoneArchiveFolder = (storedFolder?.isEmpty ?? true) ? nil : storedFolder
        snapshotMinutes = Self.resolveSnapshotMinutes(raw: d.object(forKey: Self.snapshotMinutesKey) as? Int)
        lastSnapshotAt = d.object(forKey: Self.lastSnapshotAtKey) as? Date
        notifyEnabled = Self.resolveNotifyEnabled(in: d)
    }
}
