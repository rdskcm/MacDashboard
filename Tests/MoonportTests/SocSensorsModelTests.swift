// Tests/MoonportTests/SocSensorsModelTests.swift
// TEMP-SENSORS-DETAIL Stage 2: the Sensors card's display model (lists, names, value text) and its strings.
// Serial: it switches the UI language.
import Foundation
import Testing
@testable import Moonport

private let allReadings = [SensorReading(kind: .eCores, celsius: 47), SensorReading(kind: .pCores, celsius: 58),
                           SensorReading(kind: .gpu, celsius: 46), SensorReading(kind: .battery, celsius: 31),
                           SensorReading(kind: .wireless, celsius: 39), SensorReading(kind: .ssd, celsius: 37),
                           SensorReading(kind: .charger, celsius: 39)]

extension SerialTests {
    @MainActor
    struct SocSensorsModelTests {
        init() { L10nStore.shared.language = .en }

        @Test func fullReadingsGiveTwoLists() {
            let lists = SocSensorsModel.lists(allReadings)
            #expect(lists.count == 2)
            #expect(lists[0].map(\.name) == ["Efficiency cores", "Performance cores", "GPU"])
            #expect(lists[1].map(\.name) == ["Battery", "Wi-Fi and Bluetooth", "SSD", "Charger"])
            #expect(lists[0].map(\.valueText) == ["47 °C", "58 °C", "46 °C"])
            #expect(lists[1].map(\.valueText) == ["31 °C", "39 °C", "37 °C", "39 °C"])
        }

        @Test func withoutBatteryAndCharger() {
            let lists = SocSensorsModel.lists(allReadings.filter { $0.kind != .battery && $0.kind != .charger })
            #expect(lists.count == 2)
            #expect(lists[1].map(\.name) == ["Wi-Fi and Bluetooth", "SSD"])
        }

        @Test func emptyListsAreDropped() {
            #expect(SocSensorsModel.lists(allReadings.filter { SocSensorsModel.chipKinds.contains($0.kind) }).count == 1)
            #expect(SocSensorsModel.lists(allReadings.filter { !SocSensorsModel.chipKinds.contains($0.kind) }).count == 1)
            #expect(SocSensorsModel.lists([]).isEmpty)
        }

        @Test func nilValuesShowIdleOrDash() {
            let readings = allReadings.map { $0.kind == .gpu || $0.kind == .battery ? SensorReading(kind: $0.kind, celsius: nil) : $0 }
            let lists = SocSensorsModel.lists(readings)
            #expect(lists[0].map(\.valueText) == ["47 °C", "58 °C", "Idle"])
            #expect(lists[0][2].noValueHelp == L.socSensorIdleHelp)
            #expect(lists[1].map(\.valueText) == ["—", "39 °C", "37 °C", "39 °C"])
            #expect(lists[1][0].noValueHelp == L.socSensorNoReading)
            #expect(lists[0][0].noValueHelp == nil)
            L10nStore.shared.language = .ru
            defer { L10nStore.shared.language = .en }
            #expect(SocSensorsModel.row(SensorReading(kind: .gpu, celsius: nil)).valueText == "В покое")
        }

        @Test func stringsExistInBothLanguagesWithoutSemicolons() {
            defer { L10nStore.shared.language = .en }
            for lang in [AppLanguage.en, .ru] {
                L10nStore.shared.language = lang
                let strings = [L.socSensorsTitle, L.socSensorsCaption, L.socSensorsUnavailable, L.socSensorECores,
                               L.socSensorPCores, L.socSensorWireless, L.socSensorSSD, L.socSensorCharger,
                               L.socSensorIdle, L.socSensorIdleHelp, L.socSensorNoReading]
                for s in strings {
                    #expect(!s.isEmpty)
                    #expect(!s.contains(";"))
                }
            }
        }
    }
}
