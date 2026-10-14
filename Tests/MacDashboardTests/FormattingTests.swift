// Tests/MacDashboardTests/FormattingTests.swift
// Port of Checks/main.swift lines 2378-2457 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct FormattingTests {
        @Test func capacityFormatting() async {
            // =====================================================================
            // MARK: - fmtCapacity (decimal GB/TB disk-capacity formatting)
            // =====================================================================
            do {
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }

                // (bytes, expected-ru, expected-en, case label)
                let cases: [(Int64, String, String, String)] = [
                    (Int64(228.3 * 1e9), "228,3 ГБ", "228.3 GB", "228.3 GB"),
                    (Int64(999.9 * 1e9), "999,9 ГБ", "999.9 GB", "999.9 GB"),
                    // Rounding-before-thresholding trap: 999.95 GB rounds to "1000.0" at
                    // one decimal, which must NOT render as "1000,0 ГБ" — the unit switch
                    // has to happen before formatting, giving "1 ТБ" instead.
                    (Int64(999.95 * 1e9), "1 ТБ", "1 TB", "999.95 GB (rounding trap)"),
                    (1_000_000_000_000, "1 ТБ", "1 TB", "1 TB"),
                    (Int64(2.24 * 1e12), "2,24 ТБ", "2.24 TB", "2.24 TB"),
                    (4_000_000_000_000, "4 ТБ", "4 TB", "4 TB (trailing zeros trimmed)"),
                    (Int64(10.5 * 1e12), "10,5 ТБ", "10.5 TB", "10.5 TB (one decimal at/above 10 TB)"),
                ]

                for (bytes, expectedRU, expectedEN, label) in cases {
                    L10nStore.shared.language = .ru
                    #expect(fmtCapacity(bytes) == expectedRU, "fmtCapacity: \(label) (ru) == \"\(expectedRU)\"")
                    L10nStore.shared.language = .en
                    #expect(fmtCapacity(bytes) == expectedEN, "fmtCapacity: \(label) (en) == \"\(expectedEN)\"")
                }

                // Round-trip: fmtCapacityParts must never diverge from fmtCapacity (V2-FIX-UNITS).
                for (bytes, _, _, label) in cases {
                    for lang in [AppLanguage.ru, .en] {
                        L10nStore.shared.language = lang
                        let p = fmtCapacityParts(bytes)
                        #expect(fmtCapacity(bytes) == "\(p.value) \(p.unit)",
                              "fmtCapacityParts round-trip: \(label) (\(lang))")
                    }
                }
            }
        }

        @Test func bytesRoundTrip() async {
            // =====================================================================
            // MARK: - fmtBytes / fmtBytesParts round-trip (V2-FIX-UNITS)
            // =====================================================================
            do {
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }

                // nil ⇒ ("—", nil), matching fmtBytes's "—".
                #expect(fmtBytesParts(nil).value == "—" && fmtBytesParts(nil).unit == nil,
                      "fmtBytesParts: nil ⇒ (\"—\", nil)")
                #expect(fmtBytes(nil) == "—", "fmtBytes: nil ⇒ \"—\"")

                // MUTATION-SURVIVORS M30: exactly one unit is shown as 1 of the next unit up (>=, not >).
                let exactSteps: [(Int64, String)] = [
                    (1024, L.byteUnitKB), (1_048_576, L.byteUnitMB),
                    (1_073_741_824, L.byteUnitGB), (1_099_511_627_776, L.byteUnitTB),
                ]
                for (bytes, unit) in exactSteps {
                    let p = fmtBytesParts(bytes)
                    #expect(p.value == "1" && p.unit == unit,
                          "fmtBytesParts: \(bytes) bytes ⇒ (\"1\", \(unit)) (got (\(p.value), \(p.unit ?? "nil")))")
                }

                // Each binary unit step (B/KB/MB/GB/TB).
                let byteCases: [Int64] = [
                    0, 1, 512, 1023,
                    1024, 1_048_575,
                    1_048_576, 1_073_741_823,
                    1_073_741_824, 1_099_511_627_775,
                    1_099_511_627_776, 2 * 1_099_511_627_776,
                ]

                for bytes in byteCases {
                    for lang in [AppLanguage.ru, .en] {
                        L10nStore.shared.language = lang
                        let p = fmtBytesParts(bytes)
                        #expect(fmtBytes(bytes) == "\(p.value) \(p.unit ?? "")",
                              "fmtBytesParts round-trip: \(bytes) bytes (\(lang))")
                    }
                }
            }
        }
    }
}
