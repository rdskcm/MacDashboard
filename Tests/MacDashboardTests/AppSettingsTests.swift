// Tests/MacDashboardTests/AppSettingsTests.swift
// AppSettings persistence over isolated UserDefaults suites (ARCH-SETTINGS-PATH); never the app's standard defaults.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct AppSettingsTests {
        @Test func fastIntervalPersistence() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            #expect(AppSettings(defaults: d).fastIntervalSeconds == 2, "empty suite -> default interval 2")
            // The init clamp: a stored value outside allowedIntervals resolves to 2.
            d.set(7, forKey: AppSettings.fastIntervalKey)
            #expect(AppSettings(defaults: d).fastIntervalSeconds == 2, "stored 7 is clamped to 2 by init")
            let s = AppSettings(defaults: d)
            s.fastIntervalSeconds = 5
            #expect(d.integer(forKey: AppSettings.fastIntervalKey) == 5, "setting fastIntervalSeconds = 5 persists via didSet")
            #expect(AppSettings(defaults: d).fastIntervalSeconds == 5, "a second instance reads the stored 5")
            #expect(AppSettings.allowedIntervals == [2, 5, 10], "allowedIntervals == [2, 5, 10]")
        }

        @Test func rimProfilePersistence() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            #expect(AppSettings.resolveRimProfile(raw: nil) == .medium)
            #expect(AppSettings.resolveRimProfile(raw: "1") == .narrow)
            #expect(AppSettings.resolveRimProfile(raw: "3") == .wide)
            #expect(AppSettings.resolveRimProfile(raw: "9") == .medium)
            let s = AppSettings(defaults: d)
            s.rimProfile = .wide
            #expect(d.string(forKey: AppSettings.rimProfileKey) == "3")
            #expect(AppSettings(defaults: d).rimProfile == .wide)
            s.rimProfile = .narrow
            #expect(d.string(forKey: AppSettings.rimProfileKey) == "1")
            #expect(RimProfile.allCases.allSatisfy { RimLight.heights[$0.rawValue] != nil })
        }

        @Test func notifyEnabledPersistence() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let s = AppSettings(defaults: d)
            s.notifyEnabled = [.disk]
            #expect(d.bool(forKey: NotifyCategory.disk.defaultsKey) == true)
            #expect(d.object(forKey: NotifyCategory.crashes.defaultsKey) as? Bool == false)
            #expect(AppSettings(defaults: d).notifyEnabled == [.disk])
        }

        @Test func assessmentSettingsPersistAndReload() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let a = AppSettings(defaults: d)
            let k = WakeHolderKey(owner: "caffeinate", requester: "Terminal")
            a.lowSpacePercent = 15
            a.backupStaleDays = 7
            a.claudeLogPath = "/tmp/md-test/claude-backup.log"
            a.setWakeHolderIgnored(k, ignored: true, now: Date(timeIntervalSince1970: 1_000_000))
            let b = AppSettings(defaults: d)
            #expect(b.assessmentSettings == a.assessmentSettings, "a second instance reloads all four assessment settings")
            a.claudeLogPath = ""
            #expect(a.claudeLogPath == nil, "empty log path is stored as nil")
            #expect(d.object(forKey: AppSettings.claudeLogPathKey) == nil, "empty log path removes the key")
            a.backupStaleDays = 0
            a.backupStaleDays = 31
            a.lowSpacePercent = 25
            #expect(a.backupStaleDays == 7 && a.lowSpacePercent == 15, "out-of-range writes are ignored")
            #expect(d.integer(forKey: AppSettings.backupStaleDaysKey) == 7)
            #expect(d.integer(forKey: AppSettings.lowSpacePercentKey) == 15)
        }

        @MainActor @Test func assessmentHookFiresOncePerChange() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            final class Box { var calls: [AssessmentSettings] = [] }
            let box = Box()
            let s = AppSettings(defaults: d)
            s.onAssessmentSettingsChange = { box.calls.append($0) }
            let k = WakeHolderKey(owner: "caffeinate", requester: "Terminal")
            let writes: [(String, () -> Void)] = [
                ("lowSpacePercent", { s.lowSpacePercent = 10 }),
                ("backupStaleDays", { s.backupStaleDays = 5 }),
                ("claudeLogPath", { s.claudeLogPath = "/tmp/x.log" }),
                ("wakeHolder", { s.setWakeHolderIgnored(k, ignored: true) }),
            ]
            for (label, write) in writes {
                let before = s.assessmentSettings
                let n = box.calls.count
                write()
                #expect(box.calls.count == n + 1, "\(label): exactly one hook call")
                #expect(box.calls.last == before, "\(label): the hook receives the state before the write")
            }
            let noOps: [(String, () -> Void)] = [
                ("same lowSpacePercent", { s.lowSpacePercent = 10 }),
                ("same backupStaleDays", { s.backupStaleDays = 5 }),
                ("same claudeLogPath", { s.claudeLogPath = "/tmp/x.log" }),
                ("lowSpacePercent 25", { s.lowSpacePercent = 25 }),
                ("backupStaleDays 31", { s.backupStaleDays = 31 }),
                ("wake holder again", { s.setWakeHolderIgnored(k, ignored: true) }),
                ("fastIntervalSeconds", { s.fastIntervalSeconds = 5 }),
            ]
            for (label, write) in noOps {
                let n = box.calls.count
                write()
                #expect(box.calls.count == n, "\(label): no hook call")
            }
        }

        @Test func assessmentSettingsFieldsAreCovered() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let labels = Mirror(reflecting: AppSettings(defaults: d).assessmentSettings).children.compactMap(\.label)
            #expect(labels == ["ignoredWakeHolderEntries", "backupStaleDays", "lowSpacePercent", "claudeLogPath"],
                    "a new AssessmentSettings field needs a persistence line, a load line, and cases in assessmentSettingsPersistAndReload, assessmentHookFiresOncePerChange and SettingsPathTests")
        }

        /// P3: the test process must not share the app's defaults domain.
        @Test func testProcessIsNotTheAppDomain() {
            let id = Bundle.main.bundleIdentifier
            print("P3: test process bundle id = \(id ?? "nil")")
            #expect(id != "com.rdskcm.mac-dashboard")
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
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            #expect(AppSettings(defaults: d).keepImportedArchives, "keepImportedArchives defaults to true")
        }

        @Test func iphoneAutoReadDefault() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            #expect(AppSettings(defaults: d).iphoneAutoRead, "iphoneAutoRead defaults to true")
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
