// Views/IPhoneHeaderActions.swift
// iPhone-mode header: the «Найти iPhone» menu (search again, restart the connection service).
// Layout only, no animation.

import SwiftUI

struct IPhoneHeaderActions: View {
    let model: IPhoneModel
    @State private var confirmingRestart = false

    var body: some View {
        HStack(spacing: 10) {
            if model.restartingService {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L.iphoneRestartBusy)
            }
            Menu(L.iphoneFindMenu) {
                Button(L.iphoneSearchAgain) { model.searchAgain() }
                    .accessibilityLabel(L.iphoneSearchAgain)
                Button(L.iphoneRestartService) { confirmingRestart = true }
                    .disabled(model.restartingService)
                    .accessibilityLabel(L.iphoneRestartService)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(L.iphoneFindMenu)
        }
        .confirmationDialog(L.iphoneRestartConfirmTitle, isPresented: $confirmingRestart,
                            titleVisibility: .visible) {
            Button(L.iphoneRestartConfirm) {
                Task { await model.restartConnectionService() }
            }
            .accessibilityLabel(L.iphoneRestartConfirm)
            Button(L.iphoneRestartCancel, role: .cancel) {}
                .accessibilityLabel(L.iphoneRestartCancel)
        } message: {
            Text(L.iphoneRestartConfirmBody)
        }
    }
}
