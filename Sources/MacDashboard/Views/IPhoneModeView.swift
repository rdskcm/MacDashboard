// Views/IPhoneModeView.swift
// iPhone mode content (IPHONE-DESIGN): the device list (header, banners, tile grid or notice) and,
// after a click, the device page. Navigation is a plain model key, not NavigationStack (D19: custom chrome).

import SwiftUI

struct IPhoneModeView: View {
    let model: IPhoneModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Window width, read here because this root's width is set by the window, never by its content.
    @State private var windowWidth: CGFloat = 1150

    var body: some View {
        Group {
            if let key = model.selectedDeviceKey {
                IPhoneDeviceView(model: model, deviceKey: key, wide: windowWidth >= 1200,
                                 onBack: { model.selectedDeviceKey = nil })
            } else {
                listPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { windowWidth = $0 }
    }

    private var tileCount: Int { model.devices.count + model.pendingHandles.count }

    private var listPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                banners
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ds3Appear()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(L.iphoneKickerDevices)
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.57)
                    .foregroundStyle(DS3.ink)
                    .lineLimit(1)
                if tileCount > 0 { countBadge }
            }
            Text(summary)
                .font(.system(size: 14.5))
                .foregroundStyle(DS3.inkSoft)
                .lineLimit(1)
        }
    }

    private var countBadge: some View {
        Text("\(tileCount)")
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(DS3.ink)
            .padding(.horizontal, 9)
            .frame(minWidth: 28, minHeight: 28)
            .background(Capsule().fill(DS3.chip))
            .ds3InsetRims(Capsule(), top: DS3.rimHi, ring: DS3.lineStrong)
    }

    private var summary: String {
        if !model.transportAvailable { return L.iphoneSummaryUnavailable }
        if tileCount == 0 { return L.iphoneSummaryNone }
        let c = model.devices.filter { model.connected[$0.id] != nil }.count
        return L.iphoneSummary(connected: c, notConnected: model.devices.count - c,
                               waiting: model.pendingHandles.count)
    }

    @ViewBuilder private var banners: some View {
        if model.restartingService {
            IPhoneListBanner(kind: .restarting)
        } else if let err = model.restartError {
            IPhoneListBanner(kind: .error(err))
        }
    }

    @ViewBuilder private var content: some View {
        if !model.transportAvailable {
            IPhoneNotice(kind: .unavailable)
        } else if tileCount == 0 {
            IPhoneNotice(kind: .empty, searchDisabled: model.restartingService,
                         onSearch: { model.searchAgain() })
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                      alignment: .leading, spacing: 16) {
                ForEach(Array(model.sortedDevices.enumerated()), id: \.element.id) { i, r in
                    IPhoneTileView(record: r, status: model.status[r.id] ?? .remembered,
                                   snapshot: model.lastSnapshot[r.id],
                                   storage: model.identity[r.id]?.first { $0.label == .storage }?.value) {
                        model.selectedDeviceKey = r.id
                    }
                    .accessibilityIdentifier("iphone-tile-\(i)")
                    .ds3Appear(delay: DS3Motion.tileStagger * Double(i))
                }
                ForEach(Array(model.sortedPending.enumerated()), id: \.element.raw) { j, h in
                    IPhonePendingTileView(status: model.pendingStatus[h] ?? .needsTrust) {
                        model.refresh(handle: h, trigger: .attach)
                    }
                    .ds3Appear(delay: DS3Motion.tileStagger * Double(model.devices.count + j))
                }
            }
            .opacity(model.restartingService ? 0.5 : 1)
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.4), value: model.restartingService)
        }
    }
}

/// Error / restarting strip above the device list.
struct IPhoneListBanner: View {
    enum Kind { case error(String), restarting }
    let kind: Kind

    var body: some View {
        switch kind {
        case .error(let err):
            HStack(spacing: 10) {
                Circle().fill(DS3.hot).frame(width: 7, height: 7)
                Text(err)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS3.hotInk)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(DS3.hot.opacity(0.12)))
            .ds3InsetRims(Capsule(), ring: DS3.hot.opacity(0.4))
        case .restarting:
            HStack(spacing: 10) {
                DS3Spinner(role: .accentInkRing, size: 14)
                Text(L.iphoneRestartingBanner)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS3.accentInk)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ds3TintPanel(DS3.accent, from: 0.20, to: 0.09, ring: 0.30, cornerRadius: 999, top: DS3.rimHi)
        }
    }
}

struct IPhoneTileView: View {
    let record: IPhoneDeviceRecord
    let status: IPhoneModel.DeviceStatus
    let snapshot: IPhoneSnapshot?
    let storage: String?
    let onOpen: () -> Void

    private var connected: Bool { status == .connected }

    var body: some View {
        Button(action: onOpen) { tile }
            .buttonStyle(DS3TileButtonStyle())
            .accessibilityLabel(L.iphoneOpenDeviceA11y(record.name))
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 14) {
            row1
            row2
            metrics
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 300, alignment: .topLeading)
        .ds3GlassCard(cornerRadius: 34)
    }

    private var tint: Color {
        IPhoneData.enclosureRGB(productType: record.productType, code: record.enclosureColor)
            .map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? (connected ? DS3.accentInk : DS3.muted)
    }

    private var row1: some View {
        HStack(spacing: 14) {
            IPhoneGlyph(size: .tile, tint: tint, tinted: connected)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.22)
                    .foregroundStyle(DS3.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(record.marketingName ?? "")
                    .font(.system(size: 13.5))
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var row2: some View {
        HStack(spacing: 8) {
            DS3Tag(tone: tone, text: tagText, pulse: connected).layoutPriority(1)
            Text(sub)
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var tone: DS3Tag.Tone {
        switch status {
        case .connected, .reading: return .accent
        case .needsTrust: return .amber
        case .readFailed: return .hot
        case .remembered: return .neutral
        }
    }

    private var tagText: String {
        switch status {
        case .connected: return L.iphoneStatusConnected
        case .reading: return L.iphoneStatusReading
        case .needsTrust: return L.iphoneTagTrustNeeded
        case .readFailed: return L.iphoneTagReadFailed
        case .remembered: return L.iphoneTagNotConnected
        }
    }

    private var sub: String {
        switch status {
        case .connected:
            guard let b = snapshot?.battery else { return "" }
            let state = b.isCharging ? L.iphoneStateChargingLower
                : (b.externalConnected ? L.iphoneStateExternalLower : L.iphoneStateBatteryLower)
            return b.percent.map { L.iphoneSubCharge($0, state) } ?? state
        case .reading: return ""
        case .needsTrust: return L.iphoneSubTrust
        case .readFailed: return L.iphoneSubReconnect
        case .remembered: return L.iphoneSubLastSeen(fmtShortDay(record.lastSeen))
        }
    }

    // MARK: Metrics

    private var healthValue: Double { health.value }
    private var health: (value: Double, text: String) {
        if connected, let b = snapshot?.battery, let max = b.maxCapacityMAh, let design = b.designCapacityMAh,
           let h = IPhoneData.preciseHealth(maxMAh: max, designMAh: design) {
            return (h, iphoneOneDecimal(h) + " %")
        }
        if let hp = latestPoint(where: { $0.healthPercent != nil })?.healthPercent {
            return (Double(hp), "\(hp) %")
        }
        return (0, "—")
    }

    private var cyclesText: String {
        if connected, let c = snapshot?.battery?.cycleCount { return "\(c)" }
        if let c = latestPoint(where: { $0.cycles != nil })?.cycles { return "\(c)" }
        return "—"
    }

    private func latestPoint(where pred: (BatteryPoint) -> Bool) -> BatteryPoint? {
        record.battery.filter(pred).max { $0.day < $1.day }
    }

    private var metrics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            box(L.iphoneTileHealthFull, short: L.iphoneTileHealth, health.text, bar: true)
            box(L.iphoneBatCycles, cyclesText)
            box("iOS", record.osVersion ?? "—", small: true)
            box(L.iphoneIdentityLabel(.storage), storage ?? "—", small: true)
        }
    }

    private func labelText(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12.5))
            .foregroundStyle(DS3.muted)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func box(_ label: String, short: String? = nil, _ value: String, small: Bool = false, bar: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Labels are one line so every box in a row has the same height.
            ViewThatFits(in: .horizontal) {
                labelText(label)
                if let short { labelText(short) }
            }
            Spacer(minLength: 0)
            Text(value)
                .font(small ? .system(size: 16, weight: .semibold) : .system(size: 18, weight: .bold))
                .tracking(small ? 0 : -0.18)
                .monospacedDigit()
                .foregroundStyle(connected ? DS3.ink : DS3.inkSoft)
                .lineLimit(1)
                .truncationMode(.tail)
            if bar {
                DS3Bar(fraction: healthValue / 100, height: 5,
                       fill: AnyShapeStyle(connected ? DS3.accent : DS3.muted))
            } else {
                // Reserves the bar's slot so the values of a row sit on one line.
                Color.clear.frame(height: 5).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 73, alignment: .topLeading)
        .ds3RowPanel(cornerRadius: 20)
    }
}

/// An attached phone that could not be identified (no device key yet): trust or read error.
struct IPhonePendingTileView: View {
    let status: IPhoneModel.DeviceStatus
    let onRetry: () -> Void

    private var trust: Bool { status == .needsTrust }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IPhoneGlyph(size: .tile, tint: DS3.muted, tinted: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.iphoneUnknownDevice)
                        .font(.system(size: 18, weight: .bold))
                        .tracking(-0.22)
                        .foregroundStyle(DS3.ink)
                        .lineLimit(1)
                    Text(L.iphoneNotIdentified)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS3.muted)
                        .lineLimit(1)
                }
            }
            DS3Tag(tone: trust ? .amber : .hot, text: trust ? L.iphoneTagTrustNeeded : L.iphoneTagReadFailed)
            VStack(alignment: .leading, spacing: 12) {
                Text(trust ? L.iphonePendingTrustText : L.iphonePendingFailedText)
                    .font(.system(size: 14))
                    .foregroundStyle(DS3.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(L.iphoneRetry, action: onRetry)
                    .buttonStyle(DS3ButtonStyle(kind: .primary, height: 34, hPad: 16, topRim: 0.5))
                    .accessibilityLabel(L.iphoneRetry)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ds3RowPanel(cornerRadius: 22)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 300, alignment: .topLeading)
        .ds3GlassCard(cornerRadius: 34)
    }
}

/// Centred notice replacing the grid: no phones found, or the transport is unavailable.
struct IPhoneNotice: View {
    enum Kind { case empty, unavailable }
    let kind: Kind
    var searchDisabled = false
    var onSearch: () -> Void = {}

    private var title: String {
        kind == .empty ? L.iphoneNoticeEmptyTitle : L.iphoneNoticeUnavailableTitle
    }
    private var message: String {
        kind == .empty ? L.iphoneNoticeEmptyBody : L.iphoneUnavailable
    }

    var body: some View {
        VStack(spacing: 16) {
            IPhoneGlyph(size: .notice, tint: DS3.inkSoft, tinted: false)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.33)
                    .foregroundStyle(DS3.ink)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(DS3.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if kind == .empty {
                Button(L.iphoneSearchAgain, action: onSearch)
                    .buttonStyle(DS3ButtonStyle(kind: .primary, height: 40, hPad: 20, fontSize: 14,
                                                glow: true, topRim: 0.5))
                    .disabled(searchDisabled)
                    .accessibilityLabel(L.iphoneSearchAgain)
            }
        }
        .padding(.top, 36)
        .padding(.horizontal, 36)
        .padding(.bottom, 32)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}
