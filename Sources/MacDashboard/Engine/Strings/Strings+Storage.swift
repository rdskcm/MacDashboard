// Engine/Strings/Strings+Storage.swift
// Storage folders, disks (SMART) and Storage page: the `StorageStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol StorageStrings {
    // MARK: Storage — shared folder labels
    var storageColShare: String { get }
    var storageTrashLabel: String { get }
    var storageAppsLabel: String { get }

    // MARK: Storage — folders that could not be read (V2-FDA-DEGRADE)
    func storageFoldersNoFDA(_ folders: String) -> String
    var storageFoldersNoFDAButton: String { get }
    var storageFoldersNoFDAButtonA11y: String { get }

    // MARK: Storage — folders the count did not reach before its deadline (SERVICE-DIRS-TIMEOUT)
    func storageFoldersNotMeasured(_ folders: String) -> String

    // MARK: Storage — Диски (SMART)
    func storageSmartUpdatedCaption(_ time: String) -> String

    // MARK: Storage page (REDESIGN-STORAGE)
    var groupingSeparator: String { get }
    var storageTagDriveFailing: String { get }
    var storageTagAlmostFull: String { get }
    var storageTagDriveWorn: String { get }
    var storageTagLowSpace: String { get }
    var storageDiskTitle: String { get }
    var storageFree: String { get }
    func storageHeroNote(_ size: String, _ pct: String) -> String
    var storageData: String { get }
    var storageSystem: String { get }
    var storagePurgeable: String { get }
    var storageNVMeTemp: String { get }
    var storageTempNormal: String { get }
    var storageTempHigh: String { get }
    func storageCelsius(_ t: Int) -> String
    var storageDownloads: String { get }
    var storageCaches: String { get }
    func storageFreeItem(_ name: String, _ size: String) -> String
    func storageNoteLow(_ pct: String) -> String
    func storageNoteLowItems(_ pct: String, _ list: String) -> String
    func storageNoteCritical(_ pct: String) -> String
    func storageNoteCriticalItems(_ pct: String, _ list: String) -> String
    var storageSettingsButton: String { get }
    var storageSettingsA11y: String { get }
    var storageFoldersTitle: String { get }
    var storageSegHome: String { get }
    var storageSegSystem: String { get }
    var storageSegA11y: String { get }
    var storageCaptionTop: String { get }
    func storageCaptionCounted(_ age: String) -> String
    func storageAgo(_ m: Int) -> String
    var storageJustNow: String { get }
    var storageCaptionCounting: String { get }
    var storageCaptionCountFailed: String { get }
    func storageCaptionTrashEmptied(_ size: String) -> String
    var storageCaptionSomeHidden: String { get }
    var storageCounting: String { get }
    var storageCountTimedOut: String { get }
    var storageCountNoResult: String { get }
    var storageCountTryAgainA11y: String { get }
    var storageNoFolders: String { get }
    func storageShowA11y(_ name: String) -> String
    var storageEmptyTrashButton: String { get }
    var storageEmptyTrashA11y: String { get }
    var storageConfirmTitle: String { get }
    func storageConfirmText(_ n: Int, _ size: String) -> String
    func storageConfirmTextNoCount(_ size: String) -> String
    var storageConfirmEmpty: String { get }
    var storageConfirmCancel: String { get }
    func storageFDANote(_ names: String) -> String
    func storageFDANoteMore(_ names: String, _ n: Int) -> String
    var storageFDAButtonA11y: String { get }
    var storageSmartCardTitle: String { get }
    var storageSubInternalOK: String { get }
    var storageSubExternalOK: String { get }
    var storageSubInternalNoData: String { get }
    var storageSubExternalNoData: String { get }
    var storageSubInternalFailing: String { get }
    var storageSubExternalFailing: String { get }
    func storageSubInternalWorn(_ pct: String) -> String
    func storageSubExternalWorn(_ pct: String) -> String
    var storageStatusUnavailable: String { get }
    var storageStatusFailing: String { get }
    func storageWearNote(_ pct: String) -> String
    var storageKVTemp: String { get }
    var storageKVUsed: String { get }
    var storageKVSpare: String { get }
    var storageKVSpareThreshold: String { get }
    var storageKVHours: String { get }
    var storageKVCycles: String { get }
    var storageKVUnsafe: String { get }
    var storageKVRead: String { get }
    var storageKVWritten: String { get }
    var storageKVMediaErrors: String { get }
    var storageKVErrorLog: String { get }
    var storageKVCritical: String { get }
    var storageYes: String { get }
    var storageNo: String { get }
    var storageToolsInstallable: String { get }
    var storageToolsNeedsBrew: String { get }
    var storageToolsInstall: String { get }
    var storageToolsInstallA11y: String { get }
    var storageToolsHowToBrew: String { get }
    var storageToolsHowToBrewA11y: String { get }
    func storageInstallFailedCode(_ c: Int32) -> String
    var storageInstallTimedOut: String { get }
    var storageInstallNoBrew: String { get }
    var storageInstallRetryA11y: String { get }
    var storageRefreshA11y: String { get }

    // MARK: SMART attribute/status render-time localization (smartctl output is
    // always raw English; these translate known labels for display without touching
    // the collected `SmartDisk` model — see `smartLocalizedLabel(_:)`).
    var smartAttrCriticalWarning: String { get }
    var smartAttrTemperature: String { get }
    var smartAttrAvailableSpare: String { get }
    var smartAttrPercentageUsed: String { get }
    var smartAttrPowerCycles: String { get }
    var smartAttrPowerOnHours: String { get }
    var smartAttrUnsafeShutdowns: String { get }
    var smartAttrMediaAndDataIntegrityErrors: String { get }
    var smartAttrErrorInformationLogEntries: String { get }
    var reportSmartStatusOk: String { get }
}

extension StringsEN: StorageStrings {
    // MARK: Storage — shared folder labels
    var storageColShare: String { "Share" }
    var storageTrashLabel: String { "Trash" }
    var storageAppsLabel: String { "Applications" }

    // MARK: Storage — folders that could not be read (V2-FDA-DEGRADE)
    func storageFoldersNoFDA(_ folders: String) -> String { "Not shown here: \(folders) — the app doesn't have Full Disk Access." }
    var storageFoldersNoFDAButton: String { "Open Settings" }
    var storageFoldersNoFDAButtonA11y: String { "Open Full Disk Access settings" }

    // MARK: Storage — folders the count did not reach before its deadline (SERVICE-DIRS-TIMEOUT)
    func storageFoldersNotMeasured(_ folders: String) -> String { "Not measured in time: \(folders)." }

    // MARK: Storage — Диски (SMART)
    func storageSmartUpdatedCaption(_ time: String) -> String { "updated \(time)" }

    // MARK: Storage page (REDESIGN-STORAGE)
    // REDESIGN-STORAGE
    var groupingSeparator: String { "," }
    var storageTagDriveFailing: String { "drive failing" }
    var storageTagAlmostFull: String { "almost out of space" }
    var storageTagDriveWorn: String { "drive worn" }
    var storageTagLowSpace: String { "low on space" }
    var storageDiskTitle: String { "Disk" }
    var storageFree: String { "Free" }
    func storageHeroNote(_ size: String, _ pct: String) -> String { "of \(size) · \(pct) used" }
    var storageData: String { "Data" }
    var storageSystem: String { "System" }
    var storagePurgeable: String { "Purgeable" }
    var storageNVMeTemp: String { "NVMe temperature" }
    var storageTempNormal: String { "normal" }
    var storageTempHigh: String { "high" }
    func storageCelsius(_ t: Int) -> String { "\(t) °C" }
    var storageDownloads: String { "Downloads" }
    var storageCaches: String { "Caches" }
    func storageFreeItem(_ name: String, _ size: String) -> String { "\(name) \(size)" }
    func storageNoteLow(_ pct: String) -> String { "Less than \(pct) free." }
    func storageNoteLowItems(_ pct: String, _ list: String) -> String { "Less than \(pct) free. What you can free up: \(list)." }
    func storageNoteCritical(_ pct: String) -> String { "Less than \(pct) free. macOS may stop saving files and growing swap." }
    func storageNoteCriticalItems(_ pct: String, _ list: String) -> String { "Less than \(pct) free. macOS may stop saving files and growing swap. Free up space: \(list)." }
    var storageSettingsButton: String { "Storage settings" }
    var storageSettingsA11y: String { "Open Storage settings in System Settings" }
    var storageFoldersTitle: String { "Folders" }
    var storageSegHome: String { "Home" }
    var storageSegSystem: String { "System" }
    var storageSegA11y: String { "Folder list" }
    var storageCaptionTop: String { "top by size" }
    func storageCaptionCounted(_ age: String) -> String { "top by size · counted \(age)" }
    func storageAgo(_ m: Int) -> String { "\(m) min ago" }
    var storageJustNow: String { "just now" }
    var storageCaptionCounting: String { "counting folder sizes…" }
    var storageCaptionCountFailed: String { "counting didn’t finish" }
    func storageCaptionTrashEmptied(_ size: String) -> String { "top by size · Trash emptied, \(size) freed" }
    var storageCaptionSomeHidden: String { "top by size · some folders hidden" }
    var storageCounting: String { "Counting…" }
    var storageCountTimedOut: String { "Couldn’t count folder sizes: du didn’t respond within 10 s." }
    var storageCountNoResult: String { "Couldn’t count folder sizes: du returned no result." }
    var storageCountTryAgainA11y: String { "Count folder sizes again" }
    var storageNoFolders: String { "No folder sizes yet." }
    func storageShowA11y(_ name: String) -> String { "Show \(name) in Finder" }
    var storageEmptyTrashButton: String { "Empty Trash…" }
    var storageEmptyTrashA11y: String { "Empty the Trash" }
    var storageConfirmTitle: String { "Empty Trash?" }
    func storageConfirmText(_ n: Int, _ size: String) -> String { "\(fmtGrouped(n)) \(n == 1 ? "item" : "items") (\(size)) will be deleted permanently. You can’t undo this." }
    func storageConfirmTextNoCount(_ size: String) -> String { "Everything in the Trash (\(size)) will be deleted permanently. You can’t undo this." }
    var storageConfirmEmpty: String { "Empty Trash" }
    var storageConfirmCancel: String { "Cancel" }
    func storageFDANote(_ names: String) -> String { "Not shown here: \(names) — MacDashboard doesn’t have Full Disk Access." }
    func storageFDANoteMore(_ names: String, _ n: Int) -> String { "Not shown here: \(names) and \(n) more — MacDashboard doesn’t have Full Disk Access." }
    var storageFDAButtonA11y: String { "Open Full Disk Access in Privacy & Security settings" }
    var storageSmartCardTitle: String { "Disks (SMART)" }
    var storageSubInternalOK: String { "INTERNAL · OK" }
    var storageSubExternalOK: String { "EXTERNAL · OK" }
    var storageSubInternalNoData: String { "INTERNAL · no data" }
    var storageSubExternalNoData: String { "EXTERNAL · no data" }
    var storageSubInternalFailing: String { "INTERNAL · failing" }
    var storageSubExternalFailing: String { "EXTERNAL · failing" }
    func storageSubInternalWorn(_ pct: String) -> String { "INTERNAL · worn \(pct)" }
    func storageSubExternalWorn(_ pct: String) -> String { "EXTERNAL · worn \(pct)" }
    var storageStatusUnavailable: String { "SMART unavailable: this drive’s USB bridge doesn’t pass the data through." }
    var storageStatusFailing: String { "Drive is failing. Copy your data off and replace it." }
    func storageWearNote(_ pct: String) -> String { "The drive has used \(pct) of its rated write endurance. Back up regularly and plan a replacement." }
    var storageKVTemp: String { "Temperature" }
    var storageKVUsed: String { "Percentage used" }
    var storageKVSpare: String { "Available spare" }
    var storageKVSpareThreshold: String { "Spare threshold" }
    var storageKVHours: String { "Power-on hours" }
    var storageKVCycles: String { "Power cycles" }
    var storageKVUnsafe: String { "Unsafe shutdowns" }
    var storageKVRead: String { "Data read" }
    var storageKVWritten: String { "Data written" }
    var storageKVMediaErrors: String { "Media errors" }
    var storageKVErrorLog: String { "Error log entries" }
    var storageKVCritical: String { "Critical warning" }
    var storageYes: String { "yes" }
    var storageNo: String { "no" }
    var storageToolsInstallable: String { "SMART data needs smartmontools, a free command-line tool installed with Homebrew." }
    var storageToolsNeedsBrew: String { "SMART data needs Homebrew and smartmontools." }
    var storageToolsInstall: String { "Install smartmontools" }
    var storageToolsInstallA11y: String { "Install smartmontools with Homebrew" }
    var storageToolsHowToBrew: String { "How to install Homebrew" }
    var storageToolsHowToBrewA11y: String { "Open brew.sh in your browser" }
    func storageInstallFailedCode(_ c: Int32) -> String { "Couldn’t install smartmontools: brew exited with code \(c)." }
    var storageInstallTimedOut: String { "Couldn’t install smartmontools: brew didn’t finish within 5 min." }
    var storageInstallNoBrew: String { "Couldn’t install smartmontools: Homebrew wasn’t found." }
    var storageInstallRetryA11y: String { "Try installing smartmontools again" }
    var storageRefreshA11y: String { "Count folder sizes again" }

    // MARK: SMART attribute/status render-time localization (smartctl output is
    var smartAttrCriticalWarning: String { "Critical Warning" }
    var smartAttrTemperature: String { "Temperature" }
    var smartAttrAvailableSpare: String { "Available Spare" }
    var smartAttrPercentageUsed: String { "Percentage Used" }
    var smartAttrPowerCycles: String { "Power Cycles" }
    var smartAttrPowerOnHours: String { "Power On Hours" }
    var smartAttrUnsafeShutdowns: String { "Unsafe Shutdowns" }
    var smartAttrMediaAndDataIntegrityErrors: String { "Media and Data Integrity Errors" }
    var smartAttrErrorInformationLogEntries: String { "Error Information Log Entries" }
    var reportSmartStatusOk: String { "SMART: OK" }
}

extension StringsRU: StorageStrings {
    // MARK: Storage — shared folder labels
    var storageColShare: String { "Доля" }
    var storageTrashLabel: String { "Корзина" }
    var storageAppsLabel: String { "Программы" }

    // MARK: Storage — folders that could not be read (V2-FDA-DEGRADE)
    func storageFoldersNoFDA(_ folders: String) -> String { "Здесь не показаны: \(folders) — у приложения нет полного доступа к диску." }
    var storageFoldersNoFDAButton: String { "Открыть настройки" }
    var storageFoldersNoFDAButtonA11y: String { "Открыть настройки полного доступа к диску" }

    // MARK: Storage — folders the count did not reach before its deadline (SERVICE-DIRS-TIMEOUT)
    func storageFoldersNotMeasured(_ folders: String) -> String { "Не успели измерить: \(folders)." }

    // MARK: Storage — Диски (SMART)
    func storageSmartUpdatedCaption(_ time: String) -> String { "обновлено \(time)" }

    // MARK: Storage page (REDESIGN-STORAGE)
    // REDESIGN-STORAGE
    var groupingSeparator: String { "\u{2009}" }
    var storageTagDriveFailing: String { "сбой диска" }
    var storageTagAlmostFull: String { "почти нет места" }
    var storageTagDriveWorn: String { "износ диска" }
    var storageTagLowSpace: String { "мало места" }
    var storageDiskTitle: String { "Диск" }
    var storageFree: String { "Свободно" }
    func storageHeroNote(_ size: String, _ pct: String) -> String { "из \(size) · занято \(pct)" }
    var storageData: String { "Данные" }
    var storageSystem: String { "Система" }
    var storagePurgeable: String { "Очищаемое" }
    var storageNVMeTemp: String { "Температура NVMe" }
    var storageTempNormal: String { "норма" }
    var storageTempHigh: String { "высокая" }
    func storageCelsius(_ t: Int) -> String { "\(t) °C" }
    var storageDownloads: String { "Загрузки" }
    var storageCaches: String { "Кэши" }
    func storageFreeItem(_ name: String, _ size: String) -> String { "«\(name)» \(size)" }
    func storageNoteLow(_ pct: String) -> String { "Свободно меньше \(pct)." }
    func storageNoteLowItems(_ pct: String, _ list: String) -> String { "Свободно меньше \(pct). Что можно освободить: \(list)." }
    func storageNoteCritical(_ pct: String) -> String { "Свободно меньше \(pct). macOS может перестать сохранять файлы и расширять своп." }
    func storageNoteCriticalItems(_ pct: String, _ list: String) -> String { "Свободно меньше \(pct). macOS может перестать сохранять файлы и расширять своп. Освободите место: \(list)." }
    var storageSettingsButton: String { "Настройки хранилища" }
    var storageSettingsA11y: String { "Открыть настройки хранилища в Системных настройках" }
    var storageFoldersTitle: String { "Папки" }
    var storageSegHome: String { "Домашняя" }
    var storageSegSystem: String { "Служебные" }
    var storageSegA11y: String { "Список папок" }
    var storageCaptionTop: String { "топ по размеру" }
    func storageCaptionCounted(_ age: String) -> String { "топ по размеру · подсчитано \(age)" }
    func storageAgo(_ m: Int) -> String { "\(m) мин назад" }
    var storageJustNow: String { "только что" }
    var storageCaptionCounting: String { "подсчёт размеров папок…" }
    var storageCaptionCountFailed: String { "подсчёт не завершён" }
    func storageCaptionTrashEmptied(_ size: String) -> String { "топ по размеру · корзина очищена, освобождено \(size)" }
    var storageCaptionSomeHidden: String { "топ по размеру · часть папок скрыта" }
    var storageCounting: String { "Подсчёт…" }
    var storageCountTimedOut: String { "Не удалось подсчитать размеры папок: du не ответил за 10 с." }
    var storageCountNoResult: String { "Не удалось подсчитать размеры папок: du не вернул результат." }
    var storageCountTryAgainA11y: String { "Подсчитать размеры папок заново" }
    var storageNoFolders: String { "Размеров папок пока нет." }
    func storageShowA11y(_ name: String) -> String { "Показать \(name) в Finder" }
    var storageEmptyTrashButton: String { "Очистить…" }
    var storageEmptyTrashA11y: String { "Очистить корзину" }
    var storageConfirmTitle: String { "Очистить корзину?" }
    func storageConfirmText(_ n: Int, _ size: String) -> String { "\(fmtGrouped(n)) \(ruPlural(n, "объект", "объекта", "объектов")) (\(size)) будут удалены без возможности восстановления." }
    func storageConfirmTextNoCount(_ size: String) -> String { "Всё содержимое корзины (\(size)) будет удалено без возможности восстановления." }
    var storageConfirmEmpty: String { "Очистить" }
    var storageConfirmCancel: String { "Отмена" }
    func storageFDANote(_ names: String) -> String { "Здесь не показаны: \(names) — у приложения нет полного доступа к диску." }
    func storageFDANoteMore(_ names: String, _ n: Int) -> String { "Здесь не показаны: \(names) и ещё \(n) — у приложения нет полного доступа к диску." }
    var storageFDAButtonA11y: String { "Открыть «Полный доступ к диску» в настройках конфиденциальности" }
    var storageSmartCardTitle: String { "Диски (SMART)" }
    var storageSubInternalOK: String { "ВНУТРЕННИЙ · в норме" }
    var storageSubExternalOK: String { "ВНЕШНИЙ · в норме" }
    var storageSubInternalNoData: String { "ВНУТРЕННИЙ · нет данных" }
    var storageSubExternalNoData: String { "ВНЕШНИЙ · нет данных" }
    var storageSubInternalFailing: String { "ВНУТРЕННИЙ · сбой" }
    var storageSubExternalFailing: String { "ВНЕШНИЙ · сбой" }
    func storageSubInternalWorn(_ pct: String) -> String { "ВНУТРЕННИЙ · износ \(pct)" }
    func storageSubExternalWorn(_ pct: String) -> String { "ВНЕШНИЙ · износ \(pct)" }
    var storageStatusUnavailable: String { "SMART недоступен: USB-адаптер диска не передаёт эти данные." }
    var storageStatusFailing: String { "Диск выходит из строя. Скопируйте данные и замените диск." }
    func storageWearNote(_ pct: String) -> String { "Диск израсходовал \(pct) ресурса записи. Регулярно делайте резервные копии и запланируйте замену." }
    var storageKVTemp: String { "Температура" }
    var storageKVUsed: String { "Использовано ресурса" }
    var storageKVSpare: String { "Резерв" }
    var storageKVSpareThreshold: String { "Порог резерва" }
    var storageKVHours: String { "Часы работы" }
    var storageKVCycles: String { "Циклы питания" }
    var storageKVUnsafe: String { "Небезопасные выключения" }
    var storageKVRead: String { "Прочитано" }
    var storageKVWritten: String { "Записано" }
    var storageKVMediaErrors: String { "Ошибки носителя" }
    var storageKVErrorLog: String { "Записи журнала ошибок" }
    var storageKVCritical: String { "Критическое предупреждение" }
    var storageYes: String { "да" }
    var storageNo: String { "нет" }
    var storageToolsInstallable: String { "Для данных SMART нужна smartmontools — бесплатная утилита, ставится через Homebrew." }
    var storageToolsNeedsBrew: String { "Для данных SMART нужны Homebrew и smartmontools." }
    var storageToolsInstall: String { "Установить smartmontools" }
    var storageToolsInstallA11y: String { "Установить smartmontools через Homebrew" }
    var storageToolsHowToBrew: String { "Как установить Homebrew" }
    var storageToolsHowToBrewA11y: String { "Открыть brew.sh в браузере" }
    func storageInstallFailedCode(_ c: Int32) -> String { "Не удалось установить smartmontools: brew завершился с кодом \(c)." }
    var storageInstallTimedOut: String { "Не удалось установить smartmontools: brew не завершился за 5 мин." }
    var storageInstallNoBrew: String { "Не удалось установить smartmontools: Homebrew не найден." }
    var storageInstallRetryA11y: String { "Повторить установку smartmontools" }
    var storageRefreshA11y: String { "Подсчитать размеры папок заново" }

    // MARK: SMART attribute/status render-time localization (smartctl output is
    var smartAttrCriticalWarning: String { "Критическое предупреждение" }
    var smartAttrTemperature: String { "Температура" }
    var smartAttrAvailableSpare: String { "Резервная ёмкость" }
    var smartAttrPercentageUsed: String { "Процент износа" }
    var smartAttrPowerCycles: String { "Циклов включения" }
    var smartAttrPowerOnHours: String { "Часов наработки" }
    var smartAttrUnsafeShutdowns: String { "Некорректных выключений" }
    var smartAttrMediaAndDataIntegrityErrors: String { "Ошибок целостности данных" }
    var smartAttrErrorInformationLogEntries: String { "Записей в журнале ошибок" }
    var reportSmartStatusOk: String { "SMART: в норме" }
}
