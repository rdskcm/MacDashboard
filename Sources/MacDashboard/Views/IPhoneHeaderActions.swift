// Views/IPhoneHeaderActions.swift
// iPhone-mode top-bar actions (IPHONE-DESIGN): «Restart connection service…» (secondary, confirmed
// in a popover) and «Search again» (primary). Below the width where both labels fit, the restart
// button becomes a 34 pt round icon button: the form is committed at the window root (`HeaderActionsForm`) as one
// animated button identity; the ViewThatFits is the last-resort fallback for a layout pass that loses more than
// the margin.

import SwiftUI

struct IPhoneHeaderActions: View {
    let model: IPhoneModel
    /// The committed form (RESIZE-MOTION C2, `HeaderActionsForm`), passed by `MainDashboardView`.
    let compact: Bool
    @State private var confirmingRestart = false

    private var disabled: Bool { model.restartingService || !model.transportAvailable }

    var body: some View {
        // Last resort only (see MacHeaderActions): the committed form leaves the margin to spare.
        ViewThatFits(in: .horizontal) {
            row(compact: compact)
            row(compact: true)
        }
    }

    private func row(compact: Bool) -> IPhoneActionsRow {
        IPhoneActionsRow(compact: compact, restarting: model.restartingService, disabled: disabled,
                         confirmingRestart: $confirmingRestart,
                         onConfirmRestart: { Task { await model.restartConnectionService() } },
                         onSearch: { model.searchAgain() })
    }

    /// Ideal width of the full row, hosted once per language by `ds3IdealWidth` (RESIZE-MOTION C2).
    @MainActor
    static func fullRowIdealWidth() -> CGFloat {
        ds3IdealWidth(key: "iphone-actions-full|\(L10nStore.shared.language.rawValue)") {
            IPhoneActionsRow(compact: false, restarting: false, disabled: false, confirmingRestart: .constant(false),
                             onConfirmRestart: {}, onSearch: {})
        }
    }
}

/// One row at one form from values only (no model), so the width probe can host it.
private struct IPhoneActionsRow: View {
    let compact: Bool
    let restarting: Bool
    let disabled: Bool
    @Binding var confirmingRestart: Bool
    let onConfirmRestart: () -> Void
    let onSearch: () -> Void

    var body: some View { HStack(spacing: 8) { restart; search } }

    private var restart: some View {
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
                .dsSwapInPlace(restarting) {
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
        .popover(isPresented: $confirmingRestart, arrowEdge: .bottom) {
            IPhoneRestartConfirm(
                onCancel: { confirmingRestart = false },
                onConfirm: {
                    confirmingRestart = false
                    onConfirmRestart()
                })
        }
    }

    private var search: some View {
        Button(L.iphoneSearchAgain) { onSearch() }
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
