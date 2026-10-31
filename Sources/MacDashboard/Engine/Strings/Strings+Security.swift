// Engine/Strings/Strings+Security.swift
// Security card and Security page: the `SecurityStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol SecurityStrings {
    // MARK: Security card
    var securityTitle: String { get }
    var securityFileVault: String { get }
    var securitySip: String { get }
    var securityFirewall: String { get }
    var securityGatekeeper: String { get }
    var securityFileVaultTip: String { get }
    var securitySipTip: String { get }
    var securityFirewallTip: String { get }
    var securityGatekeeperTip: String { get }

    // MARK: Security page (REDESIGN-SECURITY)
    func shortDateTime(_ d: Date) -> String
    var secSub: String { get }
    func secTagOffCount(_ n: Int) -> String
    func secTagEnabling(_ p: SecurityProtection) -> String
    var secTagUpdates: String { get }
    func secTagCrashes(_ n: Int) -> String
    func secTagOnCount(_ n: Int) -> String
    func secCaptionOn(_ n: Int) -> String
    func secCaptionEnabling(_ p: SecurityProtection) -> String
    var secValueOn: String { get }
    var secValueOff: String { get }
    var secValueEnabling: String { get }
    var secNoteUnknown: String { get }
    var secNoteTouchID: String { get }
    var secNoteWaitingTouchID: String { get }
    var secNoteFileVault: String { get }
    var secNoteFileVaultOpened: String { get }
    var secNoteSip: String { get }
    var secOpenSettings: String { get }
    var secBannerTimeout: String { get }
    var secBannerCancelled: String { get }
    func secBannerFailed(_ p: SecurityProtection, _ detail: String) -> String
    func secStillOff(_ p: SecurityProtection) -> String
    func secEnableA11y(_ name: String) -> String
    var secOpenFileVaultA11y: String { get }
    var secRefreshA11y: String { get }
    var secUpdatesCaptionChecking: String { get }
    var secUpdatesCaptionNever: String { get }
    func secUpdatesCaptionAvailable(_ n: Int) -> String
    var secCheckingUpdates: String { get }
    var secUpdatesNone: String { get }
    func secUpdatesAvailable(_ n: Int) -> String
    var secUpdatesRestart: String { get }
    var secUpdatesFailed: String { get }
    var secInstallA11y: String { get }
    var secOpenSoftwareUpdateA11y: String { get }
    var secCrashesTitle: String { get }
    var secCrashesCaption: String { get }
    func secCrashesCaptionCount(_ n: Int) -> String
    var secNoCrashes: String { get }
    var secKernelPanic: String { get }
    func secCrashLastToday(_ t: String) -> String
    func secCrashDate(_ d: String) -> String
    var secCrashFootDefault: String { get }
    func secCrashFootOpened(_ file: String) -> String
    var secOpenInConsole: String { get }
    func secCrashRowA11y(_ name: String, _ count: String) -> String
    var secCrashHide: String { get }
    var secCrashDelete: String { get }
    var secCrashUnhide: String { get }
    func secCrashHideA11y(_ name: String) -> String
    func secCrashDeleteA11y(_ name: String) -> String
    func secCrashUnhideA11y(_ name: String) -> String
    func secCrashDeleteConfirmTitle(_ n: Int) -> String
    var secCrashDeleteParagraphUser: String { get }
    var secCrashDeleteParagraphSystem: String { get }
    func secCrashDeleteRefused(_ name: String) -> String
}

extension StringsEN: SecurityStrings {
    // MARK: Security card
    var securityTitle: String { "Security" }
    var securityFileVault: String { "FileVault" }
    var securitySip: String { "SIP" }
    var securityFirewall: String { "Firewall" }
    var securityGatekeeper: String { "Gatekeeper" }
    var securityFileVaultTip: String { "Full-disk encryption — without your password the data on the drive cannot be read." }
    var securitySipTip: String { "System Integrity Protection — even an administrator cannot modify system files." }
    var securityFirewallTip: String { "Blocks unsolicited incoming network connections." }
    var securityGatekeeperTip: String { "Checks that the apps you launch are signed and notarized by Apple." }

    // MARK: Security page (REDESIGN-SECURITY)
    func shortDateTime(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "MMM d, HH:mm"
        return df.string(from: d)
    }
    var secSub: String { "protection, updates and crashes" }
    func secTagOffCount(_ n: Int) -> String { "\(n) of 4 off" }
    func secTagEnabling(_ p: SecurityProtection) -> String { p == .firewall ? "enabling firewall…" : "enabling Gatekeeper…" }
    var secTagUpdates: String { "updates available" }
    func secTagCrashes(_ n: Int) -> String { n == 1 ? "1 crash in 7 days" : "\(n) crashes in 7 days" }
    func secTagOnCount(_ n: Int) -> String { "\(n) of 4 on" }
    func secCaptionOn(_ n: Int) -> String { "\(n) of 4 on" }
    func secCaptionEnabling(_ p: SecurityProtection) -> String { p == .firewall ? "· enabling firewall…" : "· enabling Gatekeeper…" }
    var secValueOn: String { "on" }
    var secValueOff: String { "off" }
    var secValueEnabling: String { "Enabling…" }
    var secNoteUnknown: String { "not determined" }
    var secNoteTouchID: String { "Touch ID required" }
    var secNoteWaitingTouchID: String { "waiting for Touch ID…" }
    var secNoteFileVault: String { "password and recovery key needed" }
    var secNoteFileVaultOpened: String { "System Settings opened" }
    var secNoteSip: String { "can only be turned on in Recovery mode" }
    var secOpenSettings: String { "Open Settings…" }
    var secBannerTimeout: String { "Touch ID didn’t respond within 30 s." }
    var secBannerCancelled: String { "Authorization cancelled." }
    func secBannerFailed(_ p: SecurityProtection, _ detail: String) -> String {
        "Could not turn on \(p == .firewall ? "the firewall" : "Gatekeeper")" + (detail.isEmpty ? "" : " (\(detail))") + "."
    }
    func secStillOff(_ p: SecurityProtection) -> String { p == .firewall ? "The firewall is still off." : "Gatekeeper is still off." }
    func secEnableA11y(_ name: String) -> String { "Enable \(name) with Touch ID" }
    var secOpenFileVaultA11y: String { "Open FileVault in System Settings" }
    var secRefreshA11y: String { "Refresh protection, updates and crashes" }
    var secUpdatesCaptionChecking: String { "checking…" }
    var secUpdatesCaptionNever: String { "not checked" }
    func secUpdatesCaptionAvailable(_ n: Int) -> String { "· \(n) available" }
    var secCheckingUpdates: String { "Checking for updates…" }
    var secUpdatesNone: String { "No macOS updates — the system is up to date." }
    func secUpdatesAvailable(_ n: Int) -> String { n == 1 ? "1 update available." : "\(n) updates available." }
    var secUpdatesRestart: String { "The macOS update requires a restart." }
    var secUpdatesFailed: String { "Could not check for updates — press Refresh to try again." }
    var secInstallA11y: String { "Open Software Update in System Settings to install" }
    var secOpenSoftwareUpdateA11y: String { "Open Software Update in System Settings" }
    var secCrashesTitle: String { "Crashes in 7 days" }
    var secCrashesCaption: String { "own app and kernel panics" }
    func secCrashesCaptionCount(_ n: Int) -> String { (n == 1 ? "1 crash" : "\(n) crashes") + " · own app and kernel panics" }
    var secNoCrashes: String { "No crashes found" }
    var secKernelPanic: String { "Kernel panic" }
    func secCrashLastToday(_ t: String) -> String { "last today, \(t)" }
    func secCrashDate(_ d: String) -> String { d }
    var secCrashFootDefault: String { "Click a row to open the report in Console." }
    func secCrashFootOpened(_ file: String) -> String { "Opened in Console: \(file)" }
    var secOpenInConsole: String { "Open in Console" }
    func secCrashRowA11y(_ name: String, _ count: String) -> String { "\(name), \(count) — open the report in Console" }
    var secCrashHide: String { "Hide" }
    var secCrashDelete: String { "Delete" }
    var secCrashUnhide: String { "Show again" }
    func secCrashHideA11y(_ name: String) -> String { "Hide crashes: \(name)" }
    func secCrashDeleteA11y(_ name: String) -> String { "Delete crash reports: \(name)" }
    func secCrashUnhideA11y(_ name: String) -> String { "Show crashes again: \(name)" }
    func secCrashDeleteConfirmTitle(_ n: Int) -> String { n == 1 ? "Delete 1 crash report?" : "Delete \(n) crash reports?" }
    var secCrashDeleteParagraphUser: String { "Reports from your user folder will be moved to the Trash." }
    var secCrashDeleteParagraphSystem: String { "Reports in the system folder will be deleted permanently. Touch ID or an administrator password is required." }
    func secCrashDeleteRefused(_ name: String) -> String { "Nothing was deleted: \(name) is not a crash report file in a DiagnosticReports folder." }
}

extension StringsRU: SecurityStrings {
    // MARK: Security card
    var securityTitle: String { "Безопасность" }
    var securityFileVault: String { "FileVault" }
    var securitySip: String { "SIP" }
    var securityFirewall: String { "Файрвол" }
    var securityGatekeeper: String { "Gatekeeper" }
    var securityFileVaultTip: String { "Шифрование диска — без вашего пароля данные на диске прочитать нельзя." }
    var securitySipTip: String { "Защита целостности системы — даже администратор не может менять системные файлы." }
    var securityFirewallTip: String { "Блокирует незапрошенные входящие сетевые подключения." }
    var securityGatekeeperTip: String { "Проверяет, что запускаемые приложения подписаны и заверены Apple." }

    // MARK: Security page (REDESIGN-SECURITY)
    func shortDateTime(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: d)
        let m = c.month ?? 1
        let month = m == 5 ? "мая" : iphoneChartMonth(m) + "."
        return "\(c.day ?? 1) \(month), " + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    var secSub: String { "защита, обновления и сбои" }
    func secTagOffCount(_ n: Int) -> String { "выключено \(n) из 4" }
    func secTagEnabling(_ p: SecurityProtection) -> String { p == .firewall ? "включаем брандмауэр…" : "включаем Gatekeeper…" }
    var secTagUpdates: String { "есть обновления" }
    func secTagCrashes(_ n: Int) -> String { "\(n) \(ruPlural(n, "сбой", "сбоя", "сбоев")) за 7 дней" }
    func secTagOnCount(_ n: Int) -> String { "\(n) из 4 включены" }
    func secCaptionOn(_ n: Int) -> String { "\(n) из 4 включены" }
    func secCaptionEnabling(_ p: SecurityProtection) -> String { p == .firewall ? "· включаем брандмауэр…" : "· включаем Gatekeeper…" }
    var secValueOn: String { "включён" }
    var secValueOff: String { "выключен" }
    var secValueEnabling: String { "Включение…" }
    var secNoteUnknown: String { "не определено" }
    var secNoteTouchID: String { "нужен Touch ID" }
    var secNoteWaitingTouchID: String { "ждём Touch ID…" }
    var secNoteFileVault: String { "нужны пароль и ключ восстановления" }
    var secNoteFileVaultOpened: String { "открыты Системные настройки" }
    var secNoteSip: String { "включается только в режиме восстановления" }
    var secOpenSettings: String { "Открыть настройки…" }
    var secBannerTimeout: String { "Touch ID не ответил за 30 с." }
    var secBannerCancelled: String { "Авторизация отменена." }
    func secBannerFailed(_ p: SecurityProtection, _ detail: String) -> String {
        "Не удалось включить \(p == .firewall ? "брандмауэр" : "Gatekeeper")" + (detail.isEmpty ? "" : " (\(detail))") + "."
    }
    func secStillOff(_ p: SecurityProtection) -> String { p == .firewall ? "Брандмауэр по-прежнему выключен." : "Gatekeeper по-прежнему выключен." }
    func secEnableA11y(_ name: String) -> String { "Включить \(name) через Touch ID" }
    var secOpenFileVaultA11y: String { "Открыть FileVault в Системных настройках" }
    var secRefreshA11y: String { "Обновить защиту, обновления и сбои" }
    var secUpdatesCaptionChecking: String { "проверка…" }
    var secUpdatesCaptionNever: String { "не проверялось" }
    func secUpdatesCaptionAvailable(_ n: Int) -> String { "· \(n) доступно" }
    var secCheckingUpdates: String { "Проверяем обновления…" }
    var secUpdatesNone: String { "Обновлений macOS нет — система актуальна." }
    func secUpdatesAvailable(_ n: Int) -> String { "Доступно \(n) \(ruPlural(n, "обновление", "обновления", "обновлений"))." }
    var secUpdatesRestart: String { "Для macOS нужна перезагрузка." }
    var secUpdatesFailed: String { "Не удалось проверить обновления — нажмите «Обновить»." }
    var secInstallA11y: String { "Открыть «Обновление ПО» в Системных настройках для установки" }
    var secOpenSoftwareUpdateA11y: String { "Открыть «Обновление ПО» в Системных настройках" }
    var secCrashesTitle: String { "Сбои за 7 дней" }
    var secCrashesCaption: String { "своё приложение и паники ядра" }
    func secCrashesCaptionCount(_ n: Int) -> String { "\(n) \(ruPlural(n, "сбой", "сбоя", "сбоев")) · своё приложение и паники ядра" }
    var secNoCrashes: String { "Сбоев не найдено" }
    var secKernelPanic: String { "Паника ядра" }
    func secCrashLastToday(_ t: String) -> String { "последний сегодня, \(t)" }
    func secCrashDate(_ d: String) -> String { d }
    var secCrashFootDefault: String { "Нажмите на строку, чтобы открыть отчёт в Console." }
    func secCrashFootOpened(_ file: String) -> String { "Открыто в Console: \(file)" }
    var secOpenInConsole: String { "Открыть в Console" }
    func secCrashRowA11y(_ name: String, _ count: String) -> String { "\(name), \(count) — открыть отчёт в Console" }
    var secCrashHide: String { "Скрыть" }
    var secCrashDelete: String { "Удалить" }
    var secCrashUnhide: String { "Показать снова" }
    func secCrashHideA11y(_ name: String) -> String { "Скрыть сбои: \(name)" }
    func secCrashDeleteA11y(_ name: String) -> String { "Удалить отчёты о сбоях: \(name)" }
    func secCrashUnhideA11y(_ name: String) -> String { "Снова показывать сбои: \(name)" }
    func secCrashDeleteConfirmTitle(_ n: Int) -> String { "Удалить \(n) \(ruPlural(n, "отчёт о сбое", "отчёта о сбоях", "отчётов о сбоях"))?" }
    var secCrashDeleteParagraphUser: String { "Отчёты из папки пользователя будут перемещены в Корзину." }
    var secCrashDeleteParagraphSystem: String { "Отчёты из системной папки будут удалены безвозвратно. Нужен Touch ID или пароль администратора." }
    func secCrashDeleteRefused(_ name: String) -> String { "Ничего не удалено: \(name) — не файл отчёта о сбое в папке DiagnosticReports." }
}
