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
                // directly instead: the allowed set is exactly [1, 2, 3, 5, 10] as documented
                // (and as read by both the init clamp and the SettingsView picker); the
                // clamp-on-init behavior itself is enforced by code review of AppSettings.init.
                #expect(AppSettings.allowedIntervals == [1, 2, 3, 5, 10],
                      "AppSettings: allowedIntervals == [1, 2, 3, 5, 10] (init-clamp verified by code review)")

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
    }
}
