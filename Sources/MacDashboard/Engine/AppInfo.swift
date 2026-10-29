// Engine/AppInfo.swift
// The app's own identity. Foundation only — covered by Tests/MacDashboardTests.
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
    static var shortVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    static var versionText: String { versionText(short: shortVersion, build: build) }
    /// Build suffix only when the short string does not already start with the build string (build_app.sh writes the same number into both).
    static func versionText(short: String, build: String) -> String { build.isEmpty || short.hasPrefix(build) ? short : "\(short) (\(build))" }
    /// ~/Library/Application Support/MacDashboard — the report, history and caches folder (same derivation as `AppModel.defaultReportURL()` / `IPhoneStore.defaultURL()`, without creating it).
    static var supportFolderURL: URL { ((try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent("MacDashboard", isDirectory: true) }
}
