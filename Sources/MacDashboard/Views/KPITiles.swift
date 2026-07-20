// Views/KPITiles.swift
// The five live KPI tiles (CPU, memory, swap, disk, battery) shown in the top row.

import SwiftUI
import Charts

// MARK: - KPI tiles

struct CPUTile: View {
    let model: DashboardModel

    var body: some View {
        let cpu = model.cpu
        let loadStr: String = {
            guard let l = model.load, let first = l.first else { return L.kpiLoadUnavailable }
            return L.kpiLoad(fmtNum(first, decimals: 2))
        }()
        let sub: String = {
            var s = L.kpiCpuSub(loadStr, model.ncpu)
            if let t = model.socTempC { s += " · " + L.kpiCpuSocTemp(t) }   // honest-empty: no segment when nil
            return s
        }()
        KPITileView(
            label: L.kpiCpuLabel,
            value: cpu.map { fmtNum($0.user + $0.sys, decimals: 1) } ?? "—",
            unit: "%",
            sub: sub
        ) {
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
            .frame(height: 30)
            .padding(.vertical, 2)
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
                unit: L.kpiMemUnit(fmtBytes(mem.total)),
                sub: L.kpiMemSub(fmtBytes(mem.compressor), fmtBytes(mem.purgeable)),
                meterFraction: mem.total > 0 ? Double(mem.usedBytes) / Double(mem.total) : nil,
                meterColor: SeriesPalette.s1
            )
        } else {
            KPITileView(label: L.kpiMemLabel, value: "—", unit: "")
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
                unit: L.kpiSwapUnit(fmtBytes(swap.total)),
                sub: L.kpiSwapSub(fmtBytes(swap.free)),
                meterFraction: Double(swap.used) / Double(swap.total),
                meterColor: model.assessment.swapSev.color
            )
        }
    }
}

@MainActor
struct DiskTile: View {
    let model: DashboardModel

    /// Block N7: internal (disk0) NVMe temperature from the last SMART collection
    /// (launch report / 5-min sampler / manual refresh). nil until SMART lands or
    /// when smartctl/temp is unavailable — the sub-line segment then hides.
    private var internalDiskTempC: Int? {
        guard let disk = model.report.smart?.first(where: { $0.device == "internal" }) else { return nil }
        return ThermalSensors.smartTemperatureCelsius(attrs: disk.attrs).map { Int($0.rounded()) }
    }

    var body: some View {
        if let disk = model.disk, disk.size > 0 {
            let subBase = L.kpiDiskUsedPct(Int((disk.pct * 100).rounded()))
            let sub: String = {
                var s: String
                if let dataUsed = disk.dataUsed, let sysUsed = disk.sysUsed {
                    s = L.kpiDiskUsedDetail(subBase, fmtBytes(dataUsed), fmtBytes(sysUsed))
                } else {
                    s = subBase
                }
                if let t = internalDiskTempC { s += " · " + L.kpiDiskTemp(t) }   // honest-empty when nil
                return s
            }()
            KPITileView(
                label: L.kpiDiskLabel,
                value: fmtBytes(disk.avail),
                unit: L.kpiDiskUnit(fmtBytes(disk.size)),
                sub: sub,
                meterFraction: disk.pct,
                meterColor: model.assessment.diskSev.color
            )
        } else {
            KPITileView(label: L.kpiDiskLabel, value: "—", unit: "")
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
            let sub: String? = {
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
                sub: sub,
                meterFraction: batt.maxCapacity.map { Double($0) / 100 },
                meterColor: model.assessment.battSev.color
            )
            .overlay(alignment: .topTrailing) {
                RainbowCapsuleButton(title: L.kpiBatteryDetailsButton) { showDetails = true }
                    .padding(10)
            }
            .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                BatteryDetailView(condition: model.report.battery?.condition ?? model.battery?.condition)
            }
        }
    }
}
