// Engine/SystemPageModel.swift
// REDESIGN-SYSTEM: pure state, texts, tones and rows of the System page (handoff 09-system).
// The shape of BackupsPageModel: `make(Input)` computes everything, SystemPage.swift only draws it.
import Foundation

enum SystemTone: Equatable { case green, amber, hot, neutral, accent }
enum SleepCardState: Equatable { case wait, none, blockers }

struct SleepRow: Equatable, Identifiable {
    var id: String; var name: String; var age: String; var warnable: Bool; var key: WakeHolderKey
}
struct HiddenRow: Equatable, Identifiable {
    var id: String; var name: String; var sub: String; var key: WakeHolderKey; var a11y: String
}

enum StartupGroupID: String, CaseIterable { case login, userAgents, systemAgents, systemDaemons, background }
struct StartupPill: Equatable { var id: String; var text: String; var stale: Bool; var help: String }
struct StartupGroup: Equatable, Identifiable {
    var id: StartupGroupID; var title: String; var count: Int?; var staleCount: Int
    var pills: [StartupPill]; var noPermission: Bool; var openByDefault: Bool
}
struct StaleRow: Equatable, Identifiable {
    var id: String /* path */; var fileName: String; var folder: String
    var isSystemLevel: Bool; var deleting: Bool; var a11yDelete: String
}
enum StartupNote: Equatable { case noStale, failed(String), cancelled, timedOut }

enum BrewCardState: Equatable { case wait, none, outdated, updating, ok, checkFailed, upgradeFailed(String), stopped(String) }
struct BrewRow: Equatable, Identifiable { var id: String; var name: String; var sub: String }

enum EnergyRowKind: Equatable { case number, toggle, text, readOnly }
struct EnergyRowSpec: Equatable { var key: String; var kind: EnergyRowKind; var label: String; var info: String }
struct EnergyCell: Equatable { var raw: String?; var shown: String; var dirty: Bool }   // raw nil → "—"
struct EnergyRow: Equatable, Identifiable {
    var spec: EnergyRowSpec; var battery: EnergyCell; var ac: EnergyCell
    var id: String { spec.key }
}
/// Which pmset power source a pending change targets: `-b` (battery) or `-c` (AC).
enum EnergyBucket: Equatable { case battery, ac }
/// One not-yet-applied edit: a validated integer string for `key` in `bucket`.
struct EnergyChange: Equatable {
    let bucket: EnergyBucket
    let key: String
    let value: String
}
enum EnergyApplyState: Equatable, Sendable { case idle, applying, applied, failed(PrivilegedActionFailure) }

/// File-scope thunk to the shared `brewProgressText` (SharedUI.swift): inside `SystemPageModel` the name is shadowed
/// by the `brewProgressText` property, and a module-qualified call breaks the single-module harness build.
private func brewProgressLine(_ p: BrewProgress) -> String { brewProgressText(p) }

struct SystemPageModel: Equatable {
    struct Input {
        var wakeSampled: Bool
        var wakeHolders: [WakeHolder]
        var systemWakeHolders: [WakeHolder]
        var ignored: [IgnoredWakeHolder]
        var autostart: AutostartInfo?
        var startupChecking: Bool
        var startupCheckedAt: Date?
        var startupRemoved: Int
        var deletingPaths: Set<String>
        var plistFailure: PrivilegedActionFailure?
        var brewStatus: BrewStatus?
        var brewOutdated: [String]?
        var brewDetail: [BrewOutdatedPackage]?
        var brewInstalled: Int?
        var brewCheckedAt: Date?
        var brewUpgrading: Bool
        var brewProgress: BrewProgress?
        var brewError: String?
        var brewNotice: String?
        var brewRefreshing: Bool
        var energy: EnergySettings?
        var energyPending: [EnergyChange]
        var energyApply: EnergyApplyState
        var now: Date
    }

    var tag: SystemTone = .green; var tagText = ""; var sub = ""

    // Sleep
    var sleepState: SleepCardState = .wait; var sleepCaption = ""
    var sleepRows: [SleepRow] = []; var hiddenRows: [HiddenRow] = []; var hiddenCount = 0

    // Startup items
    var startupWait = true; var startupCaption = ""; var startupChecked = false; var startupChecking = false
    var groups: [StartupGroup] = []; var staleRows: [StaleRow] = []; var showDeleteAll = false
    var startupNote: StartupNote? = nil; var startupBusy = false

    // Homebrew
    var brewState: BrewCardState = .wait; var brewCaption = ""; var brewRows: [BrewRow] = []
    var brewNoteText = ""; var brewProgressText = ""; var brewUpdatingLabel = ""; var brewRefreshing = false

    // Energy
    var energyWait = true; var energyEmpty = false; var energyCaption = ""
    var energyRows: [EnergyRow] = []; var dirtyCount = 0; var showActionBar = false
    var resetAvailable = false; var showApplied = false; var energyBanner: String? = nil
    var confirmLines: [String] = []; var confirmTitle = ""

    static let dash = "—"

    // MARK: make

    static func make(_ i: Input) -> SystemPageModel {
        var m = SystemPageModel()
        m.sub = L.sysSub

        // Sleep
        let warnable = WakeHolders.unignored(i.wakeHolders, ignored: i.ignored.map(\.key))
        if !i.wakeSampled {
            m.sleepState = .wait
        } else if warnable.isEmpty && i.systemWakeHolders.isEmpty {
            m.sleepState = .none
        } else {
            m.sleepState = .blockers
        }
        m.sleepCaption = m.sleepState == .none ? L.sysSleepCaptionNone : L.sysSleepCaption
        if i.wakeSampled {
            m.sleepRows = warnable.map { sleepRow($0, warnable: true) } + i.systemWakeHolders.map { sleepRow($0, warnable: false) }
        }
        m.hiddenRows = i.ignored.map { e in
            let name = WakeHolders.label(for: e.key)
            return HiddenRow(id: rowID(e.key), name: name,
                             sub: e.since.map { L.sysHiddenSince(L.shortDate($0)) } ?? L.sysHiddenNoDate,
                             key: e.key, a11y: L.sysWarnAgainA11y(name))
        }
        m.hiddenCount = m.hiddenRows.count

        // Startup items
        m.startupChecking = i.startupChecking
        m.startupChecked = i.startupCheckedAt != nil
        m.startupBusy = !i.deletingPaths.isEmpty
        if let auto = i.autostart {
            m.startupWait = false
            let checked = m.startupChecked
            m.groups = groups(auto, checked: checked)
            if checked {
                m.staleRows = staleRows(auto, deleting: i.deletingPaths)
            }
            m.showDeleteAll = m.staleRows.count >= 2
            let total = m.groups.reduce(0) { $0 + ($1.count ?? 0) }
            var caption = L.sysStartupItems(total)
            if i.startupRemoved > 0 { caption += L.sysStartupRemoved(i.startupRemoved) }
            else if let at = i.startupCheckedAt { caption += checkedCaption(checkedAt: at, now: i.now) }
            m.startupCaption = caption
        }
        if let f = i.plistFailure {
            switch f {
            case .error(let msg): m.startupNote = .failed(msg)
            case .cancelled: m.startupNote = .cancelled
            case .timedOut: m.startupNote = .timedOut
            }
        } else if m.startupChecked && m.staleRows.isEmpty && i.autostart != nil {
            m.startupNote = .noStale
        }

        // Homebrew
        m.brewRefreshing = i.brewRefreshing
        let outdatedCount = i.brewOutdated?.count ?? 0
        m.brewRows = brewRows(names: i.brewOutdated, detail: i.brewDetail)
        m.brewState = brewState(i)
        m.brewUpdatingLabel = L.sysTagUpdating
        m.brewProgressText = i.brewProgress.map(brewProgressLine) ?? L.sysBrewUpdatingN(outdatedCount)
        m.brewCaption = brewCaption(i, state: m.brewState)
        switch m.brewState {
        case .ok: m.brewNoteText = L.sysBrewAllUpToDate(i.brewInstalled)
            + { let t = brewCheckedText(checkedAt: i.brewCheckedAt, now: i.now); return t.isEmpty ? "" : " " + t }()
        case .none: m.brewNoteText = L.sysBrewNotInstalled
        case .checkFailed: m.brewNoteText = L.sysBrewCheckFailed
        case .upgradeFailed(let msg): m.brewNoteText = msg
        case .stopped(let notice): m.brewNoteText = notice
        case .wait, .outdated, .updating: m.brewNoteText = ""
        }

        // Energy
        m.energyCaption = L.sysEnergyCaption
        m.energyWait = i.energy == nil
        if let e = i.energy {
            m.energyEmpty = e.battery.isEmpty && e.ac.isEmpty
            if !m.energyEmpty {
                m.energyRows = energySpecs.map { spec in
                    EnergyRow(spec: spec,
                              battery: cell(spec, .battery, e, i.energyPending),
                              ac: cell(spec, .ac, e, i.energyPending))
                }
                m.resetAvailable = resetAvailable(energy: e, pending: i.energyPending)
            }
        }
        m.dirtyCount = i.energyPending.count
        m.showApplied = i.energyApply == .applied
        m.showActionBar = m.dirtyCount > 0 || m.resetAvailable || m.showApplied
        if case .failed(let f) = i.energyApply { m.energyBanner = energyBannerText(f) }
        m.confirmLines = confirmLines(i.energyPending)
        m.confirmTitle = L.sysEnergyConfirmTitle(i.energyPending.count)

        // Page tag
        var energyFailed = false
        if case .failed(.error) = i.energyApply { energyFailed = true }
        let brewOutdatedShown: Bool
        switch m.brewState {
        case .outdated, .stopped, .upgradeFailed: brewOutdatedShown = outdatedCount > 0
        default: brewOutdatedShown = false
        }
        (m.tag, m.tagText) = tag(energyFailed: energyFailed,
                                 warnableSleep: i.wakeSampled && !warnable.isEmpty,
                                 staleFound: m.startupChecked && !m.staleRows.isEmpty,
                                 brewUpdating: m.brewState == .updating,
                                 brewOutdated: brewOutdatedShown)
        return m
    }

    // MARK: tag

    /// Priority: energy apply failed (hot) · warnable sleep blocker (amber) · stale startup items after a
    /// check (amber) · brew updating (accent) · brew outdated (amber) · else green.
    static func tag(energyFailed: Bool, warnableSleep: Bool, staleFound: Bool,
                    brewUpdating: Bool, brewOutdated: Bool) -> (SystemTone, String) {
        if energyFailed { return (.hot, L.sysTagApplyFailed) }
        if warnableSleep { return (.amber, L.commonMacCantSleep) }
        if staleFound { return (.amber, L.commonNeedsAttention) }
        if brewUpdating { return (.accent, L.sysTagUpdating) }
        if brewOutdated { return (.amber, L.sysTagOutdated) }
        return (.green, L.commonAllGood)
    }

    // MARK: sleep

    static func rowID(_ key: WakeHolderKey) -> String { "\(key.owner)|\(key.requester ?? "")" }

    private static func sleepRow(_ h: WakeHolder, warnable: Bool) -> SleepRow {
        SleepRow(id: rowID(h.key), name: WakeHolders.label(for: h),
                 age: WakeHolders.ageText(h.ageSeconds), warnable: warnable, key: h.key)
    }

    // MARK: startup

    /// "HH:MM" helper reused from the Security page.
    static func hhmm(_ d: Date) -> String { SecurityPageModel.hhmm(d) }

    /// " · checked just now" below a minute, else " · checked HH:MM" (the strings carry the separator).
    static func checkedCaption(checkedAt: Date, now: Date) -> String {
        now.timeIntervalSince(checkedAt) < 60 ? L.sysCheckedJustNow : L.sysCheckedAt(hhmm(checkedAt))
    }

    private static func isSystemLevel(_ path: String) -> Bool { path.hasPrefix("/Library/") }

    private static func fileName(_ path: String) -> String { (path as NSString).lastPathComponent }

    /// `~`-abbreviated directory of `path`.
    private static func folder(_ path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        if dir == home { return "~" }
        if dir.hasPrefix(home + "/") { return "~" + dir.dropFirst(home.count) }
        return dir
    }

    private static func plistHelp(_ info: LaunchdPlistInfo, stale: Bool) -> String {
        var parts: [String] = []
        if let d = info.description, !d.isEmpty { parts.append(d) }
        if let e = info.executablePath { parts.append(e) }
        if stale { parts.append(L.sysStaleHelp) }
        return parts.joined(separator: "\n")
    }

    private static func groups(_ auto: AutostartInfo, checked: Bool) -> [StartupGroup] {
        func plistGroup(_ id: StartupGroupID, _ title: String, _ items: [LaunchdPlistInfo]) -> StartupGroup {
            let pills = items.map { info -> StartupPill in
                let stale = checked && info.isOrphan
                return StartupPill(id: info.path, text: fileName(info.path), stale: stale, help: plistHelp(info, stale: stale))
            }
            let staleCount = pills.filter(\.stale).count
            return StartupGroup(id: id, title: title, count: items.count, staleCount: staleCount, pills: pills,
                                noPermission: false, openByDefault: staleCount > 0)
        }
        let login = auto.loginItems
        let loginPills = (login ?? []).enumerated().map { idx, name in
            StartupPill(id: "login|\(idx)|\(name)", text: name, stale: false, help: "")
        }
        let background = auto.background.enumerated().map { idx, bg in
            StartupPill(id: "background|\(idx)|\(bg.label)", text: bg.label, stale: false, help: "PID \(bg.pid)")
        }
        return [
            StartupGroup(id: .login, title: L.sysGroupLogin, count: login?.count, staleCount: 0, pills: loginPills,
                         noPermission: login == nil, openByDefault: true),
            plistGroup(.userAgents, L.sysGroupUserAgents, auto.userAgents),
            plistGroup(.systemAgents, L.sysGroupSystemAgents, auto.systemAgents),
            plistGroup(.systemDaemons, L.sysGroupSystemDaemons, auto.systemDaemons),
            StartupGroup(id: .background, title: L.sysGroupBackground, count: auto.background.count, staleCount: 0,
                         pills: background, noPermission: false, openByDefault: false),
        ]
    }

    /// Orphans of the three plist groups: user-level first, then /Library, each by file name.
    private static func staleRows(_ auto: AutostartInfo, deleting: Set<String>) -> [StaleRow] {
        let orphans = (auto.userAgents + auto.systemAgents + auto.systemDaemons).filter(\.isOrphan)
        let rows = orphans.map { info in
            StaleRow(id: info.path, fileName: fileName(info.path), folder: folder(info.path),
                     isSystemLevel: isSystemLevel(info.path), deleting: deleting.contains(info.path),
                     a11yDelete: L.sysDeleteA11y(fileName(info.path)))
        }
        return rows.sorted {
            if $0.isSystemLevel != $1.isSystemLevel { return !$0.isSystemLevel }
            return $0.fileName != $1.fileName ? $0.fileName < $1.fileName : $0.id < $1.id
        }
    }

    static func startupConfirmTitle(_ n: Int) -> String { L.sysDeleteConfirmTitle(n) }

    /// One paragraph per kind present: user items go to the Trash, /Library items are removed for good.
    static func confirmParagraphs(userCount: Int, systemCount: Int) -> [String] {
        var out: [String] = []
        if userCount > 0 { out.append(L.sysDeleteParagraphUser) }
        if systemCount > 0 { out.append(L.sysDeleteParagraphSystem) }
        return out
    }

    // MARK: brew

    /// "Homebrew 4.6.0" -> "4.6.0".
    static func brewVersionNumber(_ raw: String) -> String {
        let prefix = "Homebrew "
        let s = raw.trimmingCharacters(in: .whitespaces)
        return s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) : s
    }

    /// Same day -> "Checked today at HH:MM."; another day -> "Checked <date, time>."; nil -> "".
    static func brewCheckedText(checkedAt: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let d = checkedAt else { return "" }
        if calendar.isDate(d, inSameDayAs: now) { return L.sysBrewCheckedToday(hhmm(d)) }
        return L.sysBrewCheckedOn(L.shortDateTime(d))
    }

    private static func brewState(_ i: Input) -> BrewCardState {
        if i.brewUpgrading { return .updating }      // BREW-STOP-VISIBLE: whatever the report says
        guard let status = i.brewStatus else { return .wait }
        if case .notInstalled = status { return .none }
        if let e = i.brewError { return .upgradeFailed(e) }
        if let n = i.brewNotice { return .stopped(n) }
        guard let outdated = i.brewOutdated else { return .checkFailed }
        return outdated.isEmpty ? .ok : .outdated
    }

    private static func brewRows(names: [String]?, detail: [BrewOutdatedPackage]?) -> [BrewRow] {
        (names ?? []).map { name in
            var sub = ""
            if let p = detail?.first(where: { $0.name == name }), let cur = p.current, let new = p.latest {
                sub = "\(cur) → \(new)"
            }
            return BrewRow(id: name, name: name, sub: sub)
        }
    }

    private static func brewCaption(_ i: Input, state: BrewCardState) -> String {
        guard case .installed(let version)? = i.brewStatus else {
            if case .notInstalled? = i.brewStatus { return L.sysBrewCaptionNone }
            return ""
        }
        let v = version.map(brewVersionNumber) ?? L.sysBrewCaptionUnknown
        let n = i.brewOutdated?.count ?? 0
        switch state {
        case .updating: return L.sysBrewCaptionUpdating(v)
        case .checkFailed: return v
        case .outdated: return L.sysBrewCaptionOutdated(v, n, i.brewInstalled)
        case .stopped, .upgradeFailed:
            return n > 0 ? L.sysBrewCaptionOutdated(v, n, i.brewInstalled) : L.sysBrewCaptionOk(v, i.brewInstalled)
        case .ok: return L.sysBrewCaptionOk(v, i.brewInstalled)
        case .wait, .none: return ""
        }
    }

    // MARK: energy

    /// Exactly the ten rows of the handoff, in its order.
    static var energySpecs: [EnergyRowSpec] {
        [
            EnergyRowSpec(key: "displaysleep", kind: .number, label: L.sysEnergyRowDisplaySleep, info: L.sysEnergyInfoDisplaySleep),
            EnergyRowSpec(key: "sleep", kind: .number, label: L.sysEnergyRowSleep, info: L.sysEnergyInfoSleep),
            EnergyRowSpec(key: "disksleep", kind: .number, label: L.sysEnergyRowDiskSleep, info: L.sysEnergyInfoDiskSleep),
            EnergyRowSpec(key: "powernap", kind: .toggle, label: L.sysEnergyRowPowerNap, info: L.sysEnergyInfoPowerNap),
            EnergyRowSpec(key: "lowpowermode", kind: .toggle, label: L.sysEnergyRowLPM, info: L.sysEnergyInfoLPM),
            EnergyRowSpec(key: "standby", kind: .toggle, label: L.sysEnergyRowStandby, info: L.sysEnergyInfoStandby),
            EnergyRowSpec(key: "womp", kind: .toggle, label: L.sysEnergyRowWoN, info: L.sysEnergyInfoWoN),
            EnergyRowSpec(key: "hibernatemode", kind: .text, label: L.sysEnergyRowHibernate, info: L.sysEnergyInfoHibernate),
            EnergyRowSpec(key: "tcpkeepalive", kind: .readOnly, label: L.sysEnergyRowTcpKeepalive, info: L.sysEnergyInfoTcpKeepalive),
            EnergyRowSpec(key: "lidwake", kind: .readOnly, label: L.sysEnergyRowLidwake, info: L.sysEnergyInfoLidwake),
        ]
    }

    /// macOS laptop defaults (Apple Silicon portables) as (battery, AC); a nil side has no default
    /// and Reset leaves that cell alone (womp has none on battery).
    static let energyDefaults: [String: (battery: String?, ac: String?)] = [
        "displaysleep": ("2", "10"),
        "sleep": ("1", "1"),
        "disksleep": ("10", "10"),
        "powernap": ("0", "1"),
        "lowpowermode": ("0", "0"),
        "standby": ("1", "1"),
        "womp": (nil, "1"),
    ]

    static func defaultValue(bucket: EnergyBucket, key: String) -> String? {
        guard let pair = energyDefaults[key] else { return nil }
        return bucket == .battery ? pair.battery : pair.ac
    }

    static func shownValue(key: String, raw: String?) -> String {
        guard let raw else { return dash }
        switch energySpecs.first(where: { $0.key == key })?.kind {
        case .toggle?, .readOnly?:
            return raw == "1" ? L.sysEnergyOn : (raw == "0" ? L.sysEnergyOff : raw)
        default:
            return raw
        }
    }

    /// The saved value of `key` in `bucket`; nil when the report does not have it.
    static func rawValue(bucket: EnergyBucket, key: String, energy: EnergySettings) -> String? {
        let source = bucket == .battery ? energy.battery : energy.ac
        return source.first(where: { $0.0 == key })?.1
    }

    /// Pending edit when there is one, else the saved value.
    static func effectiveValue(bucket: EnergyBucket, key: String, energy: EnergySettings,
                               pending: [EnergyChange]) -> String? {
        if let p = pending.first(where: { $0.bucket == bucket && $0.key == key }) { return p.value }
        return rawValue(bucket: bucket, key: key, energy: energy)
    }

    /// Adds or replaces a pending entry, or removes it when `value` equals the saved `original`:
    /// editing back to the saved value clears the dirty state.
    static func updatedPending(_ pending: [EnergyChange], bucket: EnergyBucket, key: String,
                               value: String, original: String?) -> [EnergyChange] {
        var out = pending
        if value == original {
            out.removeAll { $0.bucket == bucket && $0.key == key }
        } else if let idx = out.firstIndex(where: { $0.bucket == bucket && $0.key == key }) {
            out[idx] = EnergyChange(bucket: bucket, key: key, value: value)
        } else {
            out.append(EnergyChange(bucket: bucket, key: key, value: value))
        }
        return out
    }

    private static func isEditable(_ spec: EnergyRowSpec) -> Bool { spec.kind == .number || spec.kind == .toggle }

    /// Stages every editable key present in the report at its default (nil default skipped).
    static func resetChanges(energy: EnergySettings, pending: [EnergyChange]) -> [EnergyChange] {
        var out = pending
        for spec in energySpecs where isEditable(spec) {
            for bucket in [EnergyBucket.battery, .ac] {
                guard let original = rawValue(bucket: bucket, key: spec.key, energy: energy),
                      let def = defaultValue(bucket: bucket, key: spec.key) else { continue }
                out = updatedPending(out, bucket: bucket, key: spec.key, value: def, original: original)
            }
        }
        return out
    }

    private static func resetAvailable(energy: EnergySettings, pending: [EnergyChange]) -> Bool {
        for spec in energySpecs where isEditable(spec) {
            for bucket in [EnergyBucket.battery, .ac] {
                guard rawValue(bucket: bucket, key: spec.key, energy: energy) != nil,
                      let def = defaultValue(bucket: bucket, key: spec.key) else { continue }
                if effectiveValue(bucket: bucket, key: spec.key, energy: energy, pending: pending) != def { return true }
            }
        }
        return false
    }

    private static func cell(_ spec: EnergyRowSpec, _ bucket: EnergyBucket, _ energy: EnergySettings,
                             _ pending: [EnergyChange]) -> EnergyCell {
        guard rawValue(bucket: bucket, key: spec.key, energy: energy) != nil else {
            return EnergyCell(raw: nil, shown: dash, dirty: false)
        }
        let raw = effectiveValue(bucket: bucket, key: spec.key, energy: energy, pending: pending)
        return EnergyCell(raw: raw, shown: shownValue(key: spec.key, raw: raw),
                          dirty: pending.contains { $0.bucket == bucket && $0.key == spec.key })
    }

    /// Defensive whitelist: the key must be a plain-letters token (this text reaches a root shell).
    static func isValidPmsetKey(_ key: String) -> Bool {
        key.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil
    }

    /// `/usr/bin/pmset -b k v …` and/or `/usr/bin/pmset -c …` joined with ` && `; only integer values and
    /// valid keys; nil when nothing is left.
    static func pmsetCommand(_ changes: [EnergyChange]) -> String? {
        func args(_ bucket: EnergyBucket) -> [String] {
            changes.filter { $0.bucket == bucket && Int($0.value) != nil && isValidPmsetKey($0.key) }
                .map { "\($0.key) \($0.value)" }
        }
        var commands: [String] = []
        let b = args(.battery), a = args(.ac)
        if !b.isEmpty { commands.append("/usr/bin/pmset -b \(b.joined(separator: " "))") }
        if !a.isEmpty { commands.append("/usr/bin/pmset -c \(a.joined(separator: " "))") }
        return commands.isEmpty ? nil : commands.joined(separator: " && ")
    }

    /// «On battery:» then its lines, «On AC power:» then its lines; each bucket in table order, a bucket
    /// without edits contributes nothing.
    static func confirmLines(_ pending: [EnergyChange]) -> [String] {
        let specs = energySpecs
        func order(_ key: String) -> Int { specs.firstIndex { $0.key == key } ?? Int.max }
        func lines(_ bucket: EnergyBucket) -> [String] {
            pending.filter { $0.bucket == bucket }
                .sorted { order($0.key) < order($1.key) }
                .map { c in
                    let label = specs.first { $0.key == c.key }?.label ?? c.key
                    return "• \(label): \(shownValue(key: c.key, raw: c.value))"
                }
        }
        var out: [String] = []
        let b = lines(.battery), a = lines(.ac)
        if !b.isEmpty { out.append(L.sysEnergyOnBattery); out += b }
        if !a.isEmpty { out.append(L.sysEnergyOnAC); out += a }
        return out
    }

    static func energyBannerText(_ f: PrivilegedActionFailure) -> String {
        switch f {
        case .cancelled: return L.sysEnergyCancelled
        case .timedOut: return L.sysEnergyTimedOut
        case .error(let msg): return L.sysEnergyFailed(msg)
        }
    }
}
