// Engine/SysdiagnoseRequest.swift
// DEVICE-ARCHIVE-CLEANUP: which sysdiagnose archive on the phone the app itself asked for. No API starts a
// sysdiagnose (IPHONE-SPIKE; pymobiledevice3 `crash sysdiagnose` also asks for the button press), so the user
// presses the buttons after the app's request. An archive is the app's own only when it is new against the listing
// taken at the request, its name's start time is inside the request window and it is the only new archive.
// In-progress names follow pymobiledevice3 `services/crash_reports.py` (`IN_PROGRESS_` + `.tmp` / `.tar.gz`).
// Pure; covered by Tests/MoonportTests/SysdiagnoseRequestTests.swift (nothing here is private).

import Foundation

/// An archive the app requested and saw finished on the phone. Persisted in `IPhoneDeviceRecord.ownArchives`.
struct OwnSysdiagnose: Codable, Equatable {
    var name: String          // basename in `SysdiagnoseDir.path`
    var size: Int64           // bytes when claimed
    var requestID: UUID
    var requestedAt: Date
}

/// One open «Create new sysdiagnose» request. Memory only: an app quit drops it and nothing is claimed.
struct SysdiagnoseRequest: Equatable {
    var id: UUID
    var requestedAt: Date
    /// Basenames directly in `SysdiagnoseDir.path` when the request was made.
    var baseline: Set<String>
    /// The single final candidate's size at the previous poll (stability check).
    var lastSize: [String: Int64] = [:]
    /// First poll that saw a candidate (in progress or final).
    var creatingSince: Date?
}

enum SysdiagnoseRequestPhase: Equatable {
    case preparing                 // baseline listing running
    case waiting                   // instruction shown, nothing new yet
    case creating                  // a candidate exists, not finished or not yet stable
    case ready(OwnSysdiagnose)     // claimed; polling stopped
    case ambiguous                 // more than one new archive: nothing claimed
    case expired                   // nothing started within `startWindow`
    case timedOut                  // started, not finished within `finishWindow`
    case failed                    // the baseline listing failed

    var isActive: Bool {
        switch self {
        case .preparing, .waiting, .creating: return true
        default: return false
        }
    }
}

/// What happened to the own archive on the phone after an import (shown after the import summary).
enum PhoneCleanup: Equatable {
    case deleting
    case deleted
    case keptBySetting
    case keptIncomplete       // the import did not meet `SysdiagnoseDir.importAllowsDelete`
    case notConnected         // the phone left before the delete could start
    case alreadyGone
    case changed              // the file on the phone is not the claimed size: not deleted
    case unavailable          // this macOS's MobileDevice has no AFCRemovePath
    case failed(Int32)
}

enum SysdiagnoseDir {
    static let path = "/DiagnosticLogs/sysdiagnose"
    static let inProgressPrefix = "IN_PROGRESS_"
    /// Assumptions with reasons: § Decisions of specs/DEVICE-ARCHIVE-CLEANUP.md.
    static let pollInterval: TimeInterval = 10
    static let clockSkew: TimeInterval = 60
    static let startWindow: TimeInterval = 15 * 60
    static let finishWindow: TimeInterval = 30 * 60
    /// Claims kept per device (oldest dropped).
    static let maxOwnRecords = 20

    static func remotePath(_ name: String) -> String { path + "/" + name }

    static func isInProgress(_ name: String) -> Bool { name.hasPrefix(inProgressPrefix) }

    /// The final name an in-progress file becomes: prefix dropped, a trailing `.tmp` or `.tar.gz` dropped, `.tar.gz`
    /// added. nil when `name` is not in progress or nothing is left.
    static func finalName(ofInProgress name: String) -> String? {
        guard isInProgress(name) else { return nil }
        var stem = String(name.dropFirst(inProgressPrefix.count))
        for ext in [".tar.gz", ".tmp"] where stem.hasSuffix(ext) {
            stem = String(stem.dropLast(ext.count))
            break
        }
        return stem.isEmpty ? nil : stem + ".tar.gz"
    }

    private static let nameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy.MM.dd_HH-mm-ssZ"
        return f
    }()

    /// Start time in a final archive name `sysdiagnose_2026.10.09_01-34-55+0300_<anything>.tar.gz`; nil for any
    /// other shape (in-progress names included).
    static func startDate(ofArchive name: String) -> Date? {
        let prefix = "sysdiagnose_"
        guard name.hasPrefix(prefix), name.hasSuffix(".tar.gz") else { return nil }
        let rest = name.dropFirst(prefix.count)
        guard rest.count > 25 else { return nil }
        let stamp = rest.prefix(24)                     // yyyy.MM.dd_HH-mm-ss±hhmm
        guard rest.dropFirst(24).first == "_" else { return nil }
        return nameDateFormatter.date(from: String(stamp))
    }

    /// The only phone path the transport may delete: a direct child of `path` with a final archive name.
    static func isOwnArchivePath(_ p: String) -> Bool {
        guard p.hasPrefix(path + "/") else { return false }
        let name = String(p.dropFirst(path.count + 1))
        guard !name.isEmpty, !name.contains("/"), name != ".", name != "..", !isInProgress(name) else { return false }
        return startDate(ofArchive: name) != nil
    }

    /// Full parse (Decision 3): a successful import with at least one battery point that did not stop on the
    /// «another phone» question.
    static func importAllowsDelete(_ summary: ImportSummary, identityAsked: Bool) -> Bool {
        summary.batteryPoints > 0 && !identityAsked
    }

    /// One poll over the files directly in `path`. Returns the updated request and its phase. The clock ends a
    /// request only while no finished candidate exists (§ Ownership, clock rules): a final candidate inside the
    /// start window is claimed whenever it is seen, so a poll paused while the panel was hidden loses nothing.
    static func step(_ r: SysdiagnoseRequest, listing: [IPhoneAFCEntry], now: Date) -> (SysdiagnoseRequest, SysdiagnoseRequestPhase) {
        var r = r
        let files = listing.filter { !$0.isDirectory }
        func base(_ e: IPhoneAFCEntry) -> String { (e.path as NSString).lastPathComponent }
        let fresh = files.filter { !r.baseline.contains(base($0)) }
        let inProgress = fresh.filter { isInProgress(base($0)) }
        let lo = r.requestedAt.addingTimeInterval(-clockSkew), hi = r.requestedAt.addingTimeInterval(startWindow)
        let finals = fresh.filter { e in
            guard !isInProgress(base(e)), let t = startDate(ofArchive: base(e)) else { return false }
            return t >= lo && t <= hi
        }
        let writing = Set(inProgress.compactMap { finalName(ofInProgress: base($0)) })
        let candidates = Set(finals.map(base)).union(writing)
        let elapsed = now.timeIntervalSince(r.requestedAt)
        if candidates.count > 1 { return (r, .ambiguous) }
        if candidates.isEmpty {
            if r.creatingSince != nil { return (r, elapsed > finishWindow ? .timedOut : .creating) }
            return (r, elapsed > startWindow ? .expired : .waiting)
        }
        if r.creatingSince == nil { r.creatingSince = now }
        guard let f = finals.first, !writing.contains(base(f)) else {
            // Only an in-progress file: the clock may end the wait.
            r.lastSize = [:]
            return (r, elapsed > finishWindow ? .timedOut : .creating)
        }
        if f.size > 0, r.lastSize[base(f)] == f.size {
            return (r, .ready(OwnSysdiagnose(name: base(f), size: f.size, requestID: r.id, requestedAt: r.requestedAt)))
        }
        r.lastSize = [base(f): f.size]
        return (r, .creating)   // a finished candidate is never timed out: the next poll confirms its size
    }

    /// Decision 7: the poll timer may run only while the request is active, its panel is mounted, the window is
    /// visible (AppActivityMonitor's verdict) and the phone is attached.
    static func shouldPoll(phase: SysdiagnoseRequestPhase?, panelShown: Bool, windowPaused: Bool, connected: Bool) -> Bool {
        (phase?.isActive ?? false) && phase != .preparing && panelShown && !windowPaused && connected
    }

    /// Decision 13: with no request open, the same loop may watch the phone's archive list only while the card is
    /// shown, the window is visible, the phone is attached and no import runs on that device.
    static func shouldWatchList(panelShown: Bool, windowPaused: Bool, connected: Bool, importing: Bool) -> Bool {
        panelShown && !windowPaused && connected && !importing
    }

    /// Finished archives of a folder listing as path -> size, by the filter «On the iPhone» uses
    /// (`IPhoneData.sysdiagnoseArchives`: no `IN_PROGRESS_`, only `.tar.gz` under the sysdiagnose folder).
    static func finishedArchives(_ entries: [IPhoneAFCEntry]) -> [String: Int64] {
        Dictionary(IPhoneData.sysdiagnoseArchives(in: entries)
            .filter { ($0.path as NSString).deletingLastPathComponent == path }  // direct children only, as `listSysdiagnoseDir`
            .map { ($0.path, $0.size) }, uniquingKeysWith: { a, _ in a })
    }
}
