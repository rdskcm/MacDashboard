// Engine/Advice.swift
// A clickable follow-up for an assessment row: what the Рекомендации card should DO
// when the user clicks the recommendation. Foundation-only — compiled into Checks.
import Foundation

/// All x-apple.systempreferences URLs and app paths below were empirically verified
/// on this machine (macOS 26) on 2026-07-17.
enum AdviceAction: Equatable {
    case settingsPane(String)   // x-apple.systempreferences:… URL
    case openApp(String)        // absolute .app path
    case revealPath(String)     // show in Finder (absolute path)
    case emptyTrash             // UI: confirmation → Finder empty trash
    case enableFirewall         // UI: confirmation → PrivilegedRunner
    case brewUpgrade            // UI: DashboardModel.upgradeBrewNow()
}

enum AdvicePanes {
    static let storage        = "x-apple.systempreferences:com.apple.settings.Storage"
    static let battery        = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
    static let privacySecurity = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    static let fileVault      = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault"
    static let softwareUpdate = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
    static let timeMachine    = "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"
    /// The classic pane id + `?Privacy_AllFiles` anchor — the form that lands on
    /// Full Disk Access itself rather than the Privacy & Security root.
    static let fullDiskAccess = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
}

enum AdviceApps {
    static let activityMonitor = "/System/Applications/Utilities/Activity Monitor.app"
    static let diskUtility     = "/System/Applications/Utilities/Disk Utility.app"
}
