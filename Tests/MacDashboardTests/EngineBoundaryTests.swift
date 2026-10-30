// Tests/MacDashboardTests/EngineBoundaryTests.swift
// ARCH-ENGINE-GUARD: the layering rules that were convention until 2026-10. Source scans only — no process-wide
// state — so this suite stays outside `SerialTests`. Paths come from `#filePath`, so the tests run from any cwd.
import Foundation
import Testing

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

/// One source line with its `//` comment and simple one-line string literals removed.
private func codeOnly(_ line: Substring) -> String {
    let noComment = line.range(of: "//").map { line[..<$0.lowerBound] } ?? line
    return noComment.replacingOccurrences(of: #""(?:[^"\\]|\\.)*""#, with: "", options: .regularExpression)
}

private func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

private func firstGroup(_ re: NSRegularExpression, in s: String) -> String? {
    guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          let r = Range(m.range(at: 1), in: s) else { return nil }
    return String(s[r])
}

private func lines(of file: URL) throws -> [Substring] {
    try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
}

struct EngineBoundaryTests {
    /// Frameworks that make a file UI-bound. System frameworks without UI (IOKit, IOSurface, CoreGraphics,
    /// ServiceManagement, UserNotifications, Observation) stay allowed.
    static let bannedImports: Set<String> = ["AppKit", "SwiftUI", "Cocoa", "Charts"]
    /// Engine files exempt from both Engine checks, with the reason. Keep it empty; an entry needs a reason and a block.
    static let engineExceptions: [String: String] = [:]
    /// Identifiers that are top-level Views type names AND unrelated Engine member/local names (none known).
    static let knownCollisions: Set<String> = []
    /// Views files allowed to read the harness flag, with the reason.
    static let viewsFixtureExceptions: [String: String] = [
        "DS3Theme.swift": "DS3Motion.isFrozen: the design system's one motion switch; views read it, not the flag",
    ]

    static let importLine = regex(#"^\s*(?:@\w+\s+)*import\s+(?:(?:class|struct|enum|protocol|func|var|let|typealias)\s+)?(\w+)"#)
    /// Type declarations; collected only at brace depth 0
    /// (a nested Views type is reachable from Engine only through its outer name).
    static let topLevelType = regex(
        #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|internal\s+)?(?:final\s+)?"#
        + #"(?:struct|enum|class|actor|protocol)\s+(\w+)"#)
    static let identifier = regex(#"[A-Za-z_]\w*"#)

    @Test func engineImportsNoUIFramework() throws {
        var offenders: [String] = []
        for file in try swiftFiles("Engine") where Self.engineExceptions[file.lastPathComponent] == nil {
            for line in try lines(of: file) {
                if let module = firstGroup(Self.importLine, in: String(line)), Self.bannedImports.contains(module) {
                    offenders.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty, "Engine is Foundation-only (ARCH-ENGINE-GUARD); UI-framework imports: \(offenders)")
    }

    @Test func engineReferencesNoViewsType() throws {
        var viewsTypes = Set<String>()
        for file in try swiftFiles("Views") {
            var depth = 0
            for line in try lines(of: file) {
                let code = codeOnly(line)
                if depth == 0, let name = firstGroup(Self.topLevelType, in: String(line)) { viewsTypes.insert(name) }
                depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
            }
        }
        viewsTypes.subtract(Self.knownCollisions)
        #expect(viewsTypes.count > 50, "the Views type scan found only \(viewsTypes.count) names; the regex is broken")
        var offenders: [String] = []
        for file in try swiftFiles("Engine") where Self.engineExceptions[file.lastPathComponent] == nil {
            var used = Set<String>()
            for line in try lines(of: file) {
                let code = codeOnly(line)
                for m in Self.identifier.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                    if let r = Range(m.range, in: code) { used.insert(String(code[r])) }
                }
            }
            let hits = used.intersection(viewsTypes).sorted()
            if !hits.isEmpty { offenders.append("\(file.lastPathComponent): \(hits)") }
        }
        #expect(offenders.isEmpty, "Engine must not reference Views types (ARCH-ENGINE-GUARD): \(offenders)")
    }

    /// Lines (file:line) whose code part contains `needle`, across the given source dirs.
    private func sites(_ needle: String, in subdirs: [String], raw: Bool = false) throws -> [String] {
        var out: [String] = []
        for dir in subdirs {
            for file in try swiftFiles(dir) {
                for (i, line) in try lines(of: file).enumerated() where (raw ? String(line) : codeOnly(line)).contains(needle) {
                    out.append("\(file.lastPathComponent):\(i + 1)")
                }
            }
        }
        return out
    }

    @Test func movedSideEffectsHaveOneSite() throws {
        let all = ["", "Engine", "Views"]
        let relaunch = try sites("AppLifecycle.relaunch(", in: all)
        #expect(relaunch.count == 1 && relaunch[0].hasPrefix("SettingsView.swift:"),
                "relaunch-single-site: exactly one call site, in SettingsView; found \(relaunch)")
        let languages = try sites("\"AppleLanguages\"", in: all, raw: true)
        #expect(Set(languages.map { $0.split(separator: ":")[0] }) == ["AppShell.swift"],
                "the AppleLanguages write lives only in AppShell.swift; found \(languages)")
        let sync = try sites("AppLifecycle.syncAppleLanguages(", in: all)
        #expect(Set(sync.map { $0.split(separator: ":")[0] }) == ["MacDashboardApp.swift", "SettingsView.swift"],
                "syncAppleLanguages: launch + language picker; found \(sync)")
        #expect(try sites("ProcessInspector.", in: ["Views"]).isEmpty, "views never call ProcessInspector")
        #expect(try sites("Task.detached", in: ["Views"]).isEmpty, "views never spawn detached tasks")
    }

    @Test func viewsReadNoFixtureHooks() throws {
        let hook = regex(#"\bfixtureNow\b|\bVisualFixture\."#)
        var offenders: [String] = []
        for file in try swiftFiles("Views") where Self.viewsFixtureExceptions[file.lastPathComponent] == nil {
            for (i, line) in try lines(of: file).enumerated() {
                let code = codeOnly(line)
                if hook.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil {
                    offenders.append("\(file.lastPathComponent):\(i + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "views get the clock from model.now() and never read the harness flag (ARCH-ENGINE-GUARD): \(offenders)")
    }

    // MARK: - ARCH-SETTINGS-PATH

    /// Views files that keep `AppSettings.shared`, with the reason (D11).
    static let viewsSharedSettingsExceptions: [String: String] = [
        "DS3Surfaces.swift": "orb backdrop modifier: no AppModel in scope; display-only preference",
        "IPhoneImportCard.swift": "iPhone feature: IPhoneModel owns its settings reads (ARCH-MODEL-SPLIT)",
    ]

    @Test func assessedReadsSettingsOnlyThroughAssessmentSettings() throws {
        let file = sourcesRoot.appendingPathComponent("Engine/AppModel.swift")
        let all = try lines(of: file)
        let start = try #require(all.firstIndex { $0.contains("func assessed(_ r: FullReport)") }, "assessed(_:) not found in AppModel.swift")
        var body: [String] = []
        for line in all[(start + 1)...] {
            if line == "    }" { break }
            body.append(codeOnly(line))
        }
        let code = body.joined(separator: "\n")
        let marker = "settings.assessmentSettings"
        #expect(code.components(separatedBy: marker).count - 1 == 1,
                "R3: assessed(_:) in AppModel.swift must read settings exactly once, through \(marker)")
        let rest = code.replacingOccurrences(of: marker, with: "")
        #expect(rest.range(of: #"\bsettings\b"#, options: .regularExpression) == nil && !rest.contains("AppSettings"),
                "R3: assessed(_:) in AppModel.swift reads a setting outside settings.assessmentSettings")
    }

    /// Files that take settings through the coordinator's init (ARCH-SETTINGS-PATH R5): the coordinator, every
    /// feature controller of the ARCH-MODEL-SPLIT series and the seam files. Every block of the series appends
    /// its controller file to `modelFilesMustInclude`.
    static func isModelFile(_ name: String) -> Bool {
        name.hasPrefix("AppModel") || name.hasSuffix("Controller.swift")
            || ["ReportHost.swift", "TimeSource.swift"].contains(name)
    }
    static let modelFilesMustInclude: Set<String> = ["AppModel.swift", "BrewController.swift", "EnergyController.swift", "StartupItemsController.swift", "TimeMachineController.swift", "SmartToolsController.swift", "CrashReportsController.swift", "SecurityController.swift", "StorageController.swift", "HistoryController.swift", "ReportHost.swift", "TimeSource.swift"]

    @Test func appModelHasNoSharedSettings() throws {
        var offenders: [String] = []
        var matched: Set<String> = []
        for file in try swiftFiles("Engine") where Self.isModelFile(file.lastPathComponent) {
            matched.insert(file.lastPathComponent)
            for (i, line) in try lines(of: file).enumerated() where codeOnly(line).contains("AppSettings.shared") {
                offenders.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        #expect(matched.isSuperset(of: Self.modelFilesMustInclude), "R5 guard lost a file it must cover: \(matched.sorted())")
        #expect(offenders.isEmpty, "R5: the coordinator and its controllers take settings through init (model.settings), never AppSettings.shared: \(offenders)")
    }

    /// ARCH-MODEL-SPLIT: the coordinator's stop() fans out to every controller's stop() (blocks append theirs).
    /// HistoryController (block 8) owns no Task and has no stop(), so it is not in the list.
    @Test func coordinatorStopFansOutToControllers() throws {
        let file = try swiftFiles("Engine").first { $0.lastPathComponent == "AppModel.swift" }
        let all = try lines(of: try #require(file)).map(codeOnly)
        let start = try #require(all.firstIndex { $0.contains("func stop() {") })
        var body: [String] = []
        for line in all[(start + 1)...] {
            if line.hasPrefix("    }") { break }
            body.append(line)
        }
        for call in ["energy.stop()", "brew.stop()", "startupItems.stop()", "timeMachine.stop()", "smart.stop()", "crashReports.stop()", "security.stop()", "storage.stop()"] {
            #expect(body.contains { $0.contains(call) }, "AppModel.stop() must call \(call)")
        }
    }

    @Test func viewsReadSettingsThroughTheModel() throws {
        var users: Set<String> = []
        for file in try swiftFiles("Views") {
            if try lines(of: file).contains(where: { codeOnly($0).contains("AppSettings.shared") }) { users.insert(file.lastPathComponent) }
        }
        let allowed = Set(Self.viewsSharedSettingsExceptions.keys)
        #expect(users.subtracting(allowed).isEmpty, "R6: views read settings through model.settings; AppSettings.shared found in \(users.subtracting(allowed).sorted())")
        #expect(allowed.subtracting(users).isEmpty, "R6: stale viewsSharedSettingsExceptions entries: \(allowed.subtracting(users).sorted())")
    }
}
