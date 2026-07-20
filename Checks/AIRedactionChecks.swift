// Checks/AIRedactionChecks.swift
// Pure-logic coverage for Redactor (Block AI, Wave 1): word-boundary-guarded,
// case-insensitive, longest-first, deterministic redaction. Real check code (NOT
// a symlink — see README.md), following the same pattern as
// LaunchdPlistInspectorChecks.swift.

import Foundation

func runAIRedactionChecks() {
    let ctx = RedactionContext(
        usernames: ["testuser", "Ivan Petrov"],
        hostNames: ["MacBook-Pro-testuser.local", "MacBook-Pro-testuser"],
        serials: ["C02XR4KGJGH5", "F5D1234PLQ"],
        ssids: ["HomeNet-5G", "Kofeynya u Doma"]
    )
    let all = RedactionOptions()

    // 1
    do {
        let result = Redactor.redact("  10,5 ГБ  /Users/testuser/Downloads", context: ctx, options: all)
        check(result.contains("/Users/[REDACTED-USER]/Downloads"),
              "redact: username in path replaced (got \(result))")
    }

    // 2
    do {
        let input = "user testuser on line 1\nsecond mention of TESTUSER here\nand teStuser again"
        let result = Redactor.redact(input, context: ctx, options: all)
        check(result.range(of: "testuser", options: .caseInsensitive) == nil,
              "redact: no case-insensitive 'testuser' remains across multiple lines")
    }

    // 3
    do {
        let result = Redactor.redact("crash report for user testuser today", context: ctx, options: all)
        check(result == "crash report for user [REDACTED-USER] today",
              "redact: exact substitution mid-sentence (got \(result))")
    }

    // 4
    do {
        let result = Redactor.redact("/USERS/TESTUSER/Library", context: ctx, options: all)
        check(result.contains("[REDACTED-USER]") && !result.contains("TESTUSER"),
              "redact: uppercase username matched case-insensitively (got \(result))")
    }

    // 5: word-boundary negative + positive
    do {
        let maxCtx = RedactionContext(usernames: ["max"])
        let unchanged = Redactor.redact("Maximum Capacity: 85%", context: maxCtx, options: all)
        check(unchanged == "Maximum Capacity: 85%",
              "redact: word-boundary prevents partial match inside 'Maximum' (got \(unchanged))")
        let matched = Redactor.redact("/Users/max/Desktop", context: maxCtx, options: all)
        check(matched.contains("[REDACTED-USER]"),
              "redact: word-boundary allows exact standalone match (got \(matched))")
    }

    // 6
    do {
        let result = Redactor.redact("Owner: Ivan Petrov", context: ctx, options: all)
        check(result == "Owner: [REDACTED-USER]", "redact: multi-word username (got \(result))")
    }

    // 7
    do {
        let result = Redactor.redact("host MacBook-Pro-testuser.local up", context: ctx, options: all)
        let hostCount = result.components(separatedBy: "[REDACTED-HOST]").count - 1
        check(hostCount == 1, "redact: hostname replaced exactly once (got \(hostCount) in \(result))")
        check(!result.contains("[REDACTED-USER]"), "redact: hostname redaction doesn't also produce [REDACTED-USER] (got \(result))")
        check(!result.contains("-testuser.local"), "redact: no leftover hostname suffix (got \(result))")
    }

    // 8
    do {
        let result = Redactor.redact("ComputerName: MacBook-Pro-testuser", context: ctx, options: all)
        check(result == "ComputerName: [REDACTED-HOST]", "redact: short hostname form (got \(result))")
    }

    // 9
    do {
        let result = Redactor.redact("Serial Number (system): C02XR4KGJGH5", context: ctx, options: all)
        check(result.contains("[REDACTED-SERIAL]"), "redact: serial number replaced (got \(result))")
    }

    // 10
    do {
        let input = "disk1 serial C02XR4KGJGH5, disk2 serial F5D1234PLQ"
        let result = Redactor.redact(input, context: ctx, options: all)
        let serialCount = result.components(separatedBy: "[REDACTED-SERIAL]").count - 1
        check(serialCount == 2, "redact: both serials replaced (got \(serialCount) in \(result))")
        check(!result.contains("C02XR4KGJGH5") && !result.contains("F5D1234PLQ"),
              "redact: no leftover serial substrings (got \(result))")
    }

    // 11
    do {
        let result = Redactor.redact("Wi-Fi: HomeNet-5G (RSSI -54)", context: ctx, options: all)
        check(result.contains("[REDACTED-SSID]"), "redact: SSID replaced (got \(result))")
        check(result.contains("(RSSI -54)"), "redact: unrelated text preserved (got \(result))")
    }

    // 12
    do {
        let result = Redactor.redact("сеть Kofeynya u Doma", context: ctx, options: all)
        check(result.contains("[REDACTED-SSID]"), "redact: multi-word SSID replaced in RU text (got \(result))")
    }

    // 13
    do {
        var opts = RedactionOptions()
        opts.redactUsername = false
        let result = Redactor.redact("/Users/testuser/x with serial C02XR4KGJGH5", context: ctx, options: opts)
        check(result.contains("testuser"), "redact: redactUsername=false leaves username untouched (got \(result))")
        check(result.contains("[REDACTED-SERIAL]"), "redact: serial still redacted with redactUsername=false (got \(result))")
    }

    // 14
    do {
        // Isolated hostname (no overlap with any username in `ctx`) so this case
        // exercises only the redactHostname flag, not a coincidental username match.
        let isolatedCtx = RedactionContext(hostNames: ["office-imac.local"])
        var opts = RedactionOptions()
        opts.redactHostname = false
        let result = Redactor.redact("host office-imac.local up", context: isolatedCtx, options: opts)
        check(result.contains("office-imac.local"), "redact: redactHostname=false leaves hostname untouched (got \(result))")
    }
    do {
        var opts = RedactionOptions()
        opts.redactSerials = false
        let result = Redactor.redact("serial C02XR4KGJGH5", context: ctx, options: opts)
        check(result.contains("C02XR4KGJGH5"), "redact: redactSerials=false leaves serial untouched (got \(result))")
    }
    do {
        var opts = RedactionOptions()
        opts.redactSSID = false
        let result = Redactor.redact("Wi-Fi: HomeNet-5G", context: ctx, options: opts)
        check(result.contains("HomeNet-5G"), "redact: redactSSID=false leaves SSID untouched (got \(result))")
    }

    // 15
    do {
        let shortCtx = RedactionContext(usernames: ["", "a"])
        let result = Redactor.redact("a banana", context: shortCtx, options: all)
        check(result == "a banana", "redact: values shorter than 2 chars ignored (got \(result))")
    }

    // 16
    do {
        let input = "/Users/testuser/Downloads with serial C02XR4KGJGH5 on HomeNet-5G"
        let result = Redactor.redact(input, context: RedactionContext(), options: all)
        check(result == input, "redact: empty context leaves input byte-identical (got \(result))")
    }

    // 17: idempotence
    do {
        let input = "  10,5 ГБ  /Users/testuser/Downloads"
        let once = Redactor.redact(input, context: ctx, options: all)
        let twice = Redactor.redact(once, context: ctx, options: all)
        check(once == twice, "redact: idempotent on already-redacted text (got \(once) vs \(twice))")
    }
}
