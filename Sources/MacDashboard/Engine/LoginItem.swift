// Engine/LoginItem.swift
import Foundation
import ServiceManagement

/// REDESIGN-SETTINGS: «Launch at login» over SMAppService.mainApp. The system is the source of truth — nothing is
/// persisted in defaults; the view re-reads `status()` every time the Settings window is shown (D7).
enum LoginItem {
    enum Status: Equatable { case enabled, disabled, requiresApproval }
    static func status() -> Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled          // .notRegistered, .notFound
        }
    }
    /// Throws the SMAppService error (shown under the row as text).
    static func setEnabled(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
    static func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
