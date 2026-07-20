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

/// Deterministic Russian byte formatter: КБ/МБ/ГБ/ТБ, one decimal place
/// (trimmed), comma as decimal separator. Intentionally NOT ByteCountFormatter,
/// which is locale-dependent and uses Latin unit abbreviations.
func fmtBytes(_ n: Int64?) -> String {
    guard let n else { return "—" }
    let units: [(String, Double)] = [
        (L.byteUnitTB, 1_099_511_627_776), (L.byteUnitGB, 1_073_741_824),
        (L.byteUnitMB, 1_048_576), (L.byteUnitKB, 1024), (L.byteUnitB, 1)
    ]
    let dn = Double(n)
    for (unit, mul) in units where dn >= mul || unit == L.byteUnitB {
        return "\(fmtNum(dn / mul, decimals: 1)) \(unit)"
    }
    return "—"
}
