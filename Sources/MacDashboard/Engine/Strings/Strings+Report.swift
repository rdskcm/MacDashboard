// Engine/Strings/Strings+Report.swift
// Report tab, report text and report collector: the `ReportStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol ReportStrings {
    // MARK: Report tab
    var reportPlaceholder: String { get }
    var reportShowInFinder: String { get }
    var reportCopy: String { get }
    var reportCollecting: String { get }
    func reportFileUpdatedCaption(_ time: String) -> String
    var reportCopied: String { get }
    var reportNotUpdated: String { get }
    func reportNotUpdatedShowing(_ time: String) -> String
    var reportFailedTimedOut: String { get }
    var reportFailedNoReading: String { get }

    // MARK: Report text
    func reportTitle(_ model: String) -> String
    func reportGenerated(_ dateTime: String, _ os: String) -> String
    func reportGeneratedNoOS(_ dateTime: String) -> String
    var reportKeyStatus: String { get }
    var reportKeyCPU: String { get }
    var reportKeyMemory: String { get }
    var reportKeyStorage: String { get }
    var reportKeyBattery: String { get }
    var reportKeySecurity: String { get }
    var reportKeyBackups: String { get }
    var reportKeyUptime: String { get }
    func reportStorageFree(_ free: String, _ total: String) -> String
    func reportPurgeable(_ v: String) -> String
    func reportCapacity(_ v: String) -> String
    func reportCycles(_ n: Int) -> String
    var reportFirewall: String { get }
    var reportOff: String { get }
    func reportLocalSnapshots(_ n: Int) -> String

    var reportSectionSystem: String { get }
    var reportSectionDisk: String { get }
    var reportSectionSnapshots: String { get }
    var reportSectionHomeDirs: String { get }
    var reportSectionServiceDirs: String { get }
    var reportSectionMemory: String { get }
    var reportSectionTopMem: String { get }
    var reportSectionTopCPU: String { get }
    var reportSectionLoginItems: String { get }
    var reportSectionAgents: String { get }
    var reportSectionBackground: String { get }
    var reportSectionBattery: String { get }
    var reportSectionEnergy: String { get }
    var reportSectionSecurity: String { get }
    var reportSectionTMDest: String { get }
    var reportSectionCrashes: String { get }
    var reportSectionUpdates: String { get }
    var reportSectionSmart: String { get }
    var reportSectionUnparsed: String { get }
    var reportUnparsedHint: String { get }
    func reportUnparsedMoreLines(_ n: Int) -> String
    var reportNone: String { get }
    func reportUptime(_ v: String) -> String
    var reportAgentsUserHeader: String { get }
    var reportEmpty: String { get }
    var reportAgentsSystemHeader: String { get }
    var reportNoBattery: String { get }
    func reportBatterySource(_ v: String) -> String
    func reportBatteryCharge(_ v: String) -> String
    func reportBatteryState(_ v: String) -> String
    var reportTMNotChecked: String { get }
    var reportTMNotConfigured: String { get }
    func reportTMLastBackup(_ v: String) -> String
    var reportNotChecked: String { get }
    var reportSectionTimings: String { get }
    var reportTimingsNote: String { get }
    func reportTimingsPass(_ v: String) -> String
    func reportTimingsUpdates(_ v: String, _ at: String) -> String
    func reportUpdatesCheckedAt(_ at: String) -> String
    var updatesCheckedJustNow: String { get }
    func updatesCheckedAgo(_ age: String) -> String
    func reportTimingsFolderSizes(_ v: String, _ at: String) -> String
    /// Short name of a report section for the COLLECTION TIMES list.
    func reportTimingsSectionName(_ s: ReportSection) -> String
    func reportFoldersCountedAt(_ at: String) -> String
    func foldersCountedAgo(_ age: String) -> String
    var foldersCountedJustNow: String { get }
    var reportBrewOutdatedHeader: String { get }
    func reportSmartDiskLine(_ title: String, _ device: String, _ status: String) -> String
    var reportSmartWarningNone: String { get }
    var reportSmartWarningLowSpareCapacity: String { get }
    var reportSmartWarningCriticalTemp: String { get }
    var reportSmartWarningReliabilityDegraded: String { get }
    var reportSmartWarningReadOnlyMode: String { get }
    var reportSmartWarningBackupPowerFail: String { get }
    var reportSmartWarningPersistentMemoryReadOnly: String { get }
    func reportSmartWarningGeneric(_ hex: String) -> String

    // MARK: Report collector
    var reportCollectorNoBackupsYet: String { get }
    var reportCollectorDiskNotConnected: String { get }
    var reportCollectorNoCompletedBackups: String { get }
    var reportCollectorDateUnavailableNoFDA: String { get }
    var reportCollectorSpotlightEnabled: String { get }
    var reportCollectorSpotlightDisabled: String { get }
    var reportCollectorInternalDiskFallbackTitle: String { get }
    var reportCollectorSmartOkVerified: String { get }
    var reportCollectorSmartNotSupported: String { get }
    var reportCollectorSmartStatusUnavailable: String { get }
    var reportCollectorSmartMediaErrors: String { get }
    var reportCollectorSmartWearHigh: String { get }
    var reportCollectorSmartUnavailable: String { get }
    var reportCollectorSmartUnavailableNoTools: String { get }
}

extension StringsEN: ReportStrings {
    // MARK: Report tab
    var reportPlaceholder: String { "Report not generated yet. Click “Refresh report”." }
    var reportShowInFinder: String { "Show in Finder" }
    var reportCopy: String { "Copy" }
    var reportCollecting: String { "Generating report…" }
    func reportFileUpdatedCaption(_ time: String) -> String { "mac_report.txt · updated \(time)" }
    var reportCopied: String { "Copied ✓" }
    var reportNotUpdated: String { "not updated" }
    func reportNotUpdatedShowing(_ time: String) -> String { "not updated · showing the \(time) report" }
    var reportFailedTimedOut: String { "Couldn’t generate the report: system_profiler didn’t respond within 30 s." }
    var reportFailedNoReading: String { "Couldn’t generate the report: system_profiler returned no data." }

    // MARK: Report text
    func reportTitle(_ model: String) -> String { "MacDashboard report — \(model)" }
    func reportGenerated(_ dateTime: String, _ os: String) -> String { "Generated \(dateTime) · \(os)" }
    func reportGeneratedNoOS(_ dateTime: String) -> String { "Generated \(dateTime)" }
    var reportKeyStatus: String { "STATUS" }
    var reportKeyCPU: String { "CPU" }
    var reportKeyMemory: String { "MEMORY" }
    var reportKeyStorage: String { "STORAGE" }
    var reportKeyBattery: String { "BATTERY" }
    var reportKeySecurity: String { "SECURITY" }
    var reportKeyBackups: String { "BACKUPS" }
    var reportKeyUptime: String { "UPTIME" }
    func reportStorageFree(_ free: String, _ total: String) -> String { "\(free) of \(total) free" }
    func reportPurgeable(_ v: String) -> String { "purgeable \(v)" }
    func reportCapacity(_ v: String) -> String { "capacity \(v)" }
    func reportCycles(_ n: Int) -> String { n == 1 ? "1 cycle" : "\(n) cycles" }
    var reportFirewall: String { "Firewall" }
    var reportOff: String { "off" }
    func reportLocalSnapshots(_ n: Int) -> String { n == 1 ? "1 local snapshot" : "\(n) local snapshots" }
    var reportSectionSystem: String { "SYSTEM" }
    var reportSectionDisk: String { "DISK" }
    var reportSectionSnapshots: String { "LOCAL TIME MACHINE SNAPSHOTS" }
    var reportSectionHomeDirs: String { "HOME FOLDER: what's taking up space (top 20)" }
    var reportSectionServiceDirs: String { "LARGE SERVICE FOLDERS" }
    var reportSectionMemory: String { "MEMORY" }
    var reportSectionTopMem: String { "TOP 10 PROCESSES BY MEMORY" }
    var reportSectionTopCPU: String { "TOP 10 PROCESSES BY CPU" }
    var reportSectionLoginItems: String { "STARTUP: Login Items" }
    var reportSectionAgents: String { "STARTUP: LaunchAgents / LaunchDaemons" }
    var reportSectionBackground: String { "BACKGROUND TASKS (non-Apple)" }
    var reportSectionBattery: String { "BATTERY" }
    var reportSectionEnergy: String { "ENERGY SETTINGS" }
    var reportSectionSecurity: String { "SECURITY" }
    var reportSectionTMDest: String { "TIME MACHINE: backup destination" }
    var reportSectionCrashes: String { "RECENT APP CRASHES" }
    var reportSectionUpdates: String { "macOS UPDATES" }
    var reportSectionSmart: String { "EXTERNAL AND INTERNAL DISKS: SMART" }
    var reportSectionUnparsed: String { "UNRECOGNISED COMMAND OUTPUT (first lines)" }
    var reportUnparsedHint: String { "MacDashboard could not read the output of these commands. Serial numbers and UUIDs are masked; attach this block to a bug report." }
    func reportUnparsedMoreLines(_ n: Int) -> String { "(+\(n) more lines not shown)" }
    var reportNone: String { "(none)" }
    func reportUptime(_ v: String) -> String { "Uptime: \(v)" }
    var reportAgentsUserHeader: String { "--- User:" }
    var reportEmpty: String { "(empty)" }
    var reportAgentsSystemHeader: String { "--- System (third-party):" }
    var reportNoBattery: String { "no battery (desktop Mac)" }
    func reportBatterySource(_ v: String) -> String { "Power source: \(v)" }
    func reportBatteryCharge(_ v: String) -> String { "Charge: \(v)" }
    func reportBatteryState(_ v: String) -> String { "State: \(v)" }
    var reportTMNotChecked: String { "(not checked)" }
    var reportTMNotConfigured: String { "(not configured)" }
    func reportTMLastBackup(_ v: String) -> String { "Last backup: \(v)" }
    var reportNotChecked: String { "(not checked)" }
    var reportSectionTimings: String { "COLLECTION TIMES" }
    var reportTimingsNote: String { "Sections are collected concurrently, so their times overlap." }
    func reportTimingsPass(_ v: String) -> String { "Whole pass: \(v)" }
    func reportTimingsUpdates(_ v: String, _ at: String) -> String { "macOS updates (background check at \(at)): \(v)" }
    func reportUpdatesCheckedAt(_ at: String) -> String { "(checked \(at))" }
    var updatesCheckedJustNow: String { "checked just now" }
    func updatesCheckedAgo(_ age: String) -> String { "checked \(age) ago" }
    func reportTimingsFolderSizes(_ v: String, _ at: String) -> String { "Folder sizes (background count at \(at)): \(v)" }
    func reportTimingsSectionName(_ s: ReportSection) -> String {
        switch s {
        case .system: return "System"
        case .snapshots: return "Local snapshots"
        case .homeDirs: return "Home folder"
        case .serviceDirs: return "Service folders"
        case .security: return "Security"
        case .tmDest: return "Time Machine"
        case .spotlight: return "Spotlight"
        case .crashes: return "Crashes"
        case .brew: return "Homebrew"
        case .updates: return "macOS updates"
        case .autostart: return "Startup items"
        case .smart: return "SMART"
        case .energy: return "Energy settings"
        case .battery: return "Battery"
        }
    }
    func reportFoldersCountedAt(_ at: String) -> String { "(counted \(at))" }
    func foldersCountedAgo(_ age: String) -> String { "counted \(age) ago" }
    var foldersCountedJustNow: String { "counted just now" }
    var reportBrewOutdatedHeader: String { "Outdated packages:" }
    func reportSmartDiskLine(_ title: String, _ device: String, _ status: String) -> String {
        "\(title) (\(device)) — status: \(status)"
    }
    var reportSmartWarningNone: String { "None" }
    var reportSmartWarningLowSpareCapacity: String { "low spare capacity" }
    var reportSmartWarningCriticalTemp: String { "critical temperature" }
    var reportSmartWarningReliabilityDegraded: String { "reliability degraded" }
    var reportSmartWarningReadOnlyMode: String { "read-only mode" }
    var reportSmartWarningBackupPowerFail: String { "backup power failure" }
    var reportSmartWarningPersistentMemoryReadOnly: String { "persistent memory read-only" }
    func reportSmartWarningGeneric(_ hex: String) -> String { "Warning present (\(hex))" }

    // MARK: Report collector
    var reportCollectorNoBackupsYet: String { "no backups yet" }
    var reportCollectorDiskNotConnected: String { "disk not connected" }
    var reportCollectorNoCompletedBackups: String { "no completed backups" }
    var reportCollectorDateUnavailableNoFDA: String { "date unavailable (no Full Disk Access)" }
    var reportCollectorSpotlightEnabled: String { "Indexing enabled" }
    var reportCollectorSpotlightDisabled: String { "Indexing disabled" }
    var reportCollectorInternalDiskFallbackTitle: String { "Internal drive" }
    var reportCollectorSmartOkVerified: String { "SMART: OK (verified)" }
    var reportCollectorSmartNotSupported: String { "SMART not supported" }
    var reportCollectorSmartStatusUnavailable: String { "SMART: status unavailable" }
    var reportCollectorSmartMediaErrors: String { "SMART: media errors" }
    var reportCollectorSmartWearHigh: String { "SMART: wear nearing end of life" }
    var reportCollectorSmartUnavailable: String { "SMART unavailable" }
    var reportCollectorSmartUnavailableNoTools: String { "SMART unavailable (no smartmontools)" }
}

extension StringsRU: ReportStrings {
    // MARK: Report tab
    var reportPlaceholder: String { "Отчёт ещё не собран. Нажмите «Обновить отчёт»." }
    var reportShowInFinder: String { "Показать в Finder" }
    var reportCopy: String { "Скопировать" }
    var reportCollecting: String { "Создание отчёта…" }
    func reportFileUpdatedCaption(_ time: String) -> String { "mac_report.txt · обновлён в \(time)" }
    var reportCopied: String { "Скопировано ✓" }
    var reportNotUpdated: String { "не обновлён" }
    func reportNotUpdatedShowing(_ time: String) -> String { "не обновлён · показан отчёт от \(time)" }
    var reportFailedTimedOut: String { "Не удалось создать отчёт: system_profiler не ответил за 30 с." }
    var reportFailedNoReading: String { "Не удалось создать отчёт: system_profiler не вернул данных." }

    // MARK: Report text
    func reportTitle(_ model: String) -> String { "Отчёт MacDashboard — \(model)" }
    func reportGenerated(_ dateTime: String, _ os: String) -> String { "Создан \(dateTime) · \(os)" }
    func reportGeneratedNoOS(_ dateTime: String) -> String { "Создан \(dateTime)" }
    var reportKeyStatus: String { "СОСТОЯНИЕ" }
    var reportKeyCPU: String { "ПРОЦЕССОР" }
    var reportKeyMemory: String { "ПАМЯТЬ" }
    var reportKeyStorage: String { "ХРАНИЛИЩЕ" }
    var reportKeyBattery: String { "БАТАРЕЯ" }
    var reportKeySecurity: String { "ЗАЩИТА" }
    var reportKeyBackups: String { "КОПИИ" }
    var reportKeyUptime: String { "АПТАЙМ" }
    func reportStorageFree(_ free: String, _ total: String) -> String { "свободно \(free) из \(total)" }
    func reportPurgeable(_ v: String) -> String { "очищаемое \(v)" }
    func reportCapacity(_ v: String) -> String { "ёмкость \(v)" }
    func reportCycles(_ n: Int) -> String { "\(n) " + ruPlural(n, "цикл", "цикла", "циклов") }
    var reportFirewall: String { "брандмауэр" }
    var reportOff: String { "выкл." }
    func reportLocalSnapshots(_ n: Int) -> String { "\(n) " + ruPlural(n, "локальный снимок", "локальных снимка", "локальных снимков") }
    var reportSectionSystem: String { "СИСТЕМА" }
    var reportSectionDisk: String { "ДИСК" }
    var reportSectionSnapshots: String { "ЛОКАЛЬНЫЕ СНАПШОТЫ TIME MACHINE" }
    var reportSectionHomeDirs: String { "ДОМАШНЯЯ ПАПКА: что занимает место (топ-20)" }
    var reportSectionServiceDirs: String { "ТЯЖЁЛЫЕ СЛУЖЕБНЫЕ ПАПКИ" }
    var reportSectionMemory: String { "ПАМЯТЬ" }
    var reportSectionTopMem: String { "ТОП-10 ПРОЦЕССОВ ПО ПАМЯТИ" }
    var reportSectionTopCPU: String { "ТОП-10 ПРОЦЕССОВ ПО CPU" }
    var reportSectionLoginItems: String { "АВТОЗАГРУЗКА: Login Items" }
    var reportSectionAgents: String { "АВТОЗАГРУЗКА: LaunchAgents / LaunchDaemons" }
    var reportSectionBackground: String { "ФОНОВЫЕ ЗАДАЧИ (не Apple)" }
    var reportSectionBattery: String { "БАТАРЕЯ" }
    var reportSectionEnergy: String { "НАСТРОЙКИ ЭНЕРГИИ" }
    var reportSectionSecurity: String { "БЕЗОПАСНОСТЬ" }
    var reportSectionTMDest: String { "TIME MACHINE: куда бэкапится" }
    var reportSectionCrashes: String { "НЕДАВНИЕ КРАШИ ПРОГРАММ" }
    var reportSectionUpdates: String { "ОБНОВЛЕНИЯ macOS" }
    var reportSectionSmart: String { "ВНЕШНИЕ И ВСТРОЕННЫЕ ДИСКИ: SMART" }
    var reportSectionUnparsed: String { "НЕРАСПОЗНАННЫЙ ВЫВОД КОМАНД (первые строки)" }
    var reportUnparsedHint: String { "MacDashboard не смог разобрать вывод этих команд. Серийные номера и UUID скрыты; приложите этот блок к сообщению об ошибке." }
    func reportUnparsedMoreLines(_ n: Int) -> String { "(ещё не показано строк: \(n))" }
    var reportNone: String { "(нет)" }
    func reportUptime(_ v: String) -> String { "Аптайм: \(v)" }
    var reportAgentsUserHeader: String { "--- Пользовательские:" }
    var reportEmpty: String { "(пусто)" }
    var reportAgentsSystemHeader: String { "--- Системные (сторонние программы):" }
    var reportNoBattery: String { "нет батареи (настольный Mac)" }
    func reportBatterySource(_ v: String) -> String { "Источник питания: \(v)" }
    func reportBatteryCharge(_ v: String) -> String { "Заряд: \(v)" }
    func reportBatteryState(_ v: String) -> String { "Состояние: \(v)" }
    var reportTMNotChecked: String { "(не проверялось)" }
    var reportTMNotConfigured: String { "(не настроен)" }
    func reportTMLastBackup(_ v: String) -> String { "Последний бэкап: \(v)" }
    var reportNotChecked: String { "(не проверено)" }
    var reportSectionTimings: String { "ВРЕМЯ СБОРА" }
    var reportTimingsNote: String { "Разделы собираются параллельно, поэтому их время перекрывается." }
    func reportTimingsPass(_ v: String) -> String { "Весь проход: \(v)" }
    func reportTimingsUpdates(_ v: String, _ at: String) -> String { "Обновления macOS (фоновая проверка в \(at)): \(v)" }
    func reportUpdatesCheckedAt(_ at: String) -> String { "(проверено \(at))" }
    var updatesCheckedJustNow: String { "проверено только что" }
    func updatesCheckedAgo(_ age: String) -> String { "проверено \(age) назад" }
    func reportTimingsFolderSizes(_ v: String, _ at: String) -> String { "Размеры папок (фоновый подсчёт в \(at)): \(v)" }
    func reportTimingsSectionName(_ s: ReportSection) -> String {
        switch s {
        case .system: return "Система"
        case .snapshots: return "Локальные снапшоты"
        case .homeDirs: return "Домашняя папка"
        case .serviceDirs: return "Служебные папки"
        case .security: return "Безопасность"
        case .tmDest: return "Time Machine"
        case .spotlight: return "Spotlight"
        case .crashes: return "Краши"
        case .brew: return "Homebrew"
        case .updates: return "Обновления macOS"
        case .autostart: return "Автозагрузка"
        case .smart: return "SMART"
        case .energy: return "Настройки энергии"
        case .battery: return "Батарея"
        }
    }
    func reportFoldersCountedAt(_ at: String) -> String { "(подсчитано \(at))" }
    func foldersCountedAgo(_ age: String) -> String { "подсчитано \(age) назад" }
    var foldersCountedJustNow: String { "подсчитано только что" }
    var reportBrewOutdatedHeader: String { "Устаревшие пакеты:" }
    func reportSmartDiskLine(_ title: String, _ device: String, _ status: String) -> String {
        "\(title) (\(device)) — статус: \(status)"
    }
    var reportSmartWarningNone: String { "Нет" }
    var reportSmartWarningLowSpareCapacity: String { "мало резервной ёмкости" }
    var reportSmartWarningCriticalTemp: String { "критическая температура" }
    var reportSmartWarningReliabilityDegraded: String { "снижена надёжность" }
    var reportSmartWarningReadOnlyMode: String { "режим только для чтения" }
    var reportSmartWarningBackupPowerFail: String { "отказ резервного питания памяти" }
    var reportSmartWarningPersistentMemoryReadOnly: String { "постоянная память только для чтения" }
    func reportSmartWarningGeneric(_ hex: String) -> String { "Есть предупреждение (\(hex))" }

    // MARK: Report collector
    var reportCollectorNoBackupsYet: String { "бэкапов ещё не было" }
    var reportCollectorDiskNotConnected: String { "диск не подключён" }
    var reportCollectorNoCompletedBackups: String { "нет завершённых бэкапов" }
    var reportCollectorDateUnavailableNoFDA: String { "дата недоступна (нет полного доступа к диску)" }
    var reportCollectorSpotlightEnabled: String { "Индексация включена" }
    var reportCollectorSpotlightDisabled: String { "Индексация отключена" }
    var reportCollectorInternalDiskFallbackTitle: String { "Встроенный накопитель" }
    var reportCollectorSmartOkVerified: String { "SMART: в норме (проверено)" }
    var reportCollectorSmartNotSupported: String { "SMART не поддерживается" }
    var reportCollectorSmartStatusUnavailable: String { "SMART: статус недоступен" }
    var reportCollectorSmartMediaErrors: String { "SMART: ошибки носителя" }
    var reportCollectorSmartWearHigh: String { "SMART: износ на исходе" }
    var reportCollectorSmartUnavailable: String { "SMART недоступен" }
    var reportCollectorSmartUnavailableNoTools: String { "SMART недоступен (нет smartmontools)" }
}
