// Views/KPITiles.swift
// The five live KPI tiles (CPU, memory, swap, disk, battery) shown in the top row.

import SwiftUI

// MARK: - CPU sparkline (custom-drawn, spec §5.3 — NOT the `Charts` framework)

/// Zone model (design spec §1, DO:415–420): thresholds on CPU load fraction
/// (0...1). Distinct from the process-list gauge ramp (`cpuGaugeColor` in
/// ProcessCards.swift) — that's a different, 5-stop spec'd system; this is
/// the CPU tile's own zone banding, reused here for the sparkline's "current
/// zone color" (the line's right-hand end / area-fill tint).
private func cpuZoneColorA(forLoadFraction f: Double) -> Color {
    switch f {
    case ...0.35: return Color(hex: 0x3F8FE0)   // calm
    case ...0.70: return Color(hex: 0x2BBD9A)   // work
    case ...0.88: return Color(hex: 0xE0A72E)   // high
    default: return Color(hex: 0xE0603A)        // crit
    }
}

/// `grad-cool-a` (design spec §1: dark `#4A9AE8` / light `#2F86DD`) — not a
/// `Theme.swift` token yet (out of this fix pass's file scope), so it's
/// inlined here the same way every other one-off literal color in this
/// codebase is handled (e.g. `RainbowBorder`'s rainbow stops in SharedUI.swift).
private let cpuSparklineGradCoolA = Color(light: Color(hex: 0x2F86DD), dark: Color(hex: 0x4A9AE8))

/// The CPU tile's Visual-band sparkline. Custom `Path`/`GeometryReader` draw
/// (matching how this app already hand-draws `DSDisclosureBars` etc.) rather
/// than a `Charts` `LineMark`, so the area fill / baseline / dual gradients
/// below are all achievable — `Charts` has no equivalent knobs for these.
///
/// Coordinate model (spec §5.3, SVG-literal): a 100×30 viewBox, non-uniform
/// scale (X and Y independently stretched to the view's actual size) — never
/// a single `.scaleEffect`, which would distort line/stroke widths anisotropically.
/// Because points are placed by computing their own scaled (x, y) rather than
/// via a view-level transform, stroke widths below are inherently "non-scaling":
/// there is no ambient scale factor for SwiftUI to apply to them.
private struct CPUSparkline: View {
    /// Oldest → newest, each 0...100 (CPU load percent, same units as `model.cpuHistory`).
    let samples: [Double]
    let zoneColor: Color

    private let vbWidth: CGFloat = 100
    private let vbHeight: CGFloat = 30

    /// y = 29.2 − value% · 0.284 (spec DO:560–562), in the 30-tall viewBox space.
    private func vbY(for value: Double) -> CGFloat {
        29.2 - CGFloat(value) * 0.284
    }

    private func scaledPoints(in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        let n = samples.count
        let scaleX = size.width / vbWidth
        let scaleY = size.height / vbHeight
        return samples.enumerated().map { i, v in
            let vbX = n > 1 ? (CGFloat(i) / CGFloat(n - 1)) * vbWidth : vbWidth
            return CGPoint(x: vbX * scaleX, y: vbY(for: v) * scaleY)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pts = scaledPoints(in: size)

            ZStack {
                // Area fill: polyline down to the bottom of the drawing area,
                // vertical gradient zoneColor 46% (top) -> 6% (bottom).
                if pts.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: pts[0].x, y: size.height))
                        for p in pts { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [zoneColor.opacity(0.46), zoneColor.opacity(0.06)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // Baseline: y=29.5 (viewBox space), 1 pt DS.lineStrong, non-scaling width.
                Path { path in
                    let by = 29.5 * (size.height / vbHeight)
                    path.move(to: CGPoint(x: 0, y: by))
                    path.addLine(to: CGPoint(x: size.width, y: by))
                }
                .stroke(DS.lineStrong, style: StrokeStyle(lineWidth: 1))

                // Polyline: 1.6 pt, round join/cap, non-scaling; horizontal
                // gradient grad-cool-a (left) -> current CPU zone color (right).
                if pts.count > 1 {
                    Path { path in
                        path.move(to: pts[0])
                        for p in pts.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [cpuSparklineGradCoolA, zoneColor]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }
}

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
            // Custom-drawn gradient polyline (spec §5.3) — 20 samples, same
            // `model.cpuHistory` source the old `Charts` LineMark read from.
            let samples = model.cpuHistory.suffix(20).map(\.1)
            let currentLoad = cpu.map { $0.user + $0.sys } ?? (samples.last ?? 0)
            CPUSparkline(samples: samples, zoneColor: cpuZoneColorA(forLoadFraction: currentLoad / 100))
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
                    // FIX-1: memory is a live tile — .8 s cubic width animation (spec §5.3).
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
                    // FIX-3: swap's bar fraction is NOT used/total — it's used/2048
                    // (MB, fixed constant) ÷ 0.6, capped at 1 (spec DO:895, 900).
                    // `swap.used` is bytes (see fmtBytes(swap.used) above / Parsers.swift),
                    // so convert to MB before dividing by the 2048 MB constant.
                    // FIX-1: swap is a live tile — .8 s cubic width animation (spec §5.3).
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
                RainbowCapsuleButton(title: L.kpiBatteryDetailsButton, size: .compact) { showDetails = true }
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
