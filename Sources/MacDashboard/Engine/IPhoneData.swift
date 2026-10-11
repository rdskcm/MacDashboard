// Engine/IPhoneData.swift
// IPHONE-MODULE: the pure half of the iPhone module — device key hashing, masking,
// crash-log header classification, AFC time conversion, battery-history merge, the
// relay request builder, registry value extraction, the colour lookup and the
// remembered-device store. Foundation + CryptoKit only (no SwiftUI), so the file is
// symlinked into the Checks target. Everything is internal, not private: Checks sit in
// a different file (checks-helper-visibility).
//
// R13: nothing here stores a serial, IMEI, part id or UDID. `IPhoneDeviceRecord` is the
// only persisted device data, and it is keyed by `deviceKey(udid:)`.

import CryptoKit
import Foundation

/// Crash-log categories in DISPLAY order (real app crashes first).
/// Identity and parts fields, in display order (non-secret first, then the masked ones).
enum IdentityLabel: String, CaseIterable {
    case marketingName, modelNumber, regulatoryModel, hardwareModel, ios, storage, colorCode
    case serial, logicBoard, imei, imei2, battery, displayPanel, displayRawPanel, coverGlass
    case backGlass, nova, ambientLight
    case backCamera, backSuperWide, backTele, frontCamera, frontIR, faceIDProjector

    var isSecret: Bool {
        switch self {
        case .marketingName, .modelNumber, .regulatoryModel, .hardwareModel, .ios, .storage, .colorCode: return false
        default: return true
        }
    }
}

/// One identity row. Memory only (R13, D10): never persisted, logged or put on the pasteboard
/// except by the explicit copy click.
struct IPhoneIdentityField: Equatable, Identifiable {
    let id: String
    let label: IdentityLabel
    let value: String
    let isSecret: Bool
}

enum LogCategory: String, CaseIterable {
    case appCrash, exceptionFault, jetsam, diskWrites, cpuResource, stackshot
    case otherReport, analytics, other
}

struct IPhoneAFCEntry: Equatable {
    var path: String
    var isDirectory: Bool
    var size: Int64
    var modified: Date?
}

struct IPhoneLogEntry: Equatable, Identifiable {
    enum Source: Equatable {
        case live
        case archive(name: String)
    }
    var path: String
    var size: Int64
    var modified: Date?
    var bugType: String?
    var category: LogCategory
    var source: Source
    var id: String { path }
}

struct BatteryPoint: Codable, Equatable {
    var day: String                 // yyyy-MM-dd, local
    var cycles: Int?
    var healthPercent: Int?
    var maxCapacityMAh: Int?
    var designCapacityMAh: Int?
    var source: String              // "live" | "import"
}

/// The ONLY persisted device data (R13).
struct IPhoneDeviceRecord: Codable, Equatable, Identifiable {
    var id: String                  // deviceKey
    var name: String
    var marketingName: String?
    var productType: String?
    var enclosureColor: String?
    var osVersion: String?
    var lastSeen: Date
    var battery: [BatteryPoint]
    var keptArchives: [String]
}

// Sysdiagnose import types (pure; L10n formats them, so Checks need them too).
enum ImportProgress: Equatable {
    case copying(done: Int64, total: Int64)
    case extracting
    case parsing
}

struct ImportSummary: Equatable {
    var batteryPoints: Int
    var skippedRows: Int
    var logFiles: Int
    var keptPath: URL?
}

enum ImportError: Error, Equatable {
    case copyFailed
    case sizeMismatch
    case tarFailed
    case keepFailed
    case cancelled
}

/// The only request shapes the transport can send (R10).
enum IPhoneRelayRequest: Equatable {
    case ioRegistryName(String)
    case ioRegistryClass(String)
    case goodbye
}

enum IPhoneData {

    /// Restarts the Mac's USB multiplexer; launchd starts `usbmuxd` again after the kill.
    static let usbmuxdRestartCommand = "/usr/bin/killall usbmuxd"

    // MARK: - Precise health and watt-hours

    // Typical iPhone Li-ion nominal voltage. Source: Wikipedia, "iPhone 16 Pro" and "iPhone 17 Pro" articles (battery rows, e.g. "18.17 Wh (4685 mAh) @ 3.88 V", "19.772 Wh (5088 mAh) @ 3.886 V"), figures derived from regulatory battery listings; iPhone 14-17 span 3.867-3.895 V, so the error is within ±0.4 %. Retrieved 2026-10-11.
    static let nominalVoltage = 3.88

    /// Max capacity as a percentage of design capacity, unrounded; nil when design is not positive.
    static func preciseHealth(maxMAh: Int, designMAh: Int) -> Double? {
        guard designMAh > 0 else { return nil }
        return Double(maxMAh) / Double(designMAh) * 100
    }

    /// Approximate energy for a capacity in mAh at `nominalVoltage`.
    static func wattHours(mAh: Int) -> Double {
        Double(mAh) * nominalVoltage / 1000
    }

    // MARK: - Device key and masking

    /// First 16 lowercase hex characters of SHA-256 over the UDID's UTF-8 bytes. The key
    /// matches the same phone on every connection without storing the UDID (D9, R13).
    static func deviceKey(udid: String) -> String {
        let digest = SHA256.hash(data: Data(udid.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// D11: first 3 + «•••» + last 4 for values of 8+ characters; shorter values become
    /// all «•» (one per character).
    static func mask(_ s: String) -> String {
        let chars = Array(s)
        if chars.count >= 8 {
            return String(chars.prefix(3)) + "•••" + String(chars.suffix(4))
        }
        return String(repeating: "•", count: chars.count)
    }

    // MARK: - Crash-log classification

    /// The first line of a crash-log header (up to `\n`) as a JSON object, or nil when the
    /// data has no newline or the line is not a JSON object.
    private static func headerObject(_ data: Data) -> [String: Any]? {
        guard let nl = data.firstIndex(of: 0x0A) else { return nil }
        let line = data[data.startIndex..<nl]
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) else { return nil }
        return obj as? [String: Any]
    }

    /// True when the header's first line is a JSON object (it may still lack `bug_type`).
    static func hasJSONHeader(_ data: Data) -> Bool {
        headerObject(data) != nil
    }

    /// `bug_type` of the header's first-line JSON object, as a string (a String or a
    /// number is accepted). nil: no newline, not JSON, not an object, or no `bug_type`.
    static func bugType(fromHeader data: Data) -> String? {
        guard let obj = headerObject(data), let v = obj["bug_type"] else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            let d = n.doubleValue
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        }
        return nil
    }

    static func category(bugType: String?) -> LogCategory {
        guard let bugType else { return .other }
        switch bugType {
        case "309": return .appCrash
        case "308": return .exceptionFault
        case "298": return .jetsam
        case "145": return .diskWrites
        case "202": return .cpuResource
        case "288": return .stackshot
        case "226", "237", "225", "233", "211", "303": return .analytics
        default: return .otherReport
        }
    }

    /// Header-cache key of one phone file: "<path>|<size>|<mtime ms>". A file whose key is
    /// unchanged keeps its cached bug_type (memory only).
    static func logCacheKey(path: String, size: Int64, modified: Date?) -> String {
        let ms = modified.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        return "\(path)|\(size)|\(ms)"
    }

    /// Entries grouped by category in display order, empty categories dropped, entries
    /// newest first (nil dates last; ties by path so the order is stable).
    static func grouped(_ entries: [IPhoneLogEntry]) -> [(LogCategory, [IPhoneLogEntry])] {
        LogCategory.allCases.compactMap { cat in
            let items = entries.filter { $0.category == cat }.sorted { a, b in
                switch (a.modified, b.modified) {
                case let (x?, y?): return x != y ? x > y : a.path < b.path
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.path < b.path
                }
            }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    /// AFC `st_mtime` is nanoseconds since the Unix epoch, as a decimal string.
    static func date(fromAFCMtime s: String) -> Date? {
        guard let ns = Int64(s) else { return nil }
        return Date(timeIntervalSince1970: Double(ns) / 1e9)
    }

    // MARK: - Battery history

    /// D7: one point per day; a live read replaces any point of its day (live wins over an
    /// import, a later live read replaces an earlier one). Sorted by day.
    static func upsertLive(_ points: [BatteryPoint], _ p: BatteryPoint) -> [BatteryPoint] {
        var out = points.filter { $0.day != p.day }
        out.append(p)
        return out.sorted { $0.day < $1.day }
    }

    /// Adds imported points only for days without a live point; a newer import replaces an
    /// older import of the same day. When `imported` itself has several points for one day,
    /// the last one wins. Sorted by day.
    static func mergeImported(_ points: [BatteryPoint], _ imported: [BatteryPoint]) -> [BatteryPoint] {
        var byDay: [String: BatteryPoint] = [:]
        for p in points { byDay[p.day] = p }
        for p in imported {
            if let existing = byDay[p.day], existing.source == "live" { continue }
            byDay[p.day] = p
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    // MARK: - Sysdiagnose import (Stage 5)

    /// Archive members the import parses (D13); nothing else is extracted.
    static let sysdiagnoseIncludes = ["*/logs/BatteryBDC/BDC_Daily_*.csv",
                                      "*/crashes_and_spins/*.ips",
                                      "*/crashes_and_spins/Retired/*.ips"]

    static func tarArguments(archive: String, into dir: String) -> [String] {
        ["-xzf", archive, "-C", dir] + sysdiagnoseIncludes.flatMap { ["--include", $0] }
    }

    private static func bdcTimestampFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.isLenient = false
        return f
    }

    /// One BDC_Daily CSV → one point per day (the last row by timestamp). Columns are found
    /// by name. A row whose timestamp is not `yyyy-MM-dd HH:mm:ss`, whose columns are
    /// missing or non-numeric, or whose `MaxCapacityPercent` is 0 is skipped and counted.
    /// Values above 100 are kept as read. maxCapacityMAh stays nil (NominalChargeCapacity
    /// is not the health basis).
    static func parseBDCDaily(_ csv: String) -> (points: [BatteryPoint], skipped: Int) {
        let lines = csv.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return ([], 0) }
        let header = headerLine.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let iTime = header.firstIndex(of: "TimeStamp"),
              let iCycle = header.firstIndex(of: "CycleCount"),
              let iHealth = header.firstIndex(of: "MaxCapacityPercent"),
              header.contains("NominalChargeCapacity") else {
            return ([], max(0, lines.count - 1))
        }
        let fmt = bdcTimestampFormatter()
        var skipped = 0
        var best: [String: (Date, BatteryPoint)] = [:]
        for line in lines.dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count == header.count,
                  cols[iTime].count == 19,
                  let when = fmt.date(from: cols[iTime]),
                  let health = Int(cols[iHealth]), let cycles = Int(cols[iCycle]),
                  health > 0 else { skipped += 1; continue }
            let day = String(cols[iTime].prefix(10))
            let p = BatteryPoint(day: day, cycles: cycles, healthPercent: health,
                                 maxCapacityMAh: nil, designCapacityMAh: nil, source: "import")
            if let cur = best[day], cur.0 > when { continue }
            best[day] = (when, p)
        }
        return (best.values.map { $0.1 }.sorted { $0.day < $1.day }, skipped)
    }

    /// Regular `.tar.gz` files under `/DiagnosticLogs/sysdiagnose/`, newest first (nil
    /// dates last, ties by path).
    static func sysdiagnoseArchives(in entries: [IPhoneAFCEntry]) -> [IPhoneAFCEntry] {
        entries.filter { !$0.isDirectory && $0.path.hasPrefix("/DiagnosticLogs/sysdiagnose/") && $0.path.hasSuffix(".tar.gz") }
            .sorted { a, b in
                switch (a.modified, b.modified) {
                case let (x?, y?): return x != y ? x > y : a.path < b.path
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.path < b.path
                }
            }
    }

    // MARK: - diagnostics_relay requests

    static func relayMessage(_ r: IPhoneRelayRequest) -> [String: Any] {
        switch r {
        case .ioRegistryName(let name): return ["Request": "IORegistry", "EntryName": name]
        case .ioRegistryClass(let cls): return ["Request": "IORegistry", "EntryClass": cls]
        case .goodbye: return ["Request": "Goodbye"]
        }
    }

    /// `Diagnostics.IORegistry` of a relay reply whose `Status` is `Success`; nil for a
    /// missing reply, any other status, a missing payload or an empty one.
    static func relayPayload(_ reply: [String: Any]?) -> [String: Any]? {
        guard let reply, reply["Status"] as? String == "Success",
              let payload = (reply["Diagnostics"] as? [String: Any])?["IORegistry"] as? [String: Any],
              !payload.isEmpty
        else { return nil }
        return payload
    }

    // MARK: - Value extraction

    /// Depth-first search for `key` in nested dictionaries, up to `maxDepth` levels below
    /// `dict` (depth 0 = `dict` itself).
    static func findValue(_ key: String, in dict: [String: Any], maxDepth: Int = 3) -> Any? {
        if let v = dict[key] { return v }
        guard maxDepth > 0 else { return nil }
        for child in dict.values {
            if let sub = child as? [String: Any], let v = findValue(key, in: sub, maxDepth: maxDepth - 1) {
                return v
            }
        }
        return nil
    }

    /// A String is trimmed; Data is decoded as UTF-8 after dropping NUL bytes, then trimmed.
    /// An empty result, or any other type, is nil.
    static func stringValue(_ v: Any?) -> String? {
        let raw: String?
        if let s = v as? String {
            raw = s
        } else if let d = v as? Data {
            raw = String(data: d.filter { $0 != 0 }, encoding: .utf8)
        } else {
            raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Identity and parts

    /// Builds the identity rows from the lockdown values, the `com.apple.disk_usage` domain
    /// and the relay payloads. A value that is missing or empty omits its field; order =
    /// `IdentityLabel.allCases`.
    static func identityFields(lockdown: [String: Any], diskUsage: [String: Any]?,
                               battery: [String: Any]?, panel: [String: Any]?,
                               product: [String: Any]?, camera: [String: Any]?) -> [IPhoneIdentityField] {
        func lock(_ key: String) -> String? { stringValue(lockdown[key]) }
        func from(_ dict: [String: Any]?, _ key: String) -> String? {
            dict.flatMap { findValue(key, in: $0) }.flatMap { stringValue($0) }
        }
        func joined(_ a: String?, _ b: String?, sep: String) -> String? {
            switch (a, b) {
            case let (x?, y?): return x + sep + y
            case let (x?, nil): return x
            case let (nil, y?): return y
            default: return nil
            }
        }
        func bytes(_ v: Any?) -> Int64? {
            if let n = v as? NSNumber { return n.int64Value }
            return stringValue(v).flatMap { Int64($0) }
        }
        var values: [IdentityLabel: String] = [:]
        values[.marketingName] = lock("MarketingName")
        values[.modelNumber] = joined(lock("ModelNumber"), lock("RegionInfo"), sep: " ")
        values[.regulatoryModel] = lock("RegulatoryModelNumber")
        values[.hardwareModel] = lock("HardwareModel")
        values[.ios] = joined(lock("ProductVersion"), lock("BuildVersion").map { "(\($0))" }, sep: " ")
        values[.storage] = diskUsage.flatMap { bytes($0["TotalDiskCapacity"]) }.flatMap { $0 > 0 ? fmtCapacity($0) : nil }
        values[.colorCode] = lock("DeviceEnclosureColor") ?? lock("DeviceColor")
        values[.serial] = lock("SerialNumber")
        values[.logicBoard] = lock("MLBSerialNumber")
        values[.imei] = lock("InternationalMobileEquipmentIdentity")
        values[.imei2] = lock("InternationalMobileEquipmentIdentity2")
        values[.battery] = from(battery, "Serial")
        values[.displayPanel] = from(panel, "Panel_ID")
        values[.displayRawPanel] = from(product, "raw-panel-serial-number")
        values[.coverGlass] = from(product, "coverglass-serial-number")
        values[.backGlass] = from(product, "backglass-compass-serial-number")
        values[.nova] = from(product, "nova-serial-num")
        values[.ambientLight] = from(product, "ambient-light-sensor-serial-num")
        values[.backCamera] = from(camera, "BackCameraModuleSerialNumString")
        values[.backSuperWide] = from(camera, "BackSuperWideCameraModuleSerialNumString")
        values[.backTele] = from(camera, "BackTeleCameraModuleSerialNumString")
        values[.frontCamera] = from(camera, "FrontCameraModuleSerialNumString")
        values[.frontIR] = from(camera, "FrontIRCameraModuleSerialNumString")
        values[.faceIDProjector] = from(camera, "FrontIRStructuredLightProjectorSerialNumString")
        return IdentityLabel.allCases.compactMap { label in
            values[label].map { IPhoneIdentityField(id: label.rawValue, label: label, value: $0, isSecret: label.isSecret) }
        }
    }

    // MARK: - Phone colour

    /// "<ProductType>|<DeviceEnclosureColor code>" → RGB. EMPTY until a colour is confirmed
    /// by the user (Needs-decision 1): the picture is neutral for every phone.
    static let enclosureColors: [String: (Double, Double, Double)] = [:]

    static func enclosureRGB(productType: String?, code: String?) -> (r: Double, g: Double, b: Double)? {
        guard let productType, let code, let c = enclosureColors["\(productType)|\(code)"] else { return nil }
        return (c.0, c.1, c.2)
    }
}

/// Remembered iPhones in one file (D8): `{"devices":[…]}` under App Support/MacDashboard.
/// Same rules as `HistoryStore.save()`: dir 0700, file 0600, atomic write, and a file
/// that cannot be decoded is renamed aside on the next save, never overwritten.
final class IPhoneStore {

    private struct Envelope: Codable {
        var devices: [IPhoneDeviceRecord]
    }

    private let url: URL
    /// true when load() found a file it could not decode; the next save() renames it aside.
    private(set) var loadedUnreadableFile = false

    init(url: URL) {
        self.url = url
    }

    /// Missing file → []. A file that exists but is not `{"devices":[…]}` → [] and flagged
    /// unreadable. Never writes, never throws.
    func load() -> [IPhoneDeviceRecord] {
        loadedUnreadableFile = false
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let envelope = try? decoder.decode(Envelope.self, from: data) else {
            loadedUnreadableFile = true
            return []
        }
        return envelope.devices
    }

    func save(_ devices: [IPhoneDeviceRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Envelope(devices: devices))

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        if loadedUnreadableFile {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.moveItem(at: url, to: unreadableBackupURL())
            }
            loadedUnreadableFile = false   // only after a successful rename (or nothing left to rename)
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// App Support/MacDashboard/iphones.json, built like `DashboardModel.defaultReportURL()`.
    static func defaultURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)) ?? fm.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MacDashboard", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("iphones.json")
    }

    /// `<file name>.unreadable-<yyyyMMdd-HHmmss>` next to the store file.
    private func unreadableBackupURL() -> URL {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyyMMdd-HHmmss"
        return url.deletingLastPathComponent().appendingPathComponent(
            url.lastPathComponent + ".unreadable-" + df.string(from: Date()))
    }
}
