// Engine/Strings/Strings+Settings.swift
// Settings window: the `SettingsStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol SettingsStrings {
    // MARK: Settings
    var settingsLanguageLabel: String { get }
    var settingsIntervalLabel: String { get }
    func settingsIntervalOption(_ seconds: Int) -> String
    /// Per-value note below the interval segmented control (§7.3, SW:96-99),
    /// switching with the current `fastIntervalSeconds` selection.
    var settingsSectionBackup: String { get }
    var settingsMenuLanguageHint: String { get }
    var settingsRelaunchNow: String { get }
    var settingsSectionGeneral: String { get }
    var settingsSectionMonitoring: String { get }
    var settingsVersionLabel: String { get }
    var settingsWindowTitle: String { get }
    var settingsSectionIPhone: String { get }
    var settingsKeepArchivesLabel: String { get }
    var settingsSectionAbout: String { get }
    var settingsInstantNote: String { get }
    var settingsOptionSystem: String { get }
    var settingsThemeLabel: String { get }
    var settingsThemeLight: String { get }
    var settingsThemeDark: String { get }
    var settingsOrbsLabel: String { get }
    var settingsOrbsSub: String { get }
    var settingsRimLabel: String { get }
    var settingsRimSub: String { get }
    var settingsRimNarrow: String { get }
    var settingsRimMedium: String { get }
    var settingsRimWide: String { get }
    var settingsLaunchAtLoginLabel: String { get }
    var settingsLaunchAtLoginApproval: String { get }
    var settingsSnapshotLabel: String { get }
    var settingsSnapshotSub: String { get }
    var settingsLowSpaceLabel: String { get }
    var settingsClaudeLogLabel: String { get }
    var settingsChoose: String { get }
    var settingsPathMissing: String { get }
    var settingsWarnAfterLabel: String { get }
    var settingsWarnAfterSub: String { get }
    var settingsWarnAfterFewer: String { get }
    var settingsWarnAfterMore: String { get }
    var settingsPermTitle: String { get }
    var settingsPermBody: String { get }
    var settingsReportFolderLabel: String { get }
    var settingsMenuItem: String { get }
    func settingsLowSpaceOption(_ percent: Int) -> String
    func settingsWarnAfterDays(_ days: Int) -> String
    // REDESIGN-NOTIFY (handoff 11-settings.md :26, Settings.dc.html :188-195)
    var settingsNotifyCaption: String { get }
    var settingsNotifyProtection: String { get }
    var settingsNotifyDisk: String { get }
    var settingsNotifyBattery: String { get }
    var settingsNotifyBackup: String { get }
    var settingsNotifyUpdates: String { get }
    var settingsNotifyCrashes: String { get }
    var settingsNotifyDenied: String { get }
    var settingsNotifyOpen: String { get }
    var settingsNotifyOpenA11y: String { get }
    var settingsAutoReadLabel: String { get }
    var settingsAutoReadSub: String { get }
    var settingsArchiveFolderLabel: String { get }
    func settingsArchiveFolderMoveFailed(_ n: Int) -> String
}

extension StringsEN: SettingsStrings {
    // MARK: Settings
    var settingsLanguageLabel: String { "Language" }
    var settingsIntervalLabel: String { "Refresh interval" }
    func settingsIntervalOption(_ seconds: Int) -> String { "\(seconds) s" }
    var settingsSectionBackup: String { "Backups" }
    var settingsMenuLanguageHint: String { "Menus and system windows switch language after a relaunch." }
    var settingsRelaunchNow: String { "Relaunch now" }
    var settingsSectionGeneral: String { "General" }
    var settingsSectionMonitoring: String { "Monitoring" }
    var settingsVersionLabel: String { "Version" }
    var settingsSectionIPhone: String { "iPhone" }
    var settingsKeepArchivesLabel: String { "Keep imported archives" }
    var settingsSectionAbout: String { "About" }
    var settingsInstantNote: String { "Changes apply instantly." }
    var settingsOptionSystem: String { "System" }
    var settingsThemeLabel: String { "Theme" }
    var settingsThemeLight: String { "Light" }
    var settingsThemeDark: String { "Dark" }
    var settingsOrbsLabel: String { "Background orbs" }
    var settingsOrbsSub: String { "Off when Reduce Motion is on" }
    var settingsRimLabel: String { "Edge light" }
    var settingsRimSub: String { "Pointer highlight is off with Reduce Motion" }
    var settingsRimNarrow: String { "Narrow" }
    var settingsRimMedium: String { "Medium" }
    var settingsRimWide: String { "Wide" }
    var settingsLaunchAtLoginLabel: String { "Launch at login" }
    var settingsLaunchAtLoginApproval: String { "Allow it in System Settings › General › Login Items" }
    var settingsSnapshotLabel: String { "Daily snapshot" }
    var settingsSnapshotSub: String { "Data for History charts" }
    var settingsLowSpaceLabel: String { "Low-space warning" }
    var settingsClaudeLogLabel: String { "Claude backup log" }
    var settingsChoose: String { "Choose…" }
    var settingsPathMissing: String { "File not found at this path" }
    var settingsWarnAfterLabel: String { "Warn after" }
    var settingsWarnAfterSub: String { "Backup age shown amber after this" }
    var settingsWarnAfterFewer: String { "Fewer days" }
    var settingsWarnAfterMore: String { "More days" }
    var settingsPermTitle: String { "Full Disk Access needed" }
    var settingsPermBody: String { "MacDashboard can’t read the Claude backup log without it." }
    var settingsReportFolderLabel: String { "Report folder" }
    var settingsMenuItem: String { "Settings…" }
    func settingsLowSpaceOption(_ percent: Int) -> String { "\(percent)%" }
    func settingsWarnAfterDays(_ days: Int) -> String { "\(days) " + (days == 1 ? "day" : "days") }
    var settingsNotifyCaption: String { "Notify about attention items" }
    var settingsNotifyProtection: String { "Protection turned off" }
    var settingsNotifyDisk: String { "Low disk space" }
    var settingsNotifyBattery: String { "Battery health" }
    var settingsNotifyBackup: String { "Backup overdue" }
    var settingsNotifyUpdates: String { "Updates available" }
    var settingsNotifyCrashes: String { "New crash reports" }
    var settingsNotifyDenied: String { "Notifications for MacDashboard are turned off in System Settings." }
    var settingsNotifyOpen: String { "Open Notification settings…" }
    var settingsNotifyOpenA11y: String { "Open System Settings › Notifications" }
    var settingsWindowTitle: String { "Settings" }
    var settingsAutoReadLabel: String { "Auto-read on connect" }
    var settingsAutoReadSub: String { "Battery and crash logs" }
    var settingsArchiveFolderLabel: String { "Archive folder" }
    func settingsArchiveFolderMoveFailed(_ n: Int) -> String {
        "Could not move \(n) " + (n == 1 ? "archive" : "archives") + " to this folder; the folder is unchanged"
    }
}

extension StringsRU: SettingsStrings {
    // MARK: Settings
    var settingsLanguageLabel: String { "Язык" }
    var settingsIntervalLabel: String { "Интервал обновления" }
    func settingsIntervalOption(_ seconds: Int) -> String { "\(seconds) с" }
    var settingsSectionBackup: String { "Резервные копии" }
    var settingsMenuLanguageHint: String { "Меню и системные окна сменят язык после перезапуска." }
    var settingsRelaunchNow: String { "Перезапустить сейчас" }
    var settingsSectionGeneral: String { "Основные" }
    var settingsSectionMonitoring: String { "Мониторинг" }
    var settingsVersionLabel: String { "Версия" }
    var settingsSectionIPhone: String { "iPhone" }
    var settingsKeepArchivesLabel: String { "Хранить импортированные архивы" }
    var settingsSectionAbout: String { "О программе" }
    var settingsInstantNote: String { "Изменения применяются сразу." }
    var settingsOptionSystem: String { "Системный" }
    var settingsThemeLabel: String { "Тема" }
    var settingsThemeLight: String { "Светлая" }
    var settingsThemeDark: String { "Тёмная" }
    var settingsOrbsLabel: String { "Фоновые сферы" }
    var settingsOrbsSub: String { "Выключены при «Уменьшении движения»" }
    var settingsRimLabel: String { "Подсветка краёв" }
    var settingsRimSub: String { "Блик у курсора выключен при «Уменьшении движения»" }
    var settingsRimNarrow: String { "Узкая" }
    var settingsRimMedium: String { "Средняя" }
    var settingsRimWide: String { "Широкая" }
    var settingsLaunchAtLoginLabel: String { "Открывать при входе" }
    var settingsLaunchAtLoginApproval: String { "Разрешите в Системных настройках › Основные › Объекты входа" }
    var settingsSnapshotLabel: String { "Ежедневный снимок" }
    var settingsSnapshotSub: String { "Данные для графиков «История»" }
    var settingsLowSpaceLabel: String { "Мало места, если свободно <" }
    var settingsClaudeLogLabel: String { "Журнал бэкапа Claude" }
    var settingsChoose: String { "Выбрать…" }
    var settingsPathMissing: String { "Файл по этому пути не найден" }
    var settingsWarnAfterLabel: String { "Предупреждать через" }
    var settingsWarnAfterSub: String { "После этого срок копии подсвечивается" }
    var settingsWarnAfterFewer: String { "Меньше дней" }
    var settingsWarnAfterMore: String { "Больше дней" }
    var settingsPermTitle: String { "Нужен полный доступ к диску" }
    var settingsPermBody: String { "Без него MacDashboard не может прочитать журнал резервных копий Claude." }
    var settingsReportFolderLabel: String { "Папка отчёта" }
    var settingsMenuItem: String { "Настройки…" }
    func settingsLowSpaceOption(_ percent: Int) -> String { "\(percent) %" }
    func settingsWarnAfterDays(_ days: Int) -> String { "\(days) " + ruPlural(days, "день", "дня", "дней") }
    var settingsNotifyCaption: String { "Уведомлять о проблемах" }
    var settingsNotifyProtection: String { "Защита выключена" }
    var settingsNotifyDisk: String { "Мало места на диске" }
    var settingsNotifyBattery: String { "Состояние батареи" }
    var settingsNotifyBackup: String { "Резервная копия устарела" }
    var settingsNotifyUpdates: String { "Доступны обновления" }
    var settingsNotifyCrashes: String { "Новые отчёты о сбоях" }
    var settingsNotifyDenied: String { "Уведомления MacDashboard выключены в Системных настройках." }
    var settingsNotifyOpen: String { "Открыть «Уведомления»…" }
    var settingsNotifyOpenA11y: String { "Открыть Системные настройки › Уведомления" }
    var settingsWindowTitle: String { "Настройки" }
    var settingsAutoReadLabel: String { "Читать при подключении" }
    var settingsAutoReadSub: String { "Батарея и журналы сбоев" }
    var settingsArchiveFolderLabel: String { "Папка архивов" }
    func settingsArchiveFolderMoveFailed(_ n: Int) -> String {
        "Не удалось переместить \(n) " + ruPlural(n, "архив", "архива", "архивов") + " в эту папку; папка не изменена"
    }
}
