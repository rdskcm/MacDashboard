// Engine/Strings/Strings+Maintenance.swift
// Maintenance card and Autostart card: the `MaintenanceStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol MaintenanceStrings {
    // MARK: Maintenance card
    var maintenanceBrewNotInstalled: String { get }
    var maintenanceBrewVersionUnknown: String { get }
    var maintenanceBrewOutdatedCheckFailed: String { get }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String
    func maintenanceAndMore(_ n: Int) -> String
    func maintenanceBrewConfirmTitle(_ n: Int) -> String
    var maintenanceBrewConfirmButton: String { get }
    var maintenanceBrewUpgrading: String { get }
    func maintenanceBrewProgressDownloading(_ files: Int) -> String
    func maintenanceBrewProgressUpgrading(_ name: String, _ k: Int, _ n: Int, _ pct: Int) -> String
    func maintenanceBrewProgressUpgradingBare(_ name: String) -> String
    var maintenanceBrewUpgradeFailed: String { get }
    var maintenanceBrewStopButton: String { get }
    var maintenanceBrewStopA11y: String { get }
    var maintenanceBrewStopping: String { get }
    var maintenanceBrewRechecking: String { get }
    func maintenanceBrewStopped(_ upgraded: Int, _ total: Int) -> String
    var maintenanceBrewStoppedUnknown: String { get }
    var maintenanceOpenSoftwareUpdate: String { get }

    // MARK: Autostart card
    var autostartNoPermission: String { get }
    /// Detail for `autostartDeleteError` when a delete request contains no path the
    /// validator accepts — both the single-path guard and the bulk "nothing survived
    /// validation" case, which used to no-op silently (V2-POLISH B7).
    var autostartDeleteInvalidPath: String { get }
    /// Detail for `autostartDeleteError` when a bulk delete had more than one failure:
    /// how many of how many, plus the first failure's own (already localized) message.
    func autostartDeleteBulkFailure(_ failed: Int, _ total: Int, _ detail: String) -> String
    /// Curated one-line descriptions of well-known launchd labels, keyed by `Label` (System page). Both tables hold
    /// the same 29 keys; `EnglishFirstTests.launchdTablesHaveTheSameKeys` checks it.
    var autostartCuratedDescriptions: [String: String] { get }
    /// Heuristic description when the label has no vendor segment.
    var autostartBackgroundProcess: String { get }
    /// Heuristic description "<Vendor> — background process".
    func autostartVendorBackgroundProcess(_ vendor: String) -> String
}

extension StringsEN: MaintenanceStrings {
    // MARK: Maintenance card
    var maintenanceBrewNotInstalled: String { "not installed" }
    var maintenanceBrewVersionUnknown: String { "Homebrew is installed, but its version couldn't be determined" }
    var maintenanceBrewOutdatedCheckFailed: String { "Couldn't check for outdated packages — run brew outdated in Terminal" }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String { count > 1 ? "\(process) \u{00D7}\(count)" : process }
    func maintenanceAndMore(_ n: Int) -> String { "and \(n) more" }
    func maintenanceBrewConfirmTitle(_ n: Int) -> String { "Upgrade \(n) \(n == 1 ? "package" : "packages")?" }
    var maintenanceBrewConfirmButton: String { "Upgrade" }
    var maintenanceBrewUpgrading: String { "Upgrading packages… (may take a few minutes)" }
    func maintenanceBrewProgressDownloading(_ files: Int) -> String {
        "Downloading packages… (\(files) \(files == 1 ? "file" : "files") done)"
    }
    func maintenanceBrewProgressUpgrading(_ name: String, _ k: Int, _ n: Int, _ pct: Int) -> String {
        "Upgrading \(name)… \(k) of \(n) (\(pct)%)"
    }
    func maintenanceBrewProgressUpgradingBare(_ name: String) -> String { "Upgrading \(name)…" }
    var maintenanceBrewUpgradeFailed: String { "Package upgrade failed — run brew upgrade in Terminal" }
    var maintenanceBrewStopButton: String { "Stop" }
    var maintenanceBrewStopA11y: String { "Stop package upgrade" }
    var maintenanceBrewStopping: String { "Stopping the upgrade…" }
    var maintenanceBrewRechecking: String { "Checking what was upgraded…" }
    func maintenanceBrewStopped(_ upgraded: Int, _ total: Int) -> String {
        "Upgrade stopped: \(upgraded) of \(total) \(total == 1 ? "package" : "packages") upgraded"
    }
    var maintenanceBrewStoppedUnknown: String { "Upgrade stopped" }
    var maintenanceOpenSoftwareUpdate: String { "Open System Settings…" }

    // MARK: Autostart card
    var autostartNoPermission: String { "(no permission)" }
    var autostartDeleteInvalidPath: String { "the path is not a valid autostart plist" }
    func autostartDeleteBulkFailure(_ failed: Int, _ total: Int, _ detail: String) -> String {
        "\(failed) of \(total): \(detail)"
    }
    var autostartCuratedDescriptions: [String: String] { Self.autostartCuratedEN }
    var autostartBackgroundProcess: String { "Background process" }
    func autostartVendorBackgroundProcess(_ vendor: String) -> String { "\(vendor) — background process" }
}

extension StringsRU: MaintenanceStrings {
    // MARK: Maintenance card
    var maintenanceBrewNotInstalled: String { "не установлен" }
    var maintenanceBrewVersionUnknown: String { "Homebrew установлен, но версию определить не удалось" }
    var maintenanceBrewOutdatedCheckFailed: String { "Не удалось проверить устаревшие пакеты — запустите brew outdated в Терминале" }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String { count > 1 ? "\(process) \u{00D7}\(count)" : process }
    func maintenanceAndMore(_ n: Int) -> String { "и ещё \(n)" }
    func maintenanceBrewConfirmTitle(_ n: Int) -> String {
        "Обновить \(n) \(ruPlural(n, "пакет", "пакета", "пакетов"))?"
    }
    var maintenanceBrewConfirmButton: String { "Обновить" }
    var maintenanceBrewUpgrading: String { "Обновляем пакеты… (может занять несколько минут)" }
    func maintenanceBrewProgressDownloading(_ files: Int) -> String {
        "Скачиваем пакеты… (готово: \(files) \(ruPlural(files, "файл", "файла", "файлов")))"
    }
    func maintenanceBrewProgressUpgrading(_ name: String, _ k: Int, _ n: Int, _ pct: Int) -> String {
        "Обновляем \(name)… \(k) из \(n) (\(pct) %)"
    }
    func maintenanceBrewProgressUpgradingBare(_ name: String) -> String { "Обновляем \(name)…" }
    var maintenanceBrewUpgradeFailed: String { "Не удалось обновить пакеты — запустите brew upgrade в Терминале" }
    var maintenanceBrewStopButton: String { "Остановить" }
    var maintenanceBrewStopA11y: String { "Остановить обновление пакетов" }
    var maintenanceBrewStopping: String { "Останавливаем обновление…" }
    var maintenanceBrewRechecking: String { "Проверяем, что успело обновиться…" }
    func maintenanceBrewStopped(_ upgraded: Int, _ total: Int) -> String {
        "Обновление остановлено: обновлено \(upgraded) из \(total) \(ruPlural(total, "пакета", "пакетов", "пакетов"))"
    }
    var maintenanceBrewStoppedUnknown: String { "Обновление остановлено" }
    var maintenanceOpenSoftwareUpdate: String { "Открыть Системные настройки…" }

    // MARK: Autostart card
    var autostartNoPermission: String { "(нет разрешения)" }
    var autostartDeleteInvalidPath: String { "путь не похож на плист автозагрузки" }
    func autostartDeleteBulkFailure(_ failed: Int, _ total: Int, _ detail: String) -> String {
        "\(failed) из \(total): \(detail)"
    }
    var autostartCuratedDescriptions: [String: String] { Self.autostartCuratedRU }
    var autostartBackgroundProcess: String { "Фоновый процесс" }
    func autostartVendorBackgroundProcess(_ vendor: String) -> String { "\(vendor) — фоновый процесс" }
}

private extension StringsEN {
    static let autostartCuratedEN: [String: String] = [
    // Apple system agents/daemons
    "com.apple.cloudd": "iCloud — data sync",
    "com.apple.bird": "iCloud Drive — file sync",
    "com.apple.suggestd": "Spotlight — suggestions",
    "com.apple.AirPlayXPCHelper": "AirPlay — helper process",
    "com.apple.security.pboxd": "Sandbox — app privacy boxing",
    "com.apple.spindump": "Hang/crash diagnostics",
    "com.apple.softwareupdated": "macOS software updates",
    "com.apple.coreduetd": "CoreDuet — app usage prediction",
    "com.apple.photoanalysisd": "Photos — on-device analysis",
    "com.apple.mediaanalysisd": "Media analysis (photos/video)",
    "com.apple.corespotlightd": "Spotlight — indexing",
    "com.apple.spotlight.Siri": "Spotlight — Siri integration",
    "com.apple.familycircled": "Family Sharing",
    "com.apple.notificationcenterui.agent": "Notification Center",
    "com.apple.rapportd": "Handoff / Continuity",
    "com.apple.sharingd": "AirDrop / Sharing",
    "com.apple.parsecd": "Maps/Weather background data",
    "com.apple.commerce": "App Store — commerce background service",
    // Common third-party vendor agents
    "com.google.keystone.agent": "Google Keystone — Google app auto-update",
    "com.google.keystone.daemon": "Google Keystone — Google app auto-update",
    "com.microsoft.autoupdate.helper": "Microsoft AutoUpdate — Microsoft app updates",
    "com.microsoft.update.agent": "Microsoft AutoUpdate — Microsoft app updates",
    "com.docker.helper": "Docker Desktop — privileged helper",
    "com.docker.vmnetd": "Docker Desktop — VM networking daemon",
    "com.spotify.webhelper": "Spotify — web helper",
    "com.adobe.acc.installer.v2": "Adobe Creative Cloud — update installer",
    "com.adobe.ARMDC.Communicator": "Adobe — update service (ARM)",
    "com.valvesoftware.steamclean": "Steam — cache cleanup",
    "com.dropbox.DropboxMacUpdate.agent": "Dropbox — auto-update",
    ]
}

private extension StringsRU {
    static let autostartCuratedRU: [String: String] = [
    // Apple system agents/daemons
    "com.apple.cloudd": "iCloud — синхронизация данных",
    "com.apple.bird": "iCloud Drive — синхронизация файлов",
    "com.apple.suggestd": "Spotlight — предложения и рекомендации",
    "com.apple.AirPlayXPCHelper": "AirPlay — вспомогательный процесс",
    "com.apple.security.pboxd": "Sandbox — изоляция приложений (Privacy Sandbox)",
    "com.apple.spindump": "Диагностика зависаний процессов",
    "com.apple.softwareupdated": "Обновления macOS",
    "com.apple.coreduetd": "CoreDuet — предсказание использования приложений",
    "com.apple.photoanalysisd": "Фото — анализ и распознавание объектов",
    "com.apple.mediaanalysisd": "Медиа — анализ фото/видео",
    "com.apple.corespotlightd": "Spotlight — индексация",
    "com.apple.spotlight.Siri": "Spotlight — интеграция с Siri",
    "com.apple.familycircled": "Семейный доступ",
    "com.apple.notificationcenterui.agent": "Центр уведомлений",
    "com.apple.rapportd": "Handoff / Continuity",
    "com.apple.sharingd": "AirDrop / Общий доступ",
    "com.apple.parsecd": "Карты/погода — фоновые данные",
    "com.apple.commerce": "App Store — фоновая служба покупок",
    // Common third-party vendor agents
    "com.google.keystone.agent": "Google Keystone — автообновление Google-приложений",
    "com.google.keystone.daemon": "Google Keystone — автообновление Google-приложений",
    "com.microsoft.autoupdate.helper": "Microsoft AutoUpdate — обновление приложений Microsoft",
    "com.microsoft.update.agent": "Microsoft AutoUpdate — обновление приложений Microsoft",
    "com.docker.helper": "Docker Desktop — системный помощник",
    "com.docker.vmnetd": "Docker Desktop — сетевой демон виртуальных машин",
    "com.spotify.webhelper": "Spotify — веб-помощник",
    "com.adobe.acc.installer.v2": "Adobe Creative Cloud — установщик обновлений",
    "com.adobe.ARMDC.Communicator": "Adobe — служба обновлений (ARM)",
    "com.valvesoftware.steamclean": "Steam — очистка кэша",
    "com.dropbox.DropboxMacUpdate.agent": "Dropbox — автообновление",
    ]
}
