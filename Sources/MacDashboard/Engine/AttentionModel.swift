// Engine/AttentionModel.swift
// The v2 "attention" data model: compact chip-sized problems (AttentionItem) and
// actionable tip capsules (TipCapsule) that Assess.assess() builds alongside the
// legacy Problem/Tip arrays, plus the shared summary-title and verb-mapping logic
// the v2 UI reads from. Pure and Foundation-only — compiled into Checks.

import Foundation

/// The 14 attention conditions the v2 model recognizes, in the fixed order the
/// spec assigns them (also the order `Assess.assess` evaluates their branches).
enum AttentionKind: String, CaseIterable {
    case diskFull, diskFullSoon, swapHigh, batteryCapacity, batteryCondition, fileVaultOff,
         gatekeeperOff, sipOff, firewallOff, updates, crashes, timeMachine, smartErrors, smartWear
}

/// A single attention chip: compact label + detail (never containing the verb)
/// plus the full sentence (today's `Problem.text`) for tooltip/list display.
struct AttentionItem: Identifiable, Equatable {
    var kind: AttentionKind
    var sev: Severity
    var label: String       // short chip form, e.g. "Диск"
    var detail: String      // e.g. "заполнен на 92 %" — NEVER contains the verb
    var fullText: String    // the existing assessment sentence (tooltip / list body)
    var verb: String        // action verb; "" when action == nil
    var action: AdviceAction? = nil
    var id: String { "\(kind.rawValue)|\(label)|\(detail)" }
}

/// A single maintenance tip rendered as a capsule: object + mono value (never
/// containing the verb) plus NEW tooltip copy explaining what the action does.
struct TipCapsule: Identifiable, Equatable {
    var object: String      // e.g. "Корзина"
    var value: String       // mono value, e.g. "1,4 ГБ" — NEVER contains the verb
    var verb: String
    var explanation: String // tooltip copy: why it is safe / what the action runs
    var action: AdviceAction? = nil
    var id: String { "\(object)|\(value)" }
}

/// Whether the security / updates groups have nothing to show — used by a later
/// block to collapse them into a single quiet line instead of an empty section.
struct QuietState: Equatable {
    var securityQuiet: Bool
    var updatesQuiet: Bool

    static func quiet(report: FullReport) -> QuietState {
        let securityQuiet: Bool
        if let sec = report.security,
           let fileVault = sec.fileVault, let gatekeeper = sec.gatekeeper,
           let sip = sec.sip, let firewall = sec.firewall {
            securityQuiet = fileVault && gatekeeper && sip && firewall
        } else {
            securityQuiet = false   // not-yet-collected (or any nil field) is not quiet
        }
        let updatesQuiet = (report.updates?.isEmpty ?? false) && (report.crashes?.isEmpty ?? false)
        return QuietState(securityQuiet: securityQuiet, updatesQuiet: updatesQuiet)
    }
}

enum AttentionModel {
    /// Resolves the string table for a language other than the process-current
    /// one (the algorithmic helpers below take `lang` explicitly rather than
    /// reading the global `L`, since they may be evaluated for a language the UI
    /// isn't currently showing, e.g. Checks exercising both).
    private static func S(_ lang: AppLanguage) -> AppStrings { lang == .en ? StringsEN() : StringsRU() }

    /// RU word forms for 1...20, lowercase, agreeing with the feminine noun
    /// "задача" (index 0 unused; 1 and 2 are "одна"/"две", not the raw cardinal).
    private static let ruWords: [String] = [
        "", "одна", "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять",
        "одиннадцать", "двенадцать", "тринадцать", "четырнадцать", "пятнадцать", "шестнадцать",
        "семнадцать", "восемнадцать", "девятнадцать", "двадцать",
    ]
    private static func ruWordForm(_ n: Int) -> String { ruWords[n] }

    private static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    /// RU noun/verb agreement for "N задача(и/-) требует(ют) внимания", shared by
    /// both the word-form (1...20) and digit-form (>20) branches.
    private static func ruTaskPhrase(_ n: Int) -> String {
        let m100 = n % 100, m10 = n % 10
        if m10 == 1 && m100 != 11 { return "задача требует внимания" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "задачи требуют внимания" }
        return "задач требуют внимания"
    }

    static func summaryTitle(count: Int, lang: AppLanguage) -> String {
        let n = max(0, count)
        if lang == .en {
            switch n {
            case 0: return "Everything is fine"
            case 1: return "1 item needs attention"
            default: return "\(n) items need attention"
            }
        }
        if n == 0 { return "Всё в порядке" }
        let phrase = ruTaskPhrase(n)
        if (1...6).contains(n) {
            return "\(capitalized(ruWordForm(n))) \(phrase)"
        }
        return "\(n) \(phrase)"
    }

    /// Single source of truth for the action verb shown on an item/capsule.
    static func verb(for action: AdviceAction?, lang: AppLanguage) -> String {
        guard let action else { return "" }
        let s = S(lang)
        switch action {
        case .settingsPane:
            return s.attnVerbSettings
        case .openApp(let path):
            if path == AdviceApps.activityMonitor { return s.attnVerbActivityMonitor }
            if path == AdviceApps.diskUtility { return s.attnVerbDiskUtility }
            return s.attnVerbOpen
        case .revealPath:
            return s.attnVerbShow
        case .emptyTrash:
            return s.attnVerbEmpty
        case .enableFirewall:
            return s.attnVerbEnable
        case .brewUpgrade:
            return s.attnVerbUpgrade
        }
    }
}
