// Engine/BatteryInspector.swift
// Parses `ioreg -rc AppleSmartBattery -a` (the AppleSmartBattery IOKit service, as
// XML plist) into a typed BatteryDetail. Foundation only — this file is also
// compiled into the Checks target.
import Foundation

/// One entry of `AdapterDetails.UsbHvcMenu`: a USB-PD profile the connected
/// adapter advertises.
struct PDProfile: Equatable {
    var index: Int
    var maxVoltageMV: Int
    var maxCurrentMA: Int
}

struct BatteryAdapterInfo: Equatable {
    var watts: Int?
    var voltageMV: Int?                       // AdapterVoltage
    var currentMA: Int?                       // Current
    var name: String?
    var manufacturer: String?
    var adapterDescription: String?           // "Description" key
    var isWireless: Bool                      // IsWireless, default false
    var pdProfiles: [PDProfile]                // UsbHvcMenu, sorted by index; [] if absent
    var selectedProfileIndex: Int?             // UsbHvcHvcIndex
}

struct BatteryChargerInfo: Equatable {
    var chargingVoltageMV: Int?
    var chargingCurrentMA: Int?
    var notChargingReason: Int?
    var slowChargingReason: Int?
    var timeChargingThermallyLimited: Int?
}

struct BatteryLifetimeInfo: Equatable {
    var maxTemperatureC: Int?
    var minTemperatureC: Int?
    var avgTemperatureC: Double?               // AverageTemperature / 10
    var maxChargeCurrentMA: Int?
    var maxDischargeCurrentMA: Int?
    var maxPackVoltageMV: Int?
    var minPackVoltageMV: Int?
    var totalOperatingTimeH: Int?              // TotalOperatingTime (unit undocumented; treated as hours, best-effort)
}

struct BatteryDetail: Equatable {
    var percent: Int?                          // CurrentCapacity
    var voltageMV: Int?
    var amperageMA: Int?                       // signed; negative = discharging
    var powerW: Double?                        // computed: voltage*amperage/1e6, nil if either missing
    var temperatureC: Double?                  // Temperature / 100
    var cellVoltagesMV: [Int]                  // BatteryData.CellVoltage, [] if absent
    var externalConnected: Bool
    var isCharging: Bool
    var fullyCharged: Bool
    var timeToEmptyMin: Int?                   // AvgTimeToEmpty, nil if absent or 65535
    var timeToFullMin: Int?                    // AvgTimeToFull, nil if absent or 65535
    var currentCapacityMAh: Int?               // AppleRawCurrentCapacity
    var maxCapacityMAh: Int?                   // AppleRawMaxCapacity
    var designCapacityMAh: Int?                // DesignCapacity
    var cycleCount: Int?
    var designCycleCount: Int?                 // DesignCycleCount9C
    var healthPercent: Int?                    // computed: round(maxCapacityMAh/designCapacityMAh*100)
    var adapter: BatteryAdapterInfo?           // nil unless AdapterDetails contains "Watts"
    var charger: BatteryChargerInfo?           // nil if ChargerData dict absent
    var lifetime: BatteryLifetimeInfo?         // nil if LifetimeData dict absent
    var serial: String? = nil               // top-level "Serial"
    var manufacturerCode: String? = nil     // decoded from ManufacturerData, e.g. "ATL"
    var mfgYear: Int? = nil                 // e.g. 2022 (from YYWW code)
    var mfgWeek: Int? = nil                 // 1...53
    var mfgCode: String? = nil              // raw 4-digit code, e.g. "2213"
    var lowPowerMode: Bool? = nil           // set by collect() only, never by parse()
}

enum BatteryInspector {

    /// `AvgTimeToEmpty`/`AvgTimeToFull`/`TimeRemaining` use 65535 as the sentinel
    /// for "unknown" (not a real 1092-hour estimate).
    private static let unknownTimeMinutes = 65535

    /// Pure parser: plist data from `ioreg -rc AppleSmartBattery -a` → BatteryDetail.
    /// Returns nil if the data isn't a plist array whose first element is a dict.
    static func parse(_ plistData: Data) -> BatteryDetail? {
        guard let raw = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let array = raw as? [[String: Any]],
              let dict = array.first
        else { return nil }

        let voltageMV = dict["Voltage"] as? Int
        let amperageMA = dict["Amperage"] as? Int
        let powerW: Double?
        if let v = voltageMV, let a = amperageMA {
            powerW = Double(v) * Double(a) / 1_000_000
        } else {
            powerW = nil
        }

        let temperatureC = (dict["Temperature"] as? Int).map { Double($0) / 100 }

        let batteryData = dict["BatteryData"] as? [String: Any]
        let cellVoltagesMV = (batteryData?["CellVoltage"] as? [Int]) ?? []

        let maxCapacityMAh = dict["AppleRawMaxCapacity"] as? Int
        let designCapacityMAh = dict["DesignCapacity"] as? Int
        let healthPercent: Int?
        if let maxCap = maxCapacityMAh, let designCap = designCapacityMAh, designCap != 0 {
            healthPercent = Int((Double(maxCap) / Double(designCap) * 100).rounded())
        } else {
            healthPercent = nil
        }

        var detail = BatteryDetail(
            percent: dict["CurrentCapacity"] as? Int,
            voltageMV: voltageMV,
            amperageMA: amperageMA,
            powerW: powerW,
            temperatureC: temperatureC,
            cellVoltagesMV: cellVoltagesMV,
            externalConnected: dict["ExternalConnected"] as? Bool ?? false,
            isCharging: dict["IsCharging"] as? Bool ?? false,
            fullyCharged: dict["FullyCharged"] as? Bool ?? false,
            timeToEmptyMin: unknownTimeFiltered(dict["AvgTimeToEmpty"] as? Int),
            timeToFullMin: unknownTimeFiltered(dict["AvgTimeToFull"] as? Int),
            currentCapacityMAh: dict["AppleRawCurrentCapacity"] as? Int,
            maxCapacityMAh: maxCapacityMAh,
            designCapacityMAh: designCapacityMAh,
            cycleCount: dict["CycleCount"] as? Int,
            designCycleCount: dict["DesignCycleCount9C"] as? Int,
            healthPercent: healthPercent,
            adapter: adapterInfo(from: dict["AdapterDetails"] as? [String: Any]),
            charger: chargerInfo(from: dict["ChargerData"] as? [String: Any]),
            lifetime: lifetimeInfo(from: batteryData?["LifetimeData"] as? [String: Any])
        )

        detail.serial = dict["Serial"] as? String
        if let md = dict["ManufacturerData"] as? Data {
            let (mfgCode, manufacturerCode) = decodeManufacturerData(md)
            detail.mfgCode = mfgCode
            detail.manufacturerCode = manufacturerCode
            if let mfgCode, let yy = Int(mfgCode.prefix(2)), let week = Int(mfgCode.suffix(2)) {
                if (1...53).contains(week) {
                    detail.mfgYear = 2000 + yy
                    detail.mfgWeek = week
                }
            }
        }

        return detail
    }

    /// App path: runs ioreg and parses. Returns nil if battery service missing.
    static func collect() -> BatteryDetail? {
        guard let out = CommandRunner.run("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-a"], timeout: 5) else {
            return nil
        }
        guard var detail = parse(Data(out.utf8)) else { return nil }
        detail.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        return detail
    }

    /// Decodes the length-prefixed ASCII segments of the 32-byte ManufacturerData blob
    /// (12-byte header, then [len][bytes]... while len ∈ 1...16 and bytes are printable
    /// ASCII 0x20...0x7E). Returns (yyww date code, manufacturer code); each nil when
    /// not confidently decodable — never garbage.
    static func decodeManufacturerData(_ data: Data) -> (mfgCode: String?, manufacturerCode: String?) {
        guard data.count > 13 else { return (nil, nil) }
        let bytes = [UInt8](data)
        var segments: [String] = []
        var i = 12
        while i < bytes.count {
            let len = Int(bytes[i])
            if len == 0 || len > 16 || i + 1 + len > bytes.count { break }
            let slice = bytes[(i + 1)..<(i + 1 + len)]
            guard slice.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else { break }
            segments.append(String(decoding: slice, as: UTF8.self))
            i += 1 + len
        }
        let mfgCode = segments.first { $0.range(of: "^[0-9]{4}$", options: .regularExpression) != nil }
        let manufacturerCode = segments.last {
            $0.count >= 2 && $0.allSatisfy { $0.isASCII && $0.isLetter }
        }
        return (mfgCode, manufacturerCode)
    }

    private static func unknownTimeFiltered(_ minutes: Int?) -> Int? {
        guard let minutes, minutes != unknownTimeMinutes else { return nil }
        return minutes
    }

    /// Non-nil only when `Watts` is present — a bare `{FamilyCode: 0}` (on-battery)
    /// means "no adapter connected".
    private static func adapterInfo(from dict: [String: Any]?) -> BatteryAdapterInfo? {
        guard let dict, let watts = dict["Watts"] as? Int else { return nil }
        let pdProfiles = ((dict["UsbHvcMenu"] as? [[String: Any]]) ?? []).compactMap { entry -> PDProfile? in
            guard let index = entry["Index"] as? Int,
                  let maxVoltageMV = entry["MaxVoltage"] as? Int,
                  let maxCurrentMA = entry["MaxCurrent"] as? Int
            else { return nil }
            return PDProfile(index: index, maxVoltageMV: maxVoltageMV, maxCurrentMA: maxCurrentMA)
        }.sorted { $0.index < $1.index }

        return BatteryAdapterInfo(
            watts: watts,
            voltageMV: dict["AdapterVoltage"] as? Int,
            currentMA: dict["Current"] as? Int,
            name: dict["Name"] as? String,
            manufacturer: dict["Manufacturer"] as? String,
            adapterDescription: dict["Description"] as? String,
            isWireless: dict["IsWireless"] as? Bool ?? false,
            pdProfiles: pdProfiles,
            selectedProfileIndex: dict["UsbHvcHvcIndex"] as? Int
        )
    }

    private static func chargerInfo(from dict: [String: Any]?) -> BatteryChargerInfo? {
        guard let dict else { return nil }
        return BatteryChargerInfo(
            chargingVoltageMV: dict["ChargingVoltage"] as? Int,
            chargingCurrentMA: dict["ChargingCurrent"] as? Int,
            notChargingReason: dict["NotChargingReason"] as? Int,
            slowChargingReason: dict["SlowChargingReason"] as? Int,
            timeChargingThermallyLimited: dict["TimeChargingThermallyLimited"] as? Int
        )
    }

    private static func lifetimeInfo(from dict: [String: Any]?) -> BatteryLifetimeInfo? {
        guard let dict else { return nil }
        return BatteryLifetimeInfo(
            maxTemperatureC: dict["MaximumTemperature"] as? Int,
            minTemperatureC: dict["MinimumTemperature"] as? Int,
            avgTemperatureC: (dict["AverageTemperature"] as? Int).map { Double($0) / 10 },
            maxChargeCurrentMA: dict["MaximumChargeCurrent"] as? Int,
            maxDischargeCurrentMA: dict["MaximumDischargeCurrent"] as? Int,
            maxPackVoltageMV: dict["MaximumPackVoltage"] as? Int,
            minPackVoltageMV: dict["MinimumPackVoltage"] as? Int,
            totalOperatingTimeH: dict["TotalOperatingTime"] as? Int
        )
    }
}
