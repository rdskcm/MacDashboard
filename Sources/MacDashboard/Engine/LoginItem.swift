// Engine/LoginItem.swift
import Foundation
import ServiceManagement

/// REDESIGN-SETTINGS: «Launch at login» over SMAppService.mainApp. The system is the source of truth — nothing is
/// persisted in defaults; the view re-reads `status()` every time the Settings window is shown (D7).
enum LoginItem {
    enum Status: Equatable { case enabled, disabled, requiresApproval }

    /// -visualFixture / snapshot tests: when non-nil, `status()` answers this and `setEnabled` only updates it, never
    /// touching SMAppService. Unset under fixture means `.enabled` (ARCH-ENGINE-GUARD: the branch left SettingsView).
    static var fixtureStatus: Status? {
        get { fixtureStatusOverride ?? (VisualFixture.isRequested ? .enabled : nil) }
        set { fixtureStatusOverride = newValue }
    }
    private static var fixtureStatusOverride: Status?

    static func status() -> Status {
        if let fixed = fixtureStatus { return fixed }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled          // .notRegistered, .notFound
        }
    }
    /// Throws the SMAppService error (shown under the row as text).
    static func setEnabled(_ on: Bool) throws {
        if fixtureStatus != nil { fixtureStatusOverride = on ? .enabled : .disabled; return }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
    static func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
