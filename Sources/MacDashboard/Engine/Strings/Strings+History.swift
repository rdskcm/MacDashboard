// Engine/Strings/Strings+History.swift
// History page: the `HistoryStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol HistoryStrings {
    // MARK: History page (REDESIGN-HISTORY)
    func historySub(_ samples: Int) -> String                 // "500 daily samples · mac_check_state.json"
    var historyTagUnreadable: String { get }                   // "file unreadable"
    var historyTagReading: String { get }                      // "reading…"
    func historySince(day: Int, month: Int, year: Int?) -> String   // "since Sep 2, 2025" / "с 2 сентября 2025"
    var historyTitleDisk: String { get }                       // "Disk: used"
    var historyTitleBattery: String { get }                    // "Battery: maximum capacity"
    var historyTitleCycles: String { get }                     // "Battery: charge cycles"
    var historyTitleSwap: String { get }                       // "Swap: used"
    var historyAllMetrics: String { get }                      // "All metrics"
    func historyDaysCaption(_ n: Int) -> String                // "30 days"
    func historySamples(_ n: Int) -> String                    // "1 sample" / "5 samples"
    var historyEmptyTitle: String { get }                      // "Not enough data yet"
    func historyEmptySub(_ samples: Int) -> String             // "1 sample · the chart needs at least 2"
    var historyNeedsTwo: String { get }                        // "Needs at least 2 samples"
    func historyOnlyMonths(_ n: Int) -> String                 // "Only 4 months of data"
    var historyRangeMonth: String { get }                      // "1M"   (kept, value changes)
    var historyRangeQuarter: String { get }                    // "3M"
    var historyRangeYear: String { get }                       // "1Y"
    var historyRangeAll: String { get }                        // "All"
    var historyRangeA11y: String { get }                       // "Range" (kept, value changes)
    var historyMetricPickerDisk: String { get }                // kept
    var historyMetricPickerBattery: String { get }             // kept
    var historyMetricPickerCycles: String { get }              // kept
    var historyMetricPickerSwap: String { get }                // kept
    var historyMetricA11y: String { get }                      // kept
    var historyViewA11y: String { get }                        // "History view"
    func historyDeltaPerMonth(_ value: String) -> String       // "+24 GB per month"
    func historyCycles(_ n: Int) -> String                     // "412 cycles"
    func historyPercent(_ n: Int) -> String                    // "76%" / "76 %"
    func historyPercentText(_ number: String) -> String        // "0.37%" / "0,37 %" (already formatted number)
    var historyColDate: String { get }                         // kept
    var historyColDiskUsed: String { get }                     // kept
    var historyColFree: String { get }                         // kept
    var historyColCycles: String { get }                       // kept
    func historyGbValue(_ n: Int) -> String                    // kept, "312 GB"
    var historyBatteryHelp: String { get }                     // "Maximum capacity, not the current charge"
    var historyTableA11y: String { get }                       // "Sample history"
    var historyReading: String { get }                         // "Reading history…"
    var historyUnreadableTitle: String { get }                 // "Can’t read the history file"
    var historyTryAgainA11y: String { get }                    // "Read the history file again"
    var historyRefreshA11y: String { get }                     // "Reload history from disk"
    func historyShortDate(day: Int, month: Int, year: Int?) -> String            // "Oct 14" · "Sep 2, 2025"
    func historyTooltipDate(weekday: Int, day: Int, month: Int, year: Int) -> String   // "Fri, Oct 17, 2026"
    func historyMonthLabel(_ month: Int) -> String             // "Jun" / "июнь" (standalone form)
    var historyRestartTitle: String { get }                    // kept
    func historyRestartDetail(_ file: String) -> String        // kept
    var historyRestartReveal: String { get }                   // kept
    var historyRestartRevealA11y: String { get }               // kept
    var historyRestartHide: String { get }                     // kept
    var historyRestartHideA11y: String { get }                 // kept
}

extension StringsEN: HistoryStrings {
    // MARK: History page (REDESIGN-HISTORY)
    func historySub(_ samples: Int) -> String { "\(fmtGrouped(samples)) daily \(samples == 1 ? "sample" : "samples") · mac_check_state.json" }
    var historyTagUnreadable: String { "file unreadable" }
    var historyTagReading: String { "reading…" }
    func historySince(day: Int, month: Int, year: Int?) -> String {
        "since \(historyMonthLabel(month)) \(day)" + (year.map { ", \($0)" } ?? "")
    }
    var historyTitleDisk: String { "Disk: used" }
    var historyTitleBattery: String { "Battery: maximum capacity" }
    var historyTitleCycles: String { "Battery: charge cycles" }
    var historyTitleSwap: String { "Swap: used" }
    var historyAllMetrics: String { "All metrics" }
    func historyDaysCaption(_ n: Int) -> String { "\(fmtGrouped(n)) \(n == 1 ? "day" : "days")" }
    func historySamples(_ n: Int) -> String { "\(fmtGrouped(n)) \(n == 1 ? "sample" : "samples")" }
    var historyEmptyTitle: String { "Not enough data yet" }
    func historyEmptySub(_ samples: Int) -> String { "\(historySamples(samples)) · the chart needs at least 2" }
    var historyNeedsTwo: String { "Needs at least 2 samples" }
    func historyOnlyMonths(_ n: Int) -> String { "Only \(n) \(n == 1 ? "month" : "months") of data" }
    var historyRangeMonth: String { "1M" }
    var historyRangeQuarter: String { "3M" }
    var historyRangeYear: String { "1Y" }
    var historyRangeAll: String { "All" }
    var historyRangeA11y: String { "Range" }
    var historyMetricPickerDisk: String { "Disk" }
    var historyMetricPickerBattery: String { "Battery" }
    var historyMetricPickerCycles: String { "Cycles" }
    var historyMetricPickerSwap: String { "Swap" }
    var historyMetricA11y: String { "History metric" }
    var historyViewA11y: String { "History view" }
    func historyDeltaPerMonth(_ value: String) -> String { "\(value) per month" }
    func historyCycles(_ n: Int) -> String { "\(fmtGrouped(n)) \(n == 1 ? "cycle" : "cycles")" }
    func historyPercent(_ n: Int) -> String { "\(n)%" }
    func historyPercentText(_ number: String) -> String { "\(number)%" }
    var historyColDate: String { "Date" }
    var historyColDiskUsed: String { "Disk used" }
    var historyColFree: String { "Free" }
    var historyColCycles: String { "Cycles" }
    func historyGbValue(_ n: Int) -> String { "\(fmtGrouped(n)) GB" }
    var historyBatteryHelp: String { "Maximum capacity, not the current charge" }
    var historyTableA11y: String { "Sample history" }
    var historyReading: String { "Reading history…" }
    var historyUnreadableTitle: String { "Can’t read the history file" }
    var historyTryAgainA11y: String { "Read the history file again" }
    var historyRefreshA11y: String { "Reload history from disk" }
    func historyShortDate(day: Int, month: Int, year: Int?) -> String {
        "\(historyMonthLabel(month)) \(day)" + (year.map { ", \($0)" } ?? "")
    }
    func historyTooltipDate(weekday: Int, day: Int, month: Int, year: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return "\(days[min(max(weekday, 1), 7) - 1]), \(historyMonthLabel(month)) \(day), \(year)"
    }
    func historyMonthLabel(_ month: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return names[min(max(month, 1), 12) - 1]
    }
    var historyRestartTitle: String { "History started over" }
    func historyRestartDetail(_ file: String) -> String { "The previous history file could not be read, so History is being recorded from scratch. The old file was not deleted: it is kept in the same folder as “\(file)”." }
    var historyRestartReveal: String { "Show in Finder" }
    var historyRestartRevealA11y: String { "Show the previous history file in Finder" }
    var historyRestartHide: String { "Hide" }
    var historyRestartHideA11y: String { "Hide the History started over notice" }
}

extension StringsRU: HistoryStrings {
    // MARK: History page (REDESIGN-HISTORY)
    func historySub(_ samples: Int) -> String {
        "\(fmtGrouped(samples)) \(ruPlural(samples, "ежедневный замер", "ежедневных замера", "ежедневных замеров")) · mac_check_state.json"
    }
    var historyTagUnreadable: String { "файл не читается" }
    var historyTagReading: String { "чтение…" }
    func historySince(day: Int, month: Int, year: Int?) -> String {
        let genitive = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        return "с \(day) \(genitive[min(max(month, 1), 12) - 1])" + (year.map { " \($0)" } ?? "")
    }
    var historyTitleDisk: String { "Диск: занято" }
    var historyTitleBattery: String { "Батарея: максимальная ёмкость" }
    var historyTitleCycles: String { "Батарея: циклы зарядки" }
    var historyTitleSwap: String { "Swap: занято" }
    var historyAllMetrics: String { "Все метрики" }
    func historyDaysCaption(_ n: Int) -> String { "\(fmtGrouped(n)) \(ruPlural(n, "день", "дня", "дней"))" }
    func historySamples(_ n: Int) -> String { "\(fmtGrouped(n)) \(ruPlural(n, "замер", "замера", "замеров"))" }
    var historyEmptyTitle: String { "Пока недостаточно данных" }
    func historyEmptySub(_ samples: Int) -> String { "\(historySamples(samples)) · для графика нужно минимум 2" }
    var historyNeedsTwo: String { "Нужно минимум 2 замера" }
    func historyOnlyMonths(_ n: Int) -> String { "Данных только за \(n) \(ruPlural(n, "месяц", "месяца", "месяцев"))" }
    var historyRangeMonth: String { "1 мес" }
    var historyRangeQuarter: String { "3 мес" }
    var historyRangeYear: String { "1 год" }
    var historyRangeAll: String { "Всё" }
    var historyRangeA11y: String { "Период" }
    var historyMetricPickerDisk: String { "Диск" }
    var historyMetricPickerBattery: String { "Батарея" }
    var historyMetricPickerCycles: String { "Циклы" }
    var historyMetricPickerSwap: String { "Swap" }
    var historyMetricA11y: String { "Метрика истории" }
    var historyViewA11y: String { "Вид истории" }
    func historyDeltaPerMonth(_ value: String) -> String { "\(value) за месяц" }
    func historyCycles(_ n: Int) -> String { "\(fmtGrouped(n)) \(ruPlural(n, "цикл", "цикла", "циклов"))" }
    func historyPercent(_ n: Int) -> String { "\(n) %" }
    func historyPercentText(_ number: String) -> String { "\(number) %" }
    var historyColDate: String { "Дата" }
    var historyColDiskUsed: String { "Диск занято" }
    var historyColFree: String { "Свободно" }
    var historyColCycles: String { "Циклы" }
    func historyGbValue(_ n: Int) -> String { "\(fmtGrouped(n)) ГБ" }
    var historyBatteryHelp: String { "Максимальная ёмкость, а не текущий заряд" }
    var historyTableA11y: String { "История замеров" }
    var historyReading: String { "Чтение истории…" }
    var historyUnreadableTitle: String { "Не удаётся прочитать файл истории" }
    var historyTryAgainA11y: String { "Прочитать файл истории ещё раз" }
    var historyRefreshA11y: String { "Перечитать историю с диска" }
    func historyShortDate(day: Int, month: Int, year: Int?) -> String {
        let names = ["янв.", "февр.", "мар.", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."]
        return "\(day) \(names[min(max(month, 1), 12) - 1])" + (year.map { " \($0)" } ?? "")
    }
    func historyTooltipDate(weekday: Int, day: Int, month: Int, year: Int) -> String {
        let days = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
        return "\(days[min(max(weekday, 1), 7) - 1]), \(historyShortDate(day: day, month: month, year: year))"
    }
    func historyMonthLabel(_ month: Int) -> String {
        let names = ["янв.", "февр.", "март", "апр.", "май", "июнь", "июль", "авг.", "сент.", "окт.", "нояб.", "дек."]
        return names[min(max(month, 1), 12) - 1]
    }
    var historyRestartTitle: String { "История началась заново" }
    func historyRestartDetail(_ file: String) -> String { "Прежний файл истории не удалось прочитать, поэтому история ведётся заново. Старый файл не удалён: он сохранён в той же папке под именем «\(file)»." }
    var historyRestartReveal: String { "Показать в Finder" }
    var historyRestartRevealA11y: String { "Показать прежний файл истории в Finder" }
    var historyRestartHide: String { "Скрыть" }
    var historyRestartHideA11y: String { "Скрыть сообщение о том, что история началась заново" }
}
