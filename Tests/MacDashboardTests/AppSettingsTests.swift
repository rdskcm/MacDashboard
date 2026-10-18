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
        }
    }
}
