// MacDashboardApp.swift
// Scaffold owns this file (SPEC §3, §8): app entry point.

import SwiftUI

@main
struct MacDashboardApp: App {
    @State private var model: AppModel
    @State private var glass: GlassSettings
    @State private var activity: AppActivityMonitor?

    init() {
        _model = State(wrappedValue: AppModel(actions: .live))
        _glass = State(wrappedValue: GlassSettings(fixture: VisualFixture.isRequested))
        SettingsWindowController.shared.configure(model: _model.wrappedValue, glass: _glass.wrappedValue)
        AppSettings.shared.appearance.apply()
        // Forces the launch-language capture now, before any UI can switch it.
        _ = L10nStore.launchLanguage
        AppLifecycle.syncAppleLanguages(for: L10nStore.shared.choice)
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
                        if activity == nil { activity = AppActivityMonitor(model: model) }
                        IPhoneModel.shared.start()
                        if ProcessInfo.processInfo.arguments.contains("-notifyProbe") { NotificationCenterClient.shared.runProbe() }
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
