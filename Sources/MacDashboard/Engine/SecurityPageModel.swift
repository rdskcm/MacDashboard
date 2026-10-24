// Engine/SecurityPageModel.swift
// REDESIGN-SECURITY: pure state, texts, tones and rows of the Security page (handoff 07-security).
import Foundation

enum SecurityProtection: String, CaseIterable, Equatable, Sendable { case fileVault, gatekeeper, sip, firewall }

/// Why a privileged enable did not end in success.
enum PrivilegedActionFailure: Equatable, Sendable { case timedOut, cancelled, error(String) }

/// The one in-flight / last-failed privileged enable; `idle` after success or Refresh.
enum SecurityActionState: Equatable, Sendable {
    case idle
    case enabling(SecurityProtection)
    case failed(SecurityProtection, PrivilegedActionFailure)
}

enum SecurityTone: Equatable { case green, amber, hot, neutral, accent }
enum SecurityTileButton: Equatable { case enable, openSettings }

struct SecurityTileModel: Equatable {
    var protection: SecurityProtection
    var label: String
    var value: String            // on / off / Enabling… / —
    var valueTone: SecurityTone? // nil ink, .hot hotInk, .neutral muted
    var dot: SecurityTone?       // .green / .hot / nil
    var note: String?
    var noteTone: SecurityTone?  // nil muted, .green greenInk
    var button: SecurityTileButton?
    var busy: Bool
    var error: Bool              // error tile tint
}
struct SecurityUpdateRow: Equatable { var id: String; var name: String; var sub: String; var value: String }
struct SecurityCrashRow: Equatable {
    var id: String; var name: String; var sub: String; var value: String
    var tone: SecurityTone; var path: String?
    /// CRASH-REPORT-DISMISS: the group carries report paths, so «Hide» / «Delete» are offered.
    var actionable = false
    /// The action running on this row (`.hide` / `.delete`), nil otherwise.
    var working: CrashActionKind? = nil
    /// Inline confirm texts; empty when not actionable.
    var confirmTitle = ""
    var confirmParagraphs: [String] = []
}
/// One row of the Crashes card's Hidden group.
struct SecurityHiddenCrashRow: Equatable { var id: String; var name: String; var sub: String; var a11y: String; var working: Bool }
struct SecurityUpdatesNote: Equatable { var tone: SecurityTone; var text: String; var showsInstall: Bool }

struct SecurityPageModel: Equatable {
    struct Input {
        var security: SecurityState?
        var action: SecurityActionState
        var fileVaultOpened: Bool
        var updates: [SoftwareUpdate]?
        var updatesCheckedAt: Date?
        var checkingUpdates: Bool
        var crashes: [CrashGroup]?
        var openedReportPath: String?
        var now: Date
        var hiddenCrashes: [CrashGroup]? = nil
        var crashAction: CrashActionState = .idle
    }
    var tag: SecurityTone = .neutral; var tagText = ""; var sub = ""
    var protectionWait = false; var protectionCaption: String? = nil
    var tiles: [SecurityTileModel] = []; var banner: String? = nil
    var updatesCaption = ""; var updatesWait = false
    var updatesWaitText = ""
    var updatesNote: SecurityUpdatesNote? = nil
    var updateRows: [SecurityUpdateRow] = []
    var crashesCaption = ""; var crashesWait = false
    var crashRows: [SecurityCrashRow] = []; var crashesNone = false; var crashFoot = ""
    var crashHiddenRows: [SecurityHiddenCrashRow] = []; var crashActionsDisabled = false; var crashNote: String? = nil

    static let dash = "—"

    /// Root command behind «Enable…». Gatekeeper: `--global-enable` (confirmed in `man spctl`, D6).
    static func privilegedEnableCommand(_ p: SecurityProtection) -> String {
        switch p {
        case .gatekeeper: return "/usr/sbin/spctl --global-enable"
        default: return "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
        }
    }

    // MARK: Helpers

    /// One paragraph per folder kind present: per-user reports go to the Trash, system ones are deleted for good.
    static func crashDeleteParagraphs(_ paths: [String], systemDirectory: String = CrashDismiss.systemDirectory) -> [String] {
        let inSystem = { (p: String) in (p as NSString).deletingLastPathComponent == systemDirectory }
        var out: [String] = []
        if paths.contains(where: { !inSystem($0) }) { out.append(L.secCrashDeleteParagraphUser) }
        if paths.contains(where: inSystem) { out.append(L.secCrashDeleteParagraphSystem) }
        return out
    }

    static func crashNoteText(_ f: CrashDeleteFailure) -> String {
        switch f {
        case .cancelled: return L.sysDeleteCancelled
        case .timedOut: return L.sysDeleteTimedOut
        case .error(let msg): return L.sysDeleteFailed(String(msg.prefix(120)))
        case .refused(let name): return L.secCrashDeleteRefused(name)
        }
    }

    static func value(_ p: SecurityProtection, _ s: SecurityState) -> Bool? {
        switch p {
        case .fileVault: return s.fileVault
        case .gatekeeper: return s.gatekeeper
        case .sip: return s.sip
        case .firewall: return s.firewall
        }
    }

    static func protectionsOn(_ s: SecurityState) -> Int {
        SecurityProtection.allCases.filter { value($0, s) == true }.count
    }

    /// Off (read as `false`) and not currently being enabled.
    static func isOff(_ p: SecurityProtection, _ s: SecurityState, action: SecurityActionState) -> Bool {
        value(p, s) == false && action != .enabling(p)
    }

    static func bannerText(_ p: SecurityProtection, _ f: PrivilegedActionFailure) -> String {
        let head: String
        switch f {
        case .timedOut: head = L.secBannerTimeout
        case .cancelled: head = L.secBannerCancelled
        case .error(let msg): head = L.secBannerFailed(p, String(msg.prefix(120)))
        }
        return head + " " + L.secStillOff(p)
    }

    /// "HH:mm" in the current zone, POSIX digits (pattern of CPUPageModel.hhmmss).
    static func hhmm(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "HH:mm"
        return df.string(from: d)
    }

    static func crashDateText(_ d: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return L.secCrashLastToday(hhmm(d)) }
        return L.secCrashDate(L.shortDateTime(d))
    }

    static func updatesCaption(updates: [SoftwareUpdate]?, checkedAt: Date?, checking: Bool, now: Date) -> String {
        var s: String
        if let checkedAt { s = updatesAgeString(checkedAt: checkedAt, now: now) }
        else if checking { s = L.secUpdatesCaptionChecking }
        else { s = L.secUpdatesCaptionNever }
        if let n = updates?.count, n > 0 { s += " " + L.secUpdatesCaptionAvailable(n) }
        return s
    }

    // MARK: make

    static func make(_ i: Input) -> SecurityPageModel {
        var m = SecurityPageModel()
        m.sub = L.secSub
        let crashTotal = (i.crashes ?? []).reduce(0) { $0 + $1.count }

        // Tag: first match wins (Design, "Tag priority").
        if let s = i.security {
            let off = SecurityProtection.allCases.filter { isOff($0, s, action: i.action) }
            if off.count >= 2 { (m.tag, m.tagText) = (.hot, L.secTagOffCount(off.count)) }
            else if isOff(.fileVault, s, action: i.action) { (m.tag, m.tagText) = (.hot, L.homeTagFileVaultOff) }
            else if isOff(.gatekeeper, s, action: i.action) { (m.tag, m.tagText) = (.hot, L.homeTagGatekeeperOff) }
            else if isOff(.sip, s, action: i.action) { (m.tag, m.tagText) = (.hot, L.homeTagSipOff) }
            else if isOff(.firewall, s, action: i.action) { (m.tag, m.tagText) = (.hot, L.homeTagFirewallOff) }
            else if case .enabling(let p) = i.action, p == .firewall || p == .gatekeeper {
                (m.tag, m.tagText) = (.accent, L.secTagEnabling(p))
            }
            else if !(i.updates ?? []).isEmpty { (m.tag, m.tagText) = (.amber, L.secTagUpdates) }
            else if crashTotal > 0 { (m.tag, m.tagText) = (.amber, L.secTagCrashes(crashTotal)) }
            else if SecurityProtection.allCases.contains(where: { value($0, s) == nil }) {
                (m.tag, m.tagText) = (.neutral, L.secTagOnCount(protectionsOn(s)))
            }
            else { (m.tag, m.tagText) = (.green, L.homeTagAllOn) }
        } else {
            (m.tag, m.tagText) = (.neutral, L.commonCollectingData)
        }

        // Protection card.
        if let s = i.security {
            var cap = L.secCaptionOn(protectionsOn(s))
            if case .enabling(let p) = i.action, p == .firewall || p == .gatekeeper { cap += " " + L.secCaptionEnabling(p) }
            m.protectionCaption = cap
            m.tiles = SecurityProtection.allCases.map { tile($0, s, i) }
            if case .failed(let p, let f) = i.action, value(p, s) == false { m.banner = bannerText(p, f) }
        } else {
            m.protectionWait = true
        }

        // Updates card.
        m.updatesCaption = updatesCaption(updates: i.updates, checkedAt: i.updatesCheckedAt, checking: i.checkingUpdates, now: i.now)
        if let ups = i.updates {
            if ups.isEmpty {
                m.updatesNote = SecurityUpdatesNote(tone: .green, text: L.secUpdatesNone, showsInstall: false)
            } else {
                var text = L.secUpdatesAvailable(ups.count)
                if ups.contains(where: \.restartRequired) { text += " " + L.secUpdatesRestart }
                m.updatesNote = SecurityUpdatesNote(tone: .amber, text: text, showsInstall: true)
            }
            m.updateRows = ups.map {
                SecurityUpdateRow(id: $0.label, name: $0.title,
                                  sub: $0.restartRequired ? L.secRestartRequired : "",
                                  value: $0.sizeBytes.map { ReportWriter.fmtBytes($0) } ?? dash)
            }
        } else if i.checkingUpdates {
            m.updatesWait = true
            m.updatesWaitText = L.secCheckingUpdates
        } else {
            m.updatesNote = SecurityUpdatesNote(tone: .neutral, text: L.secUpdatesFailed, showsInstall: false)
        }

        // Crashes card.
        var working: (kind: CrashActionKind, id: String)? = nil
        if case .working(let k, let id) = i.crashAction { working = (k, id) }
        m.crashActionsDisabled = working != nil
        if case .failed(let f) = i.crashAction { m.crashNote = crashNoteText(f) }
        if let crashes = i.crashes {
            m.crashesCaption = crashTotal > 0 ? L.secCrashesCaptionCount(crashTotal) : L.secCrashesCaption
            m.crashesNone = crashes.isEmpty
            m.crashRows = crashes.map { g in
                let actionable = !g.reportPaths.isEmpty
                return SecurityCrashRow(id: g.process,
                                        name: g.isPanic ? L.secKernelPanic : g.process,
                                        sub: g.lastReportAt.map { crashDateText($0, now: i.now) } ?? "",
                                        value: "×\(g.count)",
                                        tone: g.isPanic ? .hot : .amber,
                                        path: g.newestReportPath,
                                        actionable: actionable,
                                        working: working?.id == g.id && working?.kind != .unhide ? working?.kind : nil,
                                        confirmTitle: actionable ? L.secCrashDeleteConfirmTitle(g.count) : "",
                                        confirmParagraphs: actionable ? crashDeleteParagraphs(g.reportPaths) : [])
            }
            m.crashHiddenRows = (i.hiddenCrashes ?? []).map { g in
                let name = g.isPanic ? L.secKernelPanic : g.process
                let date = g.lastReportAt.map { crashDateText($0, now: i.now) }
                return SecurityHiddenCrashRow(id: g.process, name: name,
                                              sub: [date, "×\(g.count)"].compactMap { $0 }.joined(separator: " · "),
                                              a11y: L.secCrashUnhideA11y(name),
                                              working: working?.kind == .unhide && working?.id == g.id)
            }
        } else {
            m.crashesWait = true
            m.crashesCaption = L.secCrashesCaption
        }
        if let p = i.openedReportPath {
            m.crashFoot = L.secCrashFootOpened((p as NSString).lastPathComponent)
        } else {
            m.crashFoot = L.secCrashFootDefault
        }
        return m
    }

    private static func tile(_ p: SecurityProtection, _ s: SecurityState, _ i: Input) -> SecurityTileModel {
        let label: String
        switch p {
        case .fileVault: label = L.securityFileVault
        case .gatekeeper: label = L.securityGatekeeper
        case .sip: label = L.securitySip
        case .firewall: label = L.commonFirewall
        }
        var t = SecurityTileModel(protection: p, label: label, value: L.secValueOn, valueTone: nil, dot: .green,
                                  note: nil, noteTone: nil, button: nil, busy: false, error: false)
        switch value(p, s) {
        case true?:
            break
        case nil:
            t.value = dash; t.valueTone = .neutral; t.dot = nil; t.note = L.secNoteUnknown
        case false?:
            t.error = true; t.dot = .hot; t.valueTone = .hot
            if i.action == .enabling(p) {
                t.value = L.secValueEnabling; t.note = L.secNoteWaitingTouchID; t.button = .enable; t.busy = true
            } else {
                t.value = L.secValueOff
                switch p {
                case .fileVault:
                    t.note = i.fileVaultOpened ? L.secNoteFileVaultOpened : L.secNoteFileVault
                    t.noteTone = i.fileVaultOpened ? .green : nil
                    t.button = .openSettings
                case .gatekeeper, .firewall:
                    t.note = L.secNoteTouchID; t.button = .enable
                case .sip:
                    t.note = L.secNoteSip
                }
            }
        }
        return t
    }
}
