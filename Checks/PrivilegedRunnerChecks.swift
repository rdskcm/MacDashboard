// Checks/PrivilegedRunnerChecks.swift
// COVERAGE-EXEC: behaviour checks for Engine/PrivilegedRunner.swift — the pure command
// builders, escaping and quoting, the sudo -> osascript decision flow (fake executor) and
// the real executor against harmless binaries. No sudo, no privileged osascript and no `rm` ever runs here.

import Foundation

private let prCorpus: [(label: String, value: String)] = [
    ("plain", "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"),
    ("space", "/Library/LaunchAgents/My Agent.plist"),
    ("single quote", "/Library/LaunchAgents/it's.plist"),
    ("two single quotes", "''"),
    ("double quotes", "echo \"hi\""),
    ("backslash", "a\\b"),
    ("backslash-quote", "\\\""),
    ("trailing backslash", "end\\"),
    ("dollar", "$HOME $(id) ${PATH}"),
    ("backticks", "`id`"),
    ("newline", "line1\nline2"),
    ("tab", "a\tb"),
    ("unicode", "/Library/LaunchAgents/com.тест.\u{2714}\u{FE0E}\u{1F642}.plist"),
    ("leading dash", "-rf"),
    ("empty", ""),
    ("metachars", "a;b|c&d*e?f#g~h(i)j"),
]

/// Verbatim copies of the expressions this block removed (DashboardModel delete sites and
/// PrivilegedRunner.run's inline escaping) — the byte-identity oracle.
private func prLegacyShellQuoted(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
private func prLegacyOsaScript(_ command: String) -> String {
    let escaped = command
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "do shell script \"\(escaped)\" with administrator privileges"
}

/// Independent decoder for a word built only of single-quoted runs and `\'`. nil when any
/// character sits outside quotes unescaped (that character would be shell syntax).
private func prDecodeShellWord(_ s: String) -> String? {
    var out = String.UnicodeScalarView()
    var inQuote = false, escaped = false
    for u in s.unicodeScalars {
        if escaped { guard u == "'" else { return nil }; out.append(u); escaped = false; continue }
        if inQuote { if u == "'" { inQuote = false } else { out.append(u) }; continue }
        switch u {
        case "'": inQuote = true
        case "\\": escaped = true
        default: return nil
        }
    }
    return (inQuote || escaped) ? nil : String(out)
}

/// Independent decoder for an AppleScript string-literal body. nil on an unescaped `"` (the
/// literal would end early) or on `\` followed by anything but `\` or `"` (AppleScript would
/// reinterpret `\n`, `\t`, `\r`).
private func prDecodeAppleScriptBody(_ s: String) -> String? {
    var out = String.UnicodeScalarView()
    var escaped = false
    for u in s.unicodeScalars {
        if escaped { guard u == "\\" || u == "\"" else { return nil }; out.append(u); escaped = false; continue }
        if u == "\\" { escaped = true } else if u == "\"" { return nil } else { out.append(u) }
    }
    return escaped ? nil : String(out)
}

/// Scripted stand-in for runProcess: records every invocation, returns results in order.
private final class PRFakeExecutor {
    private var scripted: [PrivilegedRunner.ProcessResult]
    private(set) var calls: [PrivilegedRunner.Invocation] = []
    init(_ scripted: [PrivilegedRunner.ProcessResult]) { self.scripted = scripted }
    func execute(_ invocation: PrivilegedRunner.Invocation) -> PrivilegedRunner.ProcessResult {
        calls.append(invocation)
        if scripted.isEmpty { return .init(exitCode: 99, stderr: "FAKE: unscripted call", stdout: "") }
        return scripted.removeFirst()
    }
}

private typealias PR = PrivilegedRunner
private func R(_ code: Int32, _ err: String, _ out: String) -> PR.ProcessResult {
    PR.ProcessResult(exitCode: code, stderr: err, stdout: out)
}

func runPrivilegedRunnerChecks() {
    let values = prCorpus.map(\.value)
    let sudoOwn = R(1, "sudo: a password is required\n", "")
    let cmd = PR.removeCommand(paths: ["/Library/LaunchAgents/it's \"q\".plist"])

    // --- Builders ---
    check(PR.sudoInvocation("x") == PR.Invocation(path: "/usr/bin/sudo", args: ["/bin/sh", "-c", "x"], timeout: 120),
          "PrivilegedRunner: [sudoInvocation] fixed shape")
    for (label, v) in prCorpus {
        check(PR.sudoInvocation(v).args == ["/bin/sh", "-c", v],
              "PrivilegedRunner: [sudoInvocation verbatim] \(label)")
    }
    check(PR.osascriptInvocation("echo \"hi\"") == PR.Invocation(
            path: "/usr/bin/osascript",
            args: ["-e", "do shell script \"echo \\\"hi\\\"\" with administrator privileges"], timeout: 120),
          "PrivilegedRunner: [osascriptInvocation] double quotes")
    check(PR.osascriptInvocation("a\\b").args == ["-e", "do shell script \"a\\\\b\" with administrator privileges"],
          "PrivilegedRunner: [osascriptInvocation backslash]")
    for (label, v) in prCorpus {
        check(PR.osascriptInvocation(v).args == ["-e", prLegacyOsaScript(v)],
              "PrivilegedRunner: [osascriptInvocation legacy] \(label)")
    }
    for (label, v) in prCorpus {
        let expected: String
        switch label {
        case "double quotes": expected = "echo \\\"hi\\\""
        case "backslash": expected = "a\\\\b"
        case "backslash-quote": expected = "\\\\\\\""
        case "trailing backslash": expected = "end\\\\"
        default: expected = v
        }
        check(PR.appleScriptEscaped(v) == expected, "PrivilegedRunner: [appleScriptEscaped] \(label)")
    }
    for (label, v) in prCorpus {
        check(prDecodeAppleScriptBody(PR.appleScriptEscaped(v)) == v,
              "PrivilegedRunner: [appleScriptEscaped round trip] \(label)")
    }
    for (label, v) in prCorpus {
        let expected: String
        switch label {
        case "single quote": expected = "'/Library/LaunchAgents/it'\\''s.plist'"
        case "two single quotes": expected = "''\\'''\\'''"
        case "empty": expected = "''"
        default: expected = "'" + v + "'"
        }
        check(PR.shellQuoted(v) == expected, "PrivilegedRunner: [shellQuoted] \(label)")
    }
    for (label, v) in prCorpus {
        check(prDecodeShellWord(PR.shellQuoted(v)) == v, "PrivilegedRunner: [shellQuoted round trip] \(label)")
    }
    for (label, v) in prCorpus {
        check(PR.shellQuoted(v) == prLegacyShellQuoted(v), "PrivilegedRunner: [shellQuoted legacy] \(label)")
    }
    check(PR.removeCommand(paths: ["/Library/LaunchDaemons/a.plist"]) == "/bin/rm -f -- '/Library/LaunchDaemons/a.plist'",
          "PrivilegedRunner: [removeCommand one]")
    check(PR.removeCommand(paths: ["/Library/LaunchAgents/a b.plist", "/Library/LaunchDaemons/it's.plist"])
            == "/bin/rm -f -- '/Library/LaunchAgents/a b.plist' '/Library/LaunchDaemons/it'\\''s.plist'",
          "PrivilegedRunner: [removeCommand two]")
    check(PR.removeCommand(paths: []) == "/bin/rm -f -- ", "PrivilegedRunner: [removeCommand empty]")
    // PRIV-RM-DASHDASH: `--` ends rm's options before the first path, so a leading `-` stays an operand.
    check(PR.removeCommand(paths: ["-rf"]) == "/bin/rm -f -- '-rf'",
          "PrivilegedRunner: [removeCommand leading dash] single")
    check(PR.removeCommand(paths: ["-rf", "/Library/LaunchAgents/a.plist", "--force"])
            == "/bin/rm -f -- '-rf' '/Library/LaunchAgents/a.plist' '--force'",
          "PrivilegedRunner: [removeCommand leading dash] multi")
    do {
        let c = PR.removeCommand(paths: ["/Library/LaunchAgents/a.plist", "-x", "/Library/LaunchDaemons/b.plist"])
        let words = c.components(separatedBy: " ")
        check(words.filter { $0 == "--" }.count == 1 && words.firstIndex(of: "--") == 2
                && words.dropFirst(3).allSatisfy { $0.hasPrefix("'") && $0.hasSuffix("'") },
              "PrivilegedRunner: [removeCommand leading dash] one -- before every quoted path")
    }
    for (label, v) in prCorpus {
        check(PR.removeCommand(paths: [v]) == "/bin/rm -f -- \(prLegacyShellQuoted(v))",
              "PrivilegedRunner: [removeCommand legacy] \(label)")
    }
    check(PR.removeCommand(paths: values) == "/bin/rm -f -- " + values.map(prLegacyShellQuoted).joined(separator: " "),
          "PrivilegedRunner: [removeCommand legacy bulk]")

    // --- Decision flow (fake executor) ---
    let both = [PR.sudoInvocation(cmd), PR.osascriptInvocation(cmd)]
    let onlySudo = [PR.sudoInvocation(cmd)]
    let flows: [(String, [PR.ProcessResult], PR.Outcome, [PR.Invocation])] = [
        ("P1 sudo success", [R(0, "", "")], .success, onlySudo),
        ("P2 sudo success with stderr noise", [R(0, "sudo: warning\n", "")], .success, onlySudo),
        ("P3 command failed under sudo", [R(1, "rm: x: Operation not permitted\n", "")],
         .failed("rm: x: Operation not permitted"), onlySudo),
        ("P4 sudo-own, password ok", [sudoOwn, R(0, "", "")], .success, both),
        ("P5 sudo-own on 2nd line, password ok",
         [R(1, "Password:\nsudo: 1 incorrect password attempt\n", ""), R(0, "", "")], .success, both),
        ("P6 sudo-own, cancel", [sudoOwn, R(1, "0:79: execution error: User canceled. (-128)\n", "")],
         .cancelled, both),
        ("P7 sudo-own, osascript failed",
         [sudoOwn, R(1, "0:120: execution error: rm: /Library/LaunchAgents/com.foo-128.plist: Operation not permitted (1)\n", "")],
         .failed("0:120: execution error: rm: /Library/LaunchAgents/com.foo-128.plist: Operation not permitted (1)"), both),
        ("P8 sudo-own, osascript silent failure", [sudoOwn, R(1, "", "")], .failed("unknown error"), both),
        ("P9 sudo timed out", [R(-1, "timed out", "")], .failed("timed out"), onlySudo),
        ("P10 sudo launch failed", [R(-1, "launch failed: boom", "")], .failed("launch failed: boom"), onlySudo),
        ("P11 exit 127 with sudo: line", [R(127, "sudo: command not found\n", "")],
         .failed("sudo: command not found"), onlySudo),
        ("P12 stdout fallback", [R(2, "", "  Firewall is locked\n")], .failed("Firewall is locked"), onlySudo),
        ("P13 whitespace only", [R(2, " \n\t", "")], .failed("unknown error"), onlySudo),
        ("P14 stderr before stdout", [R(2, "err", "out")], .failed("err"), onlySudo),
        ("P15 200-char cap", [R(2, String(repeating: "x", count: 250), "")],
         .failed(String(repeating: "x", count: 200)), onlySudo),
    ]
    for (name, scripted, outcome, calls) in flows {
        let fake = PRFakeExecutor(scripted)
        let got = PR.run(cmd, executor: fake.execute)
        check(got == outcome, "PrivilegedRunner: [flow] \(name) outcome")
        check(fake.calls == calls, "PrivilegedRunner: [flow] \(name) calls")
    }
    do {
        let fake = PRFakeExecutor([R(0, "", "")])
        _ = PR.run(cmd, executor: fake.execute)
        check(fake.calls.count == 1 && fake.calls[0].args.count == 3 && fake.calls[0].args[2] == cmd,
              "PrivilegedRunner: [flow passes command verbatim] P16")
    }

    // --- Real executor, harmless binaries only ---
    check(PR.runProcess(.init(path: "/bin/sh", args: ["-c", "printf out; printf err >&2; exit 3"], timeout: 10))
            == R(3, "err", "out"), "PrivilegedRunner: [runProcess captures] E1")
    check(PR.runProcess(.init(path: "/usr/bin/true", args: [], timeout: 10)) == R(0, "", ""),
          "PrivilegedRunner: [runProcess clean] E2")
    let e3 = PR.runProcess(.init(path: "/usr/bin/macdashboard-no-such-binary", args: [], timeout: 10))
    check(e3.exitCode == -1 && e3.stdout == "" && e3.stderr.hasPrefix("launch failed: "),
          "PrivilegedRunner: [runProcess launch failure] E3")
    let e4 = PR.runProcess(.init(path: "/usr/bin/env", args: [], timeout: 10))
    let envLines = e4.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    let allowedKeys: Set<String> = ["PATH", "LC_ALL", "LANG", "TZ", "HOME", "__CF_USER_TEXT_ENCODING"]
    check(e4.exitCode == 0 && envLines.allSatisfy { allowedKeys.contains(String($0.prefix(while: { $0 != "=" }))) },
          "PrivilegedRunner: [runProcess pinned env keys] E4a")
    check(envLines.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin") && envLines.contains("LC_ALL=C")
            && envLines.contains("HOME=" + NSHomeDirectory()),
          "PrivilegedRunner: [runProcess pinned env values] E4b")
    check(PR.runProcess(.init(path: "/bin/cat", args: [], timeout: 5)) == R(0, "", ""),
          "PrivilegedRunner: [runProcess stdin is /dev/null] E5")
    do {
        let t0 = Date()
        let e6 = PR.runProcess(.init(path: "/bin/sleep", args: ["5"], timeout: 0.3))
        check(e6 == R(-1, "timed out", ""), "PrivilegedRunner: [runProcess timeout] E6 result")
        check(Date().timeIntervalSince(t0) < 3, "PrivilegedRunner: [runProcess timeout] E6 wall time")
    }
    for (label, v) in prCorpus {
        let r = PR.runProcess(.init(path: "/bin/sh", args: ["-c", "printf %s " + PR.shellQuoted(v)], timeout: 10))
        let ok = r.exitCode == 0 && r.stdout == v
        check(ok, "PrivilegedRunner: [shell round trip] \(label)")
        if !ok { print("  DIAG \(label): v=\(v.debugDescription) stdout=\(r.stdout.debugDescription)") }
    }
    do {
        let c = PR.removeCommand(paths: values)
        let prefix = "/bin/rm -f -- "
        let ok = c.hasPrefix(prefix)
        check(ok, "PrivilegedRunner: [removeCommand word split] prefix")
        if ok {
            let r = PR.runProcess(.init(path: "/bin/sh", args: ["-c", "printf '<%s>' " + String(c.dropFirst(prefix.count))], timeout: 10))
            let expected = values.map { "<" + $0 + ">" }.joined()
            check(r.stdout == expected, "PrivilegedRunner: [removeCommand word split] words")
            if r.stdout != expected { print("  DIAG word split: stdout=\(r.stdout.debugDescription)") }
        }
    }
    for (label, v) in prCorpus where label != "unicode" && label != "empty" {
        let r = PR.runProcess(.init(path: "/usr/bin/osascript",
                                    args: ["-e", "return \"" + PR.appleScriptEscaped(v) + "\""], timeout: 20))
        let ok = r.exitCode == 0 && r.stdout == v + "\n"
        check(ok, "PrivilegedRunner: [osascript round trip] \(label)")
        if !ok { print("  DIAG \(label): v=\(v.debugDescription) stdout=\(r.stdout.debugDescription) stderr=\(r.stderr.debugDescription)") }
    }
}
