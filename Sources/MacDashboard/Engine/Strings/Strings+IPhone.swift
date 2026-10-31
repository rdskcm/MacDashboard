// Engine/Strings/Strings+IPhone.swift
// iPhone module: device list, status, battery, history: the `IPhoneStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol IPhoneStrings {
    // MARK: iPhone module
    var mainModeMac: String { get }
    var mainModeDevices: String { get }
    var iphoneKickerDevices: String { get }
    var iphoneStatusConnected: String { get }
    var iphoneStatusNeedsTrust: String { get }
    var iphoneStatusReading: String { get }
    var iphoneStatusFailed: String { get }
    var iphoneUnknownDevice: String { get }
    var iphoneRetry: String { get }
    var iphoneSearchAgain: String { get }
    var iphoneRestartService: String { get }
    var iphoneRestartConfirmTitle: String { get }
    var iphoneRestartConfirmBody: String { get }
    var iphoneRestartConfirm: String { get }
    var iphoneRestartCancel: String { get }
    var iphoneRestartBusy: String { get }
    func iphoneRestartFailed(_ detail: String) -> String
    var iphoneBack: String { get }
    var iphoneRefresh: String { get }
    var iphoneUnavailable: String { get }
    func iphoneStatusRemembered(_ date: String) -> String
    func iphoneOpenDeviceA11y(_ name: String) -> String

    var iphoneBatteryTitle: String { get }
    var iphoneHistoryTitle: String { get }
    var iphoneBatHealth: String { get }
    var iphoneBatCycles: String { get }
    var iphoneBatCharge: String { get }
    var iphoneBatState: String { get }
    var iphoneBatTemperature: String { get }
    var iphoneTempNormal: String { get }
    var iphoneTempWarm: String { get }
    var iphoneTempHot: String { get }
    var iphoneCyclesAging: String { get }
    var iphoneCyclesHigh: String { get }
    var iphoneBatVoltage: String { get }
    var iphoneBatCapacity: String { get }
    var iphoneChargeCharging: String { get }
    var iphoneChargeExternal: String { get }
    var iphoneChargeBattery: String { get }
    var iphoneUnitMAh: String { get }
    var iphoneUnitWh: String { get }
    var iphoneCapacityUnitA11y: String { get }
    var iphoneWhSourceHelp: String { get }
    var iphoneBatteryConnectToRead: String { get }
    var iphoneBatteryNoData: String { get }
    var iphoneBatteryAutoReadOff: String { get }
    var iphoneHistoryEmpty: String { get }
    var iphoneHistorySourceLive: String { get }
    var iphoneHistorySourceImport: String { get }
    var iphoneHistoryColDate: String { get }
    var iphoneHistoryColHealth: String { get }
    var iphoneHistoryColCycles: String { get }
    var iphoneHistoryColSource: String { get }
    func iphoneBatteryFromHistory(_ date: String) -> String
    func iphoneHistoryCaption(_ n: Int) -> String
    var iphoneHistoryChart: String { get }
    var iphoneHistoryTable: String { get }
    var iphoneHistoryViewA11y: String { get }
    func iphoneChartCycles(_ n: Int) -> String
    var iphoneChartSourceImport: String { get }
    func iphoneChartMonth(_ m: Int) -> String
    func iphoneChartWeekLabel(day: Int, month: Int) -> String
}

extension StringsEN: IPhoneStrings {
    // MARK: iPhone module
    var mainModeMac: String { "This Mac" }
    var mainModeDevices: String { "Devices" }
    var iphoneKickerDevices: String { "Devices" }
    var iphoneStatusConnected: String { "Connected by cable" }
    var iphoneStatusNeedsTrust: String { "Trust needed: unlock the iPhone and tap “Trust”" }
    var iphoneStatusReading: String { "Reading…" }
    var iphoneStatusFailed: String { "Could not read the iPhone" }
    var iphoneUnknownDevice: String { "iPhone" }
    var iphoneRetry: String { "Retry" }
    var iphoneSearchAgain: String { "Search again" }
    var iphoneRestartService: String { "Restart connection service…" }
    var iphoneRestartConfirmTitle: String { "Restart the connection service?" }
    var iphoneRestartConfirmBody: String { "The service briefly interrupts every iPhone and iPad connected to this Mac, including Finder sync. It needs an administrator password or Touch ID." }
    var iphoneRestartConfirm: String { "Restart" }
    var iphoneRestartCancel: String { "Cancel" }
    var iphoneRestartBusy: String { "Restarting the connection service" }
    func iphoneRestartFailed(_ detail: String) -> String { "Could not restart the connection service: \(detail)" }
    var iphoneBack: String { "Back" }
    var iphoneRefresh: String { "Refresh" }
    var iphoneUnavailable: String { "iPhone connection is not available on this version of macOS." }
    func iphoneStatusRemembered(_ date: String) -> String { "Not connected · last seen \(date)" }
    func iphoneOpenDeviceA11y(_ name: String) -> String { "Open \(name)" }
    var iphoneBatteryTitle: String { "Battery" }
    var iphoneHistoryTitle: String { "Battery history" }
    var iphoneBatHealth: String { "Health" }
    var iphoneBatCycles: String { "Cycles" }
    var iphoneBatCharge: String { "Charge" }
    var iphoneBatState: String { "State" }
    var iphoneBatTemperature: String { "Temperature" }
    var iphoneTempNormal: String { "normal" }
    var iphoneTempWarm: String { "warm" }
    var iphoneTempHot: String { "hot" }
    var iphoneCyclesAging: String { "aging" }
    var iphoneCyclesHigh: String { "high" }
    var iphoneBatVoltage: String { "Voltage" }
    var iphoneBatCapacity: String { "Capacity" }
    var iphoneChargeCharging: String { "Charging" }
    var iphoneChargeExternal: String { "Plugged in" }
    var iphoneChargeBattery: String { "On battery" }
    var iphoneUnitMAh: String { "mAh" }
    var iphoneUnitWh: String { "Wh" }
    var iphoneCapacityUnitA11y: String { "Capacity units" }
    var iphoneWhSourceHelp: String { "Approximate: capacity × 3.88 V, the typical iPhone battery voltage (Wikipedia, iPhone 16 Pro / 17 Pro articles, from regulatory listings)" }
    var iphoneBatteryConnectToRead: String { "Connect the iPhone by cable to read the battery." }
    var iphoneBatteryNoData: String { "no data" }
    var iphoneBatteryAutoReadOff: String { "Auto-read is off. Press Refresh to read the battery." }
    var iphoneHistoryEmpty: String { "No history yet: points appear on days the iPhone is connected." }
    var iphoneHistorySourceLive: String { "Measured" }
    var iphoneHistorySourceImport: String { "From sysdiagnose" }
    var iphoneHistoryColDate: String { "Date" }
    var iphoneHistoryColHealth: String { "Health" }
    var iphoneHistoryColCycles: String { "Cycles" }
    var iphoneHistoryColSource: String { "Source" }
    func iphoneBatteryFromHistory(_ date: String) -> String { "From history · \(date)" }
    func iphoneHistoryCaption(_ n: Int) -> String { "\(n) \(n == 1 ? "day" : "days")" }
    var iphoneHistoryChart: String { "Chart" }
    var iphoneHistoryTable: String { "Table" }
    var iphoneHistoryViewA11y: String { "Battery history view" }
    func iphoneChartCycles(_ n: Int) -> String { "\(n) \(n == 1 ? "cycle" : "cycles")" }
    var iphoneChartSourceImport: String { "Sysdiagnose" }
    func iphoneChartMonth(_ m: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return names[min(max(m, 1), 12) - 1]
    }
    func iphoneChartWeekLabel(day: Int, month: Int) -> String { "\(iphoneChartMonth(month)) \(day)" }
}

extension StringsRU: IPhoneStrings {
    // MARK: iPhone module
    var mainModeMac: String { "Этот Mac" }
    var mainModeDevices: String { "Устройства" }
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
    var iphoneTempNormal: String { "норма" }
    var iphoneTempWarm: String { "тёплая" }
    var iphoneTempHot: String { "горячая" }
    var iphoneCyclesAging: String { "износ" }
    var iphoneCyclesHigh: String { "высокий" }
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
    var iphoneBatteryAutoReadOff: String { "Авточтение выключено. Нажмите «Обновить», чтобы прочитать батарею." }
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
}
