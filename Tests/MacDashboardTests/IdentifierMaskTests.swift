// Tests/MacDashboardTests/IdentifierMaskTests.swift
// SERIAL-MASK-LAST4: the masking rule (IdentifierMask) and the per-label choice (IdentityLabel.displayValue).
import Foundation
import Testing
@testable import MacDashboard

@Suite struct IdentifierMaskTests {
    @Test func serial() {
        #expect(IdentifierMask.serial("SYN0000001") == "•••• 0001", "10-char iPhone serial: last 4")
        #expect(IdentifierMask.serial("F8Y4213A7Q1MXLKA") == "•••• XLKA", "16-char battery serial: last 4")
        #expect(IdentifierMask.serial("ABCDEFGH") == "•••• EFGH", "8 chars is the shortest form with a visible tail")
        #expect(IdentifierMask.serial("ABCDEFG") == "••••", "7 chars: hidden whole")
        #expect(IdentifierMask.serial("AB") == "••••", "short value: hidden whole, length not shown")
        #expect(IdentifierMask.serial("") == "", "empty stays empty")
        #expect(IdentifierMask.serial("  SYN0000001\n") == "•••• 0001", "surrounding whitespace is trimmed first")
        #expect(IdentifierMask.serial("SYN0000001") == IdentifierMask.serial("XXXXXX0001"), "only the last 4 survive")
        #expect(IdentifierMask.serial("SYN000000000006").count == IdentifierMask.serial("SYN0000000013").count,
                "every long serial masks to the same width")
    }

    @Test func imei() {
        #expect(IdentifierMask.imei("123456789012345") == "12345678 •••••••", "IMEI: TAC + 7 hidden digits")
        #expect(IdentifierMask.imei("1234567890123456") == "12345678 ••••••••", "IMEISV: TAC + 8 hidden digits")
        #expect(IdentifierMask.imei(" 123456789012345 ") == "12345678 •••••••", "IMEI: whitespace trimmed")
        #expect(IdentifierMask.imei("12345678901234") == "••••", "14 digits: not an IMEI, nothing shown")
        #expect(IdentifierMask.imei("12345678901234A") == "••••", "non-digit: nothing shown")
        #expect(IdentifierMask.imei("١٢٣٤٥٦٧٨٩٠١٢٣٤٥") == "••••", "non-ASCII digits: nothing shown")
        #expect(IdentifierMask.imei("") == "", "empty stays empty")
    }

    @Test func identityLabels() {
        #expect(IdentityLabel.imei.displayValue("123456789012345") == "12345678 •••••••")
        #expect(IdentityLabel.imei2.displayValue("000000000000004") == "00000000 •••••••", "the fixture's IMEI 2")
        #expect(IdentityLabel.serial.displayValue("SYN0000001") == "•••• 0001")
        #expect(IdentityLabel.logicBoard.displayValue("SYN000000000002") == "•••• 0002")
        #expect(IdentityLabel.faceIDProjector.displayValue("SYN0000000016") == "•••• 0016")
        #expect(IdentityLabel.modelNumber.displayValue("MFXG4 LL/A") == "MFXG4 LL/A", "non-secret label unchanged")
        #expect(IdentityLabel.ios.displayValue("26.4.1 (23E254)") == "26.4.1 (23E254)", "non-secret label unchanged")
        for label in IdentityLabel.allCases where label.isSecret {
            #expect(label.displayValue("ABCDEFGHIJKL").hasPrefix("••••"), "every secret label masks: \(label)")
        }
    }
}
