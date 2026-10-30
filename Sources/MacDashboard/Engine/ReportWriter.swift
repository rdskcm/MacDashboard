// Engine/ReportWriter.swift
//
// Renders the short text report (title, generated line, eight aligned rows, optional
// parse-failure tail) from `ReportSummaryInput` values and writes it atomically to disk.
// The same string is shown in the Report sheet, copied by Copy and stored in
// mac_report.txt. BILINGUAL: every string goes through `L` (StringsEN/StringsRU).
// Pure rendering only — NO command execution / subprocess calls happen in this file.

import Foundation

/// Everything the short report needs, as values. Built by AppModel (live pass) and VisualFixture.
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
    var details: ReportDetails?        // non-nil: the full diagnostic sections follow the summary
}

/// The data behind the full diagnostic sections appended under the summary.
struct ReportDetails {
    var report: FullReport
    var live: LiveSnapshot
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
        if let d = i.details { appendDetails(&out, report: d.report, live: d.live) }
        let unparsed = i.parseFailures.sorted { $0.commandLine < $1.commandLine }
        if !unparsed.isEmpty { addSection(&out, L.reportSectionUnparsed, renderParseFailures(unparsed)) }
        return out
    }

    /// The full diagnostic sections (the pre-redesign report body), appended under the summary.
    private static func appendDetails(_ out: inout String, report: FullReport, live: LiveSnapshot) {
        addSection(&out, L.reportSectionSystem, renderSystem(report.system))
        addSection(&out, L.reportSectionDisk, renderDisk(live.disk))
        addSection(&out, L.reportSectionSnapshots, renderSnapshots(report.snapshots))
        addSection(&out, L.reportSectionHomeDirs, renderDirs(report.homeDirs, cap: 20, unreadable: report.homeDirsUnreadable, notMeasured: report.homeDirsNotMeasured, countedAt: report.folderSizesCountedAt))
        addSection(&out, L.reportSectionServiceDirs, renderDirs(report.serviceDirs, cap: nil, unreadable: report.serviceDirsUnreadable, notMeasured: report.serviceDirsNotMeasured, countedAt: report.folderSizesCountedAt))
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
        addSection(&out, "HOMEBREW", renderBrew(report.brewStatus, report.brewOutdated))
        addSection(&out, L.reportSectionUpdates, renderUpdates(report.updates, checkedAt: report.updatesCheckedAt))
        addSection(&out, L.reportSectionSmart, renderSmart(report.smart))
        addSection(&out, L.reportSectionTimings, renderTimings(report))
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
    // the UI already makes); the same holds for a list cut short by the count's
    // deadline (SERVICE-DIRS-TIMEOUT): the not-measured line comes before the unreadable one.
    private static func renderDirs(_ dirs: [DirSize]?, cap: Int?, unreadable: [String] = [], notMeasured: [String] = [], countedAt: Date? = nil) -> [String] {
        var lines: [String]
        if let d = dirs {
            lines = d.isEmpty ? [L.reportNone] : {
                let limited = cap.map { Array(d.prefix($0)) } ?? d
                return limited.map { padLeft(fmtBytes($0.bytes), 10) + "  " + $0.path }
            }()
        } else {
            lines = [L.sharedUnavailable]
        }
        if !notMeasured.isEmpty {
            lines.append(L.storageFoldersNotMeasured(notMeasured.joined(separator: ", ")))
        }
        if !unreadable.isEmpty {
            lines.append(L.storageFoldersNoFDA(unreadable.joined(separator: ", ")))
        }
        if dirs != nil, let at = countedAt {
            lines.append(L.reportFoldersCountedAt(reportUpdatedTimeString(at)))
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

    private static func renderBrew(_ status: BrewStatus?, _ outdated: [String]?) -> [String] {
        switch status {
        case .none:
            return [L.reportNotChecked]
        case .some(.notInstalled):
            return [L.maintenanceBrewNotInstalled]
        case .some(.installed(let v)):
            var lines = [v ?? L.maintenanceBrewVersionUnknown]
            if let out = outdated {
                lines.append(L.reportBrewOutdatedHeader)
                lines.append(contentsOf: out)
            } else {
                lines.append(L.maintenanceBrewOutdatedCheckFailed)
            }
            return lines
        }
    }

    // MARK: - ОБНОВЛЕНИЯ macOS

    private static func renderUpdates(_ updates: [SoftwareUpdate]?, checkedAt: Date?) -> [String] {
        guard let u = updates else { return [L.reportNotChecked] }
        var lines = u.isEmpty ? ["No new software available."] : u.map { item in
            var line = item.title
            if let v = item.version, !item.title.contains(v) { line += " \(v)" }
            if let size = item.sizeBytes { line += " — \(fmtBytes(size))" }
            if item.restartRequired { line += ", " + L.secRestartRequired }
            return line
        }
        if let at = checkedAt { lines.append(L.reportUpdatesCheckedAt(reportUpdatedTimeString(at))) }
        return lines
    }

    // MARK: - COLLECTION TIMES

    private static func renderTimings(_ r: FullReport) -> [String] {
        var lines: [String] = []
        if let p = r.passDuration { lines.append(L.reportTimingsPass(fmtSeconds(p))) }
        let entries = r.sectionDurations.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let labeled = entries.map { (ReportSection(rawValue: $0.key).map(L.reportTimingsSectionName) ?? $0.key, $0.value) }
        let w = (labeled.map { $0.0.count }.max() ?? 0) + 2
        for (label, v) in labeled { lines.append("  " + padRight(label + ":", w) + fmtSeconds(v)) }
        if let d = r.updatesCheckDuration, let at = r.updatesCheckedAt {
            lines.append(L.reportTimingsUpdates(fmtSeconds(d), reportUpdatedTimeString(at)))
        }
        if let d = r.folderSizesCountDuration, let at = r.folderSizesCountedAt {
            lines.append(L.reportTimingsFolderSizes(fmtSeconds(d), reportUpdatedTimeString(at)))
        }
        if lines.isEmpty { return [L.reportNone] }
        return [L.reportTimingsNote] + lines
    }

    // MARK: - SMART

    // NOTE: smartCriticalWarningRU lives at file scope below (not inside the enum) so it
    // stays a plain free function visible module-wide, matching the rest of this file's
    // top-level helpers. Kept here (Engine/ReportWriter.swift) rather than in Views/SharedUI.swift
    // so the Engine layer does not depend on Views.

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

    static func fmtSeconds(_ s: TimeInterval) -> String {
        String(format: "%.1f", max(0, s)).replacingOccurrences(of: ".", with: L.decimalSeparator)
            + " " + L.uptimeUnitSecond
    }

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

// MARK: - Report staleness caption time (pure; covered by Tests/MacDashboardTests)

/// Formats the "updated at" time for the Report sheet's staleness caption.
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
