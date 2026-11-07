// Engine/Strings/Strings+Overview.swift
// Main window header, overview kickers, KPI tiles, recommendations, advice actions: the `OverviewStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol OverviewStrings {
    // MARK: Main dashboard (header + tab picker)
    var mainCollectingInfo: String { get }

    // MARK: Overview page section kickers
    func headerUptimeChip(_ uptime: String) -> String

    // MARK: KPI tiles

    // MARK: Recommendations card

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
    func headerUptimeChip(_ uptime: String) -> String { "uptime \(uptime)" }

    // MARK: KPI tiles

    // MARK: Recommendations card

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
    func headerUptimeChip(_ uptime: String) -> String { "аптайм \(uptime)" }

    // MARK: KPI tiles

    // MARK: Recommendations card

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
