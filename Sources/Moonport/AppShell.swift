// AppShell.swift
// ARCH-ENGINE-GUARD: process-level AppKit glue that is neither a view nor Engine — the live `AppActions`, the
// app-activity monitor behind AppModel's pause/resume, relaunch, the `AppleLanguages` write and the appearance
// apply. This file may read `VisualFixture.isRequested`; views may not (EngineBoundaryTests).
import AppKit
import Observation

extension AppActions {
    /// The real actions, wired once in `MoonportApp.init`.
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
/// process by MoonportApp right after `model.start()`, never under -visualFixture; lives as long as the process.
/// It also saves a running firmware download as stopped when the app quits (`willTerminateNotification`, IPHONE-IPSW D11).
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
            // Synchronous (assumeIsolated, not Task): the process ends right after this notification. Saves, never deletes.
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { IPhoneModel.shared.ipsw.stopForQuit() }
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
/// MoonportApp right after `AppActivityMonitor`, never under -visualFixture; lives as long as the process.
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

/// MOONPORT-RENAME D6: the AppKit half of the old-app offer (detection and the Trash move are Engine, `LegacyApp`).
/// A user's app is asked to quit, never killed: no `forceTerminate()`, no AppleScript.
enum LegacyAppActions {
    private static func runningOldApps() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.legacyBundleID)
    }

    static func isOldAppRunning() -> Bool { !runningOldApps().isEmpty }

    /// The old app for the Settings › About row: the injected value (snapshot test), else live detection. Under
    /// `-visualFixture` nothing is read from disk, so the fixture states do not depend on the machine.
    static func oldApp(injected: LegacyApp.Found?) -> LegacyApp.Found? {
        injected ?? (VisualFixture.isRequested ? nil : LegacyApp.detect())
    }

    /// Asks every instance with the old bundle ID to quit and waits up to `timeout` seconds (polling every 0.2 s).
    /// true = none is running any more; false = at least one refused, nothing was forced.
    @MainActor static func quitOldApp(timeout: TimeInterval = 5) async -> Bool {
        let apps = runningOldApps()
        for app in apps { app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return apps.allSatisfy(\.isTerminated)
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

/// D-W2: whether a window of this launch holds the Welcome notice. Observable so a second window seeded while it was held
/// re-asks when the claim is released (the first window closed without the user closing the panel).
@MainActor @Observable final class WelcomeClaim {
    static let shared = WelcomeClaim()
    var claimed = false
}

extension LegacyNotice {
    /// D-W2: this launch already claimed the notice for a window, so a second window opened in the same launch shows none.
    @MainActor private static var claimed: Bool {
        get { WelcomeClaim.shared.claimed }
        set { WelcomeClaim.shared.claimed = newValue }
    }

    /// True while this launch still has a Welcome panel to show: not claimed by a window yet, not closed by the user before
    /// (`welcomeShown`), and either the data migration moved something or an earlier launch left `welcome-pending.json`
    /// (amendment 4: it showed the panel and the user never closed it). One small file read, only while the flag is unset.
    /// `MoonportApp.init` holds the `WelcomeGate` on it. `pendingURL` is a parameter so tests never read the real file.
    @MainActor static func willShowAtLaunch(settings: AppSettings, pendingURL: URL) -> Bool {
        guard !claimed, !settings.welcomeShown else { return false }
        return LegacyDataMigration.lastOutcome != .nothing || WelcomePending.load(pendingURL) != nil
    }

    /// The notice for the main window, built once per launch (D7, D-W1). Under `-visualFixture` the `main-*` states carry no
    /// panel (A6); `-fixtureLegacyNotice` shows the fixture value. Otherwise: this launch's migration outcome, the shown
    /// flag, the pending file and the old-app detection. A fresh decision (this launch moved something) is written to the
    /// pending file when none exists; a re-show reads it and writes nothing.
    @MainActor static func atLaunch(settings: AppSettings, pendingURL: URL) -> LegacyNotice? {
        if VisualFixture.isRequested { return VisualFixture.legacyNoticeRequested ? VisualFixture.legacyNotice : nil }
        guard willShowAtLaunch(settings: settings, pendingURL: pendingURL) else { return nil }
        let outcome = LegacyDataMigration.lastOutcome
        let notice = make(outcome: outcome, archivesMoving: LegacyArchiveMove.pending,
                          oldApp: LegacyApp.detect(), running: LegacyAppActions.isOldAppRunning(),
                          dismissed: settings.legacyAppOfferDismissed,
                          parkedFolder: LegacyDataMigration.newestParkedFolder(in: AppInfo.supportFolderURL),
                          shown: settings.welcomeShown, archiveCount: LegacyArchiveMove.archiveCount,
                          record: LegacyDataMigration.lastRecord,
                          pending: WelcomePending.load(pendingURL))
        guard let notice else { return nil }
        claimed = true
        // Once: a same-launch re-seed must not rebuild the file and drop the archive outcome `updateArchive` stored.
        if outcome != .nothing, WelcomePending.load(pendingURL) == nil { WelcomePending(notice).write(to: pendingURL) }
        followArchiveMove(LegacyArchiveMove.task, pendingURL: pendingURL)
        return notice
    }

    /// Stores the archive move's outcome in the pending file when the move ends (the panel was decided before it did).
    /// A closed panel has deleted the file by then: no-op.
    @MainActor static func followArchiveMove(_ task: Task<LegacyArchiveMove.Outcome, Never>?, pendingURL: URL) {
        guard let task else { return }
        Task { @MainActor in
            let outcome = await task.value
            WelcomePending.updateArchive(outcome, at: pendingURL)
        }
    }

    /// The window that claimed the notice went away before presenting it: the next window may claim it.
    @MainActor static func releaseClaim() { claimed = false }

    /// Amendment 4: written only when the user closes the panel («Later», «Done», Esc, after the exit animation), together with
    /// deleting the pending file. Cmd-Q, a crash or the Full Disk Access relaunch before that leave the flag unset and the
    /// panel comes back. Never under `-visualFixture`. The flag goes first: a crash between the two leaves an orphan file the
    /// flag outranks.
    @MainActor static func markShown(settings: AppSettings, pendingURL: URL) {
        guard !VisualFixture.isRequested else { return }
        settings.welcomeShown = true
        WelcomePending.delete(pendingURL)
    }
}

extension WelcomeActions {
    /// Snapshots and the `-fixtureLegacyNotice` window: no AppKit, no disk. A computed property because closures are not
    /// Sendable under Swift 6.
    @MainActor static var inert: WelcomeActions {
        WelcomeActions(quitOldApp: { true }, trash: { VisualFixture.legacyTrashedApp }, restore: { _ in },
                       openFullDiskAccess: {}, fullDiskAccess: { .notGranted }, archiveTask: { nil },
                       retryArchives: { nil }, reveal: { _, _ in })
    }

    /// The real actions of the panel (W3-W7). Every one runs on an explicit click, or (`fullDiskAccess`) on the panel's
    /// own app-became-active check. Nothing here can raise a TCC prompt.
    @MainActor static func live(notice: LegacyNotice) -> WelcomeActions {
        if VisualFixture.isRequested { return .inert }
        return WelcomeActions(
            quitOldApp: { await LegacyAppActions.quitOldApp() },
            trash: {
                guard let url = notice.oldApp else { throw CocoaError(.fileNoSuchFile) }
                return try LegacyApp.trash(.init(url: url))
            },
            restore: { trashed in
                guard let original = notice.oldApp else { throw CocoaError(.fileNoSuchFile) }
                try LegacyApp.restore(trashed: trashed, to: original)
            },
            openFullDiskAccess: { AdviceActionRunner.openPane(AdvicePanes.fullDiskAccess) },
            fullDiskAccess: {
                ProtectedLocations.fullDiskAccess(home: FileManager.default.homeDirectoryForCurrentUser.path,
                                                  probe: DirectoryAccess.probe)
            },
            archiveTask: { LegacyArchiveMove.task },
            retryArchives: {
                let t = LegacyArchiveMove.retryAfterAccessGranted()
                LegacyNotice.followArchiveMove(t, pendingURL: WelcomePending.defaultURL)
                return t
            },
            reveal: { urls, fallback in
                let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                if existing.isEmpty { AdviceActionRunner.reveal(fallback.path) }
                else { NSWorkspace.shared.activateFileViewerSelecting(existing) }
            })
    }
}
