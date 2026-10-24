// Views/SettingsWindow.swift
// REDESIGN-SETTINGS: the own Settings window (680×420, no system titlebar) and the app-wide theme apply.
import AppKit
import SwiftUI

/// REDESIGN-SETTINGS D1: the Settings window is an AppKit NSWindow whose content view IS 680×420 from the first frame;
/// the SwiftUI root has no hard frame (D4), so the `fixed-size-window-root` pair cannot form. Titlebar transparent and
/// title hidden (user decision 2026-10-24); traffic lights at AppKit's default place (D19).
@MainActor @Observable
final class SettingsWindowState {
    var section: SettingsSection
    init(section: SettingsSection = .general) { self.section = section }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    let state = SettingsWindowState()
    private var window: NSWindow?
    private var model: DashboardModel?
    private var glass: GlassSettings?

    func configure(model: DashboardModel, glass: GlassSettings) { self.model = model; self.glass = glass }

    func show(section: SettingsSection? = nil) {
        if let section { state.section = section }
        let first = window == nil
        let w = window ?? makeWindow()
        window = w
        w.title = L.settingsWindowTitle          // AX / Window menu only; not drawn
        if first { w.center() }
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        if let model { Task { await model.refreshClaudeBackup() } }   // D26
    }

    private func makeWindow() -> NSWindow {
        guard let model, let glass else { preconditionFailure("SettingsWindowController.configure(model:glass:) first") }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.isRestorable = false
        w.collectionBehavior.insert(.moveToActiveSpace)
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        let host = NSHostingView(rootView: SettingsView(model: model, state: state).environment(glass))
        host.sizingOptions = []          // the window owns the size, never the content
        host.safeAreaRegions = []        // no titlebar inset: the content region is the whole 680×420
        // The hosting view is NOT the window's contentView: as contentView it resizes the window to the root's ideal
        // size on every layout pass, and with `.fullSizeContentView` each pass adds the titlebar height (452, 484, 516, …)
        // until AppKit throws "more Update Constraints passes than views" (lldb, 2026-10-24). In a plain container the
        // window keeps the size it was created with.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 420))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        w.contentView = container
        return w
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
