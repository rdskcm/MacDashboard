// Engine/Strings/Strings+Overview.swift
// Main window header, overview kickers, KPI tiles, recommendations, advice actions: the `OverviewStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol OverviewStrings {
    // MARK: Main dashboard (header + tab picker)
    var mainCollectingInfo: String { get }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { get }
    var overviewKickerMemory: String { get }
    var overviewKickerProcesses: String { get }
    var overviewKickerFolders: String { get }
    var overviewKickerSystem: String { get }
    func headerLoadChip(_ load: String, _ ncpu: Int) -> String
    func headerUptimeChip(_ uptime: String) -> String
    /// Status chip label when `assessment.problems` is non-empty (pairs with `recommendationsAllGood`).
    var headerStatusNeedsAttention: String { get }

    // MARK: KPI tiles
    var kpiCpuLabel: String { get }
    /// V2-TILES footer: all three load averages, e.g. "нагрузка 1,73 · 2,05 · 2,20".
    /// The core count is NOT repeated here — it already lives in the header's load chip.
    var kpiSwapLabel: String { get }
    func kpiSwapUnit(_ total: String) -> String
    func kpiSwapSub(_ free: String) -> String
    /// V2-DISK-TILE-LABEL: the Disk tile leads with FREE space, so its header label
    /// names the quantity («Диск · свободно» / "Disk · free") — do not shorten to the
    /// bare noun; the tile has no other slot that can say what the big number is.
    var kpiDiskLabel: String { get }
    func kpiDiskUnit(_ size: String) -> String
    func kpiDiskUsedPct(_ pct: Int) -> String
    func kpiDiskUsedDetail(_ base: String, _ dataUsed: String, _ sysUsed: String) -> String
    func kpiDiskPurgeableDetail(_ base: String, _ purgeable: String) -> String
    var kpiBatteryLabel: String { get }
    func kpiBatteryCycles(_ n: Int) -> String

    // MARK: Recommendations card
    var recommendationsTitle: String { get }
    var recommendationsAllGood: String { get }

    // MARK: Advice actions
    var adviceTrashConfirmTitle: String { get }
    var adviceTrashConfirmButton: String { get }
    var adviceTrashError: String { get }
    var adviceTrashNotPermitted: String { get }
    var adviceTrashOpenAutomation: String { get }
    var adviceFirewallConfirmTitle: String { get }
    var adviceFirewallConfirmMessage: String { get }
    var adviceFirewallConfirmButton: String { get }
    var adviceFirewallError: String { get }
    var adviceCancel: String { get }
}

extension StringsEN: OverviewStrings {
    // MARK: Main dashboard (header + tab picker)
    var mainCollectingInfo: String { "Collecting system information…" }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { "Metrics" }
    var overviewKickerMemory: String { "Memory" }
    var overviewKickerProcesses: String { "Processes" }
    var overviewKickerFolders: String { "Folders" }
    var overviewKickerSystem: String { "System" }
    func headerLoadChip(_ load: String, _ ncpu: Int) -> String { "load \(load) · \(ncpu) cores" }
    func headerUptimeChip(_ uptime: String) -> String { "uptime \(uptime)" }
    var headerStatusNeedsAttention: String { "Needs attention" }

    // MARK: KPI tiles
    var kpiCpuLabel: String { "CPU" }
    var kpiSwapLabel: String { "Swap" }
    func kpiSwapUnit(_ total: String) -> String { "of \(total)" }
    func kpiSwapSub(_ free: String) -> String { "free \(free)" }
    var kpiDiskLabel: String { "Disk · free" }
    func kpiDiskUnit(_ size: String) -> String { "of \(size)" }
    func kpiDiskUsedPct(_ pct: Int) -> String { "used \(pct)%" }
    func kpiDiskUsedDetail(_ base: String, _ dataUsed: String, _ sysUsed: String) -> String {
        base + " · data \(dataUsed), system \(sysUsed)"
    }
    func kpiDiskPurgeableDetail(_ base: String, _ purgeable: String) -> String { base + " · purgeable \(purgeable)" }
    var kpiBatteryLabel: String { "Battery" }
    func kpiBatteryCycles(_ n: Int) -> String { "\(n) " + (n == 1 ? "cycle" : "cycles") }

    // MARK: Recommendations card
    var recommendationsTitle: String { "Recommendations" }
    var recommendationsAllGood: String { "All good" }

    // MARK: Advice actions
    var adviceTrashConfirmTitle: String { "Empty the Trash?" }
    var adviceTrashConfirmButton: String { "Empty Trash" }
    var adviceTrashError: String { "Could not empty the Trash" }
    var adviceTrashNotPermitted: String { "MacDashboard is not allowed to control Finder, so it cannot empty the Trash. Allow it under Privacy & Security → Automation." }
    var adviceTrashOpenAutomation: String { "Open Automation settings" }
    var adviceFirewallConfirmTitle: String { "Turn on the firewall?" }
    var adviceFirewallConfirmMessage: String { "Touch ID or an administrator password will be required." }
    var adviceFirewallConfirmButton: String { "Turn On" }
    var adviceFirewallError: String { "Could not turn on the firewall" }
    var adviceCancel: String { "Cancel" }
}

extension StringsRU: OverviewStrings {
    // MARK: Main dashboard (header + tab picker)
    var mainCollectingInfo: String { "Собираем сведения о системе…" }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { "Метрики" }
    var overviewKickerMemory: String { "Память" }
    var overviewKickerProcesses: String { "Процессы" }
    var overviewKickerFolders: String { "Папки" }
    var overviewKickerSystem: String { "Система" }
    func headerLoadChip(_ load: String, _ ncpu: Int) -> String {
        "load \(load) · \(ncpu) \(ruPlural(ncpu, "ядро", "ядра", "ядер"))"
    }
    func headerUptimeChip(_ uptime: String) -> String { "аптайм \(uptime)" }
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
}
