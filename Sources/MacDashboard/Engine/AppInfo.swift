// Engine/AppInfo.swift
// The app's own identity. Foundation only — compiled into Checks.
import Foundation

/// The single source of the user-visible app name.
///
/// Before V2-NAME-ONE the name existed twice: `CFBundleName` in the built
/// bundle (which the OS renders in the menu bar, the Settings window title and
/// the Processes list) and a localizable `appWindowTitle` string in the L10n
/// table (which the dashboard header rendered), so the same app introduced
/// itself under two different names on one screen. The name is a brand, not a
/// translatable phrase, so it lives in the Info.plist and nowhere else; the
/// literal below is only the fallback for running outside a bundle
/// (`swift run`, Checks), never a second source of truth.
enum AppInfo {
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "MacDashboard"
    }
}
