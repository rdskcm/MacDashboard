// Tests/MacDashboardTests/ParserFixtureTests.swift
// Port of Checks/ParserFixtureChecks.swift (CHECKS-SWIFT-TESTING).
// R3-FIXTURES parts 2-5: table-driven checks over Tests/Fixtures/ (every command's
// parser accepts its positives and rejects its negatives, empty input and garbage,
// and structured positives truncated to half), plus the ParseFailure/writer unit
// checks for the report-time recording of unparsed command output (part 5).
// PARSER-FIXTURES: real captures carry the macOS version in their name.
import Foundation
import Testing
@testable import MacDashboard

/// PARSER-FIXTURES: a real capture's name is `<command>-macos<major>.<minor>[-<variant>].txt`,
/// variant = lowercase words joined by `-`.
func fixtureNameIsVersioned(_ fname: String, command: String) -> Bool {
    let pattern = "^" + NSRegularExpression.escapedPattern(for: command)
        + "-macos[0-9]+\\.[0-9]+(-[a-z0-9]+)*\\.txt$"
    return fname.range(of: pattern, options: .regularExpression) != nil
}

/// Minimal report input: all optionals nil, no tasks; only the parse-failure tail varies.
private func summary(_ failures: [ParseFailure]) -> ReportSummaryInput {
    let at = Date(timeIntervalSince1970: 1_760_000_000)
    return ReportSummaryInput(
        generatedAt: at, system: nil, status: .good, tasks: [], cpu: nil, load: nil, ncpu: 8, socTempC: nil,
        mem: nil, memPressure: nil, swap: nil, disk: nil, hasBattery: false, battery: nil, security: nil,
        claudeBackup: nil, snapshotCount: nil, now: at, parseFailures: failures)
}

extension SerialTests {
    struct ParserFixtureTests {
        @Test func parserFixtures() async {
            #expect(fixtureNameIsVersioned("ps-macos26.3.txt", command: "ps"), "fixture name: ps-macos26.3.txt accepted")
            #expect(fixtureNameIsVersioned("tmutil-destinationinfo-macos27.0-not-configured.txt", command: "tmutil-destinationinfo"),
                  "fixture name: version + two-word variant accepted")
            #expect(!fixtureNameIsVersioned("ps.txt", command: "ps"), "fixture name: no version rejected")
            #expect(!fixtureNameIsVersioned("ps-laptop.txt", command: "ps"), "fixture name: variant without version rejected")
            #expect(!fixtureNameIsVersioned("ps-macos26.txt", command: "ps"), "fixture name: major only rejected")
            #expect(!fixtureNameIsVersioned("ps-macOS26.3.txt", command: "ps"), "fixture name: wrong case rejected")
            #expect(!fixtureNameIsVersioned("top-macos26.3.txt", command: "ps"), "fixture name: other command rejected")
            #expect(!fixtureNameIsVersioned("pmset-macos26.3-batt.txt", command: "pmset-batt"), "fixture name: partial command rejected")
            #expect(!fixtureNameIsVersioned("ps-macos26.3-.txt", command: "ps"), "fixture name: empty variant rejected")

            let root = fixturesRoot

            #expect(FileManager.default.fileExists(atPath: root.path), "fixtures: Tests/Fixtures exists")
            guard FileManager.default.fileExists(atPath: root.path) else { return }

            let garbage = "\u{FFFD}\u{FFFD} <<not command output>> }{ ;;; @@@\n\t~~~ ¿¿ ~~~\n"

            let entries = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

            for entry in entries {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                let name = entry.lastPathComponent
                guard let cmd = ParsedCommand(rawValue: name) else {
                    Issue.record( "fixtures: unknown directory \(name)")
                    continue
                }

                let files = ((try? FileManager.default.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }

                var positives: [URL] = []
                for file in files {
                    let fname = file.lastPathComponent
                    guard fname != "README.md" else { continue }
                    guard fname.hasSuffix(".txt") else {
                        Issue.record( "fixtures \(name)/\(fname): naming (must end in .txt)")
                        continue
                    }
                    if !fname.hasPrefix("neg-") {
                        positives.append(file)
                        if !fname.contains("synthetic") {
                            #expect(fixtureNameIsVersioned(fname, command: cmd.rawValue),
                                  "fixtures \(name)/\(fname): naming (real capture must be \(cmd.rawValue)-macos<major.minor>[-<variant>].txt)")
                        }
                    }
                }

                #expect(!positives.isEmpty, "fixtures \(cmd.rawValue): has a positive fixture")

                for file in files {
                    let fname = file.lastPathComponent
                    guard fname != "README.md", fname.hasSuffix(".txt") else { continue }
                    guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else {
                        Issue.record( "fixtures \(cmd.rawValue)/\(fname): readable as UTF-8")
                        continue
                    }
                    let label = "\(cmd.rawValue)/\(fname)"
                    if fname.hasPrefix("neg-") {
                        #expect(!cmd.parses(text), "fixtures \(label): rejected")
                    } else {
                        #expect(cmd.parses(text), "fixtures \(label): parses")
                        if cmd.isStructured {
                            let half = String(text.prefix(text.count / 2))
                            #expect(!cmd.parses(half), "fixtures \(label): truncated to half ⇒ rejected")
                        }
                    }
                }

                #expect(!cmd.parses(""), "fixtures \(cmd.rawValue): empty ⇒ rejected")
                #expect(!cmd.parses(garbage), "fixtures \(cmd.rawValue): garbage ⇒ rejected")
            }

            for cmd in ParsedCommand.allCases {
                #expect(entries.contains { $0.lastPathComponent == cmd.rawValue },
                      "fixtures \(cmd.rawValue): directory present")
            }
        }

        @Test func parseFailures() async {
            #expect(ParseFailure(.uptime, stdout: "  \n\t\n") == nil, "ParseFailure: blank stdout ⇒ nil")

            do {
                let lines = (1...10).map { "line \($0)" }
                let stdout = lines.joined(separator: "\n\n")  // blank lines between each
                let f = ParseFailure(.uptime, stdout: stdout)
                #expect(f?.excerpt.count == 8, "ParseFailure: excerpt capped at 8 lines")
                #expect(f?.omittedLineCount == 2, "ParseFailure: omittedLineCount == 2")
                #expect(f?.excerpt.first == "line 1", "ParseFailure: excerpt[0] is the first line")
            }

            do {
                let long = String(repeating: "x", count: 200)
                let f = ParseFailure(.uptime, stdout: long)
                #expect(f?.excerpt.first?.count == 160, "ParseFailure: clipped line count == 160")
                #expect(f?.excerpt.first?.hasSuffix("…") == true, "ParseFailure: clipped line ends with …")
            }

            #expect(ParsedCommand.spHardware.commandLine() == "system_profiler -json SPHardwareDataType",
                  "ParsedCommand.commandLine: sp-hardware")
            #expect(ParsedCommand.diskutilInfo.commandLine(device: "/dev/disk4") == "diskutil info -plist /dev/disk4",
                  "ParsedCommand.commandLine: diskutil-info with device")
            #expect(ParsedCommand.smartctl.commandLine(executable: "/opt/homebrew/sbin/smartctl") == "smartctl -A -j disk0",
                  "ParsedCommand.commandLine: smartctl with executable override")

            // masking
            #expect(ParseFailure.maskIdentifiers(["\"serial_number\" : \"C02XYZ\","]) ==
                  ["\"serial_number\" : <masked>"], "mask: serial_number JSON line")
            #expect(ParseFailure.maskIdentifiers(["          Serial Number: F8Y123"]) ==
                  ["          Serial Number: <masked>"], "mask: Serial Number prose line")
            #expect(ParseFailure.maskIdentifiers(["<key>IOPlatformUUID</key>", "<string>ABC</string>", "<key>Name</key>"]) ==
                  ["<key>IOPlatformUUID</key>", "<masked>", "<key>Name</key>"], "mask: plist key/value pair")
            #expect(ParseFailure.maskIdentifiers(["<key>SerialNumber</key><string>X</string>"]) ==
                  ["<masked>"], "mask: plist key+value on one line")
            #expect(ParseFailure.maskIdentifiers(["<string>0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0</string>"]) ==
                  ["<string><uuid></string>"], "mask: UUID-shaped token")
            #expect(ParseFailure.maskIdentifiers(["Firewall is enabled. (State = 1)"]) ==
                  ["Firewall is enabled. (State = 1)"], "mask: unrelated line unchanged")

            // registry
            #expect(ParsedCommand.allCases.filter { $0.path == nil } == [.smartctl],
                  "ParsedCommand: only smartctl has a nil path")
            #expect(ParsedCommand.allCases.allSatisfy { $0.path == nil || $0.path!.hasPrefix("/") },
                  "ParsedCommand: every non-nil path is absolute")
            #expect(Set(ParsedCommand.allCases.map(\.rawValue)).count == ParsedCommand.allCases.count,
                  "ParsedCommand: rawValues are unique")

            // writer
            do {
                let out = ReportWriter.render(summary([ParseFailure(.spHardware, stdout: "{\n\"SPHardwareDataType\" : 5\n}")!]))
                #expect(out.contains("===== \(L.reportSectionUnparsed) ====="), "writer: unparsed section header present")
                #expect(out.contains("$ system_profiler -json SPHardwareDataType"), "writer: command line present")
                #expect(out.contains("\n  \"SPHardwareDataType\" : 5\n"), "writer: excerpt line present")
            }
            do {
                let out = ReportWriter.render(summary([]))
                #expect(!out.contains(L.reportSectionUnparsed), "writer: no failures ⇒ no unparsed section")
            }
            do {
                let out = ReportWriter.render(summary([ParseFailure(.ps, stdout: "garbage")!]))
                #expect(out.contains("$ ps -axww -o pid=,rss=,time=,comm="), "writer: live-only parse failure rendered")
            }
        }
    }
}
