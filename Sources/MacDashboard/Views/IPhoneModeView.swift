// Views/IPhoneModeView.swift
// iPhone mode content (layout only, no animation): the tiles grid and, after a click, the
// device page. Navigation is a plain @State key, not NavigationStack (D19: custom chrome).

import SwiftUI

struct IPhoneModeView: View {
    let model: IPhoneModel
    @State private var selectedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = model.restartError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
            if let key = selectedKey {
                IPhoneDeviceView(model: model, deviceKey: key, onBack: { selectedKey = nil })
            } else {
                tiles
            }
        }
    }

    private var tiles: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.iphoneKickerDevices).dsKicker()
                if !model.transportAvailable {
                    notice(L.iphoneUnavailable)
                } else if model.devices.isEmpty && model.pendingHandles.isEmpty {
                    notice(L.iphoneEmpty)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(model.sortedDevices) { record in
                            IPhoneTileView(record: record, status: model.status[record.id] ?? .remembered) {
                                selectedKey = record.id
                            }
                        }
                        ForEach(model.sortedPending, id: \.raw) { handle in
                            IPhonePendingTileView(status: model.pendingStatus[handle] ?? .needsTrust) {
                                model.refresh(handle: handle)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(DS.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .dsCardSurface()
    }
}

/// Colour-only phone picture (R12): the lookup colour, neutral when there is no entry.
private struct IPhonePicture: View {
    let productType: String?
    let colorCode: String?

    var body: some View {
        Image(systemName: "iphone")
            .font(.system(size: 44))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var color: Color {
        if let c = IPhoneData.enclosureRGB(productType: productType, code: colorCode) {
            return Color(red: c.r, green: c.g, blue: c.b)
        }
        return DS.muted
    }
}

struct IPhoneTileView: View {
    let record: IPhoneDeviceRecord
    let status: IPhoneModel.DeviceStatus
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                IPhonePicture(productType: record.productType, colorCode: record.enclosureColor)
                Text(record.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(record.marketingName ?? "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.muted)
                    .lineLimit(1)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.muted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentShape(Rectangle())
            .dsCardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.iphoneOpenDeviceA11y(record.name))
    }

    private var statusLine: String {
        switch status {
        case .connected: return L.iphoneStatusConnected
        case .reading: return L.iphoneStatusReading
        case .needsTrust: return L.iphoneStatusNeedsTrust
        case .readFailed(let text): return text
        case .remembered: return L.iphoneStatusRemembered(fmtDisplayDay(record.lastSeen))
        }
    }
}

/// An attached phone that could not be identified (no device key yet): trust or read error.
struct IPhonePendingTileView: View {
    let status: IPhoneModel.DeviceStatus
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IPhonePicture(productType: nil, colorCode: nil)
            Text(L.iphoneUnknownDevice)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
            Text(statusLine)
                .font(.system(size: 11))
                .foregroundStyle(DS.muted)
                .lineLimit(3)
            RainbowCapsuleButton(title: L.iphoneRetry, size: .card, action: onRetry)
                .accessibilityLabel(L.iphoneRetry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .dsCardSurface()
    }

    private var statusLine: String {
        switch status {
        case .readFailed(let text): return text
        default: return L.iphoneStatusNeedsTrust
        }
    }
}
