// Engine/LaunchdPlistInspector.swift
// Pure parsing/inspection of launchd .plist files (LaunchAgents/LaunchDaemons):
// resolves the executable a plist points at, decides whether that executable is
// orphaned (its backing app/binary was removed), and attaches a short human-readable
// description of the agent (curated dictionary, falling back to a reverse-DNS
// heuristic). Foundation-only — also compiled into Checks.
import Foundation

/// Everything the UI needs to render one launchd plist row.
struct LaunchdPlistInfo: Equatable {
    var path: String
    var label: String?
    var executablePath: String?
    var isOrphan: Bool
    var description: String?
}

/// Outcome of one plist delete attempt. Hoisted out of `DashboardModel` (where
/// it used to be declared twice, locally inside two `Task` bodies) so the
/// "which paths must come back" rule below is pure and Checks-covered.
enum PlistDeleteOutcome: Equatable {
    case success
    case cancelled
    case failed(String)
}

/// The Автозагрузка card collapses an orphan row the instant the user confirms,
/// before the Trash/`rm` has run (deliberate — see `OrphanRow.onConfirm`). This
/// is the counter-signal: paths whose delete did NOT happen, so the card can put
/// exactly those rows back. ACCUMULATING: `DashboardModel` unions new paths in
/// and the card drains them via `acknowledgePlistRestore(_:)`, so two deletes
/// finishing inside one SwiftUI update cycle cannot lose each other's paths.
/// `stamp` is bumped on every publish so two identical path sets in a row are
/// still two distinct values for the card's `.onChange`.
struct PlistDeleteRestoreSignal: Equatable {
    var paths: Set<String> = []
    var stamp: Int = 0
}

enum LaunchdPlistInspector {

    // MARK: - A. Parsing

    /// Extracts `Label` from a decoded plist dictionary.
    static func label(from dict: [String: Any]) -> String? {
        dict["Label"] as? String
    }

    /// Resolves the executable a plist points at, checking `Program`, then
    /// `ProgramArguments[0]`, then `BundleProgram`, in that priority order.
    static func executablePath(from dict: [String: Any]) -> String? {
        if let program = dict["Program"] as? String, !program.isEmpty {
            return program
        }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first, !first.isEmpty {
            return first
        }
        if let bundleProgram = dict["BundleProgram"] as? String, !bundleProgram.isEmpty {
            return bundleProgram
        }
        return nil
    }

    /// Decodes raw plist `Data` (binary or XML) into a `[String: Any]` dictionary.
    /// Returns nil if the data isn't a valid property list or isn't dictionary-rooted.
    static func decode(plistData: Data) -> [String: Any]? {
        guard let obj = try? PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil) else { return nil }
        return obj as? [String: Any]
    }

    // MARK: - B. Orphan detection

    /// A plist is orphaned if it has no resolvable executable, or that executable no
    /// longer exists on disk. Deleting an app removes everything under its `.app`
    /// bundle, so a plain existence check on the resolved executable path already
    /// covers the "app was uninstalled" case.
    static func isOrphan(executablePath: String?) -> Bool {
        guard let path = executablePath, !path.isEmpty else { return true }
        return !FileManager.default.fileExists(atPath: path)
    }

    // MARK: - C. Curated descriptions

    /// Short one-line descriptions for well-known launchd labels, keyed by `Label`.
    static let curatedDescriptions: [String: (ru: String, en: String)] = [
        // Apple system agents/daemons
        "com.apple.cloudd": ("iCloud — синхронизация данных", "iCloud — data sync"),
        "com.apple.bird": ("iCloud Drive — синхронизация файлов", "iCloud Drive — file sync"),
        "com.apple.suggestd": ("Spotlight — предложения и рекомендации", "Spotlight — suggestions"),
        "com.apple.AirPlayXPCHelper": ("AirPlay — вспомогательный процесс", "AirPlay — helper process"),
        "com.apple.security.pboxd": ("Sandbox — изоляция приложений (Privacy Sandbox)", "Sandbox — app privacy boxing"),
        "com.apple.spindump": ("Диагностика зависаний процессов", "Hang/crash diagnostics"),
        "com.apple.softwareupdated": ("Обновления macOS", "macOS software updates"),
        "com.apple.coreduetd": ("CoreDuet — предсказание использования приложений", "CoreDuet — app usage prediction"),
        "com.apple.photoanalysisd": ("Фото — анализ и распознавание объектов", "Photos — on-device analysis"),
        "com.apple.mediaanalysisd": ("Медиа — анализ фото/видео", "Media analysis (photos/video)"),
        "com.apple.corespotlightd": ("Spotlight — индексация", "Spotlight — indexing"),
        "com.apple.spotlight.Siri": ("Spotlight — интеграция с Siri", "Spotlight — Siri integration"),
        "com.apple.familycircled": ("Семейный доступ", "Family Sharing"),
        "com.apple.notificationcenterui.agent": ("Центр уведомлений", "Notification Center"),
        "com.apple.rapportd": ("Handoff / Continuity", "Handoff / Continuity"),
        "com.apple.sharingd": ("AirDrop / Общий доступ", "AirDrop / Sharing"),
        "com.apple.parsecd": ("Карты/погода — фоновые данные", "Maps/Weather background data"),
        "com.apple.commerce": ("App Store — фоновая служба покупок", "App Store — commerce background service"),
        // Common third-party vendor agents
        "com.google.keystone.agent": ("Google Keystone — автообновление Google-приложений", "Google Keystone — Google app auto-update"),
        "com.google.keystone.daemon": ("Google Keystone — автообновление Google-приложений", "Google Keystone — Google app auto-update"),
        "com.microsoft.autoupdate.helper": ("Microsoft AutoUpdate — обновление приложений Microsoft", "Microsoft AutoUpdate — Microsoft app updates"),
        "com.microsoft.update.agent": ("Microsoft AutoUpdate — обновление приложений Microsoft", "Microsoft AutoUpdate — Microsoft app updates"),
        "com.docker.helper": ("Docker Desktop — системный помощник", "Docker Desktop — privileged helper"),
        "com.docker.vmnetd": ("Docker Desktop — сетевой демон виртуальных машин", "Docker Desktop — VM networking daemon"),
        "com.spotify.webhelper": ("Spotify — веб-помощник", "Spotify — web helper"),
        "com.adobe.acc.installer.v2": ("Adobe Creative Cloud — установщик обновлений", "Adobe Creative Cloud — update installer"),
        "com.adobe.ARMDC.Communicator": ("Adobe — служба обновлений (ARM)", "Adobe — update service (ARM)"),
        "com.valvesoftware.steamclean": ("Steam — очистка кэша", "Steam — cache cleanup"),
        "com.dropbox.DropboxMacUpdate.agent": ("Dropbox — автообновление", "Dropbox — auto-update"),
    ]

    // MARK: - D. Heuristic fallback

    /// Derives a human-readable guess from a reverse-DNS launchd label when it isn't
    /// present in `curatedDescriptions`, e.g. "com.adobe.acrobat.helper" -> vendor
    /// "Adobe" -> "Adobe — фоновый процесс" / "Adobe — background process".
    static func heuristicDescription(forLabel label: String, language: AppLanguage) -> String {
        var components = label.split(separator: ".").map(String.init)
        for prefix in ["com", "org", "net"] where components.first == prefix {
            components.removeFirst()
            break
        }
        guard let vendorRaw = components.first, !vendorRaw.isEmpty else {
            return language == .ru ? "Фоновый процесс" : "Background process"
        }
        let vendor = vendorRaw.prefix(1).uppercased() + vendorRaw.dropFirst()
        return language == .ru ? "\(vendor) — фоновый процесс" : "\(vendor) — background process"
    }

    /// Looks up a description for `label`: curated dictionary first, heuristic
    /// fallback otherwise. Returns nil if `label` itself is nil.
    static func description(forLabel label: String?, language: AppLanguage) -> String? {
        guard let label = label, !label.isEmpty else { return nil }
        if let curated = curatedDescriptions[label] {
            return language == .ru ? curated.ru : curated.en
        }
        return heuristicDescription(forLabel: label, language: language)
    }

    // MARK: - E. Public entry point

    /// Parses `plistData`, resolves its executable, checks orphan status and attaches
    /// a description, tying A–D together into one `LaunchdPlistInfo`.
    static func inspect(plistPath: String, plistData: Data, language: AppLanguage) -> LaunchdPlistInfo {
        let dict = decode(plistData: plistData) ?? [:]
        let plistLabel = label(from: dict)
        let execPath = executablePath(from: dict)
        return LaunchdPlistInfo(
            path: plistPath,
            label: plistLabel,
            executablePath: execPath,
            isOrphan: isOrphan(executablePath: execPath),
            description: description(forLabel: plistLabel, language: language))
    }

    // MARK: - F. Deletion-target validation

    /// Defense-in-depth check before `deleteOrphanPlist` acts on `path`: it must be a
    /// `.plist` file lexically inside the directory `isSystemLevel` claims it's in.
    /// Lexical only (no filesystem access, `.plist` and NSString path standardization
    /// only) so it stays pure and Checks-testable — the paths this app ever passes here
    /// come from its own directory scan of the three fixed launchd directories, not from
    /// untrusted input, but a cheap guard here is worth it given the system-level branch
    /// runs a privileged `rm -f`.
    static func isValidDeletionTarget(path: String, isSystemLevel: Bool) -> Bool {
        guard (path as NSString).pathExtension.lowercased() == "plist" else { return false }
        let standardized = (path as NSString).standardizingPath
        if isSystemLevel {
            return standardized.hasPrefix("/Library/LaunchAgents/")
                || standardized.hasPrefix("/Library/LaunchDaemons/")
        } else {
            let userDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents") + "/"
            return standardized.hasPrefix(userDir)
        }
    }

    // MARK: - G. Optimistic-delete restore (V2-DESTRUCTIVE-UX)

    /// Paths whose delete did not happen, given one batch's results: everything
    /// that is not `.success`. A mixed batch — user-level plists trashed fine,
    /// the single system-level `rm` cancelled at the password prompt — must
    /// restore exactly the system-level paths and leave the rest deleted.
    static func pathsNotDeleted(results: [(path: String, outcome: PlistDeleteOutcome)]) -> Set<String> {
        Set(results.compactMap { $0.outcome == .success ? nil : $0.path })
    }

    /// Re-inserts `restoring` into the card's display list at the position each
    /// path holds in `canonical` (the model's real orphan list). Preserves the
    /// existing order of `display` exactly — rows still playing a collapse are
    /// not reordered — by inserting each restored row directly after the nearest
    /// preceding canonical path that is already present (front of the list if
    /// there is none). Paths already displayed are left alone (no duplicates);
    /// paths absent from `canonical` are NOT resurrected (the plist really is
    /// gone, e.g. a report refresh already dropped it).
    static func restoredOrphanList(display: [LaunchdPlistInfo],
                                   restoring: Set<String>,
                                   canonical: [LaunchdPlistInfo]) -> [LaunchdPlistInfo] {
        guard !restoring.isEmpty else { return display }
        var result = display
        let displayed = Set(display.map(\.path))
        for (index, info) in canonical.enumerated()
        where restoring.contains(info.path) && !displayed.contains(info.path) {
            var insertAt = 0
            for predecessor in canonical[..<index].reversed() {
                if let idx = result.firstIndex(where: { $0.path == predecessor.path }) {
                    insertAt = idx + 1
                    break
                }
            }
            result.insert(info, at: insertAt)
        }
        return result
    }
}
