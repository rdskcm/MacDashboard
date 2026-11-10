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
/// close/miniaturize/deminiaturize/occlusion and hands the models Foundation-only facts: `[WindowFacts]` + `NSApp.isActive` to
/// `AppModel.applyVisibility` (the gate, SAMPLER-OCCLUSION-GATE), the gate's verdict to `IPhoneModel.setPaused` (the
/// sysdiagnose request poll), and `appDidBecomeActive()`. `NSPanel`s (HoverTip's tooltip panels) never keep the app un-paused. Created once per
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
        // SAMPLER-OCCLUSION-GATE D15: a known first state (the gate defaults to .visible).
        recompute()
    }

    isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Hidden = not (app active AND at least one non-panel window that is visible and not fully occluded) — resolved by
    /// the gate (VisibilityGate.resolve, D1/D7). This is the only reader of NSApp.isActive / occlusionState for sampling (D9).
    private func recompute() {
        let windows = NSApp.windows.map { WindowFacts($0) }
        model.applyVisibility(windows: windows, appActive: NSApp.isActive)
        IPhoneModel.shared.setPaused(model.isPaused)   // DEVICE-ARCHIVE-CLEANUP Decision 7: the request poll pauses with the app
    }
}

extension WindowFacts {
    /// SAMPLER-OCCLUSION-GATE: the three AppKit facts the gate resolves on, read here and nowhere else (D9).
    @MainActor init(_ w: NSWindow) {
        self.init(isPanel: w is NSPanel, isVisible: w.isVisible, isOnScreen: w.occlusionState.contains(.visible))
    }
}

/// DISK-MOUNT-LIVE: tells SMART's read path and the disk read that a volume mounted or unmounted. Created once per process by
/// MacDashboardApp right after `AppActivityMonitor`, never under -visualFixture; lives as long as the process.
@MainActor
final class VolumeMountMonitor {
    private let model: AppModel
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        observers = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let path = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
                Task { @MainActor [weak self] in
                    guard VolumeEvents.isRelevant(path: path) else { return }
                    self?.model.smart.volumesChanged()
                    self?.model.requestDiskRead()   // IDLE-WORK-TRIM R2
                    self?.model.claudeRun.volumesChanged()
                }
            }
        }
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
