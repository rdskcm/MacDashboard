// Engine/HomeModel.swift
// REDESIGN-HOME (stage A): everything the Home page derives from the assessment and the model
// data, as pure static functions over values — tasks, status pill, scan state, "You can" chips,
// the eight section tiles. Foundation only; covered by Tests/MacDashboardTests/HomeModelTests.
// Views must not re-derive labels (`shared-vocabulary`).

import Foundation

/// Views map: green→DS3.green/greenInk, amber→amber/amberInk, hot→hot/hotInk, neutral→muted/inkSoft.
enum HomeTone: Equatable, Sendable { case green, neutral, amber, hot }

struct HomeTask: Identifiable, Equatable {
    let id: String            // AttentionItem.id
    let kind: AttentionKind
    let tone: HomeTone        // .hot for crit/serious, .amber for warn
    let object: String        // «Disk», «caffeinate», «macOS 26.1.1»
    let state: String         // «87% full» — drawn in tone-ink after the object
    let section: Page
    let destination: Destination
    let verb: String?         // nil = no button (SIP)
    let help: String          // tooltip: SIP → homeSipHelp, else item.fullText
    let tileTag: String       // the section tile's tag text when this task is the section's first
    let legacyAction: AdviceAction?   // item.action (used only by decision 1 option A)
    let wakeHolderKeys: [WakeHolderKey]
}

struct HomeChip: Identifiable, Equatable {
    let id: String
    let object: String
    let value: String?
    let destination: Destination
}

/// `tone` nil = DS3.ink, .hot = hotInk, .amber = amberInk, .neutral = muted.
struct HomeKV: Equatable {
    let label: String
    let value: String
    let tone: HomeTone?
}

struct HomeTile: Identifiable, Equatable {
    var id: Page { page }
    let page: Page
    let name: String
    let symbol: String
    let sub: String
    let subIsFailure: Bool          // failure → hotInk
    let tagTone: HomeTone
    let tagText: String
    let skeleton: Bool
    let kvs: [HomeKV]               // always 2
    let destination: Destination
    let hotRing: Bool
}

enum HomeScan: Equatable {
    case firstScan
    case ok(at: Date)
    case refreshing(lastGoodAt: Date)
    case failed(BlockFailure, lastGoodAt: Date?)
}

enum HomeStatus: Equatable { case checking, good, attention, critical }

/// Built by the view from DashboardModel: values, no references.
struct HomeInput {
    var assessment: Assessment
    var report: FullReport
    var scan: BlockState
    var load: [Double]?
    var ncpu: Int
    var processCount: Int?
    var mem: MemSnapshot?
    var swap: SwapInfo?
    var disk: DiskInfo?
    var hasBattery: Bool
    var battery: BatteryInfo?
    var system: SystemInfo?
    var claudeBackup: ClaudeBackupStatus?
    var backupStaleHours: Int
    var history: [MacHistoryEntry]
    var now: Date
    /// Precomputed history figures. The app passes the model's cached digest (recomputed only when the history
    /// changes) and leaves `history` empty; when nil, the digest is derived from `history`.
    var historyDigest: HomeHistoryDigest? = nil
}

/// The history-derived figures of the History tile: entry count and the two quarter-window monthly slopes.
struct HomeHistoryDigest: Equatable {
    var count: Int
    var diskPerMonth: Double?
    var batteryPerMonth: Double?
    static let empty = HomeHistoryDigest(count: 0, diskPerMonth: nil, batteryPerMonth: nil)
}

extension Page {
    var title: String {
        switch self {
        case .home: return L.commonThisMac
        case .cpu: return L.commonCPU
        case .memory: return L.commonMemory
        case .storage: return L.commonStorage
        case .battery: return L.commonBattery
        case .security: return L.commonSecurity
        case .backups: return L.commonBackups
        case .system: return L.commonSystem
        case .history: return L.commonHistory
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.75percent"
        case .security: return "lock.shield"
        case .backups: return "clock.arrow.circlepath"
        case .system: return "gearshape"
        case .history: return "chart.xyaxis.line"
        }
    }

    var defaultFocus: CardID? {
        switch self {
        case .home: return nil
        case .cpu: return .cpu
        case .memory: return .usage
        case .storage: return .disk
        case .battery: return .bathero
        case .security: return .protect
        case .backups: return .tm
        case .system: return .sleep
        case .history: return .hist
        }
    }
}

enum HomeModel {
    private static let GIB: Int64 = 1 << 30
    private static let dash = "—"

    // MARK: scan / status

    static func scan(_ s: BlockState) -> HomeScan {
        switch s.phase {
        case .loading:
            if let good = s.lastGoodAt { return .refreshing(lastGoodAt: good) }
            return .firstScan
        case .ok(let at): return .ok(at: at)
        case .failed(let f, let lastGoodAt): return .failed(f, lastGoodAt: lastGoodAt)
        }
    }

    static func status(scan: HomeScan, tasks: [HomeTask]) -> HomeStatus {
        if scan == .firstScan { return .checking }
        if tasks.isEmpty { return .good }
        return tasks.contains { $0.tone == .hot } ? .critical : .attention
    }

    // MARK: tasks

    /// One task per assessment item, same order (already crit > serious > warn, stable).
    /// `disk` = `model.disk`, `battery` = `model.battery` — the same values Assessment used.
    static func tasks(_ a: Assessment, report: FullReport, disk: DiskInfo?, battery: BatteryInfo?) -> [HomeTask] {
        a.items.map { task($0, report: report, disk: disk, battery: battery) }
    }

    private static func task(_ item: AttentionItem, report: FullReport, disk: DiskInfo?, battery: BatteryInfo?) -> HomeTask {
        let tone: HomeTone = (item.sev == .crit || item.sev == .serious) ? .hot : .amber
        var section: Page = .system
        var focus: CardID? = nil
        var object = ""
        var state = ""
        var verb: String? = nil
        var tag = ""

        switch item.kind {
        case .firewallOff:
            (section, focus) = (.security, .protect)
            (object, state, verb, tag) = (L.commonFirewall, L.homeStateOff, L.commonEnable, L.homeTagFirewallOff)
        case .smartErrors:
            (section, focus) = (.storage, .smart)
            (object, state, verb, tag) = (L.homeDiskHealth, L.homeStateFailing, L.homeVerbDetails, L.homeTagDriveFailing)
        case .diskFull, .diskFullSoon:
            let pct = disk.map { Int(($0.pct * 100).rounded()) } ?? 0
            (section, focus) = (.storage, .disk)
            (object, state, verb, tag) = (L.commonDisk, L.homeStateDiskFull(pct), L.homeVerbFreeUp, L.homeStateDiskFull(pct))
        case .timeMachine:
            (section, focus) = (.backups, .tm)
            (object, state, verb, tag) = ("Time Machine", L.homeStateNotSetUp, L.commonSetUp, L.homeTagTMNotSetUp)
        case .wakeHolders:
            let keys = item.wakeHolderKeys
            let first = keys.first?.owner ?? item.label
            (section, focus) = (.system, .sleep)
            (object, state, verb, tag) = (keys.count > 1 ? "\(first) +\(keys.count - 1)" : first,
                                          L.homeStateKeepsAwake, L.commonShow, L.commonMacCantSleep)
        case .batteryCapacity:
            let cap = (report.battery ?? battery)?.maxCapacity ?? 100
            (section, focus) = (.battery, .bathero)
            (object, state, verb, tag) = (L.commonBattery, L.homeStateWorn(100 - cap), L.homeVerbDetails, L.homeTagWorn)
        case .brewOutdated:
            let n = report.brewOutdated?.count ?? 0
            (section, focus) = (.system, .brew)
            (object, state, verb, tag) = ("Homebrew", L.homeStatePackagesOutdated(n), L.homeVerbUpdate, L.homeTagBrewOutdated)
        case .updates:
            let n = report.updates?.count ?? 0
            (section, focus) = (.security, .updates)
            (object, state, verb, tag) = (updateObject(report.updates),
                                          n == 1 ? L.homeStateUpdateAvailable : L.homeStateUpdatesAvailable(n),
                                          L.commonInstall, L.homeTagUpdateAvailable)
        case .swapHigh:
            (section, focus) = (.memory, .usage)
            (object, state, verb, tag) = (L.homeMemoryObject,
                                          item.sev == .serious ? L.homeStateRunningOut : L.homeStateRunningLow,
                                          L.commonShow, L.homeTagLowMemory)
        case .batteryCondition:
            (section, focus) = (.battery, .bathero)
            (object, state, verb, tag) = (L.commonBattery, L.commonServiceRecommended, L.homeVerbDetails, L.homeTagService)
        case .fileVaultOff:
            (section, focus) = (.security, .protect)
            (object, state, verb, tag) = ("FileVault", L.homeStateOff, L.homeVerbSettings, L.homeTagFileVaultOff)
        case .gatekeeperOff:
            (section, focus) = (.security, .protect)
            (object, state, verb, tag) = ("Gatekeeper", L.homeStateOff, L.commonEnable, L.homeTagGatekeeperOff)
        case .sipOff:
            (section, focus) = (.security, .protect)
            (object, state, verb, tag) = ("SIP", L.homeStateOff, nil, L.homeTagSipOff)
        case .crashes:
            let n = (report.crashes ?? []).filter { ReportCollector.crashRaisesAttention($0) && $0.count > 0 }
                .reduce(0) { $0 + $1.count }
            (section, focus) = (.security, .crashes)
            (object, state, verb, tag) = (L.homeCrashes, L.homeStateReports(n), L.commonShow, L.homeCrashes)
        case .smartWear:
            let disk = (report.smart ?? []).first { item.label.contains($0.title) }
            let pu = disk.flatMap { smartPercentUsed($0) }
            (section, focus) = (.storage, .smart)
            (object, state, verb, tag) = (L.homeDiskWear, pu.map { L.homePercent("\($0)") } ?? item.detail,
                                          L.homeVerbDetails, L.homeTagDiskWorn)
        case .claudeBackup:
            (section, focus) = (.backups, .claude)
            (object, state, verb, tag) = (L.commonClaudeBackup, item.detail, L.commonShow, L.homeTagClaudeStale)
        }

        return HomeTask(id: item.id, kind: item.kind, tone: tone, object: object, state: state,
                        section: section, destination: Destination(section, focus: focus),
                        verb: verb, help: item.kind == .sipOff ? L.homeSipHelp : item.fullText,
                        tileTag: tag, legacyAction: item.action, wakeHolderKeys: item.wakeHolderKeys)
    }

    /// Mirrors `Assess.attrInt(d, "Percentage Used")`: first attribute with that key, digits only.
    static func smartPercentUsed(_ d: SmartDisk) -> Int? {
        guard let raw = d.attrs.first(where: { $0.0 == "Percentage Used" })?.1 else { return nil }
        let digits = raw.filter { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Object of the macOS-update task: one pending label → "macOS 26.1.1" (macOS) or the label
    /// without its build suffix; zero or several → "macOS".
    static func updateObject(_ labels: [String]?) -> String {
        guard let labels, labels.count == 1, let label = labels.first else { return "macOS" }
        if label.hasPrefix("macOS") {
            guard let token = label.split(separator: " ").first(where: { $0.first?.isNumber == true }) else { return "macOS" }
            let version = token.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? String(token)
            return "macOS " + version
        }
        if let dash = label.lastIndex(of: "-") {
            let suffix = label[label.index(after: dash)...]
            let isBuildId = !suffix.isEmpty && suffix.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." }
            if isBuildId, dash != label.startIndex { return String(label[..<dash]) }
        }
        return label
    }

    // MARK: chips

    static func chips(_ input: HomeInput) -> [HomeChip] {
        let report = input.report
        var out: [HomeChip] = []

        // Free up space: the folders that raise today's Downloads / Trash / Caches capsules.
        var freeable: Int64 = 0
        for d in report.homeDirs ?? [] {
            let name = (d.path as NSString).lastPathComponent
            if name == "Downloads", d.bytes > 10 * GIB { freeable += d.bytes }
            if name == ".Trash", d.bytes > 1 * GIB { freeable += d.bytes }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for d in report.serviceDirs ?? [] where d.path.hasSuffix("/Library/Caches") && d.path.hasPrefix(home) && d.bytes > 3 * GIB {
            freeable += d.bytes
        }
        let foldersHome = Destination(.storage, focus: .folders, foldersSegment: .home)
        if freeable > 0 {
            out.append(HomeChip(id: "freeUp", object: L.homeFreeUpSpace, value: fmtBytes(freeable), destination: foldersHome))
        }
        if let n = report.snapshots?.count, n > 0 {
            out.append(HomeChip(id: "snapshots", object: L.commonLocalSnapshots, value: "\(n)",
                                destination: Destination(.backups, focus: .tm)))
        }
        if let n = report.brewOutdated?.count, n > 0 {
            out.append(HomeChip(id: "brew", object: "Homebrew", value: L.homeBrewOutdatedShort(n),
                                destination: Destination(.system, focus: .brew)))
        }
        if !report.homeDirsUnreadable.isEmpty || !report.serviceDirsUnreadable.isEmpty {
            out.append(HomeChip(id: "fda", object: L.commonFullDiskAccessNeeded, value: nil, destination: foldersHome))
        }
        return out
    }

    // MARK: small derivations

    /// How many of the four protections are on; nil before the security section is collected.
    static func protectionOn(_ s: SecurityState?) -> Int? {
        guard let s else { return nil }
        return [s.fileVault, s.gatekeeper, s.sip, s.firewall].filter { $0 == true }.count
    }

    static func historyDigest(_ entries: [MacHistoryEntry]) -> HomeHistoryDigest {
        HomeHistoryDigest(count: entries.count,
                          diskPerMonth: monthlyRate(entries) { $0.disk_used_gb },
                          batteryPerMonth: monthlyRate(entries) { $0.battery_pct })
    }

    /// Slope per 30 days between the oldest and newest entry carrying the value inside the
    /// quarter window (D14); nil with fewer than two such entries or less than 14 days between them.
    static func monthlyRate(_ entries: [MacHistoryEntry], _ value: (MacHistoryEntry) -> Int?) -> Double? {
        // Calendar days as integers: this runs on every Home refresh over up to ~500 entries, where
        // DateFormatter parsing cost tens of milliseconds per pass. Same window as `HistorySeries.dateRange(.quarter)`.
        guard let last = entries.last, let endDay = dayNumber(last.date),
              let windowDays = HistoryRange.quarter.days else { return nil }
        let startDay = endDay - (windowDays - 1)
        let points: [(day: Int, value: Int)] = entries.compactMap { e in
            guard let day = dayNumber(e.date), day >= startDay, day <= endDay, let v = value(e) else { return nil }
            return (day, v)
        }
        guard points.count >= 2, let o = points.first, let n = points.last else { return nil }
        let days = n.day - o.day
        guard days >= 14 else { return nil }
        return Double(n.value - o.value) / Double(days) * 30
    }

    /// Days since 1970-01-01 of a "yyyy-MM-dd" string (proleptic Gregorian, no time zone); nil if malformed.
    static func dayNumber(_ s: String) -> Int? {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        // days-from-civil (H. Hinnant)
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// "+" for v > 0 (after rounding to `decimals`), U+2212 for v < 0, no sign for 0.
    static func signed(_ v: Double, decimals: Int) -> String {
        let factor = pow(10.0, Double(decimals))
        let rounded = (v * factor).rounded() / factor
        let magnitude = decimals > 0 ? fmtFixed(abs(v), decimals: decimals) : String(Int(abs(v).rounded()))
        if rounded > 0 { return "+" + magnitude }
        if rounded < 0 { return "\u{2212}" + magnitude }
        return magnitude
    }

    static func hhmm(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "HH:mm"
        return df.string(from: d)
    }

    // MARK: tiles

    static func tiles(_ input: HomeInput, tasks: [HomeTask], scan: HomeScan) -> [HomeTile] {
        var pages: [Page] = [.cpu, .memory, .storage, .battery, .security, .backups, .system, .history]
        if !input.hasBattery { pages.removeAll { $0 == .battery } }
        let skeleton = scan == .firstScan
        var failedAt: Date? = nil
        if case .failed(_, let lastGood) = scan { failedAt = lastGood }

        return pages.map { page in
            let first = tasks.first { $0.section == page }
            let (okTone, okTag, normalSub, rawKVs) = tileParts(page, input, tasks: tasks)
            let kvs = skeleton ? rawKVs.map { HomeKV(label: $0.label, value: dash, tone: .neutral) } : rawKVs
            return HomeTile(page: page, name: page.title, symbol: page.symbol,
                            sub: failedAt.map { L.homeTileLastCheck(hhmm($0)) } ?? normalSub,
                            subIsFailure: failedAt != nil,
                            tagTone: skeleton ? .neutral : (first?.tone ?? okTone),
                            tagText: skeleton ? "" : (first?.tileTag ?? okTag),
                            skeleton: skeleton, kvs: kvs,
                            destination: first?.destination ?? Destination(page, focus: page.defaultFocus),
                            hotRing: first?.tone == .hot && !skeleton)
        }
    }

    /// OK tag, normal sub line and the two mini KVs of one tile.
    private static func tileParts(_ page: Page, _ i: HomeInput, tasks: [HomeTask])
        -> (HomeTone, String, String, [HomeKV]) {
        let r = i.report
        func has(_ k: AttentionKind) -> Bool { tasks.contains { $0.kind == k } }
        func kv(_ label: String, _ value: String?, _ tone: HomeTone? = nil) -> HomeKV {
            value.map { HomeKV(label: label, value: $0, tone: tone) } ?? HomeKV(label: label, value: dash, tone: .neutral)
        }
        switch page {
        case .cpu:
            let chip = i.system?.chip ?? ""
            let sub = chip.isEmpty ? L.homeCoresOnly(i.ncpu) : L.homeCPUSub(chip, i.ncpu)
            return (.green, L.homeTagNormal, sub,
                    [kv(L.homeKVLoad, i.load?.first.map { fmtFixed($0, decimals: 2) }),
                     kv(L.homeKVProcesses, i.processCount.map { "\($0)" })])
        case .memory:
            return (.green, L.homeTagNormal, fmtBytes(i.system?.memBytes ?? i.mem?.total),
                    [kv("Swap", i.swap.map { fmtBytes($0.used) }),
                     kv(L.commonCompressed, i.mem.map { fmtBytes($0.compressor) })])
        case .storage:
            let smart: HomeKV
            if has(.smartErrors) {
                smart = HomeKV(label: "SMART", value: L.homeKVFailing, tone: .hot)
            } else if has(.smartWear) {
                let pu = (r.smart ?? []).compactMap { smartPercentUsed($0) }.first { $0 >= 80 }
                smart = pu.map { HomeKV(label: "SMART", value: L.homeKVWorn($0), tone: .amber) }
                    ?? HomeKV(label: "SMART", value: L.homeTagDiskWorn, tone: .amber)
            } else if let s = r.smart, !s.isEmpty {
                smart = HomeKV(label: "SMART", value: L.commonOK, tone: nil)
            } else {
                smart = HomeKV(label: "SMART", value: dash, tone: .neutral)
            }
            return (.green, L.homeTagHealthy, L.homeStorageSub,
                    [kv(L.homeKVPurgeable, i.disk?.purgeable.map { fmtCapacity($0) }), smart])
        case .battery:
            let b = r.battery ?? i.battery
            let cond = has(.batteryCondition)
            let capTone: HomeTone? = cond ? .hot : (has(.batteryCapacity) ? .amber : nil)
            return (.green, L.homeTagHealthy, L.homeBatterySub,
                    [kv(L.commonCycles, b?.cycles.map { "\($0)" }, cond ? .hot : nil),
                     kv(L.homeKVCapacity, b?.maxCapacity.map { L.homePercent("\($0)") }, capTone)])
        case .security:
            let on = protectionOn(r.security)
            let updates: String?
            if let u = r.updates { updates = u.isEmpty ? L.homeKVNone : "\(u.count)" } else { updates = nil }
            return (.green, L.homeTagAllOn, L.homeSecuritySub,
                    [kv(L.commonProtection, on.map { L.homeKVProtection($0) }, (on ?? 4) < 4 ? .hot : nil),
                     kv(L.commonUpdates, updates)])
        case .backups:
            let claude: HomeKV
            switch i.claudeBackup {
            case .lastSuccess(let d):
                let secs = Int(i.now.timeIntervalSince(d))
                claude = HomeKV(label: L.commonClaudeBackup, value: L.claudeBackupAgo(BackupLog.durationText(seconds: secs)),
                                tone: has(.claudeBackup) ? .amber : nil)
            case .noSuccessFound:
                claude = HomeKV(label: L.commonClaudeBackup, value: L.attnDetailClaudeBackupNone, tone: .amber)
            case .unreadable, nil:
                claude = HomeKV(label: L.commonClaudeBackup, value: dash, tone: .neutral)
            }
            return (.green, L.homeTagUpToDate, L.homeBackupsSub,
                    [claude, kv(L.homeKVSnapshots, r.snapshots.map { "\($0.count)" })])
        case .system:
            let brew: HomeKV
            if let n = r.brewOutdated?.count {
                brew = n > 0 ? HomeKV(label: "Homebrew", value: L.homeBrewOutdatedShort(n), tone: .amber)
                             : HomeKV(label: "Homebrew", value: L.homeKVUpToDate, tone: nil)
            } else {
                brew = HomeKV(label: "Homebrew", value: dash, tone: .neutral)
            }
            return (.green, L.homeTagNormal, L.homeSystemSub,
                    [kv(L.homeKVLoginItems, r.autostart?.loginItems.map { "\($0.count)" }), brew])
        case .history:
            let d = i.historyDigest ?? historyDigest(i.history)
            let disk = d.diskPerMonth
            let batt = d.batteryPerMonth
            return (.neutral, L.homeHistoryDays(d.count), L.homeHistorySub,
                    [kv(L.homeKVDiskPerMonth, disk.map { L.homeGB(signed($0, decimals: 0)) }),
                     kv(L.homeKVCapacity, batt.map { L.homePercent(signed($0, decimals: 1)) })])
        case .home:
            return (.neutral, "", "", [])
        }
    }
}
