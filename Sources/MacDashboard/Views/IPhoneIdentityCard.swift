// Views/IPhoneIdentityCard.swift
// Device and parts identity (layout only, no animation). Serial-type values are masked
// by default; reveal and copy are per value. Values live in memory only (R13, D10).

import AppKit
import SwiftUI

struct IPhoneIdentityCard: View {
    let model: IPhoneModel
    let deviceKey: String
    /// Revealed ids reset when the user leaves the device page (the card is unmounted).
    @State private var revealed: Set<String>
    @State private var copiedID: String?

    /// `initiallyRevealed` exists for the harness render; the page always passes none.
    init(model: IPhoneModel, deviceKey: String, initiallyRevealed: Set<String> = []) {
        self.model = model
        self.deviceKey = deviceKey
        _revealed = State(initialValue: initiallyRevealed)
    }

    private var isConnected: Bool { model.connected[deviceKey] != nil }
    private var fields: [IPhoneIdentityField]? { model.identity[deviceKey] }
    private var loading: Bool { model.identityLoading.contains(deviceKey) }

    var body: some View {
        CardChrome(title: L.iphoneIdentityTitle) {
            RainbowCapsuleButton(title: L.iphoneRefresh, size: .card) {
                model.loadIdentity(deviceKey: deviceKey)
            }
            .disabled(!isConnected || loading)
            .accessibilityLabel(L.iphoneIdentityRefreshA11y)
        } content: {
            content
        }
        .task(id: isConnected) {
            if isConnected, model.identity[deviceKey] == nil { model.loadIdentity(deviceKey: deviceKey) }
        }
    }

    @ViewBuilder private var content: some View {
        if let fields, !fields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(fields) { f in row(f) }
            }
        } else if loading {
            SectionStateView(done: false)
        } else if !isConnected {
            Text(L.iphoneIdentityConnectToRead).font(.callout).foregroundStyle(DS.muted)
        } else {
            SectionStateView(done: false)
        }
    }

    private func row(_ f: IPhoneIdentityField) -> some View {
        let label = L.iphoneIdentityLabel(f.label)
        let shown = !f.isSecret || revealed.contains(f.id)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12.5)).foregroundStyle(DS.muted)
                .frame(width: 190, alignment: .leading)
            Text(shown ? f.value : IPhoneData.mask(f.value))
                .font(.system(size: f.isSecret ? 12 : 12.5, design: f.isSecret ? .monospaced : .default))
                .foregroundStyle(DS.ink)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if f.isSecret {
                Button {
                    if revealed.contains(f.id) { revealed.remove(f.id) } else { revealed.insert(f.id) }
                } label: {
                    Text(shown ? L.iphoneIdentityHide : L.iphoneIdentityShow)
                        .font(.system(size: 12)).foregroundStyle(DS.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shown ? L.iphoneHideA11y(label) : L.iphoneRevealA11y(label))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(f.value, forType: .string)
                    copiedID = f.id
                    Task {
                        try? await Task.sleep(for: .milliseconds(1500))
                        if copiedID == f.id { copiedID = nil }
                    }
                } label: {
                    Text(copiedID == f.id ? L.iphoneIdentityCopied : L.iphoneIdentityCopy)
                        .font(.system(size: 12)).foregroundStyle(DS.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.iphoneCopyA11y(label))
            }
        }
    }
}
