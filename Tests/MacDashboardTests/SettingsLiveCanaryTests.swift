// Tests/MacDashboardTests/SettingsLiveCanaryTests.swift
// REDESIGN-SETTINGS opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanary
// Prints the system language and SMAppService status the Settings window depends on. Writes nothing.
import Foundation
import ServiceManagement
import Testing
@testable import MacDashboard

extension SerialTests {
    struct SettingsLiveCanaryTests {
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryLanguage() {
            let first = Locale.preferredLanguages.first ?? ""
            let resolved = LanguageChoice.resolve(.system, preferredLanguages: Locale.preferredLanguages)
            print("liveCanary preferredLanguages.first = \(first), resolved = \(resolved)")
            #expect((resolved == .ru) == first.hasPrefix("ru"), "system language resolves RU iff the first preferred language starts with ru")
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryLoginItem() {
            let raw = SMAppService.mainApp.status.rawValue
            let status = LoginItem.status()
            print("liveCanary SMAppService.mainApp.status.rawValue = \(raw), LoginItem.status() = \(status)")
            #expect((status == .enabled) == (raw == 1), "enabled <=> 1")
            #expect((status == .requiresApproval) == (raw == 2), "requiresApproval <=> 2")
        }
    }
}
