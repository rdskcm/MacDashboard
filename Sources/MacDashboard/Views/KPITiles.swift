// Views/KPITiles.swift
// The five live KPI tiles (CPU, memory, swap, disk, battery) shown in the top row.

import SwiftUI
import Charts

// MARK: - KPI tiles

struct CPUTile: View {
    let model: DashboardModel

    /// All three load averages (1/5/15) — the core count is NOT repeated here,
    /// it already lives in the header's load chip (see `HeaderChipsView`).
    private var footer: String {
        guard let l = model.load, l.count >= 3 else { return L.kpiLoadUnavailable }
        return L.kpiCpuLoadFooter(fmtNum(l[0], decimals: 2), fmtNum(l[1], decimals: 2), fmtNum(l[2], decimals: 2))
    }

    var body: some View {
        let cpu = model.cpu
        KPITileView(
            label: L.kpiCpuLabel,
            value: cpu.map { fmtNum($0.user + $0.sys, decimals: 1) } ?? "—",
            unit: "%",
            footer: footer
        ) {
            // Satellite: SOC temperature capsule — honest-empty (no capsule) when nil.
            if let t = model.socTempC {
                KPITempBadge(celsius: t, warn: 85, crit: 95)
            }
        } visual: {
            Chart {
                ForEach(Array(model.cpuHistory.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value(L.kpiCpuChartTimeLabel, point.0), y: .value("CPU", point.1))
                        .interpolationMethod(.monotone)
                }
            }
            .foregroundStyle(SeriesPalette.s1)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .frame(height: 46)
        }
    }
}

struct MemoryTile: View {
    let model: DashboardModel

    var body: some View {
        if let mem = model.mem {
            KPITileView(
                label: L.kpiMemLabel,
                value: fmtBytes(mem.usedBytes),
                outOf: L.kpiMemUnit(fmtBytes(mem.total)),
                footer: L.kpiMemSub(fmtBytes(mem.compressor), fmtBytes(mem.purgeable)),
                // Explicit `visual:` label (not trailing-closure sugar): with no
                // satellite, a bare trailing closure is ambiguous between the
                // Satellite==EmptyView and Visual==EmptyView convenience inits.
                visual: {
                    MeterBar(fraction: mem.total > 0 ? Double(mem.usedBytes) / Double(mem.total) : 0, color: SeriesPalette.s1)
                }
            )
        } else {
            KPITileView(label: L.kpiMemLabel, value: "—")
        }
    }
}

struct SwapTile: View {
    let model: DashboardModel

    var body: some View {
        if let swap = model.swap, swap.total > 0 {
            KPITileView(
                label: L.kpiSwapLabel,
                value: fmtBytes(swap.used),
                outOf: L.kpiSwapUnit(fmtBytes(swap.total)),
                footer: L.kpiSwapSub(fmtBytes(swap.free)),
                // Explicit `visual:` label — see MemoryTile's comment above.
                visual: {
                    // TRAP: never `assessment.swapSev.color` (that's the legacy v1
                    // palette, banned from every v2 view) — go through the v2 tone
                    // table instead (crit/serious -> hot, warn/info -> amber, good -> green).
                    MeterBar(fraction: Double(swap.used) / Double(swap.total), color: tone(for: model.assessment.swapSev))
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

    private func footer(for disk: DiskInfo) -> String {
        let base = L.kpiDiskUsedPct(Int((disk.pct * 100).rounded()))
        let detail: String
        if let dataUsed = disk.dataUsed, let sysUsed = disk.sysUsed {
            detail = L.kpiDiskUsedDetail(base, fmtBytes(dataUsed), fmtBytes(sysUsed))
        } else {
            detail = base
        }
        return L.kpiDiskFreeLabel + " · " + detail
    }

    var body: some View {
        if let disk = model.disk, disk.size > 0 {
            KPITileView(
                label: L.kpiDiskLabel,
                value: fmtCapacity(disk.avail),
                outOf: L.kpiDiskUnit(fmtCapacity(disk.size)),
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
    private var battery: BatteryInfo? {
        guard let live = model.battery ?? model.report.battery else { return nil }
        // For static fields (maxCapacity, cycles, condition), prefer report; for dynamic fields, use live
        let maxCapacity = model.report.battery?.maxCapacity ?? model.battery?.maxCapacity
        let cycles = model.report.battery?.cycles ?? model.battery?.cycles
        let condition = model.report.battery?.condition ?? model.battery?.condition

        return BatteryInfo(
            source: live.source,
            charge: live.charge,
            state: live.state,
            cycles: cycles,
            condition: condition,
            maxCapacity: maxCapacity
        )
    }

    var body: some View {
        if let batt = battery {
            let footer: String? = {
                var bits: [String] = []
                if let cycles = batt.cycles { bits.append(L.kpiBatteryCycles(cycles)) }
                if let cond = batt.condition { bits.append(L.kpiBatteryCondition(cond)) }
                if let charge = batt.charge {
                    var cur = L.kpiBatteryChargeNow(charge)
                    if let state = batt.state { cur += ", \(state)" }
                    if let source = batt.source { cur += " (\(source))" }
                    bits.append(cur)
                }
                return bits.isEmpty ? nil : bits.joined(separator: " · ")
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
                RainbowCapsuleButton(title: L.kpiBatteryDetailsButton) { showDetails = true }
                    .accessibilityLabel(L.kpiBatteryDetailsButton)
            } visual: {
                // TRAP: never `assessment.battSev.color` — go through the v2 tone table.
                MeterBar(fraction: batt.maxCapacity.map { Double($0) / 100 } ?? 0, color: tone(for: model.assessment.battSev))
            }
            .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                BatteryDetailView(condition: model.report.battery?.condition ?? model.battery?.condition)
            }
        }
    }
}
