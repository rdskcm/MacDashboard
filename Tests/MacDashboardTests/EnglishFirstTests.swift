// Tests/MacDashboardTests/EnglishFirstTests.swift
// ENGLISH-DEFAULT: the English-first rules as tests. Source scans and pure table reads, no process-wide state,
// so this suite stays outside `SerialTests` (like `EngineBoundaryTests`). Nothing here touches `L10nStore` or `L`.
import Foundation
import Testing
@testable import MacDashboard

/// `<package>/Sources/MacDashboard`.
private let sourcesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests/MacDashboardTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // package root
    .appendingPathComponent("Sources/MacDashboard", isDirectory: true)

/// The package root (the directory holding `Package.swift`).
private let packageRootURL = sourcesRoot.deletingLastPathComponent().deletingLastPathComponent()

/// Swift files directly inside `Sources/MacDashboard/<subdir>` ("" = the top-level files), sorted by name.
private func swiftFiles(_ subdir: String) throws -> [URL] {
    let dir = subdir.isEmpty ? sourcesRoot : sourcesRoot.appendingPathComponent(subdir, isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func lines(of file: URL) throws -> [Substring] {
    try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
}

/// Splits one source line at the first `//` outside a `"..."` literal (a backslash escapes the next character).
private func splitComment(_ line: Substring) -> (code: String, comment: String) {
    var inString = false
    var escaped = false
    var prevSlash = false
    var idx = line.startIndex
    while idx < line.endIndex {
        let ch = line[idx]
        if inString {
            if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
        } else if ch == "\"" {
            inString = true
            prevSlash = false
        } else if ch == "/" {
            if prevSlash {
                let start = line.index(before: idx)
                return (String(line[line.startIndex..<start]), String(line[start...]))
            }
            prevSlash = true
        } else {
            prevSlash = false
        }
        idx = line.index(after: idx)
    }
    return (String(line), "")
}

private func hasCyrillic(_ s: String) -> Bool {
    s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
}

struct EnglishFirstTests {
    /// Cyrillic is allowed in code outside the Russian tables only at this site: the Russian endonym line of
    /// `AppLanguage.endonym` in `L10n.swift`, matched by its exact trimmed text.
    static let endonymLine = "case .ru: return \"Русский\""

    // MARK: Moved tables

    @Test func launchdTablesHaveTheSameKeys() {
        let en = StringsEN().autostartCuratedDescriptions
        let ru = StringsRU().autostartCuratedDescriptions
        #expect(Set(en.keys) == Set(ru.keys))
        #expect(en.count == 29)
        #expect(ru.count == 29)
        #expect(en.values.allSatisfy { !$0.isEmpty })
        #expect(ru.values.allSatisfy { !$0.isEmpty })
    }

    /// Rows copied from `LaunchdPlistInspector.curatedDescriptions` at `0e3e1f7` (label, en, ru).
    static let launchdRows: [(String, String, String)] = [
        // Apple system agents/daemons
        ("com.apple.cloudd", "iCloud — data sync", "iCloud — синхронизация данных"),
        ("com.apple.bird", "iCloud Drive — file sync", "iCloud Drive — синхронизация файлов"),
        ("com.apple.suggestd", "Spotlight — suggestions", "Spotlight — предложения и рекомендации"),
        ("com.apple.AirPlayXPCHelper", "AirPlay — helper process", "AirPlay — вспомогательный процесс"),
        ("com.apple.security.pboxd", "Sandbox — app privacy boxing", "Sandbox — изоляция приложений (Privacy Sandbox)"),
        ("com.apple.spindump", "Hang/crash diagnostics", "Диагностика зависаний процессов"),
        ("com.apple.softwareupdated", "macOS software updates", "Обновления macOS"),
        ("com.apple.coreduetd", "CoreDuet — app usage prediction", "CoreDuet — предсказание использования приложений"),
        ("com.apple.photoanalysisd", "Photos — on-device analysis", "Фото — анализ и распознавание объектов"),
        ("com.apple.mediaanalysisd", "Media analysis (photos/video)", "Медиа — анализ фото/видео"),
        ("com.apple.corespotlightd", "Spotlight — indexing", "Spotlight — индексация"),
        ("com.apple.spotlight.Siri", "Spotlight — Siri integration", "Spotlight — интеграция с Siri"),
        ("com.apple.familycircled", "Family Sharing", "Семейный доступ"),
        ("com.apple.notificationcenterui.agent", "Notification Center", "Центр уведомлений"),
        ("com.apple.rapportd", "Handoff / Continuity", "Handoff / Continuity"),
        ("com.apple.sharingd", "AirDrop / Sharing", "AirDrop / Общий доступ"),
        ("com.apple.parsecd", "Maps/Weather background data", "Карты/погода — фоновые данные"),
        ("com.apple.commerce", "App Store — commerce background service", "App Store — фоновая служба покупок"),
        // Common third-party vendor agents
        ("com.google.keystone.agent", "Google Keystone — Google app auto-update", "Google Keystone — автообновление Google-приложений"),
        ("com.google.keystone.daemon", "Google Keystone — Google app auto-update", "Google Keystone — автообновление Google-приложений"),
        ("com.microsoft.autoupdate.helper", "Microsoft AutoUpdate — Microsoft app updates", "Microsoft AutoUpdate — обновление приложений Microsoft"),
        ("com.microsoft.update.agent", "Microsoft AutoUpdate — Microsoft app updates", "Microsoft AutoUpdate — обновление приложений Microsoft"),
        ("com.docker.helper", "Docker Desktop — privileged helper", "Docker Desktop — системный помощник"),
        ("com.docker.vmnetd", "Docker Desktop — VM networking daemon", "Docker Desktop — сетевой демон виртуальных машин"),
        ("com.spotify.webhelper", "Spotify — web helper", "Spotify — веб-помощник"),
        ("com.adobe.acc.installer.v2", "Adobe Creative Cloud — update installer", "Adobe Creative Cloud — установщик обновлений"),
        ("com.adobe.ARMDC.Communicator", "Adobe — update service (ARM)", "Adobe — служба обновлений (ARM)"),
        ("com.valvesoftware.steamclean", "Steam — cache cleanup", "Steam — очистка кэша"),
        ("com.dropbox.DropboxMacUpdate.agent", "Dropbox — auto-update", "Dropbox — автообновление"),
    ]

    @Test func launchdCuratedValuesUnchanged() {
        #expect(Self.launchdRows.count == 29)
        for (label, en, ru) in Self.launchdRows {
            #expect(LaunchdPlistInspector.description(forLabel: label, language: .en) == en, "\(label) en")
            #expect(LaunchdPlistInspector.description(forLabel: label, language: .ru) == ru, "\(label) ru")
        }
        #expect(LaunchdPlistInspector.heuristicDescription(forLabel: "com.acmecorp.helper.v2", language: .ru) == "Acmecorp \u{2014} \u{0444}\u{043E}\u{043D}\u{043E}\u{0432}\u{044B}\u{0439} \u{043F}\u{0440}\u{043E}\u{0446}\u{0435}\u{0441}\u{0441}")
        #expect(LaunchdPlistInspector.heuristicDescription(forLabel: "com.acmecorp.helper.v2", language: .en) == "Acmecorp \u{2014} background process")
        #expect(LaunchdPlistInspector.heuristicDescription(forLabel: "com", language: .ru) == "\u{0424}\u{043E}\u{043D}\u{043E}\u{0432}\u{044B}\u{0439} \u{043F}\u{0440}\u{043E}\u{0446}\u{0435}\u{0441}\u{0441}")
        #expect(LaunchdPlistInspector.heuristicDescription(forLabel: "com", language: .en) == "Background process")
    }

    @Test func protectedAppNamesUnchanged() {
        #expect(ProtectedApp.allCases.map { StringsEN().storageProtectedAppName($0) }
                == ["Mail", "Messages", "Safari", "Contacts", "Calendar", "Notes", "Home"])
        #expect(ProtectedApp.allCases.map { StringsRU().storageProtectedAppName($0) }
                == ["Почта", "Сообщения", "Safari", "Контакты", "Календарь", "Заметки", "Дом"])
        #expect(ProtectedLocations.table.map(\.app) == ProtectedApp.allCases)
    }

    // MARK: R1

    /// Cyrillic code is allowed only in the Russian section of a file under `Engine/Strings`, and on the endonym line.
    /// The Russian section starts at a column-0 line beginning a `StringsRU` extension (`extension StringsRU`, or with
    /// any access modifier, e.g. `private extension StringsRU`). It ends at the next column-0 declaration
    /// (`extension`, `protocol`, `struct`, `enum`, `class`, `func`, `let`, `var`, with optional modifiers) that is
    /// not a `StringsRU` extension and not a `private`/`fileprivate` `func` or `let` (Russian-grammar helpers).
    /// Other lines (for example a `StringsEN` extension) are outside the section, so Cyrillic there is an offender.
    @Test func cyrillicOnlyInRussianTables() throws {
        let modifier = "(?:(?:public|internal|private|fileprivate|final|static)\\s+)*"
        let ruStart = try Regex("^\(modifier)extension\\s+StringsRU\\b")
        let declaration = try Regex("^\(modifier)(?:extension|protocol|struct|enum|class|func|let|var)\\b")
        let helper = try Regex("^(?:private|fileprivate)\\s+(?:func|let)\\b")
        var offenders: [String] = []
        for sub in ["", "Engine", "Engine/Strings", "Views"] {
            for file in try swiftFiles(sub) {
                let all = try lines(of: file)
                let name = file.lastPathComponent
                let inStrings = sub == "Engine/Strings"
                var inRussian = false
                for (i, line) in all.enumerated() {
                    if inStrings {
                        if line.firstMatch(of: ruStart) != nil {
                            inRussian = true
                        } else if inRussian, line.firstMatch(of: declaration) != nil, line.firstMatch(of: helper) == nil {
                            inRussian = false
                        }
                    }
                    let code = splitComment(line).code
                    guard hasCyrillic(code) else { continue }
                    if inRussian { continue }
                    if name == "L10n.swift", code.trimmingCharacters(in: .whitespaces) == Self.endonymLine { continue }
                    offenders.append("\(sub.isEmpty ? "" : sub + "/")\(name):\(i + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "Cyrillic in code outside the Russian tables: \(offenders.joined(separator: ", "))")
    }

    // MARK: R4, R7

    @Test func tablesSelectByLanguage() {
        #expect(AppLanguage.en.strings is StringsEN)
        #expect(AppLanguage.ru.strings is StringsRU)
        #expect(AppLanguage.allCases == [.en, .ru])
        #expect(AppLanguage.en.localeIdentifier == "en_US")
        #expect(AppLanguage.ru.localeIdentifier == "ru_RU")
        #expect(LanguageChoice.allCases == [.system, .en, .ru])
    }

    @Test func tmBackupDateIsLocaleFree() {
        // 1_784_197_800 = 2026-07-16 10:30:00 UTC
        let date = Date(timeIntervalSince1970: 1_784_197_800)
        #expect(Parsers.formatTMBackupDate(date, timeZone: TimeZone(identifier: "UTC")!) == "16.07.2026, 10:30")
        #expect(Parsers.formatTMBackupDate(date, timeZone: TimeZone(identifier: "Europe/Moscow")!) == "16.07.2026, 13:30")
    }

    /// Opt-in: prints the Mac's first preferred language and what `.system` resolves to, and asserts the mapping.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
    func liveCanaryFirstLaunchLanguage() {
        let first = Locale.preferredLanguages.first ?? ""
        let resolved = LanguageChoice.resolve(.system, preferredLanguages: Locale.preferredLanguages)
        print("liveCanaryFirstLaunchLanguage preferred=\(first) resolved=\(resolved)")
        #expect(resolved == (first.hasPrefix("ru") ? .ru : .en))
    }

    // MARK: R2 (Stage 3)

    /// Every `.swift` under `Sources/MacDashboard`, `Tests/MacDashboardTests` and `tools`, and every `.sh` under `tools`,
    /// skipping the gitignored run output `tools/perf/out/` and `tools/visual/out/`.
    private static func commentScanFiles() -> [URL] {
        let root = packageRootURL
        let skipped = [root.appendingPathComponent("tools/perf/out").path, root.appendingPathComponent("tools/visual/out").path]
        var result: [URL] = []
        for sub in ["Sources/MacDashboard", "Tests/MacDashboardTests", "tools"] {
            let base = root.appendingPathComponent(sub, isDirectory: true)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                if skipped.contains(where: { url.path.hasPrefix($0) }) { continue }
                let ext = url.pathExtension
                if ext == "swift" || (ext == "sh" && sub == "tools") { result.append(url) }
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    /// Splits one shell line at the first `#` outside `"..."` and `'...'` and not part of `$#` or `${#...}`.
    private static func splitShellComment(_ line: Substring) -> String {
        var quote: Character?
        var prev: Character?
        var prev2: Character?
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == "#" && prev != "$" && !(prev == "{" && prev2 == "$") {
                return String(line[idx...])
            }
            prev2 = prev
            prev = ch
            idx = line.index(after: idx)
        }
        return ""
    }

    @Test func noCyrillicComments() throws {
        var offenders: [String] = []
        let prefix = packageRootURL.path + "/"
        for file in Self.commentScanFiles() {
            let isShell = file.pathExtension == "sh"
            for (i, line) in try lines(of: file).enumerated() {
                let comment = isShell ? Self.splitShellComment(line) : splitComment(line).comment
                if hasCyrillic(comment) {
                    offenders.append("\(file.path.hasPrefix(prefix) ? String(file.path.dropFirst(prefix.count)) : file.path):\(i + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "Cyrillic in comments: \(offenders.joined(separator: ", "))")
    }

    // MARK: R3 (Stage 3)

    /// Per `Engine/Strings/Strings+*.swift`: the protocol, the EN table and the RU table declare the same members,
    /// none of them empty. A Russian-grammar helper in the RU extension must be `private` (it is then not counted).
    /// The counts are printed in the failure/diagnostic message only, never asserted.
    @Test func stringTablesComplete() throws {
        let memberPattern = try NSRegularExpression(pattern: #"^    (?:var|func) (\w+)"#)
        let emptyPatterns = try [#"\{\s*""\s*\}"#, #"^\s*""\s*$"#, #"^\s*return\s+""\s*$"#].map { try NSRegularExpression(pattern: $0) }
        func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
            re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        var problems: [String] = []
        var counts: [(String, Int)] = []
        let dir = sourcesRoot.appendingPathComponent("Engine/Strings", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Strings+") && $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            let name = file.lastPathComponent
            var names: [String: [String]] = ["protocol": [], "EN": [], "RU": []]
            var section: String?
            for (i, raw) in try lines(of: file).enumerated() {
                let line = String(raw)
                if line.hasPrefix("protocol ") { section = "protocol"; continue }
                if line.hasPrefix("extension StringsEN") { section = "EN"; continue }
                if line.hasPrefix("extension StringsRU") { section = "RU"; continue }
                guard let sec = section else { continue }
                let code = splitComment(raw).code
                guard let m = memberPattern.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
                      let r = Range(m.range(at: 1), in: code) else {
                    if sec != "protocol", emptyPatterns.dropFirst().contains(where: { matches($0, code) }) {
                        problems.append("\(name):\(i + 1) empty value")
                    }
                    continue
                }
                names[sec]?.append(String(code[r]))
                if sec != "protocol", matches(emptyPatterns[0], code) || emptyPatterns.dropFirst().contains(where: { matches($0, code) }) {
                    problems.append("\(name):\(i + 1) empty value")
                }
            }
            let p = Set(names["protocol"]!), e = Set(names["EN"]!), r = Set(names["RU"]!)
            if p.isEmpty { problems.append("\(name): no protocol members") }
            if p != e { problems.append("\(name): protocol vs EN differ: \(p.symmetricDifference(e).sorted())") }
            if p != r { problems.append("\(name): protocol vs RU differ: \(p.symmetricDifference(r).sorted())") }
            counts.append((name.replacingOccurrences(of: "Strings+", with: "").replacingOccurrences(of: ".swift", with: ""), p.count))
        }
        let total = counts.reduce(0) { $0 + $1.1 }
        let printout = counts.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        print("stringTablesComplete keys per table: \(printout); total \(total) per table (expected 1330 at Stage 1)")
        #expect(problems.isEmpty, "\(problems.joined(separator: "; ")). Keys per table: \(printout); total \(total)")
        #expect(!counts.isEmpty)
    }
}
