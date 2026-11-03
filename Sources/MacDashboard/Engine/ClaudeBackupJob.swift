// Engine/ClaudeBackupJob.swift
// BACKUP-CARD-FAILURE: the Claude backup LaunchAgent, read from its plist: which .app runs it and its calendar schedule.
import Foundation

struct ClaudeBackupJob: Equatable, Sendable {
    /// One `StartCalendarInterval` dictionary; nil = launchd's wildcard. Weekday here is launchd's (0 and 7 = Sunday).
    struct CalendarEntry: Equatable, Sendable {
        var minute: Int? = nil, hour: Int? = nil, day: Int? = nil, weekday: Int? = nil, month: Int? = nil
    }

    var label: String?
    var appPath: String?              // nil = the program is not an existing .app bundle: no button
    var schedule: [CalendarEntry]     // empty = no calendar, Disabled, or not loaded
    var startsOnMount: Bool

    /// The job's plist name without its reverse-DNS prefix; same name as the log. Carries no username (D3).
    static let plistSuffix = ".claude-backup.plist"
    /// Mirrors COOLDOWN_HOURS in backup_auto.sh (D6).
    static let cooldownHours = 6

    static var defaultAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    }

    /// ".../X.app/Contents/MacOS/X" → ".../X.app"; anything else → nil.
    static func appPath(fromExecutable path: String) -> String? {
        guard let r = path.range(of: ".app/Contents/MacOS/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    static func entry(from dict: [String: Any]) -> CalendarEntry? {
        let e = CalendarEntry(minute: dict["Minute"] as? Int, hour: dict["Hour"] as? Int, day: dict["Day"] as? Int,
                              weekday: dict["Weekday"] as? Int, month: dict["Month"] as? Int)
        return e == CalendarEntry() ? nil : e     // an empty dict means every minute; never a real backup schedule
    }

    static func parse(_ dict: [String: Any], fileExists: (String) -> Bool) -> ClaudeBackupJob {
        var entries: [CalendarEntry] = []
        if let one = dict["StartCalendarInterval"] as? [String: Any] { entries = entry(from: one).map { [$0] } ?? [] }
        else if let many = dict["StartCalendarInterval"] as? [[String: Any]] { entries = many.compactMap(entry(from:)) }
        if dict["Disabled"] as? Bool == true { entries = [] }
        let app = LaunchdPlistInspector.executablePath(from: dict).flatMap(appPath(fromExecutable:)).flatMap { fileExists($0) ? $0 : nil }
        return ClaudeBackupJob(label: LaunchdPlistInspector.label(from: dict), appPath: app, schedule: entries,
                               startsOnMount: dict["StartOnMount"] as? Bool == true)
    }

    /// First `*.claude-backup.plist` in name order; nil = no such job on this Mac.
    static func read(agentsDir: URL = defaultAgentsDir) -> ClaudeBackupJob? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: agentsDir.path)) ?? []
        guard let name = names.filter({ $0.hasSuffix(plistSuffix) }).sorted().first,
              let data = try? Data(contentsOf: agentsDir.appendingPathComponent(name)),
              let dict = LaunchdPlistInspector.decode(plistData: data) else { return nil }
        return parse(dict, fileExists: { FileManager.default.fileExists(atPath: $0) })
    }

    /// `read` plus launchd's own answer (D17). Off the main actor. A timeout or failed spawn keeps the schedule.
    static func load(agentsDir: URL = defaultAgentsDir) async -> ClaudeBackupJob? {
        guard var job = read(agentsDir: agentsDir) else { return nil }
        if let label = job.label {
            let o = await CommandRunner.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"], timeout: 5)
            if case .exited(let code) = o.termination, code != 0 { job.schedule = [] }
        }
        return job
    }

    /// Arguments for /usr/bin/open (D2).
    static func launchArguments(appPath: String) -> [String] { ["-n", "-g", appPath, "--args", "--force"] }

    /// Next fire strictly after `date`.
    static func nextRun(_ entries: [CalendarEntry], after date: Date, calendar: Calendar = .current) -> Date? {
        entries.compactMap { e -> Date? in
            var c = DateComponents()
            c.second = 0; c.minute = e.minute; c.hour = e.hour; c.day = e.day; c.month = e.month
            c.weekday = e.weekday.map { ($0 % 7) + 1 }      // launchd 0/7 = Sunday → Calendar 1
            return calendar.nextDate(after: date, matching: c, matchingPolicy: .nextTime)
        }.min()
    }

    /// The next fire the cooldown will not skip.
    static func nextCopyingRun(_ entries: [CalendarEntry], now: Date, newestSuccess: Date?, calendar: Calendar = .current) -> Date? {
        let free = newestSuccess?.addingTimeInterval(TimeInterval(cooldownHours * 3600)) ?? now
        return nextRun(entries, after: max(now, free), calendar: calendar)
    }
}
