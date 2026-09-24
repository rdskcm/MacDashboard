// Checks/LiveCanary.swift
// R3-FIXTURES part 4: `swift run MacDashboardChecks --live` runs every ParsedCommand for
// real, exactly as production does (same table), and prints which parsers rejected the
// output. Exit 1 iff a command produced output its parser rejected; a command with no
// output (absent tool, refused, empty) is environment, not parser fragility.
import Foundation

func runLiveCanary() -> Int32 {
    let hasBattery = LiveCollector().collectFast().battery != nil
    var ok = 0, rejected = 0, noOutput = 0, skipped = 0
    for cmd in ParsedCommand.allCases {
        let label = cmd.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0)
        if cmd.requiresBattery && !hasBattery {
            print("SKIP      \(label)no battery on this Mac"); skipped += 1; continue
        }
        let executable: String? = cmd == .smartctl ? ReportCollector.findSmartctl() : nil
        if cmd == .smartctl && executable == nil {
            print("NO-OUTPUT \(label)smartctl not installed"); noOutput += 1; continue
        }
        let outcome = runAsyncBlocking { await cmd.run(executable: executable) }
        let line = cmd.commandLine(executable: executable)
        guard let text = outcome.nonEmptyText else {
            print("NO-OUTPUT \(label)\(line) — \(outcome.termination)"); noOutput += 1; continue
        }
        if cmd.parses(text) { print("OK        \(label)\(line)"); ok += 1; continue }
        print("NIL       \(label)\(line)"); rejected += 1
        ParseFailure(cmd, executable: executable, stdout: text)?.excerpt.forEach { print("          | " + $0) }
    }
    print("")
    print("live canary: \(ok) ok, \(rejected) nil, \(noOutput) no output, \(skipped) skipped")
    return rejected == 0 ? 0 : 1
}
