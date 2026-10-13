// Views/IPhoneHeaderActions.swift
// iPhone-mode top-bar actions (IPHONE-DESIGN): «Restart connection service…» (secondary, confirmed
// in a popover) and «Search again» (primary). Below the width where both labels fit, the restart
// button becomes a round icon button (ViewThatFits).

import SwiftUI

struct IPhoneHeaderActions: View {
    let model: IPhoneModel
    @State private var confirmingRestart = false

    private var disabled: Bool { model.restartingService || !model.transportAvailable }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { restartFull; search }
            HStack(spacing: 8) { restartCompact; search }
        }
    }

    private var restartFull: some View {
        Button { confirmingRestart = true } label: {
            Text(L.iphoneRestartService)
                .dsSwapInPlace(model.restartingService) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).accessibilityLabel(L.iphoneRestartBusy)
                        Text(L.iphoneRestartingShort)
                    }
                }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1, disabledOpacity: 0.5))
        .disabled(disabled)
        .accessibilityLabel(L.iphoneRestartService)
        .popover(isPresented: $confirmingRestart, arrowEdge: .bottom) { restartConfirm }
    }

    private var restartCompact: some View {
        Button { confirmingRestart = true } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS3.ink)
                .dsSwapInPlace(model.restartingService) {
                    ProgressView().controlSize(.small).accessibilityLabel(L.iphoneRestartBusy)
                }
        }
        .buttonStyle(DS3CircleButtonStyle(diameter: 34, disabledOpacity: 0.5))
        .help(L.iphoneRestartService)
        .disabled(disabled)
        .accessibilityLabel(L.iphoneRestartService)
        .popover(isPresented: $confirmingRestart, arrowEdge: .bottom) { restartConfirm }
    }

    private var restartConfirm: some View {
        IPhoneRestartConfirm(
            onCancel: { confirmingRestart = false },
            onConfirm: {
                confirmingRestart = false
                Task { await model.restartConnectionService() }
            })
    }

    private var search: some View {
        Button(L.iphoneSearchAgain) { model.searchAgain() }
            .buttonStyle(DS3ButtonStyle(kind: .primary, height: 34, hPad: 16, glow: true, topRim: 0.5,
                                        disabledOpacity: 0.5))
            .disabled(disabled)
            .accessibilityLabel(L.iphoneSearchAgain)
    }
}

/// Popover content for the restart confirmation (internal so the harness can render it).
struct IPhoneRestartConfirm: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.iphoneRestartConfirmTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS3.ink)
                Text(L.iphoneRestartConfirmBody)
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L.iphoneRestartCancel, action: onCancel)
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, topRim: 0))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(L.iphoneRestartCancel)
                Button(L.iphoneRestartConfirm, action: onConfirm)
                    .buttonStyle(DS3ButtonStyle(kind: .primary, height: 32, hPad: 14))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(L.iphoneRestartConfirm)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}
