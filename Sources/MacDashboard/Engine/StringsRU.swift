// Engine/StringsRU.swift
// Russian string table: literal values extracted from the views, character-for-
// character (including «», ·, — where present). Same MARK grouping as AppStrings.
import Foundation

struct StringsRU: AppStrings {
    // MARK: App
    var decimalSeparator: String { "," }

    // MARK: Settings
    var settingsLanguageLabel: String { "Язык интерфейса" }
    var settingsIntervalLabel: String { "Интервал обновления (процессор/память)" }
    func settingsIntervalOption(_ seconds: Int) -> String { "\(seconds) с" }
    var settingsIntervalNoteBalanced: String { "Рабочий диапазон: живые графики без заметной нагрузки." }
    var settingsIntervalNoteEconomy: String { "Экономный режим: значения обновляются реже, батарея живёт дольше." }
    var settingsWakeIgnoredLabel: String { "Сон: не предупреждать про эти приложения" }
    var settingsWakeIgnoredEmpty: String { "Список пуст. Чтобы добавить приложение, щёлкните правой кнопкой по предупреждению «Сон» в главном окне." }
    var settingsWakeIgnoredRestore: String { "Снова предупреждать" }
    func settingsWakeIgnoredRestoreA11y(_ holder: String) -> String { "Снова предупреждать про \(holder)" }
    var settingsSectionBackup: String { "Бэкап" }
    var settingsBackupStaleLabel: String { "Бэкап Claude: предупреждать, если старше" }
    func settingsBackupStaleOption(_ hours: Int) -> String { "\(hours / 24) дн" }
    var settingsBackupStaleNote: String { "Возраст берётся из журнала ~/Library/Logs/claude-backup.log, поэтому он известен и при отключённом или заблокированном диске." }
    var settingsMenuLanguageHint: String { "Язык меню и системных диалогов применится после перезапуска приложения" }
    var settingsRelaunchNow: String { "Перезапустить сейчас" }
    var settingsSectionGeneral: String { "Общие" }
    var settingsSectionMonitoring: String { "Мониторинг" }
    var settingsVersionLabel: String { "Версия" }
    var settingsWindowTitle: String { "Настройки" }

    // MARK: Main dashboard (header + tab picker)
    var mainCollectingInfo: String { "Собираем сведения о системе…" }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { "Метрики" }
    var overviewKickerMemory: String { "Память" }
    var overviewKickerProcesses: String { "Процессы" }
    var overviewKickerFolders: String { "Папки" }
    var overviewKickerSystem: String { "Система" }
    var overviewKickerHistory: String { "История" }

    func headerLoadChip(_ load: String, _ ncpu: Int) -> String {
        "load \(load) · \(ncpu) \(ruPlural(ncpu, "ядро", "ядра", "ядер"))"
    }
    func headerUptimeChip(_ uptime: String) -> String { "аптайм \(uptime)" }
    var headerRefreshReport: String { "Обновить отчёт" }
    var headerStatusNeedsAttention: String { "Требует внимания" }

    // MARK: KPI tiles
    var kpiCpuLabel: String { "CPU" }
    var kpiSwapLabel: String { "Подкачка (swap)" }
    func kpiSwapUnit(_ total: String) -> String { "из \(total)" }
    func kpiSwapSub(_ free: String) -> String { "свободно \(free)" }
    var kpiDiskLabel: String { "Диск · свободно" }
    func kpiDiskUnit(_ size: String) -> String { "из \(size)" }
    func kpiDiskUsedPct(_ pct: Int) -> String { "занято \(pct)%" }
    func kpiDiskUsedDetail(_ base: String, _ dataUsed: String, _ sysUsed: String) -> String {
        base + " · данные \(dataUsed), система \(sysUsed)"
    }
    func kpiDiskPurgeableDetail(_ base: String, _ purgeable: String) -> String { base + " · очищаемое \(purgeable)" }
    var kpiBatteryLabel: String { "Батарея" }
    func kpiBatteryCycles(_ n: Int) -> String { "\(n) " + ruPlural(n, "цикл", "цикла", "циклов") }

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

    // MARK: Report tab
    var reportPlaceholder: String { "Отчёт ещё не собран. Нажмите «Обновить отчёт»." }
    var reportShowInFinder: String { "Показать в Finder" }
    var reportCopy: String { "Скопировать" }
    var reportCollecting: String { "Собираем отчёт…" }
    func reportFileUpdatedCaption(_ time: String) -> String { "mac_report.txt · обновлено \(time)" }

    // MARK: Recommendations card
    var recommendationsTitle: String { "Рекомендации" }
    var recommendationsAllGood: String { "Всё в порядке" }

    // MARK: Advice actions
    var adviceTrashConfirmTitle: String { "Очистить Корзину?" }
    var adviceTrashConfirmButton: String { "Очистить" }
    var adviceTrashError: String { "Не удалось очистить Корзину" }
    var adviceTrashNotPermitted: String { "У Дашборда нет разрешения управлять Finder, поэтому очистить Корзину не получилось. Разрешите это в «Конфиденциальность и безопасность» → «Автоматизация»." }
    var adviceTrashOpenAutomation: String { "Открыть настройки автоматизации" }
    var adviceFirewallConfirmTitle: String { "Включить файрвол?" }
    var adviceFirewallConfirmMessage: String { "Понадобится Touch ID или пароль администратора." }
    var adviceFirewallConfirmButton: String { "Включить" }
    var adviceFirewallError: String { "Не удалось включить файрвол" }
    var adviceCancel: String { "Отмена" }

    // MARK: Shared (cross-card)
    var sharedUnavailable: String { "(недоступно)" }
    var sharedCollectingData: String { "Собираем данные…" }
    var sharedEmpty: String { "пусто" }
    var sharedToggleToChart: String { "График" }
    var sharedToggleToTable: String { "Таблица" }
    var sharedToggleShowChart: String { "Показать график" }
    var sharedToggleShowTable: String { "Показать таблицу" }
    var sharedInfoHide: String { "Скрыть пояснение" }
    var sharedInfoShow: String { "Показать пояснение" }
    func sharedMoreN(_ n: Int) -> String { "Ещё \(n)" }
    var sharedCollapse: String { "Свернуть" }

    // MARK: Storage — shared folder labels
    var storageColShare: String { "Доля" }
    var storageTrashLabel: String { "Корзина" }
    var storageAppsLabel: String { "Программы" }


    func storageFoldersNoFDA(_ folders: String) -> String { "Здесь не показаны: \(folders) — у приложения нет полного доступа к диску." }
    var storageFoldersNoFDAButton: String { "Открыть настройки" }
    var storageFoldersNoFDAButtonA11y: String { "Открыть настройки полного доступа к диску" }
    func storageFoldersNotMeasured(_ folders: String) -> String { "Не успели измерить: \(folders)." }

    // MARK: Storage — Диски (SMART)
    func storageSmartUpdatedCaption(_ time: String) -> String { "обновлено \(time)" }

    // MARK: Process cards
    var processesTitle: String { "Процессы" }
    var processSegCPU: String { "CPU" }
    var processSegMem: String { "Память" }
    var processesMetricA11y: String { "Метрика процессов" }
    var processLoadingDetails: String { "Загружаем детали…" }
    var processDetailPath: String { "Путь" }
    var processQuit: String { "Завершить" }
    var processForceQuit: String { "Снять принудительно…" }
    var processForceQuitConfirm: String { "Снять принудительно" }
    func processTerminateA11y(_ name: String) -> String { "Завершить процесс „\(name)“" }
    func processKillA11y(_ name: String) -> String { "Принудительно снять процесс „\(name)“" }
    // REDESIGN-MEMORY
    var memUsageTitle: String { "Использование" }
    func memUsageCaption(_ total: String) -> String { "всего \(total) · живой срез" }
    var memCompTitle: String { "Состав памяти" }
    func memCompCaption(_ total: String) -> String { "\(total) · по типам страниц" }
    var memProcsTitle: String { "Процессы по памяти" }
    func memProcsTop(_ n: Int) -> String { "топ-\(n)" }
    func memProcCPU(_ pct: String) -> String { "\(pct) CPU" }
    var memUsed: String { "Использовано" }
    func memHeroNote(_ total: String, _ pct: String) -> String { "из \(total) · \(pct)" }
    var memPurgeable: String { "Очищаемая" }
    var memSwap: String { "Своп" }
    func memSwapOf(_ pct: String, _ total: String) -> String { "\(pct) из \(total)" }
    var memFileCache: String { "Файловый кэш" }
    var memOtherShort: String { "Прочее" }
    var memTagLow: String { "Давление: низкое" }
    var memTagMedium: String { "Давление: среднее" }
    var memTagHigh: String { "Давление: высокое" }
    var memTagUnknown: String { "Давление: неизвестно" }
    var memTagReadFailed: String { "Ошибка чтения" }
    func memUpdatesEvery(_ seconds: Int) -> String { "обновляется каждые \(seconds) с" }
    var memFailTimedOut: String { "Не удалось прочитать статистику памяти: нет ответа за 5 с." }
    var memFailNoReading: String { "Не удалось прочитать статистику памяти: система не вернула данных." }
    var memTryAgainA11y: String { "Повторить чтение статистики памяти" }
    var memCompViewA11y: String { "Вид состава памяти" }
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
    var storageSmartRefreshA11y: String { "Прочитать данные SMART заново" }
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
    // REDESIGN-CPU
    var cpuLiveSnapshot: String { "живой снимок" }
    var cpuUsage: String { "Загрузка" }
    var cpuUser: String { "Пользователь" }
    var cpuSystem: String { "Система" }
    var cpuSocTemperature: String { "Температура SoC" }
    var cpuSocHot: String { "горячо · возможен троттлинг" }
    var cpuSocWarm: String { "тепло" }
    var cpuNoReading: String { "Нет текущих данных" }
    func cpuLoadNote(_ a: String, _ b: String, _ c: String, _ cores: Int) -> String { "нагрузка \(a) · \(b) · \(c) · \(cores) " + ruPlural(cores, "ядро", "ядра", "ядер") }
    func cpuHighLoadFor(_ min: Int) -> String { "Высокая нагрузка уже \(min) мин" }
    var cpuTagHigh: String { "Высокая нагрузка" }
    var cpuTagReadError: String { "Ошибка чтения" }
    func cpuSubLive(_ cores: Int, _ seconds: Int) -> String { "\(cores) " + ruPlural(cores, "ядро", "ядра", "ядер") + " · обновляется каждые \(seconds) с" }
    var cpuSubCollecting: String { "сбор данных…" }
    var cpuFailTimedOut: String { "Не удалось прочитать счётчики CPU: нет ответа за 5 с." }
    var cpuFailNoReading: String { "Не удалось прочитать счётчики CPU: система не вернула данных." }
    var cpuTryAgainA11y: String { "Повторить чтение счётчиков CPU" }
    var procsTopByCPU: String { "топ по CPU" }
    var procsTopByMemory: String { "топ по памяти" }
    func procsCount(_ n: Int) -> String { "\(n) " + ruPlural(n, "процесс", "процесса", "процессов") }
    var procsFoot: String { "нажмите на процесс, чтобы увидеть PID, путь и кнопки «Завершить» / «Снять принудительно»" }
    var processOwner: String { "Владелец" }
    var processQuitting: String { "Завершение…" }
    func processForceQuitQuestion(_ name: String) -> String { "Снять «\(name)» принудительно? Несохранённые изменения будут потеряны." }
    func processSignalFailed(_ name: String) -> String { "Не удалось завершить «\(name)»." }

    // MARK: Maintenance card
    var maintenanceTitle: String { "Обслуживание системы" }
    var maintenanceBrewNotInstalled: String { "не установлен" }
    var maintenanceBrewVersionUnknown: String { "Homebrew установлен, но версию определить не удалось" }
    var maintenanceBrewAllFresh: String { "Все пакеты свежие \u{2713}" }
    func maintenanceBrewOutdatedCount(_ n: Int) -> String { "Устаревших пакетов: \(n)" }
    var maintenanceBrewOutdatedCheckFailed: String { "Не удалось проверить устаревшие пакеты — запустите brew outdated в Терминале" }
    var maintenanceUpdatesSection: String { "Обновления" }
    var maintenanceUpdatesAllUpdated: String { "\u{2713}" }
    var maintenanceCrashesSection: String { "Краши" }
    var maintenanceCrashesNone: String { "\u{2713}" }
    var maintenanceUpdatesTip: String { "Ожидающие обновления macOS и App Store." }
    var maintenanceCrashesTip: String { "Отчёты о падениях приложений за последние 7 дней." }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String { count > 1 ? "\(process) \u{00D7}\(count)" : process }
    func maintenanceCrashRevealA11y(_ process: String) -> String { "Показать отчёты о падениях «\(process)» в Finder" }
    func maintenanceAndMore(_ n: Int) -> String { "и ещё \(n)" }
    var maintenanceBrewUpgradeButton: String { "Обновить пакеты" }
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

    // MARK: Time Machine card
    var timeMachineNotConfigured: String { "Time Machine не настроен" }
    var timeMachineDestination: String { "Назначение" }
    var timeMachineType: String { "Тип" }
    var timeMachineTypeLocal: String { "локальный диск" }
    var timeMachineQuota: String { "Квота" }
    var timeMachineLastBackup: String { "Последний бэкап" }
    var timeMachineConnection: String { "Подключение" }
    var timeMachineConnectionNone: String { "сейчас нет подключения" }
    var timeMachineSnapshots: String { "Локальные снапшоты" }
    var timeMachineSnapshotsNone: String { "нет" }
    func timeMachineSnapshotsCount(_ n: Int) -> String { "\(n) шт." }
    func timeMachineSnapshotsLast(_ date: String) -> String { ", последний \(date)" }
    var timeMachinePurgeable: String { "Очищаемое место" }
    var timeMachinePurgeableTip: String { "Место, которое macOS освободит сама, когда оно понадобится: локальные снапшоты Time Machine и кэши. Размер отдельного снапшота посчитать нельзя — снапшоты делят общие блоки диска." }

    // MARK: Claude backup card (BACKUP-AGE)
    var claudeBackupCardTitle: String { "Бэкап Claude" }
    var claudeBackupAgeLabel: String { "Возраст" }
    var claudeBackupLastLabel: String { "Последний снимок" }
    var claudeBackupLimitLabel: String { "Предупреждать после" }
    func claudeBackupAgo(_ age: String) -> String { "\(age) назад" }
    var claudeBackupJustNow: String { "только что" }
    var claudeBackupNoneFound: String { "успешных снимков в журнале нет" }
    var claudeBackupUnreadable: String { "журнал не удалось прочитать" }

    // MARK: Autostart card
    var autostartTitle: String { "Автозагрузка" }
    var autostartNoPermission: String { "(нет разрешения)" }
    var autostartUserAgents: String { "Агенты пользователя" }
    var autostartSystemAgents: String { "Системные агенты" }
    var autostartSystemDaemons: String { "Системные демоны" }
    var autostartBackgroundTasks: String { "Фоновые задачи (не Apple)" }
    var autostartCheckOutdated: String { "Проверить устаревшие" }
    func autostartCheckOutdatedCount(_ n: Int) -> String { "Устаревших: \(n)" }
    var autostartOrphanEmptyText: String { "Устаревших плистов нет" }
    var autostartOrphanTooltip: String { "Устарел — приложение удалено, безопасно удалить" }
    var autostartDeleteButton: String { "Удалить" }
    var autostartDeleteConfirmMessageUser: String { "Файл будет перемещён в Корзину. Изменение вступит в силу после повторного входа в систему или перезагрузки." }
    var autostartDeleteConfirmMessageSystem: String { "Файл будет удалён без возможности восстановления (потребуется Touch ID или пароль администратора). Изменение вступит в силу после повторного входа в систему или перезагрузки." }
    func autostartDeleteError(_ detail: String) -> String { "Не удалось удалить: \(detail)" }
    func autostartDeleteAllButton(_ n: Int) -> String { "Удалить все (\(n))" }
    func autostartDeleteAllConfirmMessageUser(_ n: Int) -> String { "Переместить в Корзину все устаревшие плисты (\(n))?" }
    func autostartDeleteAllConfirmMessageSystem(_ n: Int) -> String { "Среди них есть системные — потребуется пароль. Удалить все (\(n))?" }
    var autostartDeletingAll: String { "Удаляю…" }
    var autostartOkTooltip: String { "В порядке" }
    var autostartDeleteInvalidPath: String { "путь не похож на плист автозагрузки" }
    func autostartDeleteBulkFailure(_ failed: Int, _ total: Int, _ detail: String) -> String {
        "\(failed) из \(total): \(detail)"
    }

    // MARK: Memory card
    var memoryLegendActive: String { "Активная" }
    var memoryLegendWired: String { "Связанная (ядро)" }
    var memoryLegendOther: String { "Прочее (вкл. сжатую)" }
    var memoryLegendInactive: String { "Неактивная" }
    var memoryLegendSpeculative: String { "Спекулятивная" }
    var memoryLegendFree: String { "Свободно" }
    var memoryNoteActive: String { "Память, которую программы используют прямо сейчас или недавно к ней обращались." }
    var memoryNoteWired: String { "Занята ядром macOS и драйверами; не выгружается на диск и не освобождается." }
    var memoryNoteOther: String { "В основном сжатая память: macOS ужимает редко используемые страницы вместо записи в swap." }
    var memoryNoteInactive: String { "Давно не использовалась и будет отдана при нехватке; часто это данные недавно закрытых программ." }
    var memoryNoteSpeculative: String { "Прочитано с диска впрок, «на всякий случай»; освобождается в первую очередь." }
    var memoryNoteFree: String { "Совсем не занятая память. Малое значение — норма." }

    // MARK: History card
    var historyTitle: String { "История" }
    func historyCaption(_ n: Int) -> String { "mac_check_state.json · замеров: \(n)" }
    var historyColDate: String { "Дата" }
    var historyColDiskUsed: String { "Диск занято" }
    var historyColFree: String { "Свободно" }
    var historyColCycles: String { "Циклы" }
    var historyMetricPickerDisk: String { "Диск" }
    var historyMetricPickerBattery: String { "Батарея" }
    var historyMetricPickerCycles: String { "Циклы" }
    var historyMetricPickerSwap: String { "Swap" }
    var historyMetricA11y: String { "Метрика истории" }
    var historyMetricYLabelDisk: String { "Занято, ГБ" }
    var historyMetricYLabelBattery: String { "%" }
    var historyMetricYLabelCycles: String { "циклы" }
    var historyMetricYLabelSwap: String { "ГБ" }
    var historyMetricInsufficientData: String { "Недостаточно данных для графика по этому показателю" }
    var historyNotEnoughDays: String { "История появится здесь, когда приложение проверит этот Mac в два разных дня — оно сохраняет один снимок в день." }
    var historyRangeMonth: String { "Месяц" }
    var historyRangeQuarter: String { "3 мес" }
    var historyRangeYear: String { "Год" }
    var historyRangeAll: String { "Всё" }
    var historyRangeA11y: String { "Период графика истории" }
    func historyGbValue(_ n: Int) -> String { "\(n) ГБ" }
    var historyRestartTitle: String { "История началась заново" }
    func historyRestartDetail(_ file: String) -> String { "Прежний файл истории не удалось прочитать, поэтому история ведётся заново. Старый файл не удалён: он сохранён в той же папке под именем «\(file)»." }
    var historyRestartReveal: String { "Показать в Finder" }
    var historyRestartRevealA11y: String { "Показать прежний файл истории в Finder" }
    var historyRestartHide: String { "Скрыть" }
    var historyRestartHideA11y: String { "Скрыть сообщение о том, что история началась заново" }
    var historyInfoDate: String { "Дата — один снимок в день (хранятся все дни)" }
    var historyInfoDiskFree: String { "Диск занято / Свободно — данные и свободное место на системном томе" }
    var historyInfoBattery: String { "Батарея — максимальная ёмкость в % от новой (здоровье батареи), не текущий заряд" }
    var historyInfoCycles: String { "Циклы — счётчик циклов перезарядки" }
    var historyInfoSwap: String { "Swap — использование файла подкачки на момент снимка" }
    var historyInfoMacos: String { "macOS — версия системы на момент снимка" }
    var historyInfoSource: String { "Источник: mac_check_state.json (Application Support)" }
    var historyInfoHideLabel: String { "Скрыть пояснения к столбцам" }
    var historyInfoShowLabel: String { "Показать пояснения к столбцам" }

    // MARK: Energy card
    var energyParamDisplaySleep: String { "Гашение экрана, мин" }
    var energyParamSleep: String { "Сон системы, мин" }
    var energyParamDiskSleep: String { "Сон дисков, мин" }
    var energyParamLowPowerMode: String { "Энергосбережение" }
    var energyParamHibernateMode: String { "Режим гибернации" }
    var energyParamWoMP: String { "Пробуждение по сети" }
    var energyInfoDisplaySleep: String { "Через сколько минут бездействия гаснет экран. 0 — никогда. По умолчанию у ноутбуков: 2 мин от батареи, 10 мин от сети." }
    var energyInfoSleep: String { "Через сколько минут бездействия засыпает вся система (экран к этому моменту уже погашен). 0 — никогда. Обычно от сети ставят 0, чтобы Mac не засыпал." }
    var energyInfoDiskSleep: String { "Через сколько минут простоя останавливаются жёсткие диски. Для встроенного SSD не играет роли, влияет на внешние HDD. 0 — никогда." }
    var energyInfoPowerNap: String { "Power Nap: во сне Mac периодически просыпается для почты, iCloud и Time Machine. По умолчанию включён от сети и выключен от батареи." }
    var energyInfoLowPowerMode: String { "Энергосбережение: снижает частоту процессора и яркость ради времени работы. По умолчанию выключено; от батареи включать разумно." }
    var energyInfoStandby: String { "Standby: после ~3 часов обычного сна содержимое памяти сбрасывается на SSD и питание RAM отключается (глубокий сон). По умолчанию включён." }
    var energyInfoHibernateMode: String { "Формат сна: 0 — только RAM (настольные Mac), 3 — RAM + копия на SSD (ноутбуки, по умолчанию), 25 — только копия на SSD (медленное пробуждение, максимальная экономия). Меняется только вручную — параметр рискованный." }
    var energyInfoWoMP: String { "Пробуждение по сети (Wake on LAN): Mac можно разбудить сетевым пакетом. Работает от сети питания; по умолчанию включено от сети." }
    var energyValueOn: String { "вкл" }
    var energyValueOff: String { "выкл" }
    var energyValueNever: String { "никогда" }
    var energyCardTitle: String { "Настройки энергии (pmset)" }
    func energyApply(_ n: Int) -> String { "Применить (\(n))" }
    func energyApplyConfirmTitle(_ n: Int) -> String {
        "Применить \(n) \(ruPlural(n, "изменение", "изменения", "изменений"))?"
    }
    var energyApplyConfirmButton: String { "Применить" }
    var energyApplyConfirmAdmin: String { "Понадобится Touch ID или пароль администратора." }
    var energyCancel: String { "Отменить" }
    var energyResetToDefaults: String { "Сбросить к стандартным" }
    var energyResetHelp: String { "Вернуть редактируемые параметры к значениям macOS по умолчанию" }
    var energyApplyCancelled: String { "Отменено" }
    func energyApplyFailed(_ msg: String) -> String { "Не удалось применить: \(msg)" }
    var energyColParam: String { "Параметр" }
    var energyColBattery: String { "От батареи" }
    var energyColAC: String { "От сети" }

    // MARK: Battery page (REDESIGN-BATTERY; strings.json › Battery + 06-battery.md)
    var batteryLoadingText: String { "Читаем данные батареи…" }
    func batteryMinutes(_ m: Int) -> String { "\(m) мин" }
    func batteryHoursMinutes(_ h: Int, _ m: Int) -> String { "\(h) ч \(m) мин" }
    var batteryStatusOnBattery: String { "От батареи" }
    func batteryStatusRemaining(_ time: String) -> String { " · осталось \(time)" }
    var batteryStatusCharging: String { "Заряжается" }
    func batteryStatusUntilFull(_ time: String) -> String { " · до полного \(time)" }
    var batteryStatusACFull: String { "От сети · заряжена" }
    var batteryStatusACNotCharging: String { "От сети · не заряжается" }
    var batterySectionNow: String { "Сейчас" }
    var batteryLabelPower: String { "Мощность" }
    func batteryWatts(_ v: String) -> String { "\(v) Вт" }
    var batteryLabelCurrent: String { "Ток" }
    var batteryLabelVoltage: String { "Напряжение" }
    func batteryVolts(_ v: String) -> String { "\(v) В" }
    var batteryLabelTemperature: String { "Температура" }
    func batteryCelsius(_ v: String) -> String { "\(v) °C" }
    func batteryCellsLine(_ joined: String) -> String { "Ячейки: \(joined) В" }
    var batterySectionCapacity: String { "Ёмкость и здоровье" }
    var batteryCapMax: String { "Максимальная" }
    func batteryMAh(_ n: Int) -> String { "\(n) мАч" }
    var batteryCapDesign: String { "Проектная" }
    var batteryCapHealth: String { "Здоровье" }
    var batteryCapCycles: String { "Циклы" }
    func batteryCyclesOf(_ cycles: String, _ design: String) -> String { "\(cycles) из \(design)" }
    var batteryCapCurrentCharge: String { "Текущий заряд" }
    var batteryCapCondition: String { "Состояние" }
    var batterySectionCharging: String { "Зарядка" }
    var batteryChargeAdapter: String { "Адаптер" }
    var batteryChargeProtocol: String { "Протокол" }
    var batteryChargeProfiles: String { "Профили" }
    var batteryChargeCurrentLabel: String { "Ток зарядки" }
    var batteryChargeStatus: String { "Статус" }
    func batteryAdapterUsbC(_ watts: Int) -> String { "USB-C · \(watts) Вт" }
    func batteryAdapterWattsSuffix(_ watts: Int) -> String { " (\(watts) Вт)" }
    var batteryAdapterWireless: String { ", беспроводной" }
    func batteryUsbPdLine(_ v: String, _ a: String) -> String { "USB PD · \(v) В × \(a) А" }
    var batteryStatusFullyCharged: String { "Заряжена" }
    var batteryStatusNotCharging: String { "Не заряжается" }
    func batteryNotChargingCode(_ n: Int) -> String { " (код \(n))" }
    var batterySectionLifetime: String { "За всё время" }
    var batteryLifetimeTempLabel: String { "Температура мин/сред/макс" }
    func batteryLifetimeTempValue(_ min: Int, _ avg: String, _ max: Int) -> String { "\(min) / \(avg) / \(max) °C" }
    var batteryLifetimeMaxCharge: String { "Макс. ток заряда" }
    var batteryLifetimeMaxDischarge: String { "Макс. ток разряда" }
    var batteryLifetimeVoltage: String { "Напряжение пакета" }
    func batteryLifetimeVoltageRange(_ min: String, _ max: String) -> String { "\(min)–\(max) В" }
    var batteryLifetimeOperatingTime: String { "Наработка" }
    var batteryDetailLowPower: String { "Энергосбережение" }
    var batteryDetailPassportSection: String { "Паспорт" }
    var batteryDetailManufacturer: String { "Производитель" }
    var batteryDetailSerial: String { "Серийный номер" }
    var batteryDetailMfgDate: String { "Дата изготовления" }
    func batSub(_ cycles: Int?) -> String { cycles.map { "встроенная · \(fmtGrouped($0)) " + ruPlural($0, "цикл", "цикла", "циклов") } ?? "встроенная" }
    func batTagCapacity(_ pct: String) -> String { "ёмкость \(pct)" }
    var batTagReadFailed: String { "Ошибка чтения" }
    var batTagUnknown: String { "здоровье неизвестно" }
    func batNowCaption(_ time: String) -> String { "обновлено \(time) · каждые 3 с" }
    var batFailTimedOut: String { "Не удалось прочитать данные батареи: ioreg не ответил за 5 с." }
    var batFailNoReading: String { "Не удалось прочитать данные батареи: ioreg не нашёл батарею." }
    var batFailShowingSaved: String { "Показаны последние сохранённые значения." }
    var batTryAgainA11y: String { "Повторить чтение данных батареи" }
    var batHealthNote: String { "максимальная от проектной" }
    var batWornNote: String { "Ёмкость ниже 80 %: батарея приближается к сервисному порогу. Замена — в сервисе Apple." }
    func batServiceNote(_ parts: [String]) -> String { "macOS рекомендует обслуживание" + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", ")) + ". Mac может работать от батареи меньше или внезапно выключаться. Замена — в сервисе Apple." }
    func batServiceCapacity(_ pct: String) -> String { "ёмкость \(pct)" }
    var batServiceCycles: String { "циклов больше расчётных" }
    var batBatterySettings: String { "Настройки батареи" }
    var batBatterySettingsA11y: String { "Открыть системные настройки батареи" }
    var batChargingCaption: String { "адаптер подключён" }
    var batLifetimeCaption: String { "по данным контроллера батареи" }
    func batHours(_ s: String) -> String { "\(s) ч" }
    var batEstimate: String { "оценка" }
    func batCode(_ code: String) -> String { "код \(code)" }
    var batHistoryTitle: String { "История ёмкости" }
    func batHistoryDelta(_ signedPct: String, months: Int) -> String { "\(signedPct) за \(months) " + ruPlural(months, "месяц", "месяца", "месяцев") }
    var batHistoryNotEnough: String { "данных для тренда пока мало" }
    var batHistoryFoot: String { "полный график — в разделе «История»" }
    var batHistoryFootA11y: String { "Открыть «Историю» с графиком батареи" }
    var privilegedTimedOut: String { "Touch ID не ответил за 30 с" }
    var secGatekeeperError: String { "Не удалось включить Gatekeeper" }
    var secRestartRequired: String { "нужна перезагрузка" }
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
    // MARK: Backups page (REDESIGN-BACKUPS)
    var bkSub: String { "Time Machine и бэкап Claude" }
    var bkTagTMNotSet: String { "Time Machine не настроена" }
    var bkTagOverdue: String { "Копия просрочена" }
    var bkTagBacking: String { "Идёт копирование…" }
    var bkTagClaudeStale: String { "Бэкап Claude устарел" }
    var bkTagClaudeMissing: String { "Лог Claude не найден" }
    var bkTagClaudeUnreadable: String { "Лог Claude не читается" }
    var bkCaptionAutoHourly: String { "автоматически · каждый час" }
    var bkCaptionAutoDaily: String { "автоматически · каждый день" }
    var bkCaptionAutoWeekly: String { "автоматически · каждую неделю" }
    func bkCaptionAutoEveryHours(_ n: Int) -> String { "автоматически · каждые \(n) ч" }
    var bkCaptionManual: String { "вручную" }
    var bkCaptionDiskNotConnected: String { "диск не подключён" }
    var bkCaptionBacking: String { "идёт резервное копирование" }
    var bkNoteNotSet: String { "Time Machine не настроена — копий этого Mac нет." }
    func bkNoteOverdueDisconnected(_ days: Int, _ disk: String) -> String { "Последняя копия была \(days) \(ruDays(days)) назад. Подключите \(disk), чтобы продолжить." }
    func bkNoteOverdueDisconnectedHot(_ days: Int, _ disk: String) -> String { "Последняя копия была \(days) \(ruDays(days)) назад — больше месяца. Подключите \(disk) и создайте копию." }
    func bkNoteOverdueConnected(_ days: Int) -> String { "Последняя копия была \(days) \(ruDays(days)) назад. Создайте копию сейчас." }
    func bkNoteOverdueConnectedHot(_ days: Int) -> String { "Последняя копия была \(days) \(ruDays(days)) назад — больше месяца. Создайте копию сейчас." }
    var bkTheBackupDisk: String { "диск для копий" }
    func bkDaysAgo(_ n: Int) -> String { "\(n) \(ruDays(n)) назад" }
    func bkToday(_ t: String) -> String { "сегодня, \(t)" }
    func bkYesterday(_ t: String) -> String { "вчера, \(t)" }
    var bkLastBackup: String { "Последняя копия" }
    var bkNextBackup: String { "Следующая копия" }
    func bkNextIn(_ d: String) -> String { "через \(d)" }
    var bkNextSoon: String { "скоро" }
    var bkNextWhenConnected: String { "при подключении" }
    var bkNextAfterThis: String { "после текущей" }
    var bkNextAutoOff: String { "автоматические копии выключены" }
    func bkFree(_ s: String) -> String { "свободно \(s)" }
    var bkNotConnected: String { "не подключён" }
    var bkPurgeable: String { "Очищаемое место" }
    var bkPurgeableNote: String { "снимки и кэши" }
    func bkLatestSnapshotToday(_ t: String) -> String { "последний сегодня в \(t)" }
    func bkLatestSnapshot(_ d: String) -> String { "последний \(d)" }
    var bkBackUpNow: String { "Создать копию" }
    var bkBackUpNowA11y: String { "Начать резервное копирование Time Machine сейчас" }
    func bkConnectFirst(_ disk: String) -> String { "Сначала подключите \(disk)" }
    var bkStop: String { "Остановить" }
    var bkStopA11y: String { "Остановить текущее копирование Time Machine" }
    var bkSetUpA11y: String { "Открыть настройки Time Machine" }
    func bkBackingTo(_ disk: String) -> String { "Копирование на \(disk)" }
    func bkProgressBytes(_ done: String, _ total: String) -> String { "\(done) из \(total)" }
    func bkTimeLeft(_ d: String) -> String { "осталось около \(d)" }
    var bkPreparing: String { "подготовка…" }
    func bkFindingChanges(_ count: String) -> String { "Поиск изменений · найдено \(count)" }
    var bkFindingChangesNoCount: String { "Поиск изменений…" }
    var bkStopping: String { "остановка…" }
    func bkStartFailed(_ why: String) -> String { "Не удалось начать копирование: \(why)" }
    var bkStartDidNotBegin: String { "Копирование не началось. Проверьте Time Machine в Системных настройках." }
    func bkStopFailed(_ why: String) -> String { "Не удалось остановить копирование: \(why)" }
    var bkFailedNoReason: String { "tmutil не сообщил причину" }
    func bkClaudeCaption(_ path: String) -> String { "из \(path)" }
    var bkAgeOK: String { "в норме" }
    var bkOverLimit: String { "старше порога" }
    var bkChangeInSettings: String { "меняется в Настройках" }
    func bkNoteClaudeStale(_ limit: String) -> String { "Последний бэкап Claude старше \(limit). Проверьте, что задача резервного копирования запускается." }
    var bkNoteClaudeNone: String { "В журнале нет успешных бэкапов Claude. Проверьте, что задача резервного копирования запускается." }
    func bkNoteClaudeMissing(_ path: String) -> String { "Лог не найден: \(path)" }
    var bkOpenSettingsBackups: String { "Настройки › Расположение бэкапа" }
    var bkOpenSettingsBackupsA11y: String { "Открыть настройки MacDashboard, раздел «Бэкап»" }
    func bkNoteClaudeUnreadable(_ path: String) -> String { "Не удалось прочитать \(path). Возможно, нужен полный доступ к диску." }
    var bkOpenPrivacy: String { "Открыть «Конфиденциальность»…" }
    var bkOpenPrivacyA11y: String { "Открыть Системные настройки › Конфиденциальность › Полный доступ к диску" }
    private func ruDays(_ n: Int) -> String {
        let r = n % 100, d = n % 10
        if r >= 11 && r <= 14 { return "дней" }
        if d == 1 { return "день" }
        if (2...4).contains(d) { return "дня" }
        return "дней"
    }
    func batMAh(_ s: String) -> String { "\(s) мАч" }
    func batMA(_ s: String) -> String { "\(s) мА" }
    var batConditionNormal: String { "В норме" }
    var batConditionService: String { "Рекомендуется сервис" }
    var batConditionReplaceSoon: String { "Скоро заменить" }
    var batConditionReplaceNow: String { "Заменить" }
    var batConditionCheck: String { "Проверить батарею" }

    // MARK: Assessment
    func assessDiskFull(_ pct: String) -> String { "Диск заполнен на \(pct)% — срочно освободите место." }
    func assessDiskFullSoon(_ pct: String) -> String { "Диск заполнен на \(pct)% — пора освобождать место." }
    func assessMemPressure(critical: Bool, apps: [String]) -> String {
        let head = critical ? "macOS сообщает, что оперативной памяти не хватает — Mac может замедляться."
                            : "macOS сообщает, что свободной оперативной памяти мало."
        let tail = " — закройте то, чем сейчас не пользуетесь."
        switch apps.count {
        case 0: return head + " Закройте приложения, которыми сейчас не пользуетесь."
        case 1: return head + " Больше всего памяти занимает \(apps[0])" + tail
        default: return head + " Больше всего памяти занимают \(apps.dropLast().joined(separator: ", ")) и \(apps[apps.count - 1])" + tail
        }
    }
    func assessWakeHolders(_ entries: [String]) -> String {
        let n = entries.count
        return "\(n) \(ruPlural(n, "программа не даёт", "программы не дают", "программ не дают")) Mac уснуть: \(entries.joined(separator: "; "))."
    }
    func assessBatteryCapacityLow(_ cap: Int) -> String { "Ёмкость батареи \(cap)% от новой — думайте о замене." }
    func assessBatteryCapacityWarn(_ cap: Int) -> String { "Ёмкость батареи \(cap)% — ресурс подходит к сервисному порогу (80%)." }
    func assessBatteryConditionBad(_ cond: String) -> String { "Состояние батареи: \(cond) — загляните в сервис." }
    var assessFileVaultOff: String { "FileVault выключен — стоит включить." }
    var assessGatekeeperOff: String { "Gatekeeper выключен — стоит включить." }
    var assessSipOff: String { "SIP выключен — стоит включить." }
    var assessFirewallOff: String { "Файрвол выключен — стоит включить." }
    func assessMacUpdatesAvailable(_ n: Int) -> String { "Доступны обновления macOS: \(n) шт." }
    func assessBrewOutdatedTip(_ n: Int) -> String { "Homebrew: устаревших пакетов — \(n) (brew upgrade)." }
    func assessOwnCrashesRecent(_ app: String, _ n: Int) -> String { "Сбои \(app) за последние 7 дней: \(n) шт. — отчёты в Console.app." }
    func assessKernelPanicsRecent(_ n: Int) -> String { "Сбой системы (паника ядра) за последние 7 дней: \(n) шт. — отчёты в Console.app." }
    var assessTimeMachineNotSetUp: String { "Time Machine не настроен — бэкапов нет." }
    func assessClaudeBackupStale(_ age: String) -> String { "Бэкапа Claude не было \(age) — проверьте, подключён ли диск и разблокирован ли он." }
    var assessClaudeBackupNone: String { "В журнале бэкапа Claude нет ни одного успешного снимка — проверьте диск." }
    func assessSmartDiskErrors(_ title: String) -> String { "Диск «\(title)»: SMART сообщает об ошибках носителя — проверьте диск и бэкапы." }
    func assessSmartDiskWearHigh(_ title: String, _ pct: Int) -> String { "Диск «\(title)»: износ \(pct)% — ресурс на исходе." }
    func assessSmartDiskUnavailableTip(_ title: String) -> String { "Диск «\(title)»: SMART недоступен — переподключите кабель или установите smartmontools (brew install smartmontools)." }
    func assessDownloadsTip(_ sizeStr: String, _ shareSuffix: String) -> String { "«Загрузки» занимают \(sizeStr)\(shareSuffix) — стоит разобрать." }
    func assessDownloadsShareSuffix(_ pct: String) -> String { " (\(pct)% всего диска)" }
    func assessTrashTip(_ sizeStr: String) -> String { "Корзина: \(sizeStr) — можно очистить." }
    func assessCachesTip(_ sizeStr: String) -> String { "Кэши ~/Library/Caches: \(sizeStr) — чистить безопасно." }
    var assessNoFDATip: String { "Часть папок не попала в отчёт: у приложения нет полного доступа к диску." }
    func assessSummaryCount(_ n: Int) -> String { "Замечаний: \(n)" }

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

    // MARK: DashboardModel errors
    func errorHistorySaveFailed(_ msg: String) -> String { "Не удалось сохранить историю: \(msg)" }
    func errorReportWriteFailed(_ msg: String) -> String { "Не удалось записать отчёт: \(msg)" }

    // MARK: Report writer
    func reportCreatedAt(_ time: String) -> String { "Отчёт создан: \(time)" }
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
    var reportDoneBanner: String { "ГОТОВО" }
    func reportSavedTo(_ path: String) -> String { "Отчёт сохранён: \(path)" }
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

    // MARK: v2 attention
    var attnLabelDiskFull: String { "Диск" }
    func attnDetailDiskFull(_ pct: String) -> String { "заполнен на \(pct) %" }
    var attnLabelDiskFullSoon: String { "Диск" }
    func attnDetailDiskFullSoon(_ pct: String) -> String { "заполнен на \(pct) %" }
    var attnLabelSwapHigh: String { "Память" }
    var attnDetailMemPressureWarn: String { "памяти мало" }
    var attnDetailMemPressureCritical: String { "памяти не хватает" }
    var attnLabelBatteryCapacity: String { "Батарея" }
    func attnDetailBatteryCapacity(_ cap: Int) -> String { "ёмкость \(cap) %" }
    var attnLabelBatteryCondition: String { "Батарея" }
    func attnDetailBatteryCondition(_ cond: String) -> String { "состояние: \(cond)" }
    var attnLabelFileVaultOff: String { "FileVault" }
    var attnDetailFileVaultOff: String { "выключен" }
    var attnLabelGatekeeperOff: String { "Gatekeeper" }
    var attnDetailGatekeeperOff: String { "выключен" }
    var attnLabelSipOff: String { "SIP" }
    var attnDetailSipOff: String { "выключен" }
    var attnLabelFirewallOff: String { "Брандмауэр" }
    var attnDetailFirewallOff: String { "выключен" }
    var attnLabelUpdates: String { "Обновления" }
    func attnDetailUpdates(_ n: Int) -> String { "\(n) доступно" }
    var attnLabelCrashes: String { "Сбои" }
    func attnDetailCrashes(_ n: Int) -> String { "\(n) \(ruPlural(n, "отчёт", "отчёта", "отчётов"))" }
    var attnLabelTimeMachine: String { "Time Machine" }
    var attnDetailTimeMachine: String { "не настроена" }
    var attnLabelClaudeBackup: String { "Бэкап Claude" }
    var attnDetailClaudeBackupNone: String { "нет успешных" }
    var attnLabelWakeHolders: String { "Сон" }
    func attnDetailWakeHolders(_ first: String, more: Int) -> String { more > 0 ? "\(first), ещё \(more)" : first }
    func wakeHolderOnBehalf(_ owner: String, _ requester: String) -> String { "\(owner) (от \(requester))" }
    func wakeHolderEntry(_ holder: String, _ age: String) -> String { "\(holder) — \(age)" }
    func attnWakeIgnore(_ holder: String) -> String { "Не предупреждать про \(holder)" }
    var attnWakeIgnoreHint: String { "Правый щелчок — не предупреждать про приложение." }
    func attnLabelSmartErrors(_ title: String) -> String { title }
    var attnDetailSmartErrors: String { "ошибки SMART" }
    func attnLabelSmartWear(_ title: String) -> String { title }
    func attnDetailSmartWear(_ pu: Int) -> String { "износ \(pu) %" }

    var attnVerbSettings: String { "Настройки" }
    var attnVerbActivityMonitor: String { "Мониторинг системы" }
    var attnVerbDiskUtility: String { "Дисковая утилита" }
    var attnVerbShow: String { "Показать" }
    var attnVerbEmpty: String { "Очистить" }
    var attnVerbEnable: String { "Включить" }
    var attnVerbUpgrade: String { "Обновить" }
    var attnVerbOpen: String { "Открыть" }

    var attnCapBattery: String { "Батарея" }
    func attnCapBatteryValue(_ p: Int) -> String { "\(p) %" }
    var attnCapBrew: String { "Homebrew" }
    func attnCapBrewValue(_ n: Int) -> String { "\(n) \(ruPlural(n, "пакет", "пакета", "пакетов"))" }
    var attnCapSmartNoData: String { "нет данных SMART" }
    var attnCapDownloads: String { "Загрузки" }
    var attnCapTrash: String { "Корзина" }
    var attnCapCaches: String { "Кэши" }
    var attnExplainBattery: String { "Ёмкость снижается естественным образом со временем. Откроются системные настройки батареи; ничего не изменится без вашего подтверждения." }
    var attnExplainBrew: String { "Запустит `brew upgrade` в фоне — прогресс виден в карточке Homebrew. Установленные пакеты заменяются на свежие версии." }
    var attnExplainSmart: String { "Откроет «Дисковую утилиту». У внешних дисков SMART-атрибуты часто недоступны через USB — это не признак поломки." }
    var attnExplainDownloads: String { "Откроет папку в Finder. Ничего не удаляется — вы сами решаете, что убрать." }
    var attnExplainTrash: String { "Спросит подтверждение, затем очистит Корзину через Finder. Восстановить файлы после этого нельзя." }
    var attnExplainCaches: String { "Откроет ~/Library/Caches в Finder. Приложения пересоздадут кэш при следующем запуске." }
    var attnCapFolders: String { "Папки" }
    var attnCapFoldersNoAccess: String { "видны не все" }
    var attnExplainNoFDA: String { "Откроет «Системные настройки» → «Конфиденциальность и безопасность» → «Полный доступ к диску». Без него приложение не видит Корзину и часть служебных папок, поэтому их размер не попадает в отчёт." }

    func attnMore(_ n: Int) -> String { "Ещё \(n)" }
    var attnCollapse: String { "Свернуть" }

    var quietUpdatesTitle: String { "Обновления и краши" }
    var quietNeedsAttention: String { "требует внимания" }
    var quietStatusAllEnabled: String { "всё включено" }
    var quietStatusAllClear: String { "всё в норме" }
    var quietMarkOff: String { "выключен" }
    var quietMarkUnknown: String { "неизвестно" }
    func quietCountItems(_ n: Int) -> String { "\(n) шт." }

    // MARK: iPhone module
    var mainModeMac: String { "Этот Mac" }
    var mainModeIPhone: String { "iPhone" }
    var iphoneKickerDevices: String { "Устройства" }
    var iphoneStatusConnected: String { "Подключён по кабелю" }
    var iphoneStatusNeedsTrust: String { "Нужно доверие: разблокируйте iPhone и нажмите «Доверять»" }
    var iphoneStatusReading: String { "Чтение…" }
    var iphoneStatusFailed: String { "Не удалось прочитать iPhone" }
    var iphoneUnknownDevice: String { "iPhone" }
    var iphoneRetry: String { "Повторить" }
    var iphoneSearchAgain: String { "Искать снова" }
    var iphoneRestartService: String { "Перезапустить службу подключения…" }
    var iphoneRestartConfirmTitle: String { "Перезапустить службу подключения?" }
    var iphoneRestartConfirmBody: String { "Служба на мгновение прервёт связь со всеми iPhone и iPad, подключёнными к этому Mac, включая синхронизацию в Finder. Понадобится пароль администратора или Touch ID." }
    var iphoneRestartConfirm: String { "Перезапустить" }
    var iphoneRestartCancel: String { "Отмена" }
    var iphoneRestartBusy: String { "Перезапуск службы подключения" }
    func iphoneRestartFailed(_ detail: String) -> String { "Не удалось перезапустить службу подключения: \(detail)" }
    var iphoneBack: String { "Назад" }
    var iphoneRefresh: String { "Обновить" }
    var iphoneUnavailable: String { "Подключение к iPhone недоступно на этой версии macOS." }
    func iphoneStatusRemembered(_ date: String) -> String { "Не подключён · был \(date)" }
    func iphoneOpenDeviceA11y(_ name: String) -> String { "Открыть \(name)" }
    var iphoneBatteryTitle: String { "Батарея" }
    var iphoneHistoryTitle: String { "История батареи" }
    var iphoneBatHealth: String { "Здоровье" }
    var iphoneBatCycles: String { "Циклы" }
    var iphoneBatCharge: String { "Заряд" }
    var iphoneBatState: String { "Состояние" }
    var iphoneBatTemperature: String { "Температура" }
    var iphoneBatVoltage: String { "Напряжение" }
    var iphoneBatCapacity: String { "Ёмкость" }
    var iphoneChargeCharging: String { "Заряжается" }
    var iphoneChargeExternal: String { "Подключён к питанию" }
    var iphoneChargeBattery: String { "От батареи" }
    var iphoneUnitMAh: String { "мА·ч" }
    var iphoneUnitWh: String { "Вт·ч" }
    var iphoneCapacityUnitA11y: String { "Единицы ёмкости" }
    var iphoneWhSourceHelp: String { "Примерно: ёмкость × 3,88 В — типовое напряжение батарей iPhone (Википедия, статьи iPhone 16 Pro / 17 Pro, по данным регуляторов)" }
    var iphoneBatteryConnectToRead: String { "Подключите iPhone кабелем, чтобы прочитать батарею." }
    var iphoneBatteryNoData: String { "нет данных" }
    var iphoneHistoryEmpty: String { "История пока пуста: точки появятся в дни, когда iPhone подключён." }
    var iphoneHistorySourceLive: String { "Измерено" }
    var iphoneHistorySourceImport: String { "Из sysdiagnose" }
    var iphoneHistoryColDate: String { "Дата" }
    var iphoneHistoryColHealth: String { "Здоровье" }
    var iphoneHistoryColCycles: String { "Циклы" }
    var iphoneHistoryColSource: String { "Источник" }
    func iphoneBatteryFromHistory(_ date: String) -> String { "Из истории · \(date)" }
    func iphoneHistoryCaption(_ n: Int) -> String { "\(n) \(ruPlural(n, "день", "дня", "дней"))" }
    var iphoneHistoryChart: String { "График" }
    var iphoneHistoryTable: String { "Таблица" }
    var iphoneHistoryViewA11y: String { "Вид истории батареи" }
    func iphoneChartCycles(_ n: Int) -> String { "\(n) \(ruPlural(n, "цикл", "цикла", "циклов"))" }
    var iphoneChartSourceImport: String { "sysdiagnose" }
    func iphoneChartMonth(_ m: Int) -> String {
        let names = ["янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
        return names[min(max(m, 1), 12) - 1]
    }
    func iphoneChartWeekLabel(day: Int, month: Int) -> String { "\(day) \(iphoneChartMonth(month))" }

    var iphoneLogsTitle: String { "Журналы сбоев" }
    var iphoneLogsConnectToRead: String { "Подключите iPhone кабелем, чтобы прочитать журналы." }
    var iphoneLogsEmpty: String { "Файлов журналов не найдено." }
    var iphoneLogsRefreshA11y: String { "Обновить список журналов сбоев" }
    func iphoneLogsCaption(_ n: Int) -> String { "\(n) \(ruPlural(n, "файл", "файла", "файлов"))" }
    func iphoneLogsCategory(_ c: LogCategory) -> String {
        switch c {
        case .appCrash: return "Сбои приложений"
        case .exceptionFault: return "Исключения"
        case .jetsam: return "Нехватка памяти (Jetsam)"
        case .diskWrites: return "Запись на диск"
        case .cpuResource: return "Нагрузка CPU"
        case .stackshot: return "Стекшоты"
        case .otherReport: return "Другие отчёты"
        case .analytics: return "Аналитика"
        case .other: return "Прочие файлы"
        }
    }
    var iphoneSectionReadFailed: String { "Не удалось прочитать данные с iPhone. Нажмите «Обновить», чтобы попробовать снова." }

    var iphoneImportTitle: String { "Импорт sysdiagnose" }
    var iphoneImportButton: String { "Импортировать" }
    func iphoneImportArchiveA11y(_ name: String) -> String { "Импортировать архив \(name)" }
    var iphoneImportPickFile: String { "Выбрать файл на Mac…" }
    var iphoneImportPickA11y: String { "Выбрать архив sysdiagnose на Mac" }
    var iphoneImportPickPrompt: String { "Выбрать" }
    func iphoneImportConfirmTitle(_ name: String, into phone: String) -> String { "Импорт «\(name)» в \(phone)" }
    var iphoneImportParseOnly: String { "Только разобрать" }
    var iphoneImportParseKeep: String { "Разобрать и сохранить" }
    var iphoneImportCancel: String { "Отмена" }
    var iphoneImportParseOnlyA11y: String { "Только разобрать архив, не сохраняя его" }
    var iphoneImportParseKeepA11y: String { "Разобрать архив и сохранить его на Mac" }
    var iphoneImportCancelA11y: String { "Отменить импорт" }
    func iphoneImportMismatchTitle(_ target: String) -> String { "Загрузить данные другого телефона в \(target)?" }
    func iphoneImportMismatchMessage(file: String, owner: String?, archiveMAh: [Int], deviceMAh: Int, target: String) -> String {
        "Похоже, файл «\(file)» снят с \(owner ?? "другого iPhone"): проектная ёмкость его аккумулятора — "
            + "\(archiveMAh.map { batteryMAh($0) }.joined(separator: ", ")), у \(target) — \(batteryMAh(deviceMAh)). "
            + "Если загрузить, история аккумулятора из файла заменит историю \(target) за те же дни."
    }
    var iphoneImportMismatchProceed: String { "Всё равно загрузить" }
    var iphoneImportMismatchProceedA11y: String { "Загрузить историю аккумулятора другого телефона в этот" }
    var iphoneImportHint: String { "Архивы с телефона видны после чтения журналов; можно выбрать и файл .tar.gz на Mac." }
    func iphoneImportProgress(_ p: ImportProgress) -> String {
        switch p {
        case .copying(let done, let total):
            return "Копирование с телефона: \(fmtBytes(done)) из \(fmtBytes(total))"
        case .extracting: return "Распаковка нужных файлов…"
        case .parsing: return "Разбор…"
        }
    }
    func iphoneImportSummary(_ s: ImportSummary) -> String {
        var t = "Точек батареи: \(s.batteryPoints), файлов журналов: \(s.logFiles)"
        if s.skippedRows > 0 { t += ", пропущено строк: \(s.skippedRows)" }
        return t + (s.keptPath != nil ? ". Архив сохранён." : ".")
    }
    func iphoneImportError(_ e: ImportError) -> String {
        switch e {
        case .copyFailed: return "Не удалось скопировать архив с телефона."
        case .sizeMismatch: return "Размер скопированного архива не совпал с размером на телефоне."
        case .tarFailed: return "Не удалось распаковать архив."
        case .keepFailed: return "Не удалось сохранить архив."
        case .cancelled: return "Импорт отменён."
        }
    }
    func iphoneImportErrorDetail(_ e: ImportError) -> String? {
        guard case .tarFailed(let f) = e else { return nil }
        switch f {
        case .message(let line): return line
        case .exitCode(let n): return "tar завершился с кодом \(n)."
        case .signal(let s): return "tar остановлен сигналом \(s)."
        case .launchFailed(let code): return "Не удалось запустить tar (ошибка \(code))."
        case .timedOut: return "tar не завершился вовремя."
        case .listingTooLong: return "В архиве слишком много файлов."
        case .workFiles: return "Не удалось создать временные файлы для распаковки."
        }
    }
    var iphoneImportKeptTitle: String { "Сохранённые архивы" }
    func iphoneImportRevealA11y(_ name: String) -> String { "Показать архив \(name) в Finder" }
    func iphoneLogsFromArchive(_ name: String) -> String { "Из архива \(name)" }
    var iphoneIdentityTitle: String { "Устройство и детали" }
    var iphoneIdentityConnectToRead: String { "Подключите iPhone кабелем, чтобы прочитать данные устройства." }
    var iphoneIdentityRefreshA11y: String { "Обновить данные устройства" }
    var iphoneIdentityShow: String { "Показать полностью" }
    var iphoneIdentityHide: String { "Скрыть" }
    var iphoneIdentityCopy: String { "Копировать" }
    var iphoneIdentityCopied: String { "Скопировано" }
    func iphoneRevealA11y(_ label: String) -> String { "Показать полностью: \(label)" }
    func iphoneHideA11y(_ label: String) -> String { "Скрыть значение: \(label)" }
    func iphoneCopyA11y(_ label: String) -> String { "Копировать значение: \(label)" }
    func iphoneIdentityLabel(_ l: IdentityLabel) -> String {
        switch l {
        case .marketingName: return "Модель"
        case .modelNumber: return "Номер модели"
        case .regulatoryModel: return "Регуляторная модель"
        case .hardwareModel: return "Аппаратная модель"
        case .ios: return "Версия iOS"
        case .storage: return "Память"
        case .colorCode: return "Код цвета"
        case .serial: return "Серийный номер"
        case .logicBoard: return "Логическая плата"
        case .imei: return "IMEI"
        case .imei2: return "IMEI 2"
        case .battery: return "Батарея"
        case .displayPanel: return "Дисплей (панель)"
        case .displayRawPanel: return "Дисплей (заводской номер)"
        case .coverGlass: return "Защитное стекло"
        case .backGlass: return "Задняя панель"
        case .nova: return "Модуль Nova"
        case .ambientLight: return "Датчик освещённости"
        case .backCamera: return "Основная камера"
        case .backSuperWide: return "Сверхширокоугольная"
        case .backTele: return "Телефото"
        case .frontCamera: return "Фронтальная камера"
        case .frontIR: return "ИК-камера Face ID"
        case .faceIDProjector: return "Проектор Face ID"
        }
    }

    var iphoneTagNotConnected: String { "Не подключён" }
    var iphoneTagTrustNeeded: String { "Нужно доверие" }
    var iphoneTagReadFailed: String { "Не удалось прочитать" }
    var iphoneSubTrust: String { "разблокируйте и нажмите «Доверять»" }
    var iphoneSubReconnect: String { "переподключите кабель" }
    func iphoneSubLastSeen(_ date: String) -> String { "был \(date)" }
    func iphoneSubCharge(_ percent: Int, _ state: String) -> String { "\(percent) % · \(state)" }
    var iphoneStateChargingLower: String { "заряжается" }
    var iphoneStateExternalLower: String { "от сети" }
    var iphoneStateBatteryLower: String { "от батареи" }
    var iphoneTileHealth: String { "Здоровье батареи" }
    var iphoneNotIdentified: String { "Ещё не опознан" }
    var iphonePendingTrustText: String { "Разблокируйте iPhone, нажмите «Доверять» на его экране и повторите." }
    var iphonePendingFailedText: String { "Не удалось прочитать iPhone. Переподключите кабель и повторите." }
    func iphoneSummary(connected: Int, notConnected: Int, waiting: Int) -> String {
        var parts: [String] = []
        if connected > 0 { parts.append("подключено: \(connected)") }
        if notConnected > 0 { parts.append("не подключено: \(notConnected)") }
        if waiting > 0 { parts.append("ждёт доверия: \(waiting)") }
        return parts.joined(separator: " · ")
    }
    var iphoneSummaryNone: String { "iPhone пока не найден" }
    var iphoneSummaryUnavailable: String { "Недоступно на этом Mac" }
    var iphoneNoticeEmptyTitle: String { "iPhone не найден" }
    var iphoneNoticeEmptyBody: String { "Подключите iPhone кабелем, разблокируйте его и нажмите «Доверять»." }
    var iphoneNoticeUnavailableTitle: String { "Подключение к iPhone недоступно" }
    var iphoneRestartingShort: String { "Перезапуск…" }
    var iphoneRestartingBanner: String { "Служба подключения перезапускается. Устройства переподключатся через несколько секунд." }

    var iphoneBatteryMeasuredNow: String { "Измерено сейчас" }
    var iphoneHealthNote: String { "Текущая ёмкость к проектной" }
    func iphoneHealthHistoryNote(cycles: Int?) -> String {
        guard let n = cycles else { return "последнее значение из истории" }
        return "\(n) \(ruPlural(n, "цикл", "цикла", "циклов")) · последнее значение из истории"
    }
    var iphoneLiveReadings: String { "Текущие показания" }
    var iphoneLiveReadingsConnect: String { "Подключите iPhone кабелем, чтобы увидеть заряд, состояние, температуру, напряжение и ёмкость." }
    var iphoneRefreshOfflineHelp: String { "Подключите iPhone кабелем, чтобы обновить" }
    var iphoneLogsSourceLive: String { "На iPhone" }
    var iphoneLogsSourceArchive: String { "Из архива" }
    var iphoneLogsSourceA11y: String { "Источник журналов сбоев" }
    var iphoneLogsColSize: String { "Размер" }
    var iphoneImportOnPhone: String { "На iPhone" }
    var iphoneImportChoiceBody: String { "Разбор читает из архива историю батареи и журналы. «Сохранить» также оставляет копию архива на этом Mac." }
    var iphoneImportInArchive: String { "В архиве" }
    var iphoneIdentitySerials: String { "Серийные номера" }
    // MARK: Common (strings.json › Shared + 00 §4.16/§7; REDESIGN-FOUNDATION)
    var commonShowInFinder: String { "Показать в Finder" }
    var commonFirewall: String { "Брандмауэр" }
    var commonEnable: String { "Включить…" }
    var commonDisk: String { "Диск" }
    var commonSetUp: String { "Настроить…" }
    var commonShow: String { "Показать" }
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
    var commonCancel: String { "Отмена" }
    var commonOpenPrivacySettings: String { "Открыть «Конфиденциальность»…" }
    func commonUpdated(_ time: String) -> String { "обновлено \(time)" }
    var commonChecking: String { "Проверка…" }
    var commonCritical: String { "Критично" }
    func commonLastData(_ time: String) -> String { "последние данные — \(time)" }
    // MARK: IPSW (IPHONE-IPSW)
    var ipswSigned: String { "Подписывается (по данным ipsw.me)" }
    var ipswNotSigned: String { "Не подписывается (по данным ipsw.me)" }
    var ipswNotListed: String { "Нет в списке ipsw.me" }
    var ipswIsAppleTarget: String { "Текущая сборка Apple для восстановления" }
    var ipswNotAppleTarget: String { "Не текущая сборка Apple для восстановления" }
    func ipswAskSends(_ identifier: String) -> String { "Отправит в ipsw.me идентификатор модели \(identifier)" }
    func ipswVerified(_ list: String) -> String { "Проверено: \(list)" }
    var ipswVerifiedSizeOnly: String { "и размер" }
    var ipswUnknown: String { "Неизвестно" }
    var ipswChecking: String { "Проверяем…" }
    func ipswCheckedAgo(_ rel: String) -> String { "Проверено \(rel)" }
    var ipswErrNoIdentifier: String { "Модель телефона неизвестна — подключите его хотя бы раз." }
    var ipswErrUnknownDevice: String { "ipsw.me не знает эту модель." }
    var ipswErrOffline: String { "Нет подключения к интернету." }
    var ipswErrTimedOut: String { "Сервер не ответил вовремя." }
    func ipswErrHTTP(_ code: Int) -> String { "Сервер ответил ошибкой \(code)." }
    var ipswErrBadResponse: String { "Сервер прислал ответ, который приложение не может прочитать." }
    func ipswSourceFailed(_ source: String, _ reason: String) -> String { "\(source) недоступен: \(reason)" }
    var ipswErrNotDownloadable: String { "Эта сборка не раздаётся с защищённых серверов Apple, её не скачиваем." }
    var ipswNoSecureAppleLink: String { "Защищённой ссылки Apple на эту сборку нет, здесь её не скачать." }
    var ipswNotFromApple: String { "MacDashboard скачивает только ту сборку, которую сейчас предлагает каталог Apple." }
    var ipswErrNoChecksum: String { "Для этой сборки нет контрольной суммы, её не скачиваем." }
    var ipswErrNoSize: String { "Размер файла неизвестен, его не скачиваем." }
    var ipswErrSourcesDisagree: String { "Apple и ipsw.me расходятся в данных об этом файле, его не скачиваем." }
    func ipswErrNotEnoughSpace(_ needed: String, _ free: String) -> String { "Не хватает места: нужно \(needed), свободно \(free)." }
    var ipswErrDownloadsDenied: String { "Нет доступа к папке «Загрузки». Разрешите его в Системных настройках › Конфиденциальность и безопасность › Файлы и папки." }
    var ipswErrSizeMismatch: String { "Скачанный файл не того размера и удалён." }
    var ipswErrChecksumMismatch: String { "Скачанный файл не прошёл проверку контрольной суммы и удалён." }
    func ipswErrTransfer(_ detail: String) -> String { "Загрузка не удалась: \(detail)" }
    func ipswErrFileSystem(_ detail: String) -> String { "Не удалось сохранить файл: \(detail)" }
    var ipswBusy: String { "Уже идёт другая загрузка." }
    var ipswCancelled: String { "Загрузка отменена." }
    var ipswPreparing: String { "Готовим загрузку…" }
    func ipswDownloading(_ done: String, _ total: String) -> String { "Загружено \(done) из \(total)" }
    var ipswVerifying: String { "Проверяем контрольные суммы…" }
    var ipswFinished: String { "Сохранено в «Загрузки»" }

    // MARK: Home (REDESIGN-HOME; strings.json › This Mac Home + 02-home.md)
    var homeMacStatus: String { "Состояние Mac" }
    func homeTaskCount(_ n: Int) -> String { "\(n) " + ruPlural(n, "задача", "задачи", "задач") }
    func homeNeedAttention(_ n: Int) -> String { ruPlural(n, "требует внимания", "требуют внимания", "требуют внимания") }
    var homeCriticalCount: String { "Серьёзные" }
    var homeWarnings: String { "Предупреждения" }
    func homeCheckedAt(_ t: String) -> String { "проверено в \(t)" }
    func homeLastCheck(_ t: String) -> String { "последняя проверка \(t)" }
    func homeTileLastCheck(_ t: String) -> String { "проверка в \(t)" }
    func homeShowAll(_ n: Int) -> String { "Показать все (\(n))" }
    var homeYouCan: String { "Можно сделать" }
    var homeFreeUpSpace: String { "Освободить место" }
    func homeBrewOutdatedShort(_ n: Int) -> String { "\(n) устар." }
    var homeNothingNeedsAttention: String { "Ничего не требует внимания" }
    var homeFirstScanTitle: String { "Первая проверка Mac…" }
    var homeFirstScanCaption: String { "обычно до 30 с" }
    func homeScanFailed(timedOut: Bool, lastGood: String?) -> String { (timedOut ? "Не удалось проверить Mac: system_profiler не ответил за 30 с." : "Не удалось проверить Mac: system_profiler не вернул данных.") + (lastGood.map { " Показаны данные проверки в \($0)." } ?? "") }
    var homeSipHelp: String { "SIP включается только из режима восстановления macOS." }
    var homeStateOff: String { "выключен" }
    var homeDiskHealth: String { "Здоровье диска" }
    var homeStateFailing: String { "сбой диска" }
    var homeStateFailingShort: String { "сбой" }
    func homeStateDiskFull(_ pct: Int) -> String { "заполнен на \(pct) %" }
    var homeStateNotSetUp: String { "не настроена" }
    var homeStateKeepsAwake: String { "не даёт уснуть" }
    func homeStateWorn(_ pct: Int) -> String { "износ \(pct) %" }
    func homeStatePackagesOutdated(_ n: Int) -> String { "\(n) " + ruPlural(n, "пакет устарел", "пакета устарели", "пакетов устарели") }
    var homeStateUpdateAvailable: String { "доступно обновление" }
    func homeStateUpdatesAvailable(_ n: Int) -> String { "доступно обновлений: \(n)" }
    var homeMemoryObject: String { "Памяти" }
    var homeStateRunningLow: String { "мало" }
    var homeStateRunningOut: String { "не хватает" }
    var homeCrashes: String { "Сбои" }
    func homeStateReports(_ n: Int) -> String { "\(n) " + ruPlural(n, "отчёт", "отчёта", "отчётов") }
    var homeDiskWear: String { "Износ диска" }
    func homePercent(_ s: String) -> String { "\(s) %" }
    func homeGB(_ s: String) -> String { "\(s) ГБ" }
    var homeVerbDetails: String { "Подробнее" }
    var homeVerbFreeUp: String { "Освободить" }
    var homeVerbUpdate: String { "Обновить" }
    var homeVerbSettings: String { "Настройки…" }
    var homeTagFirewallOff: String { "брандмауэр выключен" }
    var homeTagDriveFailing: String { "сбой диска" }
    var homeTagTMNotSetUp: String { "TM не настроена" }
    var homeTagWorn: String { "износ" }
    var homeTagBrewOutdated: String { "Homebrew устарел" }
    var homeTagUpdateAvailable: String { "есть обновление" }
    var homeTagLowMemory: String { "Мало памяти" }
    var homeTagService: String { "Сервис" }
    var homeTagFileVaultOff: String { "FileVault выключен" }
    var homeTagGatekeeperOff: String { "Gatekeeper выключен" }
    var homeTagSipOff: String { "SIP выключен" }
    var homeTagDiskWorn: String { "Износ" }
    var homeTagClaudeStale: String { "Бэкап устарел" }
    var homeTagNormal: String { "в норме" }
    var homeTagHealthy: String { "в норме" }
    var homeTagAllOn: String { "всё включено" }
    var homeTagUpToDate: String { "в норме" }
    func homeHistoryDays(_ n: Int) -> String { "\(n) " + ruPlural(n, "день", "дня", "дней") }
    var homeSections: String { "Разделы" }
    func homeSectionCount(_ n: Int) -> String { "\(n) " + ruPlural(n, "раздел", "раздела", "разделов") }
    func homeCPUSub(_ chip: String, _ cores: Int) -> String { "\(chip) · \(cores) " + ruPlural(cores, "ядро", "ядра", "ядер") }
    func homeCoresOnly(_ cores: Int) -> String { "\(cores) " + ruPlural(cores, "ядро", "ядра", "ядер") }
    var homeStorageSub: String { "диск, папки, SMART" }
    var homeBatterySub: String { "встроенная" }
    var homeSecuritySub: String { "защита, обновления, сбои" }
    var homeBackupsSub: String { "Time Machine, Claude" }
    var homeSystemSub: String { "сон, автозагрузка, Homebrew" }
    var homeHistorySub: String { "ежедневные замеры" }
    var homeKVLoad: String { "Нагрузка" }
    var homeKVProcesses: String { "Процессов" }
    var homeKVPurgeable: String { "Очищаемое" }
    var homeKVFailing: String { "сбой диска" }
    func homeKVWorn(_ pct: Int) -> String { "износ \(pct) %" }
    var homeKVCapacity: String { "Ёмкость" }
    func homeKVProtection(_ on: Int) -> String { "\(on) из 4" }
    var homeKVNone: String { "нет" }
    var homeKVSnapshots: String { "Снимки" }
    var homeKVLoginItems: String { "Автозагрузка" }
    var homeKVUpToDate: String { "актуален" }
    var homeKVDiskPerMonth: String { "Диск за месяц" }
    var homeBackA11y: String { "Назад к разделу «Этот Mac»" }
    // HOME-C: the Now card
    func homeEverySeconds(_ n: Int) -> String { "каждые \(n) с" }
    func homeLoadCores(_ load: String, _ cores: Int) -> String {
        "нагрузка \(load) · \(cores) " + ruPlural(cores, "ядро", "ядра", "ядер")
    }
    func homeOf(_ s: String) -> String { "из \(s)" }
    var homePressureLow: String { "давление низкое" }
    var homePressureMedium: String { "давление среднее" }
    var homePressureHigh: String { "давление высокое" }
    func homeLegendActive(_ v: String, short: Bool) -> String { short ? "акт. \(v)" : "активная \(v)" }
    func homeLegendWired(_ v: String) -> String { "ядро \(v)" }
    func homeLegendInactive(_ v: String, short: Bool) -> String { short ? "неакт. \(v)" : "неактивная \(v)" }
    func homeLegendCompressed(_ v: String, short: Bool) -> String { short ? "сжат. \(v)" : "сжатая \(v)" }
    func homeMemFoot(_ used: String, _ total: String, _ compressed: String) -> String { "swap \(used) из \(total) · сжатая \(compressed)" }
    func homeMemFootNoSwap(_ compressed: String) -> String { "сжатая \(compressed)" }
    var homeFreeWord: String { "свободно" }
    var homeChipHealthy: String { "в норме" }
    var homeChipLowSpace: String { "мало места" }
    func homeChipDriveFailing(short: Bool) -> String { short ? "сбой" : "сбой диска" }
    var homeChipWorn: String { "износ" }
    var homeChipService: String { "сервис" }
    func homeLegendData(_ v: String) -> String { "данные \(v)" }
    func homeLegendSystem(_ v: String, short: Bool) -> String { short ? "сист. \(v)" : "система \(v)" }
    func homeLegendOther(_ v: String, short: Bool) -> String { short ? "проч. \(v)" : "прочее \(v)" }
    func homeStorageFoot(size: String, purgeable: String?, short: Bool) -> String {
        "из \(size)" + (purgeable.map { " · очищаемое \($0)" } ?? "")
    }
    var homeCapacityWord: String { "ёмкость" }
    var homeOfNew: String { "от новой" }
    var homeWearThreshold: String { "порог износа 80 %" }
    var homeWearThresholdHelp: String { "80 % — порог износа по Apple" }
    func homeBatteryFoot(cycles: Int?, charge: Int?, state: String?, short: Bool) -> String {
        var parts: [String] = []
        if let n = cycles { parts.append("\(n) " + ruPlural(n, "цикл", "цикла", "циклов")) }
        if let c = charge { parts.append(short ? "заряд \(c) %" : "сейчас \(c) %" + (state.map { ", \($0)" } ?? "")) }
        return parts.joined(separator: " · ")
    }
}
