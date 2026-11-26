// Engine/SocSensorsModel.swift
// TEMP-SENSORS-DETAIL: what the Sensors card draws, from `SensorsState` rows. Pure (strings via L), tested by
// SocSensorsModelTests. Two lists (D11): chip parts (E, P, GPU) and other parts; an empty list is dropped.

import Foundation

enum SocSensorsModel {
    struct Row: Equatable {
        var name: String
        var valueText: String
        /// Set for a row with no value: muted ink and this hover text.
        var noValueHelp: String? = nil
    }

    static let chipKinds: Set<SensorKind> = [.eCores, .pCores, .gpu]

    /// The chip list and the other-parts list, in display order; empty lists left out (0, 1 or 2 lists).
    @MainActor static func lists(_ readings: [SensorReading]) -> [[Row]] {
        let chip = readings.filter { chipKinds.contains($0.kind) }.map(row)
        let other = readings.filter { !chipKinds.contains($0.kind) }.map(row)
        return [chip, other].filter { !$0.isEmpty }
    }

    @MainActor static func row(_ r: SensorReading) -> Row {
        if let c = r.celsius { return Row(name: name(r.kind), valueText: "\(c) °C") }
        if r.kind == .gpu { return Row(name: name(r.kind), valueText: L.socSensorIdle, noValueHelp: L.socSensorIdleHelp) }
        return Row(name: name(r.kind), valueText: "—", noValueHelp: L.socSensorNoReading)
    }

    @MainActor static func name(_ kind: SensorKind) -> String {
        switch kind {
        case .eCores: return L.socSensorECores
        case .pCores: return L.socSensorPCores
        case .gpu: return L.commonGPU
        case .battery: return L.commonBattery
        case .wireless: return L.socSensorWireless
        case .ssd: return L.socSensorSSD
        case .charger: return L.socSensorCharger
        }
    }
}
