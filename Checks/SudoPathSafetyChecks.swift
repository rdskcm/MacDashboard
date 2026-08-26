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
}
