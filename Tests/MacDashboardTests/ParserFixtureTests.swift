// Tests/MacDashboardTests/ParserFixtureTests.swift
// CI-SWIFT-TESTING: swift-testing port of the R3 fixture table
// (Checks/ParserFixtureChecks.swift, runParserFixtureChecks). Runs via `swift test` locally
// and in CI; the primary gate is still `swift run MacDashboardChecks`. Same Tests/Fixtures tree, same rules.
import Foundation
import Testing
@testable import MacDashboard

private let fixturesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests/MacDashboardTests
    .deletingLastPathComponent()   // Tests
    .appendingPathComponent("Fixtures", isDirectory: true)

private let garbage = "\u{FFFD}\u{FFFD} <<not command output>> }{ ;;; @@@\n\t~~~ ¿¿ ~~~\n"

/// Same rule as `fixtureNameIsVersioned` in Checks/ParserFixtureChecks.swift:
/// `<command>-macos<major>.<minor>[-<variant>].txt`, variant = lowercase words joined by `-`.
private func isVersionedFixtureName(_ fname: String, command: String) -> Bool {
    let pattern = "^" + NSRegularExpression.escapedPattern(for: command)
        + "-macos[0-9]+\\.[0-9]+(-[a-z0-9]+)*\\.txt$"
    return fname.range(of: pattern, options: .regularExpression) != nil
}

@Test(arguments: [
    ("ps-macos26.3.txt", "ps"),
    ("tmutil-destinationinfo-macos27.0-not-configured.txt", "tmutil-destinationinfo"),
])
func fixtureNameAccepted(fname: String, command: String) {
    #expect(isVersionedFixtureName(fname, command: command))
}

@Test(arguments: [
    ("ps.txt", "ps"),
    ("ps-laptop.txt", "ps"),
    ("ps-macos26.txt", "ps"),
    ("ps-macOS26.3.txt", "ps"),
    ("top-macos26.3.txt", "ps"),
    ("pmset-macos26.3-batt.txt", "pmset-batt"),
    ("ps-macos26.3-.txt", "ps"),
])
func fixtureNameRejected(fname: String, command: String) {
    #expect(!isVersionedFixtureName(fname, command: command))
}

@Test(arguments: ParsedCommand.allCases)
func fixturesParseAsDeclared(_ cmd: ParsedCommand) throws {
    let dir = fixturesRoot.appendingPathComponent(cmd.rawValue, isDirectory: true)
    try #require(FileManager.default.fileExists(atPath: dir.path),
                 "Tests/Fixtures/\(cmd.rawValue) is missing")
    let files = try FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        .filter { $0.lastPathComponent != "README.md" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    var positives = 0
    for file in files {
        let fname = file.lastPathComponent
        let label = "\(cmd.rawValue)/\(fname)"
        #expect(fname.hasSuffix(".txt"), "\(label): fixture names must end in .txt")
        guard fname.hasSuffix(".txt") else { continue }
        let data = try Data(contentsOf: file)
        let text = try #require(String(data: data, encoding: .utf8), "\(label): not readable as UTF-8")
        if fname.hasPrefix("neg-") {
            #expect(!cmd.parses(text), "\(label): negative fixture must be rejected")
        } else {
            positives += 1
            if !fname.contains("synthetic") {
                #expect(isVersionedFixtureName(fname, command: cmd.rawValue),
                        "\(label): real capture must be named \(cmd.rawValue)-macos<major.minor>[-<variant>].txt")
            }
            #expect(cmd.parses(text), "\(label): positive fixture must parse")
            if cmd.isStructured {
                let half = String(text.prefix(text.count / 2))
                #expect(!cmd.parses(half), "\(label): truncated to half must be rejected")
            }
        }
    }
    #expect(positives > 0, "\(cmd.rawValue): needs at least one positive fixture")
    #expect(!cmd.parses(""), "\(cmd.rawValue): empty input must be rejected")
    #expect(!cmd.parses(garbage), "\(cmd.rawValue): garbage must be rejected")
}

@Test func everyFixtureDirectoryNamesACommand() throws {
    let entries = try FileManager.default.contentsOfDirectory(
        at: fixturesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
        #expect(ParsedCommand(rawValue: entry.lastPathComponent) != nil,
                "Tests/Fixtures/\(entry.lastPathComponent) is not a ParsedCommand rawValue")
    }
}
