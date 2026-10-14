// Tests/MacDashboardTests/LaunchdPlistInspectorTests.swift
// Port of Checks/LaunchdPlistInspectorChecks.swift (CHECKS-SWIFT-TESTING).
// Pure-logic coverage for LaunchdPlistInspector: Program/ProgramArguments parsing,
// orphan detection, curated description lookup and heuristic fallback. This file is
// real check code (NOT a symlink — see README.md), split out of main.swift because
// Swift executable targets only allow ONE file with top-level (script-mode)
// statements — main.swift already owns that slot — so this file instead defines a
// plain function that main.swift calls. `check()`/`total`/`failures` are the
// top-level helpers declared in main.swift; they're visible here because both files
// compile into the same MacDashboardChecks module.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct LaunchdPlistInspectorTests {
        @Test func launchdPlistInspector() async {
            // A: Program-based plist
            let programDict: [String: Any] = [
                "Label": "com.example.programstyle",
                "Program": "/usr/local/bin/example",
            ]
            #expect(LaunchdPlistInspector.label(from: programDict) == "com.example.programstyle",
                  "LaunchdPlistInspector.label: reads Label")
            #expect(LaunchdPlistInspector.executablePath(from: programDict) == "/usr/local/bin/example",
                  "LaunchdPlistInspector.executablePath: Program key wins")

            // A: ProgramArguments-based plist (Program absent)
            let argsDict: [String: Any] = [
                "Label": "com.example.argsstyle",
                "ProgramArguments": ["/usr/local/bin/args-exe", "--flag"],
            ]
            #expect(LaunchdPlistInspector.executablePath(from: argsDict) == "/usr/local/bin/args-exe",
                  "LaunchdPlistInspector.executablePath: falls back to ProgramArguments[0]")

            // A: BundleProgram-based plist (Program and ProgramArguments absent)
            let bundleDict: [String: Any] = [
                "Label": "com.example.bundlestyle",
                "BundleProgram": "Contents/MacOS/BundleExe",
            ]
            #expect(LaunchdPlistInspector.executablePath(from: bundleDict) == "Contents/MacOS/BundleExe",
                  "LaunchdPlistInspector.executablePath: falls back to BundleProgram")

            // A: priority order — Program beats ProgramArguments beats BundleProgram
            let priorityDict: [String: Any] = [
                "Program": "/usr/bin/winner",
                "ProgramArguments": ["/usr/bin/loser1"],
                "BundleProgram": "loser2",
            ]
            #expect(LaunchdPlistInspector.executablePath(from: priorityDict) == "/usr/bin/winner",
                  "LaunchdPlistInspector.executablePath: Program takes priority over the others")

            // B: orphan detection
            #expect(LaunchdPlistInspector.isOrphan(executablePath: "/path/does/not/exist-\(UUID().uuidString)"),
                  "isOrphan: nonexistent path -> true")
            #expect(!LaunchdPlistInspector.isOrphan(executablePath: "/bin/bash"),
                  "isOrphan: /bin/bash exists -> false")
            #expect(LaunchdPlistInspector.isOrphan(executablePath: nil),
                  "isOrphan: nil path -> true")

            // C: curated description lookup
            #expect(LaunchdPlistInspector.description(forLabel: "com.google.keystone.agent", language: .en)
                      == "Google Keystone — Google app auto-update",
                  "description: curated EN lookup hit")
            #expect(LaunchdPlistInspector.description(forLabel: "com.apple.cloudd", language: .ru)
                      == "iCloud — синхронизация данных",
                  "description: curated RU lookup hit")

            // D: heuristic fallback for an unknown label
            #expect(LaunchdPlistInspector.heuristicDescription(forLabel: "com.acmecorp.helper.v2", language: .en)
                      == "Acmecorp — background process",
                  "heuristicDescription: unknown com.* label -> vendor-derived EN string")
            #expect(LaunchdPlistInspector.heuristicDescription(forLabel: "org.mozilla.updater", language: .ru)
                      == "Mozilla — фоновый процесс",
                  "heuristicDescription: unknown org.* label -> vendor-derived RU string")
            #expect(LaunchdPlistInspector.description(forLabel: nil, language: .en) == nil,
                  "description: nil label -> nil")

            // E: end-to-end inspect()
            let plistData = try! PropertyListSerialization.data(
                fromPropertyList: [
                    "Label": "com.example.orphantest",
                    "Program": "/path/does/not/exist-\(UUID().uuidString)",
                ], format: .xml, options: 0)
            let info = LaunchdPlistInspector.inspect(plistPath: "/tmp/fake.plist", plistData: plistData, language: .en)
            #expect(info.label == "com.example.orphantest", "inspect: label parsed")
            #expect(info.isOrphan, "inspect: nonexistent executable -> isOrphan true")
            #expect(info.description == "Example — background process", "inspect: heuristic description attached")

            // F: deletion-target validation
            let userAgentsPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/x.plist")
            #expect(LaunchdPlistInspector.isValidDeletionTarget(path: userAgentsPath, isSystemLevel: false),
                  "isValidDeletionTarget: valid user-level path -> true")
            #expect(LaunchdPlistInspector.isValidDeletionTarget(path: "/Library/LaunchAgents/x.plist", isSystemLevel: true),
                  "isValidDeletionTarget: valid system-level LaunchAgents path -> true")
            #expect(LaunchdPlistInspector.isValidDeletionTarget(path: "/Library/LaunchDaemons/x.plist", isSystemLevel: true),
                  "isValidDeletionTarget: valid system-level LaunchDaemons path -> true")
            #expect(!LaunchdPlistInspector.isValidDeletionTarget(path: userAgentsPath.replacingOccurrences(of: ".plist", with: ".txt"), isSystemLevel: false),
                  "isValidDeletionTarget: non-.plist extension -> false")
            #expect(!LaunchdPlistInspector.isValidDeletionTarget(path: "/Library/LaunchAgents/x.plist", isSystemLevel: false),
                  "isValidDeletionTarget: system path passed with isSystemLevel: false -> false")
            #expect(!LaunchdPlistInspector.isValidDeletionTarget(path: userAgentsPath, isSystemLevel: true),
                  "isValidDeletionTarget: user path passed with isSystemLevel: true -> false")
            #expect(!LaunchdPlistInspector.isValidDeletionTarget(path: "/Library/LaunchAgents/../../etc/whatever.plist", isSystemLevel: true),
                  "isValidDeletionTarget: traversal escaping the allowed directory -> false")
        }
    }
}
