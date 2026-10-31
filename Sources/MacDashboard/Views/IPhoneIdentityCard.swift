// Views/IPhoneIdentityCard.swift
// IPHONE-DESIGN: device and parts identity as an info grid and a serial-number grid. Serial-type values are
// masked by default; reveal and copy are per value. Values live in memory only (R13, D10).

import AppKit
import SwiftUI

struct IPhoneIdentityCard: View {
    let model: IPhoneModel
    let deviceKey: String
    /// Window is at least 1200 pt wide: 7 info columns and 3 serial columns instead of 4 and 2.
    let wide: Bool
    /// Revealed ids reset when the user leaves the device page or the phone is unplugged.
    @State private var revealed: Set<String>
    @State private var copiedID: String?

    /// `initiallyRevealed` and `initiallyCopied` exist for the harness render; the page always passes none.
    init(model: IPhoneModel, deviceKey: String, wide: Bool = false,
         initiallyRevealed: Set<String> = [], initiallyCopied: String? = nil) {
        self.model = model
        self.deviceKey = deviceKey
        self.wide = wide
        _revealed = State(initialValue: initiallyRevealed)
        _copiedID = State(initialValue: initiallyCopied)
    }

    private var isConnected: Bool { model.connected[deviceKey] != nil }
    private var fields: [IPhoneIdentityField]? { model.identityRows(deviceKey) }
    private var loading: Bool { model.identityLoading.contains(deviceKey) }

    var body: some View {
        DS3Card(title: L.iphoneIdentityTitle, trailing: {
            Button(L.iphoneRefresh) { model.loadIdentity(deviceKey: deviceKey) }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, topRim: 1))
                .disabled(!isConnected || loading)
                .accessibilityLabel(L.iphoneIdentityRefreshA11y)
        }) {
            content
        }
        .task(id: model.connected[deviceKey]) {
            if isConnected, model.identity[deviceKey] == nil { model.loadIdentity(deviceKey: deviceKey) }
        }
        .onChange(of: model.identity[deviceKey] == nil) { _, cleared in
            if cleared { revealed.removeAll() }
        }
    }

    @ViewBuilder private var content: some View {
        if let fields, !fields.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                infoGrid(fields)
                serials(fields)
            }
        } else if loading {
            IPhoneMessagePanel(text: L.sharedCollectingData, tone: .loading)
        } else if !isConnected {
            IPhoneMessagePanel(text: L.iphoneIdentityConnectToRead)
        } else if model.identityFailed.contains(deviceKey) {
            IPhoneMessagePanel(text: L.iphoneSectionReadFailed, tone: .error)
        } else {
            IPhoneMessagePanel(text: L.sharedCollectingData, tone: .loading)
        }
    }

    private func infoGrid(_ fields: [IPhoneIdentityField]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: wide ? 7 : 4),
                  alignment: .leading, spacing: 8) {
            ForEach(fields.filter { !$0.isSecret }) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.iphoneIdentityLabel(f.label))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS3.inkSoft)
                        .lineLimit(1)
                    Text(f.value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(f.isPending ? DS3.muted : DS3.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(f.isPending ? "" : f.value)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ds3RowPanel(cornerRadius: 20)
                .modifier(PendingCellAccessibility(isPending: f.isPending))
            }
        }
    }

    private func serials(_ fields: [IPhoneIdentityField]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.iphoneIdentitySerials)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS3.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: wide ? 3 : 2),
                      alignment: .leading, spacing: 8) {
                ForEach(fields.filter(\.isSecret)) { secretRow($0) }
            }
        }
    }

    private func secretRow(_ f: IPhoneIdentityField) -> some View {
        let label = L.iphoneIdentityLabel(f.label)
        let shown = revealed.contains(f.id)
        let copied = copiedID == f.id
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS3.inkSoft)
                    .lineLimit(1)
                Text(shown ? f.value : IPhoneData.mask(f.value))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .tracking(0.28)
                    .foregroundStyle(DS3.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Button(shown ? L.iphoneIdentityHide : L.iphoneIdentityShow) {
                    if revealed.contains(f.id) { revealed.remove(f.id) } else { revealed.insert(f.id) }
                }
                .buttonStyle(DS3ButtonStyle(kind: .text, height: 30, hPad: 11, fontSize: 12.5))
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
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(copied ? DS3.accentInk : DS3.ink)
                }
                .buttonStyle(DS3CircleButtonStyle(diameter: 30))
                .help(copied ? L.iphoneIdentityCopied : L.iphoneIdentityCopy)
                .accessibilityLabel(L.iphoneCopyA11y(label))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .ds3RowPanel(cornerRadius: 20)
    }
}

/// A pending cell (value still being read) is one element whose value says so; other cells are untouched.
private struct PendingCellAccessibility: ViewModifier {
    let isPending: Bool
    func body(content: Content) -> some View {
        if isPending {
            content.accessibilityElement(children: .combine).accessibilityValue(L.sharedCollectingData)
        } else {
            content
        }
    }
}
