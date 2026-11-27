// Tests/MoonportTests/SMCReaderTests.swift
// SOC-DETAILS 1.4: the `flt` decoder, the (0, 1000] guard and the wire struct size. The SMC itself is read only by the
// live canary (SocReadersLiveCanaryTests).
import Foundation
import Synchronization
import Testing
@testable import Moonport

private func leBytes(_ f: Float) -> [UInt8] {
    let b = f.bitPattern
    return [UInt8(b & 255), UInt8(b >> 8 & 255), UInt8(b >> 16 & 255), UInt8(b >> 24 & 255)]
}

struct SMCReaderTests {
    // TEMP-SENSORS-DETAIL
    @Test func decodeTemperatureFlt() {
        #expect(SMCReader.decodeTemperature(bytes: leBytes(57.8125), type: "flt ") == 57.8125)
        #expect(SMCReader.decodeTemperature(bytes: leBytes(57.8125), type: "flt") == 57.8125)
    }

    @Test func decodeTemperatureIoft() {
        let raw: UInt64 = 2_514_944   // 38.375 x 65536
        let bytes = (0..<8).map { UInt8(raw >> (8 * UInt64($0)) & 255) }
        #expect(SMCReader.decodeTemperature(bytes: bytes, type: "ioft") == 38.375)
        #expect(SMCReader.decodeTemperature(bytes: Array(bytes.prefix(7)), type: "ioft") == nil)
        #expect(SMCReader.decodeTemperature(bytes: bytes, type: "sp78") == nil)
        #expect(SMCReader.decodeTemperature(bytes: bytes, type: "si32") == nil)
    }

    @Test func decodeKeyCountRange() {
        #expect(SMCReader.decodeKeyCount([0, 0, 7, 60]) == 1852)
        #expect(SMCReader.decodeKeyCount([0, 0, 0, 0]) == nil)
        #expect(SMCReader.decodeKeyCount([0, 0, 7]) == nil)
        #expect(SMCReader.decodeKeyCount([0, 1, 0, 0]) == nil)
    }

    @Test func enumerationAcceptsOnlyKeptKeysAndRetriesWhenNothingRead() {
        let keep: (String) -> Bool = { $0.hasPrefix("T") }
        #expect(SMCReader.accepted(readKeys: ["Tp01", "FNum", "Te05"], count: 3, keep: keep) == ["Tp01", "Te05"])
        #expect(SMCReader.accepted(readKeys: ["FNum"], count: 1, keep: keep) == [])     // no sensor keys: a real answer
        #expect(SMCReader.accepted(readKeys: [], count: 1852, keep: keep) == nil)       // every index failed: retry
        #expect(SMCReader.accepted(readKeys: [], count: 0, keep: keep) == [])
    }

    @Test func stringFromFourCCInvertsFourCC() {
        #expect(SMCReader.string(fromFourCC: SMCReader.fourCC("TH0x")) == "TH0x")
        #expect(SMCReader.string(fromFourCC: SMCReader.fourCC("flt ")) == "flt ")
    }

    @Test func missingKeyKeepsTheConnection() {
        let outcome = SMCReader.powerOutcome(.missing(result: 0x84))
        #expect(outcome.watts == nil && outcome.dropConnection == false)
    }

    @Test func fltDecodesLittleEndian() {
        #expect(SMCReader.decodeFloat(bytes: leBytes(6.8), type: "flt ") == Double(Float(6.8)))
        #expect(SMCReader.decodeFloat(bytes: leBytes(12.3), type: "flt") == Double(Float(12.3)))   // blank-less spelling
        #expect(SMCReader.decodeFloat(bytes: [0x00, 0x00, 0x80, 0x3F], type: "flt ") == 1.0)      // 0x3F800000
        #expect(SMCReader.decodeFloat(bytes: leBytes(-3.5), type: "flt ") == -3.5)
    }

    @Test func otherTypesAndShortBuffersAreNil() {
        #expect(SMCReader.decodeFloat(bytes: leBytes(6.8), type: "sp78") == nil)
        #expect(SMCReader.decodeFloat(bytes: leBytes(6.8), type: "ui32") == nil)
        #expect(SMCReader.decodeFloat(bytes: [1, 2, 3], type: "flt ") == nil)
        #expect(SMCReader.decodeFloat(bytes: [], type: "flt ") == nil)
        #expect(SMCReader.decodeFloat(bytes: leBytes(.nan), type: "flt ") == nil)
        #expect(SMCReader.decodeFloat(bytes: leBytes(.infinity), type: "flt ") == nil)
    }

    @Test func powerGuardIsZeroExclusiveThousandInclusive() {
        #expect(SMCReader.plausibleWatts(6.8) == 6.8)
        #expect(SMCReader.plausibleWatts(1000) == 1000)
        #expect(SMCReader.plausibleWatts(0.001) == 0.001)
        #expect(SMCReader.plausibleWatts(0) == nil)
        #expect(SMCReader.plausibleWatts(-1) == nil)
        #expect(SMCReader.plausibleWatts(1000.01) == nil)
        #expect(SMCReader.plausibleWatts(.nan) == nil)
        #expect(SMCReader.plausibleWatts(nil) == nil)
    }

    @Test func keyAndStructLayout() {
        #expect(SMCReader.fourCC("PSTR") == 0x5053_5452)
        #expect(MemoryLayout<SMCReader.Param>.stride == 80)   // the kernel's SMCKeyData size; probe.swift printed 80
    }

    @Test func onlyACallFailureDropsTheConnection() {
        #expect(SMCReader.powerOutcome(.callFailed(kern: 5, result: 0)).dropConnection)
        #expect(SMCReader.powerOutcome(.callFailed(kern: 5, result: 0)).watts == nil)
        let good = SMCReader.powerOutcome(.value(type: "flt ", bytes: leBytes(6.8)))
        #expect(good.watts == Double(Float(6.8)) && !good.dropConnection)
        for bad in [leBytes(0), leBytes(1000.5), leBytes(.nan)] {
            let o = SMCReader.powerOutcome(.value(type: "flt ", bytes: bad))
            #expect(o.watts == nil && !o.dropConnection)
        }
        let wrongType = SMCReader.powerOutcome(.value(type: "ui32", bytes: leBytes(6.8)))
        #expect(wrongType.watts == nil && !wrongType.dropConnection)
    }

    // READER-STATUS
    @Test func unsupportedKeyKeepsTheConnection() {
        let outcome = SMCReader.powerOutcome(.unsupported(type: "ch8*", size: 40))
        #expect(outcome.watts == nil && outcome.dropConnection == false)
    }

    @Test func failureReasons() {
        #expect(SMCReader.failure(key: "PSTR", read: .value(type: "flt ", bytes: leBytes(1))) == nil)
        #expect(SMCReader.failure(key: "TCMz", read: .missing(result: 0x84)) == .smcKeyAbsent(key: "TCMz", result: 0x84))
        #expect(SMCReader.failure(key: "X", read: .unsupported(type: "ch8*", size: 40)) == .smcKeyUnsupported(key: "X", type: "ch8*", size: 40))
        #expect(SMCReader.failure(key: "PSTR", read: .callFailed(kern: 5, result: 0))
                == .kernReturn(call: "IOConnectCallStructMethod(SMC PSTR)", code: 5))
        #expect(SMCReader.failure(key: "PSTR", read: .callFailed(kern: 0, result: 0x85)) == .smcResult(key: "PSTR", result: 0x85))
    }

    @Test func keyCountText() {
        #expect(SMCReader.keyCountText([0, 0, 7, 60]) == "1852")
        #expect(SMCReader.keyCountText([1, 2]) == "2 bytes")
    }

    // READER-STATUS: a failed call on the `#KEY` read or a key-list index drops the connection, like a failed key read.
    private static let countBytes: [UInt8] = [0, 0, 0, 5]
    private static let keepAll: @Sendable (String) -> Bool = { _ in true }

    @Test func enumerationStopsAtAFailedCallAndKeepsNothingPartial() {
        var asked: [UInt32] = []
        let failed = SMCReader.IndexFailure(reason: .kernReturn(call: "x", code: 5), callFailed: true)
        let result = SMCReader.enumerate(count: .value(type: "ui32", bytes: Self.countBytes), keyAt: { i in
            asked.append(i)
            return i == 2 ? .failure(failed) : .success("Tp0\(i)")
        }, keep: Self.keepAll)
        #expect(result == .failure(.kernReturn(call: "x", code: 5)))
        #expect(asked == [0, 1, 2])
    }

    @Test func enumerationSkipsAnSMCResultErrorOnAnIndex() {
        let skipped = SMCReader.IndexFailure(reason: .smcResult(key: "index 1", result: 0x84), callFailed: false)
        let result = SMCReader.enumerate(count: .value(type: "ui32", bytes: Self.countBytes), keyAt: { i in
            i == 1 ? .failure(skipped) : .success("Tp0\(i)")
        }, keep: Self.keepAll)
        #expect(result == .success(["Tp00", "Tp02", "Tp03", "Tp04"]))
    }

    @Test func enumerationReportsAFailedCountRead() {
        var asked = 0
        let result = SMCReader.enumerate(count: .callFailed(kern: 5, result: 0), keyAt: { _ in asked += 1; return .success("A") },
                                         keep: Self.keepAll)
        #expect(result == .failure(.kernReturn(call: "IOConnectCallStructMethod(SMC #KEY)", code: 5)))
        #expect(asked == 0)
    }

    @Test func onlyACallFailedReadDropsInTheKeyStep() {
        #expect(SMCReader.dropsConnection(.callFailed(kern: 5, result: 0)))
        #expect(!SMCReader.dropsConnection(.missing(result: 0x84)))
        #expect(!SMCReader.dropsConnection(.unsupported(type: "ch8*", size: 40)))
        #expect(!SMCReader.dropsConnection(.value(type: "flt ", bytes: leBytes(1))))
    }

    // A reader on connection 0 fails every IOKit call without touching the SMC.
    @Test func aFailedKeyCountReadDropsTheKeptConnection() {
        let conn = Mutex(SMCReader.Connection(reader: SMCReader(connection: 0)))
        guard case .success(.callFailed) = SMCReader.readKey(SMCReader.keyCountKey, on: conn) else {
            Issue.record("expected a callFailed read on connection 0"); return
        }
        #expect(conn.withLock { $0.reader == nil })
    }

    @Test func aFailedIndexCallDropsTheKeptConnection() {
        let conn = Mutex(SMCReader.Connection(reader: SMCReader(connection: 0)))
        guard case .failure(let f) = SMCReader.readIndex(0, on: conn) else {
            Issue.record("expected a failed index read on connection 0"); return
        }
        #expect(f.callFailed)
        #expect(conn.withLock { $0.reader == nil })
    }

    @Test func anOpenFailureStopsTheProbeAndTheSteps() {
        let reason = ReaderReason.serviceAbsent(className: "AppleSMC")
        let conn = Mutex(SMCReader.Connection(openFailure: reason))
        #expect(SMCReader.readKey("PSTR", on: conn) == .failure(reason))
        #expect(SMCReader.readIndex(0, on: conn) == .failure(.init(reason: reason, callFailed: true)))
        #expect(SMCReader.probe(on: conn) == SMCProbe(openFailure: reason))
    }

    @Test func theLiveEnumerationDropsTheConnectionAfterAFailedCall() {
        let conn = Mutex(SMCReader.Connection(reader: SMCReader(connection: 0)))
        let failedWithKern = conn.withLock { c -> Bool in
            guard let reader = c.reader,
                  case .failure(.kernReturn) = SMCReader.enumerateLocked(reader, &c, keep: Self.keepAll) else { return false }
            return true
        }
        #expect(failedWithKern)
        #expect(conn.withLock { $0.reader == nil })
    }

    /// Release-only crash (2026-11-27): the optimizer built the shared connection's initial value with a wrong nil
    /// encoding for `openFailure`, so a fresh process held `libraryNotLoaded(path: "", dlerror: nil)`. A debug run
    /// passes either way: run `swift test -c release -Xswiftc -enable-testing --filter sharedConnectionStartsWithoutAForeignFailure` to see it.
    /// Reads no hardware: only the stored state is looked at, and `open()` itself can only fail three ways.
    @Test func sharedConnectionStartsWithoutAForeignFailure() {
        switch SMCReader.connection.withLock({ $0.openFailure }) {
        case nil, .serviceAbsent?, .kernReturn?, .nullResult?: break
        case let other?: Issue.record("the shared SMC connection holds a reason open() never produces: \(other)")
        }
    }
}
