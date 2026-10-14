// Tests/MacDashboardTests/ThermalSensorsTests.swift
// Port of Checks/ThermalSensorsChecks.swift (CHECKS-SWIFT-TESTING).
// Block N7: pure-logic checks for ThermalSensors (classification, filtering,
// max-aggregation, smartctl temperature extraction). Real file (not a symlink) —
// main.swift owns the single top-level-statements slot, so this exposes a plain
// function it calls (see README.md).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct ThermalSensorsTests {
        @Test func thermalSensors() async {
            typealias R = ThermalSensors.Reading

            #expect(ThermalSensors.isSOCDieSensor("PMU tdie1"), "ThermalSensors: PMU tdie1 is SOC die")
            #expect(ThermalSensors.isSOCDieSensor("PMU2 tdie8"), "ThermalSensors: PMU2 tdie8 is SOC die")
            #expect(!ThermalSensors.isSOCDieSensor("PMU tdev4"), "ThermalSensors: PMU tdev4 excluded (package sensor)")
            #expect(!ThermalSensors.isSOCDieSensor("PMU tcal"), "ThermalSensors: PMU tcal excluded (calibration)")
            #expect(!ThermalSensors.isSOCDieSensor("gas gauge battery"), "ThermalSensors: battery sensor excluded")
            #expect(!ThermalSensors.isSOCDieSensor("NAND CH0 temp"), "ThermalSensors: NAND sensor excluded")
            #expect(!ThermalSensors.isSOCDieSensor(""), "ThermalSensors: empty name excluded")

            #expect(ThermalSensors.isValidReading(38.7), "ThermalSensors: 38.7 valid")
            #expect(!ThermalSensors.isValidReading(Double.nan), "ThermalSensors: NaN invalid")
            #expect(!ThermalSensors.isValidReading(-1.47), "ThermalSensors: -1.47 (unpopulated channel) invalid")
            #expect(!ThermalSensors.isValidReading(0), "ThermalSensors: 0 invalid")
            #expect(!ThermalSensors.isValidReading(.infinity), "ThermalSensors: +inf invalid")

            #expect(ThermalSensors.socTemperature(from: []) == nil, "socTemperature: empty ⇒ nil")
            #expect(ThermalSensors.socTemperature(from: [
                R(name: "PMU tdie1", value: .nan),
                R(name: "PMU2 tdie3", value: -1.43),
            ]) == nil, "socTemperature: all-invalid tdie readings ⇒ nil")
            #expect(ThermalSensors.socTemperature(from: [
                R(name: "gas gauge battery", value: 30.8),
                R(name: "NAND CH0 temp", value: 32.0),
                R(name: "PMU tdev5", value: 90.0),          // valid value, wrong class — must not leak in
            ]) == nil, "socTemperature: no tdie sensors ⇒ nil even when others are valid/hot")

            let mixed: [R] = [
                R(name: "gas gauge battery", value: 30.8),
                R(name: "PMU tdie1", value: 38.7),
                R(name: "PMU tdie4", value: 40.9),
                R(name: "PMU2 tdie7", value: 40.3),
                R(name: "PMU2 tdie3", value: -1.43),        // invalid channel
                R(name: "PMU tdev4", value: 51.0),          // hotter but wrong class
                R(name: "PMU tcal", value: 51.85),
                R(name: "NAND CH0 temp", value: 32.0),
                R(name: "PMU tdie8", value: .nan),          // dead reading
            ]
            #expect(ThermalSensors.socTemperature(from: mixed) == 40.9,
                  "socTemperature: mixed fixture ⇒ max of valid tdie (40.9)")

            #expect(ThermalSensors.smartTemperatureCelsius(attrs: [("Temperature", "32 Celsius")]) == 32,
                  "smartTemperatureCelsius: \"32 Celsius\" ⇒ 32")
            #expect(ThermalSensors.smartTemperatureCelsius(attrs: [("Critical Warning", "0x00")]) == nil,
                  "smartTemperatureCelsius: no Temperature attr ⇒ nil")
            #expect(ThermalSensors.smartTemperatureCelsius(attrs: []) == nil,
                  "smartTemperatureCelsius: empty attrs ⇒ nil")
            #expect(ThermalSensors.smartTemperatureCelsius(attrs: [("Temperature", "N/A")]) == nil,
                  "smartTemperatureCelsius: unparseable value ⇒ nil")

            let disk0Fixture = Data(#"{"nvme_smart_health_information_log":{"critical_warning":0,"temperature":32,"available_spare":100,"percentage_used":1}}"#.utf8)
            #expect(ThermalSensors.smartTemperatureCelsius(attrs: Parsers.smartctlAttrs(json: disk0Fixture)) == 32,
                  "smartTemperatureCelsius: smartctl -A disk0 fixture end-to-end ⇒ 32")
        }
    }
}
