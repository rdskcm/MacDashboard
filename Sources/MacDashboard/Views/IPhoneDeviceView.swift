// Views/IPhoneDeviceView.swift
// The device page (layout only, no animation): header row and the section cards.

import SwiftUI

struct IPhoneDeviceView: View {
    let model: IPhoneModel
    let deviceKey: String
    let onBack: () -> Void

    private var record: IPhoneDeviceRecord? { model.devices.first { $0.id == deviceKey } }
    private var isConnected: Bool { model.connected[deviceKey] != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                IPhoneBatteryCard(record: record, snapshot: model.lastSnapshot[deviceKey])
                IPhoneBatteryHistoryCard(points: record?.battery ?? [])
                IPhoneLogsCard(model: model, deviceKey: deviceKey)
                IPhoneImportCard(model: model, deviceKey: deviceKey)
                IPhoneIdentityCard(model: model, deviceKey: deviceKey)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RainbowCapsuleButton(title: L.iphoneBack, size: .card, action: onBack)
                .accessibilityLabel(L.iphoneBack)
            Text(record?.name ?? L.iphoneUnknownDevice)
                .font(.system(size: 19, weight: .bold))
                .lineLimit(1)
            Text([record?.marketingName, record?.osVersion.map { "iOS \($0)" }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12.5))
                .foregroundStyle(DS.muted)
                .lineLimit(1)
            Spacer(minLength: 12)
            RainbowCapsuleButton(title: L.iphoneRefresh, size: .card) {
                model.refresh(deviceKey: deviceKey)
            }
            .disabled(!isConnected)
            .accessibilityLabel(L.iphoneRefresh)
        }
    }
}
