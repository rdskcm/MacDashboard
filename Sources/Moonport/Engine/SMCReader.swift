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
    /// Keys the SMC answered for with an error or an unusable size, remembered with the answer (READER-STATUS).
    private var refusedKeys: [UInt32: InfoResult] = [:]

    /// Internal so a test can build a reader on connection 0, whose every call fails without touching hardware.
    init(connection: io_connect_t) { self.connection = connection }

    /// Opens the AppleSMC user client. The failure says what failed (READER-STATUS).
    static func open() -> Result<SMCReader, ReaderReason> {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return .failure(.serviceAbsent(className: "AppleSMC")) }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == KERN_SUCCESS else { return .failure(.kernReturn(call: "IOServiceOpen(AppleSMC)", code: kr)) }
        guard connection != 0 else { return .failure(.nullResult(call: "IOServiceOpen(AppleSMC)")) }
        return .success(SMCReader(connection: connection))
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

    /// Pure (READER-STATUS). The reason for a key read that gave no value; nil for `.value`.
    static func failure(key: String, read: KeyRead) -> ReaderReason? {
        switch read {
        case .value: return nil
        case .missing(let result): return .smcKeyAbsent(key: key, result: result)
        case .unsupported(let type, let size): return .smcKeyUnsupported(key: key, type: type, size: Int(size))
        case .callFailed(let kern, let result):
            return kern != KERN_SUCCESS ? .kernReturn(call: "IOConnectCallStructMethod(SMC \(key))", code: kern)
                                        : .smcResult(key: key, result: result)
        }
    }

    /// Pure (READER-STATUS). `#KEY` bytes as text for a rejected count: the big-endian value, or "<n> bytes" when short.
    static func keyCountText(_ bytes: [UInt8]) -> String {
        guard bytes.count >= 4 else { return "\(bytes.count) bytes" }
        return "\(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))"
    }

    // MARK: - Read

    /// The `kern_return_t` of the struct method call (READER-STATUS: kept, was reduced to a Bool).
    private func call(_ input: inout Param, _ output: inout Param) -> kern_return_t {
        let size = MemoryLayout<Param>.stride
        var outSize = size
        return IOConnectCallStructMethod(connection, Self.kernelIndex, &input, size, &output, &outSize)
    }

    private enum InfoResult { case info(KeyInfo), missing(result: UInt8), unsupported(type: String, size: UInt32), callFailed(kern_return_t) }

    private func info(for key: UInt32) -> InfoResult {
        if let cached = keyInfo[key] { return .info(cached) }
        if let refused = refusedKeys[key] { return refused }
        var input = Param(), output = Param()
        input.key = key
        input.data8 = Self.cmdReadKeyInfo
        let kr = call(&input, &output)
        guard kr == KERN_SUCCESS else { return .callFailed(kr) }
        // The SMC answered, but not with a usable key: this Mac has no such key (spec D8).
        guard output.result == 0 else {
            refusedKeys[key] = .missing(result: output.result)
            return .missing(result: output.result)
        }
        guard output.info.dataSize > 0, output.info.dataSize <= 32 else {
            // READER-STATUS D14: the SMC knows the key, but this reader cannot take its size (was counted as missing).
            let refused = InfoResult.unsupported(type: Self.string(fromFourCC: output.info.dataType), size: output.info.dataSize)
            refusedKeys[key] = refused
            return refused
        }
        keyInfo[key] = output.info
        return .info(output.info)
    }

    /// Outcome of one key read: the value, or a failed IOKit/SMC call (non-KERN_SUCCESS or an SMC result error).
    enum KeyRead: Equatable, Sendable {
        case value(type: String, bytes: [UInt8])
        /// The SMC has no such key (key info answered with an error). Not a connection failure.
        case missing(result: UInt8)
        /// The SMC knows the key, but its size is 0 or over 32 bytes. Not a connection failure.
        case unsupported(type: String, size: UInt32)
        /// The IOKit call failed (`kern` non-zero) or the read-bytes reply carried a non-zero SMC `result`.
        case callFailed(kern: kern_return_t, result: UInt8)
    }

    /// Type code and raw bytes of one key.
    func read(key: String) -> KeyRead {
        let code = Self.fourCC(key)
        let info: KeyInfo
        switch self.info(for: code) {
        case .info(let i): info = i
        case .missing(let result): return .missing(result: result)
        case .unsupported(let type, let size): return .unsupported(type: type, size: size)
        case .callFailed(let kr): return .callFailed(kern: kr, result: 0)
        }
        var input = Param(), output = Param()
        input.key = code
        input.info.dataSize = info.dataSize
        input.data8 = Self.cmdReadBytes
        let kr = call(&input, &output)
        guard kr == KERN_SUCCESS, output.result == 0 else { return .callFailed(kern: kr, result: output.result) }
        let all = withUnsafeBytes(of: output.bytes) { Array($0) }
        let type = Self.string(fromFourCC: info.dataType)
        return .value(type: type, bytes: Array(all.prefix(Int(info.dataSize))))
    }

    /// Why one index of the key list gave no key. `callFailed`: the IOKit call itself failed (non-KERN_SUCCESS), so the
    /// kept connection must be dropped, as after a failed key read. An SMC result error on an index is an answer from
    /// a working connection: the index is skipped and the connection kept.
    struct IndexFailure: Error, Equatable {
        let reason: ReaderReason
        let callFailed: Bool
    }

    /// Key name at `index` of the SMC key list (command 8); the failure on any failure (READER-STATUS).
    func key(at index: UInt32) -> Result<String, IndexFailure> {
        var input = Param(), output = Param()
        input.data8 = Self.cmdReadIndex
        input.data32 = index
        let kr = call(&input, &output)
        guard kr == KERN_SUCCESS else {
            return .failure(IndexFailure(reason: .kernReturn(call: "IOConnectCallStructMethod(SMC key index \(index))", code: kr), callFailed: true))
        }
        guard output.result == 0 else {
            return .failure(IndexFailure(reason: .smcResult(key: "index \(index)", result: output.result), callFailed: false))
        }
        return .success(Self.string(fromFourCC: output.key))
    }

    /// Pure. Every key accepted by `keep`, in SMC order, given the `#KEY` read and a reader of one index; the failure
    /// reason when the key count cannot be read or no index could be read (the caller does not cache a failure, so the
    /// next pass retries). An index with an SMC result error is skipped. A failed call stops the enumeration at once
    /// (the connection is dropped by `keyAt`'s owner and a partial list must not be cached). About 44 ms on the
    /// reference Mac.
    static func enumerate(count countRead: KeyRead, keyAt: (UInt32) -> Result<String, IndexFailure>,
                          keep: (String) -> Bool) -> Result<[String], ReaderReason> {
        guard case .value(_, let bytes) = countRead else {
            // Safe: a non-value read always has a reason (READER-STATUS T4).
            return .failure(failure(key: keyCountKey, read: countRead)!)
        }
        guard let count = decodeKeyCount(bytes) else {
            return .failure(.implausible(what: "SMC #KEY", value: keyCountText(bytes), accepted: "1...\(maxKeyCount)"))
        }
        var readKeys: [String] = []
        var firstFailure: ReaderReason?
        for index in 0..<count {
            switch keyAt(index) {
            case .success(let k): readKeys.append(k)
            case .failure(let f):
                if f.callFailed { return .failure(f.reason) }
                if firstFailure == nil { firstFailure = f.reason }
            }
        }
        if let kept = accepted(readKeys: readKeys, count: Int(count), keep: keep) { return .success(kept) }
        return .failure(firstFailure ?? .nullResult(call: "SMC key enumeration"))
    }

    /// Pure. Whether a key read means the kept connection is broken: only a failed call does (the same rule as
    /// `powerOutcome` and the temperature sweep); a missing or unsupported key does not.
    static func dropsConnection(_ read: KeyRead) -> Bool {
        if case .callFailed = read { return true }
        return false
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
            case .missing, .unsupported:
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
        case .missing, .unsupported: return (nil, false)
        case .value(let type, let bytes): return (plausibleWatts(decodeFloat(bytes: bytes, type: type)), false)
        }
    }

    // MARK: - Shared connection

    /// The kept connection and the "never retry" flag, under one lock (SWIFT6-MODE D6; was NSLock + two statics).
    struct Connection {
        var reader: SMCReader? = nil
        /// The first open failure, remembered for the process lifetime and never retried (READER-STATUS D10).
        var openFailure: ReaderReason? = nil
        /// The sensor-row keys, enumerated once per process (they do not change while the app runs). Kept when a broken reader is dropped.
        var sensorKeys: [String]? = nil
    }
    /// The initial value comes from a function that is never inlined, on purpose: with `Mutex(Connection())` the release
    /// optimizer builds this global at compile time and writes `openFailure` (an `Optional<ReaderReason>` next to
    /// another optional) with a wrong nil encoding, so a fresh process read `libraryNotLoaded(path: "", dlerror: nil)`
    /// and the report crashed printing it (READER-STATUS crash, 2026-11-27, release build only). A runtime-built value
    /// is encoded correctly. `SMCReaderTests.sharedConnectionStartsWithoutAForeignFailure` guards this in a release test run.
    static let connection = Mutex(makeConnection())

    @inline(never) static func makeConnection() -> Connection { Connection() }

    /// Whole-Mac power now, in watts. nil on any failure or an implausible value. Safe from any thread.
    /// `openFailed` is set once the first open failed: the SMC is then treated as absent for the process lifetime (never retried).
    static func readSystemPowerW() -> Double? {
        connection.withLock { c -> Double? in
            guard case .success(let reader) = openedReader(&c) else { return nil }
            let outcome = powerOutcome(reader.read(key: systemPowerKey))
            // A call failure may mean a broken kept connection: drop it so the next call opens a new one.
            if outcome.dropConnection { c.reader = nil }
            return outcome.watts
        }
    }

    /// The kept reader, opened on first use; the open failure when the SMC cannot be opened (remembered, never retried).
    private static func openedReader(_ c: inout Connection) -> Result<SMCReader, ReaderReason> {
        if let failure = c.openFailure { return .failure(failure) }
        if let reader = c.reader { return .success(reader) }
        switch open() {
        case .success(let reader):
            c.reader = reader
            return .success(reader)
        case .failure(let failure):
            c.openFailure = failure
            return .failure(failure)
        }
    }

    /// Decoded values of `keys` (°C, not yet filtered). nil when the SMC cannot be opened. Safe from any thread.
    static func readTemperatures(keys: [String]) -> [String: Double]? {
        connection.withLock { c -> [String: Double]? in
            guard case .success(let reader) = openedReader(&c) else { return nil }
            let result = reader.temperatures(keys)
            if result.drop { c.reader = nil }
            return result.values
        }
    }

    /// Decoded values of every sensor-row key (`TemperatureSensors.kind(forKey:)` accepts it). The key list is
    /// enumerated on the first call and kept for the process. nil when the SMC cannot be opened or its key list cannot
    /// be read. Safe from any thread.
    static func readSensorTemperatures() -> [String: Double]? {
        connection.withLock { c -> [String: Double]? in
            guard case .success(let reader) = openedReader(&c) else { return nil }
            if c.sensorKeys == nil, case .success(let keys) = enumerateLocked(reader, &c, keep: { TemperatureSensors.kind(forKey: $0) != nil }) {
                c.sensorKeys = keys
            }
            // READER-STATUS D14: a failed enumeration is not cached (the next call retries) and is nil, not an empty reading.
            guard let keys = c.sensorKeys else { return nil }
            let result = reader.temperatures(keys)
            if result.drop { c.reader = nil }
            return result.values
        }
    }

    /// The whole enumeration under the caller's lock (the live path: once per process). A failed call on the `#KEY`
    /// read or on an index drops the kept connection, as a failed key read does.
    static func enumerateLocked(_ reader: SMCReader, _ c: inout Connection, keep: (String) -> Bool) -> Result<[String], ReaderReason> {
        let countRead = reader.read(key: keyCountKey)
        if dropsConnection(countRead) { c.reader = nil }
        return enumerate(count: countRead, keyAt: { index in
            let step = reader.key(at: index)
            if case .failure(let f) = step, f.callFailed { c.reader = nil }
            return step
        }, keep: keep)
    }

    // The two probe steps below each take the shared lock for one SMC call only, so a live reader waits for one call at
    // most. A failed call drops the kept connection inside the same lock hold, the way the live reads do; the next
    // step opens a new one. The lock is released between steps.

    /// One key read as its own locked step. The open failure when the SMC cannot be opened.
    static func readKey(_ key: String, on conn: borrowing Mutex<Connection>) -> Result<KeyRead, ReaderReason> {
        conn.withLock { c -> Result<KeyRead, ReaderReason> in
            switch openedReader(&c) {
            case .failure(let reason): return .failure(reason)
            case .success(let reader):
                let read = reader.read(key: key)
                if dropsConnection(read) { c.reader = nil }
                return .success(read)
            }
        }
    }

    /// One key-list index as its own locked step. An open failure counts as a failed call, so the enumeration stops.
    static func readIndex(_ index: UInt32, on conn: borrowing Mutex<Connection>) -> Result<String, IndexFailure> {
        conn.withLock { c -> Result<String, IndexFailure> in
            switch openedReader(&c) {
            case .failure(let reason): return .failure(IndexFailure(reason: reason, callFailed: true))
            case .success(let reader):
                let result = reader.key(at: index)
                if case .failure(let f) = result, f.callFailed { c.reader = nil }
                return result
            }
        }
    }

    /// READER-STATUS: the chip keys, PSTR and every sensor key once, keeping each key's outcome. Uses and fills the
    /// same sensor-key cache as `readSensorTemperatures`. Every SMC call takes the shared lock on its own, like a live
    /// read does, so a live reader waits for one call at most, never for the whole probe (about 44 ms of enumeration
    /// plus every key read, longer if an SMC call hangs). A failed call drops the kept connection at once and the next
    /// call opens a new one; if that open fails the probe is an open failure. Safe from any thread.
    static func probe() -> SMCProbe { probe(on: connection) }

    static func probe(on conn: borrowing Mutex<Connection>) -> SMCProbe {
        var p = SMCProbe()
        func outcome(_ key: String) -> SMCKeyOutcome? {
            switch readKey(key, on: conn) {
            case .failure(let r): p.openFailure = r; return nil
            case .success(let read): return SMCKeyOutcome(key: key, read: read)
            }
        }
        for key in TemperatureSensors.chipKeys {
            guard let o = outcome(key) else { return SMCProbe(openFailure: p.openFailure) }
            p.chip.append(o)
        }
        guard let power = outcome(systemPowerKey) else { return SMCProbe(openFailure: p.openFailure) }
        p.power = power
        let keys: Result<[String], ReaderReason>
        if let cached = conn.withLock({ $0.sensorKeys }) { keys = .success(cached) }
        else {
            switch readKey(keyCountKey, on: conn) {
            case .failure(let r): return SMCProbe(openFailure: r)
            case .success(let countRead):
                keys = enumerate(count: countRead, keyAt: { readIndex($0, on: conn) }, keep: { TemperatureSensors.kind(forKey: $0) != nil })
            }
            if case .success(let k) = keys {
                conn.withLock { if $0.sensorKeys == nil { $0.sensorKeys = k } }
            }
        }
        p.sensorKeys = keys
        if case .success(let k) = keys {
            for key in k {
                guard let o = outcome(key) else { return SMCProbe(openFailure: p.openFailure) }
                p.sensors.append(o)
            }
        }
        return p
    }
}

/// One SMC key and what reading it gave (READER-STATUS).
struct SMCKeyOutcome: Equatable, Sendable {
    let key: String
    let read: SMCReader.KeyRead
}

/// The report's one-shot SMC reads (READER-STATUS). `openFailure` non-nil → nothing else was read.
struct SMCProbe: Equatable, Sendable {
    var openFailure: ReaderReason? = nil
    var chip: [SMCKeyOutcome] = []
    var power: SMCKeyOutcome? = nil
    var sensorKeys: Result<[String], ReaderReason>? = nil
    var sensors: [SMCKeyOutcome] = []
}
