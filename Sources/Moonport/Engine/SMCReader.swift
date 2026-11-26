// Engine/SMCReader.swift
// SOC-DETAILS 1.4: whole-Mac power in watts from the SMC key `PSTR` (System Total), a source separate from the
// frozen IOReport energy counters. Public IOKit calls only (IOServiceOpen + IOConnectCallStructMethod), so nothing
// is resolved with dlsym. Read-only: only the "read key info" (9), "read bytes" (5) and "read key at index" (8)
// commands are ever issued.
// TEMP-SENSORS-DETAIL: also reads temperature keys (`flt ` and `ioft`) and enumerates the key list once per process
// (command 8, read key at index). A key the SMC reports as missing (key info answered with a non-zero result) is not a
// call failure: it never drops the connection and is remembered per reader.
//
// Method sources (open, MIT), cited by file and line; no code was copied from either:
// - Stats (exelban/stats): Modules/Sensors/values.swift:666 (the key name `PSTR`, "System Total"), and its SMC wrapper
//   (Kit, `SMCKit`) for the call shape: struct method index 2, key info then read bytes.
// - macmon (vladkens/macmon): src/metrics.rs:647-649 (the same key as whole-system power).
// - Verified on the reference Mac: inputs/SOC-DETAILS-research/probe-load-tested/probe.swift:205-286 (struct layout,
//   stride 80, the two commands, `flt ` decoding), 6.7-8.4 W at rest, 12.3 W after a 2-thread spin.
//
// Failure model (all-or-nothing, logic 3.6 and D15): any non-KERN_SUCCESS, a non-zero SMC result byte, an unexpected
// type or size, a non-finite value, or a value outside (0, 1000] W → nil. The connection is kept between reads and closed
// on deinit. It is dropped (so the next call reopens it) only after an IOKit/SMC call failure, never after a plausibility
// rejection. A failed open is remembered for the process lifetime and never retried. Never throws, never prompts.

import Foundation
import IOKit
import Synchronization

final class SMCReader {
    // MARK: - Wire format (AppleSMC `SMCKeyData`, 80 bytes)

    struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct Limit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var attrs: UInt8 = 0 }
    struct Param {
        var key: UInt32 = 0
        var vers = Vers()
        var limit = Limit()
        var info = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private static let kernelIndex: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdReadKeyInfo: UInt8 = 9
    private static let cmdReadIndex: UInt8 = 8
    static let keyCountKey = "#KEY"
    /// Guard against a garbage key count (1852 on the reference Mac).
    static let maxKeyCount: UInt32 = 20_000
    static let systemPowerKey = "PSTR"
    /// Logic 3.6 / D15: this app's guard against a garbage reading, not a claim about any Mac.
    static let maxPlausibleWatts = 1000.0

    private var connection: io_connect_t = 0
    private var keyInfo: [UInt32: KeyInfo] = [:]
    private var missingKeys: Set<UInt32> = []

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS, connection != 0 else { return nil }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    // MARK: - Pure

    /// "PSTR" → 0x50535452.
    static func fourCC(_ key: String) -> UInt32 { key.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    /// Pure. `flt` (the SMC type code is `"flt "` with a trailing blank, both spellings accepted): 4 bytes, IEEE 754,
    /// little-endian. Any other type, a short buffer or a non-finite value → nil.
    static func decodeFloat(bytes: [UInt8], type: String) -> Double? {
        guard type.trimmingCharacters(in: .whitespaces) == "flt", bytes.count >= 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let v = Double(Float(bitPattern: bits))
        return v.isFinite ? v : nil
    }

    /// Pure. D15 / logic 3.6: `0 < W ≤ 1000`, else nil.
    static func plausibleWatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= maxPlausibleWatts else { return nil }
        return value
    }

    /// Pure. 0x54483078 → "TH0x"; the inverse of `fourCC`. Also turns a type code into its string ("flt ").
    static func string(fromFourCC code: UInt32) -> String {
        String(bytes: [UInt8(code >> 24 & 255), UInt8(code >> 16 & 255), UInt8(code >> 8 & 255), UInt8(code & 255)],
               encoding: .isoLatin1) ?? ""
    }

    /// Pure. A temperature key's value: `flt ` through `decodeFloat`; `ioft` = 8 bytes, little-endian unsigned 48.16
    /// fixed point (value / 65536, as the reference-Mac probe decoded it). Other types or short buffers → nil. No range
    /// check here: `TemperatureSensors.isValid` decides plausibility.
    static func decodeTemperature(bytes: [UInt8], type: String) -> Double? {
        if let value = decodeFloat(bytes: bytes, type: type) { return value }
        guard type.trimmingCharacters(in: .whitespaces) == "ioft", bytes.count >= 8 else { return nil }
        var raw: UInt64 = 0
        for (i, byte) in bytes.prefix(8).enumerated() { raw |= UInt64(byte) << (8 * UInt64(i)) }
        return Double(raw) / 65536
    }

    /// Pure. `#KEY` = number of keys, big-endian UInt32. nil for a short buffer, 0, or more than `maxKeyCount`.
    static func decodeKeyCount(_ bytes: [UInt8]) -> UInt32? {
        guard bytes.count >= 4 else { return nil }
        let n = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        return n > 0 && n <= maxKeyCount ? n : nil
    }

    // MARK: - Read

    private func call(_ input: inout Param, _ output: inout Param) -> Bool {
        let size = MemoryLayout<Param>.stride
        var outSize = size
        return IOConnectCallStructMethod(connection, Self.kernelIndex, &input, size, &output, &outSize) == KERN_SUCCESS
    }

    private enum InfoResult { case info(KeyInfo), missing, callFailed }

    private func info(for key: UInt32) -> InfoResult {
        if let cached = keyInfo[key] { return .info(cached) }
        if missingKeys.contains(key) { return .missing }
        var input = Param(), output = Param()
        input.key = key
        input.data8 = Self.cmdReadKeyInfo
        guard call(&input, &output) else { return .callFailed }
        // The SMC answered, but not with a usable key: this Mac has no such key (spec D8).
        guard output.result == 0, output.info.dataSize > 0, output.info.dataSize <= 32 else {
            missingKeys.insert(key)
            return .missing
        }
        keyInfo[key] = output.info
        return .info(output.info)
    }

    /// Outcome of one key read: the value, or a failed IOKit/SMC call (non-KERN_SUCCESS or an SMC result error).
    enum KeyRead {
        case value(type: String, bytes: [UInt8])
        /// The SMC has no such key (key info answered with an error). Not a connection failure.
        case missing
        case callFailed
    }

    /// Type code and raw bytes of one key.
    func read(key: String) -> KeyRead {
        let code = Self.fourCC(key)
        let info: KeyInfo
        switch self.info(for: code) {
        case .info(let i): info = i
        case .missing: return .missing
        case .callFailed: return .callFailed
        }
        var input = Param(), output = Param()
        input.key = code
        input.info.dataSize = info.dataSize
        input.data8 = Self.cmdReadBytes
        guard call(&input, &output), output.result == 0 else { return .callFailed }
        let all = withUnsafeBytes(of: output.bytes) { Array($0) }
        let type = Self.string(fromFourCC: info.dataType)
        return .value(type: type, bytes: Array(all.prefix(Int(info.dataSize))))
    }

    /// Key name at `index` of the SMC key list (command 8); nil on any failure.
    private func key(at index: UInt32) -> String? {
        var input = Param(), output = Param()
        input.data8 = Self.cmdReadIndex
        input.data32 = index
        guard call(&input, &output), output.result == 0 else { return nil }
        return Self.string(fromFourCC: output.key)
    }

    /// Every key accepted by `keep`, in SMC order; nil when the key count cannot be read or no index could be read
    /// (the caller does not cache nil, so the next pass retries). An index that fails to read is skipped. About 44 ms
    /// on the reference Mac.
    private func enumerateKeys(keep: (String) -> Bool) -> [String]? {
        guard case .value(_, let bytes) = read(key: Self.keyCountKey), let count = Self.decodeKeyCount(bytes) else { return nil }
        return Self.accepted(readKeys: (0..<count).compactMap { key(at: $0) }, count: Int(count), keep: keep)
    }

    /// Pure. The kept keys of an enumeration that read `readKeys` out of `count` indices; nil when `count` > 0 and
    /// none could be read (a failed enumeration, not a Mac without sensor keys). An empty result of a successful
    /// read is a real answer and is returned.
    static func accepted(readKeys: [String], count: Int, keep: (String) -> Bool) -> [String]? {
        if readKeys.isEmpty && count > 0 { return nil }
        return readKeys.filter(keep)
    }

    /// Decoded values of `keys` (unfiltered °C); keys without a value are left out. `drop` = a call failed, so the
    /// kept connection must be dropped; the sweep stops there.
    private func temperatures(_ keys: [String]) -> (values: [String: Double], drop: Bool) {
        var values: [String: Double] = [:]
        for key in keys {
            switch read(key: key) {
            case .value(let type, let bytes):
                if let value = Self.decodeTemperature(bytes: bytes, type: type) { values[key] = value }
            case .missing:
                continue
            case .callFailed:
                return (values, true)
            }
        }
        return (values, false)
    }

    /// Pure. Watts for one read, and whether the kept connection must be dropped: only a failed call drops it; a
    /// value that fails decoding or the plausibility guard returns nil and keeps the connection.
    static func powerOutcome(_ read: KeyRead) -> (watts: Double?, dropConnection: Bool) {
        switch read {
        case .callFailed: return (nil, true)
        case .missing: return (nil, false)
        case .value(let type, let bytes): return (plausibleWatts(decodeFloat(bytes: bytes, type: type)), false)
        }
    }

    // MARK: - Shared connection

    /// The kept connection and the "never retry" flag, under one lock (SWIFT6-MODE D6; was NSLock + two statics).
    private struct Connection {
        var reader: SMCReader? = nil
        var openFailed = false
        /// The sensor-row keys, enumerated once per process (they do not change while the app runs). Kept when a broken reader is dropped.
        var sensorKeys: [String]? = nil
    }
    private static let connection = Mutex(Connection())

    /// Whole-Mac power now, in watts. nil on any failure or an implausible value. Safe from any thread.
    /// `openFailed` is set once the first open failed: the SMC is then treated as absent for the process lifetime (never retried).
    static func readSystemPowerW() -> Double? {
        connection.withLock { c -> Double? in
            if c.openFailed { return nil }
            if c.reader == nil {
                c.reader = SMCReader()
                if c.reader == nil { c.openFailed = true; return nil }
            }
            guard let reader = c.reader else { return nil }
            let outcome = powerOutcome(reader.read(key: systemPowerKey))
            // A call failure may mean a broken kept connection: drop it so the next call opens a new one.
            if outcome.dropConnection { c.reader = nil }
            return outcome.watts
        }
    }

    /// The kept reader, opened on first use; nil when the SMC cannot be opened (remembered, never retried).
    private static func openedReader(_ c: inout Connection) -> SMCReader? {
        if c.openFailed { return nil }
        if c.reader == nil {
            c.reader = SMCReader()
            if c.reader == nil { c.openFailed = true }
        }
        return c.reader
    }

    /// Decoded values of `keys` (°C, not yet filtered). nil when the SMC cannot be opened. Safe from any thread.
    static func readTemperatures(keys: [String]) -> [String: Double]? {
        connection.withLock { c -> [String: Double]? in
            guard let reader = openedReader(&c) else { return nil }
            let result = reader.temperatures(keys)
            if result.drop { c.reader = nil }
            return result.values
        }
    }

    /// Decoded values of every sensor-row key (`TemperatureSensors.kind(forKey:)` accepts it). The key list is
    /// enumerated on the first call and kept for the process. nil when the SMC cannot be opened. Safe from any thread.
    static func readSensorTemperatures() -> [String: Double]? {
        connection.withLock { c -> [String: Double]? in
            guard let reader = openedReader(&c) else { return nil }
            if c.sensorKeys == nil {
                c.sensorKeys = reader.enumerateKeys { TemperatureSensors.kind(forKey: $0) != nil }
            }
            let result = reader.temperatures(c.sensorKeys ?? [])
            if result.drop { c.reader = nil }
            return result.values
        }
    }
}
