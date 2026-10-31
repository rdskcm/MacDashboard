// Engine/Strings/Strings+Home.swift
// Home page: the `HomeStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol HomeStrings {
    // MARK: Home (REDESIGN-HOME; strings.json › This Mac Home + 02-home.md)
    var homeMacStatus: String { get }
    func homeTaskCount(_ n: Int) -> String
    func homeNeedAttention(_ n: Int) -> String
    var homeCriticalCount: String { get }
    var homeWarnings: String { get }
    func homeCheckedAt(_ t: String) -> String
    func homeLastCheck(_ t: String) -> String
    func homeTileLastCheck(_ t: String) -> String
    func homeShowAll(_ n: Int) -> String
    var homeYouCan: String { get }
    var homeFreeUpSpace: String { get }
    func homeBrewOutdatedShort(_ n: Int) -> String
    var homeNothingNeedsAttention: String { get }
    var homeFirstScanTitle: String { get }
    var homeFirstScanCaption: String { get }
    func homeScanFailed(timedOut: Bool, lastGood: String?) -> String
    var homeSipHelp: String { get }
    var homeStateOff: String { get }
    var homeDiskHealth: String { get }
    var homeStateFailing: String { get }
    var homeStateFailingShort: String { get }
    func homeStateDiskFull(_ pct: Int) -> String
    var homeStateNotSetUp: String { get }
    var homeStateKeepsAwake: String { get }
    func homeStateWorn(_ pct: Int) -> String
    func homeStatePackagesOutdated(_ n: Int) -> String
    var homeStateUpdateAvailable: String { get }
    func homeStateUpdatesAvailable(_ n: Int) -> String
    var homeMemoryObject: String { get }
    var homeStateRunningLow: String { get }
    var homeStateRunningOut: String { get }
    var homeCrashes: String { get }
    func homeStateReports(_ n: Int) -> String
    var homeDiskWear: String { get }
    func homePercent(_ s: String) -> String
    func homeGB(_ s: String) -> String
    var homeVerbDetails: String { get }
    var homeVerbFreeUp: String { get }
    var homeVerbUpdate: String { get }
    var homeVerbSettings: String { get }
    var homeTagFirewallOff: String { get }
    var homeTagDriveFailing: String { get }
    var homeTagTMNotSetUp: String { get }
    var homeTagWorn: String { get }
    var homeTagBrewOutdated: String { get }
    var homeTagUpdateAvailable: String { get }
    var homeTagLowMemory: String { get }
    var homeTagService: String { get }
    var homeTagFileVaultOff: String { get }
    var homeTagGatekeeperOff: String { get }
    var homeTagSipOff: String { get }
    var homeTagDiskWorn: String { get }
    var homeTagClaudeStale: String { get }
    var homeTagNormal: String { get }
    var homeTagHealthy: String { get }
    var homeTagAllOn: String { get }
    var homeTagUpToDate: String { get }
    func homeHistoryDays(_ n: Int) -> String
    var homeSections: String { get }
    func homeSectionCount(_ n: Int) -> String
    func homeCPUSub(_ chip: String, _ cores: Int) -> String
    func homeCoresOnly(_ cores: Int) -> String
    var homeStorageSub: String { get }
    var homeBatterySub: String { get }
    var homeSecuritySub: String { get }
    var homeBackupsSub: String { get }
    var homeSystemSub: String { get }
    var homeHistorySub: String { get }
    var homeKVLoad: String { get }
    var homeKVProcesses: String { get }
    var homeKVPurgeable: String { get }
    var homeKVFailing: String { get }
    func homeKVWorn(_ pct: Int) -> String
    var homeKVCapacity: String { get }
    func homeKVProtection(_ on: Int) -> String
    var homeKVNone: String { get }
    var homeKVSnapshots: String { get }
    var homeKVLoginItems: String { get }
    var homeKVUpToDate: String { get }
    var homeKVDiskPerMonth: String { get }
    var homeBackA11y: String { get }
    // HOME-C: the Now card
    func homeEverySeconds(_ n: Int) -> String
    func homeLoadCores(_ load: String, _ cores: Int) -> String
    func homeOf(_ s: String) -> String
    var homePressureLow: String { get }
    var homePressureMedium: String { get }
    var homePressureHigh: String { get }
    func homeLegendActive(_ v: String, short: Bool) -> String
    func homeLegendWired(_ v: String) -> String
    func homeLegendInactive(_ v: String, short: Bool) -> String
    func homeLegendCompressed(_ v: String, short: Bool) -> String
    func homeMemFoot(_ used: String, _ total: String, _ compressed: String) -> String
    func homeMemFootNoSwap(_ compressed: String) -> String
    var homeFreeWord: String { get }
    var homeChipHealthy: String { get }
    var homeChipLowSpace: String { get }
    func homeChipDriveFailing(short: Bool) -> String
    var homeChipWorn: String { get }
    var homeChipService: String { get }
    func homeLegendData(_ v: String) -> String
    func homeLegendSystem(_ v: String, short: Bool) -> String
    func homeLegendOther(_ v: String, short: Bool) -> String
    func homeStorageFoot(size: String, purgeable: String?, short: Bool) -> String
    var homeCapacityWord: String { get }
    var homeOfNew: String { get }
    var homeWearThreshold: String { get }
    var homeWearThresholdHelp: String { get }
    func homeBatteryFoot(cycles: Int?, charge: Int?, state: String?, short: Bool) -> String
}

extension StringsEN: HomeStrings {
    // MARK: Home (REDESIGN-HOME; strings.json › This Mac Home + 02-home.md)
    var homeMacStatus: String { "Mac status" }
    func homeTaskCount(_ n: Int) -> String { n == 1 ? "1 task" : "\(n) tasks" }
    func homeNeedAttention(_ n: Int) -> String { n == 1 ? "needs attention" : "need attention" }
    var homeCriticalCount: String { "Critical" }
    var homeWarnings: String { "Warnings" }
    func homeCheckedAt(_ t: String) -> String { "checked at \(t)" }
    func homeLastCheck(_ t: String) -> String { "last check \(t)" }
    func homeTileLastCheck(_ t: String) -> String { "last check \(t)" }
    func homeShowAll(_ n: Int) -> String { "Show all (\(n))" }
    var homeYouCan: String { "You can" }
    var homeFreeUpSpace: String { "Free up space" }
    func homeBrewOutdatedShort(_ n: Int) -> String { "\(n) outdated" }
    var homeNothingNeedsAttention: String { "Nothing needs your attention" }
    var homeFirstScanTitle: String { "Scanning this Mac for the first time…" }
    var homeFirstScanCaption: String { "usually under 30 s" }
    func homeScanFailed(timedOut: Bool, lastGood: String?) -> String { (timedOut ? "Couldn’t scan this Mac: system_profiler didn’t respond within 30 s." : "Couldn’t scan this Mac: system_profiler returned no data.") + (lastGood.map { " Showing data from \($0)." } ?? "") }
    var homeSipHelp: String { "SIP can only be turned on from macOS Recovery." }
    var homeStateOff: String { "off" }
    var homeDiskHealth: String { "Disk health" }
    var homeStateFailing: String { "failing" }
    var homeStateFailingShort: String { "failing" }
    func homeStateDiskFull(_ pct: Int) -> String { "\(pct)% full" }
    var homeStateNotSetUp: String { "not set up" }
    var homeStateKeepsAwake: String { "keeps the Mac awake" }
    func homeStateWorn(_ pct: Int) -> String { "\(pct)% worn" }
    func homeStatePackagesOutdated(_ n: Int) -> String { n == 1 ? "1 package outdated" : "\(n) packages outdated" }
    var homeStateUpdateAvailable: String { "update available" }
    func homeStateUpdatesAvailable(_ n: Int) -> String { "\(n) updates available" }
    var homeMemoryObject: String { "Memory" }
    var homeStateRunningLow: String { "running low" }
    var homeStateRunningOut: String { "running out" }
    var homeCrashes: String { "Crashes" }
    func homeStateReports(_ n: Int) -> String { n == 1 ? "1 report" : "\(n) reports" }
    var homeDiskWear: String { "Disk wear" }
    func homePercent(_ s: String) -> String { "\(s)%" }
    func homeGB(_ s: String) -> String { "\(s) GB" }
    var homeVerbDetails: String { "Details" }
    var homeVerbFreeUp: String { "Free up" }
    var homeVerbUpdate: String { "Update" }
    var homeVerbSettings: String { "Settings…" }
    var homeTagFirewallOff: String { "Firewall off" }
    var homeTagDriveFailing: String { "drive failing" }
    var homeTagTMNotSetUp: String { "TM not set up" }
    var homeTagWorn: String { "Worn" }
    var homeTagBrewOutdated: String { "Homebrew outdated" }
    var homeTagUpdateAvailable: String { "Update available" }
    var homeTagLowMemory: String { "Low memory" }
    var homeTagService: String { "Service" }
    var homeTagFileVaultOff: String { "FileVault off" }
    var homeTagGatekeeperOff: String { "Gatekeeper off" }
    var homeTagSipOff: String { "SIP off" }
    var homeTagDiskWorn: String { "Worn" }
    var homeTagClaudeStale: String { "Claude stale" }
    var homeTagNormal: String { "Normal" }
    var homeTagHealthy: String { "Healthy" }
    var homeTagAllOn: String { "All on" }
    var homeTagUpToDate: String { "Up to date" }
    func homeHistoryDays(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
    var homeSections: String { "Sections" }
    func homeSectionCount(_ n: Int) -> String { "\(n) sections" }
    func homeCPUSub(_ chip: String, _ cores: Int) -> String { "\(chip) · \(cores) cores" }
    func homeCoresOnly(_ cores: Int) -> String { "\(cores) cores" }
    var homeStorageSub: String { "disk, folders, SMART" }
    var homeBatterySub: String { "built-in" }
    var homeSecuritySub: String { "protection, updates, crashes" }
    var homeBackupsSub: String { "Time Machine, Claude" }
    var homeSystemSub: String { "sleep, login items, Homebrew" }
    var homeHistorySub: String { "daily samples" }
    var homeKVLoad: String { "Load" }
    var homeKVProcesses: String { "Processes" }
    var homeKVPurgeable: String { "Purgeable" }
    var homeKVFailing: String { "failing" }
    func homeKVWorn(_ pct: Int) -> String { "\(pct)% worn" }
    var homeKVCapacity: String { "Capacity" }
    func homeKVProtection(_ on: Int) -> String { "\(on) of 4" }
    var homeKVNone: String { "none" }
    var homeKVSnapshots: String { "Snapshots" }
    var homeKVLoginItems: String { "Login items" }
    var homeKVUpToDate: String { "up to date" }
    var homeKVDiskPerMonth: String { "Disk per month" }
    var homeBackA11y: String { "Back to This Mac" }
    // HOME-C: the Now card
    func homeEverySeconds(_ n: Int) -> String { "every \(n) s" }
    func homeLoadCores(_ load: String, _ cores: Int) -> String { "load \(load) · \(cores) cores" }
    func homeOf(_ s: String) -> String { "of \(s)" }
    var homePressureLow: String { "pressure low" }
    var homePressureMedium: String { "pressure medium" }
    var homePressureHigh: String { "pressure high" }
    func homeLegendActive(_ v: String, short: Bool) -> String { short ? "act. \(v)" : "active \(v)" }
    func homeLegendWired(_ v: String) -> String { "wired \(v)" }
    func homeLegendInactive(_ v: String, short: Bool) -> String { short ? "inact. \(v)" : "inactive \(v)" }
    func homeLegendCompressed(_ v: String, short: Bool) -> String { short ? "compr. \(v)" : "compressed \(v)" }
    func homeMemFoot(_ used: String, _ total: String, _ compressed: String) -> String { "swap \(used) of \(total) · compressed \(compressed)" }
    func homeMemFootNoSwap(_ compressed: String) -> String { "compressed \(compressed)" }
    var homeFreeWord: String { "free" }
    var homeChipHealthy: String { "healthy" }
    var homeChipLowSpace: String { "low space" }
    func homeChipDriveFailing(short: Bool) -> String { "drive failing" }
    var homeChipWorn: String { "worn" }
    var homeChipService: String { "service" }
    func homeLegendData(_ v: String) -> String { "data \(v)" }
    func homeLegendSystem(_ v: String, short: Bool) -> String { short ? "sys. \(v)" : "system \(v)" }
    func homeLegendOther(_ v: String, short: Bool) -> String { short ? "oth. \(v)" : "other \(v)" }
    func homeStorageFoot(size: String, purgeable: String?, short: Bool) -> String {
        "of \(size)" + (purgeable.map { short ? " · free up \($0)" : " · purgeable \($0)" } ?? "")
    }
    var homeCapacityWord: String { "capacity" }
    var homeOfNew: String { "of new" }
    var homeWearThreshold: String { "wear threshold 80%" }
    var homeWearThresholdHelp: String { "80% — Apple’s wear threshold" }
    func homeBatteryFoot(cycles: Int?, charge: Int?, state: String?, short: Bool) -> String {
        var parts: [String] = []
        if let n = cycles { parts.append(n == 1 ? "1 cycle" : "\(n) cycles") }
        if let c = charge { parts.append(short ? "charge \(c)%" : "now \(c)%" + (state.map { ", \($0)" } ?? "")) }
        return parts.joined(separator: " · ")
    }
}

extension StringsRU: HomeStrings {
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
