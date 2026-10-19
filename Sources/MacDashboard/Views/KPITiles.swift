// Views/KPITiles.swift
// The five live KPI tiles (CPU, memory, swap, disk, battery) shown in the top row.

import SwiftUI

// MARK: - KPI tiles

struct MemoryTile: View {
    let model: DashboardModel

    var body: some View {
        if let mem = model.mem {
            let usedParts = fmtBytesParts(mem.usedBytes)
            KPITileView(
                label: L.kpiMemLabel,
                value: usedParts.value,
                unit: usedParts.unit,
                unitStyle: .prominent,
                outOf: L.kpiMemUnit(tight(fmtBytesParts(mem.total))),
                footer: L.kpiMemSub(fmtBytes(mem.compressor), fmtBytes(mem.purgeable)),
                // Explicit `visual:` label (not trailing-closure sugar): with no
                // satellite, a bare trailing closure is ambiguous between the
                // Satellite==EmptyView and Visual==EmptyView convenience inits.
                visual: {
                    // FIX-1: memory is a live tile — 0.45 s cubic width animation (spec §5.3).
                    MeterBar(fraction: mem.total > 0 ? Double(mem.usedBytes) / Double(mem.total) : 0, color: SeriesPalette.s1, animated: true)
                }
            )
        } else {
            KPITileView(label: L.kpiMemLabel, value: "—")
        }
    }
}

struct SwapTile: View {
    let model: DashboardModel

    static func isVisible(_ model: DashboardModel) -> Bool { if let s = model.swap { return s.total > 0 }; return false }

    var body: some View {
        if let swap = model.swap, swap.total > 0 {
            let usedParts = fmtBytesParts(swap.used)
            KPITileView(
                label: L.kpiSwapLabel,
                value: usedParts.value,
                unit: usedParts.unit,
                unitStyle: .prominent,
                outOf: L.kpiSwapUnit(tight(fmtBytesParts(swap.total))),
                footer: L.kpiSwapSub(fmtBytes(swap.free)),
                // Explicit `visual:` label — see MemoryTile's comment above.
                visual: {
                    // TRAP: never `assessment.swapSev.color` (that's the legacy v1
                    // palette, banned from every v2 view) — go through the v2 tone
                    // table instead (crit/serious -> hot, warn/info -> amber, good -> green).
                    // FIX-3: swap's bar fraction is NOT used/total — it's used/2048
                    // (MB, fixed constant) ÷ 0.6, capped at 1 (spec DO:895, 900).
                    // `swap.used` is bytes (see fmtBytes(swap.used) above / Parsers.swift),
                    // so convert to MB before dividing by the 2048 MB constant.
                    // FIX-1: swap is a live tile — 0.45 s cubic width animation (spec §5.3).
                    let swapUsedMB = Double(swap.used) / 1024.0 / 1024.0
                    let swapFraction = min(1.0, (swapUsedMB / 2048.0) / 0.6)
                    MeterBar(fraction: swapFraction, color: tone(for: model.assessment.swapSev), animated: true)
                }
            )
        }
    }
}

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
