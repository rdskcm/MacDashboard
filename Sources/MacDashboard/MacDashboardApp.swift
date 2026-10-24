// MacDashboardApp.swift
// Scaffold owns this file (SPEC §3, §8): app entry point.

import SwiftUI

@main
struct MacDashboardApp: App {
    @State private var model: DashboardModel
    @State private var glass: GlassSettings

    init() {
        _model = State(wrappedValue: DashboardModel())
        _glass = State(wrappedValue: GlassSettings())
        SettingsWindowController.shared.configure(model: _model.wrappedValue, glass: _glass.wrappedValue)
        AppSettings.shared.appearance.apply()
        // Forces the launch-language capture now, before any UI can switch it.
        _ = L10nStore.launchLanguage
        syncAppleLanguages()
    }

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            MainDashboardView(model: model)
                .environment(glass)
                .frame(minWidth: 900, minHeight: 620)
                .onAppear {
                    if VisualFixture.isRequested {
                        model.applyVisualFixture()
                        IPhoneModel.shared.applyVisualFixture()
                        _ = FixtureAppearance.shared
                    } else {
                        model.start()
                        IPhoneModel.shared.start()
                    }
                }
        }
        .defaultSize(width: 1150, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L.settingsMenuItem) { SettingsWindowController.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Menus are built by AppKit at launch from the app-domain `AppleLanguages`
/// default; this write only affects the NEXT launch. Instant in-app strings are
/// handled by L10n — system chrome (menu bar, standard dialogs) catches up on
/// relaunch only.
private func syncAppleLanguages() {
    switch L10nStore.shared.choice {
    case .system:
        if UserDefaults.standard.object(forKey: "AppleLanguages") != nil {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    case .en, .ru:
        let want = [L10nStore.shared.choice.rawValue]
        if UserDefaults.standard.stringArray(forKey: "AppleLanguages") != want {
            UserDefaults.standard.set(want, forKey: "AppleLanguages")
        }
    }
}
