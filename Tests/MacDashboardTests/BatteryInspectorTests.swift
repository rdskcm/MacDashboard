// Tests/MacDashboardTests/BatteryInspectorTests.swift
// Port of Checks/main.swift lines 1016-1489 (CHECKS-SWIFT-TESTING). BatteryInspector parsing: ioreg fixtures, macOS 27 layout, passport fields.
import Foundation
import Testing
@testable import MacDashboard

// Trimmed sample fixture (on battery, no adapter connected).
private let batteryOnBatteryFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
\t<dict>
\t\t<key>AdapterDetails</key>
\t\t<dict>
\t\t\t<key>FamilyCode</key>
\t\t\t<integer>0</integer>
\t\t</dict>
\t\t<key>Amperage</key>
\t\t<integer>-587</integer>
\t\t<key>AppleRawCurrentCapacity</key>
\t\t<integer>2930</integer>
\t\t<key>AppleRawMaxCapacity</key>
\t\t<integer>3977</integer>
\t\t<key>AtCriticalLevel</key>
\t\t<false/>
\t\t<key>AvgTimeToEmpty</key>
\t\t<integer>296</integer>
\t\t<key>AvgTimeToFull</key>
\t\t<integer>65535</integer>
\t\t<key>BatteryData</key>
\t\t<dict>
\t\t\t<key>CellVoltage</key>
\t\t\t<array>
\t\t\t\t<integer>4032</integer>
\t\t\t\t<integer>4032</integer>
\t\t\t\t<integer>4030</integer>
\t\t\t</array>
\t\t\t<key>LifetimeData</key>
\t\t\t<dict>
\t\t\t\t<key>AverageTemperature</key>
\t\t\t\t<integer>259</integer>
\t\t\t\t<key>MaximumChargeCurrent</key>
\t\t\t\t<integer>5345</integer>
\t\t\t\t<key>MaximumDischargeCurrent</key>
\t\t\t\t<integer>-3001</integer>
\t\t\t\t<key>MaximumPackVoltage</key>
\t\t\t\t<integer>13321</integer>
\t\t\t\t<key>MaximumTemperature</key>
\t\t\t\t<integer>44</integer>
\t\t\t\t<key>MinimumPackVoltage</key>
\t\t\t\t<integer>9335</integer>
\t\t\t\t<key>MinimumTemperature</key>
\t\t\t\t<integer>10</integer>
\t\t\t\t<key>TotalOperatingTime</key>
\t\t\t\t<integer>20219</integer>
\t\t\t</dict>
\t\t</dict>
\t\t<key>ChargerData</key>
\t\t<dict>
\t\t\t<key>ChargerID</key>
\t\t\t<integer>14</integer>
\t\t\t<key>ChargingCurrent</key>
\t\t\t<integer>0</integer>
\t\t\t<key>ChargingVoltage</key>
\t\t\t<integer>4406</integer>
\t\t\t<key>NotChargingReason</key>
\t\t\t<integer>128</integer>
\t\t\t<key>SlowChargingReason</key>
\t\t\t<integer>0</integer>
\t\t\t<key>TimeChargingThermallyLimited</key>
\t\t\t<integer>0</integer>
\t\t\t<key>VacVoltageLimit</key>
\t\t\t<integer>4375</integer>
\t\t</dict>
\t\t<key>CurrentCapacity</key>
\t\t<integer>78</integer>
\t\t<key>CycleCount</key>
\t\t<integer>338</integer>
\t\t<key>DesignCapacity</key>
\t\t<integer>4563</integer>
\t\t<key>DesignCycleCount9C</key>
\t\t<integer>1000</integer>
\t\t<key>DeviceName</key>
\t\t<string>bq40z651</string>
\t\t<key>ExternalConnected</key>
\t\t<false/>
\t\t<key>FullyCharged</key>
\t\t<false/>
\t\t<key>InstantAmperage</key>
\t\t<integer>-587</integer>
\t\t<key>IsCharging</key>
\t\t<false/>
\t\t<key>MaxCapacity</key>
\t\t<integer>100</integer>
\t\t<key>NominalChargeCapacity</key>
\t\t<integer>4104</integer>
\t\t<key>Serial</key>
\t\t<string>X0X00000ABC00XXXX</string>
\t\t<key>Temperature</key>
\t\t<integer>3044</integer>
\t\t<key>TimeRemaining</key>
\t\t<integer>296</integer>
\t\t<key>Voltage</key>
\t\t<integer>12093</integer>
\t</dict>
</array>
</plist>
"""

// Trimmed sample fixture (charging, third-party 45W USB-PD adapter).
private let batteryChargingFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
\t<dict>
\t\t<key>AdapterDetails</key>
\t\t<dict>
\t\t\t<key>AdapterID</key>
\t\t\t<integer>0</integer>
\t\t\t<key>AdapterPowerTier</key>
\t\t\t<integer>2</integer>
\t\t\t<key>AdapterVoltage</key>
\t\t\t<integer>20000</integer>
\t\t\t<key>Current</key>
\t\t\t<integer>2250</integer>
\t\t\t<key>FamilyCode</key>
\t\t\t<integer>-536854518</integer>
\t\t\t<key>IsWireless</key>
\t\t\t<false/>
\t\t\t<key>PMUConfiguration</key>
\t\t\t<integer>2250</integer>
\t\t\t<key>UsbHvcHvcIndex</key>
\t\t\t<integer>3</integer>
\t\t\t<key>UsbHvcMenu</key>
\t\t\t<array>
\t\t\t\t<dict>
\t\t\t\t\t<key>Index</key>
\t\t\t\t\t<integer>0</integer>
\t\t\t\t\t<key>MaxCurrent</key>
\t\t\t\t\t<integer>3000</integer>
\t\t\t\t\t<key>MaxVoltage</key>
\t\t\t\t\t<integer>5000</integer>
\t\t\t\t</dict>
\t\t\t\t<dict>
\t\t\t\t\t<key>Index</key>
\t\t\t\t\t<integer>1</integer>
\t\t\t\t\t<key>MaxCurrent</key>
\t\t\t\t\t<integer>3000</integer>
\t\t\t\t\t<key>MaxVoltage</key>
\t\t\t\t\t<integer>9000</integer>
\t\t\t\t</dict>
\t\t\t\t<dict>
\t\t\t\t\t<key>Index</key>
\t\t\t\t\t<integer>2</integer>
\t\t\t\t\t<key>MaxCurrent</key>
\t\t\t\t\t<integer>3000</integer>
\t\t\t\t\t<key>MaxVoltage</key>
\t\t\t\t\t<integer>15000</integer>
\t\t\t\t</dict>
\t\t\t\t<dict>
\t\t\t\t\t<key>Index</key>
\t\t\t\t\t<integer>3</integer>
\t\t\t\t\t<key>MaxCurrent</key>
\t\t\t\t\t<integer>2250</integer>
\t\t\t\t\t<key>MaxVoltage</key>
\t\t\t\t\t<integer>20000</integer>
\t\t\t\t</dict>
\t\t\t</array>
\t\t\t<key>Watts</key>
\t\t\t<integer>45</integer>
\t\t</dict>
\t\t<key>Amperage</key>
\t\t<integer>-479</integer>
\t\t<key>AppleRawCurrentCapacity</key>
\t\t<integer>2889</integer>
\t\t<key>AppleRawMaxCapacity</key>
\t\t<integer>3984</integer>
\t\t<key>AtCriticalLevel</key>
\t\t<false/>
\t\t<key>AvgTimeToEmpty</key>
\t\t<integer>352</integer>
\t\t<key>AvgTimeToFull</key>
\t\t<integer>65535</integer>
\t\t<key>BatteryData</key>
\t\t<dict>
\t\t\t<key>CellVoltage</key>
\t\t\t<array>
\t\t\t\t<integer>4027</integer>
\t\t\t\t<integer>4024</integer>
\t\t\t\t<integer>4020</integer>
\t\t\t</array>
\t\t\t<key>LifetimeData</key>
\t\t\t<dict>
\t\t\t\t<key>AverageTemperature</key>
\t\t\t\t<integer>259</integer>
\t\t\t\t<key>MaximumChargeCurrent</key>
\t\t\t\t<integer>5345</integer>
\t\t\t\t<key>MaximumDischargeCurrent</key>
\t\t\t\t<integer>-3001</integer>
\t\t\t\t<key>MaximumPackVoltage</key>
\t\t\t\t<integer>13321</integer>
\t\t\t\t<key>MaximumTemperature</key>
\t\t\t\t<integer>44</integer>
\t\t\t\t<key>MinimumPackVoltage</key>
\t\t\t\t<integer>9335</integer>
\t\t\t\t<key>MinimumTemperature</key>
\t\t\t\t<integer>10</integer>
\t\t\t\t<key>TotalOperatingTime</key>
\t\t\t\t<integer>20219</integer>
\t\t\t</dict>
\t\t</dict>
\t\t<key>ChargerData</key>
\t\t<dict>
\t\t\t<key>ChargerID</key>
\t\t\t<integer>14</integer>
\t\t\t<key>ChargingCurrent</key>
\t\t\t<integer>570</integer>
\t\t\t<key>ChargingVoltage</key>
\t\t\t<integer>4027</integer>
\t\t\t<key>NotChargingReason</key>
\t\t\t<integer>0</integer>
\t\t\t<key>SlowChargingReason</key>
\t\t\t<integer>0</integer>
\t\t\t<key>TimeChargingThermallyLimited</key>
\t\t\t<integer>0</integer>
\t\t\t<key>VacVoltageLimit</key>
\t\t\t<integer>4375</integer>
\t\t</dict>
\t\t<key>CurrentCapacity</key>
\t\t<integer>76</integer>
\t\t<key>CycleCount</key>
\t\t<integer>338</integer>
\t\t<key>DesignCapacity</key>
\t\t<integer>4563</integer>
\t\t<key>DesignCycleCount9C</key>
\t\t<integer>1000</integer>
\t\t<key>DeviceName</key>
\t\t<string>bq40z651</string>
\t\t<key>ExternalConnected</key>
\t\t<true/>
\t\t<key>FullyCharged</key>
\t\t<false/>
\t\t<key>InstantAmperage</key>
\t\t<integer>-479</integer>
\t\t<key>IsCharging</key>
\t\t<false/>
\t\t<key>MaxCapacity</key>
\t\t<integer>100</integer>
\t\t<key>NominalChargeCapacity</key>
\t\t<integer>4111</integer>
\t\t<key>Serial</key>
\t\t<string>X0X00000ABC00XXXX</string>
\t\t<key>Temperature</key>
\t\t<integer>3033</integer>
\t\t<key>TimeRemaining</key>
\t\t<integer>65535</integer>
\t\t<key>Voltage</key>
\t\t<integer>12071</integer>
\t</dict>
</array>
</plist>
"""

// Trimmed from a real `ioreg -r -c AppleSmartBattery -a -l` capture on macOS 27
// (charging, 45W adapter). Serial is a placeholder; binary blobs are synthetic.
// On macOS 27 the top-level entry has no Temperature / AppleRawMaxCapacity /
// AppleRawCurrentCapacity / DesignCapacity, its BatteryData has no CellVoltage or
// LifetimeData, and its ChargerData has no ChargingCurrent / ChargingVoltage.
private func battery27Bank(_ bankID: Int, _ cellMV: Int?) -> [String: Any] {
    var data: [String: Any] = ["LifetimeData": ["TimeAtHighSoc": Data([0, 0, 0, 0])]]
    if let cellMV { data["CellVoltage"] = cellMV }
    return ["IOObjectClass": "AppleSmartBatteryBank", "BankID": bankID, "BatteryData": data]
}

private func battery27Fixture(banks: [[String: Any]]) -> [String: Any] {
    let pack: [String: Any] = [
        "IOObjectClass": "AppleSmartBatteryPack",
        "BatteryData": [
            "AppleRawCurrentCapacity": 2106,
            "AppleRawMaxCapacity": 3899,
            "DesignCapacity": 4563,
            "Temperature": 2789,
            "VirtualTemperature": 2789,
            "LifetimeData": [
                "AverageTemperature": 259,
                "CycleCountLastQmax": 364,
                "MaximumChargeCurrent": 5345,
                "MaximumDischargeCurrent": -3001,
                "MaximumPackVoltage": 13321,
                "MaximumTemperature": 44,
                "MinimumPackVoltage": 9335,
                "MinimumTemperature": 10,
                "Raw": Data([0, 0, 0, 0, 0, 0, 0, 0]),
                "TotalOperatingTime": 21969,
                "UpdateTime": 1790591672
            ] as [String: Any]
        ] as [String: Any],
        "IORegistryEntryChildren": banks
    ]
    let chargerChild: [String: Any] = [
        "IOObjectClass": "AppleChargerData",
        "ChargerData": ["ChargingCurrent": 4055, "ChargingVoltage": 4216, "NotChargingReason": 0,
                        "SlowChargingReason": 0, "TimeChargingThermallyLimited": 0]
    ]
    return [
        "IOObjectClass": "AppleSmartBattery",
        "Amperage": 2889,
        "Voltage": 12294,
        "CurrentCapacity": 55,
        "CycleCount": 364,
        "DesignCycleCount9C": 1000,
        "ExternalConnected": true,
        "IsCharging": true,
        "FullyCharged": false,
        "AvgTimeToEmpty": 65535,
        "AvgTimeToFull": 84,
        "Serial": "X0X00000ABC00XXXX",
        "BatteryData": ["CurrentCapacity": 55, "DesignCapacity": 4563, "FullChargeCapacity": 3899,
                        "RemainingCapacity": 2106],
        "ChargerData": ["IsCharging": 1, "NotChargingReason": 0, "SlowChargingReason": 0,
                        "TimeChargingThermallyLimited": 0],
        "IORegistryEntryChildren": [pack, chargerChild]
    ]
}

private func battery27Plist(_ entry: [String: Any]) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: [entry], format: .xml, options: 0)
}

extension SerialTests {
    struct BatteryInspectorTests {
        @Test func ioregBattery() async {
            // =====================================================================
            // MARK: - BatteryInspector (ioreg AppleSmartBattery)
            // =====================================================================
            do {
                let d1 = BatteryInspector.parse(Data(batteryOnBatteryFixture.utf8))
                #expect(d1 != nil, "BatteryInspector: on-battery fixture parses")
                let d = d1!
                #expect(d.amperageMA == -587 && d.voltageMV == 12093, "BatteryInspector on-battery: amperageMA/voltageMV signed values")
                #expect(d.powerW.map { abs($0 - (-7.099)) < 0.01 } ?? false, "BatteryInspector on-battery: powerW ≈ -7.099")
                #expect(d.temperatureC == 30.44, "BatteryInspector on-battery: temperatureC == 30.44")
                #expect(d.percent == 78 && d.currentCapacityMAh == 2930 && d.maxCapacityMAh == 3977
                      && d.designCapacityMAh == 4563 && d.healthPercent == 87,
                      "BatteryInspector on-battery: capacity/health fields")
                #expect(d.cycleCount == 338 && d.designCycleCount == 1000, "BatteryInspector on-battery: cycle counts")
                #expect(d.timeToEmptyMin == 296 && d.timeToFullMin == nil, "BatteryInspector on-battery: timeToEmpty/timeToFull (65535 → nil)")
                #expect(d.externalConnected == false && d.adapter == nil, "BatteryInspector on-battery: no external adapter")
                #expect(d.cellVoltagesMV == [4032, 4032, 4030], "BatteryInspector on-battery: cellVoltagesMV")
                #expect(d.lifetime?.maxTemperatureC == 44 && d.lifetime?.avgTemperatureC == 25.9
                      && d.lifetime?.maxDischargeCurrentMA == -3001 && d.lifetime?.totalOperatingTimeH == 20219,
                      "BatteryInspector on-battery: lifetime fields")
                #expect(d.charger?.notChargingReason == 128, "BatteryInspector on-battery: charger.notChargingReason")
            }

            do {
                let d = BatteryInspector.parse(Data(batteryChargingFixture.utf8))!
                #expect(d.externalConnected == true && d.adapter != nil, "BatteryInspector charging: externalConnected/adapter present")
                #expect(d.adapter?.watts == 45 && d.adapter?.voltageMV == 20000 && d.adapter?.currentMA == 2250
                      && d.adapter?.isWireless == false,
                      "BatteryInspector charging: adapter watts/voltage/current/isWireless")
                #expect(d.adapter?.pdProfiles.count == 4 && d.adapter?.selectedProfileIndex == 3,
                      "BatteryInspector charging: pdProfiles count + selectedProfileIndex")
                if let profile3 = d.adapter?.pdProfiles.first(where: { $0.index == 3 }) {
                    #expect(profile3.maxVoltageMV == 20000 && profile3.maxCurrentMA == 2250,
                          "BatteryInspector charging: profile index 3 maxVoltage/maxCurrent")
                } else {
                    Issue.record("BatteryInspector charging: expected a pdProfile with index 3")
                }
                #expect(d.adapter?.name == nil, "BatteryInspector charging: adapter.name absent on this adapter")
                #expect(d.charger?.chargingCurrentMA == 570 && d.charger?.notChargingReason == 0,
                      "BatteryInspector charging: charger.chargingCurrentMA/notChargingReason")
            }

            do {
                #expect(BatteryInspector.parse(Data("not a plist".utf8)) == nil, "BatteryInspector: garbage input → nil")
            }

            do {
                let collected = hasBattery ? await BatteryInspector.collect() : nil
                #expect(!hasBattery || collected != nil,
                      "smoke BatteryInspector: collect() != nil (or no battery on this machine)")
            }
        }

        @Test func macOS27Layout() async {
            // =====================================================================
            // MARK: - BatteryInspector (macOS 27 layout: keys on child entries, V27-BATTERY)
            // =====================================================================
            do {
                let banks = [battery27Bank(0, 4093), battery27Bank(1, 4097), battery27Bank(2, 4103)]
                let d27 = BatteryInspector.parse(battery27Plist(battery27Fixture(banks: banks)))
                #expect(d27 != nil, "BatteryInspector macOS 27: fixture parses")
                let d = d27!
                #expect(d.voltageMV == 12294 && d.amperageMA == 2889 && d.percent == 55 && d.cycleCount == 364 && d.isCharging,
                      "BatteryInspector macOS 27: top-level fields unchanged")
                #expect(d.temperatureC == 27.89, "BatteryInspector macOS 27: temperatureC from Pack == 27.89")
                #expect(d.maxCapacityMAh == 3899 && d.designCapacityMAh == 4563 && d.currentCapacityMAh == 2106
                      && d.healthPercent == 85,
                      "BatteryInspector macOS 27: capacity/health from Pack")
                #expect(d.cellVoltagesMV == [4093, 4097, 4103], "BatteryInspector macOS 27: cellVoltagesMV from Banks")
                #expect(d.lifetime == BatteryLifetimeInfo(maxTemperatureC: 44, minTemperatureC: 10, avgTemperatureC: 25.9,
                                                        maxChargeCurrentMA: 5345, maxDischargeCurrentMA: -3001,
                                                        maxPackVoltageMV: 13321, minPackVoltageMV: 9335,
                                                        totalOperatingTimeH: 21969),
                      "BatteryInspector macOS 27: lifetime from Pack")
                #expect(d.charger?.chargingCurrentMA == 4055 && d.charger?.chargingVoltageMV == 4216
                      && d.charger?.notChargingReason == 0,
                      "BatteryInspector macOS 27: charger from AppleChargerData child")

                // Lookup order: a pre-27 top-level value wins over the child value.
                var both = battery27Fixture(banks: banks)
                both["Temperature"] = 3044
                both["AppleRawMaxCapacity"] = 3977
                both["ChargerData"] = ["ChargingCurrent": 570, "NotChargingReason": 128]
                let dBoth = BatteryInspector.parse(battery27Plist(both))
                #expect(dBoth?.temperatureC == 30.44 && dBoth?.maxCapacityMAh == 3977 && dBoth?.designCapacityMAh == 4563,
                      "BatteryInspector macOS 27: top-level value wins over Pack, missing top-level key falls through")
                #expect(dBoth?.charger?.chargingCurrentMA == 570 && dBoth?.charger?.notChargingReason == 128
                      && dBoth?.charger?.chargingVoltageMV == 4216,
                      "BatteryInspector macOS 27: ChargerData per key — top-level wins, missing key from child")

                // All-or-nothing cells: one bank without CellVoltage ⇒ [].
                let partial = [battery27Bank(0, 4093), battery27Bank(1, nil), battery27Bank(2, 4103)]
                #expect(BatteryInspector.parse(battery27Plist(battery27Fixture(banks: partial))).map { $0.cellVoltagesMV == [] } ?? false,
                      "BatteryInspector macOS 27: a bank without CellVoltage ⇒ cellVoltagesMV == []")
            }

            do {
                // Live: on a Mac with a battery, the real ioreg output must yield the fields macOS 27
                // moved into child entries. Skipped on battery-less machines (CI runners).
                let live = hasBattery ? await BatteryInspector.collect() : nil
                #expect(!hasBattery || (live?.maxCapacityMAh != nil && live?.designCapacityMAh != nil
                                      && live?.temperatureC != nil && live?.lifetime != nil
                                      && live?.cellVoltagesMV.isEmpty == false),
                      "smoke BatteryInspector: live collect() has capacity/temperature/lifetime/cells (or no battery on this machine)")
            }
        }

        @Test func batteryPassport() async {
            // =====================================================================
            // MARK: - BatteryInspector (battery passport: serial / manufacturer / mfg date)
            // =====================================================================

            do {
                var mfgBlobBytes: [UInt8] = [0,0,0,0, 0x0b,0,1,0, 0xf9,0x14,0,0, 4]
                mfgBlobBytes += Array("2213".utf8)
                mfgBlobBytes += [3]
                mfgBlobBytes += Array("00B".utf8)
                mfgBlobBytes += [3]
                mfgBlobBytes += Array("ATL".utf8)
                mfgBlobBytes += [0, 0x21, 0,0,0,0,0]
                let mfgBlob = Data(mfgBlobBytes)
                let fixture: [[String: Any]] = [["Serial": "X0X00000ABC00XXXX",
                                                 "ManufacturerData": mfgBlob,
                                                 "CurrentCapacity": 90, "Voltage": 12628]]
                let plist = try! PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0)
                let d = BatteryInspector.parse(plist)

                #expect(d?.serial == "X0X00000ABC00XXXX", "BatteryInspector passport: serial")
                #expect(d?.manufacturerCode == "ATL", "BatteryInspector passport: manufacturerCode == ATL")
                #expect(d?.mfgCode == "2213" && d?.mfgYear == 2022 && d?.mfgWeek == 13,
                      "BatteryInspector passport: mfgCode/mfgYear/mfgWeek from YYWW code")
                #expect(d?.lowPowerMode == nil, "BatteryInspector passport: parse() never sets lowPowerMode")

                let garbage = BatteryInspector.decodeManufacturerData(Data([0,0,0]))
                #expect(garbage.mfgCode == nil && garbage.manufacturerCode == nil,
                      "BatteryInspector passport: garbage blob decodes to (nil, nil)")

                var invalidWeekBlobBytes: [UInt8] = [0,0,0,0, 0x0b,0,1,0, 0xf9,0x14,0,0, 4]
                invalidWeekBlobBytes += Array("2299".utf8)
                invalidWeekBlobBytes += [3]
                invalidWeekBlobBytes += Array("00B".utf8)
                invalidWeekBlobBytes += [3]
                invalidWeekBlobBytes += Array("ATL".utf8)
                invalidWeekBlobBytes += [0, 0x21, 0,0,0,0,0]
                let invalidWeekBlob = Data(invalidWeekBlobBytes)
                let fixture2: [[String: Any]] = [["Serial": "X", "ManufacturerData": invalidWeekBlob,
                                                  "CurrentCapacity": 90, "Voltage": 12628]]
                let plist2 = try! PropertyListSerialization.data(fromPropertyList: fixture2, format: .xml, options: 0)
                let d2 = BatteryInspector.parse(plist2)
                #expect(d2?.mfgCode == "2299" && d2?.mfgYear == nil && d2?.mfgWeek == nil,
                      "BatteryInspector passport: week 99 rejected, mfgCode kept but mfgYear/mfgWeek nil")
            }
        }
    }
}
