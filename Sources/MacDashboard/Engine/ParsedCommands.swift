// Engine/ParsedCommands.swift
// R3-FIXTURES: the single definition of every command whose stdout goes through a
// `Parsers` function with an observable failure value — how production runs it and what
// "parsed" means. Production call sites, the fixture table (Checks/ParserFixtureChecks.swift)
// and the live canary (`MacDashboardChecks --live`) all read THIS table, so the canary can
// never test a different invocation than the app runs. Pure Foundation; symlinked into Checks.

import Foundation

enum ParsedCommand: String, CaseIterable {
    case ps
    case top
    case pmsetBatt = "pmset-batt"
    case pmsetCustom = "pmset-custom"
    case spPower = "sp-power"
    case spHardware = "sp-hardware"
    case uptime
    case tmutilDestinationInfo = "tmutil-destinationinfo"
    case diskutilInfo = "diskutil-info"
    case smartctl
    case fdesetup
    case spctl
    case csrutil
    case socketfilterfw

    /// Absolute executable. nil only for smartctl, resolved at run time
    /// (`ReportCollector.findSmartctl()`) and passed as `executable:`.
    var path: String? {
        switch self {
        case .ps: return "/bin/ps"
        case .top: return "/usr/bin/top"
        case .pmsetBatt, .pmsetCustom: return "/usr/bin/pmset"
        case .spPower, .spHardware: return "/usr/sbin/system_profiler"
        case .uptime: return "/usr/bin/uptime"
        case .tmutilDestinationInfo: return "/usr/bin/tmutil"
        case .diskutilInfo: return "/usr/sbin/diskutil"
        case .smartctl: return nil
        case .fdesetup: return "/usr/bin/fdesetup"
        case .spctl: return "/usr/sbin/spctl"
        case .csrutil: return "/usr/bin/csrutil"
        case .socketfilterfw: return "/usr/libexec/ApplicationFirewall/socketfilterfw"
        }
    }

    /// `device` is used by diskutil-info and smartctl only ("disk0", "/dev/disk4").
    func arguments(device: String = "disk0") -> [String] {
        switch self {
        case .ps: return ["-axww", "-o", "pid=,rss=,time=,comm="]
        case .top: return ["-l", "1", "-stats", "pid,command,mem"]
        case .pmsetBatt: return ["-g", "batt"]
        case .pmsetCustom: return ["-g", "custom"]
        case .spPower: return ["SPPowerDataType"]
        case .spHardware: return ["-json", "SPHardwareDataType"]
        case .uptime: return []
        case .tmutilDestinationInfo: return ["destinationinfo", "-X"]
        case .diskutilInfo: return ["info", "-plist", device]
        case .smartctl: return ["-A", "-j", device]
        case .fdesetup, .csrutil: return ["status"]
        case .spctl: return ["--status"]
        case .socketfilterfw: return ["--getglobalstate"]
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .ps: return 5
        case .spPower, .spHardware: return 25
        case .top, .tmutilDestinationInfo, .diskutilInfo, .smartctl: return 15
        case .pmsetBatt, .pmsetCustom, .uptime, .fdesetup, .spctl, .csrutil, .socketfilterfw: return 10
        }
    }

    /// Output is decoded as a whole (JSON/plist), not line by line.
    var isStructured: Bool {
        switch self {
        case .spHardware, .tmutilDestinationInfo, .diskutilInfo, .smartctl: return true
        default: return false
        }
    }

    /// Only meaningful on a Mac with a battery; the canary skips these elsewhere.
    var requiresBattery: Bool { self == .pmsetBatt || self == .spPower }

    /// THE success rule: did the production parser get a usable value out of `stdout`?
    func parses(_ stdout: String) -> Bool {
        switch self {
        case .ps: return !Parsers.psProcesses(stdout).isEmpty
        case .top: return !Parsers.topMemoryFootprints(stdout).isEmpty
        case .pmsetBatt: return Parsers.batteryPmset(stdout) != nil
        case .pmsetCustom:
            let e = Parsers.pmsetCustom(stdout)
            return !e.battery.isEmpty || !e.ac.isEmpty
        case .spPower:
            let p = Parsers.batteryPowerProfile(stdout)
            return p.cycles != nil || p.condition != nil || p.maxCapacity != nil
        case .spHardware: return Parsers.hardwareProfile(json: Data(stdout.utf8)) != nil
        case .uptime: return Parsers.uptimeHuman(stdout) != nil
        case .tmutilDestinationInfo: return Parsers.tmDestination(plist: Data(stdout.utf8)) != .undecodable
        case .diskutilInfo:
            let r = Parsers.diskutilSmart(plist: Data(stdout.utf8))
            return r.status != nil || r.mediaName != nil
        case .smartctl: return !Parsers.smartctlAttrs(json: Data(stdout.utf8)).isEmpty
        case .fdesetup: return Parsers.fileVaultStatus(stdout) != nil
        case .spctl: return Parsers.gatekeeperStatus(stdout) != nil
        case .csrutil: return Parsers.sipStatus(stdout) != nil
        case .socketfilterfw: return Parsers.firewallStatus(stdout) != nil
        }
    }

    /// Runs the command exactly as production does. `executable` overrides `path` (smartctl);
    /// no path and no override is a launch failure (ENOENT), never a crash.
    func run(device: String = "disk0", executable: String? = nil) async -> CommandOutcome {
        guard let exe = executable ?? path else { return .launchFailed(ENOENT) }
        return await CommandRunner.run(exe, arguments(device: device), timeout: timeout)
    }

    /// "system_profiler -json SPHardwareDataType" — for the report and the canary.
    func commandLine(device: String = "disk0", executable: String? = nil) -> String {
        let exe = executable ?? path ?? rawValue
        return ([(exe as NSString).lastPathComponent] + arguments(device: device)).joined(separator: " ")
    }
}

/// Non-blank stdout that its parser rejected, kept so the report carries the evidence
/// (R3 part 5). The excerpt is capped and identifier-masked; it is diagnostic, not a fixture.
struct ParseFailure: Equatable {
    static let excerptLineLimit = 8
    static let excerptLineLength = 160

    let command: ParsedCommand
    let commandLine: String       // as run, e.g. "diskutil info -plist disk0"
    let excerpt: [String]         // first non-blank lines, masked, clipped
    let omittedLineCount: Int     // non-blank lines after the excerpt

    /// nil for blank stdout: no output is a runner outcome, not a parse failure.
    init?(_ command: ParsedCommand, device: String = "disk0", executable: String? = nil, stdout: String) {
        let lines = stdout.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return nil }
        self.command = command
        self.commandLine = command.commandLine(device: device, executable: executable)
        self.excerpt = Self.maskIdentifiers(Array(lines.prefix(Self.excerptLineLimit))).map(Self.clip)
        self.omittedLineCount = lines.count - min(lines.count, Self.excerptLineLimit)
    }

    private static let identifierKey = try! NSRegularExpression(pattern: "serial|uuid|udid", options: [.caseInsensitive])
    private static let uuidToken = try! NSRegularExpression(
        pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /// Best-effort mask for known identifier shapes, not a guarantee: any UUID-shaped token
    /// becomes `<uuid>`; a line whose key mentions serial/uuid/udid keeps its key and loses
    /// its value (`"serial_number" : <masked>`, `Serial Number: <masked>`); for a plist
    /// `<key>…UUID</key>` line the following value line becomes `<masked>`.
    static func maskIdentifiers(_ lines: [String]) -> [String] {
        var out: [String] = []
        var maskNext = false
        for line in lines {
            if maskNext { out.append("<masked>"); maskNext = false; continue }
            let whole = NSRange(line.startIndex..., in: line)
            var masked = uuidToken.stringByReplacingMatches(in: line, range: whole, withTemplate: "<uuid>")
            if identifierKey.firstMatch(in: line, range: whole) != nil {
                if line.contains("</key>") {
                    if line.contains("<string>") || line.contains("<data>") { masked = "<masked>" } else { maskNext = true }
                } else if let colon = masked.firstIndex(of: ":") {
                    masked = String(masked[...colon]) + " <masked>"
                } else {
                    masked = "<masked>"
                }
            }
            out.append(masked)
        }
        return out
    }

    private static func clip(_ line: String) -> String {
        line.count <= excerptLineLength ? line : String(line.prefix(excerptLineLength - 1)) + "…"
    }
}
