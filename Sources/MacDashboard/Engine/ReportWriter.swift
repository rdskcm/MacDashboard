// Engine/ReportWriter.swift
//
// Renders the short text report (title, generated line, eight aligned rows, optional
// parse-failure tail) from `ReportSummaryInput` values and writes it atomically to disk.
// The same string is shown in the Report sheet, copied by Copy and stored in
// mac_report.txt. BILINGUAL: every string goes through `L` (StringsEN/StringsRU).
// Pure rendering only — NO command execution / subprocess calls happen in this file.

import Foundation

/// Everything the short report needs, as values. Built by DashboardModel (live pass) and VisualFixture.
struct ReportSummaryInput {
    var generatedAt: Date
    var system: SystemInfo?
    var status: HomeStatus
    var tasks: [HomeTask]
    var cpu: CPUUsage?
    var load: [Double]?
    var ncpu: Int
    var socTempC: Int?
    var mem: MemSnapshot?
    var memPressure: MemoryPressureLevel?
    var swap: SwapInfo?
    var disk: DiskInfo?
    var hasBattery: Bool
    var battery: BatteryInfo?          // already BatteryInfo.merged(live:report:)
    var security: SecurityState?
    var claudeBackup: ClaudeBackupStatus?
    var snapshotCount: Int?            // report.snapshots?.count; nil = not collected
    var now: Date                      // for the Claude backup age
    var parseFailures: [ParseFailure]  // report.parseFailures + live.parseFailures
}

/// The free `fmtBytes(_: Int64?)` (Formatting.swift); inside `ReportWriter` the name resolves to its own helper.
private func reportFmtBytes(_ n: Int64) -> String { fmtBytes(n as Int64?) }

enum ReportWriter {

    // MARK: - Public API

    /// The short report, in the app's current language. Ends with exactly one "\n".
    static func render(_ i: ReportSummaryInput) -> String {
        let key: (String) -> String = { padRight($0, 16) }
        let dash = "—"
        var lines: [String] = []

        var model = i.system?.modelName ?? "Mac"
        if let chip = i.system?.chip { model += " (\(chip))" }
        lines.append(L.reportTitle(model))
        let dateTime = formatDateTime(i.generatedAt)
        if let v = i.system?.osVersion {
            let os = "macOS \(v)" + (i.system?.osBuild.map { " (\($0))" } ?? "")
            lines.append(L.reportGenerated(dateTime, os))
        } else {
            lines.append(L.reportGeneratedNoOS(dateTime))
        }
        lines.append("")

        let statusText: String
        switch i.status {
        case .checking: statusText = L.commonChecking
        case .good: statusText = L.commonAllGood
        case .attention: statusText = L.commonNeedsAttention
        case .critical: statusText = L.commonCritical
        }
        var statusLine = key(L.reportKeyStatus) + statusText
        if !i.tasks.isEmpty { statusLine += " · " + L.homeTaskCount(i.tasks.count) }
        lines.append(statusLine)
        for t in i.tasks {
            let mark = t.tone == .hot ? "!!" : "! "
            let obj = t.object.count >= 14 ? t.object + " " : padRight(t.object, 14)
            lines.append("  \(mark) \(obj)\(t.state)")
        }
        lines.append("")

        lines.append(key(L.reportKeyCPU) + cpuRow(i, dash))
        lines.append(key(L.reportKeyMemory) + memoryRow(i, dash))
        lines.append(key(L.reportKeyStorage) + storageRow(i, dash))
        lines.append(key(L.reportKeyBattery) + batteryRow(i, dash))
        lines.append(key(L.reportKeySecurity) + securityRow(i, dash))
        lines.append(key(L.reportKeyBackups) + backupsRow(i, dash))
        lines.append(key(L.reportKeyUptime) + (i.system?.uptime ?? dash))

        var out = lines.joined(separator: "\n") + "\n"
        let unparsed = i.parseFailures.sorted { $0.commandLine < $1.commandLine }
        if !unparsed.isEmpty { addSection(&out, L.reportSectionUnparsed, renderParseFailures(unparsed)) }
        return out
    }

    /// Atomic overwrite (temp file + replace or Data.write(.atomic)). Creates parent dir.
    /// The report profiles the user (home paths, login items, process names, hardware
    /// model), so the file is 0600 and the directory 0700 — the defaults (0644/0755) make
    /// it readable by every other local account.
    static func write(text: String, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // `attributes:` only applies to directories createDirectory actually creates; an
        // install that already has this directory from an older build keeps its 0755 until
        // it is tightened explicitly. Best-effort: a chmod failure on a pre-existing,
        // possibly foreign-owned directory must not block writing the report.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let data = Data(text.utf8)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Section plumbing

    private static func addSection(_ out: inout String, _ name: String, _ lines: [String]) {
        out += "\n===== \(name) =====\n"
        out += lines.joined(separator: "\n")
        out += "\n"
    }

    // MARK: - Rows

    private static func cpuRow(_ i: ReportSummaryInput, _ dash: String) -> String {
        guard let cpu = i.cpu else { return dash }
        var parts = [L.homePercent(fmtFixed(cpu.user + cpu.sys, decimals: 1))]
        parts.append(i.load?.first.map { L.homeLoadCores(fmtFixed($0, decimals: 2), i.ncpu) } ?? L.homeCoresOnly(i.ncpu))
        if let t = i.socTempC { parts.append("SoC \(t) °C") }
        return parts.joined(separator: " · ")
    }

    private static func memoryRow(_ i: ReportSummaryInput, _ dash: String) -> String {
        guard let mem = i.mem, mem.total > 0 else { return dash }
        let gib = 1_073_741_824.0
        let totalGB = "\(Int((Double(mem.total) / gib).rounded())) \(L.byteUnitGB)"
        var parts = ["\(fmtNum(Double(mem.usedBytes) / gib, decimals: 1)) \(L.homeOf(totalGB))"]
        switch MemoryLoad.pressureTone(i.memPressure) {
        case .low?: parts.append(L.homePressureLow)
        case .medium?: parts.append(L.homePressureMedium)
        case .high?: parts.append(L.homePressureHigh)
        case nil: break
        }
        if let s = i.swap { parts.append("swap \(reportFmtBytes(s.used))") }
        return parts.joined(separator: " · ")
    }

    private static func storageRow(_ i: ReportSummaryInput, _ dash: String) -> String {
        guard let d = i.disk, d.size > 0 else { return dash }
        var parts = [L.reportStorageFree(fmtCapacityParts(d.avail).value, fmtCapacity(d.size))]
        if let p = d.purgeable { parts.append(L.reportPurgeable(fmtCapacity(p))) }
        return parts.joined(separator: " · ")
    }

    private static func batteryRow(_ i: ReportSummaryInput, _ dash: String) -> String {
        guard i.hasBattery else { return L.reportNoBattery }
        guard let b = i.battery else { return dash }
        var parts: [String] = []
        if let c = b.charge { parts.append(L.homePercent("\(c)") + (b.state.map { ", \($0)" } ?? "")) }
        if let m = b.maxCapacity { parts.append(L.reportCapacity(L.homePercent("\(m)"))) }
        if let n = b.cycles { parts.append(L.reportCycles(n)) }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    private static func securityRow(_ i: ReportSummaryInput, _ dash: String) -> String {
        guard let s = i.security else { return dash }
        // D6: ON = bare name, OFF = «<name> off», unknown = «<name> ?».
        func item(_ name: String, _ v: Bool?) -> String {
            guard let v else { return "\(name) ?" }
            return v ? name : "\(name) \(L.reportOff)"
        }
        return [item("FileVault", s.fileVault), item("Gatekeeper", s.gatekeeper), item("SIP", s.sip),
                item(L.reportFirewall, s.firewall)].joined(separator: " · ")
    }

    private static func backupsRow(_ i: ReportSummaryInput, _ dash: String) -> String {
        var parts: [String] = []
        switch i.claudeBackup {
        case .lastSuccess(let d)?:
            let age = BackupLog.durationText(seconds: Int(i.now.timeIntervalSince(d)))
            parts.append("\(L.commonClaudeBackup) \(L.claudeBackupAgo(age))")
        case .noSuccessFound?:
            parts.append("\(L.commonClaudeBackup) \(L.attnDetailClaudeBackupNone)")
        case .unreadable?, nil: break
        }
        if let n = i.snapshotCount { parts.append(L.reportLocalSnapshots(n)) }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    /// "Oct 17, 2026, 10:30" / "17 окт. 2026, 10:30" in the app language and the local time zone.
    private static func formatDateTime(_ date: Date) -> String {
        let ru = L10nStore.shared.language == .ru
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: ru ? "ru_RU" : "en_US")
        fmt.timeZone = .current
        fmt.dateFormat = ru ? "d MMM yyyy, HH:mm" : "MMM d, yyyy, HH:mm"
        return fmt.string(from: date)
    }

    private static func renderParseFailures(_ failures: [ParseFailure]) -> [String] {
        var lines = [L.reportUnparsedHint]
        for f in failures {
            lines.append("$ \(f.commandLine)")
            lines.append(contentsOf: f.excerpt.map { "  " + $0 })
            if f.omittedLineCount > 0 { lines.append("  " + L.reportUnparsedMoreLines(f.omittedLineCount)) }
        }
        return lines
    }

    // MARK: - Formatting helpers

    /// Human byte size, "96,4 ГБ" style: comma decimal, КБ/МБ/ГБ/ТБ, base 1024, one
    /// fixed decimal once above the smallest unit. Deterministic regardless of the
    /// user's system locale — String(format:) without an explicit locale always uses
    /// "." internally, which is then replaced with ",".
    static func fmtBytes(_ bytes: Int64) -> String {
        let units = [L.byteUnitB, L.byteUnitKB, L.byteUnitMB, L.byteUnitGB, L.byteUnitTB]
        let sign = bytes < 0 ? "-" : ""
        var value = Double(bytes.magnitude)
        var idx = 0
        while value >= 1024, idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        if idx == 0 {
            return "\(sign)\(Int64(value)) \(units[idx])"
        }
        let str = String(format: "%.1f", value).replacingOccurrences(of: ".", with: L.decimalSeparator)
        return "\(sign)\(str) \(units[idx])"
    }

    /// Fixed-width column padding — never truncates (only pads when shorter than width).
    static func padRight(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    static func padLeft(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}

// MARK: - SMART Critical Warning humanizer (display-only; raw value untouched)

/// Renders the NVMe SMART "Critical Warning" bitfield as a human-readable RU string.
/// Display-layer only — never use this to gate severity logic, which must keep
/// comparing the raw hex string (e.g. `!= "0x00"`).
func smartCriticalWarningRU(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var hexDigits = trimmed
    if hexDigits.hasPrefix("0x") || hexDigits.hasPrefix("0X") {
        hexDigits.removeFirst(2)
    }
    guard !hexDigits.isEmpty, let value = UInt(hexDigits, radix: 16) else {
        return raw
    }
    if value == 0 { return L.reportSmartWarningNone }

    let bits: [(UInt, String)] = [
        (0x01, L.reportSmartWarningLowSpareCapacity),
        (0x02, L.reportSmartWarningCriticalTemp),
        (0x04, L.reportSmartWarningReliabilityDegraded),
        (0x08, L.reportSmartWarningReadOnlyMode),
        (0x10, L.reportSmartWarningBackupPowerFail),
        (0x20, L.reportSmartWarningPersistentMemoryReadOnly),
    ]
    let matched = bits.filter { value & $0.0 != 0 }.map { $0.1 }
    if matched.isEmpty {
        return L.reportSmartWarningGeneric(String(format: "0x%02X", value))
    }
    return matched.joined(separator: ", ")
}

// MARK: - SMART attribute/status localizer (display-only; raw model untouched)

/// Translates known smartctl attribute names (`"Temperature"`, `"Power Cycles"`, …)
/// and status words (`"SMART: OK"`) to the active app language for render-time
/// display — SwiftUI table headers/rows (`StorageCards.swift`) and the text report
/// (`ReportWriter.renderSmart`). Rebuilds the lookup from `L` on every call so a
/// language switch is picked up immediately without re-collecting SMART data.
///
/// Distinct from `smartCriticalWarningRU`, which decodes the *value* of the
/// "Critical Warning" bitfield, not a label/status string. Unrecognized input
/// (unknown attribute name, already-localized status, etc.) passes through
/// unchanged — never crashes, never blanks the display.
func smartLocalizedLabel(_ raw: String) -> String {
    let knownLabels: [String: String] = [
        "Critical Warning": L.smartAttrCriticalWarning,
        "Temperature": L.smartAttrTemperature,
        "Available Spare": L.smartAttrAvailableSpare,
        "Percentage Used": L.smartAttrPercentageUsed,
        "Power Cycles": L.smartAttrPowerCycles,
        "Power On Hours": L.smartAttrPowerOnHours,
        "Unsafe Shutdowns": L.smartAttrUnsafeShutdowns,
        "Media and Data Integrity Errors": L.smartAttrMediaAndDataIntegrityErrors,
        "Error Information Log Entries": L.smartAttrErrorInformationLogEntries,
        "SMART: OK": L.reportSmartStatusOk,
    ]
    return knownLabels[raw] ?? raw
}

// MARK: - Report staleness caption time (pure; Checks-tested)

/// Formats the "updated at" time for the Отчёт tab's staleness caption.
/// Same calendar day as `now` → time only ("14:32"), matching the SMART card's
/// caption; an older cached report (previous day or earlier) → abbreviated
/// date + time so a stale file is never mistaken for today's.
func reportUpdatedTimeString(_ updatedAt: Date,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> String {
    if calendar.isDate(updatedAt, inSameDayAs: now) {
        return updatedAt.formatted(date: .omitted, time: .shortened)
    }
    return updatedAt.formatted(date: .abbreviated, time: .shortened)
}

/// Age of the cached macOS update result for the Updates card. Future or < 60 s => "just now".
func updatesAgeString(checkedAt: Date, now: Date = Date()) -> String {
    let age = now.timeIntervalSince(checkedAt)
    if age < 60 { return L.updatesCheckedJustNow }
    if age < 3600 { return L.updatesCheckedAgo("\(Int(age / 60)) \(L.uptimeUnitMinute)") }
    if age < 86_400 { return L.updatesCheckedAgo("\(Int(age / 3600)) \(L.uptimeUnitHour)") }
    return L.updatesCheckedAgo("\(Int(age / 86_400)) \(L.uptimeUnitDay)")
}

/// Age of the cached folder sizes for the Folders card. Future or < 60 s => "just now".
func folderSizesAgeString(countedAt: Date, now: Date = Date()) -> String {
    let age = now.timeIntervalSince(countedAt)
    if age < 60 { return L.foldersCountedJustNow }
    if age < 3600 { return L.foldersCountedAgo("\(Int(age / 60)) \(L.uptimeUnitMinute)") }
    if age < 86_400 { return L.foldersCountedAgo("\(Int(age / 3600)) \(L.uptimeUnitHour)") }
    return L.foldersCountedAgo("\(Int(age / 86_400)) \(L.uptimeUnitDay)")
}
