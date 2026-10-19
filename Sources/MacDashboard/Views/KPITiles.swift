// Views/KPITiles.swift
// The remaining live KPI tiles (disk, battery).

import SwiftUI

// MARK: - KPI tiles

@MainActor
struct DiskTile: View {
    let model: DashboardModel

    /// Block N7: internal (disk0) NVMe temperature from the last SMART collection
    /// (launch report / 5-min sampler / manual refresh). nil until SMART lands or
    /// when smartctl/temp is unavailable — the satellite capsule then hides.
    private var internalDiskTempC: Int? {
        guard let disk = model.report.smart?.first(where: { $0.device == "internal" }) else { return nil }
        return ThermalSensors.smartTemperatureCelsius(attrs: disk.attrs).map { Int($0.rounded()) }
    }

    /// V2-DISK-TILE-LABEL: used-side detail only. The «свободно»/"free" word that used
    /// to lead this string now lives in the tile's header label (`L.kpiDiskLabel`),
    /// next to the free-space value it actually describes.
    private func footer(for disk: DiskInfo) -> String {
        let base = L.kpiDiskUsedPct(Int((disk.pct * 100).rounded()))
        let withDetail: String
        if let dataUsed = disk.dataUsed, let sysUsed = disk.sysUsed {
            withDetail = L.kpiDiskUsedDetail(base, fmtBytes(dataUsed), fmtBytes(sysUsed))
        } else {
            withDetail = base
        }
        guard let purgeable = disk.purgeable else { return withDetail }
        return L.kpiDiskPurgeableDetail(withDetail, fmtCapacity(purgeable))
    }

    var body: some View {
        if let disk = model.disk, disk.size > 0 {
            let availParts = fmtCapacityParts(disk.avail)
            KPITileView(
                label: L.kpiDiskLabel,
                value: availParts.value,
                unit: availParts.unit,
                unitStyle: .prominent,
                outOf: L.kpiDiskUnit(tight(fmtCapacityParts(disk.size))),
                footer: footer(for: disk)
            ) {
                // Satellite: internal NVMe temperature capsule — honest-empty when nil.
                if let t = internalDiskTempC {
                    KPITempBadge(celsius: t, warn: 58, crit: 68)
                }
            } visual: {
                // TRAP: never `assessment.diskSev.color` — go through the v2 tone table.
                MeterBar(fraction: disk.pct, color: tone(for: model.assessment.diskSev))
            }
        } else {
            KPITileView(label: L.kpiDiskLabel, value: "—")
        }
    }
}

@MainActor
struct BatteryTile: View {
    let model: DashboardModel
    @State private var showDetails = false

    static func isVisible(_ model: DashboardModel) -> Bool { (model.battery ?? model.report.battery) != nil }

    private var battery: BatteryInfo? {
        BatteryInfo.merged(live: model.battery, report: model.report.battery)
    }

    var body: some View {
        if let batt = battery {
            let footer: String? = {
                guard let charge = batt.charge else { return nil }
                var cur = L.kpiBatteryChargeNow(charge)
                if let state = batt.state { cur += ", \(state)" }
                return cur
            }()
            KPITileView(
                label: L.kpiBatteryLabel,
                value: batt.maxCapacity.map { "\($0)" } ?? "—",
                unit: "%",
                footer: footer
            ) {
                // Satellite: the "Детали" pill — the rainbow hover ring lives in
                // the header itself now (it belongs to the tile header per the
                // Overview recipe), not floated over the tile as a v1 overlay.
                RainbowCapsuleButton(title: L.kpiBatteryDetailsButton, size: .compact) { showDetails.toggle() }
                    .accessibilityLabel(L.kpiBatteryDetailsButton)
                    .accessibilityIdentifier("battery-details")
                    .popover(isPresented: $showDetails, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        BatteryDetailView(condition: model.report.battery?.condition ?? model.battery?.condition)
                    }
            } visual: {
                // TRAP: never `assessment.battSev.color` — go through the v2 tone table.
                MeterBar(fraction: batt.maxCapacity.map { Double($0) / 100 } ?? 0, color: tone(for: model.assessment.battSev))
            }
        }
    }
}
