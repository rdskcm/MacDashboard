// Tests/MacDashboardTests/IPhoneHistoryRangeTests.swift
// IPHONE-HISTORY-RANGE: the iPhone battery-history range filter (Engine/IPhoneData.swift) and the shared
// DayWindowRule (Engine/HistorySeries.swift) — window days, enable / fallback / tooltip, strings. Language-dependent
// strings, so the suite sits in `SerialTests` and every string check sets and restores the UI language.
import Foundation
import Testing
@testable import MacDashboard

@MainActor private func withLanguage(_ lang: AppLanguage, _ body: @MainActor () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

extension SerialTests {
    @MainActor struct IPhoneHistoryRangeTests {
        /// `n` consecutive days ending on `end` ("yyyy-MM-dd"), oldest first; health 100, source "import".
        func days(_ n: Int, endingOn end: String) -> [BatteryPoint] {
            let e = IPhoneData.historyDate(end)!
            return (0..<n).map { i in
                let d = Calendar.current.date(byAdding: .day, value: -(n - 1 - i), to: e)!
                return BatteryPoint(day: IPhoneData.historyDay(d), cycles: i, healthPercent: 100,
                                    maxCapacityMAh: nil, designCapacityMAh: 5030, source: "import")
            }
        }
        func pt(_ day: String) -> BatteryPoint {
            BatteryPoint(day: day, cycles: nil, healthPercent: 99, maxCapacityMAh: nil, designCapacityMAh: nil, source: "live")
        }
        func shown(_ p: [BatteryPoint], _ r: IPhoneHistoryRange) -> [String] {
            IPhoneData.historyPoints(p, in: r).map(\.day)
        }

        @Test func windowDays() {
            #expect(IPhoneHistoryRange.allCases.map(\.days) == [30, 91, 182, 365, nil], "segment window days")
        }

        @Test func allIsIdentity() {
            let p = days(400, endingOn: "2026-01-15")
            #expect(IPhoneData.historyPoints(p, in: .all) == p, "All returns the input")
        }

        @Test func windowsEndOnNewest() {
            let p = days(400, endingOn: "2026-01-15")
            let m = IPhoneData.historyPoints(p, in: .month)
            #expect(m.count == 30 && m.first?.day == "2025-12-17" && m.last?.day == "2026-01-15", "1M")
            let q = IPhoneData.historyPoints(p, in: .quarter)
            #expect(q.count == 91 && q.first?.day == "2025-10-17", "3M")
            let h = IPhoneData.historyPoints(p, in: .halfYear)
            #expect(h.count == 182 && h.first?.day == "2025-07-18", "6M")
            let y = IPhoneData.historyPoints(p, in: .year)
            #expect(y.count == 365 && y.first?.day == "2025-01-16", "1Y")
        }

        @Test func anchoredOnNewestPoint() {
            let m = IPhoneData.historyPoints(days(60, endingOn: "2025-06-30"), in: .month)
            #expect(m.first?.day == "2025-06-01" && m.last?.day == "2025-06-30", "window ends on the newest day")
        }

        @Test func sparse() {
            let p = [pt("2025-01-01"), pt("2025-11-20"), pt("2026-01-15")]
            #expect(shown(p, .month) == ["2026-01-15"], "1M")
            for r in [IPhoneHistoryRange.quarter, .halfYear, .year] {
                #expect(shown(p, r) == ["2025-11-20", "2026-01-15"], "\(r)")
            }
            #expect(shown(p, .all).count == 3, "All")
        }

        @Test func orderKept() {
            let p = [pt("2026-01-15"), pt("2025-12-01"), pt("2026-01-10")]
            #expect(shown(p, .month) == ["2026-01-15", "2026-01-10"], "input order")
        }

        @Test func emptyInput() {
            for r in IPhoneHistoryRange.allCases { #expect(shown([], r).isEmpty, "\(r)") }
            #expect(IPhoneData.historySpanDays([]) == nil, "no span")
        }

        @Test func malformedDay() {
            let p = [pt("2026-01-10"), pt("garbage"), pt("2026-01-15")]
            #expect(shown(p, .month) == ["2026-01-10", "2026-01-15"], "malformed dropped from a ranged result")
            #expect(shown(p, .all).count == 3, "All keeps it")
            #expect(IPhoneData.historySpanDays(p) == 5, "span ignores it")
            let g = [pt("garbage")]
            #expect(IPhoneData.historyPoints(g, in: .month) == g, "no valid day returns the input")
        }

        @Test func dstInWindow() {
            let m = IPhoneData.historyPoints(days(120, endingOn: "2026-03-31"), in: .month)
            #expect(m.count == 30 && m.first?.day == "2026-03-02", "30 days across a DST change")
        }

        @Test func enabledAndFallback() {
            withLanguage(.en) {
                let all = IPhoneData.historyRangeState(days(400, endingOn: "2026-01-15"), selected: .year)
                #expect(all.enabled == Set(IPhoneHistoryRange.allCases) && all.disabledHelp == nil, "400 days")

                let alex = IPhoneData.historyRangeState(days(180, endingOn: "2026-01-15"), selected: .month)
                #expect(alex.enabled == [.month, .quarter, .all], "180 days")
                #expect(alex.disabledHelp == "Only 6 months of data", "180 days help")

                let samP = days(120, endingOn: "2026-01-14")
                let sam = IPhoneData.historyRangeState(samP, selected: .year)
                #expect(sam.effective == .all && sam.shown.count == 120, "1Y falls back to All")
                #expect(sam.disabledHelp == "Only 4 months of data", "120 days help")

                let h = IPhoneData.historyRangeState(days(182, endingOn: "2026-01-15"), selected: .all)
                #expect(h.enabled.contains(.halfYear) && !h.enabled.contains(.year), "182 days")

                let sparse = [pt("2025-01-01"), pt("2025-11-20"), pt("2026-01-15")]
                #expect(IPhoneData.historySpanDays(sparse) == 379, "sparse span")
                let sp = IPhoneData.historyRangeState(sparse, selected: .month)
                #expect(sp.enabled == Set(IPhoneHistoryRange.allCases) && sp.disabledHelp == nil, "sparse enabled")
                #expect(sp.shown.count == 1, "1M shows one point")

                let ten = IPhoneData.historyRangeState(days(10, endingOn: "2026-01-15"), selected: .month)
                #expect(ten.enabled == [.all] && ten.disabledHelp == "Only 10 days of data", "10 days")
                #expect(ten.effective == .all && ten.shown.count == 10, "10 days fallback")

                let one = [pt("2026-01-15")]
                let s1 = IPhoneData.historyRangeState(one, selected: .all)
                #expect(s1.enabled.isEmpty && s1.effective == nil && s1.shown == one, "one point")
                #expect(s1.disabledHelp == "Needs at least 2 samples", "one point help")

                let two = IPhoneData.historyRangeState(days(2, endingOn: "2026-01-15"), selected: .all)
                #expect(two.enabled == [.all] && two.disabledHelp == "Only 2 days of data", "2 days")
            }
            withLanguage(.ru) {
                let sam = IPhoneData.historyRangeState(days(120, endingOn: "2026-01-14"), selected: .year)
                #expect(sam.disabledHelp == "Данных только за 4 месяца", "RU 120 days help")
                let ten = IPhoneData.historyRangeState(days(10, endingOn: "2026-01-15"), selected: .all)
                #expect(ten.disabledHelp == "Данных только за 10 дней", "RU 10 days help")
            }
        }

        @Test func strings() {
            func labels() -> [String] {
                [L.historyRangeMonth, L.historyRangeQuarter, L.iphoneHistoryRangeHalfYear, L.historyRangeYear, L.historyRangeAll]
            }
            withLanguage(.en) {
                #expect(labels() == ["1M", "3M", "6M", "1Y", "All"], "EN labels")
            }
            withLanguage(.ru) {
                #expect(labels() == ["1М", "3М", "6М", "1Г", "Всё"], "RU labels")
            }
            #expect(StringsRU().historyRangeYear.unicodeScalars.map(\.value) == [0x31, 0x413], "1Г scalars")
            #expect(StringsRU().historyRangeMonth.unicodeScalars.map(\.value) == [0x31, 0x41C], "1М scalars")
            #expect(StringsRU().historyRangeQuarter.unicodeScalars.map(\.value) == [0x33, 0x41C], "3М scalars")
            #expect(StringsRU().iphoneHistoryRangeHalfYear.unicodeScalars.map(\.value) == [0x36, 0x41C], "6М scalars")
            #expect(StringsEN().iphoneHistoryRangeA11y == "Battery history range", "EN a11y")
            #expect(StringsRU().iphoneHistoryRangeA11y == "Период истории батареи", "RU a11y")
            #expect(StringsEN().iphoneHistoryNoHealth == "No battery health values in this period.", "EN no health")
            #expect(StringsRU().iphoneHistoryNoHealth == "За этот период нет значений здоровья батареи.", "RU no health")
        }

        @Test func historyRegression() {
            withLanguage(.en) {
                #expect(DayWindowRule.disabledHelp(HistoryRange.self, sampleCount: 10, spanDays: 9) == "Only 10 days of data", "D5")
                #expect(DayWindowRule.disabledHelp(HistoryRange.self, sampleCount: 30, spanDays: 29) == "Only 1 month of data", "30 days")
            }
        }
    }
}
