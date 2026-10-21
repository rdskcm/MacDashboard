// Tests/MacDashboardTests/BatteryPageModelTests.swift
// REDESIGN-BATTERY: health classification, Condition localization, Battery page state/texts/tones, capacity history.
import Foundation
import Testing
@testable import MacDashboard

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func batDetail(_ tweak: (inout BatteryDetail) -> Void = { _ in }) -> BatteryDetail {
    var d = VisualFixture.batteryDetail
    d.cycleCount = 412
    tweak(&d)
    return d
}

private func batInput(detail: BatteryDetail? = batDetail(), condition: String? = "Normal",
                      block: BlockPhase = .ok(at: t0), history: [MacHistoryEntry] = []) -> BatteryPageModel.Input {
    BatteryPageModel.Input(detail: detail, condition: condition, block: block, history: history)
}

private func withLanguage(_ lang: AppLanguage, _ body: () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

private func entries(_ month: String, days: Int, pct: (Int) -> Int?) -> [MacHistoryEntry] {
    (1...days).map { MacHistoryEntry(date: String(format: "%@-%02d", month, $0), battery_pct: pct($0)) }
}

extension SerialTests {
    struct BatteryPageModelTests {
        @Test func classify() {
            #expect(BatteryHealth.classify(healthPercent: nil, condition: nil) == .unknown)
            #expect(BatteryHealth.classify(healthPercent: 88, condition: "Normal") == .normal)
            #expect(BatteryHealth.classify(healthPercent: 80, condition: "Normal") == .normal)
            #expect(BatteryHealth.classify(healthPercent: 79, condition: "Normal") == .worn)
            #expect(BatteryHealth.classify(healthPercent: 88, condition: "Service Recommended") == .service)
            #expect(BatteryHealth.classify(healthPercent: nil, condition: "Service Recommended") == .service)
            #expect(BatteryHealth.classify(healthPercent: 95, condition: "") == .normal)
            #expect(BatteryHealth.classify(healthPercent: 95, condition: " Normal ") == .normal)
        }

        @Test func conditionText() {
            let known = ["Normal", "Service Recommended", "Replace Soon", "Replace Now", "Check Battery"]
            withLanguage(.en) {
                #expect(known.map { BatteryPageModel.conditionText($0) } == known)
                #expect(BatteryPageModel.conditionText("Weird") == "Weird")
                #expect(BatteryPageModel.conditionText("") == nil)
                #expect(BatteryPageModel.conditionText(nil) == nil)
            }
            withLanguage(.ru) {
                #expect(known.map { BatteryPageModel.conditionText($0) } ==
                        ["В норме", "Рекомендуется сервис", "Скоро заменить", "Заменить", "Проверить батарею"])
                #expect(BatteryPageModel.conditionText("Weird") == "Weird")
                #expect(BatteryPageModel.conditionText(nil) == nil)
            }
        }

        @Test func liveCharging() {
            withLanguage(.en) {
                let m = BatteryPageModel.make(batInput())
                #expect(m.phase == .live)
                #expect(m.health == .worn)
                #expect(m.tag == .worn)
                #expect(m.tagText == "capacity 76%")
                #expect(m.sub == "internal · 412 cycles")
                #expect(m.symbol == "battery.100percent.bolt")
                #expect(m.nowCaption == "updated \(CPUPageModel.hhmmss(t0)) · every 3 s")
                let h = m.nowHero
                #expect(h?.label == "Charging · 1 h 10 min until full")
                #expect(h?.value == "82%")
                #expect(h?.fraction == 0.82)
                #expect(h?.tone == .green)
                #expect(h?.note == "Cells: 4.421 · 4.425 · 4.423 V · Low Power Mode off")
                #expect(m.nowTiles.map(\.value) == ["+28.4 W", "+2,140 mA", "13.27 V", "31.2 °C"])
                #expect(m.nowTiles.map(\.valueTone) == [.green, .green, nil, nil])
                #expect(m.nowColumns == 2)
                #expect(m.healthHero.value == "76%")
                #expect(m.healthHero.tone == .amber)
                #expect(m.healthTiles.map(\.value) == ["3,874 mAh", "5,103 mAh", "412 of 1,000", "3,177 mAh", "Normal"])
                #expect(m.healthTiles[4].dot == .green)
                #expect(m.healthTiles[2].valueTone == nil)
                #expect(m.healthNote?.tone == .amber)
                #expect(m.healthNote?.text == L.batWornNote)
                #expect(m.healthNote?.button == .batterySettings)
                #expect(m.showsCharging)
                #expect(m.chargingTiles.map(\.value) == ["Apple 35W Dual USB-C", "USB PD · 20 V × 1.75 A", "5 V · 9 V · 15 V · [20 V]", "2,140 mA", "Charging"])
                #expect(m.chargingTiles[0].note == "Apple · 35 W")
                #expect(m.chargingTiles[4].dot == .green)
                #expect(m.lifetimeTiles.map(\.value) == ["12 / 29 / 47 °C", "3,960 mA", "5,210 mA", "10.2–13.1 V", "6,480 h"])
                #expect(m.lifetimeTiles.last?.note == "estimate")
                #expect(m.passportTiles.map(\.value) == ["Samsung SDI", "F8Y4213A7Q1MXLKA", "Mar 2024"])
                #expect(m.passportTiles.last?.note == "code 2410")
                #expect(m.showsDetailCards)
                #expect(!m.showsWait)
            }
        }

        @Test func liveChargingRU() {
            withLanguage(.ru) {
                let m = BatteryPageModel.make(batInput())
                #expect(m.tagText == "ёмкость 76 %")
                #expect(m.sub == "встроенная · 412 циклов")
                #expect(m.nowTiles[0].value == "+28,4 Вт")
                #expect(m.nowTiles[1].value == "+2\u{2009}140 мА")
                #expect(m.healthTiles[0].value == "3\u{2009}874 мАч")
                #expect(m.healthTiles[2].value == "412 из 1\u{2009}000")
                #expect(m.healthTiles[4].value == "В норме")
                #expect(m.passportTiles.last?.value == "март 2024")
                #expect(m.passportTiles.last?.note == "код 2410")
            }
        }

        @Test func onBattery() {
            withLanguage(.en) {
                let d = batDetail {
                    $0.externalConnected = false; $0.isCharging = false; $0.amperageMA = -604; $0.powerW = -7.9
                    $0.timeToEmptyMin = 380; $0.percent = 64
                }
                let m = BatteryPageModel.make(batInput(detail: d))
                #expect(m.nowHero?.label == "On battery · 6 h 20 min remaining")
                #expect(m.nowHero?.tone == .amber)
                #expect(m.nowTiles[0].value == "\u{2212}7.9 W")
                #expect(m.nowTiles[0].valueTone == .amber)
                #expect(m.nowTiles[1].value == "\u{2212}604 mA")
                #expect(m.nowTiles[1].valueTone == .amber)
                #expect(!m.showsCharging)
                #expect(m.symbol == "battery.75percent")
            }
        }

        @Test func service() {
            let d = batDetail { $0.maxCapacityMAh = 3623; $0.healthPercent = 71; $0.cycleCount = 1012 }
            let input = batInput(detail: d, condition: "Service Recommended")
            withLanguage(.en) {
                let m = BatteryPageModel.make(input)
                #expect(m.health == .service)
                #expect(m.tag == .service)
                #expect(m.tagText == L.commonServiceRecommended)
                #expect(m.healthHero.tone == .hot)
                #expect(m.healthTiles[2].value == "1,012 of 1,000")
                #expect(m.healthTiles[2].valueTone == .hot)
                #expect(m.healthTiles[4].value == "Service Recommended")
                #expect(m.healthTiles[4].dot == .hot)
                #expect(m.healthTiles[4].valueTone == .hot)
                #expect(m.healthNote?.tone == .hot)
                #expect(m.healthNote?.text == "macOS recommends service: capacity is 71% and the cycle count exceeds the rated limit. Runtime may be shorter and the Mac may shut down unexpectedly. Replace it at an Apple service provider.")
            }
            withLanguage(.ru) {
                let m = BatteryPageModel.make(input)
                #expect(m.healthNote?.text == "macOS рекомендует обслуживание: ёмкость 71 %, циклов больше расчётных. Mac может работать от батареи меньше или внезапно выключаться. Замена — в сервисе Apple.")
            }
        }

        @Test func normal() {
            withLanguage(.en) {
                let d = batDetail { $0.maxCapacityMAh = 4491; $0.healthPercent = 88 }
                let m = BatteryPageModel.make(batInput(detail: d))
                #expect(m.health == .normal)
                #expect(m.tag == .healthy)
                #expect(m.tagText == L.homeTagHealthy)
                #expect(m.healthHero.tone == .green)
                #expect(m.healthNote == nil)
            }
        }

        @Test func reading() {
            withLanguage(.en) {
                let m = BatteryPageModel.make(batInput(detail: nil, block: .loading(since: t0)))
                #expect(m.phase == .reading)
                #expect(m.showsWait)
                #expect(!m.showsDetailCards)
                #expect(m.nowHero == nil)
                #expect(m.tag == .reading)
                #expect(m.tagText == L.commonCollectingData)
                #expect(m.sub == "internal")
                #expect(m.nowCaption == nil)
                #expect(m.nowTiles.allSatisfy { $0.value == "—" && $0.valueTone == .neutral })
            }
        }

        @Test func failedWithSaved() {
            withLanguage(.en) {
                let m = BatteryPageModel.make(batInput(block: .failed(.timedOut, lastGoodAt: t0)))
                let hh = CPUPageModel.hhmmss(t0)
                #expect(m.phase == .failed(.timedOut, lastGoodAt: t0))
                #expect(m.nowCaption == L.commonLastData(hh))
                #expect(m.failureNote == L.batFailTimedOut + " " + L.batFailShowingSaved)
                #expect(m.nowHero == nil)
                #expect(m.nowColumns == 4)
                #expect(m.nowTiles.allSatisfy { $0.value == "—" })
                #expect(m.showsDetailCards)
                #expect(m.healthHero.value == "76%")
                #expect(m.sub == "internal · " + L.commonLastData(hh))
                #expect(m.subIsFailure)
                #expect(m.tag == .failed)
                #expect(m.tagText == "Read failed")
            }
        }

        @Test func failedWithoutSaved() {
            withLanguage(.en) {
                let m = BatteryPageModel.make(batInput(detail: nil, block: .failed(.noReading, lastGoodAt: nil)))
                #expect(m.failureNote == L.batFailNoReading)
                #expect(!m.showsDetailCards)
                #expect(m.nowCaption == nil)
                #expect(m.sub == "internal")
                #expect(!m.subIsFailure)
            }
        }

        @Test func capacityHistory() {
            var hist = entries("2025-09", days: 30) { _ in 90 }
            hist += entries("2025-10", days: 31) { _ in 90 }
            hist += entries("2025-11", days: 30) { _ in 89 }
            hist += entries("2025-12", days: 31) { $0 % 2 == 1 ? 88 : 89 }
            hist += entries("2026-01", days: 15) { _ in 88 }
            hist.append(MacHistoryEntry(date: "2026-01-10", battery_pct: nil))
            withLanguage(.en) {
                let (rows, caption) = BatteryPageModel.capacityHistory(hist)
                #expect(rows.map(\.id) == ["2026-01", "2025-12", "2025-11", "2025-10"])
                #expect(rows.map(\.label) == ["Jan 2026", "Dec 2025", "Nov 2025", "Oct 2025"])
                #expect(rows.map(\.value) == ["88%", "88.5%", "89%", "90%"])
                #expect(caption == "\u{2212}2% over 3 months")

                let one = BatteryPageModel.capacityHistory(entries("2026-01", days: 15) { _ in 88 })
                #expect(one.rows.count == 1)
                #expect(one.caption == L.batHistoryNotEnough)

                let two = BatteryPageModel.capacityHistory(
                    [MacHistoryEntry(date: "2025-10-01", battery_pct: 90), MacHistoryEntry(date: "2026-01-01", battery_pct: 88)])
                #expect(two.rows.count == 2)
                #expect(two.caption == "\u{2212}2% over 3 months")

                #expect(BatteryPageModel.capacityHistory([]).rows.isEmpty)
            }
            withLanguage(.ru) {
                let (rows, caption) = BatteryPageModel.capacityHistory(hist)
                #expect(rows.map(\.label) == ["янв. 2026", "дек. 2025", "нояб. 2025", "окт. 2025"])
                #expect(caption == "\u{2212}2 % за 3 месяца")
            }
        }

        @Test func symbol() {
            #expect(BatteryPageModel.symbol(percent: nil, charging: false) == "battery.75percent")
            #expect(BatteryPageModel.symbol(percent: 5, charging: false) == "battery.0percent")
            #expect(BatteryPageModel.symbol(percent: 13, charging: false) == "battery.25percent")
            #expect(BatteryPageModel.symbol(percent: 50, charging: false) == "battery.50percent")
            #expect(BatteryPageModel.symbol(percent: 70, charging: false) == "battery.75percent")
            #expect(BatteryPageModel.symbol(percent: 90, charging: false) == "battery.100percent")
            #expect(BatteryPageModel.symbol(percent: 10, charging: true) == "battery.100percent.bolt")
        }

        @Test func strings() {
            withLanguage(.en) {
                #expect(L.batSub(1) == "internal · 1 cycle")
                #expect(L.batSub(1012) == "internal · 1,012 cycles")
                #expect(L.batHistoryDelta("−1.2%", months: 1) == "−1.2% over 1 month")
            }
            withLanguage(.ru) {
                #expect(L.batSub(1) == "встроенная · 1 цикл")
                #expect(L.batSub(1012) == "встроенная · 1\u{2009}012 циклов")
                #expect(L.batHistoryDelta("−1,2 %", months: 2) == "−1,2 % за 2 месяца")
                #expect(L.batHistoryDelta("−1,2 %", months: 5) == "−1,2 % за 5 месяцев")
            }
        }
    }
}
