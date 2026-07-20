// Engine/ThermalSensors.swift
// Block N7: pure classification/aggregation logic for the SOC-temperature tile.
// The actual private-IOKit read lives in Engine/ThermalHIDReader.swift (app-only,
// NOT symlinked into Checks); this file is symlinked into MacDashboardChecks and
// must stay Foundation-only.
//
// Hardware ground truth (spike, base M3 MacBook Air): no per-core CPU sensors
// exist on this chip class — only generic "PMU tdie1-8"/"PMU2 tdie1-8" die-
// junction sensors (hottest, most volatile) plus "PMU tdev*" package sensors
// (3 of 16 channels report invalid ~-1.5 °C), "gas gauge battery", "NAND CH0
// temp", "PMU tcal", and one unnamed NaN service. Hence: honest label is "SOC",
// source set is tdie-only, aggregation is max() (signals thermal pressure better
// than an average diluted across 16 near-identical readings).

import Foundation

enum ThermalSensors {

    /// One HID temperature sensor sample (name from the service's "Product"
    /// property, value in °C).
    struct Reading: Equatable {
        var name: String
        var value: Double
    }

    /// True iff `name` is a SOC die-junction sensor: "PMU tdie3", "PMU2 tdie8", …
    /// Excludes "PMU tdev*" (package), "PMU tcal" (calibration constant),
    /// "gas gauge battery", "NAND CH0 temp", and anything else.
    static func isSOCDieSensor(_ name: String) -> Bool {
        name.hasPrefix("PMU") && name.contains("tdie")
    }

    /// True iff a reading is physically plausible: finite and strictly positive.
    /// Filters the NaN of unnamed/dead services and the consistently-invalid
    /// negative (~-1.2…-1.5 °C) unpopulated channels seen on this SKU.
    static func isValidReading(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    /// max() across valid SOC die sensors; nil when none survive filtering
    /// (Intel Mac, private-API failure, all channels invalid) — honest-empty.
    static func socTemperature(from readings: [Reading]) -> Double? {
        readings.filter { isSOCDieSensor($0.name) && isValidReading($0.value) }
                .map(\.value)
                .max()
    }

    /// Extracts °C from smartctl attrs already parsed by Parsers.smartctlAttrs:
    /// ("Temperature", "32 Celsius") -> 32.0. First whitespace-separated token of
    /// the value must parse as a finite Double; otherwise nil (honest-empty).
    static func smartTemperatureCelsius(attrs: [(String, String)]) -> Double? {
        guard let raw = attrs.first(where: { $0.0 == "Temperature" })?.1 else { return nil }
        let token = raw.split(separator: " ").first.map(String.init) ?? raw
        guard let v = Double(token), v.isFinite else { return nil }
        return v
    }
}
