// Tests/MoonportTests/SMCReaderTests.swift
// SOC-DETAILS 1.4: the `flt` decoder, the (0, 1000] guard and the wire struct size. The SMC itself is read only by the
// live canary (SocReadersLiveCanaryTests).
import Foundation
import Testing
@testable import Moonport

private func leBytes(_ f: Float) -> [UInt8] {
    let b = f.bitPattern
    return [UInt8(b & 255), UInt8(b >> 8 & 255), UInt8(b >> 16 & 255), UInt8(b >> 24 & 255)]
}

struct SMCReaderTests {
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
        #expect(SMCReader.powerOutcome(.callFailed).dropConnection)
        #expect(SMCReader.powerOutcome(.callFailed).watts == nil)
        let good = SMCReader.powerOutcome(.value(type: "flt ", bytes: leBytes(6.8)))
        #expect(good.watts == Double(Float(6.8)) && !good.dropConnection)
        for bad in [leBytes(0), leBytes(1000.5), leBytes(.nan)] {
            let o = SMCReader.powerOutcome(.value(type: "flt ", bytes: bad))
            #expect(o.watts == nil && !o.dropConnection)
        }
        let wrongType = SMCReader.powerOutcome(.value(type: "ui32", bytes: leBytes(6.8)))
        #expect(wrongType.watts == nil && !wrongType.dropConnection)
    }
}
