// Engine/SMCReader.swift
// SOC-DETAILS 1.4: whole-Mac power in watts from the SMC key `PSTR` (System Total), a source separate from the
// frozen IOReport energy counters. Public IOKit calls only (IOServiceOpen + IOConnectCallStructMethod), so nothing
// is resolved with dlsym. Read-only: only the "read key info" (9) and "read bytes" (5) commands are ever issued.
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
    static let systemPowerKey = "PSTR"
    /// Logic 3.6 / D15: this app's guard against a garbage reading, not a claim about any Mac.
    static let maxPlausibleWatts = 1000.0

    private var connection: io_connect_t = 0
    private var keyInfo: [UInt32: KeyInfo] = [:]

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

    // MARK: - Read

    private func call(_ input: inout Param, _ output: inout Param) -> Bool {
        let size = MemoryLayout<Param>.stride
        var outSize = size
        return IOConnectCallStructMethod(connection, Self.kernelIndex, &input, size, &output, &outSize) == KERN_SUCCESS
    }

    private func info(for key: UInt32) -> KeyInfo? {
        if let cached = keyInfo[key] { return cached }
        var input = Param(), output = Param()
        input.key = key
        input.data8 = Self.cmdReadKeyInfo
        guard call(&input, &output), output.result == 0,
              output.info.dataSize > 0, output.info.dataSize <= 32 else { return nil }
        keyInfo[key] = output.info
        return output.info
    }

    /// Outcome of one key read: the value, or a failed IOKit/SMC call (non-KERN_SUCCESS or an SMC result error).
    enum KeyRead {
        case value(type: String, bytes: [UInt8])
        case callFailed
    }

    /// Type code and raw bytes of one key.
    func read(key: String) -> KeyRead {
        let code = Self.fourCC(key)
        guard let info = info(for: code) else { return .callFailed }
        var input = Param(), output = Param()
        input.key = code
        input.info.dataSize = info.dataSize
        input.data8 = Self.cmdReadBytes
        guard call(&input, &output), output.result == 0 else { return .callFailed }
        let all = withUnsafeBytes(of: output.bytes) { Array($0) }
        let type = String(bytes: [UInt8(info.dataType >> 24 & 255), UInt8(info.dataType >> 16 & 255),
                                  UInt8(info.dataType >> 8 & 255), UInt8(info.dataType & 255)], encoding: .isoLatin1) ?? ""
        return .value(type: type, bytes: Array(all.prefix(Int(info.dataSize))))
    }

    /// Pure. Watts for one read, and whether the kept connection must be dropped: only a failed call drops it; a
    /// value that fails decoding or the plausibility guard returns nil and keeps the connection.
    static func powerOutcome(_ read: KeyRead) -> (watts: Double?, dropConnection: Bool) {
        switch read {
        case .callFailed: return (nil, true)
        case .value(let type, let bytes): return (plausibleWatts(decodeFloat(bytes: bytes, type: type)), false)
        }
    }

    // MARK: - Shared connection

    private static let lock = NSLock()
    private static var shared: SMCReader?
    /// Set once the first open failed: the SMC is then treated as absent for the process lifetime (never retried).
    private static var openFailed = false

    /// Whole-Mac power now, in watts. nil on any failure or an implausible value. Safe from any thread.
    static func readSystemPowerW() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        if openFailed { return nil }
        if shared == nil {
            shared = SMCReader()
            if shared == nil { openFailed = true; return nil }
        }
        guard let reader = shared else { return nil }
        let outcome = powerOutcome(reader.read(key: systemPowerKey))
        // A call failure may mean a broken kept connection: drop it so the next call opens a new one.
        if outcome.dropConnection { shared = nil }
        return outcome.watts
    }
}
