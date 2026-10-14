// Tests/MacDashboardTests/L10nTests.swift
// Port of Checks/main.swift lines 1491-1617 (CHECKS-SWIFT-TESTING). ruPlural / StringsRU smoke, live language switching, SMART label localizer.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct L10nTests {
        @Test func ruPluralAndStrings() async {
            // =====================================================================
            // MARK: - L10n (ruPlural + StringsRU smoke)
            // =====================================================================

            // Full Russian plural-form edge-case set (V21-RU-PLURAL).
            #expect(ruPlural(0,   "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=0 ⇒ циклов")
            #expect(ruPlural(1,   "цикл", "цикла", "циклов") == "цикл",   "ruPlural: n=1 ⇒ цикл")
            #expect(ruPlural(2,   "цикл", "цикла", "циклов") == "цикла",  "ruPlural: n=2 ⇒ цикла")
            #expect(ruPlural(3,   "цикл", "цикла", "циклов") == "цикла",  "ruPlural: n=3 ⇒ цикла")
            #expect(ruPlural(4,   "цикл", "цикла", "циклов") == "цикла",  "ruPlural: n=4 ⇒ цикла")
            #expect(ruPlural(5,   "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=5 ⇒ циклов")
            #expect(ruPlural(11,  "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=11 ⇒ циклов (teen exception)")
            #expect(ruPlural(12,  "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=12 ⇒ циклов (teen exception)")
            #expect(ruPlural(14,  "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=14 ⇒ циклов (teen exception)")
            #expect(ruPlural(21,  "цикл", "цикла", "циклов") == "цикл",   "ruPlural: n=21 ⇒ цикл")
            #expect(ruPlural(100, "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=100 ⇒ циклов")
            #expect(ruPlural(101, "цикл", "цикла", "циклов") == "цикл",   "ruPlural: n=101 ⇒ цикл")
            #expect(ruPlural(104, "цикл", "цикла", "циклов") == "цикла",  "ruPlural: n=104 ⇒ цикла")
            #expect(ruPlural(111, "цикл", "цикла", "циклов") == "циклов", "ruPlural: n=111 ⇒ циклов (teen exception)")

            // The three RU strings converted in V21-RU-PLURAL. StringsRU() directly, not L,
            // so these do not depend on the language pin.
            do {
                let ru = StringsRU()
                #expect(ru.attnDetailCrashes(1) == "1 отчёт",    "StringsRU.attnDetailCrashes(1) ⇒ 1 отчёт")
                #expect(ru.attnDetailCrashes(2) == "2 отчёта",   "StringsRU.attnDetailCrashes(2) ⇒ 2 отчёта")
                #expect(ru.attnDetailCrashes(5) == "5 отчётов",  "StringsRU.attnDetailCrashes(5) ⇒ 5 отчётов")
                #expect(ru.attnDetailCrashes(11) == "11 отчётов", "StringsRU.attnDetailCrashes(11) ⇒ 11 отчётов")
                #expect(ru.attnCapBrewValue(1) == "1 пакет",     "StringsRU.attnCapBrewValue(1) ⇒ 1 пакет")
                #expect(ru.attnCapBrewValue(3) == "3 пакета",    "StringsRU.attnCapBrewValue(3) ⇒ 3 пакета")
                #expect(ru.attnCapBrewValue(8) == "8 пакетов",   "StringsRU.attnCapBrewValue(8) ⇒ 8 пакетов")
                #expect(ru.headerLoadChip("1,00", 1) == "load 1,00 · 1 ядро",  "StringsRU.headerLoadChip ncpu=1 ⇒ 1 ядро")
                #expect(ru.headerLoadChip("1,00", 2) == "load 1,00 · 2 ядра",  "StringsRU.headerLoadChip ncpu=2 ⇒ 2 ядра")
                #expect(ru.headerLoadChip("1,00", 8) == "load 1,00 · 8 ядер",  "StringsRU.headerLoadChip ncpu=8 ⇒ 8 ядер")
                // Amendment 1: the history chart's cycles tooltip renders exactly this string.
                // HistoryCard.valueParts is a private method on a SwiftUI View and is not
                // reachable from this target, so this asserts the composed string, not the
                // call site.
                #expect(ru.kpiBatteryCycles(1) == "1 цикл",       "StringsRU.kpiBatteryCycles(1) ⇒ 1 цикл")
                #expect(ru.kpiBatteryCycles(2) == "2 цикла",      "StringsRU.kpiBatteryCycles(2) ⇒ 2 цикла")
                #expect(ru.kpiBatteryCycles(11) == "11 циклов",   "StringsRU.kpiBatteryCycles(11) ⇒ 11 циклов")
                #expect(ru.kpiBatteryCycles(357) == "357 циклов", "StringsRU.kpiBatteryCycles(357) ⇒ 357 циклов")
            }

            #expect(!L.kpiCpuLabel.isEmpty, "L.kpiCpuLabel: non-empty")
            #expect(!L.securityTitle.isEmpty, "L.securityTitle: non-empty")
            #expect(!AppInfo.name.isEmpty, "AppInfo.name: non-empty")
        }

        @Test func liveLanguageSwitching() async {
            // =====================================================================
            // MARK: - L10nStore (live language switching)
            // =====================================================================

            do {
                L10nStore.shared.language = .en
                #expect(L.kpiBatteryLabel == "Battery", "L10nStore: switch .en, kpiBatteryLabel == Battery")
                #expect(L.kpiBatteryCycles(1) == "1 cycle", "L10nStore: switch .en, kpiBatteryCycles(1) == 1 cycle")
                #expect(L.kpiBatteryCycles(3) == "3 cycles", "L10nStore: switch .en, kpiBatteryCycles(3) == 3 cycles")
                #expect(ReportWriter.fmtBytes(1_073_741_824).contains("GB"), "L10nStore: switch .en, fmtBytes(1GiB) contains GB")
                #expect(!L.recommendationsAllGood.isEmpty && L.recommendationsAllGood != StringsRU().recommendationsAllGood,
                      "L10nStore: switch .en, recommendationsAllGood non-empty and differs from RU")

                L10nStore.shared.language = .ru
                #expect(L.kpiBatteryLabel == "Батарея", "L10nStore: switch back .ru, kpiBatteryLabel == Батарея")
                #expect(ReportWriter.fmtBytes(1_073_741_824).contains("ГБ"), "L10nStore: switch back .ru, fmtBytes(1GiB) contains ГБ")

                // launchLanguage is a lazily-initialized static: since it's touched here for
                // the first time (after the .ru pin at file top), it captures .ru — matching
                // the pinned language regardless of the switches above.
                #expect(L10nStore.launchLanguage == .ru, "L10nStore: launchLanguage == .ru (matches pinned launch language)")
            }
        }

        @Test func smartLocalizedLabelRender() async {
            // =====================================================================
            // MARK: - SMART render-time localizer (smartLocalizedLabel — Block N2)
            // =====================================================================
            //
            // smartCriticalWarningRU and smartLocalizedLabel are defined in
            // Engine/ReportWriter.swift. That file is symlinked into this Checks target
            // (Checks/ReportWriter.swift → ../Sources/MacDashboard/Engine/ReportWriter.swift)
            // as production engine code, not a test file, so — despite the name similarity —
            // the cases below live here in main.swift, alongside every other check in this
            // harness, rather than inside the symlinked engine source.

            do {
                // Pinned .ru at file top: known attribute names and the hardcoded "SMART: OK"
                // status word both translate.
                #expect(smartLocalizedLabel("Temperature") == "Температура", "smartLocalizedLabel: RU Temperature -> Температура")
                #expect(smartLocalizedLabel("Percentage Used") == "Процент износа", "smartLocalizedLabel: RU Percentage Used -> Процент износа")
                #expect(smartLocalizedLabel("Power Cycles") == "Циклов включения", "smartLocalizedLabel: RU Power Cycles -> Циклов включения")
                #expect(smartLocalizedLabel("Critical Warning") == "Критическое предупреждение", "smartLocalizedLabel: RU Critical Warning -> Критическое предупреждение")
                #expect(smartLocalizedLabel("Available Spare") == "Резервная ёмкость", "smartLocalizedLabel: RU Available Spare -> Резервная ёмкость")
                #expect(smartLocalizedLabel("Power On Hours") == "Часов наработки", "smartLocalizedLabel: RU Power On Hours -> Часов наработки")
                #expect(smartLocalizedLabel("Unsafe Shutdowns") == "Некорректных выключений", "smartLocalizedLabel: RU Unsafe Shutdowns -> Некорректных выключений")
                #expect(smartLocalizedLabel("Media and Data Integrity Errors") == "Ошибок целостности данных", "smartLocalizedLabel: RU Media and Data Integrity Errors -> Ошибок целостности данных")
                #expect(smartLocalizedLabel("Error Information Log Entries") == "Записей в журнале ошибок", "smartLocalizedLabel: RU Error Information Log Entries -> Записей в журнале ошибок")
                #expect(smartLocalizedLabel("SMART: OK") == "SMART: в норме", "smartLocalizedLabel: RU SMART: OK -> SMART: в норме")

                // Unknown/unrecognized input passes through unchanged — no crash, no blank output.
                #expect(smartLocalizedLabel("Some Unknown Attr") == "Some Unknown Attr", "smartLocalizedLabel: RU unknown attr passes through unchanged")
                #expect(smartLocalizedLabel("") == "", "smartLocalizedLabel: RU empty string passes through unchanged")

                // Already-localized status strings (baked at collection time by ReportCollector,
                // e.g. "SMART: в норме (проверено)") are not in the lookup table and pass through too.
                #expect(smartLocalizedLabel(L.reportCollectorSmartOkVerified) == L.reportCollectorSmartOkVerified,
                      "smartLocalizedLabel: RU already-localized status word passes through unchanged")
            }

            do {
                L10nStore.shared.language = .en
                #expect(smartLocalizedLabel("Temperature") == "Temperature", "smartLocalizedLabel: EN Temperature -> Temperature")
                #expect(smartLocalizedLabel("Percentage Used") == "Percentage Used", "smartLocalizedLabel: EN Percentage Used -> Percentage Used")
                #expect(smartLocalizedLabel("Power Cycles") == "Power Cycles", "smartLocalizedLabel: EN Power Cycles -> Power Cycles")
                #expect(smartLocalizedLabel("Critical Warning") == "Critical Warning", "smartLocalizedLabel: EN Critical Warning -> Critical Warning")
                #expect(smartLocalizedLabel("SMART: OK") == "SMART: OK", "smartLocalizedLabel: EN SMART: OK -> SMART: OK")

                // Cross-language sanity: a label that differs meaningfully between RU/EN really
                // does differ (guards against the dict silently falling back to raw/no-op).
                L10nStore.shared.language = .ru
                let ru = smartLocalizedLabel("Temperature")
                L10nStore.shared.language = .en
                let en = smartLocalizedLabel("Temperature")
                #expect(ru != en, "smartLocalizedLabel: Temperature differs between RU and EN")

                // Pass-through for unknown input holds in EN too.
                #expect(smartLocalizedLabel("Some Unknown Attr") == "Some Unknown Attr", "smartLocalizedLabel: EN unknown attr passes through unchanged")

                L10nStore.shared.language = .ru
            }
        }
    }
}
