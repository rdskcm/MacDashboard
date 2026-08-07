// Engine/StringsRU.swift
// Russian string table: literal values extracted from the views, character-for-
// character (including «», ·, — where present). Same MARK grouping as AppStrings.
import Foundation

struct StringsRU: AppStrings {
    // MARK: App
    var appWindowTitle: String { "Диагностика Mac" }
    var decimalSeparator: String { "," }

    // MARK: Settings
    var settingsLanguageLabel: String { "Язык интерфейса" }
    var settingsIntervalLabel: String { "Интервал обновления (процессор/память)" }
    func settingsIntervalOption(_ seconds: Int) -> String { "\(seconds) с" }
    var settingsIntervalNoteFast: String { "1 с — самый отзывчивый график, заметная фоновая нагрузка." }
    var settingsIntervalNoteBalanced: String { "Рабочий диапазон: живые графики без заметной нагрузки." }
    var settingsIntervalNoteEconomy: String { "Экономный режим: значения обновляются реже, батарея живёт дольше." }
    var settingsMenuLanguageHint: String { "Язык меню и системных диалогов применится после перезапуска приложения" }
    var settingsRelaunchNow: String { "Перезапустить сейчас" }
    var settingsSectionGeneral: String { "Общие" }
    var settingsSectionMonitoring: String { "Мониторинг" }
    var settingsVersionLabel: String { "Версия" }
    var settingsWindowTitle: String { "Настройки" }

    // MARK: Main dashboard (header + tab picker)
    var mainTabOverview: String { "Обзор" }
    var mainTabReport: String { "Отчёт" }
    var mainCollectingInfo: String { "Собираем сведения о системе…" }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { "Метрики" }
    var overviewKickerMemory: String { "Память" }
    var overviewKickerProcesses: String { "Процессы" }
    var overviewKickerFolders: String { "Папки" }
    var overviewKickerSystem: String { "Система" }
    var overviewKickerHistory: String { "История" }

    func headerLoadChip(_ load: String, _ ncpu: Int) -> String { "load \(load) · \(ncpu) ядер" }
    func headerUptimeChip(_ uptime: String) -> String { "аптайм \(uptime)" }
    var headerRefreshReport: String { "Обновить отчёт" }
    var headerStatusNeedsAttention: String { "Требует внимания" }

    // MARK: KPI tiles
    var kpiCpuLabel: String { "Процессор (CPU)" }
    func kpiLoad(_ v: String) -> String { "load \(v)" }
    var kpiLoadUnavailable: String { "load —" }
    func kpiCpuSub(_ loadStr: String, _ ncpu: Int) -> String { "\(loadStr) · \(ncpu) ядер" }
    func kpiCpuLoadFooter(_ l1: String, _ l2: String, _ l3: String) -> String { "нагрузка \(l1) · \(l2) · \(l3)" }
    func kpiCpuSocTemp(_ t: Int) -> String { "SOC \(t) °C" }
    var kpiCpuChartTimeLabel: String { "Время" }
    var kpiMemLabel: String { "Память" }
    func kpiMemUnit(_ total: String) -> String { "из \(total)" }
    func kpiMemSub(_ compressor: String, _ purgeable: String) -> String { "сжатая \(compressor) · выгружаемая \(purgeable)" }
    var kpiSwapLabel: String { "Подкачка (swap)" }
    func kpiSwapUnit(_ total: String) -> String { "из \(total)" }
    func kpiSwapSub(_ free: String) -> String { "свободно \(free)" }
    var kpiDiskLabel: String { "Диск" }
    func kpiDiskUnit(_ size: String) -> String { "из \(size)" }
    var kpiDiskFreeLabel: String { "свободно" }
    func kpiDiskUsedPct(_ pct: Int) -> String { "занято \(pct)%" }
    func kpiDiskUsedDetail(_ base: String, _ dataUsed: String, _ sysUsed: String) -> String {
        base + " · данные \(dataUsed), система \(sysUsed)"
    }
    func kpiDiskTemp(_ t: Int) -> String { "темп. \(t) °C" }
    var kpiBatteryLabel: String { "Батарея" }
    func kpiBatteryCycles(_ n: Int) -> String { "\(n) " + ruPlural(n, "цикл", "цикла", "циклов") }
    func kpiBatteryCondition(_ cond: String) -> String { "состояние \(cond)" }
    func kpiBatteryChargeNow(_ charge: Int) -> String { "сейчас \(charge)%" }
    var kpiBatteryDetailsButton: String { "Детали" }

    // MARK: Security card
    var securityTitle: String { "Безопасность" }
    var securityFileVault: String { "FileVault (шифрование диска)" }
    var securitySip: String { "SIP (защита системы)" }
    var securityFirewall: String { "Файрвол" }
    var securityGatekeeper: String { "Gatekeeper" }

    // MARK: Report tab
    var reportPlaceholder: String { "Отчёт ещё не собран. Нажмите «Обновить отчёт»." }
    var reportShowInFinder: String { "Показать в Finder" }
    var reportCopy: String { "Скопировать" }
    var reportCollecting: String { "Собираем отчёт…" }
    func reportFileUpdatedCaption(_ time: String) -> String { "mac_report.txt · обновлено \(time)" }

    // MARK: Recommendations card
    var recommendationsTitle: String { "Рекомендации" }
    var recommendationsCaption: String { "по отчёту" }
    var recommendationsAllGood: String { "Всё в порядке" }
    var recommendationsTipPrefix: String { "Совет: " }

    // MARK: Advice actions
    var adviceTrashConfirmTitle: String { "Очистить Корзину?" }
    var adviceTrashConfirmButton: String { "Очистить" }
    var adviceTrashError: String { "Не удалось очистить Корзину" }
    var adviceDone: String { "готово" }
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

    // MARK: Storage — shared folder labels
    var storageColFolder: String { "Папка" }
    var storageColSize: String { "Размер" }
    var storageColShare: String { "Доля" }
    var storageTrashLabel: String { "Корзина" }
    var storageAppsLabel: String { "Программы" }

    // MARK: Storage — Домашняя папка
    var storageHomeDirsTitle: String { "Домашняя папка" }
    var storageHomeDirsCaption: String { "топ по размеру" }

    // MARK: Storage — Служебные папки
    var storageServiceDirsTitle: String { "Служебные папки" }
    var storageServiceDirsCaption: String { "кэши, контейнеры, логи, программы" }
    var folderTabHome: String { "Домашняя" }
    var folderTabSvc: String { "Служебные" }

    // MARK: Storage — Диски (SMART)
    var storageSmartTitle: String { "Диски (SMART)" }
    func storageSmartUpdatedCaption(_ time: String) -> String { "обновлено \(time)" }
    var storageSmartRefreshButton: String { "Обновить" }
    var storageSmartColAttribute: String { "Атрибут" }
    var storageSmartColValue: String { "Значение" }
    var storageSmartInstallButton: String { "Установить smartmontools" }
    var storageSmartNeedsHomebrew: String { "Для SMART внешних дисков нужны Homebrew и smartmontools" }
    func storageSmartInstallFailed(_ msg: String) -> String { "Установка не удалась: \(msg)" }
    var storageSmartKindInternal: String { "ВНУТРЕННИЙ" }
    var storageSmartKindExternal: String { "ВНЕШНИЙ" }

    // MARK: Process cards
    var processesTitle: String { "Процессы" }
    var processSegCPU: String { "CPU" }
    var processSegMem: String { "Память" }
    var processesMetricA11y: String { "Метрика процессов" }
    var processListCaption: String { "живой снимок top" }
    var processLoadingDetails: String { "Загружаем детали…" }
    var processDetailThreads: String { "Потоки" }
    var processDetailMemory: String { "Память" }
    var processDetailPath: String { "Путь" }
    var processQuit: String { "Завершить" }
    var processSignalError: String { "Не удалось отправить сигнал (нет прав)" }
    var processForceQuit: String { "Снять принудительно" }
    var processForceQuitConfirm: String { "Снять" }
    var processForceQuitInlineQuestion: String { "Снять принудительно?" }
    func processForceQuitTitle(_ name: String) -> String { "Принудительно снять процесс „\(name)“?" }
    func processRevealA11y(_ name: String) -> String { "Показать „\(name)“ в Finder" }
    func processTerminateA11y(_ name: String) -> String { "Завершить процесс „\(name)“" }
    func processKillA11y(_ name: String) -> String { "Принудительно снять процесс „\(name)“" }

    // MARK: Maintenance card
    var maintenanceTitle: String { "Обслуживание системы" }
    var maintenanceBrewNotInstalled: String { "не установлен" }
    var maintenanceBrewAllFresh: String { "Все пакеты свежие \u{2713}" }
    func maintenanceBrewOutdatedCount(_ n: Int) -> String { "Устаревших пакетов: \(n)" }
    var maintenanceUpdatesSection: String { "Обновления macOS" }
    var maintenanceUpdatesAllUpdated: String { "Всё обновлено \u{2713}" }
    var maintenanceCrashesSection: String { "Недавние краши" }
    var maintenanceCrashesNone: String { "Свежих крашей нет \u{2713}" }
    func maintenanceAndMore(_ n: Int) -> String { "и ещё \(n)" }
    var maintenanceBrewUpgradeButton: String { "Обновить пакеты" }
    var maintenanceBrewUpgrading: String { "Обновляем пакеты… (может занять несколько минут)" }
    func maintenanceBrewProgressDownloading(_ files: Int) -> String {
        "Скачиваем пакеты… (готово: \(files) \(ruPlural(files, "файл", "файла", "файлов")))"
    }
    func maintenanceBrewProgressUpgrading(_ name: String, _ k: Int, _ n: Int, _ pct: Int) -> String {
        "Обновляем \(name)… \(k) из \(n) (\(pct) %)"
    }
    func maintenanceBrewProgressUpgradingBare(_ name: String) -> String { "Обновляем \(name)…" }
    var maintenanceBrewUpgradeFailed: String { "Не удалось обновить пакеты — запустите brew upgrade в Терминале" }
    var maintenanceOpenSoftwareUpdate: String { "Открыть Системные настройки…" }

    // MARK: Time Machine card
    var timeMachineNotConfigured: String { "Time Machine не настроен" }
    var timeMachineDestination: String { "Назначение" }
    var timeMachineType: String { "Тип" }
    var timeMachineTypeLocal: String { "локальный диск" }
    var timeMachineQuota: String { "Квота" }
    var timeMachineLastBackup: String { "Последний бэкап" }
    var timeMachineSnapshots: String { "Локальные снапшоты" }
    var timeMachineSnapshotsNone: String { "нет" }
    func timeMachineSnapshotsCount(_ n: Int) -> String { "\(n) шт." }
    func timeMachineSnapshotsLast(_ date: String) -> String { ", последний \(date)" }

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
    var autostartOkTooltip: String { "В порядке" }

    // MARK: Memory card
    var memoryLegendActive: String { "Активная" }
    var memoryLegendWired: String { "Связанная (ядро)" }
    var memoryLegendOther: String { "Прочее (вкл. сжатую)" }
    var memoryLegendInactive: String { "Неактивная" }
    var memoryLegendSpeculative: String { "Спекулятивная" }
    var memoryLegendFree: String { "Свободно" }
    var memoryLegendPurgeable: String { "Выгружаемая (справочно)" }
    var memoryLegendFileCache: String { "Файловый кэш (справочно)" }
    var memoryNoteActive: String { "Память, которую программы используют прямо сейчас или недавно к ней обращались." }
    var memoryNoteWired: String { "Занята ядром macOS и драйверами; не выгружается на диск и не освобождается." }
    var memoryNoteOther: String { "В основном сжатая память: macOS ужимает редко используемые страницы вместо записи в swap." }
    var memoryNoteInactive: String { "Давно не использовалась и будет отдана при нехватке; часто это данные недавно закрытых программ." }
    var memoryNoteSpeculative: String { "Прочитано с диска впрок, «на всякий случай»; освобождается в первую очередь." }
    var memoryNoteFree: String { "Совсем не занятая память. Малое значение — норма." }
    var memoryNotePurgeable: String { "Часть памяти, которую система при нехватке может освободить без потерь (кэши, временные данные)." }
    var memoryNoteFileCache: String { "Содержимое файлов, оставленное в памяти для ускорения повторного доступа; освобождается при необходимости." }
    func memoryTitle(_ total: String) -> String { "Память · всего \(total)" }
    var memoryCaption: String { "живой срез, обновляется непрерывно" }
    var memoryInfoHelp: String { "Наведите на тип памяти, чтобы узнать, что он значит" }
    func memorySwapNote(_ used: String, _ total: String) -> String { "swap: \(used) из \(total)" }
    var memoryOtherNote: String { "«прочее» — сжатая память и не попавшее в срез выше" }
    var memoryColCategory: String { "Категория" }
    var memoryColVolume: String { "Объём" }

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
    func historyGbValue(_ n: Int) -> String { "\(n) ГБ" }
    var historyInfoDate: String { "Дата — один снимок в день (хранится до 60 дней)" }
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
    var energyCancel: String { "Отменить" }
    var energyResetToDefaults: String { "Сбросить к стандартным" }
    var energyResetHelp: String { "Вернуть редактируемые параметры к значениям macOS по умолчанию" }
    var energyApplyCancelled: String { "Отменено" }
    func energyApplyFailed(_ msg: String) -> String { "Не удалось применить: \(msg)" }
    var energyColParam: String { "Параметр" }
    var energyColBattery: String { "От батареи" }
    var energyColAC: String { "От сети" }

    // MARK: Battery detail popover
    func batteryUpdatedAt(_ time: String) -> String { "обновлено \(time)" }
    var batteryLoadingText: String { "Читаем данные батареи…" }
    var batteryPercentSign: String { "%" }
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
    func batteryMA(_ n: Int) -> String { "\(n) мА" }
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
    func batteryPercent(_ n: Int) -> String { "\(n)%" }
    var batteryCapCycles: String { "Циклы" }
    func batteryCyclesOf(_ cycles: Int, _ design: Int) -> String { "\(cycles) из \(design)" }
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
    func batteryOperatingHours(_ n: Int) -> String { "\(n) ч (оценка)" }
    var batteryDetailLowPower: String { "Энергосбережение" }
    var batteryDetailPassportSection: String { "Паспорт" }
    var batteryDetailManufacturer: String { "Производитель" }
    var batteryDetailSerial: String { "Серийный номер" }
    var batteryDetailMfgDate: String { "Дата производства" }
    func batteryDetailMfgDateValue(_ month: String, _ code: String) -> String { "\(month) (код \(code))" }

    // MARK: Assessment
    func assessDiskFull(_ pct: String) -> String { "Диск заполнен на \(pct)% — срочно освободите место." }
    func assessDiskFullSoon(_ pct: String) -> String { "Диск заполнен на \(pct)% — пора освобождать место." }
    func assessSwapHighSerious(_ used: String) -> String { "Swap занят на \(used) — памяти явно не хватает." }
    func assessSwapHighWarn(_ used: String) -> String { "Swap занят на \(used) — память впритык, закрывайте тяжёлые приложения." }
    func assessBatteryCapacityLow(_ cap: Int) -> String { "Ёмкость батареи \(cap)% от новой — думайте о замене." }
    func assessBatteryCapacityWarn(_ cap: Int) -> String { "Ёмкость батареи \(cap)% — ресурс подходит к сервисному порогу (80%)." }
    func assessBatteryConditionBad(_ cond: String) -> String { "Состояние батареи: \(cond) — загляните в сервис." }
    var assessFileVaultOff: String { "FileVault выключен — стоит включить." }
    var assessGatekeeperOff: String { "Gatekeeper выключен — стоит включить." }
    var assessSipOff: String { "SIP выключен — стоит включить." }
    var assessFirewallOff: String { "Файрвол выключен — стоит включить." }
    func assessMacUpdatesAvailable(_ n: Int) -> String { "Доступны обновления macOS: \(n) шт." }
    func assessBrewOutdatedTip(_ n: Int) -> String { "Homebrew: устаревших пакетов — \(n) (brew upgrade)." }
    func assessCrashesRecent(_ n: Int) -> String { "Свежие крэш-репорты: \(n) — посмотрите в Console.app." }
    var assessTimeMachineNotSetUp: String { "Time Machine не настроен — бэкапов нет." }
    func assessSmartDiskErrors(_ title: String) -> String { "Диск «\(title)»: SMART сообщает об ошибках носителя — проверьте диск и бэкапы." }
    func assessSmartDiskWearHigh(_ title: String, _ pct: Int) -> String { "Диск «\(title)»: износ \(pct)% — ресурс на исходе." }
    func assessSmartDiskUnavailableTip(_ title: String) -> String { "Диск «\(title)»: SMART недоступен — переподключите кабель или установите smartmontools (brew install smartmontools)." }
    func assessDownloadsTip(_ sizeStr: String, _ shareSuffix: String) -> String { "«Загрузки» занимают \(sizeStr)\(shareSuffix) — стоит разобрать." }
    func assessDownloadsShareSuffix(_ pct: String) -> String { " (\(pct)% всего диска)" }
    func assessTrashTip(_ sizeStr: String) -> String { "Корзина: \(sizeStr) — можно очистить." }
    func assessCachesTip(_ sizeStr: String) -> String { "Кэши ~/Library/Caches: \(sizeStr) — чистить безопасно." }
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

    // MARK: AI assistant
    var settingsSectionAI: String { "ИИ-ассистент" }
    var aiSettingsProviderLabel: String { "Провайдер" }
    var aiSettingsBaseURLLabel: String { "Базовый URL" }
    var aiSettingsBaseURLPlaceholder: String { "Для Anthropic по умолчанию: api.anthropic.com" }
    var aiSettingsModelLabel: String { "Модель" }
    var aiSettingsKeyLabel: String { "API-ключ" }
    var aiSettingsKeySave: String { "Сохранить ключ" }
    var aiSettingsKeyDelete: String { "Удалить ключ" }
    var aiSettingsKeyStored: String { "Ключ сохранён" }
    var aiSettingsKeyMissing: String { "Ключ не задан — кнопка «Спросить ИИ» скрыта" }
    var aiSettingsPrivacyNote: String { "Ключ хранится только в Связке ключей. Ничего не отправляется без явного подтверждения." }
    var aiSettingsModelCustom: String { "Другое…" }
    var aiSettingsModelCustomPlaceholder: String { "Введите ID модели" }
    var aiSettingsInDevelopmentNote: String { "Функция находится в разработке" }
    var aiAskButton: String { "Спросить ИИ" }
    var aiSheetTitle: String { "Спросить ИИ" }
    var aiSheetPayloadCaption: String { "Будет отправлено ровно то, что показано ниже" }
    var aiToggleSerials: String { "Скрывать серийные номера" }
    var aiToggleUsername: String { "Скрывать имя пользователя в путях" }
    var aiToggleHostname: String { "Скрывать имя компьютера" }
    var aiToggleSSID: String { "Скрывать имя сети Wi-Fi" }
    var aiSendButton: String { "Отправить" }
    var aiSending: String { "Отправка…" }
    var aiAnswerTitle: String { "Ответ" }
    func aiRequestFailed(_ msg: String) -> String { "Ошибка запроса: \(msg)" }
    var aiKeyReadFailed: String { "Не удалось прочитать ключ из Связки ключей" }
    var aiNoReport: String { "Отчёт ещё не собран" }
    var aiPayloadSectionAssessment: String { "ОЦЕНКА" }
    var aiPayloadSectionLive: String { "ТЕКУЩИЕ ПОКАЗАТЕЛИ" }
    var aiPayloadSectionReport: String { "ОТЧЁТ" }
    var aiPayloadTipPrefix: String { "- совет: " }
    var aiSystemPrompt: String { "Ты — ассистент по диагностике Mac. Ниже — диагностический отчёт компьютера пользователя. Кратко ответь по-русски: что в порядке, какие есть проблемы и что делать в первую очередь." }
    var aiPrivacyContract: String { "Ничего не отправляется без ключа и явного подтверждения. Ключ хранится только в Связке ключей и не попадает в отчёты и журналы. Телеметрии нет." }

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
    var attnLabelSwapHigh: String { "Swap" }
    func attnDetailSwapHigh(_ used: String) -> String { used }
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
    func attnDetailCrashes(_ n: Int) -> String { "\(n) отчётов" }
    var attnLabelTimeMachine: String { "Time Machine" }
    var attnDetailTimeMachine: String { "не настроена" }
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

    var attnCapSwap: String { "Swap" }
    var attnCapBattery: String { "Батарея" }
    func attnCapBatteryValue(_ p: Int) -> String { "\(p) %" }
    var attnCapBrew: String { "Homebrew" }
    func attnCapBrewValue(_ n: Int) -> String { "\(n) пакетов" }
    var attnCapSmartNoData: String { "нет данных SMART" }
    var attnCapDownloads: String { "Загрузки" }
    var attnCapTrash: String { "Корзина" }
    var attnCapCaches: String { "Кэши" }
    var attnExplainSwap: String { "Система выгружает память на диск. Откроется «Мониторинг системы» — вкладка «Память» покажет, какие процессы её занимают." }
    var attnExplainBattery: String { "Ёмкость снижается естественным образом со временем. Откроются системные настройки батареи; ничего не изменится без вашего подтверждения." }
    var attnExplainBrew: String { "Запустит `brew upgrade` в фоне — прогресс виден в карточке Homebrew. Установленные пакеты заменяются на свежие версии." }
    var attnExplainSmart: String { "Откроет «Дисковую утилиту». У внешних дисков SMART-атрибуты часто недоступны через USB — это не признак поломки." }
    var attnExplainDownloads: String { "Откроет папку в Finder. Ничего не удаляется — вы сами решаете, что убрать." }
    var attnExplainTrash: String { "Спросит подтверждение, затем очистит Корзину через Finder. Восстановить файлы после этого нельзя." }
    var attnExplainCaches: String { "Откроет ~/Library/Caches в Finder. Приложения пересоздадут кэш при следующем запуске." }

    func attnMore(_ n: Int) -> String { "Ещё \(n)" }
    var attnCollapse: String { "Свернуть" }

    var quietSecurityTitle: String { "Безопасность" }
    var quietUpdatesTitle: String { "Обновления и краши" }
    var quietSecurityStatus: String { "всё включено" }
    var quietUpdatesStatus: String { "нет обновлений и сбоев" }
    var quietNeedsAttention: String { "требует внимания" }
    var quietStatusAllEnabled: String { "всё включено" }
    var quietStatusAllClear: String { "всё в норме" }
    var quietMarkOff: String { "выключен" }
    var quietMarkUnknown: String { "неизвестно" }
    func quietCountItems(_ n: Int) -> String { "\(n) шт." }
}
