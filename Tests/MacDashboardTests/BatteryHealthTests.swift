// Tests/MacDashboardTests/BatteryHealthTests.swift
// BATTERY-HEALTH-UNIFY: the one battery-health rule (Engine/BatteryHealth.swift).
import Testing
@testable import MacDashboard

struct BatteryHealthTests {
    @Test func threshold() {
        #expect(BatteryHealth.wornBelowPercent == 80)
    }

    @Test func intBoundaries() {
        for p in [81, 80, 100, 120] { #expect(BatteryHealth.classify(healthPercent: p, condition: "Normal") == .normal, "\(p)") }
        for p in [79, 70, 69, 0] { #expect(BatteryHealth.classify(healthPercent: p, condition: "Normal") == .worn, "\(p)") }
    }

    @Test func conditions() {
        #expect(BatteryHealth.classify(healthPercent: 79, condition: nil) == .worn)
        #expect(BatteryHealth.classify(healthPercent: 79, condition: "") == .worn)
        #expect(BatteryHealth.classify(healthPercent: 79, condition: " Normal\n") == .worn)
        #expect(BatteryHealth.classify(healthPercent: 95, condition: "Service Recommended") == .service)
        #expect(BatteryHealth.classify(healthPercent: nil, condition: "Replace Now") == .service)
        #expect(BatteryHealth.classify(healthPercent: 50, condition: "Check Battery") == .service)
        #expect(BatteryHealth.classify(healthPercent: 90, condition: "normal") == .service)
        #expect(BatteryHealth.classify(healthPercent: nil, condition: nil) == .unknown)
        #expect(BatteryHealth.classify(healthPercent: nil, condition: "") == .unknown)
        #expect(BatteryHealth.classify(healthPercent: nil, condition: "Normal") == .unknown)
    }

    @Test func precise() {
        for p in [79.9, 79.99] { #expect(BatteryHealth.classify(precisePercent: p, condition: nil) == .worn, "\(p)") }
        for p in [80.0, 80.04] { #expect(BatteryHealth.classify(precisePercent: p, condition: nil) == .normal, "\(p)") }
        #expect(BatteryHealth.classify(precisePercent: .nan, condition: nil) == .unknown)
        #expect(BatteryHealth.classify(precisePercent: .infinity, condition: nil) == .unknown)
        #expect(BatteryHealth.classify(precisePercent: nil, condition: nil) == .unknown)
    }

    @Test func overloadsAgree() {
        for p in -1...120 {
            for c in [nil, "Normal", "Replace Soon"] as [String?] {
                #expect(BatteryHealth.classify(healthPercent: p, condition: c) == BatteryHealth.classify(precisePercent: Double(p), condition: c), "\(p) \(String(describing: c))")
            }
        }
    }

    @Test func serviceCondition() {
        for c in [nil, "", "  ", "Normal", " Normal "] as [String?] { #expect(!BatteryHealth.isServiceCondition(c), "\(String(describing: c))") }
        for c in ["Service Recommended", "normal"] { #expect(BatteryHealth.isServiceCondition(c), "\(c)") }
    }

    @Test func macShownPercent() {
        #expect(BatteryHealth.macShownPercent(apple: 82, raw: 78, prefersRaw: false) == 82)
        #expect(BatteryHealth.macShownPercent(apple: 82, raw: 78, prefersRaw: true) == 78)
        #expect(BatteryHealth.macShownPercent(apple: 82, raw: nil, prefersRaw: true) == 82)
        #expect(BatteryHealth.macShownPercent(apple: nil, raw: 78, prefersRaw: false) == nil)
        #expect(BatteryHealth.macShownPercent(apple: nil, raw: 78, prefersRaw: true) == 78)
        #expect(BatteryHealth.macShownPercent(apple: nil, raw: nil, prefersRaw: true) == nil)
    }
}
