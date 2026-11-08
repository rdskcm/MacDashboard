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
    /// Cyrillic is allowed in code outside the Russian tables only at these sites.
    static let exceptions: [String: String] = ["L10n.swift": "AppLanguage.endonym: the Russian language's own name"]

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

    @Test func cyrillicOnlyInRussianTables() throws {
        var offenders: [String] = []
        for sub in ["", "Engine", "Engine/Strings", "Views"] {
            for file in try swiftFiles(sub) {
                let all = try lines(of: file)
                let name = file.lastPathComponent
                let inStrings = sub == "Engine/Strings"
                let ruStart = all.firstIndex { $0.hasPrefix("extension StringsRU") } ?? Int.max
                for (i, line) in all.enumerated() where hasCyrillic(splitComment(line).code) {
                    if inStrings && i >= ruStart { continue }
                    if Self.exceptions[name] != nil { continue }
                    offenders.append("\(sub.isEmpty ? "" : sub + "/")\(name):\(i + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "Cyrillic in code outside the Russian tables: \(offenders.joined(separator: ", "))")
    }
}
