// Engine/Formatting.swift
// Deterministic number/byte formatting — relocated out of Views/Theme.swift
// (Block H) so it's Foundation-only and can be unit-tested by Tests/MacDashboardTests;
// HistorySeries.swift's formattedSwap needs it and Checks must stay SwiftUI-free.
// Views/Theme.swift keeps the Color/palette helpers; this file owns the numeric
// formatters that any Engine or View code may call.

import Foundation

/// Number formatting in the UI language (comma decimal in Russian), trims trailing zeros
/// ("12,0" -> "12", "12,34" @ decimals:1 -> "12,3").
@MainActor func fmtNum(_ v: Double, decimals: Int = 1) -> String { fmtNum(v, decimals: decimals, language: L10nStore.shared.language) }
func fmtNum(_ v: Double, decimals: Int = 1, language: AppLanguage) -> String {
    var s = String(format: "%.\(decimals)f", v)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    return s.replacingOccurrences(of: ".", with: language.strings.decimalSeparator)
}

/// Fixed decimals, never trimmed ("2.10", "25.0"): load averages and the CPU percentage.
@MainActor func fmtFixed(_ v: Double, decimals: Int) -> String { fmtFixed(v, decimals: decimals, language: L10nStore.shared.language) }
func fmtFixed(_ v: Double, decimals: Int, language: AppLanguage) -> String {
    String(format: "%.\(decimals)f", v).replacingOccurrences(of: ".", with: language.strings.decimalSeparator)
}

/// Integers grouped by 3 with the language's separator (EN "1,204", RU "1\u{2009}204"); negatives keep the sign.
@MainActor func fmtGrouped<T: BinaryInteger>(_ v: T) -> String { fmtGrouped(v, language: L10nStore.shared.language) }
func fmtGrouped<T: BinaryInteger>(_ v: T, language: AppLanguage) -> String {
    let separator = language.strings.groupingSeparator
    let digits = String(v.magnitude)
    var out = ""
    for (i, ch) in digits.reversed().enumerated() {
        if i > 0 && i % 3 == 0 { out.append(contentsOf: separator.reversed()) }
        out.append(ch)
    }
    return (v < 0 ? "-" : "") + String(out.reversed())
}

/// NVMe data units (1 unit = 1000 x 512 bytes) as TB with one decimal.
@MainActor func fmtTB(dataUnits: UInt64) -> String { fmtTB(dataUnits: dataUnits, language: L10nStore.shared.language) }
func fmtTB(dataUnits: UInt64, language: AppLanguage) -> String {
    fmtFixed(Double(dataUnits) * 512_000 / 1e12, decimals: 1, language: language) + " " + language.strings.byteUnitTB
}

/// Deterministic decimal capacity formatter: GB/TB, matching how macOS
/// reports disk sizes (decimal, 10^9/10^12) — unlike `fmtBytes`, which is binary
/// and used for memory/swap. One decimal place under 1000 GB; two decimals from
/// 1 TB up to (not including) 10 TB, one decimal at/above 10 TB; trailing zeros
/// trimmed, comma as decimal separator. Used by the disk tile value, "of N"
/// slot, and footer sizes ("2.24 TB of 4 TB").
@MainActor func fmtCapacity(_ bytes: Int64) -> String { fmtCapacity(bytes, language: L10nStore.shared.language) }
func fmtCapacity(_ bytes: Int64, language: AppLanguage) -> String {
    let p = fmtCapacityParts(bytes, language: language)
    return "\(p.value) \(p.unit)"
}

/// Same value/unit split `fmtCapacity` produces, returned separately so a caller rendering in a
/// monospaced face can control the gap itself (a U+0020 in a monospaced font carries a full
/// glyph advance — ~15 pt at 27 pt).
@MainActor func fmtCapacityParts(_ bytes: Int64) -> (value: String, unit: String) { fmtCapacityParts(bytes, language: L10nStore.shared.language) }
func fmtCapacityParts(_ bytes: Int64, language: AppLanguage) -> (value: String, unit: String) {
    let S = language.strings
    let gb = Double(bytes) / 1_000_000_000
    // Decide the unit using the value AFTER rounding to the digits it will be
    // displayed with, so e.g. 999.95 GB (which rounds to "1000.0") reports as
    // TB instead of the misleading "1000.0 GB".
    if (gb * 10).rounded() / 10 >= 1000 {
        let tb = Double(bytes) / 1_000_000_000_000
        let decimals = (tb * 100).rounded() / 100 >= 10 ? 1 : 2
        return (fmtNum(tb, decimals: decimals, language: language), S.byteUnitTB)
    }
    return (fmtNum(gb, decimals: 1, language: language), S.byteUnitGB)
}

/// Backup progress amounts (DISK-MOUNT-LIVE): decimal MB under 1 GB so early progress does not read as zero, then exactly
/// `fmtCapacityParts`. The unit is decided after rounding, like `fmtCapacityParts`; a non-zero amount shows at least 0.1 MB.
@MainActor func fmtBackupBytesParts(_ bytes: Int64) -> (value: String, unit: String) {
    let mb = Double(bytes) / 1_000_000
    guard (mb * 10).rounded() / 10 < 1000 else { return fmtCapacityParts(bytes) }
    return (fmtNum(bytes > 0 ? max(mb, 0.1) : 0, decimals: 1), L.byteUnitMB)
}

/// Deterministic byte formatter in the UI language: KB/MB/GB/TB, one decimal place
/// (trimmed), comma as decimal separator. Intentionally NOT ByteCountFormatter,
/// which is locale-dependent and uses Latin unit abbreviations.
@MainActor func fmtBytes(_ n: Int64?) -> String { fmtBytes(n, language: L10nStore.shared.language) }
func fmtBytes(_ n: Int64?, language: AppLanguage) -> String {
    let p = fmtBytesParts(n, language: language)
    guard let unit = p.unit else { return p.value }
    return "\(p.value) \(unit)"
}

/// Same value/unit split `fmtBytes` produces, returned separately so a caller rendering in a
/// monospaced face can control the gap itself (a U+0020 in a monospaced font carries a full
/// glyph advance — ~15 pt at 27 pt).
@MainActor func fmtBytesParts(_ n: Int64?) -> (value: String, unit: String?) { fmtBytesParts(n, language: L10nStore.shared.language) }
func fmtBytesParts(_ n: Int64?, language: AppLanguage) -> (value: String, unit: String?) {
    guard let n else { return ("—", nil) }
    let S = language.strings
    let units: [(String, Double)] = [
        (S.byteUnitTB, 1_099_511_627_776), (S.byteUnitGB, 1_073_741_824),
        (S.byteUnitMB, 1_048_576), (S.byteUnitKB, 1024), (S.byteUnitB, 1)
    ]
    let dn = Double(n)
    for (unit, mul) in units where dn >= mul || unit == S.byteUnitB {
        return (fmtNum(dn / mul, decimals: 1, language: language), unit)
    }
    return ("—", nil)
}

/// Uptime in seconds → the header/report form, mirroring `uptime(1)`'s own print rules so the text equals what
/// `Parsers.uptimeSeconds` was parsed from: "10 d 22 h 32 min", "2 d 3 min", "1 d 1 h", "5 min", "30 s".
func fmtUptime(seconds: Int, language: AppLanguage) -> String {
    let S = language.strings
    let s = max(0, seconds)
    let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60, sec = s % 60
    var parts: [String] = []
    if d > 0 { parts.append("\(d) \(S.uptimeUnitDay)") }
    if h > 0 && m > 0 { parts.append(S.uptimeHourMinuteCombo(h, m)) }
    else if h > 0 { parts.append("\(h) \(S.uptimeUnitHour)") }
    else if m > 0 { parts.append("\(m) \(S.uptimeUnitMinute)") }
    else { parts.append("\(sec) \(S.uptimeUnitSecond)") }
    return parts.joined(separator: " ")
}
@MainActor func fmtUptime(seconds: Int) -> String { fmtUptime(seconds: seconds, language: L10nStore.shared.language) }

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

/// Display-only day formatter for already-parsed dates: the history file's
/// "yyyy-MM-dd" ids are parsed with fixed `en_US_POSIX` formatters
/// (`HistoryCard.dateFormatter`, `HistoryStore.dayFormatter`)
/// because day-boundary math must not depend on any locale — those stay. This one is the
/// opposite job: render a `Date` for a human using the Mac's system Region setting
/// (day/month/year order, separators) — independent of the app's own UI language toggle,
/// so an app set to English on a Mac whose Region is e.g. Germany still shows German-style
/// dates. Both `locale` and `timeZone` are `.autoupdatingCurrent` (not `.current`) so this
/// once-captured `let` reads today's Region/time-zone rather than the one in effect when the
/// formatter was built. NOT verified in this project: whether a CACHED `DateFormatter`
/// re-derives its `.short` PATTERN after a mid-session Region change, or only picks it up on
/// the next formatter creation — Foundation documents neither, so treat live pattern updates
/// as unproven. Worst case is a stale day/month ORDER until relaunch, never a wrong date.
/// Never parse with this formatter. `.short` keeps the chart footer compact and digit-aligned.
private let displayDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.timeZone = .autoupdatingCurrent
    f.dateStyle = .short
    f.timeStyle = .none
    return f
}()

/// System-region short date for display (never for parsing) — see above.
func fmtDisplayDay(_ date: Date) -> String {
    displayDayFormatter.string(from: date)
}

private let displayDateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.timeZone = .autoupdatingCurrent
    f.dateStyle = .short
    f.timeStyle = .medium
    return f
}()

/// System-region short date + time with seconds, for display only (crash-log «Created»).
func fmtDisplayDateTime(_ date: Date) -> String {
    displayDateTimeFormatter.string(from: date)
}

private let displayDateTimeShortFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.timeZone = .autoupdatingCurrent
    f.dateStyle = .short
    f.timeStyle = .short
    return f
}()

/// System-region short date + hours:minutes, no seconds, for display only (the firmware card's «checked» and «stopped» times).
func fmtDisplayDateTimeShort(_ date: Date) -> String {
    displayDateTimeShortFormatter.string(from: date)
}

private func makeShortDayFormatter(_ template: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.timeZone = .autoupdatingCurrent
    f.setLocalizedDateFormatFromTemplate(template)
    return f
}
private let shortDayFormatter = makeShortDayFormatter("dMMM")
private let shortDayYearFormatter = makeShortDayFormatter("dMMMyy")

/// Compact day for tight tiles (display only, never parsing; same locale/time-zone policy as `fmtDisplayDay`):
/// day + month in the current calendar year, plus a two-digit year otherwise.
func fmtShortDay(_ date: Date) -> String {
    let sameYear = Calendar.autoupdatingCurrent.isDate(date, equalTo: Date(), toGranularity: .year)
    return (sameYear ? shortDayFormatter : shortDayYearFormatter).string(from: date)
}
