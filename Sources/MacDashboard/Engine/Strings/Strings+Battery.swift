// Engine/Strings/Strings+Battery.swift
// Energy card and Battery page: the `BatteryStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol BatteryStrings {
    // MARK: Energy card
    var energyValueOn: String { get }
    var energyValueOff: String { get }
    func energyApply(_ n: Int) -> String

    // MARK: Battery page (REDESIGN-BATTERY; strings.json › Battery + 06-battery.md)
    var batteryLoadingText: String { get }
    func batteryMinutes(_ m: Int) -> String
    func batteryHoursMinutes(_ h: Int, _ m: Int) -> String
    var batteryStatusOnBattery: String { get }
    func batteryStatusRemaining(_ time: String) -> String
    var batteryStatusCharging: String { get }
    func batteryStatusUntilFull(_ time: String) -> String
    var batteryStatusACFull: String { get }
    var batteryStatusACNotCharging: String { get }
    var batterySectionNow: String { get }
    var batteryLabelPower: String { get }
    func batteryWatts(_ v: String) -> String
    var batteryLabelCurrent: String { get }
    var batteryLabelVoltage: String { get }
    func batteryVolts(_ v: String) -> String
    var batteryLabelTemperature: String { get }
    func batteryCelsius(_ v: String) -> String
    func batteryCellsLine(_ joined: String) -> String
    var batterySectionCapacity: String { get }
    var batteryCapMax: String { get }
    func batteryMAh(_ n: Int) -> String
    var batteryCapDesign: String { get }
    var batteryCapHealth: String { get }
    var batteryCapCycles: String { get }
    func batteryCyclesOf(_ cycles: String, _ design: String) -> String
    var batteryCapCurrentCharge: String { get }
    var batteryCapCondition: String { get }
    var batterySectionCharging: String { get }
    var batteryChargeAdapter: String { get }
    var batteryChargeProtocol: String { get }
    var batteryChargeProfiles: String { get }
    var batteryChargeCurrentLabel: String { get }
    var batteryChargeStatus: String { get }
    func batteryAdapterUsbC(_ watts: Int) -> String
    func batteryAdapterWattsSuffix(_ watts: Int) -> String
    var batteryAdapterWireless: String { get }
    func batteryUsbPdLine(_ v: String, _ a: String) -> String
    var batteryStatusFullyCharged: String { get }
    var batteryStatusNotCharging: String { get }
    func batteryNotChargingCode(_ n: Int) -> String
    var batterySectionLifetime: String { get }
    var batteryLifetimeTempLabel: String { get }
    func batteryLifetimeTempValue(_ min: Int, _ avg: String, _ max: Int) -> String
    var batteryLifetimeMaxCharge: String { get }
    var batteryLifetimeMaxDischarge: String { get }
    var batteryLifetimeVoltage: String { get }
    func batteryLifetimeVoltageRange(_ min: String, _ max: String) -> String
    var batteryLifetimeOperatingTime: String { get }
    var batteryDetailLowPower: String { get }
    var batteryDetailPassportSection: String { get }
    var batteryDetailManufacturer: String { get }
    var batteryDetailSerial: String { get }
    var batteryDetailMfgDate: String { get }
    func batSub(_ cycles: Int?) -> String
    func batTagCapacity(_ pct: String) -> String
    var batTagReadFailed: String { get }
    var batTagUnknown: String { get }
    func batNowCaption(_ time: String) -> String
    var batFailTimedOut: String { get }
    var batFailNoReading: String { get }
    var batFailShowingSaved: String { get }
    var batHealthNote: String { get }
    var batWornNote: String { get }
    func batServiceNote(_ parts: [String]) -> String
    func batServiceCapacity(_ pct: String) -> String
    var batServiceCycles: String { get }
    var batBatterySettings: String { get }
    var batBatterySettingsA11y: String { get }
    var batChargingCaption: String { get }
    var batLifetimeCaption: String { get }
    func batHours(_ s: String) -> String
    var batEstimate: String { get }
    func batCode(_ code: String) -> String
    var batHistoryTitle: String { get }
    func batHistoryDelta(_ signedPct: String, months: Int) -> String
    var batHistoryNotEnough: String { get }
    var batHistoryFoot: String { get }
    var batHistoryFootA11y: String { get }
    var privilegedTimedOut: String { get }   // REDESIGN-SECURITY step 2
    var secGatekeeperError: String { get }
    var secRestartRequired: String { get }   // REDESIGN-SECURITY (step 1 minimum; the rest of the table lands in step 3)
}

extension StringsEN: BatteryStrings {
    // MARK: Energy card
    var energyValueOn: String { "on" }
    var energyValueOff: String { "off" }
    func energyApply(_ n: Int) -> String { "Apply (\(n))" }

    // MARK: Battery page (REDESIGN-BATTERY; strings.json › Battery + 06-battery.md)
    var batteryLoadingText: String { "Reading battery data…" }
    func batteryMinutes(_ m: Int) -> String { "\(m) min" }
    func batteryHoursMinutes(_ h: Int, _ m: Int) -> String { "\(h) h \(m) min" }
    var batteryStatusOnBattery: String { "On battery" }
    func batteryStatusRemaining(_ time: String) -> String { " · \(time) remaining" }
    var batteryStatusCharging: String { "Charging" }
    func batteryStatusUntilFull(_ time: String) -> String { " · \(time) until full" }
    var batteryStatusACFull: String { "AC power · charged" }
    var batteryStatusACNotCharging: String { "AC power · not charging" }
    var batterySectionNow: String { "Now" }
    var batteryLabelPower: String { "Power" }
    func batteryWatts(_ v: String) -> String { "\(v) W" }
    var batteryLabelCurrent: String { "Current" }
    var batteryLabelVoltage: String { "Voltage" }
    func batteryVolts(_ v: String) -> String { "\(v) V" }
    var batteryLabelTemperature: String { "Temperature" }
    func batteryCelsius(_ v: String) -> String { "\(v) °C" }
    func batteryCellsLine(_ joined: String) -> String { "Cells: \(joined) V" }
    var batterySectionCapacity: String { "Capacity and health" }
    var batteryCapMax: String { "Maximum" }
    func batteryMAh(_ n: Int) -> String { "\(n) mAh" }
    var batteryCapDesign: String { "Design" }
    var batteryCapHealth: String { "Health" }
    var batteryCapCycles: String { "Cycles" }
    func batteryCyclesOf(_ cycles: String, _ design: String) -> String { "\(cycles) of \(design)" }
    var batteryCapCurrentCharge: String { "Current charge" }
    var batteryCapCondition: String { "Condition" }
    var batterySectionCharging: String { "Charging" }
    var batteryChargeAdapter: String { "Adapter" }
    var batteryChargeProtocol: String { "Protocol" }
    var batteryChargeProfiles: String { "Profiles" }
    var batteryChargeCurrentLabel: String { "Charging current" }
    var batteryChargeStatus: String { "Status" }
    func batteryAdapterUsbC(_ watts: Int) -> String { "USB-C · \(watts) W" }
    func batteryAdapterWattsSuffix(_ watts: Int) -> String { " (\(watts) W)" }
    var batteryAdapterWireless: String { ", wireless" }
    func batteryUsbPdLine(_ v: String, _ a: String) -> String { "USB PD · \(v) V × \(a) A" }
    var batteryStatusFullyCharged: String { "Charged" }
    var batteryStatusNotCharging: String { "Not charging" }
    func batteryNotChargingCode(_ n: Int) -> String { " (code \(n))" }
    var batterySectionLifetime: String { "Lifetime" }
    var batteryLifetimeTempLabel: String { "Temperature min/avg/max" }
    func batteryLifetimeTempValue(_ min: Int, _ avg: String, _ max: Int) -> String { "\(min) / \(avg) / \(max) °C" }
    var batteryLifetimeMaxCharge: String { "Max charge current" }
    var batteryLifetimeMaxDischarge: String { "Max discharge current" }
    var batteryLifetimeVoltage: String { "Pack voltage" }
    func batteryLifetimeVoltageRange(_ min: String, _ max: String) -> String { "\(min)–\(max) V" }
    var batteryLifetimeOperatingTime: String { "Operating hours" }
    var batteryDetailLowPower: String { "Low Power Mode" }
    var batteryDetailPassportSection: String { "Passport" }
    var batteryDetailManufacturer: String { "Manufacturer" }
    var batteryDetailSerial: String { "Serial number" }
    var batteryDetailMfgDate: String { "Manufacture date" }
    func batSub(_ cycles: Int?) -> String { cycles.map { "internal · \(fmtGrouped($0)) " + ($0 == 1 ? "cycle" : "cycles") } ?? "internal" }
    func batTagCapacity(_ pct: String) -> String { "capacity \(pct)" }
    var batTagReadFailed: String { "Read failed" }
    var batTagUnknown: String { "health unknown" }
    func batNowCaption(_ time: String) -> String { "updated \(time) · every 3 s" }
    var batFailTimedOut: String { "Couldn’t read battery data: ioreg didn’t respond within 5 s." }
    var batFailNoReading: String { "Couldn’t read battery data: ioreg reported no battery." }
    var batFailShowingSaved: String { "Showing the last saved values." }
    var batHealthNote: String { "maximum vs design" }
    var batWornNote: String { "Capacity is below 80%: the battery is nearing the service threshold. Replace it at an Apple service provider." }
    func batServiceNote(_ parts: [String]) -> String { "macOS recommends service" + (parts.isEmpty ? "" : ": " + parts.joined(separator: " and ")) + ". Runtime may be shorter and the Mac may shut down unexpectedly. Replace it at an Apple service provider." }
    func batServiceCapacity(_ pct: String) -> String { "capacity is \(pct)" }
    var batServiceCycles: String { "the cycle count exceeds the rated limit" }
    var batBatterySettings: String { "Battery Settings" }
    var batBatterySettingsA11y: String { "Open the system Battery settings" }
    var batChargingCaption: String { "adapter connected" }
    var batLifetimeCaption: String { "from the battery controller" }
    func batHours(_ s: String) -> String { "\(s) h" }
    var batEstimate: String { "estimate" }
    func batCode(_ code: String) -> String { "code \(code)" }
    var batHistoryTitle: String { "Capacity history" }
    func batHistoryDelta(_ signedPct: String, months: Int) -> String { "\(signedPct) over \(months) " + (months == 1 ? "month" : "months") }
    var batHistoryNotEnough: String { "not enough data for a trend yet" }
    var batHistoryFoot: String { "full chart in History" }
    var batHistoryFootA11y: String { "Open History with the Battery chart" }
    var privilegedTimedOut: String { "Touch ID didn’t respond within 30 s" }
    var secGatekeeperError: String { "Could not turn on Gatekeeper" }
    var secRestartRequired: String { "restart required" }
}

extension StringsRU: BatteryStrings {
    // MARK: Energy card
    var energyValueOn: String { "вкл" }
    var energyValueOff: String { "выкл" }
    func energyApply(_ n: Int) -> String { "Применить (\(n))" }

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
}
