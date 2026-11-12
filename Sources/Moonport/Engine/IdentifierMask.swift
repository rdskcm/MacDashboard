// Engine/IdentifierMask.swift
// SERIAL-MASK-LAST4: the one rule for showing a device or part identifier masked. A serial shows its last 4
// characters, an IMEI its TAC. Every identifier the app puts on screen is shown in this form until the user reveals it
// (Views/IdentifierRevealControls.swift); nothing else masks for display.
// Pure, Foundation only; covered by Tests/MoonportTests/IdentifierMaskTests.swift.

import Foundation

enum IdentifierMask {
    /// The hidden part of a serial, always four bullets so the value's length is not shown.
    static let hidden = "••••"
    /// Characters a serial keeps visible at its end.
    static let serialVisible = 4
    /// A serial shorter than this is hidden whole: the visible 4 would leave fewer than 4 hidden.
    static let serialMinLength = 8
    /// IMEI type allocation code length (3GPP TS 23.003 §6.2.1).
    static let tacLength = 8

    /// "" for an empty value, "••••" below `serialMinLength` characters, otherwise "•••• " + the last 4.
    static func serial(_ value: String) -> String {
        let chars = Array(value.trimmingCharacters(in: .whitespacesAndNewlines))
        if chars.isEmpty { return "" }
        if chars.count < serialMinLength { return hidden }
        return hidden + " " + String(chars.suffix(serialVisible))
    }

    /// An IMEI (15 digits) or IMEISV (16 digits): the TAC, a space, one "•" per remaining digit.
    /// "" for an empty value; any other shape shows nothing ("••••").
    static func imei(_ value: String) -> String {
        let chars = Array(value.trimmingCharacters(in: .whitespacesAndNewlines))
        if chars.isEmpty { return "" }
        guard chars.count == 15 || chars.count == 16, chars.allSatisfy({ ("0"..."9").contains($0) }) else { return hidden }
        return String(chars.prefix(tacLength)) + " " + String(repeating: "•", count: chars.count - tacLength)
    }
}
