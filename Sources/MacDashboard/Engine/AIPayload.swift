// Engine/AIPayload.swift
// Renders the exact text sent to the AI assistant (Block AI, Wave 1): assessment
// summary + current live metrics + the last collected text report, each as a
// clearly delimited section so the user can see precisely what will be sent
// before confirming. Pure Foundation only — symlinked into the Checks target.

import Foundation

// Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
#if AI_ENABLED
struct AIPayloadInput {
    var reportText: String?
    var assessment: Assessment
    var live: LiveSnapshot
}

enum AIPayloadBuilder {
    static func build(_ input: AIPayloadInput) -> String {
        var out = ""
        out += banner(L.aiPayloadSectionAssessment) + "\n"
        out += renderAssessment(input.assessment) + "\n\n"
        out += banner(L.aiPayloadSectionLive) + "\n"
        out += renderLive(input.live) + "\n\n"
        out += banner(L.aiPayloadSectionReport) + "\n"
        out += (input.reportText ?? L.aiNoReport)
        return out
    }

    private static func banner(_ name: String) -> String {
        "===== \(name) ====="
    }

    // MARK: - Assessment section

    private static func renderAssessment(_ a: Assessment) -> String {
        if a.problems.isEmpty && a.tips.isEmpty {
            return L.recommendationsAllGood
        }
        var lines: [String] = [a.summaryText]
        for p in a.problems { lines.append("- [\(p.sev.rawValue)] \(p.text)") }
        for t in a.tips { lines.append("\(L.aiPayloadTipPrefix)\(t.text)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Live section

    private static func renderLive(_ live: LiveSnapshot) -> String {
        var lines: [String] = []

        if let load = live.load, !load.isEmpty {
            let parts = load.map { String(format: "%.2f", $0) }.joined(separator: " ")
            lines.append("Load average: \(parts)")
        }
        if let mem = live.mem {
            lines.append("Memory: \(ReportWriter.fmtBytes(mem.usedBytes)) / \(ReportWriter.fmtBytes(mem.total))")
        }
        if let swap = live.swap {
            lines.append("Swap: \(ReportWriter.fmtBytes(swap.used)) / \(ReportWriter.fmtBytes(swap.total))")
        }
        if let disk = live.disk {
            let pct = Int((disk.pct * 100).rounded())
            lines.append("Disk: \(ReportWriter.fmtBytes(disk.usedTotal)) / \(ReportWriter.fmtBytes(disk.size)) (\(pct)%)")
        }
        if let batt = live.battery {
            if let charge = batt.charge { lines.append("Battery charge: \(charge)%") }
            if let state = batt.state { lines.append("Battery state: \(state)") }
            if let cycles = batt.cycles { lines.append("Battery cycles: \(cycles)") }
            if let condition = batt.condition { lines.append("Battery condition: \(condition)") }
        }

        return lines.joined(separator: "\n")
    }
}
#endif
