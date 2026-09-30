// Checks/BrewUpgraderChecks.swift
// COVERAGE-EXEC: behaviour checks for Engine/BrewUpgrader.swift — the brew invocation,
// the flow and result mapping, and progress forwarding, all through a fake runner. brew never runs here.

import Foundation

/// Scripted stand-in for CommandRunner.run: records the invocation, replays lines, returns the outcome.
private final class BUFakeRunner: @unchecked Sendable {
    let lines: [(String, Bool)]
    let outcome: CommandOutcome
    private(set) var calls: [BrewUpgrader.Invocation] = []
    init(lines: [(String, Bool)] = [], outcome: CommandOutcome) { self.lines = lines; self.outcome = outcome }
    func run(_ invocation: BrewUpgrader.Invocation, _ onLine: @escaping (String, Bool) -> Void) async -> CommandOutcome {
        calls.append(invocation)
        for (line, isStderr) in lines { onLine(line, isStderr) }
        return outcome
    }
}
private final class BUProgressLog: @unchecked Sendable { var items: [BrewProgress] = [] }
private func buOutcome(_ t: CommandOutcome.Termination, stdout: String = "") -> CommandOutcome {
    CommandOutcome(termination: t, stdout: stdout, stdoutTruncated: false, stderrHead: "")
}
/// Runs the injectable flow with a fake; never the 2-argument production overload.
private func buRun(total: Int, brewPath: String?, _ fake: BUFakeRunner, _ log: BUProgressLog) -> String? {
    runAsyncBlocking {
        await BrewUpgrader.upgradeAll(totalOutdated: total, brewPath: brewPath,
                                      onProgress: { log.items.append($0) }, run: fake.run)
    }
}

func runBrewUpgraderChecks() {
    let fail = L.maintenanceBrewUpgradeFailed
    let homebrew = "/opt/homebrew/bin/brew"
    let sysPATH = "/usr/bin:/bin:/usr/sbin:/sbin"
    func P(_ phase: BrewProgress.Phase, _ formula: String?, _ completed: Int, _ total: Int, _ downloads: Int) -> BrewProgress {
        BrewProgress(phase: phase, formula: formula, completed: completed, total: total, downloadsDone: downloads)
    }

    // --- Invocation ---
    let inv = BrewUpgrader.invocation(brewPath: homebrew)
    let expectedEnv = ["PATH": "/opt/homebrew/bin:" + sysPATH, "LC_ALL": "C", "LANG": "C", "TZ": "UTC",
                       "HOME": NSHomeDirectory()]
    check(inv == BrewUpgrader.Invocation(path: homebrew, args: ["upgrade"], timeout: 900, interruptGrace: 30,
                                            environment: expectedEnv),
          "BrewUpgrader: [invocation] BI1 full value")
    check(inv.interruptGrace == 30, "BrewUpgrader: [invocation] BI8 stop grace 30 s")
    check(inv.environment["PATH"] == "/opt/homebrew/bin:" + sysPATH, "BrewUpgrader: [invocation] BI2 PATH")
    check(inv.environment["HOMEBREW_NO_AUTO_UPDATE"] == nil, "BrewUpgrader: [invocation] BI3 auto-update not disabled")
    check(Set(inv.environment.keys) == ["PATH", "LC_ALL", "LANG", "TZ", "HOME"],
          "BrewUpgrader: [invocation] BI4 nothing inherited")
    let intel = BrewUpgrader.invocation(brewPath: "/usr/local/bin/brew")
    check(intel.path == "/usr/local/bin/brew", "BrewUpgrader: [invocation] BI5 path")
    check(intel.args == ["upgrade"], "BrewUpgrader: [invocation] BI5 args")
    check(intel.environment["PATH"] == "/usr/local/bin:" + sysPATH, "BrewUpgrader: [invocation] BI5 PATH")
    let spaced = BrewUpgrader.invocation(brewPath: "/Users/me/My Brew/bin/brew")
    check(spaced.path == "/Users/me/My Brew/bin/brew", "BrewUpgrader: [invocation] BI6 path")
    check(spaced.args == ["upgrade"], "BrewUpgrader: [invocation] BI6 args")
    check(spaced.environment["PATH"] == "/Users/me/My Brew/bin:" + sysPATH, "BrewUpgrader: [invocation] BI6 PATH")
    let uni = BrewUpgrader.invocation(brewPath: "/Users/тест/homebrew/bin/brew")
    check(uni.environment["PATH"] == "/Users/тест/homebrew/bin:" + sysPATH, "BrewUpgrader: [invocation] BI7 PATH")

    // --- Flow and result mapping ---
    func flow(_ name: String, _ t: CommandOutcome.Termination,
              stdout: String = "", expect: String?, extra: (BUFakeRunner, BUProgressLog) -> Void = { _, _ in }) {
        let fake = BUFakeRunner(outcome: buOutcome(t, stdout: stdout))
        let log = BUProgressLog()
        let got = buRun(total: 3, brewPath: homebrew, fake, log)
        check(got == expect, "BrewUpgrader: [flow] \(name)")
        extra(fake, log)
    }
    do {
        let fake = BUFakeRunner(outcome: buOutcome(.exited(0)))
        let log = BUProgressLog()
        check(buRun(total: 3, brewPath: nil, fake, log) == fail, "BrewUpgrader: [flow] BU1 no brew")
        check(fake.calls.isEmpty, "BrewUpgrader: [flow] BU1 no launch")
        check(log.items.isEmpty, "BrewUpgrader: [flow] BU1 no progress")
    }
    flow("BU2 clean", .exited(0), expect: nil) { fake, _ in
        check(fake.calls == [BrewUpgrader.invocation(brewPath: homebrew)], "BrewUpgrader: [flow] BU2 invocation passed")
    }
    flow("BU3 clean with output", .exited(0), stdout: "Already up-to-date.\n", expect: nil)
    flow("BU4 exit 1, no output", .exited(1), expect: fail)
    flow("BU5 exit 1 with output", .exited(1), stdout: "==> Upgrading foo\n", expect: fail)
    flow("BU6 timed out", .timedOut, expect: fail)
    flow("BU7 cancelled", .cancelled, expect: fail)
    flow("BU8 launch failed", .launchFailed(ENOENT), expect: fail)
    flow("BU9 signaled, no output", .signaled(9), expect: fail)
    flow("BU10 signaled with output", .signaled(9), stdout: "x", expect: fail)
    flow("BU15 signal status unknown with output", .signaled(0), stdout: "==> Upgrading foo\n", expect: fail)
    flow("BU16 timed out with output", .timedOut, stdout: "==> Upgrading foo\n", expect: fail)
    flow("BU17 cancelled with output", .cancelled, stdout: "==> Upgrading foo\n", expect: fail)

    // --- Progress forwarding ---
    let OK = "\u{2714}\u{FE0E} "
    let lines: [(String, Bool)] = [
        ("==> Fetching downloads for: python@3.12, openssl@3", false),
        (OK + "Bottle Manifest python@3.12 (3.12.7)", true),
        (OK + "Bottle homebrew/core/openssl@3 (3.4.0)", true),
        ("Pouring python@3.12--3.12.7.arm64_sequoia.bottle.tar.gz", false),
        ("==> Upgrading python@3.12", false),
        ("==> Upgrading 2 dependents of upgraded formulae:", false),
        ("==> Upgrading user/tap/odd-name_v2+x", false),
        ("==> Installing python@3.12 dependency: sqlite", false),
        ("==> Upgrading -dash", false),
        ("==> Upgrading it's\"q\"\\$`x`", false),
        ("==> Upgrading тест\u{2714}\u{FE0E}", false),
        (OK + "Bottle late (1.0)", true),
        ("", false),
        ("Warning: something", true),
        ("==> Upgrading two words", false),
    ]
    do {
        let fake = BUFakeRunner(lines: lines, outcome: buOutcome(.exited(0)))
        let log = BUProgressLog()
        check(buRun(total: 3, brewPath: homebrew, fake, log) == nil, "BrewUpgrader: [progress] BU11 returns nil")
        check(log.items == [
            P(.downloading, nil, 0, 3, 0),
            P(.downloading, "python@3.12", 0, 3, 1),
            P(.downloading, "homebrew/core/openssl@3", 0, 3, 2),
            P(.upgrading, "python@3.12", 1, 3, 2),
            P(.upgrading, "user/tap/odd-name_v2+x", 2, 3, 2),
            P(.upgrading, "sqlite", 2, 3, 2),
            P(.upgrading, "-dash", 3, 3, 2),
            P(.upgrading, "it's\"q\"\\$`x`", 4, 3, 2),
            P(.upgrading, "тест\u{2714}\u{FE0E}", 5, 3, 2),
            P(.upgrading, "тест\u{2714}\u{FE0E}", 5, 3, 3),
        ], "BrewUpgrader: [progress] BU12 exact sequence")
    }
    do {
        let fake = BUFakeRunner(lines: [("==> Upgrading foo", false)], outcome: buOutcome(.exited(0)))
        let log = BUProgressLog()
        _ = buRun(total: 0, brewPath: homebrew, fake, log)
        check(log.items == [P(.upgrading, "foo", 1, 0, 0)], "BrewUpgrader: [progress] BU13 unknown total")
    }
    do {
        let fake = BUFakeRunner(lines: [("==> Upgrading foo", false)], outcome: buOutcome(.exited(1)))
        let log = BUProgressLog()
        check(buRun(total: 3, brewPath: homebrew, fake, log) == fail, "BrewUpgrader: [progress] BU14 returns failure")
        check(log.items.count == 1, "BrewUpgrader: [progress] BU14 progress still forwarded")
    }

    // --- Stop notice (BREW-CANCEL) ---
    check(BrewUpgrader.upgradedCount(before: ["a", "b", "c"], after: ["c"]) == 2, "BrewUpgrader: [stop] BS1 count")
    check(BrewUpgrader.upgradedCount(before: ["a", "b"], after: ["a", "b", "z"]) == 0,
          "BrewUpgrader: [stop] BS2 newly outdated not counted")
    check(BrewUpgrader.upgradedCount(before: ["a"], after: []) == 1, "BrewUpgrader: [stop] BS3 all upgraded")
    check(BrewUpgrader.upgradedCount(before: ["a"], after: nil) == nil, "BrewUpgrader: [stop] BS4 re-check failed")
    check(BrewUpgrader.upgradedCount(before: [], after: []) == nil, "BrewUpgrader: [stop] BS5 empty before")
    check(BrewUpgrader.stoppedNotice(before: ["a", "b", "c"], after: ["c"]) == L.maintenanceBrewStopped(2, 3),
          "BrewUpgrader: [stop] BS6 notice")
    check(BrewUpgrader.stoppedNotice(before: ["a"], after: nil) == L.maintenanceBrewStoppedUnknown,
          "BrewUpgrader: [stop] BS7 notice unknown")
    check(StringsRU().maintenanceBrewStopped(1, 1) == "Обновление остановлено: обновлено 1 из 1 пакета"
          && StringsRU().maintenanceBrewStopped(2, 5) == "Обновление остановлено: обновлено 2 из 5 пакетов",
          "BrewUpgrader: [stop] BS8 RU plural")
    check(StringsEN().maintenanceBrewStopped(1, 1) == "Upgrade stopped: 1 of 1 package upgraded"
          && StringsEN().maintenanceBrewStopped(0, 3) == "Upgrade stopped: 0 of 3 packages upgraded",
          "BrewUpgrader: [stop] BS9 EN plural")
}
