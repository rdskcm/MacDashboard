// Tests/MoonportTests/IPhoneManufactureMonthTests.swift
// IPHONE-MANUFACTURE-DATE R5: `BatteryPageModel.mfgMonth` full month name follows the UI language,
// so these run inside SerialTests (process-wide language).
import Testing
@testable import Moonport

extension SerialTests {
    @MainActor struct IPhoneManufactureMonthTests {          // EN via the root .uiLanguage(.en) pin
        @Test func english() {
            #expect(BatteryPageModel.mfgMonth(year: 2025, week: 30, fullMonth: true) == "July 2025")
            #expect(BatteryPageModel.mfgMonth(year: 2023, week: 38, fullMonth: true) == "September 2023")
            #expect(BatteryPageModel.mfgMonth(year: 2024, week: 10) == "Mar 2024")
        }
    }

    @Suite(.uiLanguage(.ru)) @MainActor struct IPhoneManufactureMonthTestsRU {
        @Test func russian() {
            #expect(BatteryPageModel.mfgMonth(year: 2025, week: 30, fullMonth: true) == "июль 2025")
            #expect(BatteryPageModel.mfgMonth(year: 2023, week: 38, fullMonth: true) == "сентябрь 2023")
        }
    }
}
