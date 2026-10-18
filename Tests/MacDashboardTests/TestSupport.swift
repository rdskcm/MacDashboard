// Tests/MacDashboardTests/TestSupport.swift
// CHECKS-SWIFT-TESTING: the root suite every ported check lives in, its language pin,
// and the helpers the old Checks/main.swift exposed to every check file.
import Foundation
import Testing
@testable import MacDashboard

/// Root of every ported check. `.serialized` runs this whole subtree one test at a time:
/// the checks share process-wide state (L10nStore.shared.language, AppSettings.shared,
/// UserDefaults.standard, pid-named temp markers) and assert wall-clock bounds.
/// `.russianUI` starts every test in this subtree with the UI language set to Russian.
/// A new test that touches any process-wide state goes inside this suite.
@Suite(.serialized, .russianUI)
struct SerialTests {}

/// Sets `L10nStore.shared.language = .ru` before each test case in its scope and restores
/// the previous value afterwards, so a test that switches to `.en` cannot leak into the next.
struct RussianUITrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        let saved = L10nStore.shared.language
        L10nStore.shared.language = .ru
        defer { L10nStore.shared.language = saved }
        try await function()
    }
}

extension Trait where Self == RussianUITrait {
    static var russianUI: Self { RussianUITrait() }
}

/// <package>/Tests/Fixtures, found from this file's own location.
let fixturesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests/MacDashboardTests
    .deletingLastPathComponent()   // Tests
    .appendingPathComponent("Fixtures", isDirectory: true)

/// <package>/Tests/APIFixtures: recorded HTTP API answers (IPHONE-IPSW). A separate root because
/// Tests/Fixtures only admits `ParsedCommand` directories (see its README).
let apiFixturesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests/MacDashboardTests
    .deletingLastPathComponent()   // Tests
    .appendingPathComponent("APIFixtures", isDirectory: true)

let GIB: Int64 = 1 << 30
let MIB: Int64 = 1 << 20

/// Thread-safe collector for lines delivered by `run`'s `onLine` callback
/// (which fires on CommandRunner's own private serial queue, not the test's thread).
final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [(String, Bool)] = []
    func append(_ line: String, _ isStderr: Bool) {
        lock.lock(); defer { lock.unlock() }
        _lines.append((line, isStderr))
    }
    var lines: [(String, Bool)] {
        lock.lock(); defer { lock.unlock() }
        return _lines
    }
}

/// One CommandRunner.run for tests (was the runAsyncBlocking bridge in Checks).
func runCommand(_ path: String, _ args: [String], timeout: TimeInterval,
                environment: [String: String] = CommandRunner.defaultEnvironment,
                onLine: ((String, Bool) -> Void)? = nil) async -> CommandOutcome {
    await CommandRunner.run(path, args, timeout: timeout, environment: environment, onLine: onLine)
}

// V2-CRASH-REVEAL: the two real DiagnosticReports directories, by their production
// priority order (per-user first). Used by every crash fixture below.
let userCrashDir = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Logs/DiagnosticReports"
let systemCrashDir = "/Library/Logs/DiagnosticReports"

// Battery presence varies by machine (MacBook vs. Mac mini/Mac Studio/CI runner) —
// this mirrors how LiveCollector/ReportCollector already treat "no battery" as a
// normal, fully-supported state (see StringsEN.reportNoBattery), not an error. Smoke
// checks below use this to stay meaningful on battery-equipped machines while not
// spuriously failing on desktop Macs or CI runners.
// `collect(limit:)` takes the process-table length explicitly rather than reading
// AppSettings.shared — checks must not depend on the user's saved preferences.
// Battery comes from `collectFast()`, which avoids spawning processes.
let hasBattery = LiveCollector().collectFast().battery != nil

func memFixture(total: Int64, compressor: Int64 = 0) -> MemSnapshot {
    MemSnapshot(total: total, pageSize: 16384,
                free: total / 16, active: total / 4, inactive: total / 8,
                speculative: total / 32, wired: total / 4,
                compressor: compressor, purgeable: total / 64, fileBacked: total / 8)
}
