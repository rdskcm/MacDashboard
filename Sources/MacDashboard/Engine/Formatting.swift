// Engine/Formatting.swift
// Deterministic Russian number/byte formatting — relocated out of Views/Theme.swift
// (Block H) so it's Foundation-only and can be symlinked into MacDashboardChecks;
// HistorySeries.swift's formattedSwap needs it and Checks must stay SwiftUI-free.
// Views/Theme.swift keeps the Color/palette helpers; this file owns the numeric
// formatters that any Engine or View code may call.

import Foundation

/// Comma-decimal Russian number formatting, trims trailing zeros
/// ("12,0" -> "12", "12,34" @ decimals:1 -> "12,3").
func fmtNum(_ v: Double, decimals: Int = 1) -> String {
    var s = String(format: "%.\(decimals)f", v)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    return s.replacingOccurrences(of: ".", with: L.decimalSeparator)
}

/// Deterministic decimal capacity formatter: ГБ/ТБ (GB/TB), matching how macOS
/// reports disk sizes (decimal, 10^9/10^12) — unlike `fmtBytes`, which is binary
/// and used for memory/swap. One decimal place under 1000 GB; two decimals from
/// 1 TB up to (not including) 10 TB, one decimal at/above 10 TB; trailing zeros
/// trimmed, comma as decimal separator. Used by the disk tile value, «из N»
/// slot, and footer sizes ("2,24 ТБ из 4 ТБ").
func fmtCapacity(_ bytes: Int64) -> String {
    let p = fmtCapacityParts(bytes)
    return "\(p.value) \(p.unit)"
}

/// Same value/unit split `fmtCapacity` produces, returned separately so a caller rendering in a
/// monospaced face can control the gap itself (a U+0020 in a monospaced font carries a full
/// glyph advance — ~15 pt at 27 pt).
func fmtCapacityParts(_ bytes: Int64) -> (value: String, unit: String) {
    let gb = Double(bytes) / 1_000_000_000
    // Decide the unit using the value AFTER rounding to the digits it will be
    // displayed with, so e.g. 999.95 GB (which rounds to "1000.0") reports as
    // TB instead of the misleading "1000,0 ГБ".
    if (gb * 10).rounded() / 10 >= 1000 {
        let tb = Double(bytes) / 1_000_000_000_000
        let decimals = (tb * 100).rounded() / 100 >= 10 ? 1 : 2
        return (fmtNum(tb, decimals: decimals), L.byteUnitTB)
    }
    return (fmtNum(gb, decimals: 1), L.byteUnitGB)
}

/// Deterministic Russian byte formatter: КБ/МБ/ГБ/ТБ, one decimal place
/// (trimmed), comma as decimal separator. Intentionally NOT ByteCountFormatter,
/// which is locale-dependent and uses Latin unit abbreviations.
func fmtBytes(_ n: Int64?) -> String {
    let p = fmtBytesParts(n)
    guard let unit = p.unit else { return p.value }
    return "\(p.value) \(unit)"
}

/// Same value/unit split `fmtBytes` produces, returned separately so a caller rendering in a
/// monospaced face can control the gap itself (a U+0020 in a monospaced font carries a full
/// glyph advance — ~15 pt at 27 pt).
func fmtBytesParts(_ n: Int64?) -> (value: String, unit: String?) {
    guard let n else { return ("—", nil) }
    let units: [(String, Double)] = [
        (L.byteUnitTB, 1_099_511_627_776), (L.byteUnitGB, 1_073_741_824),
        (L.byteUnitMB, 1_048_576), (L.byteUnitKB, 1024), (L.byteUnitB, 1)
    ]
    let dn = Double(n)
    for (unit, mul) in units where dn >= mul || unit == L.byteUnitB {
        return (fmtNum(dn / mul, decimals: 1), unit)
    }
    return ("—", nil)
}

/// V2-FIX-UNITS follow-up: joins `fmtBytesParts`/`fmtCapacityParts` output with
/// U+2009 THIN SPACE instead of a plain U+0020, for call sites embedding the
/// value in a larger localized string at a PROPORTIONAL font — in a
/// proportional face a thin-space glyph has a genuinely narrower advance than
/// a regular space (unlike a monospaced face, where every glyph including
/// spaces gets the same fixed advance and this trick doesn't help).
func tight(_ parts: (value: String, unit: String?)) -> String {
    guard let unit = parts.unit else { return parts.value }
    return "\(parts.value)\u{2009}\(unit)"
}

/// Overload for `fmtCapacityParts`, whose `unit` is non-optional.
func tight(_ parts: (value: String, unit: String)) -> String {
    "\(parts.value)\u{2009}\(parts.unit)"
}
