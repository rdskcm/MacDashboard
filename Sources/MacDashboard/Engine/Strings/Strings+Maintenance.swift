// Engine/Strings/Strings+Maintenance.swift
// Maintenance card and Autostart card: the `MaintenanceStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol MaintenanceStrings {
    // MARK: Maintenance card
    var maintenanceBrewNotInstalled: String { get }
    var maintenanceBrewVersionUnknown: String { get }
    var maintenanceBrewOutdatedCheckFailed: String { get }
    var maintenanceUpdatesTip: String { get }
    var maintenanceCrashesTip: String { get }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String
    func maintenanceCrashRevealA11y(_ process: String) -> String
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
}

extension StringsEN: MaintenanceStrings {
    // MARK: Maintenance card
    var maintenanceBrewNotInstalled: String { "not installed" }
    var maintenanceBrewVersionUnknown: String { "Homebrew is installed, but its version couldn't be determined" }
    var maintenanceBrewOutdatedCheckFailed: String { "Couldn't check for outdated packages — run brew outdated in Terminal" }
    var maintenanceUpdatesTip: String { "Pending macOS and App Store updates." }
    var maintenanceCrashesTip: String { "Crash reports macOS recorded in the last 7 days." }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String { count > 1 ? "\(process) \u{00D7}\(count)" : process }
    func maintenanceCrashRevealA11y(_ process: String) -> String { "Show \(process) crash reports in Finder" }
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
}

extension StringsRU: MaintenanceStrings {
    // MARK: Maintenance card
    var maintenanceBrewNotInstalled: String { "не установлен" }
    var maintenanceBrewVersionUnknown: String { "Homebrew установлен, но версию определить не удалось" }
    var maintenanceBrewOutdatedCheckFailed: String { "Не удалось проверить устаревшие пакеты — запустите brew outdated в Терминале" }
    var maintenanceUpdatesTip: String { "Ожидающие обновления macOS и App Store." }
    var maintenanceCrashesTip: String { "Отчёты о падениях приложений за последние 7 дней." }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String { count > 1 ? "\(process) \u{00D7}\(count)" : process }
    func maintenanceCrashRevealA11y(_ process: String) -> String { "Показать отчёты о падениях «\(process)» в Finder" }
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
}
