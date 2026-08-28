// Engine/ReportWriter.swift
// Report agent owns this file (SPEC §3, §7).
//
// Renders the text report (mirroring the legacy mac_checkup.sh / mac_report.txt layout)
// from structured data, and writes it atomically to disk. The report is BILINGUAL: every
// string goes through `L` / `L.reportSection*` (StringsEN/StringsRU via
// `L10nStore.shared.language`), so it renders in whichever language the app is set to.
// Pure rendering only — NO command execution / subprocess calls happen in this file.

import Foundation

enum ReportWriter {

    // MARK: - Public API (verbatim per SPEC §7 / integration contract)

    /// Renders the full text report from structured data, in the app's current language.
    static func render(report: FullReport, live: LiveSnapshot, history: HistoryState) -> String {
        // `history` is accepted for interface parity (integration phase depends on this
        // exact signature) but is intentionally NOT rendered into the text report: the
        // legacy mac_checkup.sh section list (mirrored below) has no history section —
        // history only ever lived in the separate mac_check_state.json file. The
        // History card (chart + table) is a UI-only feature per SPEC §8.
        _ = history

        var out = "\(L.reportCreatedAt(formatCreatedAt(report.createdAt ?? Date())))\n"

        addSection(&out, L.reportSectionSystem, renderSystem(report.system))
        addSection(&out, L.reportSectionDisk, renderDisk(live.disk))
        addSection(&out, L.reportSectionSnapshots, renderSnapshots(report.snapshots))
        addSection(&out, L.reportSectionHomeDirs, renderDirs(report.homeDirs, cap: 20, unreadable: report.homeDirsUnreadable))
        addSection(&out, L.reportSectionServiceDirs, renderDirs(report.serviceDirs, cap: nil, unreadable: report.serviceDirsUnreadable))
        addSection(&out, L.reportSectionMemory, renderMemory(live.mem, live.swap))
        addSection(&out, L.reportSectionTopMem, renderProcTable(live.topMem, primary: .mem))
        addSection(&out, L.reportSectionTopCPU, renderProcTable(live.topCPU, primary: .cpu))
        addSection(&out, L.reportSectionLoginItems, renderLoginItems(report.autostart))
        addSection(&out, L.reportSectionAgents, renderAgents(report.autostart))
        addSection(&out, L.reportSectionBackground, renderBackground(report.autostart))
        addSection(&out, L.reportSectionBattery, renderBattery(report.battery ?? live.battery))
        addSection(&out, L.reportSectionEnergy, renderEnergy(report.energy))
        addSection(&out, L.reportSectionSecurity, renderSecurity(report.security))
        addSection(&out, L.reportSectionTMDest, renderTMDest(report.tmDest))
        addSection(&out, "SPOTLIGHT", renderSpotlight(report.spotlight))
        addSection(&out, L.reportSectionCrashes, renderCrashes(report.crashes))
        addSection(&out, "HOMEBREW", renderBrew(report.brewVersion, report.brewOutdated))
        addSection(&out, L.reportSectionUpdates, renderUpdates(report.updates))
        addSection(&out, L.reportSectionSmart, renderSmart(report.smart))

        out += "\n===== \(L.reportDoneBanner) =====\n"
        out += "\(L.reportSavedTo(defaultReportPathForFooter()))\n"
        return out
    }

    /// Atomic overwrite (temp file + replace or Data.write(.atomic)). Creates parent dir.
    static func write(text: String, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = Data(text.utf8)
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Section plumbing

    private static func addSection(_ out: inout String, _ name: String, _ lines: [String]) {
        out += "\n===== \(name) =====\n"
        out += lines.joined(separator: "\n")
        out += "\n"
    }

    // MARK: - Footer path (§2/§7: ALWAYS the same fixed App Support path)

    /// Same fixed location as SPEC §2 (`~/Library/Application Support/MacDashboard/
    /// mac_report.txt`), recomputed here purely for display in the footer line —
    /// render() has no URL parameter, and this path is a spec-level constant derivable
    /// from standard APIs only (NSHomeDirectory(), explicitly allowed by SPEC §1.2),
    /// so there is no risk of drifting from the real write destination.
    private static func defaultReportPathForFooter() -> String {
        NSHomeDirectory() + "/Library/Application Support/MacDashboard/mac_report.txt"
    }

    // MARK: - Date formatting

    /// "Fri Jul  3 18:37:03 MSK 2026" — en_US_POSIX weekday/month, local TZ abbreviation,
    /// day-of-month space-padded to width 2 (matches legacy `date` output where a
    /// single-digit day produces a double space, e.g. "Jul  3").
    private static func formatCreatedAt(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current

        fmt.dateFormat = "EEE MMM"
        let head = fmt.string(from: date)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let day = cal.component(.day, from: date)
        let dayStr = day < 10 ? " \(day)" : "\(day)"

        fmt.dateFormat = "HH:mm:ss zzz yyyy"
        let tail = fmt.string(from: date)

        return "\(head) \(dayStr) \(tail)"
    }

    // MARK: - СИСТЕМА

    private static func renderSystem(_ system: SystemInfo?) -> [String] {
        guard let s = system else { return [L.sharedUnavailable] }
        var lines: [String] = []
        if let v = s.osName { lines.append("ProductName:\t\(v)") }
        if let v = s.osVersion { lines.append("ProductVersion:\t\(v)") }
        if let v = s.osBuild { lines.append("BuildVersion:\t\(v)") }
        if let v = s.modelName { lines.append("      Model Name: \(v)") }
        if let v = s.modelId { lines.append("      Model Identifier: \(v)") }
        if let v = s.chip { lines.append("      Chip: \(v)") }
        if let v = s.cores { lines.append("      Total Number of Cores: \(v)") }
        if let v = s.memBytes { lines.append("      Memory: \(fmtBytes(v))") }
        if let v = s.uptime { lines.append(L.reportUptime(v)) }
        return lines.isEmpty ? [L.sharedUnavailable] : lines
    }

    // MARK: - ДИСК

    /// df-like table. LiveSnapshot only carries a single DiskInfo (per SPEC §5.1, no
    /// `df` subprocess — volume resource-value APIs only), so dataUsed/sysUsed are
    /// optional extras: render a "/" row only when sysUsed is actually known, always
    /// render the Data-volume row (falling back to the derived usedTotal when the more
    /// precise dataUsed isn't populated).
    private static func renderDisk(_ disk: DiskInfo?) -> [String] {
        guard let d = disk else { return [L.sharedUnavailable] }
        var lines: [String] = []
        let header = padRight("Filesystem", 24) + padRight("Size", 9) + padRight("Used", 9)
            + padRight("Avail", 9) + padRight("Capacity", 10) + "Mounted on"
        lines.append(header)

        if let sysUsed = d.sysUsed {
            let pct = d.size > 0 ? Double(sysUsed) / Double(d.size) * 100 : 0
            lines.append(diskRow(name: "/", size: d.size, used: sysUsed, avail: d.avail, pct: pct, mount: "/"))
        }

        let dataUsed = d.dataUsed ?? d.usedTotal
        let dataPct = d.dataUsed != nil ? (d.size > 0 ? Double(dataUsed) / Double(d.size) * 100 : 0) : d.pct * 100
        lines.append(diskRow(
            name: "/System/Volumes/Data", size: d.size, used: dataUsed, avail: d.avail,
            pct: dataPct, mount: "/System/Volumes/Data"
        ))
        return lines
    }

    private static func diskRow(name: String, size: Int64, used: Int64, avail: Int64, pct: Double, mount: String) -> String {
        padRight(name, 24) + padRight(fmtBytes(size), 9) + padRight(fmtBytes(used), 9)
            + padRight(fmtBytes(avail), 9) + padRight(String(format: "%.0f%%", pct), 10) + mount
    }

    // MARK: - Snapshots / dirs (shared shape)

    private static func renderSnapshots(_ snapshots: [String]?) -> [String] {
        guard let s = snapshots else { return [L.sharedUnavailable] }
        if s.isEmpty { return [L.reportNone] }
        return s
    }

    // The exported text report is the one artefact the user shares; an FDA-truncated
    // folder list must not read as complete (V2-FDA-DEGRADE honesty, same statement
    // the UI already makes).
    private static func renderDirs(_ dirs: [DirSize]?, cap: Int?, unreadable: [String] = []) -> [String] {
        var lines: [String]
        if let d = dirs {
            lines = d.isEmpty ? [L.reportNone] : {
                let limited = cap.map { Array(d.prefix($0)) } ?? d
                return limited.map { padLeft(fmtBytes($0.bytes), 10) + "  " + $0.path }
            }()
        } else {
            lines = [L.sharedUnavailable]
        }
        if !unreadable.isEmpty {
            lines.append(L.storageFoldersNoFDA(unreadable.joined(separator: ", ")))
        }
        return lines
    }

    // MARK: - ПАМЯТЬ

    private static func renderMemory(_ mem: MemSnapshot?, _ swap: SwapInfo?) -> [String] {
        if mem == nil && swap == nil { return [L.sharedUnavailable] }
        var lines: [String] = []

        if let m = mem {
            lines.append("Mach Virtual Memory Statistics: (page size of \(m.pageSize) bytes)")
            lines.append(vmLine("Pages free", m.free, m.pageSize))
            lines.append(vmLine("Pages active", m.active, m.pageSize))
            lines.append(vmLine("Pages inactive", m.inactive, m.pageSize))
            lines.append(vmLine("Pages speculative", m.speculative, m.pageSize))
            lines.append(vmLine("Pages wired down", m.wired, m.pageSize))
            lines.append(vmLine("Pages purgeable", m.purgeable, m.pageSize))
            lines.append(vmLine("Pages occupied by compressor", m.compressor, m.pageSize))
            lines.append(vmLine("File-backed pages", m.fileBacked, m.pageSize))
        } else {
            lines.append("Mach Virtual Memory Statistics: \(L.sharedUnavailable)")
        }

        if let sw = swap {
            let total = String(format: "%.2fM", Double(sw.total) / 1_048_576.0)
            let used = String(format: "%.2fM", Double(sw.used) / 1_048_576.0)
            let free = String(format: "%.2fM", Double(sw.free) / 1_048_576.0)
            lines.append("vm.swapusage: total = \(total)  used = \(used)  free = \(free)")
        } else {
            lines.append("vm.swapusage: \(L.sharedUnavailable)")
        }
        return lines
    }

    private static func vmLine(_ label: String, _ bytes: Int64, _ pageSize: Int64) -> String {
        let pages = pageSize > 0 ? bytes / pageSize : 0
        return padRight(label + ":", 32) + padLeft("\(pages).", 10)
    }

    // MARK: - ТОП-10 процессов

    private enum ProcPrimary { case mem, cpu }

    private static func renderProcTable(_ entries: [ProcEntry], primary: ProcPrimary) -> [String] {
        let top10 = Array(entries.prefix(10))
        guard !top10.isEmpty else { return [L.sharedUnavailable] }
        var lines: [String] = []
        switch primary {
        case .mem:
            lines.append(padRight("MEM", 8) + padRight("%CPU", 7) + "COMMAND")
            for p in top10 {
                let mem = p.memBytes.map(fmtBytes) ?? "?"
                let cpu = p.cpu.map { String(format: "%.1f", $0) } ?? "?"
                lines.append(padRight(mem, 8) + padRight(cpu, 7) + p.name)
            }
        case .cpu:
            lines.append(padRight("%CPU", 7) + padRight("MEM", 8) + "COMMAND")
            for p in top10 {
                let cpu = p.cpu.map { String(format: "%.1f", $0) } ?? "?"
                let mem = p.memBytes.map(fmtBytes) ?? "?"
                lines.append(padRight(cpu, 7) + padRight(mem, 8) + p.name)
            }
        }
        return lines
    }

    // MARK: - АВТОЗАГРУЗКА

    private static func renderLoginItems(_ autostart: AutostartInfo?) -> [String] {
        guard let a = autostart else { return [L.sharedUnavailable] }
        guard let items = a.loginItems else { return [L.autostartNoPermission] }
        if items.isEmpty { return [L.reportNone] }
        return items
    }

    private static func renderAgents(_ autostart: AutostartInfo?) -> [String] {
        guard let a = autostart else { return [L.sharedUnavailable] }
        func names(_ items: [LaunchdPlistInfo]) -> [String] {
            items.map { info in
                let name = URL(fileURLWithPath: info.path).lastPathComponent
                return info.isOrphan ? "\(name) [ORPHAN]" : name
            }
        }
        var lines: [String] = [L.reportAgentsUserHeader]
        lines.append(contentsOf: a.userAgents.isEmpty ? [L.reportEmpty] : names(a.userAgents))
        lines.append(L.reportAgentsSystemHeader)
        lines.append(contentsOf: names(a.systemAgents))
        lines.append(contentsOf: names(a.systemDaemons))
        return lines
    }

    private static func renderBackground(_ autostart: AutostartInfo?) -> [String] {
        guard let a = autostart else { return [L.sharedUnavailable] }
        if a.background.isEmpty { return [L.reportNone] }
        var lines = [padRight("PID", 7) + "Label"]
        lines.append(contentsOf: a.background.map { padRight($0.pid, 7) + $0.label })
        return lines
    }

    // MARK: - БАТАРЕЯ

    private static func renderBattery(_ battery: BatteryInfo?) -> [String] {
        guard let b = battery else { return [L.reportNoBattery] }
        var lines: [String] = []
        lines.append(L.reportBatterySource(b.source ?? "?"))
        lines.append(L.reportBatteryCharge(b.charge.map { "\($0)%" } ?? "?"))
        lines.append(L.reportBatteryState(b.state ?? "?"))
        lines.append("Cycle Count: \(b.cycles.map(String.init) ?? "?")")
        lines.append("Condition: \(b.condition ?? "?")")
        lines.append("Maximum Capacity: \(b.maxCapacity.map { "\($0)%" } ?? "?")")
        return lines
    }

    // MARK: - НАСТРОЙКИ ЭНЕРГИИ

    private static func renderEnergy(_ energy: EnergySettings?) -> [String] {
        guard let e = energy else { return [L.sharedUnavailable] }
        var lines: [String] = ["Battery Power:"]
        lines.append(contentsOf: e.battery.map { " \($0.0) \($0.1)" })
        lines.append("AC Power:")
        lines.append(contentsOf: e.ac.map { " \($0.0) \($0.1)" })
        return lines
    }

    // MARK: - БЕЗОПАСНОСТЬ

    private static func renderSecurity(_ security: SecurityState?) -> [String] {
        guard let s = security else { return [L.sharedUnavailable] }
        func tri(_ v: Bool?) -> String { v == nil ? "?" : (v! ? "On" : "Off") }
        return [
            "FileVault: \(tri(s.fileVault))",
            "Gatekeeper: \(tri(s.gatekeeper))",
            "SIP: \(tri(s.sip))",
            "Firewall: \(tri(s.firewall))"
        ]
    }

    // MARK: - TIME MACHINE

    private static func renderTMDest(_ tmDest: TMDestination??) -> [String] {
        switch tmDest {
        case .none:
            return [L.reportTMNotChecked]
        case .some(.none):
            return [L.reportTMNotConfigured]
        case .some(.some(let dest)):
            var lines: [String] = []
            if let v = dest.name { lines.append("Name          : \(v)") }
            if let v = dest.kind { lines.append("Kind          : \(v)") }
            if let v = dest.mountPoint { lines.append("Mount Point   : \(v)") }
            if let v = dest.quotaBytes { lines.append("Quota         : \(fmtBytes(v))") }
            if let v = dest.lastBackup { lines.append(L.reportTMLastBackup(v)) }
            else if let v = dest.lastBackupUnavailableReason { lines.append(L.reportTMLastBackup(v.localizedText)) }
            return lines.isEmpty ? [L.reportTMNotConfigured] : lines
        }
    }

    // MARK: - SPOTLIGHT

    private static func renderSpotlight(_ spotlight: String?) -> [String] {
        guard let s = spotlight else { return [L.sharedUnavailable] }
        return [s]
    }

    // MARK: - КРАШИ

    private static func renderCrashes(_ crashes: [CrashGroup]?) -> [String] {
        guard let c = crashes else { return [L.sharedUnavailable] }
        if c.isEmpty { return [L.reportNone] }
        return c.prefix(15).map { L.maintenanceCrashRow($0.process, $0.count) }
    }

    // MARK: - HOMEBREW

    private static func renderBrew(_ version: String??, _ outdated: [String]?) -> [String] {
        switch version {
        case .none:
            return [L.reportNotChecked]
        case .some(.none):
            return [L.maintenanceBrewNotInstalled]
        case .some(.some(let v)):
            var lines = [v]
            if let out = outdated {
                lines.append(L.reportBrewOutdatedHeader)
                lines.append(contentsOf: out)
            }
            return lines
        }
    }

    // MARK: - ОБНОВЛЕНИЯ macOS

    private static func renderUpdates(_ updates: [String]?) -> [String] {
        guard let u = updates else { return [L.reportNotChecked] }
        if u.isEmpty { return ["No new software available."] }
        return u
    }

    // MARK: - SMART

    // NOTE: smartCriticalWarningRU lives at file scope below (not inside the enum) so it
    // stays a plain free function visible module-wide, matching the rest of this file's
    // top-level helpers. Kept here (Engine/ReportWriter.swift) rather than in Views/SharedUI.swift
    // because this file is also symlinked into the headless Checks/ target (see Package.swift),
    // which does not include the Views sources.

    private static func renderSmart(_ smart: [SmartDisk]?) -> [String] {
        guard let disks = smart else { return [L.sharedUnavailable] }
        if disks.isEmpty { return [L.reportNone] }
        var lines: [String] = []
        for disk in disks {
            lines.append(L.reportSmartDiskLine(disk.title, disk.device, smartLocalizedLabel(disk.status)))
            // Localize the attribute-name column before measuring width, so RU labels
            // (which run longer/shorter than the raw English ones) still align.
            let localizedAttrs = disk.attrs.map { (smartLocalizedLabel($0.0), $0.0, $0.1) }
            let width = localizedAttrs.map { $0.0.count }.max().map { $0 + 1 } ?? 0
            for (label, rawLabel, rawValue) in localizedAttrs {
                let value = rawLabel == "Critical Warning" ? smartCriticalWarningRU(rawValue) : rawValue
                lines.append("  " + padRight(label + ":", width + 2) + value)
            }
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
