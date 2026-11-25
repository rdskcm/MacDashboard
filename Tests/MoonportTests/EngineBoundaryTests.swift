// Tests/MoonportTests/EngineBoundaryTests.swift
// ARCH-ENGINE-GUARD: the layering rules that were convention until 2026-10. Source scans only — no process-wide
// state — so this suite stays outside `SerialTests`. Paths come from `#filePath`, so the tests run from any cwd.
import Foundation
import Testing

/// `<package>/Sources/Moonport`.
private let sourcesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests/MoonportTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // package root
    .appendingPathComponent("Sources/Moonport", isDirectory: true)

/// Swift files directly inside `Sources/Moonport/<subdir>` ("" = the top-level files), sorted by name.
private func swiftFiles(_ subdir: String) throws -> [URL] {
    let dir = subdir.isEmpty ? sourcesRoot : sourcesRoot.appendingPathComponent(subdir, isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// Engine sources: `Engine/` plus its `Strings/` subfolder (ARCH-STRINGS-SPLIT: the per-feature string tables).
private func engineFiles() throws -> [URL] { try swiftFiles("Engine") + swiftFiles("Engine/Strings") }

/// Per-line code of a file: `//` comments and string-literal text removed, code inside interpolations kept.
/// Understands `"…"`, multi-line `"""…"""` (state carried across lines) and raw strings `#"…"#` / `#"""…"""#`
/// with any number of `#` (`\#(…)` is their interpolation, a bare `\(` is literal text). A lone `"` with no closing
/// quote on its line stays visible and the rest of the line is scanned as code. `/* */` comments are not handled.
private func codeLines(_ lines: [Substring]) -> [String] {
    var open: Int? = nil   // `#` count of the open multi-line literal; nil = in code
    return lines.map { line in
        let c = Array(line)
        var i = 0
        var out = ""
        if let hashes = open {
            let (code, closed) = scanString(c, &i, hashes: hashes, multiline: true)
            out += code
            guard closed else { return out }
            open = nil
        }
        out += scanCode(c, &i, interpolation: false, open: &open)
        return out
    }
}

/// One line on its own (no literal open before it).
private func codeOnly(_ line: Substring) -> String { codeLines([line])[0] }

/// Code outside string literals; stops at a `//` comment, or (interpolation) at the `)` closing the `\(`.
/// A multi-line opener sets `open` and ends the line (its text starts on the next line).
private func scanCode(_ c: [Character], _ i: inout Int, interpolation: Bool, open: inout Int?) -> String {
    var out = ""
    var depth = 0
    while i < c.count {
        let ch = c[i]
        if ch == "/", i + 1 < c.count, c[i + 1] == "/" { i = c.count; break }
        if ch == "\"" || ch == "#" {
            var j = i
            while j < c.count, c[j] == "#" { j += 1 }
            let hashes = j - i
            if j < c.count, c[j] == "\"" {
                if j + 2 < c.count, c[j + 1] == "\"", c[j + 2] == "\"" { open = hashes; i = c.count; break }
                let start = i
                i = j + 1
                let (code, closed) = scanString(c, &i, hashes: hashes, multiline: false)
                if closed { out += code; continue }
                out += String(c[start...j])   // lone quote: keep it, scan the rest of the line as code
                i = j + 1
                continue
            }
        }
        if interpolation {
            if ch == "(" { depth += 1 }
            else if ch == ")" {
                if depth == 0 { i += 1; return out }
                depth -= 1
            }
        }
        out.append(ch)
        i += 1
    }
    return out
}

/// Consumes literal text after an opening delimiter with `hashes` `#`s; returns the code of its interpolations
/// and whether the closing delimiter (`"` or `"""`, followed by `hashes` `#`s) was found on this line.
private func scanString(_ c: [Character], _ i: inout Int, hashes: Int, multiline: Bool) -> (code: String, closed: Bool) {
    let quotes = multiline ? 3 : 1
    func matches(_ ch: Character, count: Int, at k: Int) -> Bool {
        k + count <= c.count && c[k..<(k + count)].allSatisfy { $0 == ch }
    }
    var out = ""
    while i < c.count {
        if c[i] == "\\", matches("#", count: hashes, at: i + 1) {
            let k = i + 1 + hashes
            if k < c.count, c[k] == "(" {
                i = k + 1
                var nested: Int? = nil
                out += " " + scanCode(c, &i, interpolation: true, open: &nested) + " "
            } else {
                i = k + 1   // an escape: skip the escaped character
            }
            continue
        }
        if matches("\"", count: quotes, at: i), matches("#", count: hashes, at: i + quotes) {
            i += quotes + hashes
            return (out, true)
        }
        i += 1
    }
    return (out, false)
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
        for file in try engineFiles() where Self.engineExceptions[file.lastPathComponent] == nil {
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
            let all = try lines(of: file)
            let codes = codeLines(all)
            for (n, line) in all.enumerated() {
                let code = codes[n]
                if depth == 0, let name = firstGroup(Self.topLevelType, in: String(line)) { viewsTypes.insert(name) }
                depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
            }
        }
        viewsTypes.subtract(Self.knownCollisions)
        #expect(viewsTypes.count > 50, "the Views type scan found only \(viewsTypes.count) names; the regex is broken")
        var offenders: [String] = []
        for file in try engineFiles() where Self.engineExceptions[file.lastPathComponent] == nil {
            var used = Set<String>()
            for code in codeLines(try lines(of: file)) {
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
                let all = try lines(of: file)
                let code = codeLines(all)
                for (i, line) in all.enumerated() where (raw ? String(line) : code[i]).contains(needle) {
                    out.append("\(file.lastPathComponent):\(i + 1)")
                }
            }
        }
        return out
    }

    @Test func movedSideEffectsHaveOneSite() throws {
        let all = ["", "Engine", "Engine/Strings", "Views"]
        let relaunch = try sites("AppLifecycle.relaunch(", in: all)
        #expect(relaunch.count == 1 && relaunch[0].hasPrefix("SettingsView.swift:"),
                "relaunch-single-site: exactly one call site, in SettingsView; found \(relaunch)")
        let languages = try sites("\"AppleLanguages\"", in: all, raw: true)
        #expect(Set(languages.map { $0.split(separator: ":")[0] }) == ["AppShell.swift"],
                "the AppleLanguages write lives only in AppShell.swift; found \(languages)")
        let sync = try sites("AppLifecycle.syncAppleLanguages(", in: all)
        #expect(Set(sync.map { $0.split(separator: ":")[0] }) == ["MoonportApp.swift", "SettingsView.swift"],
                "syncAppleLanguages: launch + language picker; found \(sync)")
        #expect(try sites("ProcessInspector.", in: ["Views"]).isEmpty, "views never call ProcessInspector")
        #expect(try sites("Task.detached", in: ["Views"]).isEmpty, "views never spawn detached tasks")
    }

    @Test func viewsReadNoFixtureHooks() throws {
        let hook = regex(#"\bfixtureNow\b|\bVisualFixture\."#)
        var offenders: [String] = []
        for file in try swiftFiles("Views") where Self.viewsFixtureExceptions[file.lastPathComponent] == nil {
            for (i, code) in codeLines(try lines(of: file)).enumerated() {
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
        let code0 = codeLines(all)
        var body: [String] = []
        for n in (start + 1)..<all.count {
            if all[n] == "    }" { break }
            body.append(code0[n])
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
            for (i, line) in codeLines(try lines(of: file)).enumerated() where line.contains("AppSettings.shared") {
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
        let all = codeLines(try lines(of: try #require(file)))
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
            if codeLines(try lines(of: file)).contains(where: { $0.contains("AppSettings.shared") }) { users.insert(file.lastPathComponent) }
        }
        let allowed = Set(Self.viewsSharedSettingsExceptions.keys)
        #expect(users.subtracting(allowed).isEmpty, "R6: views read settings through model.settings; AppSettings.shared found in \(users.subtracting(allowed).sorted())")
        #expect(allowed.subtracting(users).isEmpty, "R6: stale viewsSharedSettingsExceptions entries: \(allowed.subtracting(users).sorted())")
    }

    // MARK: - ARCH-TEXT-EDGE

    /// `codeOnly` keeps code inside string interpolations and does not treat `//` inside a literal as a comment.
    @Test func codeOnlyKeepsInterpolationsAndLiteralSlashes() {
        let a = codeOnly(#"let s = "x \(L.foo) y""#)
        #expect(a.contains("L.foo"), "interpolated code must survive: \(a)")
        #expect(!a.contains("x ") && !a.contains(" y"), "literal text must be removed: \(a)")
        let nested = codeOnly(#"let s = "\(f(L.bar, (1)))" + L10nStore.x"#)
        #expect(nested.contains("L.bar") && nested.contains("L10nStore"), "nested parentheses: \(nested)")
        let b = codeOnly(#"let u = "http://a"; let v = L.baz // note L.gone"#)
        #expect(b.contains("L.baz"), "code after a literal containing // must survive: \(b)")
        #expect(!b.contains("L.gone") && !b.contains("http"), "comment and literal text removed: \(b)")
    }

    /// A quote with no closing quote on its line does not hide the rest of the line.
    @Test func codeOnlyKeepsCodeAfterALoneQuote() {
        let s = codeOnly(#"let q = "unterminated; let v = L.foo"#)
        #expect(s.contains("L.foo"), "code after a lone quote must stay visible: \(s)")
    }

    /// Raw strings: text and a bare `\(` are literal, `\#(` is interpolation, `"` inside does not close them.
    @Test func codeOnlyUnderstandsRawStrings() {
        let a = codeOnly(##"let r = #"a "quoted" \(L.notCode) b"#; let v = L.bar"##)
        #expect(a.contains("L.bar"), "code after a raw string survives: \(a)")
        #expect(!a.contains("L.notCode") && !a.contains("quoted"), "raw-string text removed, bare \\( is text: \(a)")
        let b = codeOnly(##"let r = #"x \#(L.baz) y"#"##)
        #expect(b.contains("L.baz") && !b.contains("x "), "\\#( is interpolation in a raw string: \(b)")
        let c = codeOnly(###"let r = ##"a "# b \#(L.no) \##(L.yes)"##; let w = L.after"###)
        #expect(c.contains("L.yes") && c.contains("L.after") && !c.contains("L.no"), "two-hash raw string: \(c)")
    }

    /// Multi-line literals: the text of the interior lines is removed, interpolations and code after `"""` are kept.
    @Test func codeLinesCarryMultilineLiterals() {
        let plain: [Substring] = [#"let s = """"#, #"  text "lone L.inText"#, #"  \(L.interp)"#, #"  """ + L.after"#]
        let p = codeLines(plain)
        #expect(p[0].contains("let s =") && !p[1].contains("L.inText") && p[2].contains("L.interp") && p[3].contains("L.after"),
                "plain multi-line literal: \(p)")
        let raw: [Substring] = [##"let s = #""""##, ##"  "# no \(L.no) \#(L.yes)"##, ##"  """# ; let z = L.end"##]
        let r = codeLines(raw)
        #expect(r[1].contains("L.yes") && !r[1].contains("L.no") && r[2].contains("L.end"), "raw multi-line literal: \(r)")
    }

    /// R2: probes, parsers and the assessment take the language as a value; only the view edge reads `L`.
    /// `ReportWriter.swift` is checked above its staleness-caption marker (the helpers below it are card captions).
    @Test func engineProbesReadNoUILanguage() throws {
        let probeFiles = ["Parsers.swift", "LiveCollector.swift", "ReportCollector.swift", "WakeHolders.swift",
                          "BackupLog.swift", "Assessment.swift", "LaunchdPlistInspector.swift", "ReportWriter.swift"]
        let marker = "// MARK: - Report staleness caption time"
        let globalL = regex(#"(?<![A-Za-z0-9_])L\."#)
        let store = regex(#"L10nStore"#)
        var offenders: [String] = []
        for name in probeFiles {
            let file = try #require(try swiftFiles("Engine").first { $0.lastPathComponent == name }, "\(name) not found")
            var scanned = 0
            let all = try lines(of: file)
            let codes = codeLines(all)
            for (i, line) in all.enumerated() {
                if name == "ReportWriter.swift", line.contains(marker) { break }
                scanned += 1
                let code = codes[i]
                let range = NSRange(code.startIndex..., in: code)
                if globalL.firstMatch(in: code, range: range) != nil || store.firstMatch(in: code, range: range) != nil {
                    offenders.append("\(name):\(i + 1)")
                }
            }
            #expect(scanned > 20, "\(name): only \(scanned) lines scanned; the marker or the scan is broken")
        }
        #expect(offenders.isEmpty, "R2 (ARCH-TEXT-EDGE): these files read the UI language global; pass `language:` instead: \(offenders)")
    }
}
