// Engine/SnapshotDeletion.swift
// STORAGE-ACTIONS-COPY Stage 2: the pure parts of deleting local Time Machine snapshots. The run itself is in
// `TimeMachineController`. Measured on this Mac 2026-11-04: one date form run takes
// about 2.1 s, prints "Deleted local snapshot '<date>'" and exits 0; a date with no snapshot exits 70.
// man tmutil: the date form deletes the local snapshots of that date on all mounted disks.
import Foundation

/// Why a snapshot stayed. `.tool` carries tmutil's first output line, nil when it printed none or never ran.
enum SnapshotDeleteFailure: Equatable, Sendable {
    case permission, backupRunning, timedOut
    case tool(String?)
}

/// `failed` includes the dates a stopped run never tried. deleted == 0 and failed == 0: macOS had already removed them all.
struct SnapshotDeleteResult: Equatable, Sendable {
    var deleted: Int
    var failed: Int
    var failure: SnapshotDeleteFailure?
    /// Of `failed`, the dates whose names could not be read: tmutil never ran for them.
    var unparsable = 0
}

enum SnapshotDeleteState: Equatable, Sendable {
    case idle, deleting
    case finished(SnapshotDeleteResult)
}

enum SnapshotDeletion {
    static let tmutilPath = "/usr/bin/tmutil"
    /// About 30 × the measured 2.1 s run.
    static let timeoutSeconds: TimeInterval = 60
    /// `build_app.sh`'s CFBundleIdentifier. Bench copies, `swift test` and `swift run` have another id or none.
    static let appBundleID = "com.rdskcm.mac-dashboard"

    /// The real command runs only in the app itself, never in a test process or a fixture run.
    static func mayRunRealDelete(bundleID: String?, visualFixture: Bool) -> Bool {
        bundleID == appBundleID && !visualFixture
    }

    /// "com.apple.TimeMachine.2026-11-03-043250.local" → "2026-11-03-043250". Any other shape: nil.
    static func date(fromName name: String) -> String? {
        let prefix = "com.apple.TimeMachine.", suffix = ".local"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.utf8.count == prefix.utf8.count + 17 + suffix.utf8.count else { return nil }
        let date = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        return isValidDate(date) ? date : nil
    }

    /// Exactly YYYY-MM-DD-HHMMSS in ASCII. The leading digit also means it can never read as a command-line option.
    static func isValidDate(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        guard bytes.count == 17 else { return false }
        for (i, b) in bytes.enumerated() {
            if i == 4 || i == 7 || i == 10 {
                if b != UInt8(ascii: "-") { return false }
            } else if b < UInt8(ascii: "0") || b > UInt8(ascii: "9") {
                return false
            }
        }
        return true
    }

    static func arguments(date: String) -> [String] { ["deletelocalsnapshots", date] }

    /// The local time zone, as in the tested run: the date argument names a local time. `CommandRunner.defaultEnvironment` pins TZ=UTC.
    static var environment: [String: String] {
        var env = CommandRunner.defaultEnvironment
        env["TZ"] = nil
        return env
    }

    struct Plan: Equatable {
        var dates: [String]
        var unparsable: Int
    }

    /// Only what the user confirmed and is still there. `current` nil (the read failed): the confirmed names stand.
    static func plan(confirmed: [String], current: [String]?) -> Plan {
        let stillThere = confirmed.filter { current?.contains($0) ?? true }
        let dates = stillThere.compactMap(date(fromName:))
        return Plan(dates: dates, unparsable: stillThere.count - dates.count)
    }

    enum RunVerdict: Equatable {
        case deleted
        case failed(SnapshotDeleteFailure, stopsTheRun: Bool)
    }

    static func verdict(_ outcome: CommandOutcome) -> RunVerdict {
        switch outcome.termination {
        case .exited(0): return .deleted
        case .timedOut: return .failed(.timedOut, stopsTheRun: true)
        case .launchFailed, .cancelled: return .failed(.tool(nil), stopsTheRun: true)
        case .exited, .signaled:
            let text = outcome.stderrHead + "\n" + outcome.stdout
            if isPermissionFailure(text) { return .failed(.permission, stopsTheRun: true) }
            return .failed(.tool(firstLine(text)), stopsTheRun: false)
        }
    }

    static func isPermissionFailure(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("full disk access") || t.contains("not permitted")
    }

    static func firstLine(_ text: String) -> String? {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}
