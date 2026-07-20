// Engine/BrewUpgrader.swift
// Runs `brew upgrade` for the Maintenance card's in-app package update. Homebrew
// refreshes its own formula index during upgrade (auto-update), so a single
// command suffices. Unprivileged — brew runs as the user. Streams progress via
// BrewProgressParser so the caller can show a live current-formula/phase/k-of-N
// indicator instead of a blind spinner.
import Foundation

enum BrewUpgrader {
    /// Blocking; call off the main actor. Streams progress via `onProgress` (invoked
    /// on CommandRunner's private serial queue — caller hops to main). Returns nil on
    /// success, else a short localized failure string.
    static func upgradeAll(totalOutdated: Int, onProgress: @escaping (BrewProgress) -> Void) -> String? {
        guard let brew = ReportCollector.findBrew() else { return L.maintenanceBrewUpgradeFailed }
        var parser = BrewProgressParser(total: totalOutdated)
        // Generous timeout: downloads can take a while.
        guard CommandRunner.runStreaming(brew, ["upgrade"], timeout: 900, onLine: { line, isStderr in
            if parser.consume(line: line, isStderr: isStderr), let p = parser.progress {
                onProgress(p)
            }
        }) != nil else {
            return L.maintenanceBrewUpgradeFailed
        }
        return nil
    }
}
