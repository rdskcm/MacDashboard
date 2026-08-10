// MacDashboardApp.swift
// Scaffold owns this file (SPEC §3, §8): app entry point.

import SwiftUI

@main
struct MacDashboardApp: App {
    @State private var model: DashboardModel

    init() {
        _model = State(wrappedValue: DashboardModel())
        // Forces the launch-language capture now, before any UI can switch it.
        _ = L10nStore.launchLanguage
        syncAppleLanguages()
    }

    var body: some Scene {
        WindowGroup(L.appWindowTitle) {
            MainDashboardView(model: model)
                .frame(minWidth: 900, minHeight: 620)
                .onAppear {
                    model.start()
                }
        }
        .defaultSize(width: 1150, height: 780)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }
}

/// Menus are built by AppKit at launch from the app-domain `AppleLanguages`
/// default; this write only affects the NEXT launch. Instant in-app strings are
/// handled by L10n — system chrome (menu bar, standard dialogs) catches up on
/// relaunch only.
private func syncAppleLanguages() {
    let want = [L10nStore.shared.language == .en ? "en" : "ru"]
    if UserDefaults.standard.stringArray(forKey: "AppleLanguages") != want {
        UserDefaults.standard.set(want, forKey: "AppleLanguages")
    }
}
