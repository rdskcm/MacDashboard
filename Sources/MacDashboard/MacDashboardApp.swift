// MacDashboardApp.swift
// Scaffold owns this file (SPEC §3, §8): app entry point.

import SwiftUI

@main
struct MacDashboardApp: App {
    @State private var model: AppModel
    @State private var glass: GlassSettings
    @State private var activity: AppActivityMonitor?
    @State private var volumes: VolumeMountMonitor?

    init() {
        // MOONPORT-RENAME: before any store reads or creates a folder or AppSettings.shared is first read, in this order:
        // data folder (D2, with the IPSW partials), defaults copy (D3), kept-archive gate (D4: reads the moved
        // iphones.json and the copied setting; the move itself runs in the background).
        if !VisualFixture.isRequested, LegacyDataMigration.runsMigrationHere() {
            LegacyDataMigration.runAtLaunch()
            LegacyDefaultsMigration.runAtLaunch()
            LegacyArchiveMove.runAtLaunch()
        }
        _model = State(wrappedValue: AppModel(actions: .live))
        _glass = State(wrappedValue: GlassSettings(fixture: VisualFixture.isRequested))
        // MOONPORT-RENAME: decided here, before any view or launch work exists; released when the panel closes.
        if !VisualFixture.isRequested, LegacyNotice.willShowAtLaunch(settings: _model.wrappedValue.settings, pendingURL: WelcomePending.defaultURL) {
            _model.wrappedValue.welcome.hold()
        }
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
                        if volumes == nil { volumes = VolumeMountMonitor(model: model) }
                        // Starts the iPhone transport: over Wi-Fi it raises the Local Network prompt (MOONPORT-RENAME).
                        model.welcome.whenOpen { IPhoneModel.shared.start() }
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
