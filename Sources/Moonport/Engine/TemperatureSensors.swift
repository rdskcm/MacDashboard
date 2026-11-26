// Engine/TemperatureSensors.swift
// TEMP-SENSORS-DETAIL: pure logic for SMC temperatures — the validity filter, key classification, row aggregation and
// the chip-temperature source order. Foundation-only, covered by TemperatureSensorsTests; the IOKit reads live in
// SMCReader. Sources (inputs/TEMP-SENSORS-DETAIL-findings.md): filter 10-150 °C as macmon (row 13); TB0T battery,
// TW0P Wi-Fi/BT module, TH0x NAND, TCHP charge regulator from the Linux and OpenBSD drivers (row 15); cluster readings
// over Te*/Tp*/Tg*, never TG* (battery gas-gauge values, rows 18-20) and never per-core labels (rows 8, 12, 21).
// Max, not average (spec D1): here TCMz equals max(Tp*) under load, and a max ignores extra cooler keys.

import Foundation

/// One row of the Sensors card. The case order is the display order.
enum SensorKind: Int, CaseIterable, Sendable {
    case eCores, pCores, gpu, battery, wireless, ssd, charger
}

/// One row value: the hottest valid key of the row, in whole degrees Celsius. nil = the Mac has keys for this row
/// but none is valid in this pass (an idle GPU reports 0).
struct SensorReading: Equatable, Sendable {
    var kind: SensorKind
    var celsius: Int?
}

/// What the Sensors card shows. `.rows` is never empty: no row at all is `.unavailable`. Rows whose values are all nil
/// are still `.rows`.
enum SensorsState: Equatable, Sendable {
    case notYet
    case rows([SensorReading])
    case unavailable

    static func from(_ readings: [SensorReading]) -> SensorsState { readings.isEmpty ? .unavailable : .rows(readings) }
}

enum TemperatureSensors {
    /// The chip temperature's SMC sources, in order (user decision 2026-11-26): CPU die max, then CPU die average.
    static let chipKeys = ["TCMz", "TCMb"]
    static let minValid = 10.0
    static let maxValid = 150.0

    /// True iff a value is a plausible temperature: finite, above 10 and at most 150 °C. Drops the 0 and -3.6
    /// placeholders and the `ioft` sentinel (about 2.8e14) seen on the reference Mac.
    static func isValid(_ value: Double) -> Bool {
        value.isFinite && value > minValid && value <= maxValid
    }

    /// The row a key belongs to; nil for every other key. Case-sensitive: `Tg*` is GPU, `TG*` is not a row.
    static func kind(forKey key: String) -> SensorKind? {
        switch key {
        case "TB0T": return .battery
        case "TW0P": return .wireless
        case "TH0x": return .ssd
        case "TCHP": return .charger
        default: break
        }
        guard key.utf8.count == 4 else { return nil }
        if key.hasPrefix("Te") { return .eCores }
        if key.hasPrefix("Tp") { return .pCores }
        if key.hasPrefix("Tg") { return .gpu }
        return nil
    }

    /// One reading per row that has at least one key in `values` (valid or not), in display order. The value is the
    /// max of the valid values, rounded; nil when none is valid.
    static func readings(from values: [String: Double]) -> [SensorReading] {
        var present: Set<SensorKind> = []
        var hottest: [SensorKind: Double] = [:]
        for (key, value) in values {
            guard let kind = kind(forKey: key) else { continue }
            present.insert(kind)
            guard isValid(value) else { continue }
            hottest[kind] = max(hottest[kind] ?? -.infinity, value)
        }
        return SensorKind.allCases.compactMap { kind in
            present.contains(kind) ? SensorReading(kind: kind, celsius: hottest[kind].map { Int($0.rounded()) }) : nil
        }
    }

    /// How long a row keeps its last valid value while the sensor gives none.
    static let holdSeconds: TimeInterval = 30

    /// The hold step: a valid reading refreshes `last` and passes through; a nil reading younger than or exactly
    /// `holdSeconds` old in `last` gets the held value; otherwise it stays nil.
    static func holding(_ current: [SensorReading], last: [SensorKind: (celsius: Int, at: Date)], now: Date)
        -> (readings: [SensorReading], last: [SensorKind: (celsius: Int, at: Date)]) {
        var last = last
        let out = current.map { r -> SensorReading in
            if let c = r.celsius {
                last[r.kind] = (c, now)
                return r
            }
            if let held = last[r.kind], now.timeIntervalSince(held.at) <= holdSeconds {
                return SensorReading(kind: r.kind, celsius: held.celsius)
            }
            return r
        }
        return (out, last)
    }

    /// The chip temperature: the first valid of `chipKeys` in `values`, else `fallback()` when valid, else nil.
    /// `fallback` (the ~50 ms HID pass) is called only when no SMC key gives a valid value.
    static func chipTemperature(_ values: [String: Double], fallback: () -> Double?) -> Double? {
        for key in chipKeys {
            if let value = values[key], isValid(value) { return value }
        }
        guard let value = fallback(), isValid(value) else { return nil }
        return value
    }
}
