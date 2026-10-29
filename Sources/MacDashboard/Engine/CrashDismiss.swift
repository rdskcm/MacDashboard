// Engine/CrashDismiss.swift
// CRASH-REPORT-DISMISS: hide and delete the crash reports behind one row of the Security page's Crashes card.
// Pure rules (hidden list, path validation) plus the one impure delete, whose file-system and privilege calls are
// injected so tests run against temp folders and never touch real reports, the real Trash or sudo.
import Foundation

/// One report file the user hid. Keyed on the FILE NAME (unique: process + second-resolution timestamp), so a new
/// crash of the same process writes a new name and shows again. `hiddenAt` drives pruning.
struct HiddenCrashReport: Codable, Equatable, Sendable {
    var name: String
    var hiddenAt: Date
}

enum CrashActionKind: Equatable, Sendable { case hide, unhide, delete }

/// Why a delete did not remove everything. `refused` = validation stopped the whole batch before any file was
/// touched; it carries the offending file name.
enum CrashDeleteFailure: Equatable, Sendable {
    case cancelled, timedOut
    case error(String)
    case refused(String)
}

/// The one crash action in flight, or the last delete that did not fully succeed (cleared by the next action).
/// One state is also the re-entrancy guard: no second action starts while one is working.
enum CrashActionState: Equatable, Sendable {
    case idle
    case working(CrashActionKind, groupID: String)
    case failed(CrashDeleteFailure)
    var isWorking: Bool { if case .working = self { return true }; return false }
}

enum CrashFileKind: Equatable, Sendable { case regular, missing, other }

struct CrashDeleteResult: Equatable, Sendable {
    var removed: [String] = []
    var failure: CrashDeleteFailure? = nil
}

/// CRASH-REPORT-DISMISS fix wave 2: the ordering rule of every crash re-scan outside a pass (hide, unhide, delete,
/// Security Refresh, pass-end rerun). Pure; `CrashReportsController` owns one and asks it before each scan and each write.
/// Rule: a request is made AFTER its input changed (hidden list written, files deleted), so its scan is fresh; only
/// the scan of the newest request may write, so the last write is always the freshest. A request or a landing while
/// a pass collects is parked and requested again when the pass ends (D10).
struct CrashScanSequencer: Equatable, Sendable {
    /// What one finished scan may do: write the crash section, and set the controller's `action` to `outcome` when non-nil.
    struct Landing: Equatable, Sendable {
        var write: Bool
        var outcome: CrashActionState?
    }

    private(set) var latestTicket = 0
    /// The newest action's result, waiting for the scan that writes. nil = nothing to deliver.
    private(set) var pendingOutcome: CrashActionState? = nil
    /// A request was parked by a pass; the pass's end must request a scan again.
    private(set) var rerunDue = false

    /// Registers a request. Returns the ticket the caller's scan carries, or nil when a pass is collecting (parked:
    /// no scan now). A nil `outcome` (Refresh, rerun) keeps an outcome already waiting.
    mutating func request(completing outcome: CrashActionState?, collecting: Bool) -> Int? {
        if let outcome { pendingOutcome = outcome }
        latestTicket += 1
        guard !collecting else { rerunDue = true; return nil }
        return latestTicket
    }

    /// The scan for `ticket` returned. A newer request owns the write and the outcome; a pass collecting now parks it.
    mutating func landed(ticket: Int, collecting: Bool) -> Landing {
        guard ticket == latestTicket else { return Landing(write: false, outcome: nil) }
        guard !collecting else { rerunDue = true; return Landing(write: false, outcome: nil) }
        defer { pendingOutcome = nil }
        return Landing(write: true, outcome: pendingOutcome)
    }

    /// A pass ended, completed or cancelled. True when a parked request must be requested again now; resets the flag.
    mutating func passEnded() -> Bool {
        defer { rerunDue = false }
        return rerunDue
    }
}

enum CrashDismiss {
    static var userDirectory: String { ReportCollector.crashReportDirectories[0].path }
    static var systemDirectory: String { ReportCollector.crashReportDirectories[1].path }
    /// Same extensions `ReportCollector.crashFiles(in:)` lists (exact, lowercase).
    static let reportExtensions: Set<String> = ["ips", "crash", "panic"]

    // MARK: hidden list

    /// The group's distinct report file names, in `reportPaths` order.
    static func names(of group: CrashGroup) -> [String] {
        var seen = Set<String>()
        return group.reportPaths.map { ($0 as NSString).lastPathComponent }.filter { seen.insert($0).inserted }
    }

    /// A report hidden at T has mtime <= T and leaves the scan at mtime + 7 d, so its entry is useless after
    /// T + 7 d. A future `hiddenAt` (clock rolled back) is dropped too, as `isCrashRecent` does; the report then
    /// simply shows again.
    static func pruned(_ entries: [HiddenCrashReport], now: Date) -> [HiddenCrashReport] {
        entries.filter { ReportCollector.isCrashRecent(mtime: $0.hiddenAt, now: now) }
    }

    static func hiding(_ group: CrashGroup, in entries: [HiddenCrashReport], now: Date) -> [HiddenCrashReport] {
        var out = pruned(entries, now: now)
        let present = Set(out.map(\.name))
        out += names(of: group).filter { !present.contains($0) }.map { HiddenCrashReport(name: $0, hiddenAt: now) }
        return out
    }

    static func unhiding(_ group: CrashGroup, in entries: [HiddenCrashReport], now: Date) -> [HiddenCrashReport] {
        let drop = Set(names(of: group))
        return pruned(entries, now: now).filter { !drop.contains($0.name) }
    }

    /// AppSettings codec. Missing or unreadable data is an empty list (failing toward "show" is the safe
    /// direction); duplicate names are dropped, first kept.
    static func decode(_ data: Data?) -> [HiddenCrashReport] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = data.flatMap { try? decoder.decode([HiddenCrashReport].self, from: $0) } ?? []
        var seen = Set<String>()
        return stored.filter { seen.insert($0.name).inserted }
    }

    static func encode(_ entries: [HiddenCrashReport]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(entries)
    }

    // MARK: delete

    /// Pure: `path` is exactly `<dir>/<name>` with `<dir>` one of `directories` (string-equal, no `..`, `.`, `//`,
    /// trailing slash or subfolder), `<name>` not hidden, extension one of `reportExtensions`.
    static func isReportPath(_ path: String, directories: [String]) -> Bool {
        let name = (path as NSString).lastPathComponent
        let dir = (path as NSString).deletingLastPathComponent
        guard directories.contains(dir), path == dir + "/" + name else { return false }
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return false }
        return reportExtensions.contains((name as NSString).pathExtension)
    }

    /// `lstat`, so a symlink is `.other`, never followed.
    static func fileKind(atPath path: String) -> CrashFileKind {
        var st = stat()
        guard lstat(path, &st) == 0 else { return errno == ENOENT ? .missing : .other }
        return (st.st_mode & S_IFMT) == S_IFREG ? .regular : .other
    }

    static func resolvedDirectory(_ dir: String) -> String {
        URL(fileURLWithPath: dir, isDirectory: true).resolvingSymlinksInPath().path
    }

    /// Deletes one group's report files. Synchronous (the privileged step waits for Touch ID) — call off the
    /// main actor. Validates every path before touching any (one bad path refuses the batch), then removes the
    /// system-folder files with ONE privileged `rm` (first, so a cancel leaves everything in place), then moves
    /// the per-user files to the Trash one by one (the first error is reported, the rest still run).
    static func delete(paths: [String],
                       userDirectory: String = CrashDismiss.userDirectory,
                       systemDirectory: String = CrashDismiss.systemDirectory,
                       fileKind: (String) -> CrashFileKind = CrashDismiss.fileKind(atPath:),
                       resolve: (String) -> String = CrashDismiss.resolvedDirectory,
                       trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                       privileged: (String) -> PrivilegedRunner.Outcome = { PrivilegedRunner.run($0) }) -> CrashDeleteResult {
        let directories = [userDirectory, systemDirectory]
        var kinds: [String: CrashFileKind] = [:]
        for path in paths {
            let dir = (path as NSString).deletingLastPathComponent
            let kind = fileKind(path)
            guard isReportPath(path, directories: directories), resolve(dir) == dir, kind != .other else {
                return CrashDeleteResult(failure: .refused((path as NSString).lastPathComponent))
            }
            kinds[path] = kind
        }
        var result = CrashDeleteResult()
        result.removed = paths.filter { kinds[$0] == .missing }          // already gone counts as removed
        let present = paths.filter { kinds[$0] == .regular }
        let system = present.filter { ($0 as NSString).deletingLastPathComponent == systemDirectory }
        let user = present.filter { ($0 as NSString).deletingLastPathComponent == userDirectory }
        if !system.isEmpty {
            switch privileged(PrivilegedRunner.removeCommand(paths: system)) {
            case .success: result.removed += system
            case .cancelled: result.failure = .cancelled; return result
            case .timedOut: result.failure = .timedOut; return result
            case .failed(let msg): result.failure = .error(msg); return result
            }
        }
        for path in user {
            do {
                try trash(URL(fileURLWithPath: path))
                result.removed.append(path)
            } catch {
                if result.failure == nil { result.failure = .error(error.localizedDescription) }
            }
        }
        return result
    }
}
