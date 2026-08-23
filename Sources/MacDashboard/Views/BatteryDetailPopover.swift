// Views/BatteryDetailPopover.swift
// Content of the "Details" popover on the battery KPI tile: a self-refreshing
// (every 3s, cancelled automatically on popover dismissal) deep dive into
// AppleSmartBattery, sourced from BatteryInspector.collect().

import SwiftUI

/// Deterministic 24-hour footer timestamp (the locale-aware .standard style
/// renders AM/PM under en_US).
private let batteryTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm:ss"
    return f
}()

/// Popover-local palette per Spec §6.9; never reference `BP` outside this file
/// and never reference `DS` inside it.
enum BP {
    static let ink = Color(light: Color(hex: 0x12161B), dark: Color(hex: 0xE7EAF0))
    static let inkSoft = Color(light: Color(hex: 0x2E3742), dark: Color(hex: 0xC3CAD4))
    static let muted = Color(light: Color(hex: 0x4A5460), dark: Color(hex: 0x8B94A1))
    static let line = Color(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.10))
    static let tile = Color(light: Color.white.opacity(0.55), dark: Color.white.opacity(0.055))
    static let tileLine = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))
    static let track = Color(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.10))
    static let green = Color(light: Color(hex: 0x1C7A34), dark: Color(hex: 0x30D158))
    static let yellow = Color(light: Color(hex: 0x9C4600), dark: Color(hex: 0xFFD60A))
    static let orange = Color(light: Color(hex: 0xB32E00), dark: Color(hex: 0xFF9F0A))
    static let red = Color(light: Color(hex: 0xB3000F), dark: Color(hex: 0xFF453A))
    static let bolt = Color(light: Color(hex: 0xFFCC00), dark: Color(hex: 0xFFD60A))
    static let flowIn = Color(light: Color(hex: 0x1C7A34), dark: Color(hex: 0x30D158))
    static let flowOut = Color(light: Color(hex: 0xB3000F), dark: Color(hex: 0xFF453A))
}

/// Colour for the two "Now" flow tiles (Power, Current), from the SIGN of the reading
/// they actually show — never from `d.isCharging`, which painted idle-on-AC (`0 mA` /
/// `0.00 W`) and the `—` placeholder in the alarm red `BP.flowOut` (V2-HONEST-READINGS).
/// Charging is green, discharging is amber (normal operation, not an alarm), an idle
/// zero gets the default text tone, and "no reading" gets the muted tone.
private func batteryFlowColor(_ value: Double?) -> Color {
    guard let value else { return BP.muted }
    if value > 0 { return BP.flowIn }
    if value < 0 { return BP.orange }
    return BP.ink
}

struct BatteryDetailView: View {
    let condition: String?          // from system_profiler report, e.g. "Normal" — may be nil
    @State private var detail: BatteryDetail?
    @State private var updatedAt: Date? = nil
    @State private var lifetimeExpanded: Bool
    @State private var contentHeight: CGFloat? = nil
    /// Fed by `.onGeometryChange` on the health-bar track Capsule (never a
    /// GeometryReader inside the animated subtree — see capacitySection).
    @State private var healthTrackWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Preview/test harness seam: when `previewDetail` is supplied, the refresh
    /// loop never starts and `detail` is seeded synchronously.
    private let skipRefreshLoop: Bool

    init(condition: String?, startLifetimeExpanded: Bool = true, previewDetail: BatteryDetail? = nil) {
        self.condition = condition
        _lifetimeExpanded = State(initialValue: startLifetimeExpanded)
        _detail = State(initialValue: previewDetail)
        self.skipRefreshLoop = previewDetail != nil
    }

    /// Cap for the popover height; content taller than this scrolls (measured via
    /// PopoverContentHeightKey), shorter content sizes the popover exactly.
    private let maxPopoverHeight: CGFloat = 640

    var body: some View {
        Group {
            if let d = detail {
                ScrollView {
                    loadedContent(d)
                        .padding(16)
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: PopoverContentHeightKey.self, value: g.size.height)
                            }
                        )
                }
                .onPreferenceChange(PopoverContentHeightKey.self) { contentHeight = $0 }
                .frame(width: 380, height: min(contentHeight ?? maxPopoverHeight, maxPopoverHeight))
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(L.batteryLoadingText)
                        .font(.system(size: 13))
                        .foregroundStyle(BP.muted)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .padding(16)
                .frame(width: 380)
            }
        }
        .task {
            if skipRefreshLoop { return }
            while !Task.isCancelled {
                // Keep the last known-good reading on a transient collect() failure
                // instead of flipping the popover back to the loading state.
                let fetched = await Task.detached { BatteryInspector.collect() }.value
                if let d = fetched {
                    if detail != d { detail = d }
                    updatedAt = Date()
                }
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    break
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(BP.line).frame(height: 1)
    }

    @ViewBuilder
    private func loadedContent(_ d: BatteryDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(d)
            divider
            nowSection(d)
            divider
            capacitySection(d)
            divider
            if d.externalConnected {
                chargingSection(d)
            }
            lifetimeSection(d)
            if d.serial != nil || d.manufacturerCode != nil || d.mfgYear != nil {
                divider
                passportSection(d)
            }
            if let updatedAt {
                Text(L.batteryUpdatedAt(batteryTimeFormatter.string(from: updatedAt)))
                    .font(.system(size: 11))
                    .foregroundStyle(BP.muted)
            }
        }
    }

    // MARK: - Header

    private func fmtMinutes(_ m: Int) -> String {
        let h = m / 60
        let mm = m % 60
        if m < 60 {
            return L.batteryMinutes(mm)
        }
        return L.batteryHoursMinutes(h, mm)
    }

    private func statusLine(_ d: BatteryDetail) -> String {
        if !d.externalConnected {
            var s = L.batteryStatusOnBattery
            if let m = d.timeToEmptyMin { s += L.batteryStatusRemaining(fmtMinutes(m)) }
            return s
        }
        if d.isCharging {
            var s = L.batteryStatusCharging
            if let m = d.timeToFullMin { s += L.batteryStatusUntilFull(fmtMinutes(m)) }
            return s
        }
        if d.fullyCharged {
            return L.batteryStatusACFull
        }
        return L.batteryStatusACNotCharging
    }

    private func header(_ d: BatteryDetail) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                BatteryGlyph(percent: d.percent ?? 0)
                if d.isCharging {
                    BoltShape()
                        .fill(BP.bolt)
                        .frame(width: 12, height: 16)
                        .modifier(PulsingBoltModifier())
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: "\(d.percent ?? 0)")
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .kerning(-0.85)
                        .foregroundStyle(BP.ink)
                    Text(L.batteryPercentSign)
                        .font(.system(size: 19))
                        .foregroundStyle(BP.muted)
                }
            }
            Text(statusLine(d))
                .font(.system(size: 13))
                .foregroundStyle(BP.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - "Now" section

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(BP.muted)
    }

    private func nowSection(_ d: BatteryDetail) -> some View {
        let amperage = d.amperageMA

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L.batterySectionNow)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                StatTile(
                    label: L.batteryLabelPower,
                    value: d.powerW.map { L.batteryWatts(fmtNum($0, decimals: 2)) } ?? "—",
                    valueColor: batteryFlowColor(d.powerW)
                )
                StatTile(
                    label: L.batteryLabelCurrent,
                    value: amperage.map { L.batteryMA($0) } ?? "—",
                    valueColor: batteryFlowColor(amperage.map(Double.init))
                )
                StatTile(
                    label: L.batteryLabelVoltage,
                    value: d.voltageMV.map { L.batteryVolts(fmtNum(Double($0) / 1000, decimals: 2)) } ?? "—"
                )
                StatTile(
                    label: L.batteryLabelTemperature,
                    value: d.temperatureC.map { L.batteryCelsius(fmtNum($0, decimals: 1)) } ?? "—"
                )
            }
            if !d.cellVoltagesMV.isEmpty {
                Text(L.batteryCellsLine(d.cellVoltagesMV.map { fmtNum(Double($0) / 1000, decimals: 3) }.joined(separator: " · ")))
                    .font(.system(size: 12))
                    .foregroundStyle(BP.muted)
            }
            if let lpm = d.lowPowerMode {
                BPRow(
                    label: L.batteryDetailLowPower,
                    value: lpm ? L.energyValueOn : L.energyValueOff,
                    valueColor: BP.muted
                )
            }
        }
    }

    // MARK: - "Capacity and health" section

    private func capacitySection(_ d: BatteryDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L.batterySectionCapacity)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.batteryCapMax).font(.system(size: 11)).foregroundStyle(BP.muted)
                    Text(verbatim: d.maxCapacityMAh.map { L.batteryMAh($0) } ?? "—")
                        .font(.system(size: 13.5))
                        .monospacedDigit()
                        .foregroundStyle(BP.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L.batteryCapDesign).font(.system(size: 11)).foregroundStyle(BP.muted)
                    Text(verbatim: d.designCapacityMAh.map { L.batteryMAh($0) } ?? "—")
                        .font(.system(size: 13.5))
                        .monospacedDigit()
                        .foregroundStyle(BP.ink)
                }
            }
            if let maxCap = d.maxCapacityMAh, let designCap = d.designCapacityMAh, designCap > 0 {
                let fraction = min(1, Double(maxCap) / Double(designCap))
                let color: Color = {
                    guard let health = d.healthPercent else { return BP.ink }
                    if health >= 80 { return BP.green }
                    if health >= 60 { return BP.yellow }
                    return BP.red
                }()
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BP.track)
                        .frame(height: 6)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { newWidth in
                            healthTrackWidth = newWidth
                        }
                    Capsule()
                        .fill(color)
                        .frame(width: healthTrackWidth * CGFloat(fraction), height: 6)
                        .animation(reduceMotion ? nil : .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.6), value: fraction)
                }
            }
            VStack(spacing: 6) {
                if let health = d.healthPercent {
                    BPRow(label: L.batteryCapHealth, value: L.batteryPercent(health))
                }
                if let cycles = d.cycleCount {
                    let value = d.designCycleCount.map { L.batteryCyclesOf(cycles, $0) } ?? "\(cycles)"
                    BPRow(label: L.batteryCapCycles, value: value)
                }
                if let current = d.currentCapacityMAh {
                    BPRow(label: L.batteryCapCurrentCharge, value: L.batteryMAh(current))
                }
                if let condition {
                    BPRow(label: L.batteryCapCondition, value: condition)
                }
            }
        }
    }

    // MARK: - "Charging" section

    private func chargingSection(_ d: BatteryDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L.batterySectionCharging)
            VStack(spacing: 6) {
                if let adapter = d.adapter {
                    BPRow(label: L.batteryChargeAdapter, value: adapterLine(adapter), gap: 14, baseline: true)
                    if let pdLine = protocolLine(adapter) {
                        BPRow(label: L.batteryChargeProtocol, value: pdLine, gap: 14, baseline: true)
                    }
                    if !adapter.pdProfiles.isEmpty {
                        BPRow(label: L.batteryChargeProfiles, value: profilesLine(adapter), gap: 14, baseline: true)
                    }
                }
                if let mA = d.charger?.chargingCurrentMA, mA > 0 {
                    BPRow(label: L.batteryChargeCurrentLabel, value: L.batteryMA(mA), gap: 14, baseline: true)
                }
                BPRow(
                    label: L.batteryChargeStatus,
                    value: statusValue(d),
                    valueColor: d.isCharging ? BP.green : BP.ink,
                    gap: 14,
                    baseline: true
                )
            }
        }
    }

    private func adapterLine(_ adapter: BatteryAdapterInfo) -> String {
        let joined = [adapter.name, adapter.manufacturer].compactMap { $0 }.joined(separator: ", ")
        var line: String
        if joined.isEmpty {
            line = L.batteryAdapterUsbC(adapter.watts ?? 0)
        } else if adapter.name != nil {
            line = joined + L.batteryAdapterWattsSuffix(adapter.watts ?? 0)
        } else {
            line = joined
        }
        if adapter.isWireless {
            line += L.batteryAdapterWireless
        }
        return line
    }

    private func protocolLine(_ adapter: BatteryAdapterInfo) -> String? {
        guard let selected = adapter.selectedProfileIndex,
              let profile = adapter.pdProfiles.first(where: { $0.index == selected })
        else { return nil }
        let v = Double(profile.maxVoltageMV) / 1000
        let vStr = v.truncatingRemainder(dividingBy: 1) == 0 ? fmtNum(v, decimals: 0) : fmtNum(v, decimals: 1)
        let aStr = fmtNum(Double(profile.maxCurrentMA) / 1000, decimals: 2)
        return L.batteryUsbPdLine(vStr, aStr)
    }

    private func profilesLine(_ adapter: BatteryAdapterInfo) -> String {
        adapter.pdProfiles.map { profile in
            let vStr = fmtNum(Double(profile.maxVoltageMV) / 1000, decimals: 0)
            let s = L.batteryVolts(vStr)
            return profile.index == adapter.selectedProfileIndex ? "[\(s)]" : s
        }.joined(separator: " · ")
    }

    private func statusValue(_ d: BatteryDetail) -> String {
        if d.isCharging { return L.batteryStatusCharging }
        if d.fullyCharged { return L.batteryStatusFullyCharged }
        var s = L.batteryStatusNotCharging
        if let reason = d.charger?.notChargingReason, reason != 0 {
            s += L.batteryNotChargingCode(reason)
        }
        return s
    }

    // MARK: - "All-time" section

    private func lifetimeSection(_ d: BatteryDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LifetimeToggle(expanded: $lifetimeExpanded, reduceMotion: reduceMotion)
            if lifetimeExpanded {
                VStack(spacing: 6) {
                    if let lifetime = d.lifetime {
                        if let minT = lifetime.minTemperatureC, let avgT = lifetime.avgTemperatureC, let maxT = lifetime.maxTemperatureC {
                            BPRow(label: L.batteryLifetimeTempLabel, value: L.batteryLifetimeTempValue(minT, fmtNum(avgT, decimals: 1), maxT), gap: 14)
                        }
                        if let maxCharge = lifetime.maxChargeCurrentMA {
                            BPRow(label: L.batteryLifetimeMaxCharge, value: L.batteryMA(maxCharge), gap: 14)
                        }
                        if let maxDischarge = lifetime.maxDischargeCurrentMA {
                            BPRow(label: L.batteryLifetimeMaxDischarge, value: L.batteryMA(maxDischarge), gap: 14)
                        }
                        if let minV = lifetime.minPackVoltageMV, let maxV = lifetime.maxPackVoltageMV {
                            BPRow(
                                label: L.batteryLifetimeVoltage,
                                value: L.batteryLifetimeVoltageRange(fmtNum(Double(minV) / 1000, decimals: 2), fmtNum(Double(maxV) / 1000, decimals: 2)),
                                gap: 14
                            )
                        }
                        if let hours = lifetime.totalOperatingTimeH {
                            BPRow(label: L.batteryLifetimeOperatingTime, value: L.batteryOperatingHours(hours), gap: 14)
                        }
                    }
                }
                .transition(.dsDisclosure(reduceMotion: reduceMotion))
            }
        }
    }

    // MARK: - "Battery ID" section

    private static let manufacturerNames: [String: String] = [
        "ATL": "Amperex (ATL)",
        "SMP": "Simplo (SMP)",
        "LGC": "LG Chem (LGC)",
        "SDI": "Samsung SDI"
    ]

    @ViewBuilder
    private func passportSection(_ d: BatteryDetail) -> some View {
        if d.serial != nil || d.manufacturerCode != nil || d.mfgYear != nil {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(L.batteryDetailPassportSection)
                VStack(spacing: 6) {
                    if let code = d.manufacturerCode {
                        BPRow(label: L.batteryDetailManufacturer, value: Self.manufacturerNames[code] ?? code, gap: 14)
                    }
                    if let serial = d.serial {
                        BPRow(label: L.batteryDetailSerial, value: serial, gap: 14)
                    }
                    if let year = d.mfgYear, let week = d.mfgWeek, let code = d.mfgCode {
                        BPRow(label: L.batteryDetailMfgDate, value: mfgDateValue(year: year, week: week, code: code), gap: 14)
                    }
                }
            }
        }
    }

    private func mfgDateValue(year: Int, week: Int, code: String) -> String {
        var comps = DateComponents()
        comps.weekOfYear = week
        comps.yearForWeekOfYear = year
        comps.weekday = 2 // Monday
        let cal = Calendar(identifier: .iso8601)
        let df = DateFormatter()
        df.locale = Locale(identifier: L10nStore.shared.language == .en ? "en_US" : "ru_RU")
        df.dateFormat = "LLLL yyyy"    // standalone month: «март 2022» / "March 2022"
        let month = cal.date(from: comps).map { df.string(from: $0) }
        return L.batteryDetailMfgDateValue(month ?? code, code)
    }
}

// MARK: - Shared label/value row

private struct BPRow: View {
    let label: String
    let value: String
    var valueColor: Color = BP.ink
    var gap: CGFloat = 10
    var baseline: Bool = false

    var body: some View {
        HStack(alignment: baseline ? .firstTextBaseline : .center, spacing: gap) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(BP.muted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Battery glyph (header)

/// Hand-drawn battery outline + fill + terminal nub (replaces the SF Symbol
/// battery glyphs, which don't offer fine-grained fill-percentage control).
private struct BatteryGlyph: View {
    let percent: Int

    private var fillWidth: CGFloat {
        switch percent {
        case 90...: return 21.4
        case 60..<90: return 16
        case 35..<60: return 10.7
        case 10..<35: return 5.4
        default: return 1.4
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4.4)
                .strokeBorder(BP.ink.opacity(0.55), lineWidth: 1.3)
                .frame(width: 25.2, height: 13.7)
                .offset(x: 0.65, y: 0.65)
            RoundedRectangle(cornerRadius: 2.6)
                .fill(BP.ink)
                .frame(width: fillWidth, height: 10)
                .offset(x: 2.5, y: 2.5)
            Canvas { context, _ in
                var nub = Path()
                let start = CGPoint(x: 28.1, y: 5.3)
                nub.move(to: start)
                nub.addCurve(
                    to: CGPoint(x: start.x, y: start.y + 4.4),
                    control1: CGPoint(x: start.x + 1.5, y: start.y + 0.55),
                    control2: CGPoint(x: start.x + 1.5, y: start.y + 3.85)
                )
                nub.closeSubpath()
                context.fill(nub, with: .color(BP.ink.opacity(0.5)))
            }
        }
        .frame(width: 31, height: 15)
    }
}

/// Charging bolt glyph, traced from the design handoff's SVG path and scaled
/// into whatever rect it's given.
private struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 8.9, y: 0.35))
        p.addLine(to: CGPoint(x: 1.05, y: 9.6))
        p.addCurve(to: CGPoint(x: 1.75, y: 11.1), control1: CGPoint(x: 0.55, y: 10.2), control2: CGPoint(x: 0.95, y: 11.1))
        p.addLine(to: CGPoint(x: 4.95, y: 11.1))
        p.addLine(to: CGPoint(x: 2.85, y: 17.0))
        p.addCurve(to: CGPoint(x: 3.95, y: 17.65), control1: CGPoint(x: 2.6, y: 17.7), control2: CGPoint(x: 3.45, y: 18.2))
        p.addLine(to: CGPoint(x: 11.85, y: 8.4))
        p.addCurve(to: CGPoint(x: 11.15, y: 6.9), control1: CGPoint(x: 12.35, y: 7.8), control2: CGPoint(x: 11.95, y: 6.9))
        p.addLine(to: CGPoint(x: 8, y: 6.9))
        p.addLine(to: CGPoint(x: 10.05, y: 1.0))
        p.addCurve(to: CGPoint(x: 8.9, y: 0.35), control1: CGPoint(x: 10.3, y: 0.3), control2: CGPoint(x: 9.45, y: -0.2))
        p.closeSubpath()

        let transform = CGAffineTransform(scaleX: rect.width / 13, y: rect.height / 18)
        return p.applying(transform)
    }
}

// MARK: - "All-time" disclosure toggle

private struct ChevronGlyph: View {
    let expanded: Bool
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 3.4, y: 1.6))
            p.addLine(to: CGPoint(x: 6.8, y: 5))
            p.addLine(to: CGPoint(x: 3.4, y: 8.4))
        }
        .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        .frame(width: 9, height: 9)
        .rotationEffect(.degrees(expanded ? 90 : 0))
    }
}

private struct LifetimeToggle: View {
    @Binding var expanded: Bool
    let reduceMotion: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.2)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                ChevronGlyph(expanded: expanded)
                Text(L.batterySectionLifetime)
                    .font(.system(size: 12))
                    .foregroundStyle(isHovering ? BP.inkSoft : BP.muted)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Mini-tile

private struct StatTile: View {
    let label: String
    let value: String
    var valueColor: Color = BP.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(BP.muted)
            Text(value).font(.system(size: 19, weight: .bold)).monospacedDigit().kerning(-0.285).foregroundStyle(valueColor)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(BP.tile))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(BP.tileLine, lineWidth: 1))
    }
}

// MARK: - Popover height measurement

/// Reports the popover content's natural height so the ScrollView frame can be
/// capped at maxPopoverHeight only when the content actually exceeds it.
private struct PopoverContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Charging bolt animation

/// Pulsing glow animation for the charging bolt icon.
/// When accessibility reduce motion is enabled, displays a static glow without animation.
private struct PulsingBoltModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        if reduceMotion {
            // Static glow, no pulsing animation
            content
                .shadow(color: BP.bolt.opacity(0.6), radius: 6)
        } else {
            // Pulsing glow: opacity 0.6↔1.0, scale 0.95↔1.05, soft shadow
            content
                .opacity(isAnimating ? 1.0 : 0.6)
                .scaleEffect(isAnimating ? 1.05 : 0.95)
                .shadow(color: BP.bolt.opacity(0.6), radius: 6)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }
        }
    }
}
