// Engine/L10n.swift
// In-app localization core: the language enums, `AppStrings` (the composition of the per-feature string
// protocols in Engine/Strings/), the StringsEN/StringsRU structs, `ruPlural`, `L10nStore` and `var L`.
// Foundation-only: also covered by Tests/MacDashboardTests.
import Foundation
import Observation

enum AppLanguage: String, CaseIterable {
    case ru, en
}

/// REDESIGN-SETTINGS: the persisted language choice; `system` follows the macOS preferred language.
enum LanguageChoice: String, CaseIterable { case system, en, ru }

extension LanguageChoice {
    /// Effective language for a choice; `system` follows the first preferred language (`ru…` → RU, anything else → EN).
    static func resolve(_ c: LanguageChoice, preferredLanguages: [String]) -> AppLanguage {
        switch c {
        case .en: return .en
        case .ru: return .ru
        case .system: return (preferredLanguages.first ?? "").hasPrefix("ru") ? .ru : .en
        }
    }
}

/// The full UI string table: the composition of the per-feature protocols in Engine/Strings/.
/// Each Engine/Strings/Strings+<Feature>.swift holds one feature protocol, the English table
/// (`extension StringsEN`, the reference) and the Russian table (`extension StringsRU`, the
/// translation). A key missing from either table is a compile error. Parameterized strings are
/// funcs returning plain String (never LocalizedStringKey — avoids SwiftUI's interpolation-localization trap).
protocol AppStrings: SettingsStrings, CommonStrings, OverviewStrings, SecurityStrings, ReportStrings,
    StorageStrings, MemoryStrings, CPUStrings, MaintenanceStrings, BackupsStrings,
    HistoryStrings, BatteryStrings, SystemStrings, AttentionStrings, IPhoneStrings,
    IPhoneLogsStrings, IPSWStrings, HomeStrings {}

/// English string table, the reference. Its members are the `extension StringsEN` parts of Engine/Strings/.
struct StringsEN: AppStrings {}

/// Russian string table, the translation of StringsEN. Its members are the `extension StringsRU` parts of Engine/Strings/.
struct StringsRU: AppStrings {}

/// Russian plural picker: ruPlural(1, ...)="цикл", (2)="цикла", (5)="циклов",
/// (11)="циклов", (21)="цикл". Standard Russian plural-form rules.
func ruPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m100 = abs(n) % 100, m10 = abs(n) % 10
    if (11...14).contains(m100) { return many }
    switch m10 {
    case 1: return one
    case 2...4: return few
    default: return many
    }
}

/// Current-language holder. @Observable so any SwiftUI body that reads `L`
/// re-renders instantly on language change; Engine code reads the same global at
/// collection time (its output refreshes on the next tick — accepted design).
@Observable
final class L10nStore {
    static let shared = L10nStore()
    /// Language the process started with — UI offers «Relaunch Now» only while
    /// the current choice differs (menus/system chrome are fixed at launch).
    static let launchLanguage: AppLanguage = shared.language
    static let defaultsKey = "appLanguage"
    static let choiceKey = "appLanguageChoice"

    var choice: LanguageChoice {
        didSet {
            UserDefaults.standard.set(choice.rawValue, forKey: Self.choiceKey)
            language = LanguageChoice.resolve(choice, preferredLanguages: Locale.preferredLanguages)
        }
    }

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private var localeObserver: NSObjectProtocol?

    private init() {
        let d = UserDefaults.standard
        let initial: LanguageChoice
        if let raw = d.string(forKey: Self.choiceKey), let c = LanguageChoice(rawValue: raw) {
            initial = c
        } else if let raw = d.string(forKey: Self.defaultsKey), let lang = AppLanguage(rawValue: raw) {
            // An existing install: the stored language stays an explicit choice (D9).
            initial = lang == .ru ? .ru : .en
        } else {
            initial = .system
        }
        choice = initial
        language = LanguageChoice.resolve(initial, preferredLanguages: Locale.preferredLanguages)
        localeObserver = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.choice == .system else { return }
            let l = LanguageChoice.resolve(.system, preferredLanguages: Locale.preferredLanguages)
            if l != self.language { self.language = l }
        }
    }
}

extension AppStrings {
    /// Toggle label of a notify category — also the notification title (D5).
    func settingsNotifyLabel(_ c: NotifyCategory) -> String {
        switch c {
        case .protection: return settingsNotifyProtection
        case .disk: return settingsNotifyDisk
        case .battery: return settingsNotifyBattery
        case .backup: return settingsNotifyBackup
        case .updates: return settingsNotifyUpdates
        case .crashes: return settingsNotifyCrashes
        }
    }
}

var L: AppStrings { L10nStore.shared.language == .en ? StringsEN() : StringsRU() }
