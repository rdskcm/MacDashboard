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
}
