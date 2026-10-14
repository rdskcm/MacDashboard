// Tests/MacDashboardTests/SmartToolsAvailabilityTests.swift
// Port of Checks/SmartToolsAvailabilityChecks.swift (CHECKS-SWIFT-TESTING).
// Block N8: pure-logic coverage for ReportCollector.smartToolsAvailability's 4-way
// input mapping (smartctl present/absent x brew present/absent).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct SmartToolsAvailabilityTests {
        @Test func smartToolsAvailability() async {
            #expect(ReportCollector.smartToolsAvailability(smartctl: "/opt/homebrew/bin/smartctl",
                                                          brew: "/opt/homebrew/bin/brew") == .installed,
                  "smartToolsAvailability: smartctl present, brew present ⇒ .installed")
            #expect(ReportCollector.smartToolsAvailability(smartctl: "/opt/homebrew/bin/smartctl",
                                                          brew: nil) == .installed,
                  "smartToolsAvailability: smartctl present, brew absent ⇒ .installed (smartctl wins)")
            #expect(ReportCollector.smartToolsAvailability(smartctl: nil,
                                                          brew: "/opt/homebrew/bin/brew") == .installable,
                  "smartToolsAvailability: smartctl absent, brew present ⇒ .installable")
            #expect(ReportCollector.smartToolsAvailability(smartctl: nil, brew: nil) == .needsHomebrew,
                  "smartToolsAvailability: smartctl absent, brew absent ⇒ .needsHomebrew")
        }
    }
}
