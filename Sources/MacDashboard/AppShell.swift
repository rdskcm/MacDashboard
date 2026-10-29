// AppShell.swift
// ARCH-ENGINE-GUARD: process-level AppKit glue that is neither a view nor Engine — the live `AppActions`, the
// app-activity monitor behind AppModel's pause/resume, relaunch, the `AppleLanguages` write and the appearance
// apply. This file may read `VisualFixture.isRequested`; views may not (EngineBoundaryTests).
import AppKit

extension AppActions {
    /// The real actions, wired once in `MacDashboardApp.init`.
    static let live = AppActions(
        openSettingsPane: { AdviceActionRunner.openPane($0) },
        ensureWindowShown: {
            let hasWindow = NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible }
            if !hasWindow { NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init()) }
        })
}

/// The AppKit side of AppModel's pause/resume (SPEC §1.4). Observes app activate/resign and window
/// close/miniaturize/deminiaturize/occlusion and tells the model two Foundation-only facts: `setPaused(_:)` and
/// `appDidBecomeActive()`. `NSPanel`s (HoverTip's tooltip panels) never keep the app un-paused. Created once per
/// process by MacDashboardApp right after `model.start()`, never under -visualFixture; lives as long as the process.
@MainActor
final class AppActivityMonitor {
    private let model: AppModel
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recompute() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recompute()
                    self?.model.appDidBecomeActive()
                }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
                // Deferred one runloop turn: at the moment this notification fires, the closing window is still in
                // NSApp.windows and still reports isVisible == true, so a synchronous recompute would see stale state.
                Task { @MainActor in DispatchQueue.main.async { self?.recompute() } }
            },
            center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recompute() }
            },
            center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recompute() }
            },
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recompute() }
            },
        ]
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Paused = not (app active AND at least one non-panel window that is visible and not fully occluded).
    private func recompute() {
        let hasVisibleWindow = NSApp.windows.contains { window in
            !(window is NSPanel) && window.isVisible && window.occlusionState.contains(.visible)
        }
        model.setPaused(!(NSApp.isActive && hasVisibleWindow))
    }
}

enum AppLifecycle {
    /// Menus are built by AppKit at launch from the app-domain `AppleLanguages` default; this write only affects the
    /// NEXT launch. Instant in-app strings are handled by L10n — system chrome (menu bar, standard dialogs) catches up
    /// on relaunch only. Kept out of Engine: the tests cover Engine and must not write the test runner's defaults.
    static func syncAppleLanguages(for choice: LanguageChoice) {
        switch choice {
        case .system:
            if UserDefaults.standard.object(forKey: "AppleLanguages") != nil {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        case .en, .ru:
            let want = [choice.rawValue]
            if UserDefaults.standard.stringArray(forKey: "AppleLanguages") != want {
                UserDefaults.standard.set(want, forKey: "AppleLanguages")
            }
        }
    }

    /// The one relaunch path app-wide (constraint `relaunch-single-site`): a second instance is launched and this one
    /// terminates 0.3 s later. Its only call site is the Settings «Relaunch now» button.
    static func relaunch() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }
}

extension AppAppearance {
    /// D5: app-wide; under -visualFixture `FixtureAppearance` owns NSApp.appearance and this is a no-op.
    @MainActor func apply() {
        guard !VisualFixture.isRequested else { return }
        switch self {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
