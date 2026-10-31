// Engine/Strings/Strings+System.swift
// System page: the `SystemStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol SystemStrings {
    // MARK: - System page (REDESIGN-SYSTEM)
    func shortDate(_ d: Date) -> String
    var sysSub: String { get }
    var sysTagApplyFailed: String { get }
    var sysTagOutdated: String { get }
    var sysTagUpdating: String { get }
    var sysOK: String { get }
    var sysSleepTitle: String { get }
    var sysSleepCaption: String { get }
    var sysSleepCaptionNone: String { get }
    var sysSleepNone: String { get }
    var sysActivityMonitor: String { get }
    var sysDontWarn: String { get }
    func sysDontWarnA11y(_ name: String) -> String
    var sysHidden: String { get }
    func sysHiddenSince(_ date: String) -> String
    var sysHiddenNoDate: String { get }
    var sysWarnAgain: String { get }
    func sysWarnAgainA11y(_ name: String) -> String
    var sysStartupTitle: String { get }
    func sysStartupItems(_ n: Int) -> String
    func sysStartupRemoved(_ n: Int) -> String
    var sysCheckedJustNow: String { get }
    func sysCheckedAt(_ t: String) -> String
    var sysCheckStale: String { get }
    var sysChecking: String { get }
    var sysGroupLogin: String { get }
    var sysGroupUserAgents: String { get }
    var sysGroupSystemAgents: String { get }
    var sysGroupSystemDaemons: String { get }
    var sysGroupBackground: String { get }
    var sysGroupExpandedA11y: String { get }
    var sysGroupCollapsedA11y: String { get }
    func sysGroupStale(_ n: Int) -> String
    var sysStaleHelp: String { get }
    var sysNoStale: String { get }
    var sysDelete: String { get }
    func sysDeleteA11y(_ file: String) -> String
    func sysDeleteAll(_ n: Int) -> String
    var sysDeleting: String { get }
    func sysDeleteConfirmTitle(_ n: Int) -> String
    var sysDeleteParagraphUser: String { get }
    var sysDeleteParagraphSystem: String { get }
    func sysDeleteFailed(_ detail: String) -> String
    var sysDeleteCancelled: String { get }
    var sysDeleteTimedOut: String { get }
    var sysBrewTitle: String { get }
    func sysBrewCaptionOutdated(_ v: String, _ n: Int, _ total: Int?) -> String
    func sysBrewCaptionUpdating(_ v: String) -> String
    func sysBrewCaptionOk(_ v: String, _ total: Int?) -> String
    var sysBrewCaptionNone: String { get }
    var sysBrewCaptionUnknown: String { get }
    var sysBrewUpdate: String { get }
    func sysBrewUpdatingN(_ n: Int) -> String
    func sysBrewAllUpToDate(_ total: Int?) -> String
    func sysBrewCheckedToday(_ t: String) -> String
    func sysBrewCheckedOn(_ d: String) -> String
    var sysBrewNotInstalled: String { get }
    var sysBrewHowToInstall: String { get }
    func sysBrewFailedLine(_ line: String) -> String
    var sysBrewCheckFailed: String { get }
    var sysEnergyTitle: String { get }
    var sysEnergyCaption: String { get }
    var sysEnergyEmpty: String { get }
    var sysEnergyColSetting: String { get }
    var sysEnergyColBattery: String { get }
    var sysEnergyColAC: String { get }
    var sysEnergyRowDisplaySleep: String { get }
    var sysEnergyRowSleep: String { get }
    var sysEnergyRowDiskSleep: String { get }
    var sysEnergyRowPowerNap: String { get }
    var sysEnergyRowLPM: String { get }
    var sysEnergyRowStandby: String { get }
    var sysEnergyRowWoN: String { get }
    var sysEnergyRowHibernate: String { get }
    var sysEnergyRowTcpKeepalive: String { get }
    var sysEnergyRowLidwake: String { get }
    var sysEnergyInfoDisplaySleep: String { get }
    var sysEnergyInfoSleep: String { get }
    var sysEnergyInfoDiskSleep: String { get }
    var sysEnergyInfoPowerNap: String { get }
    var sysEnergyInfoLPM: String { get }
    var sysEnergyInfoStandby: String { get }
    var sysEnergyInfoWoN: String { get }
    var sysEnergyInfoHibernate: String { get }
    var sysEnergyInfoTcpKeepalive: String { get }
    var sysEnergyInfoLidwake: String { get }
    var sysEnergyOn: String { get }
    var sysEnergyOff: String { get }
    func sysEnergyInfoA11y(_ row: String) -> String
    func sysEnergyApply(_ n: Int) -> String
    var sysEnergyCancel: String { get }
    var sysEnergyReset: String { get }
    var sysEnergyResetHelp: String { get }
    var sysEnergyApplied: String { get }
    func sysEnergyConfirmTitle(_ n: Int) -> String
    var sysEnergyOnBattery: String { get }
    var sysEnergyOnAC: String { get }
    var sysEnergyConfirmAdmin: String { get }
    var sysEnergyConfirmApply: String { get }
    var sysEnergyCancelled: String { get }
    var sysEnergyTimedOut: String { get }
    func sysEnergyFailed(_ detail: String) -> String
    func batMAh(_ s: String) -> String
    func batMA(_ s: String) -> String
    var batConditionNormal: String { get }
    var batConditionService: String { get }
    var batConditionReplaceSoon: String { get }
    var batConditionReplaceNow: String { get }
    var batConditionCheck: String { get }
}

extension StringsEN: SystemStrings {
    // MARK: System page (REDESIGN-SYSTEM)
    func shortDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "MMM d"
        return df.string(from: d)
    }
    var sysSub: String { "sleep, startup items, Homebrew, energy" }
    var sysTagApplyFailed: String { "Apply failed" }
    var sysTagOutdated: String { "Outdated packages" }
    var sysTagUpdating: String { "Updating…" }
    var sysOK: String { "OK" }
    var sysSleepTitle: String { "Sleep" }
    var sysSleepCaption: String { "what keeps the Mac awake" }
    var sysSleepCaptionNone: String { "Mac sleeps normally" }
    var sysSleepNone: String { "Nothing prevents sleep." }
    var sysActivityMonitor: String { "Activity Monitor" }
    var sysDontWarn: String { "Don’t warn" }
    func sysDontWarnA11y(_ name: String) -> String { "Don’t warn about \(name)" }
    var sysHidden: String { "Hidden" }
    func sysHiddenSince(_ date: String) -> String { "not warned since \(date)" }
    var sysHiddenNoDate: String { "not warned" }
    var sysWarnAgain: String { "Warn again" }
    func sysWarnAgainA11y(_ name: String) -> String { "Warn again about \(name)" }
    var sysStartupTitle: String { "Startup items" }
    func sysStartupItems(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }
    func sysStartupRemoved(_ n: Int) -> String { " · \(n) removed" }
    var sysCheckedJustNow: String { " · checked just now" }
    func sysCheckedAt(_ t: String) -> String { " · checked \(t)" }
    var sysCheckStale: String { "Check for stale" }
    var sysChecking: String { "Checking…" }
    var sysGroupLogin: String { "Login items" }
    var sysGroupUserAgents: String { "User agents" }
    var sysGroupSystemAgents: String { "System agents" }
    var sysGroupSystemDaemons: String { "System daemons" }
    var sysGroupBackground: String { "Background tasks (non-Apple)" }
    var sysGroupExpandedA11y: String { "expanded" }
    var sysGroupCollapsedA11y: String { "collapsed" }
    func sysGroupStale(_ n: Int) -> String { "stale: \(n)" }
    var sysStaleHelp: String { "Stale — the app was removed, safe to delete" }
    var sysNoStale: String { "No stale items" }
    var sysDelete: String { "Delete" }
    func sysDeleteA11y(_ file: String) -> String { "Delete \(file)" }
    func sysDeleteAll(_ n: Int) -> String { "Delete all (\(n))" }
    var sysDeleting: String { "Deleting…" }
    func sysDeleteConfirmTitle(_ n: Int) -> String { n == 1 ? "Delete 1 startup item?" : "Delete \(n) startup items?" }
    var sysDeleteParagraphUser: String { "The file will be moved to the Trash. The change takes effect after the next login or restart." }
    var sysDeleteParagraphSystem: String { "The file will be deleted permanently. Touch ID or an administrator password is required. The change takes effect after a restart." }
    func sysDeleteFailed(_ detail: String) -> String { "Couldn’t delete: \(detail)" }
    var sysDeleteCancelled: String { "Authorization cancelled. Nothing was deleted." }
    var sysDeleteTimedOut: String { "Touch ID didn’t respond within 30 s. Nothing was deleted." }
    var sysBrewTitle: String { "Homebrew" }
    func sysBrewCaptionOutdated(_ v: String, _ n: Int, _ total: Int?) -> String { total.map { "\(v) · \(n) of \($0) packages outdated" } ?? "\(v) · \(n) outdated" }
    func sysBrewCaptionUpdating(_ v: String) -> String { "\(v) · updating" }
    func sysBrewCaptionOk(_ v: String, _ total: Int?) -> String { total.map { "\(v) · \($0) " + ($0 == 1 ? "package" : "packages") } ?? v }
    var sysBrewCaptionNone: String { "not installed" }
    var sysBrewCaptionUnknown: String { "version unknown" }
    var sysBrewUpdate: String { "Update packages…" }
    func sysBrewUpdatingN(_ n: Int) -> String { n == 1 ? "Updating 1 package…" : "Updating \(n) packages…" }
    func sysBrewAllUpToDate(_ total: Int?) -> String { total.map { "All \($0) packages are up to date." } ?? "All packages are up to date." }
    func sysBrewCheckedToday(_ t: String) -> String { "Checked today at \(t)." }
    func sysBrewCheckedOn(_ d: String) -> String { "Checked \(d)." }
    var sysBrewNotInstalled: String { "Homebrew isn’t installed, so there is nothing to show here." }
    var sysBrewHowToInstall: String { "How to install" }
    func sysBrewFailedLine(_ line: String) -> String { "Update failed: \(line)" }
    var sysBrewCheckFailed: String { "Couldn’t check for outdated packages." }
    var sysEnergyTitle: String { "Energy settings (pmset)" }
    var sysEnergyCaption: String { "changes require an administrator password" }
    var sysEnergyEmpty: String { "Couldn’t read the energy settings (pmset)." }
    var sysEnergyColSetting: String { "Setting" }
    var sysEnergyColBattery: String { "Battery" }
    var sysEnergyColAC: String { "AC power" }
    var sysEnergyRowDisplaySleep: String { "Display sleep, min" }
    var sysEnergyRowSleep: String { "System sleep, min" }
    var sysEnergyRowDiskSleep: String { "Disk sleep, min" }
    var sysEnergyRowPowerNap: String { "Power Nap" }
    var sysEnergyRowLPM: String { "Low Power Mode" }
    var sysEnergyRowStandby: String { "Standby" }
    var sysEnergyRowWoN: String { "Wake on network" }
    var sysEnergyRowHibernate: String { "Hibernate mode" }
    var sysEnergyRowTcpKeepalive: String { "tcpkeepalive" }
    var sysEnergyRowLidwake: String { "lidwake" }
    var sysEnergyInfoDisplaySleep: String { "Minutes of inactivity before the display turns off." }
    var sysEnergyInfoSleep: String { "0 means the Mac never sleeps on its own while on AC power." }
    var sysEnergyInfoDiskSleep: String { "Has almost no effect on energy use with an SSD." }
    var sysEnergyInfoPowerNap: String { "The Mac checks mail and updates while asleep." }
    var sysEnergyInfoLPM: String { "Lowers CPU clock and screen brightness." }
    var sysEnergyInfoStandby: String { "After long sleep, saves memory to disk and powers down almost fully." }
    var sysEnergyInfoWoN: String { "Lets the Mac wake for network access, e.g. file sharing." }
    var sysEnergyInfoHibernate: String { "3 keeps memory in both RAM and on disk. Change it only in Terminal." }
    var sysEnergyInfoTcpKeepalive: String { "Keeps network connections alive during sleep. Read-only." }
    var sysEnergyInfoLidwake: String { "Wakes the Mac when the lid opens. Read-only." }
    var sysEnergyOn: String { "on" }
    var sysEnergyOff: String { "off" }
    func sysEnergyInfoA11y(_ row: String) -> String { "Explain \(row)" }
    func sysEnergyApply(_ n: Int) -> String { "Apply (\(n))" }
    var sysEnergyCancel: String { "Cancel" }
    var sysEnergyReset: String { "Reset to defaults" }
    var sysEnergyResetHelp: String { "Fills in default values; press Apply to apply them" }
    var sysEnergyApplied: String { "Applied ✓" }
    func sysEnergyConfirmTitle(_ n: Int) -> String { n == 1 ? "Apply 1 change?" : "Apply \(n) changes?" }
    var sysEnergyOnBattery: String { "On battery:" }
    var sysEnergyOnAC: String { "On AC power:" }
    var sysEnergyConfirmAdmin: String { "Touch ID or administrator password required." }
    var sysEnergyConfirmApply: String { "Apply" }
    var sysEnergyCancelled: String { "Authentication cancelled. Nothing was changed; your edits are kept and can be applied again." }
    var sysEnergyTimedOut: String { "Touch ID didn’t respond within 30 s. Nothing was changed; your edits are kept and can be applied again." }
    func sysEnergyFailed(_ detail: String) -> String { "Couldn’t apply: pmset returned an error (\(detail)). Values were reverted." }
    func batMAh(_ s: String) -> String { "\(s) mAh" }
    func batMA(_ s: String) -> String { "\(s) mA" }
    var batConditionNormal: String { "Normal" }
    var batConditionService: String { "Service Recommended" }
    var batConditionReplaceSoon: String { "Replace Soon" }
    var batConditionReplaceNow: String { "Replace Now" }
    var batConditionCheck: String { "Check Battery" }
}

extension StringsRU: SystemStrings {
    // MARK: System page (REDESIGN-SYSTEM)
    func shortDate(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        let m = c.month ?? 1
        let month = m == 5 ? "мая" : iphoneChartMonth(m) + "."
        return "\(c.day ?? 1) \(month)"
    }
    var sysSub: String { "сон, автозагрузка, Homebrew, энергия" }
    var sysTagApplyFailed: String { "Ошибка применения" }
    var sysTagOutdated: String { "Есть устаревшие пакеты" }
    var sysTagUpdating: String { "Обновление…" }
    var sysOK: String { "OK" }
    var sysSleepTitle: String { "Сон" }
    var sysSleepCaption: String { "кто не даёт Mac уснуть" }
    var sysSleepCaptionNone: String { "Mac засыпает как обычно" }
    var sysSleepNone: String { "Ничто не мешает сну." }
    var sysActivityMonitor: String { "Мониторинг системы" }
    var sysDontWarn: String { "Не предупреждать" }
    func sysDontWarnA11y(_ name: String) -> String { "Не предупреждать про \(name)" }
    var sysHidden: String { "Скрытые" }
    func sysHiddenSince(_ date: String) -> String { "не предупреждаем с \(date)" }
    var sysHiddenNoDate: String { "не предупреждаем" }
    var sysWarnAgain: String { "Снова предупреждать" }
    func sysWarnAgainA11y(_ name: String) -> String { "Снова предупреждать про \(name)" }
    var sysStartupTitle: String { "Автозагрузка" }
    func sysStartupItems(_ n: Int) -> String { "\(n) " + ruPlural(n, "объект", "объекта", "объектов") }
    func sysStartupRemoved(_ n: Int) -> String { " · удалено \(n)" }
    var sysCheckedJustNow: String { " · проверено только что" }
    func sysCheckedAt(_ t: String) -> String { " · проверено \(t)" }
    var sysCheckStale: String { "Проверить устаревшие" }
    var sysChecking: String { "Проверяю…" }
    var sysGroupLogin: String { "Объекты входа" }
    var sysGroupUserAgents: String { "Агенты пользователя" }
    var sysGroupSystemAgents: String { "Системные агенты" }
    var sysGroupSystemDaemons: String { "Системные демоны" }
    var sysGroupBackground: String { "Фоновые задачи (не Apple)" }
    var sysGroupExpandedA11y: String { "развёрнуто" }
    var sysGroupCollapsedA11y: String { "свёрнуто" }
    func sysGroupStale(_ n: Int) -> String { "устарело: \(n)" }
    var sysStaleHelp: String { "Устарел — приложение удалено, можно убрать" }
    var sysNoStale: String { "Устаревших нет" }
    var sysDelete: String { "Удалить" }
    func sysDeleteA11y(_ file: String) -> String { "Удалить \(file)" }
    func sysDeleteAll(_ n: Int) -> String { "Удалить все (\(n))" }
    var sysDeleting: String { "Удаляю…" }
    func sysDeleteConfirmTitle(_ n: Int) -> String { "Удалить \(n) " + ruPlural(n, "объект", "объекта", "объектов") + " автозагрузки?" }
    var sysDeleteParagraphUser: String { "Файл будет перемещён в Корзину. Изменение вступит в силу после следующего входа или перезагрузки." }
    var sysDeleteParagraphSystem: String { "Файл будет удалён без возможности восстановления. Нужен Touch ID или пароль администратора. Изменение вступит в силу после перезагрузки." }
    func sysDeleteFailed(_ detail: String) -> String { "Не удалось удалить: \(detail)" }
    var sysDeleteCancelled: String { "Авторизация отменена. Ничего не удалено." }
    var sysDeleteTimedOut: String { "Touch ID не ответил за 30 с. Ничего не удалено." }
    var sysBrewTitle: String { "Homebrew" }
    func sysBrewCaptionOutdated(_ v: String, _ n: Int, _ total: Int?) -> String { total.map { "\(v) · \(n) из \($0) пакетов " + ruPlural(n, "устарел", "устарели", "устарели") } ?? "\(v) · \(n) " + ruPlural(n, "пакет устарел", "пакета устарели", "пакетов устарели") }
    func sysBrewCaptionUpdating(_ v: String) -> String { "\(v) · обновление" }
    func sysBrewCaptionOk(_ v: String, _ total: Int?) -> String { total.map { "\(v) · \($0) " + ruPlural($0, "пакет", "пакета", "пакетов") } ?? v }
    var sysBrewCaptionNone: String { "не установлен" }
    var sysBrewCaptionUnknown: String { "версия неизвестна" }
    var sysBrewUpdate: String { "Обновить пакеты…" }
    func sysBrewUpdatingN(_ n: Int) -> String { "Обновляю \(n) " + ruPlural(n, "пакет", "пакета", "пакетов") + "…" }
    func sysBrewAllUpToDate(_ total: Int?) -> String { total.map { "Все \($0) " + ruPlural($0, "пакет актуален", "пакета актуальны", "пакетов актуальны") + "." } ?? "Все пакеты актуальны." }
    func sysBrewCheckedToday(_ t: String) -> String { "Проверено сегодня в \(t)." }
    func sysBrewCheckedOn(_ d: String) -> String { "Проверено \(d)." }
    var sysBrewNotInstalled: String { "Homebrew не установлен — разделу нечего показать." }
    var sysBrewHowToInstall: String { "Как установить" }
    func sysBrewFailedLine(_ line: String) -> String { "Обновление не удалось: \(line)" }
    var sysBrewCheckFailed: String { "Не удалось проверить устаревшие пакеты." }
    var sysEnergyTitle: String { "Энергосбережение (pmset)" }
    var sysEnergyCaption: String { "изменения применяются с паролем администратора" }
    var sysEnergyEmpty: String { "Не удалось прочитать настройки энергии (pmset)." }
    var sysEnergyColSetting: String { "Параметр" }
    var sysEnergyColBattery: String { "От батареи" }
    var sysEnergyColAC: String { "От сети" }
    var sysEnergyRowDisplaySleep: String { "Сон дисплея, мин" }
    var sysEnergyRowSleep: String { "Сон системы, мин" }
    var sysEnergyRowDiskSleep: String { "Сон диска, мин" }
    var sysEnergyRowPowerNap: String { "Power Nap" }
    var sysEnergyRowLPM: String { "Энергосбережение" }
    var sysEnergyRowStandby: String { "Режим ожидания" }
    var sysEnergyRowWoN: String { "Пробуждение по сети" }
    var sysEnergyRowHibernate: String { "Режим гибернации" }
    var sysEnergyRowTcpKeepalive: String { "tcpkeepalive" }
    var sysEnergyRowLidwake: String { "lidwake" }
    var sysEnergyInfoDisplaySleep: String { "Через сколько минут бездействия гаснет экран." }
    var sysEnergyInfoSleep: String { "0 — Mac не засыпает сам, пока подключён к сети." }
    var sysEnergyInfoDiskSleep: String { "Для SSD почти не влияет на расход энергии." }
    var sysEnergyInfoPowerNap: String { "Mac проверяет почту и обновления во сне." }
    var sysEnergyInfoLPM: String { "Снижает частоту процессора и яркость экрана." }
    var sysEnergyInfoStandby: String { "После долгого сна сохраняет память на диск и почти полностью выключается." }
    var sysEnergyInfoWoN: String { "Позволяет будить Mac по сети, например для общего доступа к файлам." }
    var sysEnergyInfoHibernate: String { "3 — память хранится и в ОЗУ, и на диске. Меняется только из Терминала." }
    var sysEnergyInfoTcpKeepalive: String { "Поддерживает сетевые соединения во сне. Только для чтения." }
    var sysEnergyInfoLidwake: String { "Пробуждение при открытии крышки. Только для чтения." }
    var sysEnergyOn: String { "вкл" }
    var sysEnergyOff: String { "выкл" }
    func sysEnergyInfoA11y(_ row: String) -> String { "Пояснение: \(row)" }
    func sysEnergyApply(_ n: Int) -> String { "Применить (\(n))" }
    var sysEnergyCancel: String { "Отменить" }
    var sysEnergyReset: String { "Сбросить к стандартным" }
    var sysEnergyResetHelp: String { "Подставляет стандартные значения; применяются они кнопкой «Применить»" }
    var sysEnergyApplied: String { "Применено ✓" }
    func sysEnergyConfirmTitle(_ n: Int) -> String { "Применить \(n) " + ruPlural(n, "изменение", "изменения", "изменений") + "?" }
    var sysEnergyOnBattery: String { "От батареи:" }
    var sysEnergyOnAC: String { "От сети:" }
    var sysEnergyConfirmAdmin: String { "Потребуется Touch ID или пароль администратора." }
    var sysEnergyConfirmApply: String { "Применить" }
    var sysEnergyCancelled: String { "Авторизация отменена. Ничего не изменено — правки остались, их можно применить снова." }
    var sysEnergyTimedOut: String { "Touch ID не ответил за 30 с. Ничего не изменено — правки остались, их можно применить снова." }
    func sysEnergyFailed(_ detail: String) -> String { "Не удалось применить: pmset вернул ошибку (\(detail)). Значения откатились к прежним." }
    func batMAh(_ s: String) -> String { "\(s) мАч" }
    func batMA(_ s: String) -> String { "\(s) мА" }
    var batConditionNormal: String { "В норме" }
    var batConditionService: String { "Рекомендуется сервис" }
    var batConditionReplaceSoon: String { "Скоро заменить" }
    var batConditionReplaceNow: String { "Заменить" }
    var batConditionCheck: String { "Проверить батарею" }
}
