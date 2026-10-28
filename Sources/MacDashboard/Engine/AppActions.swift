// Engine/AppActions.swift
// ARCH-ENGINE-GUARD: the AppKit-side actions DashboardModel needs, as closures, so Engine stays Foundation-only.
// The app passes `AppActions.live` (AppShell.swift); tests and the harness scenarios keep the default `.none`.
import Foundation

struct AppActions {
    /// Opens a System Settings pane by URL (REDESIGN-STORAGE D14: Full Disk Access).
    var openSettingsPane: (String) -> Void
    /// Reopens the main window when a notification is clicked while no window is open (REDESIGN-NOTIFY R5).
    var ensureWindowShown: () -> Void

    static let none = AppActions(openSettingsPane: { _ in }, ensureWindowShown: {})
}
