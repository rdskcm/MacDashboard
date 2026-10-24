// Tests/MacDashboardTests/AppInfoTests.swift
// REDESIGN-SETTINGS R14 / D22: About version text.
import Testing
@testable import MacDashboard

struct AppInfoTests {
    @Test func versionText() {
        #expect(AppInfo.versionText(short: "2.3.2 Krieg", build: "2.3.2") == "2.3.2 Krieg")
        #expect(AppInfo.versionText(short: "1.4.0", build: "212") == "1.4.0 (212)")
        #expect(AppInfo.versionText(short: "1.4.0", build: "") == "1.4.0")
    }
}
