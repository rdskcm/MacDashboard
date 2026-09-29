// Engine/BrewUpgrader.swift
// Runs `brew upgrade` for the Maintenance card's in-app package update. Homebrew
// refreshes its own formula index during upgrade (auto-update), so a single
// command suffices. Unprivileged — brew runs as the user. Streams progress via
// BrewProgressParser so the caller can show a live current-formula/phase/k-of-N
// indicator instead of a blind spinner.
import Foundation

enum BrewUpgrader {
    /// Everything `brew upgrade` is launched with — built purely so Checks can verify it.
    struct Invocation: Equatable {
        let path: String
        let args: [String]
        let timeout: TimeInterval
        let environment: [String: String]
    }

    /// Launches one `Invocation`, delivering every output line to the callback before it returns.
    typealias Runner = (Invocation, @escaping (_ line: String, _ isStderr: Bool) -> Void) async -> CommandOutcome

    /// Cancelling the awaiting Task kills brew's process group. Streams progress via
    /// `onProgress` (invoked on CommandRunner's private serial queue — caller hops to
    /// main). Returns nil on success, else a short localized failure string.
    static func upgradeAll(totalOutdated: Int, onProgress: @escaping (BrewProgress) -> Void) async -> String? {
        await upgradeAll(totalOutdated: totalOutdated, brewPath: ReportCollector.findBrew(),
                         onProgress: onProgress, run: { invocation, onLine in
            await CommandRunner.run(invocation.path, invocation.args, timeout: invocation.timeout,
                                    environment: invocation.environment, onLine: onLine)
        })
    }

    /// `upgradeAll(totalOutdated:onProgress:)` with brew's location and the launcher injected —
    /// Checks pass a fake so brew never runs. This is the whole flow.
    static func upgradeAll(totalOutdated: Int, brewPath: String?,
                           onProgress: @escaping (BrewProgress) -> Void, run: Runner) async -> String? {
        guard let brew = brewPath else { return L.maintenanceBrewUpgradeFailed }
        var parser = BrewProgressParser(total: totalOutdated)
        let outcome = await run(invocation(brewPath: brew), { line, isStderr in
            if parser.consume(line: line, isStderr: isStderr), let p = parser.progress {
                onProgress(p)
            }
        })
        return outcome.text == nil ? L.maintenanceBrewUpgradeFailed : nil
    }

    static func invocation(brewPath: String) -> Invocation {
        // brew is a Homebrew-prefix script that shells out to its own helper binaries
        // (ruby, git, curl, …) inside that prefix — same reason `collectBrewInfo()`
        // builds this environment for `--version`/`outdated`. It was missing here, on
        // the one call that actually matters, until V2-POLISH B1.
        // Generous timeout: downloads can take a while.
        Invocation(path: brewPath, args: ["upgrade"], timeout: 900,
                   environment: CommandRunner.environment(
                       prependingPATH: [(brewPath as NSString).deletingLastPathComponent]))
    }
}
