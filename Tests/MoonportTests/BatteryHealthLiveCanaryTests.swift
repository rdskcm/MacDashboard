// Tests/MoonportTests/BatteryHealthLiveCanaryTests.swift
// BATTERY-HEALTH-UNIFY opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanaryBatteryHealth
// Reads this Mac's battery through ioreg (BatteryInspector.read) and system_profiler (Parsers.batteryPowerProfile) and
// prints Apple's figure next to the raw ratio — the two numbers the Monitoring switch chooses between (D2). Read-only.
import Foundation
import Testing
@testable import Moonport

extension SerialTests {
    struct BatteryHealthLiveCanaryTests {
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryBatteryHealth() async {
            guard case .detail(let d) = await BatteryInspector.read() else { print("liveCanary no battery on this Mac"); return }
            print("liveCanary ioreg maxCapacityMAh = \(String(describing: d.maxCapacityMAh)), designCapacityMAh = \(String(describing: d.designCapacityMAh)), healthPercent (raw) = \(String(describing: d.healthPercent)), rawHealthOneDecimal = \(String(describing: d.rawHealthOneDecimal))")
            if let raw1 = d.rawHealthOneDecimal, let raw = d.healthPercent {
                #expect(abs(raw1 - Double(raw)) <= 0.5, "the one-decimal ratio rounds to healthPercent")
            }
            if let m = d.maxCapacityMAh, let des = d.designCapacityMAh, des > 0 {
                #expect(d.healthPercent == Int((Double(m) / Double(des) * 100).rounded()), "raw ratio = round(max / design)")
                #expect(m <= des + des / 10, "max capacity is at most 10 % above design")
            }
            let sp = await CommandRunner.run("/usr/sbin/system_profiler", ["SPPowerDataType"], timeout: 30)
            let parsed = Parsers.batteryPowerProfile(sp.stdout)
            print("liveCanary system_profiler Maximum Capacity = \(String(describing: parsed.maxCapacity)), Condition = \(String(describing: parsed.condition)), Cycle Count = \(String(describing: parsed.cycles))")
            if parsed.maxCapacity == nil { print("liveCanary system_profiler head:\n" + sp.stdout.split(separator: "\n").prefix(40).joined(separator: "\n")) }
            #expect(parsed.maxCapacity != nil, "system_profiler reports Maximum Capacity on this Mac (the figure Home shows)")
            if let apple = parsed.maxCapacity, let raw = d.healthPercent {
                print("liveCanary apple − raw = \(apple - raw) points; classify(apple) = \(BatteryHealth.classify(healthPercent: apple, condition: parsed.condition)), classify(raw) = \(BatteryHealth.classify(healthPercent: raw, condition: parsed.condition))")
                #expect((1...100).contains(apple) && (1...110).contains(raw), "both percentages are plausible")
                #expect(abs(apple - raw) <= 10, "Apple's figure and the raw ratio are within 10 points of each other")
            }
            #expect(BatteryHealth.macShownPercent(apple: parsed.maxCapacity, raw: d.rawHealthOneDecimal, prefersRaw: false)?.percent == parsed.maxCapacity.map(Double.init))
            #expect(BatteryHealth.macShownPercent(apple: parsed.maxCapacity, raw: d.rawHealthOneDecimal, prefersRaw: true)?.percent == d.rawHealthOneDecimal)
        }
    }
}
