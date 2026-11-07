// Tests/MacDashboardTests/DirectoryAccessTests.swift
// Port of Checks/main.swift lines 2501-2602 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct DirectoryAccessTests {
        @Test func directoryAccess() async {
            // =====================================================================
            // MARK: - DirectoryAccess (Block V2-FDA-DEGRADE)
            // =====================================================================

            do {
                // Pure decision table — every branch, no syscalls, no dependence on whether
                // this machine actually holds Full Disk Access.
                #expect(DirectoryAccess.classify(exists: false, isDirectory: false, open: .opened) == .missing,
                      "DirectoryAccess.classify: path absent ⇒ .missing")
                #expect(DirectoryAccess.classify(exists: true, isDirectory: false, open: .opened) == .missing,
                      "DirectoryAccess.classify: exists but not a directory ⇒ .missing")
                #expect(DirectoryAccess.classify(exists: true, isDirectory: true, open: .opened) == .readable,
                      "DirectoryAccess.classify: directory opened ⇒ .readable")
                #expect(DirectoryAccess.classify(exists: true, isDirectory: true, open: .permissionDenied) == .denied,
                      "DirectoryAccess.classify: directory refused ⇒ .denied")
                #expect(DirectoryAccess.classify(exists: true, isDirectory: true, open: .otherFailure) == .missing,
                      "DirectoryAccess.classify: open failed for a non-permission reason ⇒ .missing")

                // Pure set math for the home rule.
                let missing = DirectoryAccess.missingHomeChildren(
                    home: "/Users/x",
                    duPaths: ["/Users/x", "/Users/x/Documents", "/Users/x/Library"],
                    childNames: ["Documents", "Library", ".Trash", "notes.txt"])
                #expect(missing == ["/Users/x/.Trash", "/Users/x/notes.txt"],
                      "DirectoryAccess.missingHomeChildren: exactly the children du never reported, sorted")

                #expect(DirectoryAccess.missingHomeChildren(home: "/Users/x/",
                                                          duPaths: ["/Users/x/Documents/"],
                                                          childNames: ["Documents"]).isEmpty,
                      "DirectoryAccess.missingHomeChildren: trailing slashes on either side still count as reported")

                #expect(DirectoryAccess.missingHomeChildren(home: "/Users/x", duPaths: [], childNames: []).isEmpty,
                      "DirectoryAccess.missingHomeChildren: $HOME unlistable ⇒ empty, never a claim")

                // Live probe, grant-independent: $HOME is readable for whoever runs this;
                // /private/var/root is 0750 root:wheel, so a non-root process is refused with
                // or without Full Disk Access; the third path does not exist.
                #expect(DirectoryAccess.probe(NSHomeDirectory()) == .readable,
                      "DirectoryAccess.probe: $HOME ⇒ .readable")
                #expect(DirectoryAccess.probe("/private/var/empty/macdashboard-no-such-dir") == .missing,
                      "DirectoryAccess.probe: absent path ⇒ .missing")
                #expect(DirectoryAccess.probe("/usr/bin/du") == .missing,
                      "DirectoryAccess.probe: a regular file ⇒ .missing")
                if geteuid() != 0 {
                    #expect(DirectoryAccess.probe("/private/var/root") == .denied,
                          "DirectoryAccess.probe: root-only directory ⇒ .denied")
                }
            }

            do {
                var report = FullReport()
                report.homeDirsUnreadable = ["/Users/x/.Trash"]
                let a = Assess.assess(report: report, live: LiveSnapshot(), language: L10nStore.shared.language)
                #expect(a.items.isEmpty, "assess no-FDA: never produces a «Требует внимания» item")
            }
            do {
                #expect(AdvicePanes.fullDiskAccess == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
                      "AdvicePanes.fullDiskAccess: exact pane URL")
                for (name, s) in [("EN", StringsEN() as AppStrings), ("RU", StringsRU() as AppStrings)] {
                    #expect(s.storageFoldersNoFDA("Корзина").contains("Корзина"),
                          "L10n storageFoldersNoFDA: interpolates the folder list in \(name)")
                }
            }
            do {
                for (name, s) in [("EN", StringsEN() as AppStrings), ("RU", StringsRU() as AppStrings)] {
                    #expect(!s.autostartDeleteInvalidPath.isEmpty,
                          "L10n autostartDeleteInvalidPath: non-empty in \(name)")
                    let bulk = s.autostartDeleteBulkFailure(2, 5, "boom")
                    #expect(bulk.contains("2") && bulk.contains("5") && bulk.contains("boom"),
                          "L10n autostartDeleteBulkFailure: interpolates counts and detail in \(name)")
                }
            }
        }
    }
}
