// Engine/Strings/Strings+Common.swift
// Shared words, decimal separator, byte units, parser status, model errors: the `CommonStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol CommonStrings {
    // MARK: App
    // The app name is deliberately NOT here — it is a brand, not a phrase to
    // translate, and lives in `AppInfo.name` (V2-NAME-ONE).
    /// Decimal separator for number formatting (`fmtNum`): "," RU, "." EN.
    var decimalSeparator: String { get }

    // MARK: Shared (cross-card)
    var sharedUnavailable: String { get }
    var sharedCollectingData: String { get }
    var sharedEmpty: String { get }
    func sharedMoreN(_ n: Int) -> String
    var sharedCollapse: String { get }

    // MARK: Parsers / live status
    var battStateCharging: String { get }
    var battStateDischarging: String { get }
    var battStateCharged: String { get }
    var battStateFinishingCharge: String { get }
    var battStateNotCharging: String { get }
    var battSourceAC: String { get }
    var battSourceBattery: String { get }
    var uptimeUnitDay: String { get }
    var uptimeUnitHour: String { get }
    var uptimeUnitMinute: String { get }
    var uptimeUnitSecond: String { get }
    func uptimeHourMinuteCombo(_ h: Int, _ mm: Int) -> String

    // MARK: Byte units
    var byteUnitTB: String { get }
    var byteUnitGB: String { get }
    var byteUnitMB: String { get }
    var byteUnitKB: String { get }
    var byteUnitB: String { get }

    // MARK: AppModel errors
    func errorHistorySaveFailed(_ msg: String) -> String
    func errorReportWriteFailed(_ msg: String) -> String

    // MARK: Common (strings.json › Shared + 00 §4.16/§7; REDESIGN-FOUNDATION)
    var commonShowInFinder: String { get }
    var commonFirewall: String { get }
    var commonEnable: String { get }
    var commonDisk: String { get }
    var commonSetUp: String { get }
    var commonShow: String { get }
    var commonDone: String { get }
    var commonMacCantSleep: String { get }
    var commonBattery: String { get }
    var commonInstall: String { get }
    var commonServiceRecommended: String { get }
    var commonClaudeBackup: String { get }
    var commonCPU: String { get }
    var commonMemory: String { get }
    var commonStorage: String { get }
    var commonSecurity: String { get }
    var commonBackups: String { get }
    var commonSystem: String { get }
    var commonHistory: String { get }
    var commonLocalSnapshots: String { get }
    var commonFullDiskAccessNeeded: String { get }
    var commonCompressed: String { get }
    var commonOK: String { get }
    var commonCycles: String { get }
    var commonProtection: String { get }
    var commonUpdates: String { get }
    var commonCollectingData: String { get }
    var commonAllGood: String { get }
    var commonNeedsAttention: String { get }
    var commonThisMac: String { get }
    var commonReport: String { get }
    var commonRefresh: String { get }
    var commonRefreshReport: String { get }
    var commonNow: String { get }
    var commonTryAgain: String { get }
    var commonShowLess: String { get }
    var commonSetting: String { get }
    var commonOnBattery: String { get }
    var commonACPower: String { get }
    var commonNormal: String { get }
    var commonFree: String { get }
    var commonChart: String { get }
    var commonTable: String { get }
    var commonRefreshing: String { get }
    var commonInProgress: String { get }
    var commonCancel: String { get }
    var commonOpenPrivacySettings: String { get }
    func commonUpdated(_ time: String) -> String
    var commonChecking: String { get }
    var commonCritical: String { get }
    func commonLastData(_ time: String) -> String
}

extension StringsEN: CommonStrings {
    // MARK: App
    var decimalSeparator: String { "." }

    // MARK: Shared (cross-card)
    var sharedUnavailable: String { "(unavailable)" }
    var sharedCollectingData: String { "Collecting data…" }
    var sharedEmpty: String { "empty" }
    func sharedMoreN(_ n: Int) -> String { "\(n) more" }
    var sharedCollapse: String { "Collapse" }

    // MARK: Parsers / live status
    var battStateCharging: String { "charging" }
    var battStateDischarging: String { "discharging" }
    var battStateCharged: String { "charged" }
    var battStateFinishingCharge: String { "finishing charge" }
    var battStateNotCharging: String { "not charging" }
    var battSourceAC: String { "AC power" }
    var battSourceBattery: String { "battery" }
    var uptimeUnitDay: String { "d" }
    var uptimeUnitHour: String { "h" }
    var uptimeUnitMinute: String { "min" }
    var uptimeUnitSecond: String { "s" }
    func uptimeHourMinuteCombo(_ h: Int, _ mm: Int) -> String { "\(h) h \(mm) min" }

    // MARK: Byte units
    var byteUnitTB: String { "TB" }
    var byteUnitGB: String { "GB" }
    var byteUnitMB: String { "MB" }
    var byteUnitKB: String { "KB" }
    var byteUnitB: String { "B" }

    // MARK: AppModel errors
    func errorHistorySaveFailed(_ msg: String) -> String { "Failed to save history: \(msg)" }
    func errorReportWriteFailed(_ msg: String) -> String { "Failed to write report: \(msg)" }

    // MARK: Common (strings.json › Shared + 00 §4.16/§7; REDESIGN-FOUNDATION)
    var commonShowInFinder: String { "Show in Finder" }
    var commonFirewall: String { "Firewall" }
    var commonEnable: String { "Enable…" }
    var commonDisk: String { "Disk" }
    var commonSetUp: String { "Set up…" }
    var commonShow: String { "Show" }
    var commonDone: String { "Done" }
    var commonMacCantSleep: String { "Mac can’t sleep" }
    var commonBattery: String { "Battery" }
    var commonInstall: String { "Install…" }
    var commonServiceRecommended: String { "service recommended" }
    var commonClaudeBackup: String { "Claude backup" }
    var commonCPU: String { "CPU" }
    var commonMemory: String { "Memory" }
    var commonStorage: String { "Storage" }
    var commonSecurity: String { "Security" }
    var commonBackups: String { "Backups" }
    var commonSystem: String { "System" }
    var commonHistory: String { "History" }
    var commonLocalSnapshots: String { "Local snapshots" }
    var commonFullDiskAccessNeeded: String { "Full Disk Access needed" }
    var commonCompressed: String { "Compressed" }
    var commonOK: String { "OK" }
    var commonCycles: String { "Cycles" }
    var commonProtection: String { "Protection" }
    var commonUpdates: String { "Updates" }
    var commonCollectingData: String { "Collecting data…" }
    var commonAllGood: String { "All good" }
    var commonNeedsAttention: String { "Needs attention" }
    var commonThisMac: String { "This Mac" }
    var commonReport: String { "Report" }
    var commonRefresh: String { "Refresh" }
    var commonRefreshReport: String { "Refresh report" }
    var commonNow: String { "Now" }
    var commonTryAgain: String { "Try again" }
    var commonShowLess: String { "Show less" }
    var commonSetting: String { "Setting" }
    var commonOnBattery: String { "Battery" }
    var commonACPower: String { "AC power" }
    var commonNormal: String { "normal" }
    var commonFree: String { "Free" }
    var commonChart: String { "Chart" }
    var commonTable: String { "Table" }
    var commonRefreshing: String { "Refreshing…" }
    var commonInProgress: String { "In progress" }
    var commonCancel: String { "Cancel" }
    var commonOpenPrivacySettings: String { "Open Privacy settings…" }
    func commonUpdated(_ time: String) -> String { "updated \(time)" }
    var commonChecking: String { "Checking…" }
    var commonCritical: String { "Critical" }
    func commonLastData(_ time: String) -> String { "last data — \(time)" }
}

extension StringsRU: CommonStrings {
    // MARK: App
    var decimalSeparator: String { "," }

    // MARK: Shared (cross-card)
    var sharedUnavailable: String { "(недоступно)" }
    var sharedCollectingData: String { "Собираем данные…" }
    var sharedEmpty: String { "пусто" }
    func sharedMoreN(_ n: Int) -> String { "Ещё \(n)" }
    var sharedCollapse: String { "Свернуть" }

    // MARK: Parsers / live status
    var battStateCharging: String { "заряжается" }
    var battStateDischarging: String { "разряжается" }
    var battStateCharged: String { "заряжена" }
    var battStateFinishingCharge: String { "дозаряд" }
    var battStateNotCharging: String { "не заряжается" }
    var battSourceAC: String { "от сети" }
    var battSourceBattery: String { "от батареи" }
    var uptimeUnitDay: String { "дн" }
    var uptimeUnitHour: String { "ч" }
    var uptimeUnitMinute: String { "мин" }
    var uptimeUnitSecond: String { "с" }
    func uptimeHourMinuteCombo(_ h: Int, _ mm: Int) -> String { "\(h) ч \(mm) мин" }

    // MARK: Byte units
    var byteUnitTB: String { "ТБ" }
    var byteUnitGB: String { "ГБ" }
    var byteUnitMB: String { "МБ" }
    var byteUnitKB: String { "КБ" }
    var byteUnitB: String { "Б" }

    // MARK: AppModel errors
    func errorHistorySaveFailed(_ msg: String) -> String { "Не удалось сохранить историю: \(msg)" }
    func errorReportWriteFailed(_ msg: String) -> String { "Не удалось записать отчёт: \(msg)" }

    // MARK: Common (strings.json › Shared + 00 §4.16/§7; REDESIGN-FOUNDATION)
    var commonShowInFinder: String { "Показать в Finder" }
    var commonFirewall: String { "Брандмауэр" }
    var commonEnable: String { "Включить…" }
    var commonDisk: String { "Диск" }
    var commonSetUp: String { "Настроить…" }
    var commonShow: String { "Показать" }
    var commonDone: String { "Готово" }
    var commonMacCantSleep: String { "Mac не засыпает" }
    var commonBattery: String { "Батарея" }
    var commonInstall: String { "Установить…" }
    var commonServiceRecommended: String { "нужен сервис" }
    var commonClaudeBackup: String { "Бэкап Claude" }
    var commonCPU: String { "Процессор" }
    var commonMemory: String { "Память" }
    var commonStorage: String { "Хранилище" }
    var commonSecurity: String { "Безопасность" }
    var commonBackups: String { "Резервные копии" }
    var commonSystem: String { "Система" }
    var commonHistory: String { "История" }
    var commonLocalSnapshots: String { "Локальные снимки" }
    var commonFullDiskAccessNeeded: String { "Нужен полный доступ к диску" }
    var commonCompressed: String { "Сжатая" }
    var commonOK: String { "в норме" }
    var commonCycles: String { "Циклы" }
    var commonProtection: String { "Защита" }
    var commonUpdates: String { "Обновления" }
    var commonCollectingData: String { "Сбор данных…" }
    var commonAllGood: String { "Всё в порядке" }
    var commonNeedsAttention: String { "Требует внимания" }
    var commonThisMac: String { "Этот Mac" }
    var commonReport: String { "Отчёт" }
    var commonRefresh: String { "Обновить" }
    var commonRefreshReport: String { "Обновить отчёт" }
    var commonNow: String { "Сейчас" }
    var commonTryAgain: String { "Повторить" }
    var commonShowLess: String { "Свернуть" }
    var commonSetting: String { "Параметр" }
    var commonOnBattery: String { "От батареи" }
    var commonACPower: String { "От сети" }
    var commonNormal: String { "норма" }
    var commonFree: String { "Свободно" }
    var commonChart: String { "График" }
    var commonTable: String { "Таблица" }
    var commonRefreshing: String { "Обновление…" }
    var commonInProgress: String { "Выполняется" }
    var commonCancel: String { "Отмена" }
    var commonOpenPrivacySettings: String { "Открыть «Конфиденциальность»…" }
    func commonUpdated(_ time: String) -> String { "обновлено \(time)" }
    var commonChecking: String { "Проверка…" }
    var commonCritical: String { "Критично" }
    func commonLastData(_ time: String) -> String { "последние данные — \(time)" }
}
