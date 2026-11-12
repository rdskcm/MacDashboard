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
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Moonport"
    }
    static var shortVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    static var versionText: String { versionText(short: shortVersion, build: build) }
    /// Build suffix only when the short string does not already start with the build string (build_app.sh writes the same number into both).
    static func versionText(short: String, build: String) -> String { build.isEmpty || short.hasPrefix(build) ? short : "\(short) (\(build))" }
    /// The bundle ID `build_app.sh` writes (MOONPORT-RENAME). The literal lives here and in `build_app.sh` only.
    static let bundleID = "app.moonport"
    /// MacDashboard's bundle ID (up to 2.3.3): detection of the old app, the defaults-domain copy, the old cache folder. Never changes.
    static let legacyBundleID = "com.rdskcm.mac-dashboard"
    /// Name of the folder under Application Support (and under Documents, for kept archives).
    static let supportFolderName = "Moonport"
    static let legacySupportFolderName = "MacDashboard"
    /// The old app's name, for the migration and the one-time notice.
    static let legacyAppName = "MacDashboard"

    /// ~/Library/Application Support/Moonport — the report, history and caches folder (same derivation as `supportFolderURL(create:)`, without creating it).
    static var supportFolderURL: URL { supportFolderURL(create: false) }
    /// ~/Library/Application Support/MacDashboard — the folder the first Moonport launch moves away (`LegacyDataMigration`). Never created.
    static var legacySupportFolderURL: URL { applicationSupportBase(create: false).appendingPathComponent(legacySupportFolderName, isDirectory: true) }

    /// The support folder; with `create`, also made (0700) so callers can write into it. A failure to create it is not reported (callers fall back as before).
    static func supportFolderURL(create: Bool) -> URL {
        let dir = applicationSupportBase(create: create).appendingPathComponent(supportFolderName, isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        return dir
    }

    private static func applicationSupportBase(create: Bool) -> URL {
        let fm = FileManager.default
        return (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: create))
            ?? fm.homeDirectoryForCurrentUser
    }
}
