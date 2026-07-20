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

struct BatteryDetailView: View {
    let condition: String?          // from system_profiler report, e.g. "Normal" — may be nil
    @State private var detail: BatteryDetail? = nil
    @State private var updatedAt: Date? = nil
    @State private var lifetimeExpanded: Bool
    @State private var contentHeight: CGFloat? = nil

    init(condition: String?, startLifetimeExpanded: Bool = false) {
        self.condition = condition
        _lifetimeExpanded = State(initialValue: startLifetimeExpanded)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .padding(16)
                .frame(width: 380)
            }
        }
        .task {
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

    @ViewBuilder
    private func loadedContent(_ d: BatteryDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(d)
            Divider()
            nowSection(d)
            Divider()
            capacitySection(d)
            Divider()
            if d.externalConnected {
                chargingSection(d)
            }
            lifetimeSection(d)
            if d.serial != nil || d.manufacturerCode != nil || d.mfgYear != nil {
                Divider()
                passportSection(d)
            }
            if let updatedAt {
                Text(L.batteryUpdatedAt(batteryTimeFormatter.string(from: updatedAt)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Header

    private func batteryIconName(percent: Int) -> String {
        switch percent {
        case 90...: return "battery.100percent"
        case 60..<90: return "battery.75percent"
        case 35..<60: return "battery.50percent"
        case 10..<35: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

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
                Image(systemName: batteryIconName(percent: d.percent ?? 0))
                    .font(.title2)
                if d.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .modifier(PulsingBoltModifier())
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: "\(d.percent ?? 0)")
                        .font(.system(size: 34, weight: .semibold))
                    Text(L.batteryPercentSign)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Text(statusLine(d))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - "Now" section

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func nowSection(_ d: BatteryDetail) -> some View {
        let amperage = d.amperageMA
        let color: Color = {
            guard let amperage else { return .primary }
            if amperage > 0 { return .green }
            if amperage < 0 { return .orange }
            return .primary
        }()

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L.batterySectionNow)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    StatTile(
                        label: L.batteryLabelPower,
                        value: d.powerW.map { L.batteryWatts(fmtNum($0, decimals: 2)) } ?? "—",
                        valueColor: color
                    )
                    .gridCellUnsizedAxes([])
                    StatTile(
                        label: L.batteryLabelCurrent,
                        value: amperage.map { L.batteryMA($0) } ?? "—",
                        valueColor: color
                    )
                    .gridCellUnsizedAxes([])
                }
                GridRow {
                    StatTile(
                        label: L.batteryLabelVoltage,
                        value: d.voltageMV.map { L.batteryVolts(fmtNum(Double($0) / 1000, decimals: 2)) } ?? "—"
                    )
                    .gridCellUnsizedAxes([])
                    StatTile(
                        label: L.batteryLabelTemperature,
                        value: d.temperatureC.map { L.batteryCelsius(fmtNum($0, decimals: 1)) } ?? "—"
                    )
                    .gridCellUnsizedAxes([])
                }
            }
            if !d.cellVoltagesMV.isEmpty {
                Text(L.batteryCellsLine(d.cellVoltagesMV.map { fmtNum(Double($0) / 1000, decimals: 3) }.joined(separator: " · ")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lpm = d.lowPowerMode {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                    labelValueRow(
                        L.batteryDetailLowPower,
                        lpm ? L.energyValueOn : L.energyValueOff,
                        valueColor: lpm ? Severity.good.color : .secondary
                    )
                }
            }
        }
    }

    // MARK: - "Capacity and health" section

    private func capacitySection(_ d: BatteryDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L.batterySectionCapacity)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.batteryCapMax).font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: d.maxCapacityMAh.map { L.batteryMAh($0) } ?? "—").font(.callout)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L.batteryCapDesign).font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: d.designCapacityMAh.map { L.batteryMAh($0) } ?? "—").font(.callout)
                }
            }
            if let maxCap = d.maxCapacityMAh, let designCap = d.designCapacityMAh, designCap > 0 {
                let fraction = min(1, Double(maxCap) / Double(designCap))
                let color: Color = {
                    guard let health = d.healthPercent else { return .primary }
                    if health >= 80 { return .green }
                    if health >= 60 { return .yellow }
                    return .red
                }()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(color)
                            .frame(width: geo.size.width * CGFloat(fraction))
                    }
                }
                .frame(height: 6)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                if let health = d.healthPercent {
                    labelValueRow(L.batteryCapHealth, L.batteryPercent(health))
                }
                if let cycles = d.cycleCount {
                    let value = d.designCycleCount.map { L.batteryCyclesOf(cycles, $0) } ?? "\(cycles)"
                    labelValueRow(L.batteryCapCycles, value)
                }
                if let current = d.currentCapacityMAh {
                    labelValueRow(L.batteryCapCurrentCharge, L.batteryMAh(current))
                }
                if let condition {
                    labelValueRow(L.batteryCapCondition, condition)
                }
            }
        }
    }

    // MARK: - "Charging" section

    private func chargingSection(_ d: BatteryDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L.batterySectionCharging)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                if let adapter = d.adapter {
                    labelValueRow(L.batteryChargeAdapter, adapterLine(adapter))
                    if let pdLine = protocolLine(adapter) {
                        labelValueRow(L.batteryChargeProtocol, pdLine)
                    }
                    if !adapter.pdProfiles.isEmpty {
                        labelValueRow(L.batteryChargeProfiles, profilesLine(adapter))
                    }
                }
                if let mA = d.charger?.chargingCurrentMA, mA > 0 {
                    labelValueRow(L.batteryChargeCurrentLabel, L.batteryMA(mA))
                }
                labelValueRow(L.batteryChargeStatus, statusValue(d))
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
        DisclosureGroup(isExpanded: $lifetimeExpanded) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                if let lifetime = d.lifetime {
                    if let minT = lifetime.minTemperatureC, let avgT = lifetime.avgTemperatureC, let maxT = lifetime.maxTemperatureC {
                        labelValueRow(L.batteryLifetimeTempLabel, L.batteryLifetimeTempValue(minT, fmtNum(avgT, decimals: 1), maxT))
                    }
                    if let maxCharge = lifetime.maxChargeCurrentMA {
                        labelValueRow(L.batteryLifetimeMaxCharge, L.batteryMA(maxCharge))
                    }
                    if let maxDischarge = lifetime.maxDischargeCurrentMA {
                        labelValueRow(L.batteryLifetimeMaxDischarge, L.batteryMA(maxDischarge))
                    }
                    if let minV = lifetime.minPackVoltageMV, let maxV = lifetime.maxPackVoltageMV {
                        labelValueRow(L.batteryLifetimeVoltage, L.batteryLifetimeVoltageRange(fmtNum(Double(minV) / 1000, decimals: 2), fmtNum(Double(maxV) / 1000, decimals: 2)))
                    }
                    if let hours = lifetime.totalOperatingTimeH {
                        labelValueRow(L.batteryLifetimeOperatingTime, L.batteryOperatingHours(hours))
                    }
                }
            }
        } label: {
            Text(L.batterySectionLifetime)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared label/value row

    @ViewBuilder
    private func labelValueRow(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(valueColor)
                .gridColumnAlignment(.trailing)
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
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                    if let code = d.manufacturerCode {
                        labelValueRow(L.batteryDetailManufacturer, Self.manufacturerNames[code] ?? code)
                    }
                    if let serial = d.serial {
                        labelValueRow(L.batteryDetailSerial, serial)
                    }
                    if let year = d.mfgYear, let week = d.mfgWeek, let code = d.mfgCode {
                        labelValueRow(L.batteryDetailMfgDate, mfgDateValue(year: year, week: week, code: code))
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

// MARK: - Mini-tile

private struct StatTile: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
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
                .shadow(color: Color.yellow.opacity(0.6), radius: 6)
        } else {
            // Pulsing glow: opacity 0.6↔1.0, scale 0.95↔1.05, soft shadow
            content
                .opacity(isAnimating ? 1.0 : 0.6)
                .scaleEffect(isAnimating ? 1.05 : 0.95)
                .shadow(color: Color.yellow.opacity(0.6), radius: 6)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }
        }
    }
}
