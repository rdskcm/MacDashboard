// Checks/ParserFixtureChecks.swift
// R3-FIXTURES parts 2-5: table-driven checks over Tests/Fixtures/ (every command's
// parser accepts its positives and rejects its negatives, empty input and garbage,
// and structured positives truncated to half), plus the ParseFailure/writer unit
// checks for the report-time recording of unparsed command output (part 5).
import Foundation

func runParserFixtureChecks() {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tests/Fixtures", isDirectory: true)

    check(FileManager.default.fileExists(atPath: root.path), "fixtures: Tests/Fixtures exists")
    guard FileManager.default.fileExists(atPath: root.path) else { return }

    let garbage = "\u{FFFD}\u{FFFD} <<not command output>> }{ ;;; @@@\n\t~~~ ¿¿ ~~~\n"

    let entries = (try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

    for entry in entries {
        let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard isDir else { continue }
        let name = entry.lastPathComponent
        guard let cmd = ParsedCommand(rawValue: name) else {
            check(false, "fixtures: unknown directory \(name)")
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
                check(false, "fixtures \(name)/\(fname): naming (must end in .txt)")
                continue
            }
            if !fname.hasPrefix("neg-") { positives.append(file) }
        }

        check(!positives.isEmpty, "fixtures \(cmd.rawValue): has a positive fixture")

        for file in files {
            let fname = file.lastPathComponent
            guard fname != "README.md", fname.hasSuffix(".txt") else { continue }
            guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else {
                check(false, "fixtures \(cmd.rawValue)/\(fname): readable as UTF-8")
                continue
            }
            let label = "\(cmd.rawValue)/\(fname)"
            if fname.hasPrefix("neg-") {
                check(!cmd.parses(text), "fixtures \(label): rejected")
            } else {
                check(cmd.parses(text), "fixtures \(label): parses")
                if cmd.isStructured {
                    let half = String(text.prefix(text.count / 2))
                    check(!cmd.parses(half), "fixtures \(label): truncated to half ⇒ rejected")
                }
            }
        }

        check(!cmd.parses(""), "fixtures \(cmd.rawValue): empty ⇒ rejected")
        check(!cmd.parses(garbage), "fixtures \(cmd.rawValue): garbage ⇒ rejected")
    }

    for cmd in ParsedCommand.allCases {
        check(entries.contains { $0.lastPathComponent == cmd.rawValue },
              "fixtures \(cmd.rawValue): directory present")
    }
}

func runParseFailureChecks() {
    check(ParseFailure(.uptime, stdout: "  \n\t\n") == nil, "ParseFailure: blank stdout ⇒ nil")

    do {
        let lines = (1...10).map { "line \($0)" }
        let stdout = lines.joined(separator: "\n\n")  // blank lines between each
        let f = ParseFailure(.uptime, stdout: stdout)
        check(f?.excerpt.count == 8, "ParseFailure: excerpt capped at 8 lines")
        check(f?.omittedLineCount == 2, "ParseFailure: omittedLineCount == 2")
        check(f?.excerpt.first == "line 1", "ParseFailure: excerpt[0] is the first line")
    }

    do {
        let long = String(repeating: "x", count: 200)
        let f = ParseFailure(.uptime, stdout: long)
        check(f?.excerpt.first?.count == 160, "ParseFailure: clipped line count == 160")
        check(f?.excerpt.first?.hasSuffix("…") == true, "ParseFailure: clipped line ends with …")
    }

    check(ParsedCommand.spHardware.commandLine() == "system_profiler -json SPHardwareDataType",
          "ParsedCommand.commandLine: sp-hardware")
    check(ParsedCommand.diskutilInfo.commandLine(device: "/dev/disk4") == "diskutil info -plist /dev/disk4",
          "ParsedCommand.commandLine: diskutil-info with device")
    check(ParsedCommand.smartctl.commandLine(executable: "/opt/homebrew/sbin/smartctl") == "smartctl -A -j disk0",
          "ParsedCommand.commandLine: smartctl with executable override")

    // masking
    check(ParseFailure.maskIdentifiers(["\"serial_number\" : \"C02XYZ\","]) ==
          ["\"serial_number\" : <masked>"], "mask: serial_number JSON line")
    check(ParseFailure.maskIdentifiers(["          Serial Number: F8Y123"]) ==
          ["          Serial Number: <masked>"], "mask: Serial Number prose line")
    check(ParseFailure.maskIdentifiers(["<key>IOPlatformUUID</key>", "<string>ABC</string>", "<key>Name</key>"]) ==
          ["<key>IOPlatformUUID</key>", "<masked>", "<key>Name</key>"], "mask: plist key/value pair")
    check(ParseFailure.maskIdentifiers(["<key>SerialNumber</key><string>X</string>"]) ==
          ["<masked>"], "mask: plist key+value on one line")
    check(ParseFailure.maskIdentifiers(["<string>0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0</string>"]) ==
          ["<string><uuid></string>"], "mask: UUID-shaped token")
    check(ParseFailure.maskIdentifiers(["Firewall is enabled. (State = 1)"]) ==
          ["Firewall is enabled. (State = 1)"], "mask: unrelated line unchanged")

    // registry
    check(ParsedCommand.allCases.filter { $0.path == nil } == [.smartctl],
          "ParsedCommand: only smartctl has a nil path")
    check(ParsedCommand.allCases.allSatisfy { $0.path == nil || $0.path!.hasPrefix("/") },
          "ParsedCommand: every non-nil path is absolute")
    check(Set(ParsedCommand.allCases.map(\.rawValue)).count == ParsedCommand.allCases.count,
          "ParsedCommand: rawValues are unique")

    // writer
    do {
        var r = FullReport()
        r.parseFailures = [ParseFailure(.spHardware, stdout: "{\n\"SPHardwareDataType\" : 5\n}")!]
        let out = ReportWriter.render(report: r, live: LiveSnapshot(), history: HistoryState())
        check(out.contains("===== \(L.reportSectionUnparsed) ====="), "writer: unparsed section header present")
        check(out.contains("$ system_profiler -json SPHardwareDataType"), "writer: command line present")
        check(out.contains("\n  \"SPHardwareDataType\" : 5\n"), "writer: excerpt line present")
    }
    do {
        let out = ReportWriter.render(report: FullReport(), live: LiveSnapshot(), history: HistoryState())
        check(!out.contains(L.reportSectionUnparsed), "writer: no failures ⇒ no unparsed section")
    }
    do {
        var live = LiveSnapshot()
        live.parseFailures = [ParseFailure(.ps, stdout: "garbage")!]
        let out = ReportWriter.render(report: FullReport(), live: live, history: HistoryState())
        check(out.contains("$ ps -axww -o pid=,rss=,time=,comm="), "writer: live-only parse failure rendered")
    }
}
