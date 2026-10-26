// Views/IPhoneHeaderActions.swift
// iPhone-mode top-bar actions (IPHONE-DESIGN): «Restart connection service…» (secondary, confirmed
// in a popover) and «Search again» (primary). Below the width where both labels fit, the restart
// button becomes a 34 pt round icon button: the tier (< 1000) drives it as one animated button identity, and a
// ViewThatFits fallback keeps the compact form when the full label does not fit.

import SwiftUI

struct IPhoneHeaderActions: View {
    let model: IPhoneModel
    /// The width tier's `isNarrow` (RESIZE-MOTION), passed by `MainDashboardView`.
    let compact: Bool
    @State private var confirmingRestart = false

    private var disabled: Bool { model.restartingService || !model.transportAvailable }

    var body: some View {
        // The first child animates the tier change (one button identity, RESIZE-MOTION §3.3); the second keeps the
        // content-fit fallback for a language whose full label does not fit at tier mid (RU, D5).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { restart(compact: compact); search }
            HStack(spacing: 8) { restart(compact: true); search }
        }
    }

    private func restart(compact: Bool) -> some View {
        let font = Font.system(size: 13, weight: .semibold)
        let fullW = ds3IdealWidth(key: "restart|\(L.iphoneRestartService)|13s") { Text(L.iphoneRestartService).font(font).lineLimit(1) }
        let iconW = ds3IdealWidth(key: "restart|arrow.triangle.2.circlepath|13s") {
            Image(systemName: "arrow.triangle.2.circlepath").font(font)
        }
        return Button { confirmingRestart = true } label: {
            Color.clear
                .frame(width: compact ? iconW : fullW)
                .overlay { Text(L.iphoneRestartService).frame(width: fullW).opacity(compact ? 0 : 1) }
                .overlay { Image(systemName: "arrow.triangle.2.circlepath").opacity(compact ? 1 : 0) }
                .clipped()
                .dsSwapInPlace(model.restartingService) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).accessibilityLabel(L.iphoneRestartBusy)
                        if !compact { Text(L.iphoneRestartingShort) }
                    }
                }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: compact ? (34 - iconW) / 2 : 15, topRim: 1,
                                    disabledOpacity: 0.5))
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
