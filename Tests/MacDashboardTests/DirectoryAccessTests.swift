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
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.tips.filter { $0.text == L.assessNoFDATip }.count == 1,
                      "assess no-FDA: unreadable home folders ⇒ exactly one tip")
                let caps = a.capsules.filter { $0.action == .settingsPane(AdvicePanes.fullDiskAccess) }
                #expect(caps.count == 1, "assess no-FDA: exactly one capsule")
                #expect(caps.first?.object == L.attnCapFolders && caps.first?.value == L.attnCapFoldersNoAccess,
                      "assess no-FDA: capsule carries the folders object/value")
                #expect(caps.first?.verb == L.attnVerbSettings,
                      "assess no-FDA: capsule verb is the settings verb")
                #expect(a.problems.isEmpty && a.items.isEmpty,
                      "assess no-FDA: never produces a problem / «Требует внимания» item")
            }
            do {
                var report = FullReport()
                report.homeDirsUnreadable = ["/Users/x/.Trash"]
                report.serviceDirsUnreadable = ["/Users/x/Library/Containers"]
                let a = Assess.assess(report: report, live: LiveSnapshot())
                #expect(a.tips.filter { $0.text == L.assessNoFDATip }.count == 1,
                      "assess no-FDA: both sections unreadable ⇒ still exactly one tip")
                #expect(a.capsules.filter { $0.action == .settingsPane(AdvicePanes.fullDiskAccess) }.count == 1,
                      "assess no-FDA: both sections unreadable ⇒ still exactly one capsule")
            }
            do {
                let a = Assess.assess(report: FullReport(), live: LiveSnapshot())
                #expect(!a.tips.contains { $0.text == L.assessNoFDATip },
                      "assess no-FDA: nothing hidden ⇒ no tip")
                #expect(!a.capsules.contains { $0.action == .settingsPane(AdvicePanes.fullDiskAccess) },
                      "assess no-FDA: nothing hidden ⇒ no capsule")
            }
            do {
                #expect(AdvicePanes.fullDiskAccess == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
                      "AdvicePanes.fullDiskAccess: exact pane URL")
                for (name, s) in [("EN", StringsEN() as AppStrings), ("RU", StringsRU() as AppStrings)] {
                    #expect(!s.assessNoFDATip.isEmpty && !s.storageFoldersNoFDAButton.isEmpty &&
                          !s.storageFoldersNoFDAButtonA11y.isEmpty && !s.attnCapFolders.isEmpty &&
                          !s.attnCapFoldersNoAccess.isEmpty && !s.attnExplainNoFDA.isEmpty,
                          "L10n no-FDA strings: non-empty in \(name)")
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
