// Views/IPhoneDeviceView.swift
// IPHONE-DESIGN: the device page on DS3 - pinned frosted header and the six section cards.

import SwiftUI

struct IPhoneDeviceView: View {
    let model: IPhoneModel
    let deviceKey: String
    /// Window is at least 1200 pt wide (identity grids use 7 / 3 columns).
    let wide: Bool
    let onBack: () -> Void
    var onAskRestart: () -> Void = {}

    private var record: IPhoneDeviceRecord? { model.devices.first { $0.id == deviceKey } }
    private var isConnected: Bool { model.connected[deviceKey] != nil }
    private var status: IPhoneModel.DeviceStatus { model.status[deviceKey] ?? .remembered }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.wifiStalled.contains(deviceKey) && !isConnected {
                    IPhoneWifiStallNote(restarting: model.restartingService,
                                        disabled: model.restartingService || !model.transportAvailable,
                                        onRestart: onAskRestart)
                    if let err = model.restartError { IPhoneListBanner(kind: .error(err)) }   // existing strip, so a failed restart shows here too
                }
                IPhoneBatteryCard(record: record, snapshot: model.lastSnapshot[deviceKey], prefersRawHealth: model.prefersRawHealth)
                    .ds3Appear(delay: DS3Motion.cardDelays[0])
                    // IPHONE-LIVE-BATTERY: the 10 s battery refresh runs only while this card is mounted and at least
                    // partly inside the page's scroll viewport (rule no-unseen-work).
                    .onAppear { model.setBatteryCardShown(deviceKey: deviceKey, true) }
                    .onDisappear { model.setBatteryCardShown(deviceKey: deviceKey, false) }
                    .onScrollVisibilityChange(threshold: 0.01) { visible in model.setBatteryCardShown(deviceKey: deviceKey, visible) }
                    .onChange(of: model.autoReadEnabled) { _, _ in model.liveBatteryGateChanged(deviceKey: deviceKey) }
                IPhoneBatteryHistoryCard(points: record?.battery ?? [])
                    .ds3Appear(delay: DS3Motion.cardDelays[1])
                IPhoneLogsCard(model: model, deviceKey: deviceKey)
                    .ds3Appear(delay: DS3Motion.cardDelays[2])
                IPhoneImportCard(model: model, deviceKey: deviceKey)
                    .ds3Appear(delay: DS3Motion.cardDelays[3])
                IPhoneIdentityCard(model: model, deviceKey: deviceKey, wide: wide)
                    .ds3Appear(delay: DS3Motion.cardDelays[4])
                IPhoneFirmwareCard(model: model, deviceKey: deviceKey)
                    .ds3Appear(delay: DS3Motion.cardDelays[5])
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            back
            IPhoneGlyph(size: .header, tint: tint, tinted: isConnected)
            nameBlock
            tag
            refresh
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background { DS3GlassBar() }
        .overlay(alignment: .bottom) { Rectangle().fill(DS3.line).frame(height: 1) }
    }

    private var tint: Color {
        record.flatMap { IPhoneData.enclosureRGB(productType: $0.productType, code: $0.enclosureColor) }
            .map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? (isConnected ? DS3.accentInk : DS3.muted)
    }

    private var back: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                Text(L.iphoneKickerDevices)
            }
            .padding(.leading, -3)
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 14, topRim: 1))
        .accessibilityLabel(L.iphoneBack)
        .accessibilityIdentifier("iphone-back")
        .layoutPriority(1)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(record?.name ?? L.iphoneUnknownDevice)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
            Text([record?.marketingName, record?.osVersion.map { "iOS \($0)" }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13.5))
                .foregroundStyle(DS3.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tag: some View {
        let t: (DS3Tag.Tone, String) = {
            switch status {
            case .connected: return (.accent, model.link(deviceKey) == .wifi ? L.iphoneStatusConnectedWifi : L.iphoneStatusConnected)
            case .reading: return (.accent, L.iphoneStatusReading)
            case .needsTrust: return (.amber, L.iphoneStatusNeedsTrust)
            case .readFailed(let text): return (.hot, text)
            case .remembered:
                return (.neutral, record.map { L.iphoneStatusRemembered(fmtDisplayDay($0.lastSeen)) } ?? L.iphoneTagNotConnected)
            }
        }()
        return DS3Tag(tone: t.0, text: t.1, pulse: false, vPad: 5, hPad: 12).layoutPriority(1)
    }

    private var refresh: some View {
        Button(L.iphoneRefresh) { model.refresh(deviceKey: deviceKey) }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1))
            .disabled(!isConnected || status == .reading)
            .help(isConnected ? "" : L.iphoneRefreshOfflineHelp)
            .accessibilityLabel(L.iphoneRefresh)
            .layoutPriority(1)
    }
}

/// IPHONE-WIFI D15: under the device page header when the phone was lost over Wi-Fi and has not come back.
struct IPhoneWifiStallNote: View {
    let restarting: Bool
    let disabled: Bool
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(DS3.amber).frame(width: 7, height: 7)
            Text(L.iphoneWifiStallNote)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS3.amberInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { onRestart() } label: {
                Text(L.iphoneRestartService)
                    .dsSwapInPlace(restarting) {
                        HStack(spacing: 8) {
                            DS3Spinner(role: .softRing, size: 13, accessibilityLabel: L.iphoneRestartBusy)
                            Text(L.iphoneRestartingShort)
                        }
                    }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1, disabledOpacity: 0.5))
            .disabled(disabled)
            .help(L.iphoneRestartService)
            .accessibilityLabel(L.iphoneRestartService)
            .ds3BusyValue(restarting)
        }
        .padding(.vertical, 9)
        .padding(.leading, 18)
        .padding(.trailing, 9)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS3.amber.opacity(0.12)))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 18, style: .continuous), ring: DS3.amber.opacity(0.4))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.iphoneWifiStallNote)
    }
}
