// Checks/WakeHoldersChecks.swift
// WAKE-HOLDERS: the `pmset -g assertions` parser (captured fixture + negatives), the
// classification rule (system vs ordinary, requester walk), the age threshold, merging,
// sort order, `ageText` formatting, and the `Assess.assess` branch in both languages.
import Foundation

func runWakeHoldersChecks() {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tests/Fixtures/pmset-assertions/pmset-assertions.txt")
    guard let captureText = try? String(contentsOf: fixtureURL, encoding: .utf8) else {
        check(false, "WakeHolders: could not read pmset-assertions.txt fixture")
        return
    }

    // --- R1: parser on the captured fixture ---
    guard let assertions = WakeHolders.parseAssertions(captureText) else {
        check(false, "WakeHolders: capture fixture parses")
        return
    }
    check(assertions.count == 5, "WakeHolders: capture fixture -> 5 assertions (got \(assertions.count))")
    if let powerd = assertions.first(where: { $0.pid == 349 }) {
        check(powerd.processName == "powerd" && powerd.type == "PreventUserIdleSystemSleep" && powerd.ageSeconds == 1783,
              "WakeHolders: pid 349 powerd PreventUserIdleSystemSleep 1783s")
    } else { check(false, "WakeHolders: pid 349 powerd present") }
    if let sharingd = assertions.first(where: { $0.pid == 685 }) {
        check(sharingd.processName == "sharingd" && sharingd.ageSeconds == 463, "WakeHolders: pid 685 sharingd 463s")
    } else { check(false, "WakeHolders: pid 685 sharingd present") }
    if let shortCaffeinate = assertions.first(where: { $0.pid == 94316 }) {
        check(shortCaffeinate.ageSeconds == 92 && shortCaffeinate.onBehalfOfPID == nil,
              "WakeHolders: pid 94316 caffeinate 92s, onBehalfOfPID nil")
    } else { check(false, "WakeHolders: pid 94316 caffeinate present") }
    if let longCaffeinate = assertions.first(where: { $0.pid == 67867 }) {
        check(longCaffeinate.ageSeconds == 4902 && longCaffeinate.onBehalfOfPID == 67807 &&
              longCaffeinate.name == "caffeinate command-line tool",
              "WakeHolders: pid 67867 caffeinate 4902s, onBehalfOfPID 67807, name matches")
    } else { check(false, "WakeHolders: pid 67867 caffeinate present") }
    if let windowServer = assertions.first(where: { $0.pid == 405 }) {
        check(windowServer.type == "UserIsActive" && windowServer.ageSeconds == 31,
              "WakeHolders: pid 405 WindowServer UserIsActive 31s")
    } else { check(false, "WakeHolders: pid 405 WindowServer present") }
    check(!assertions.contains { $0.processName.contains("IOSkywalkNetworkBSDClient") },
          "WakeHolders: kernel-assertion line not parsed")

    // --- R1: negatives ---
    check(WakeHolders.parseAssertions("") == nil, "WakeHolders: parseAssertions(\"\") -> nil")
    let garbage = "\u{FFFD}\u{FFFD} <<not command output>> }{ ;;; @@@\n\t~~~ ¿¿ ~~~\n"
    check(WakeHolders.parseAssertions(garbage) == nil, "WakeHolders: parseAssertions(garbage) -> nil")
    let negURL = fixtureURL.deletingLastPathComponent().appendingPathComponent("neg-truncated.txt")
    if let negText = try? String(contentsOf: negURL, encoding: .utf8) {
        check(WakeHolders.parseAssertions(negText) == nil, "WakeHolders: neg-truncated.txt -> nil")
    } else {
        check(false, "WakeHolders: could not read neg-truncated.txt")
    }
    check(WakeHolders.parseAssertions("Listed by owning process:\n") != nil,
          "WakeHolders: header-only text -> [] (non-nil)")
    check(WakeHolders.parseAssertions("Listed by owning process:\n")?.isEmpty == true,
          "WakeHolders: header-only text -> empty array")

    // --- R4: fixture lookup table (pid -> ProcRecord), from the spec ---
    let baseTable: [Int32: ProcRecord] = [
        349: ProcRecord(path: "/System/Library/CoreServices/powerd.bundle/powerd", ppid: 1),
        685: ProcRecord(path: "/usr/libexec/sharingd", ppid: 1),
        405: ProcRecord(path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", ppid: 1),
        94316: ProcRecord(path: "/usr/bin/caffeinate", ppid: 94300),
        94300: ProcRecord(path: "/Users/test/.local/bin/claude", ppid: 5000),
        67867: ProcRecord(path: "/usr/bin/caffeinate", ppid: 67807),
        67807: ProcRecord(path: "/Users/test/.local/bin/claude", ppid: 5000),
        5000: ProcRecord(path: "/bin/zsh", ppid: 4999),
        4999: ProcRecord(path: "/usr/bin/login", ppid: 4998),
        4998: ProcRecord(path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", ppid: 1),
    ]
    func lookup(_ extra: [Int32: ProcRecord] = [:]) -> (Int32) -> ProcRecord? {
        let table = baseTable.merging(extra) { _, new in new }
        return { table[$0] }
    }

    // --- R3: default floor on the capture ---
    let defaultHolders = WakeHolders.holders(from: assertions, lookup: lookup())
    check(defaultHolders == [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)],
          "WakeHolders: default floor on capture -> exactly caffeinate(claude) 4902s (got \(defaultHolders))")

    // --- R3/R5: minimumAge 0 merges the two caffeinate/claude entries ---
    let allHolders = WakeHolders.holders(from: assertions, lookup: lookup(), minimumAge: 0)
    check(allHolders.count == 1 && allHolders.first == WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902),
          "WakeHolders: minimumAge 0 -> merged caffeinate(claude) 4902s only (got \(allHolders))")

    // --- R4: parent walk without on-behalf ---
    let synthNoBehalf = PowerAssertion(pid: 94316, processName: "caffeinate", ageSeconds: 600,
                                        type: "PreventUserIdleSystemSleep", name: "x")
    let noBehalfHolders = WakeHolders.holders(from: [synthNoBehalf], lookup: lookup(), minimumAge: 0)
    check(noBehalfHolders.first?.requester == "claude",
          "WakeHolders: parent walk without on-behalf -> requester claude (got \(String(describing: noBehalfHolders.first)))")

    // --- R4: Terminal walk (caffeinate -> zsh -> login -> Terminal) ---
    let terminalExtra: [Int32: ProcRecord] = [7000: ProcRecord(path: "/usr/bin/caffeinate", ppid: 5000)]
    let synthTerminal = PowerAssertion(pid: 7000, processName: "caffeinate", ageSeconds: 600,
                                        type: "PreventUserIdleSystemSleep", name: "x")
    let terminalHolders = WakeHolders.holders(from: [synthTerminal], lookup: lookup(terminalExtra), minimumAge: 0)
    check(terminalHolders.first?.requester == "Terminal",
          "WakeHolders: Terminal walk -> requester Terminal (got \(String(describing: terminalHolders.first)))")

    // --- A1: requester name from p_comm, not the versioned file name ---
    let claudeVersionExtra: [Int32: ProcRecord] = [
        9400: ProcRecord(path: "/usr/bin/caffeinate", ppid: 9401),
        9401: ProcRecord(path: "/Users/u/.local/share/claude/versions/2.1.283", ppid: 1, name: "claude"),
    ]
    let synthClaudeVersion = PowerAssertion(pid: 9400, processName: "caffeinate", ageSeconds: 900,
                                             type: "PreventUserIdleSystemSleep", name: "x")
    let claudeVersionHolders = WakeHolders.holders(from: [synthClaudeVersion], lookup: lookup(claudeVersionExtra), minimumAge: 0)
    check(claudeVersionHolders == [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 900)],
          "WakeHolders: A1 versioned path -> requester claude, not 2.1.283 (got \(claudeVersionHolders))")

    // --- A1: name nil -> falls back to the path's last component ---
    let nilNameExtra: [Int32: ProcRecord] = [
        9500: ProcRecord(path: "/usr/bin/caffeinate", ppid: 9501),
        9501: ProcRecord(path: "/Users/u/.local/share/claude/versions/2.1.283", ppid: 1, name: nil),
    ]
    let synthNilName = PowerAssertion(pid: 9500, processName: "caffeinate", ageSeconds: 900,
                                       type: "PreventUserIdleSystemSleep", name: "x")
    let nilNameHolders = WakeHolders.holders(from: [synthNilName], lookup: lookup(nilNameExtra), minimumAge: 0)
    check(nilNameHolders == [WakeHolder(owner: "caffeinate", requester: "2.1.283", ageSeconds: 900)],
          "WakeHolders: A1 nil name -> requester falls back to path's last component (got \(nilNameHolders))")

    // --- A2: argv0Name, pure parse of a raw KERN_PROCARGS2 buffer ---
    func procargsBuffer(argc: Int32, execPath: String, padding: Int, argv: [String]) -> [UInt8] {
        var bytes: [UInt8] = withUnsafeBytes(of: argc) { Array($0) }
        bytes.append(contentsOf: Array(execPath.utf8))
        bytes.append(0)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: padding))
        for (i, a) in argv.enumerated() {
            bytes.append(contentsOf: Array(a.utf8))
            if i < argv.count - 1 { bytes.append(0) }
        }
        bytes.append(0)
        return bytes
    }
    let claudeArgs = procargsBuffer(argc: 2, execPath: "/Users/u/.local/share/claude/versions/2.1.283",
                                     padding: 3, argv: ["claude", "-r"])
    check(WakeHolders.argv0Name(procargs: claudeArgs) == "claude",
          "WakeHolders: A2 argv0Name claude+versions path -> claude (got \(String(describing: WakeHolders.argv0Name(procargs: claudeArgs))))")

    let brewArgs = procargsBuffer(argc: 1, execPath: "/opt/homebrew/bin/tool", padding: 2, argv: ["/opt/homebrew/bin/foo"])
    check(WakeHolders.argv0Name(procargs: brewArgs) == "foo",
          "WakeHolders: A2 argv0Name absolute argv[0] -> last component foo (got \(String(describing: WakeHolders.argv0Name(procargs: brewArgs))))")

    let loginShellArgs = procargsBuffer(argc: 1, execPath: "/bin/zsh", padding: 1, argv: ["-zsh"])
    check(WakeHolders.argv0Name(procargs: loginShellArgs) == "zsh",
          "WakeHolders: A2 argv0Name login-shell '-zsh' -> zsh (got \(String(describing: WakeHolders.argv0Name(procargs: loginShellArgs))))")

    var truncatedNoNUL: [UInt8] = withUnsafeBytes(of: Int32(1)) { Array($0) }
    truncatedNoNUL.append(contentsOf: Array("/bin/zsh".utf8))   // no terminating NUL at all
    check(WakeHolders.argv0Name(procargs: truncatedNoNUL) == nil,
          "WakeHolders: A2 argv0Name no NUL after exec path -> nil")

    let argcZero = procargsBuffer(argc: 0, execPath: "/bin/zsh", padding: 1, argv: ["zsh"])
    check(WakeHolders.argv0Name(procargs: argcZero) == nil, "WakeHolders: A2 argv0Name argc 0 -> nil")

    check(WakeHolders.argv0Name(procargs: [1, 0, 0]) == nil, "WakeHolders: A2 argv0Name too-short buffer (<4 bytes) -> nil")

    // --- R4/R5: ordinary owner, no delegation ---
    let zoomExtra: [Int32: ProcRecord] = [8000: ProcRecord(path: "/Applications/zoom.us.app/Contents/MacOS/zoom.us", ppid: 1)]
    let synthZoom = PowerAssertion(pid: 8000, processName: "zoom.us", ageSeconds: 900,
                                    type: "PreventUserIdleDisplaySleep", name: "x")
    let zoomHolders = WakeHolders.holders(from: [synthZoom], lookup: lookup(zoomExtra), minimumAge: 0)
    check(zoomHolders == [WakeHolder(owner: "zoom.us", requester: nil, ageSeconds: 900)],
          "WakeHolders: ordinary owner, no delegation -> zoom.us, nil requester (got \(zoomHolders))")

    // --- R5: on-behalf pointing into the owner's own app collapses requester ---
    let fooExtra: [Int32: ProcRecord] = [
        8100: ProcRecord(path: "/Applications/Foo.app/Contents/MacOS/Foo Helper", ppid: 1),
        8101: ProcRecord(path: "/Applications/Foo.app/Contents/MacOS/Foo", ppid: 1),
    ]
    let synthFoo = PowerAssertion(pid: 8100, processName: "Foo Helper", ageSeconds: 900,
                                   type: "PreventUserIdleSystemSleep", name: "x", onBehalfOfPID: 8101)
    let fooHolders = WakeHolders.holders(from: [synthFoo], lookup: lookup(fooExtra), minimumAge: 0)
    check(fooHolders == [WakeHolder(owner: "Foo", requester: nil, ageSeconds: 900)],
          "WakeHolders: on-behalf into owner's own app -> Foo, nil requester (got \(fooHolders))")

    // --- R4: Homebrew under /usr/local and /opt/homebrew are ordinary ---
    let brewExtra: [Int32: ProcRecord] = [
        8200: ProcRecord(path: "/usr/local/bin/mytool", ppid: 1),
        8300: ProcRecord(path: "/opt/homebrew/bin/x", ppid: 1),
    ]
    let synthUsrLocal = PowerAssertion(pid: 8200, processName: "mytool", ageSeconds: 900, type: "PreventUserIdleSystemSleep", name: "x")
    let synthHomebrew = PowerAssertion(pid: 8300, processName: "x", ageSeconds: 900, type: "PreventUserIdleSystemSleep", name: "x")
    check(!WakeHolders.holders(from: [synthUsrLocal], lookup: lookup(brewExtra), minimumAge: 0).isEmpty,
          "WakeHolders: /usr/local holder shown")
    check(!WakeHolders.holders(from: [synthHomebrew], lookup: lookup(brewExtra), minimumAge: 0).isEmpty,
          "WakeHolders: /opt/homebrew holder shown")

    // --- R4: orphan system tool (ppid 1, no on-behalf) not shown ---
    let orphanExtra: [Int32: ProcRecord] = [8400: ProcRecord(path: "/usr/bin/caffeinate", ppid: 1)]
    let synthOrphan = PowerAssertion(pid: 8400, processName: "caffeinate", ageSeconds: 900, type: "PreventUserIdleSystemSleep", name: "x")
    check(WakeHolders.holders(from: [synthOrphan], lookup: lookup(orphanExtra), minimumAge: 0).isEmpty,
          "WakeHolders: orphan system tool not shown")

    // --- R4: unknown pid (lookup nil) not shown ---
    let synthUnknown = PowerAssertion(pid: 9999, processName: "ghost", ageSeconds: 900, type: "PreventUserIdleSystemSleep", name: "x")
    check(WakeHolders.holders(from: [synthUnknown], lookup: lookup(), minimumAge: 0).isEmpty,
          "WakeHolders: unknown pid not shown")

    // --- R4: isOSExecutable table ---
    for p in ["/usr/bin/x", "/System/Library/x", "/bin/zsh", "/sbin/x", "/Library/Apple/x"] {
        check(WakeHolders.isOSExecutable(p), "WakeHolders: isOSExecutable(\(p)) true")
    }
    for p in ["/usr/local/bin/x", "/Applications/X.app/Contents/MacOS/X", "/Users/a/bin/x"] {
        check(!WakeHolders.isOSExecutable(p), "WakeHolders: isOSExecutable(\(p)) false")
    }

    // --- R5: sort order (age desc, then label asc) ---
    let sortExtra: [Int32: ProcRecord] = [
        9100: ProcRecord(path: "/Applications/a.app/Contents/MacOS/a", ppid: 1),
        9200: ProcRecord(path: "/Applications/b.app/Contents/MacOS/b", ppid: 1),
        9300: ProcRecord(path: "/Applications/c.app/Contents/MacOS/c", ppid: 1),
    ]
    let sortAssertions = [
        PowerAssertion(pid: 9200, processName: "b", ageSeconds: 900, type: "PreventUserIdleSystemSleep", name: "x"),
        PowerAssertion(pid: 9100, processName: "a", ageSeconds: 900, type: "PreventUserIdleSystemSleep", name: "x"),
        PowerAssertion(pid: 9300, processName: "c", ageSeconds: 1200, type: "PreventUserIdleSystemSleep", name: "x"),
    ]
    let sorted = WakeHolders.holders(from: sortAssertions, lookup: lookup(sortExtra), minimumAge: 0)
    check(sorted.map(\.owner) == ["c", "a", "b"], "WakeHolders: sort order c, a, b (got \(sorted.map(\.owner)))")

    // --- R7: ageText, RU/EN ---
    let originalLang = L10nStore.shared.language
    defer { L10nStore.shared.language = originalLang }

    L10nStore.shared.language = .ru
    check(WakeHolders.ageText(300) == "5 мин", "WakeHolders: ageText(300) RU -> 5 мин (got \(WakeHolders.ageText(300)))")
    check(WakeHolders.ageText(4902) == "1 ч 21 мин", "WakeHolders: ageText(4902) RU -> 1 ч 21 мин (got \(WakeHolders.ageText(4902)))")
    check(WakeHolders.ageText(3600) == "1 ч 0 мин", "WakeHolders: ageText(3600) RU -> 1 ч 0 мин (got \(WakeHolders.ageText(3600)))")

    L10nStore.shared.language = .en
    check(WakeHolders.ageText(4902) == "1 h 21 min", "WakeHolders: ageText(4902) EN -> 1 h 21 min (got \(WakeHolders.ageText(4902)))")

    // --- R6: Assess branch, RU ---
    L10nStore.shared.language = .ru
    let oneHolder = [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)]
    let assessOne = Assess.assess(report: FullReport(), live: LiveSnapshot(), wakeHolders: oneHolder)
    check(assessOne.items.count == 1 && assessOne.items.first?.kind == .wakeHolders,
          "WakeHolders: Assess RU, 1 holder -> exactly one .wakeHolders item")
    if let item = assessOne.items.first {
        check(item.sev == .warn, "WakeHolders: Assess RU, sev == .warn")
        check(item.label == "Сон", "WakeHolders: Assess RU, label == Сон (got \(item.label))")
        check(item.detail == "caffeinate (от claude) — 1 ч 21 мин",
              "WakeHolders: Assess RU, detail matches (got \(item.detail))")
        check(item.fullText == "1 программа не даёт Mac уснуть: caffeinate (от claude) — 1 ч 21 мин.",
              "WakeHolders: Assess RU, fullText matches (got \(item.fullText))")
        check(item.action == .openApp(AdviceApps.activityMonitor), "WakeHolders: Assess RU, action opens Activity Monitor")
        check(!item.verb.isEmpty, "WakeHolders: Assess RU, verb non-empty")
    }
    check(assessOne.problems.count == 1, "WakeHolders: Assess RU, 1 holder -> problems.count == 1")

    func holdersOfCount(_ n: Int) -> [WakeHolder] {
        (0..<n).map { WakeHolder(owner: "app\($0)", requester: nil, ageSeconds: 900 - $0) }
    }
    let assessThree = Assess.assess(report: FullReport(), live: LiveSnapshot(), wakeHolders: holdersOfCount(3))
    if let item = assessThree.items.first(where: { $0.kind == .wakeHolders }) {
        check(item.detail.hasSuffix(", ещё 2"), "WakeHolders: Assess RU, 3 holders -> detail ends with ', ещё 2' (got \(item.detail))")
        check(item.fullText.hasPrefix("3 программы не дают Mac уснуть: "),
              "WakeHolders: Assess RU, 3 holders -> fullText prefix (got \(item.fullText))")
        check(item.fullText.components(separatedBy: "; ").count - 1 == 2,
              "WakeHolders: Assess RU, 3 holders -> two '; ' separators")
    } else { check(false, "WakeHolders: Assess RU, 3 holders -> item present") }

    let assessFive = Assess.assess(report: FullReport(), live: LiveSnapshot(), wakeHolders: holdersOfCount(5))
    if let item = assessFive.items.first(where: { $0.kind == .wakeHolders }) {
        check(item.fullText.hasPrefix("5 программ не дают"), "WakeHolders: Assess RU, 5 holders -> '5 программ не дают' (got \(item.fullText))")
    } else { check(false, "WakeHolders: Assess RU, 5 holders -> item present") }

    // --- R6: Assess branch, EN ---
    L10nStore.shared.language = .en
    let assessOneEN = Assess.assess(report: FullReport(), live: LiveSnapshot(), wakeHolders: oneHolder)
    if let item = assessOneEN.items.first(where: { $0.kind == .wakeHolders }) {
        check(item.detail == "caffeinate (for claude) — 1 h 21 min", "WakeHolders: Assess EN, detail matches (got \(item.detail))")
        check(item.fullText == "1 program is keeping the Mac awake: caffeinate (for claude) — 1 h 21 min.",
              "WakeHolders: Assess EN, fullText matches (got \(item.fullText))")
    } else { check(false, "WakeHolders: Assess EN, 1 holder -> item present") }

    // --- R6: empty holders -> no item ---
    L10nStore.shared.language = .ru
    let assessNone = Assess.assess(report: FullReport(), live: LiveSnapshot(), wakeHolders: [])
    check(!assessNone.items.contains { $0.kind == .wakeHolders }, "WakeHolders: Assess with [] -> no .wakeHolders item")
}
