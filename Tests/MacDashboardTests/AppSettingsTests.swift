// Tests/MacDashboardTests/AppSettingsTests.swift
// Port of Checks/main.swift lines 1619-1660 (CHECKS-SWIFT-TESTING). AppSettings fast-loop polling interval persistence.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct AppSettingsTests {
        @Test func fastIntervalPersistence() async {
            // =====================================================================
            // MARK: - AppSettings (fast-loop polling interval)
            // =====================================================================

            do {
                // UserDefaults hygiene: capture the pre-existing value (if any) and restore it
                // afterwards — the Checks binary has its own defaults domain, but keep it clean.
                let savedRaw = UserDefaults.standard.object(forKey: AppSettings.fastIntervalKey)

                // 1. Fresh state: AppSettings.shared is a lazy singleton initialized ONCE (on
                // first access anywhere in the process), so removeObject here can't force a
                // re-init — we're asserting the INSTANCE's already-established value, which
                // was clamped into allowedIntervals at first-touch time.
                UserDefaults.standard.removeObject(forKey: AppSettings.fastIntervalKey)
                #expect(AppSettings.allowedIntervals.contains(AppSettings.shared.fastIntervalSeconds),
                      "AppSettings: shared.fastIntervalSeconds is a member of allowedIntervals")

                // 2. Set → didSet persists to UserDefaults.
                AppSettings.shared.fastIntervalSeconds = 5
                #expect(UserDefaults.standard.integer(forKey: AppSettings.fastIntervalKey) == 5,
                      "AppSettings: setting fastIntervalSeconds = 5 persists via didSet")

                // 3. Clamp logic: the singleton can't be re-initialized mid-process, so the
                // init-time clamp (raw defaults value → nearest-safe default of 2 when not in
                // allowedIntervals) can't be re-exercised here. Asserting the rule's contract
                // directly instead: the allowed set is exactly [2, 5, 10] as documented
                // (and as read by both the init clamp and the SettingsView picker); the
                // clamp-on-init behavior itself is enforced by code review of AppSettings.init.
                #expect(AppSettings.allowedIntervals == [2, 5, 10],
                      "AppSettings: allowedIntervals == [2, 5, 10] (init-clamp verified by code review)")

                // 4. Restore/settle.
                AppSettings.shared.fastIntervalSeconds = 2
                #expect(UserDefaults.standard.integer(forKey: AppSettings.fastIntervalKey) == 2,
                      "AppSettings: setting fastIntervalSeconds = 2 persists via didSet")

                if let savedRaw {
                    UserDefaults.standard.set(savedRaw, forKey: AppSettings.fastIntervalKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: AppSettings.fastIntervalKey)
                }
            }
        }

        @Test func rimProfilePersistence() {
            let d = UserDefaults.standard
            let saved = d.object(forKey: AppSettings.rimProfileKey)
            let savedSetting = AppSettings.shared.rimProfile
            defer {
                AppSettings.shared.rimProfile = savedSetting
                if let saved { d.set(saved, forKey: AppSettings.rimProfileKey) } else { d.removeObject(forKey: AppSettings.rimProfileKey) }
            }
            #expect(AppSettings.resolveRimProfile(raw: nil) == .medium)
            #expect(AppSettings.resolveRimProfile(raw: "1") == .narrow)
            #expect(AppSettings.resolveRimProfile(raw: "3") == .wide)
            #expect(AppSettings.resolveRimProfile(raw: "9") == .medium)
            AppSettings.shared.rimProfile = .wide
            #expect(d.string(forKey: AppSettings.rimProfileKey) == "3")
            AppSettings.shared.rimProfile = .narrow
            #expect(d.string(forKey: AppSettings.rimProfileKey) == "1")
            #expect(RimProfile.allCases.allSatisfy { RimLight.heights[$0.rawValue] != nil })
        }

        @Test func notifyEnabledPersistence() {
            let saved = AppSettings.shared.notifyEnabled
            defer { AppSettings.shared.notifyEnabled = saved }
            AppSettings.shared.notifyEnabled = [.disk]
            #expect(UserDefaults.standard.bool(forKey: NotifyCategory.disk.defaultsKey) == true)
            #expect(UserDefaults.standard.object(forKey: NotifyCategory.crashes.defaultsKey) as? Bool == false)
        }

        @Test func fastIntervalResolution() {
            for v in [2, 5, 10] {
                #expect(AppSettings.resolveFastInterval(raw: v) == v, "resolveFastInterval keeps \(v)")
            }
            for v in [0, 1, 3, 7, -1] {
                #expect(AppSettings.resolveFastInterval(raw: v) == 2, "resolveFastInterval(\(v)) == 2")
            }
        }

        @Test func legacyMigration() {
            let name = "MacDashboardTests.migration.\(ProcessInfo.processInfo.processIdentifier)"
            let d = UserDefaults(suiteName: name)!
            d.removePersistentDomain(forName: name)
            defer { d.removePersistentDomain(forName: name) }
            let key = AppSettings.fastIntervalKey
            let limitKey = AppSettings.legacyProcessLimitKey

            // (a) interval 1 + stored process limit
            d.set(1, forKey: key); d.set(15, forKey: limitKey)
            AppSettings.migrateLegacyValues(in: d)
            #expect(d.integer(forKey: key) == 2, "migration: 1 -> 2")
            #expect(d.object(forKey: limitKey) == nil, "migration: retired process-count key removed")
            AppSettings.migrateLegacyValues(in: d)
            #expect(d.integer(forKey: key) == 2, "migration idempotent: still 2")
            #expect(d.object(forKey: limitKey) == nil, "migration idempotent: still removed")

            // (b) 3 -> 2
            d.set(3, forKey: key)
            AppSettings.migrateLegacyValues(in: d)
            #expect(d.integer(forKey: key) == 2, "migration: 3 -> 2")

            // (c) 5 and 10 untouched
            for v in [5, 10] {
                d.set(v, forKey: key)
                AppSettings.migrateLegacyValues(in: d)
                #expect(d.integer(forKey: key) == v, "migration: \(v) untouched")
            }

            // (d) other values left to resolveFastInterval
            d.set(7, forKey: key)
            AppSettings.migrateLegacyValues(in: d)
            #expect(d.integer(forKey: key) == 7, "migration: 7 left stored")
            #expect(AppSettings.resolveFastInterval(raw: 7) == 2, "resolveFastInterval(7) == 2")

            // (e) nothing stored -> nothing written
            d.removeObject(forKey: key)
            AppSettings.migrateLegacyValues(in: d)
            #expect(d.object(forKey: key) == nil, "migration: nothing written when unset")

            // (f) hours -> days
            let hKey = AppSettings.legacyBackupStaleHoursKey, dKey = AppSettings.backupStaleDaysKey
            for (h, days) in [(24, 1), (48, 2), (72, 3), (168, 7)] {
                d.removeObject(forKey: dKey); d.set(h, forKey: hKey)
                AppSettings.migrateLegacyValues(in: d)
                #expect(d.integer(forKey: dKey) == days, "migration: \(h) h -> \(days) d")
                #expect(d.object(forKey: hKey) == nil, "migration: hours key removed")
                AppSettings.migrateLegacyValues(in: d)
                #expect(d.integer(forKey: dKey) == days, "migration idempotent: days stay \(days)")
            }
            // existing days key wins
            d.set(168, forKey: hKey); d.set(5, forKey: dKey)
            AppSettings.migrateLegacyValues(in: d)
            #expect(d.integer(forKey: dKey) == 5, "migration: existing days key wins")
            #expect(d.object(forKey: hKey) == nil, "migration: hours key removed when days exists")
            // nothing stored -> nothing written
            d.removeObject(forKey: dKey); d.removeObject(forKey: hKey)
            AppSettings.migrateLegacyValues(in: d)
            #expect(d.object(forKey: dKey) == nil, "migration: no days written when nothing stored")
        }

        @Test func backupStaleDaysResolve() {
            for (raw, want) in [(0, 2), (1, 1), (30, 30), (31, 2), (-1, 2)] {
                #expect(AppSettings.resolveBackupStaleDays(raw: raw) == want, "resolveBackupStaleDays(\(raw)) == \(want)")
            }
            for (h, want) in [(30, 1), (36, 2), (1000, 30)] {
                #expect(AppSettings.daysFromLegacyHours(h) == want, "daysFromLegacyHours(\(h)) == \(want)")
            }
        }

        @Test func snapshotMinutesResolve() {
            for (raw, want) in [(nil, 180), (0, 0), (1439, 1439), (1440, 180)] as [(Int?, Int)] {
                #expect(AppSettings.resolveSnapshotMinutes(raw: raw) == want, "resolveSnapshotMinutes(\(String(describing: raw))) == \(want)")
            }
        }

        @Test func appearanceResolve() {
            #expect(AppSettings.resolveAppearance(raw: nil) == .system)
            #expect(AppSettings.resolveAppearance(raw: "x") == .system)
            #expect(AppSettings.resolveAppearance(raw: "dark") == .dark)
        }

        @Test func keepImportedArchivesDefault() {
            #expect(AppSettings.shared.keepImportedArchives, "keepImportedArchives defaults to true")
        }

        @Test func iphoneAutoReadDefault() {
            #expect(AppSettings.shared.iphoneAutoRead, "iphoneAutoRead defaults to true")
        }

        @Test func archiveFolderResolve() {
            let def = URL(fileURLWithPath: "/tmp/md-default", isDirectory: true)
            #expect(AppSettings.resolveArchiveFolder(raw: nil, defaultRoot: def) == def)
            #expect(AppSettings.resolveArchiveFolder(raw: "", defaultRoot: def) == def)
            #expect(AppSettings.resolveArchiveFolder(raw: "relative/path", defaultRoot: def) == def)
            #expect(AppSettings.resolveArchiveFolder(raw: "/Users/x/Archives/", defaultRoot: def).path == "/Users/x/Archives")
        }

        @Test func lowSpacePercentResolve() async {
            #expect(AppSettings.resolveLowSpacePercent(raw: 0) == 20, "lowSpacePercent unset (0) -> 20")
            #expect(AppSettings.resolveLowSpacePercent(raw: 15) == 15, "lowSpacePercent 15 kept")
            #expect(AppSettings.resolveLowSpacePercent(raw: 10) == 10, "lowSpacePercent 10 kept")
            #expect(AppSettings.resolveLowSpacePercent(raw: 25) == 20, "lowSpacePercent 25 -> 20")
        }
    }
}
