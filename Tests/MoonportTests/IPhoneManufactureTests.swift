// Tests/MoonportTests/IPhoneManufactureTests.swift
// IPHONE-MANUFACTURE-DATE: the YWW decoder, the BDC_Once manufacture parser, the cross-import merge and the
// device record's Codable shape. All CSV text is synthetic. No process-wide state, so no SerialTests.
import Foundation
import Testing
@testable import Moonport

@Suite struct IPhoneManufactureTests {
    private static let header = "TimeStamp,ChemID,AlgoChemID,EEEE,YWW,DesignCapacity,GasGaugeFirmwareVersion"

    private func stamp(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)!
    }

    private func csv(_ rows: (String, String)...) -> String {
        ([Self.header] + rows.map { "\($0.0),1,1,X,\($0.1),5030,1" }).joined(separator: "\n")
    }

    @Test func decodeYWW() {
        func d(_ raw: String, _ y: Int) -> (year: Int, week: Int)? { IPhoneData.decodeYWW(raw, stampYear: y) }
        #expect(d("530", 2025)?.year == 2025 && d("530", 2025)?.week == 30)
        #expect(d("338", 2026)?.year == 2023 && d("338", 2026)?.week == 38)
        #expect(d("952", 2030)?.year == 2029 && d("952", 2030)?.week == 52)
        #expect(d("030", 2030)?.year == 2030 && d("030", 2030)?.week == 30)
        #expect(d("653", 2026)?.year == 2026 && d("653", 2026)?.week == 53)
        for (raw, y) in [("553", 2025), ("500", 2025), ("554", 2025), ("53", 2025), ("5300", 2025), ("", 2025),
                         ("5a0", 2025), ("-30", 2025), ("5 3", 2025), ("５３０", 2025)] {
            #expect(d(raw, y) == nil, "\(raw) must not decode")
        }
    }

    @Test func parseSingleFile() {
        let r = IPhoneData.batteryManufacture(fromBDCOnce: [csv(("2025-11-05 10:00:00", "530"))])
        #expect(r?.year == 2025 && r?.week == 30)
        #expect(r?.stamp == stamp("2025-11-05 10:00:00"))
        let wide = Self.header + ",Extra\n2025-11-05 10:00:00,1,1,X,530,5030,1,0"
        let w = IPhoneData.batteryManufacture(fromBDCOnce: [wide])
        #expect(w?.year == 2025 && w?.week == 30)
    }

    @Test func parseRejects() {
        let good = "2025-11-05 10:00:00,1,1,X,530,5030,1"
        #expect(IPhoneData.batteryManufacture(fromBDCOnce: ["TimeStamp,DesignCapacity\n2025-11-05 10:00:00,5030"]) == nil)
        #expect(IPhoneData.batteryManufacture(fromBDCOnce: ["YWW,DesignCapacity\n530,5030"]) == nil)
        #expect(IPhoneData.batteryManufacture(fromBDCOnce: [Self.header + "\n" + good + ",extra"]) == nil)
        #expect(IPhoneData.batteryManufacture(fromBDCOnce: [csv(("2025-11-05", "530"))]) == nil)
        #expect(IPhoneData.batteryManufacture(fromBDCOnce: [csv(("2025-13-40 10:00:00", "530"))]) == nil)
        #expect(IPhoneData.batteryManufacture(fromBDCOnce: [csv(("2025-11-05 10:00:00", "500"))]) == nil)
        #expect(IPhoneData.batteryManufacture(fromBDCOnce: [""]) == nil)
        #expect(IPhoneData.batteryManufacture(fromBDCOnce: []) == nil)
    }

    @Test func newestStampWins() {
        let a = csv(("2024-01-10 08:00:00", "338"))
        let b = csv(("2025-12-01 08:00:00", "541"))
        for texts in [[a, b], [b, a]] {
            let r = IPhoneData.batteryManufacture(fromBDCOnce: texts)
            #expect(r?.year == 2025 && r?.week == 41)
            #expect(r?.stamp == stamp("2025-12-01 08:00:00"))
        }
        let both = csv(("2025-12-01 08:00:00", "541"), ("2024-01-10 08:00:00", "338"))
        let one = IPhoneData.batteryManufacture(fromBDCOnce: [both])
        #expect(one?.year == 2025 && one?.week == 41)
        let bad = csv(("2025-12-01 08:00:00", "000"), ("2024-01-10 08:00:00", "338"))
        let skipped = IPhoneData.batteryManufacture(fromBDCOnce: [bad])
        #expect(skipped?.year == 2023 && skipped?.week == 38)
        let a2 = csv(("2025-12-01 08:00:00", "338"))
        let tie = IPhoneData.batteryManufacture(fromBDCOnce: [a2, b])
        #expect(tie?.year == 2025 && tie?.week == 41)
    }

    @Test func mergeAcrossImports() {
        let old = IPhoneBatteryManufacture(year: 2023, week: 38, stamp: stamp("2024-01-10 08:00:00"))
        let new = IPhoneBatteryManufacture(year: 2025, week: 41, stamp: stamp("2025-12-01 08:00:00"))
        #expect(IPhoneData.mergedManufacture(stored: new, imported: old) == new)
        #expect(IPhoneData.mergedManufacture(stored: old, imported: new) == new)
        #expect(IPhoneData.mergedManufacture(stored: nil, imported: old) == old)
        #expect(IPhoneData.mergedManufacture(stored: old, imported: nil) == old)
        #expect(IPhoneData.mergedManufacture(stored: nil, imported: nil) == nil)
        let same = IPhoneBatteryManufacture(year: 2023, week: 39, stamp: old.stamp)
        #expect(IPhoneData.mergedManufacture(stored: old, imported: same) == same)
    }

    @Test func recordCodable() throws {
        let oldJSON = #"{"id":"k","name":"P","lastSeen":"2025-11-05T10:00:00Z","battery":[],"keptArchives":[]}"#
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let r = try dec.decode(IPhoneDeviceRecord.self, from: Data(oldJSON.utf8))
        #expect(r.batteryManufacture == nil)

        var rec = r
        rec.batteryManufacture = IPhoneBatteryManufacture(year: 2025, week: 30, stamp: Date(timeIntervalSince1970: 1_762_336_800))
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(rec)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"batteryManufacture\"") && text.contains("\"stamp\""))
        #expect(try dec.decode(IPhoneDeviceRecord.self, from: data) == rec)
    }
}
