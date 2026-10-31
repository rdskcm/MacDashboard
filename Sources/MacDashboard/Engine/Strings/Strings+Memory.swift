// Engine/Strings/Strings+Memory.swift
// Memory page and Memory card: the `MemoryStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol MemoryStrings {
    // MARK: Memory page (REDESIGN-MEMORY)
    var memUsageTitle: String { get }
    func memUsageCaption(_ total: String) -> String
    var memCompTitle: String { get }
    func memCompCaption(_ total: String) -> String
    var memProcsTitle: String { get }
    func memProcsTop(_ n: Int) -> String
    func memProcCPU(_ pct: String) -> String
    var memUsed: String { get }
    func memHeroNote(_ total: String, _ pct: String) -> String
    var memPurgeable: String { get }
    var memSwap: String { get }
    func memSwapOf(_ pct: String, _ total: String) -> String
    var memFileCache: String { get }
    var memOtherShort: String { get }
    var memTagLow: String { get }
    var memTagMedium: String { get }
    var memTagHigh: String { get }
    var memTagUnknown: String { get }
    var memTagReadFailed: String { get }
    func memUpdatesEvery(_ seconds: Int) -> String
    var memFailTimedOut: String { get }
    var memFailNoReading: String { get }
    var memCompViewA11y: String { get }

    // MARK: Memory card
    var memoryLegendActive: String { get }
    var memoryLegendWired: String { get }
    var memoryLegendOther: String { get }
    var memoryLegendInactive: String { get }
    var memoryLegendSpeculative: String { get }
    var memoryLegendFree: String { get }
    var memoryNoteActive: String { get }
    var memoryNoteWired: String { get }
    var memoryNoteOther: String { get }
    var memoryNoteInactive: String { get }
    var memoryNoteSpeculative: String { get }
    var memoryNoteFree: String { get }
}

extension StringsEN: MemoryStrings {
    // MARK: Memory page (REDESIGN-MEMORY)
    // REDESIGN-MEMORY
    var memUsageTitle: String { "Usage" }
    func memUsageCaption(_ total: String) -> String { "\(total) total · live snapshot" }
    var memCompTitle: String { "Memory composition" }
    func memCompCaption(_ total: String) -> String { "\(total) · by page type" }
    var memProcsTitle: String { "Processes by memory" }
    func memProcsTop(_ n: Int) -> String { "top \(n)" }
    func memProcCPU(_ pct: String) -> String { "\(pct) CPU" }
    var memUsed: String { "Used" }
    func memHeroNote(_ total: String, _ pct: String) -> String { "of \(total) · \(pct)" }
    var memPurgeable: String { "Purgeable" }
    var memSwap: String { "Swap" }
    func memSwapOf(_ pct: String, _ total: String) -> String { "\(pct) of \(total)" }
    var memFileCache: String { "File cache" }
    var memOtherShort: String { "Other" }
    var memTagLow: String { "Pressure: low" }
    var memTagMedium: String { "Pressure: medium" }
    var memTagHigh: String { "Pressure: high" }
    var memTagUnknown: String { "Pressure: unknown" }
    var memTagReadFailed: String { "Read failed" }
    func memUpdatesEvery(_ seconds: Int) -> String { "updates every \(seconds) s" }
    var memFailTimedOut: String { "Couldn’t read memory statistics: no response within 5 s." }
    var memFailNoReading: String { "Couldn’t read memory statistics: the system returned no data." }
    var memCompViewA11y: String { "Composition view" }

    // MARK: Memory card
    var memoryLegendActive: String { "Active" }
    var memoryLegendWired: String { "Wired (kernel)" }
    var memoryLegendOther: String { "Other (incl. compressed)" }
    var memoryLegendInactive: String { "Inactive" }
    var memoryLegendSpeculative: String { "Speculative" }
    var memoryLegendFree: String { "Free" }
    var memoryNoteActive: String { "Memory that apps are using right now or have accessed recently." }
    var memoryNoteWired: String { "Held by the macOS kernel and drivers; can't be swapped out or freed." }
    var memoryNoteOther: String { "Mostly compressed memory: macOS compresses rarely used pages instead of writing them to swap." }
    var memoryNoteInactive: String { "Hasn't been used in a while and will be reclaimed when needed; often data from recently closed apps." }
    var memoryNoteSpeculative: String { "Read from disk ahead of time, “just in case”; the first to be freed." }
    var memoryNoteFree: String { "Completely unused memory. A small value here is normal." }
}

extension StringsRU: MemoryStrings {
    // MARK: Memory page (REDESIGN-MEMORY)
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
    var memCompViewA11y: String { "Вид состава памяти" }

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
}
