// Checks/SudoPathSafetyChecks.swift
// V2-SECURITY-FIX (M2): coverage for ReportCollector.isSafeToRunViaSudo — the
// predicate that decides whether a resolved smartctl path may be handed to `sudo`.
// Real check code (NOT a symlink — see README.md); `check()` is main.swift's
// top-level helper, visible here because both files compile into the same module.

import Foundation

func runSudoPathSafetyChecks() {
    check(ReportCollector.isSafeToRunViaSudo("/usr/bin/sudo"),
          "isSafeToRunViaSudo: /usr/bin/sudo (root-owned chain, no group/other write) ⇒ true")
    check(!ReportCollector.isSafeToRunViaSudo("/tmp"),
          "isSafeToRunViaSudo: /tmp (world-writable) ⇒ false")
    check(!ReportCollector.isSafeToRunViaSudo("/usr/bin/macdashboard-no-such-binary"),
          "isSafeToRunViaSudo: nonexistent path ⇒ false")
    check(!ReportCollector.isSafeToRunViaSudo("usr/bin/sudo"),
          "isSafeToRunViaSudo: relative path ⇒ false")
    check(!ReportCollector.isSafeToRunViaSudo("/usr"),
          "isSafeToRunViaSudo: /usr (root-owned, non-writable — but a DIRECTORY) ⇒ false")

    // re-review 2 [N7]: the two branches the filesystem cases above structurally cannot
    // reach — no stock macOS file carries `schg`, and this process cannot create a
    // root-owned file — covered on the pure decision core instead.
    check(ReportCollector.sudoSafetyVerdict(isRegularFile: true, ownerUID: 0, mode: 0o755,
                                            isImmutable: true, ancestorsRootOwned: false),
          "sudoSafetyVerdict: root-owned 0755 file with schg in a group-writable dir ⇒ true")
    check(!ReportCollector.sudoSafetyVerdict(isRegularFile: true, ownerUID: 0, mode: 0o755,
                                             isImmutable: false, ancestorsRootOwned: false),
          "sudoSafetyVerdict: root-owned 0755 file in a group-writable dir WITHOUT schg ⇒ false")
    check(ReportCollector.sudoSafetyVerdict(isRegularFile: true, ownerUID: 0, mode: 0o755,
                                            isImmutable: false, ancestorsRootOwned: true),
          "sudoSafetyVerdict: root-owned 0755 file with a fully root-owned ancestor chain ⇒ true")
    check(!ReportCollector.sudoSafetyVerdict(isRegularFile: true, ownerUID: 501, mode: 0o755,
                                             isImmutable: true, ancestorsRootOwned: true),
          "sudoSafetyVerdict: non-root owner ⇒ false even with schg and a root-owned chain")
    check(!ReportCollector.sudoSafetyVerdict(isRegularFile: true, ownerUID: 0, mode: 0o775,
                                             isImmutable: true, ancestorsRootOwned: true),
          "sudoSafetyVerdict: group-writable file mode ⇒ false even with schg")
    check(!ReportCollector.sudoSafetyVerdict(isRegularFile: false, ownerUID: 0, mode: 0o755,
                                             isImmutable: true, ancestorsRootOwned: true),
          "sudoSafetyVerdict: not a regular file ⇒ false")

    // N3: /usr/local {bin,sbin} fallback-tool ownership check.
    check(ReportCollector.fallbackToolVerdict(isRegularFile: true, ownerUID: 501, currentUID: 501, mode: 0o755),
          "fallbackToolVerdict: regular, owner 501, current 501, 0o755 ⇒ true")
    check(ReportCollector.fallbackToolVerdict(isRegularFile: true, ownerUID: 0, currentUID: 501, mode: 0o755),
          "fallbackToolVerdict: regular, owner 0, current 501, 0o755 ⇒ true")
    check(!ReportCollector.fallbackToolVerdict(isRegularFile: true, ownerUID: 502, currentUID: 501, mode: 0o755),
          "fallbackToolVerdict: regular, owner 502, current 501, 0o755 ⇒ false")
    check(!ReportCollector.fallbackToolVerdict(isRegularFile: true, ownerUID: 501, currentUID: 501, mode: 0o775),
          "fallbackToolVerdict: regular, owner 501, current 501, 0o775 (group-writable) ⇒ false")
    check(!ReportCollector.fallbackToolVerdict(isRegularFile: true, ownerUID: 501, currentUID: 501, mode: 0o757),
          "fallbackToolVerdict: regular, owner 501, current 501, 0o757 (world-writable) ⇒ false")
    check(!ReportCollector.fallbackToolVerdict(isRegularFile: false, ownerUID: 0, currentUID: 501, mode: 0o755),
          "fallbackToolVerdict: not a regular file ⇒ false")

    check(ReportCollector.isTrustedFallbackTool("/usr/bin/true"),
          "isTrustedFallbackTool: /usr/bin/true ⇒ true")
    check(!ReportCollector.isTrustedFallbackTool("/tmp"),
          "isTrustedFallbackTool: /tmp (world-writable) ⇒ false")
    check(!ReportCollector.isTrustedFallbackTool("/usr/bin/macdashboard-no-such-binary"),
          "isTrustedFallbackTool: nonexistent path ⇒ false")
    check(!ReportCollector.isTrustedFallbackTool("usr/bin/true"),
          "isTrustedFallbackTool: relative path ⇒ false")

    do {
        let path = NSTemporaryDirectory() + "macdashboard-fallback-tool-\(getpid())"
        FileManager.default.createFile(atPath: path, contents: Data())
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        check(ReportCollector.isTrustedFallbackTool(path),
              "isTrustedFallbackTool: own temp file, mode 0o644 ⇒ true")
        try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: path)
        check(!ReportCollector.isTrustedFallbackTool(path),
              "isTrustedFallbackTool: own temp file, mode 0o666 (world-writable) ⇒ false")
        try? FileManager.default.setAttributes([.posixPermissions: 0o664], ofItemAtPath: path)
        check(!ReportCollector.isTrustedFallbackTool(path),
              "isTrustedFallbackTool: own temp file, mode 0o664 (group-writable) ⇒ false")
        try? FileManager.default.removeItem(atPath: path)
    }

    do {
        let alwaysExecutable: (String) -> Bool = { _ in true }
        let neverExecutable: (String) -> Bool = { _ in false }
        let alwaysTrusted: (String) -> Bool = { _ in true }
        let neverTrusted: (String) -> Bool = { _ in false }

        check(ReportCollector.firstTool(primary: ["/opt/homebrew/bin/x"], fallback: ["/usr/local/bin/x"],
                                        isExecutable: alwaysExecutable, isTrusted: alwaysTrusted) == "/opt/homebrew/bin/x",
              "firstTool: primary executable ⇒ the primary, even when a fallback is also trusted")
        check(ReportCollector.firstTool(primary: ["/opt/homebrew/bin/x"], fallback: ["/usr/local/bin/x"],
                                        isExecutable: { $0 == "/usr/local/bin/x" }, isTrusted: neverTrusted) == nil,
              "firstTool: primary absent, only fallback executable but untrusted ⇒ nil")
        check(ReportCollector.firstTool(primary: [], fallback: ["/usr/local/sbin/x", "/usr/local/bin/x"],
                                        isExecutable: alwaysExecutable,
                                        isTrusted: { $0 == "/usr/local/bin/x" }) == "/usr/local/bin/x",
              "firstTool: two fallbacks, first untrusted, second trusted ⇒ the second")
        check(ReportCollector.firstTool(primary: ["/opt/homebrew/bin/x"], fallback: ["/usr/local/bin/x"],
                                        isExecutable: neverExecutable, isTrusted: alwaysTrusted) == nil,
              "firstTool: nothing executable ⇒ nil")
    }
}
