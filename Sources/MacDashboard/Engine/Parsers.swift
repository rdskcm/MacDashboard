// Engine/Parsers.swift
// Collectors agent owns this file (SPEC §3, §5, §10).
//
// Pure, total, crash-proof text -> model parsers. These port the tolerance behavior
// of mac_dashboard.py's `parse_*` functions (lines 93-455 of the legacy script):
// parse only what matches, never throw, never index out of bounds, return nil/empty
// on garbage or absent input rather than guessing. No I/O, no state — every function
// here is a pure `String -> model` (or `String -> String -> model`) transform, which
// is what makes them cheaply unit-testable from MacDashboardChecks.
// The file also holds structured (JSON/plist) decoders: they take the raw stdout bytes as
// `Data`, are equally pure and total, and return nil, `[]` or `.undecodable` on any decode error.

import Foundation

enum Parsers {

    // MARK: - ps (process table)

    /// One row of `/bin/ps -axww -o pid=,rss=,time=,comm=`.
    struct PSRow: Equatable {
        var pid: Int32
        var name: String        // full basename (psCommandName), never truncation-marked
        var cpuSeconds: Double  // CUMULATIVE cpu time since the process started
        var memBytes: Int64     // RSS as `ps` printed it — NOT the footprint the UI shows;
                                // ProcessSampler substitutes `top`'s MEM column (all pids)
                                // and keeps this only for a row `top` didn't report
    }

    /// Parses `/bin/ps -axww -o pid=,rss=,time=,comm=` output (no header line — the
    /// `=` after each keyword suppresses it) into process rows. Pure, total: skips
    /// whatever it cannot parse rather than shifting columns or crashing.
    static func psProcesses(_ text: String) -> [PSRow] {
        var rows: [PSRow] = []
        for line in text.components(separatedBy: "\n") {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let fields = splitWhitespaceLimited(line, maxSplit: 3)
            guard fields.count == 4 else { continue }
            guard let pid = Int32(fields[0]), let rssKB = Int64(fields[1]),
                  let secs = psCPUSeconds(fields[2]) else { continue }
            let name = psCommandName(fields[3])
            guard !name.isEmpty else { continue }
            rows.append(PSRow(pid: pid, name: name, cpuSeconds: secs, memBytes: rssKB * 1024))
        }
        return rows
    }

    /// pid -> memory footprint in bytes, from `/usr/bin/top -l 1 -stats pid,command,mem`.
    ///
    /// Pure and total, structured like `duKilobyteLines`: a line counts only if its FIRST
    /// whitespace field is an integer pid, which drops top's whole banner (`Processes:`,
    /// `Load Avg:`, `PhysMem:`, the timestamp) and its `PID COMMAND MEM` header without
    /// pattern-matching any of them. MEM is the LAST field because COMMAND may contain
    /// spaces, and it is parsed by `parseSize`, which already handles top's K/M/G suffixes
    /// and its trailing `+`/`-` delta markers. A row whose MEM does not parse is simply
    /// absent from the result — its process keeps `ps` RSS rather than a bogus 0.
    static func topMemoryFootprints(_ text: String) -> [Int32: Int64] {
        var out: [Int32: Int64] = [:]
        for line in text.components(separatedBy: "\n") {
            let fields = splitWhitespaceLimited(line, maxSplit: 1)
            guard fields.count == 2, let pid = Int32(fields[0]) else { continue }
            guard let memToken = fields[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).last,
                  let bytes = parseSize(String(memToken)), bytes > 0 else { continue }
            out[pid] = bytes
        }
        return out
    }

    /// Parses macOS `ps`'s cumulative-time text (`%3ld:%02ld.%02ld` = `MMM:SS.hh`,
    /// with an optional `DD-` day prefix for very long-lived processes) to seconds.
    /// Minutes are NOT rolled into hours by `ps` — `145:22.35` is 2.4 hours printed
    /// as 145 minutes, not `2:25:22.35`.
    static func psCPUSeconds(_ token: String) -> Double? {
        guard !token.isEmpty else { return nil }
        var days = 0
        var rest = Substring(token)
        if let dashIdx = token.firstIndex(of: "-") {
            guard let d = Int(token[token.startIndex..<dashIdx]) else { return nil }
            days = d
            rest = token[token.index(after: dashIdx)...]
        }
        let parts = rest.components(separatedBy: ":")
        guard parts.count <= 3, !parts.isEmpty else { return nil }
        guard let seconds = Double(parts.last!) else { return nil }
        var hours = 0
        var minutes = 0
        if parts.count == 3 {
            guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            hours = h
            minutes = m
        } else if parts.count == 2 {
            guard let m = Int(parts[0]) else { return nil }
            minutes = m
        }
        return Double(days) * 86400 + Double(hours) * 3600 + Double(minutes) * 60 + seconds
    }

    /// Trims whitespace, strips one leading `(`/trailing `)` pair (how `ps` renders
    /// a process whose path it cannot read, e.g. `(bash)`), then keeps everything
    /// after the last `/` if a path is present. Does NOT cut at a space — an
    /// executable name may legitimately contain spaces.
    ///
    /// The result is the FULL basename, never marked as truncated: `ps -axww -o comm=`
    /// prints the whole path, unlike the `top -stats command` this sampler replaced,
    /// which hard-truncated COMMAND at 16 characters and needed a trailing "…" to say
    /// so. Visual overflow is the row's job — `.lineLimit(1).truncationMode(.tail)`,
    /// `ProcessCards.swift:344-348` (V2-RELEASE re-review [M1]).
    private static func psCommandName(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") && trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        if let slashIdx = trimmed.lastIndex(of: "/") {
            trimmed = String(trimmed[trimmed.index(after: slashIdx)...])
        }
        return trimmed
    }

    // MARK: - sizes ("62G", "228Gi", "4.0K", "0B", "545M+", "3808K-")

    /// Parses du/top-style human sizes (binary/IEC multiples) to bytes. Tolerant:
    /// unrecognized tokens return nil rather than throwing or defaulting to 0.
    static func parseSize(_ token: String) -> Int64? {
        var chars = Array(token.trimmingCharacters(in: .whitespaces))
        guard !chars.isEmpty else { return nil }

        if let last = chars.last, last == "+" || last == "-" {
            chars.removeLast()
        }
        if let last = chars.last, last == "B" || last == "b" {
            chars.removeLast()
        }
        if let last = chars.last, last == "i" || last == "I" {
            chars.removeLast()
        }
        var multiplier: Double = 1
        if let last = chars.last, "KMGTPEkmgtpe".contains(last) {
            switch last.uppercased() {
            case "K": multiplier = Double(1 << 10)
            case "M": multiplier = Double(1 << 20)
            case "G": multiplier = Double(1 << 30)
            case "T": multiplier = Double(1 << 40)
            case "P": multiplier = Double(1 << 50)
            case "E": multiplier = Double(1 << 60)
            default: break
            }
            chars.removeLast()
        }
        let numberPart = String(chars).trimmingCharacters(in: .whitespaces)
        guard !numberPart.isEmpty, let value = Double(numberPart) else { return nil }
        return Int64((value * multiplier).rounded())
    }

    /// `du -xk` output: "<kilobytes>\t<path>" (plain integers, no unit suffix — the
    /// Swift rewrite deliberately uses `-k` instead of legacy's `-h` to avoid
    /// human-readable-size precision loss). Not in the "needed at minimum" list but
    /// cheap, testable, and keeps ReportCollector free of ad-hoc parsing.
    static func duKilobyteLines(_ text: String) -> [DirSize] {
        var results: [DirSize] = []
        for rawLine in text.components(separatedBy: "\n") {
            let fields = splitWhitespaceLimited(rawLine, maxSplit: 1)
            guard fields.count == 2, let kib = Int64(fields[0]) else { continue }
            let path = fields[1].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            results.append(DirSize(path: path, bytes: kib * 1024))
        }
        return results
    }

    // MARK: - swap ("vm.swapusage: total = 2048.00M  used = 430.44M  free = 1617.56M  (encrypted)")

    static func swapUsage(line: String) -> SwapInfo? {
        guard let total = doubleAfter("total = ", in: line),
              let used = doubleAfter("used = ", in: line),
              let free = doubleAfter("free = ", in: line) else { return nil }
        let mib = 1024.0 * 1024.0
        return SwapInfo(total: Int64(total * mib), used: Int64(used * mib), free: Int64(free * mib))
    }

    private static func doubleAfter(_ label: String, in text: String) -> Double? {
        guard let range = text.range(of: label) else { return nil }
        let rest = text[range.upperBound...].drop { $0 == " " }
        let numChars = rest.prefix { $0.isNumber || $0 == "." }
        guard !numChars.isEmpty else { return nil }
        return Double(numChars)
    }

    // MARK: - battery (`pmset -g batt`)

    private static var pmsetBatteryStates: [String: String] {
        [
            "charging": L.battStateCharging,
            "discharging": L.battStateDischarging,
            "charged": L.battStateCharged,
            "finishing charge": L.battStateFinishingCharge
        ]
    }

    /// Parses `pmset -g batt` output. Returns nil if no battery-related field was
    /// found at all (desktop Mac, or garbage input).
    static func batteryPmset(_ text: String) -> BatteryInfo? {
        var source: String?
        var charge: Int?
        var state: String?

        for line in text.components(separatedBy: "\n") {
            if let openRange = line.range(of: "Now drawing from '") {
                let afterOpen = line[openRange.upperBound...]
                if let closeIdx = afterOpen.firstIndex(of: "'") {
                    let src = String(afterOpen[afterOpen.startIndex..<closeIdx])
                    source = src.contains("AC") ? L.battSourceAC : L.battSourceBattery
                }
            }
            guard line.contains("InternalBattery"), let pctSemi = line.range(of: "%;") else { continue }

            let before = line[line.startIndex..<pctSemi.lowerBound]
            let digits = before.reversed().prefix { $0.isNumber }
            if !digits.isEmpty {
                charge = Int(String(digits.reversed()))
            }

            let afterPct = line[pctSemi.upperBound...]
            let clauses = afterPct.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            let firstClause = clauses.first ?? ""
            if firstClause == "AC attached", clauses.count > 1, clauses[1] == "not charging" {
                // Real pmset output splits this state across TWO semicolon clauses
                // ("...; AC attached; not charging; ...") — legacy's single-clause
                // regex can't reach its own "не заряжается" dict entry for this
                // exact reason; special-cased here so it actually triggers.
                state = L.battStateNotCharging
            } else if !firstClause.isEmpty {
                state = pmsetBatteryStates[firstClause] ?? firstClause
            }
        }

        guard source != nil || charge != nil || state != nil else { return nil }
        return BatteryInfo(source: source, charge: charge, state: state, cycles: nil, condition: nil, maxCapacity: nil)
    }

    /// Parses the Cycle Count / Condition / Maximum Capacity lines grepped from
    /// `system_profiler SPPowerDataType` (ReportCollector's battery section merges
    /// this with `batteryPmset`'s source/charge/state).
    static func batteryPowerProfile(_ text: String) -> (cycles: Int?, condition: String?, maxCapacity: Int?) {
        var cycles: Int?
        var condition: String?
        var maxCapacity: Int?
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let r = line.range(of: "Cycle Count:") {
                let digits = line[r.upperBound...].trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
                cycles = Int(digits)
            } else if let r = line.range(of: "Condition:") {
                let value = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                condition = value.isEmpty ? nil : value
            } else if let r = line.range(of: "Maximum Capacity:") {
                let digits = line[r.upperBound...].trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
                maxCapacity = Int(digits)
            }
        }
        return (cycles, condition, maxCapacity)
    }

    // MARK: - system (SystemVersion.plist / system_profiler -json SPHardwareDataType / uptime)

    static func systemVersion(plist data: Data) -> SystemInfo? {
        struct Plist: Decodable {
            var ProductName: String?
            var ProductVersion: String?
            var ProductBuildVersion: String?
        }
        guard let p = try? PropertyListDecoder().decode(Plist.self, from: data) else { return nil }
        var info = SystemInfo()
        info.osName = p.ProductName
        info.osVersion = p.ProductVersion
        info.osBuild = p.ProductBuildVersion
        return info
    }

    /// Decodes `system_profiler -json SPHardwareDataType` (first item). Apple Silicon has
    /// `chip_type`, Intel has `cpu_type`. `number_processors` is an Int (Intel) or a
    /// "proc T:P:E" / "proc T:0:P:E" string (Apple Silicon); any other shape gives nil cores.
    static func hardwareProfile(json data: Data) -> SystemInfo? {
        enum CoreCount: Decodable {
            case count(Int), tiers(String)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let n = try? c.decode(Int.self) { self = .count(n); return }
                self = .tiers(try c.decode(String.self))
            }
        }
        struct Item: Decodable {
            var machine_name: String?
            var machine_model: String?
            var chip_type: String?
            var cpu_type: String?
            var physical_memory: String?
            var number_processors: CoreCount?
        }
        struct Root: Decodable { var SPHardwareDataType: [Item] }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let item = root.SPHardwareDataType.first else { return nil }
        var info = SystemInfo()
        info.modelName = item.machine_name
        info.modelId = item.machine_model
        info.chip = item.chip_type ?? item.cpu_type
        info.memBytes = item.physical_memory.flatMap(parseWholeGBString)
        switch item.number_processors {
        case .count(let n)?: info.cores = "\(n)"
        case .tiers(let s)?:
            // exactly "proc T:P:E" or "proc T:0:P:E"; the meaning of the 0 field is unverified
            let re = #"^proc (\d+):(?:0:)?(\d+):(\d+)$"#
            if let m = s.range(of: re, options: .regularExpression) {
                let nums = s[m].dropFirst(5).split(separator: ":").compactMap { Int($0) }
                if nums.count >= 3 {
                    info.cores = "\(nums[0]) (\(nums[nums.count - 2]) Performance and \(nums[nums.count - 1]) Efficiency)"
                }
            }
        case nil: break
        }
        return info
    }

    private static func parseWholeGBString(_ s: String) -> Int64? {
        let digits = s.prefix { $0.isNumber }
        guard !digits.isEmpty, let gb = Int64(digits) else { return nil }
        return gb * (1 << 30)
    }

    /// `uptime` output → human duration in the app's current language ("2 дн 3 мин" /
    /// "10 дн 22 ч 32 мин" under RU, "2 d 3 min" / "10 d 22 h 32 min" under EN). Units come
    /// from `L.uptimeUnitDay/Hour/Minute/Second` + `L.uptimeHourMinuteCombo`, not from
    /// literals. The RU abbreviations port legacy `_ru_uptime` (mac_dashboard.py lines
    /// 163-178) verbatim in their choice — дн/ч/мин/с are grammatically number-agnostic,
    /// unlike a spelled-out "дня/дней" which legacy deliberately avoids.
    static func uptimeHuman(_ text: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            guard line.contains(" up "), line.contains("load average") else { continue }
            guard let uptimeSegment = firstRegexGroup(
                in: line,
                pattern: #"\bup\s+(.*?),\s*\d+\s+users?"#
            ) else { continue }
            return ruUptime(uptimeSegment)
        }
        return nil
    }

    private static func ruUptime(_ s: String) -> String {
        let unitMap = ["day": L.uptimeUnitDay, "hr": L.uptimeUnitHour, "hour": L.uptimeUnitHour,
                       "min": L.uptimeUnitMinute, "sec": L.uptimeUnitSecond]
        var parts: [String] = []
        for rawPart in s.components(separatedBy: ",") {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            if let (num, unit) = matchDayUnit(part), let ru = unitMap[unit] {
                parts.append("\(num) \(ru)")
            } else if let (h, mm) = matchHourMinute(part) {
                parts.append(L.uptimeHourMinuteCombo(h, mm))
            } else {
                parts.append(part)
            }
        }
        return parts.isEmpty ? s : parts.joined(separator: " ")
    }

    private static func matchDayUnit(_ part: String) -> (String, String)? {
        guard let m = firstRegexMatch(in: part, pattern: #"^(\d+)\s+([a-z]+?)s?$"#), m.count >= 3 else { return nil }
        return (m[1], m[2])
    }

    private static func matchHourMinute(_ part: String) -> (Int, Int)? {
        guard let m = firstRegexMatch(in: part, pattern: #"^(\d+):(\d\d)$"#), m.count >= 3,
              let h = Int(m[1]), let mm = Int(m[2]) else { return nil }
        return (h, mm)
    }

    // MARK: - Time Machine (`tmutil destinationinfo -X`)

    /// Decodes `tmutil destinationinfo -X`; only the first destination is used.
    static func tmDestination(plist data: Data) -> TMDestinationResult {
        if String(decoding: data, as: UTF8.self).lowercased().contains("no destinations configured") {
            return .notConfigured
        }
        struct Quota: Decodable {
            var value: Double
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let i = try? c.decode(Int.self) { value = Double(i) } else { value = try c.decode(Double.self) }
            }
        }
        struct Entry: Decodable {
            var Name: String?
            var Kind: String?
            var MountPoint: String?
            var QuotaGB: Quota?
        }
        struct Root: Decodable { var Destinations: [Entry]? }
        guard let root = try? PropertyListDecoder().decode(Root.self, from: data) else { return .undecodable }
        guard let first = root.Destinations?.first else { return .notConfigured }
        if first.Name == nil && first.Kind == nil && first.MountPoint == nil && first.QuotaGB == nil {
            return .undecodable
        }
        let gb = first.QuotaGB?.value ?? 0
        return .configured(TMDestination(name: first.Name, kind: first.Kind, mountPoint: first.MountPoint,
                                         quotaBytes: gb > 0 ? Int64((gb * 1e9).rounded()) : nil, lastBackup: nil))
    }

    /// Extracts the trailing `YYYY-MM-DD-HHMMSS` timestamp from a `tmutil
    /// latestbackup` path (e.g.
    /// ".../2026-07-12-230458.backup/2026-07-12-230458.backup") and parses it as a
    /// local-time `Date`. `tmutil`'s path timestamps are local wall-clock time, not
    /// UTC (verified empirically: a path timestamp of 23:04:58 matched a
    /// `SnapshotDates` entry of 20:04:58 UTC at the local UTC+3 offset in effect).
    /// `timeZone` is injectable so tests are deterministic regardless of the CI
    /// machine's zone.
    static func tmLatestBackupDate(fromPath path: String, timeZone: TimeZone = .current) -> Date? {
        let name = (path as NSString).lastPathComponent
        guard let stamp = firstRegexGroup(in: name, pattern: #"(\d{4}-\d{2}-\d{2}-\d{6})"#) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return fmt.date(from: stamp)
    }

    /// Outcome of parsing `diskutil apfs listSnapshots <mount>` output, distinguishing
    /// "ran fine, found a date", "ran fine, zero completed backups exist" and "output
    /// doesn't look like a diskutil snapshot listing at all" — the last case is a
    /// safety net for a genuinely failed/unavailable `diskutil` invocation — but not an
    /// unreachable one: a clean exit with empty stdout now reaches this parser as `""`
    /// (⇒ `CommandRunner.run` no longer returns nil for that case) and lands here.
    enum TMDestinationResult: Equatable {
        case configured(TMDestination), notConfigured, undecodable
    }

    enum DiskutilBackupSnapshotResult: Equatable {
        case found(Date)
        case noBackupsFound
        case unparseable
    }

    /// Parses `diskutil apfs listSnapshots <mount>` output for the latest Time
    /// Machine BACKUP snapshot's timestamp. This works WITHOUT Full Disk Access —
    /// `diskutil` goes through diskarbitrationd, a different privilege gate than
    /// the VFS/TCC path that blocks `tmutil latestbackup` and any direct read
    /// under the destination volume or the TimeMachine plist (verified
    /// empirically on an FDA-denied build of this app). Only `.backup`-suffixed
    /// snapshot names are considered — per tmutil(8) terminology a "backup" is an
    /// increment on the DESTINATION volume, distinct from a ".local"-suffixed
    /// LOCAL snapshot on the source Mac (handled separately by `collectSnapshots`
    /// in ReportCollector; deliberately not conflated here).
    ///
    /// A recognizable diskutil listing is either a "No snapshots for <disk>" line
    /// (empirically confirmed output for a mounted APFS volume with zero snapshots)
    /// or a "Snapshot(s) for <disk> (<N> found)" header (singular for one snapshot,
    /// plural otherwise — both forms observed empirically). If such a header/line is
    /// present but no `.backup`-suffixed snapshot name parses to a date, that's a
    /// real "zero completed backups" result, not a parse failure.
    static func tmDiskutilLatestBackupDate(_ text: String, timeZone: TimeZone = .current) -> DiskutilBackupSnapshotResult {
        var latest: Date?
        var sawRecognizedListing = false
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.range(of: #"^No snapshots for \S+"#, options: .regularExpression) != nil {
                sawRecognizedListing = true
                continue
            }
            if line.range(of: #"^Snapshots? for \S+ \(\d+ found\)"#, options: .regularExpression) != nil {
                sawRecognizedListing = true
                continue
            }
            guard let r = line.range(of: "Name:") else { continue }
            let name = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            guard name.hasSuffix(".backup") else { continue }
            guard let date = tmLatestBackupDate(fromPath: name, timeZone: timeZone) else { continue }
            if latest == nil || date > latest! { latest = date }
        }
        if let latest { return .found(latest) }
        return sawRecognizedListing ? .noBackupsFound : .unparseable
    }

    /// Latest date in the FIRST destination's `SnapshotDates` array of a parsed
    /// `/Library/Preferences/com.apple.TimeMachine.plist` root dictionary — the
    /// fallback source when `tmutil latestbackup` yields nothing (typically no
    /// Full Disk Access). Only the first destination is read, matching
    /// `tmDestination`'s "first entry is fine" behavior (this repo doesn't
    /// correlate destinations by ID since `destinationinfo` also only surfaces the
    /// first block). Deliberately reads `SnapshotDates`, NOT
    /// `ReferenceLocalSnapshotDate`/`StableLocalSnapshotDate` — those describe the
    /// LOCAL snapshot kept on the source Mac, a different concept from the
    /// external destination's backup history that this function targets.
    static func tmPlistLatestSnapshotDate(_ root: [String: Any]) -> Date? {
        guard let destinations = root["Destinations"] as? [[String: Any]],
              let first = destinations.first,
              let dates = first["SnapshotDates"] as? [Date] else { return nil }
        return dates.max()
    }

    /// "16.07.2026, 10:50" — Russian-locale day.month.year + 24h time, used for the
    /// TM card's "Последний бэкап" value regardless of which source (tmutil path
    /// timestamp vs plist `SnapshotDates`) produced the `Date`.
    static func formatTMBackupDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.timeZone = timeZone
        fmt.dateFormat = "dd.MM.yyyy, HH:mm"
        return fmt.string(from: date)
    }

    // MARK: - disks (diskutil / smartctl)

    /// `diskutil info -plist <dev>` → SMART status + media/model name, when present.
    static func diskutilSmart(plist data: Data) -> (status: String?, mediaName: String?) {
        struct Info: Decodable {
            var SMARTStatus: String?
            var MediaName: String?
        }
        guard let i = try? PropertyListDecoder().decode(Info.self, from: data) else { return (nil, nil) }
        return (i.SMARTStatus, i.MediaName)
    }

    /// `diskutil list -plist external physical` → `/dev/diskN` for every whole disk.
    static func externalPhysicalDisks(plist data: Data) -> [String] {
        struct List: Decodable { var WholeDisks: [String] }
        guard let l = try? PropertyListDecoder().decode(List.self, from: data) else { return [] }
        return l.WholeDisks.map { "/dev/" + $0 }
    }

    /// Extracts the 9 NVMe attrs (SPEC §5.2) from `smartctl -A -j` output, in a fixed
    /// canonical order. ATA disks, error documents and non-JSON output give `[]`.
    static func smartctlAttrs(json data: Data) -> [(String, String)] {
        struct Log: Decodable {
            var critical_warning: UInt64?
            var temperature: Int64?
            var available_spare: UInt64?
            var percentage_used: UInt64?
            var power_cycles: UInt64?
            var power_on_hours: UInt64?
            var unsafe_shutdowns: UInt64?
            var media_errors: UInt64?
            var num_err_log_entries: UInt64?
        }
        struct Root: Decodable { var nvme_smart_health_information_log: Log? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let log = root.nvme_smart_health_information_log else { return [] }
        var rows: [(String, String)] = []
        if let v = log.critical_warning { rows.append(("Critical Warning", String(format: "0x%02x", v))) }
        rows.append(("Temperature", log.temperature.map { "\($0) Celsius" } ?? "-"))
        if let v = log.available_spare { rows.append(("Available Spare", "\(v)%")) }
        if let v = log.percentage_used { rows.append(("Percentage Used", "\(v)%")) }
        if let v = log.power_cycles { rows.append(("Power Cycles", groupedThousands(v))) }
        if let v = log.power_on_hours { rows.append(("Power On Hours", groupedThousands(v))) }
        if let v = log.unsafe_shutdowns { rows.append(("Unsafe Shutdowns", groupedThousands(v))) }
        if let v = log.media_errors { rows.append(("Media and Data Integrity Errors", groupedThousands(v))) }
        if let v = log.num_err_log_entries { rows.append(("Error Information Log Entries", groupedThousands(v))) }
        return rows
    }

    /// Locale-independent "1,234,567" (smartctl's own form under LC_ALL=C).
    private static func groupedThousands(_ v: UInt64) -> String {
        let digits = Array(String(v))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return out
    }

    // MARK: - launchctl (`launchctl list`, non-Apple only)

    /// Filters out Apple-owned labels, strips the "application." prefix and a
    /// trailing ".NNN.NNN" instance-id suffix that macOS appends to app-derived
    /// jobs, and dedupes (post-cleanup, matching legacy's comment that duplicates
    /// only appear *after* suffix-stripping and aren't interesting before that).
    static func launchctlNonApple(_ text: String) -> [(pid: String, label: String)] {
        var seen = Set<String>()
        var results: [(pid: String, label: String)] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let fields = line.contains("\t")
                ? line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
                : splitWhitespaceLimited(line, maxSplit: 2)
            guard fields.count >= 3 else { continue }
            let pid = fields[0]
            guard pid != "PID" else { continue }  // header row
            var label = fields[2]
            guard !label.isEmpty, !label.lowercased().contains("com.apple.") else { continue }
            if label.hasPrefix("application.") {
                label.removeFirst("application.".count)
            }
            label = stripTrailingNumericSuffix(label)
            guard !label.isEmpty, seen.insert(label).inserted else { continue }
            results.append((pid: pid, label: label))
        }
        return results
    }

    private static func stripTrailingNumericSuffix(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\.\d+\.\d+$"#) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    // MARK: - energy (`pmset -g custom`)

    /// One pmset key is genuinely multi-word ("Sleep On Power Button") while every
    /// other key is a single token; legacy's single-token-key regex mis-splits that
    /// one line (key="Sleep", value="On Power Button 1"). Special-cased here since
    /// it's purely display data and getting the one known exception right is cheap.
    private static let knownMultiWordPmsetKeys = ["Sleep On Power Button"]

    static func pmsetCustom(_ text: String) -> EnergySettings {
        enum Bucket { case none, battery, ac }
        var battery: [(String, String)] = []
        var ac: [(String, String)] = []
        var bucket: Bucket = .none

        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Battery Power:") { bucket = .battery; continue }
            if trimmed.hasPrefix("AC Power:") { bucket = .ac; continue }
            guard bucket != .none else { continue }
            // Legacy requires an indented "key value" line (`^\s+\S+\s+.+$`).
            guard let first = rawLine.first, first == " " || first == "\t" else { continue }
            guard let pair = splitPmsetKeyValue(trimmed) else { continue }
            switch bucket {
            case .battery: battery.append(pair)
            case .ac: ac.append(pair)
            case .none: break
            }
        }
        return EnergySettings(battery: battery, ac: ac)
    }

    private static func splitPmsetKeyValue(_ trimmedLine: String) -> (String, String)? {
        for key in knownMultiWordPmsetKeys where trimmedLine.hasPrefix(key + " ") {
            let value = String(trimmedLine.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            return (key, value)
        }
        let fields = splitWhitespaceLimited(trimmedLine, maxSplit: 1)
        guard fields.count == 2, !fields[1].isEmpty else { return nil }
        return (fields[0], fields[1])
    }

    // MARK: - security (fdesetup / spctl / csrutil / socketfilterfw)

    static func fileVaultStatus(_ text: String) -> Bool? {
        let lower = text.lowercased()
        if lower.contains("filevault is on") { return true }
        if lower.contains("filevault is off") { return false }
        return nil
    }

    static func gatekeeperStatus(_ text: String) -> Bool? {
        let lower = text.lowercased()
        if lower.contains("assessments enabled") { return true }
        if lower.contains("assessments disabled") { return false }
        return nil
    }

    static func sipStatus(_ text: String) -> Bool? {
        let lower = text.lowercased()
        if lower.contains("enabled") { return true }
        if lower.contains("disabled") { return false }
        return nil
    }

    /// Covers both socketfilterfw's prose ("Firewall is enabled."/"disabled") and
    /// the numeric `defaults read com.apple.alf globalstate` fallback (0 = off,
    /// 1/2 = on), matching legacy's combined interpretation.
    static func firewallStatus(_ text: String) -> Bool? {
        let lower = text.lowercased()
        if lower.contains("enabled") { return true }
        if lower.contains("disabled") { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed) { return n >= 1 }
        if let r = trimmed.range(of: "State = ") {
            let numPart = trimmed[r.upperBound...].prefix { $0.isNumber }
            if let n = Int(numPart) { return n >= 1 }
        }
        return nil
    }

    // MARK: - login items (osascript System Events)

    /// osascript returns one comma-separated line of item names; an AppleScript
    /// error (no Automation permission) is reported as text starting with "(".
    static func loginItems(_ text: String) -> [String]? {
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("(") { return nil }
            return line.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    // MARK: - generic string utilities

    /// Mirrors Python's `str.split(None, maxSplit)`: splits on runs of
    /// space/tab, collapsing consecutive separators, for at most `maxSplit` splits
    /// — the final piece keeps whatever remains verbatim (including any internal
    /// whitespace), which matters for `top`'s COMMAND column and pmset's value
    /// column.
    static func splitWhitespaceLimited(_ line: String, maxSplit: Int) -> [String] {
        var pieces: [String] = []
        var remainder = Substring(line)
        func dropLeadingWhitespace() {
            while let f = remainder.first, f == " " || f == "\t" { remainder = remainder.dropFirst() }
        }
        while pieces.count < maxSplit {
            dropLeadingWhitespace()
            guard !remainder.isEmpty else { return pieces }
            if let idx = remainder.firstIndex(where: { $0 == " " || $0 == "\t" }) {
                pieces.append(String(remainder[..<idx]))
                remainder = remainder[idx...]
            } else {
                pieces.append(String(remainder))
                return pieces
            }
        }
        dropLeadingWhitespace()
        if !remainder.isEmpty {
            pieces.append(String(remainder))
        }
        return pieces
    }

    /// Group-1 capture of the first regex match, or nil. Uses NSRegularExpression
    /// (ICU backtracking engine — same non-greedy semantics as Python's `re`) rather
    /// than hand-rolled scanning for the handful of patterns where that's the clearer
    /// and more obviously-correct choice (uptime parsing).
    private static func firstRegexGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// All capture groups (index 0 = whole match) of the first regex match, or nil.
    private static func firstRegexMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }
}
