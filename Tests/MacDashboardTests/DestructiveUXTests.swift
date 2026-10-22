// Tests/MacDashboardTests/DestructiveUXTests.swift
// Port of Checks/main.swift lines 2904-2997 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct DestructiveUXTests {
        @Test func destructiveUX() async {
            // =====================================================================
            // MARK: - V2-DESTRUCTIVE-UX (optimistic-delete restore + AppleScript outcome)
            // =====================================================================

            do {
                func orphan(_ path: String) -> LaunchdPlistInfo {
                    LaunchdPlistInfo(path: path, label: nil, executablePath: nil, isOrphan: true, description: nil)
                }
                let a = orphan("/Users/x/Library/LaunchAgents/a.plist")
                let b = orphan("/Library/LaunchAgents/b.plist")
                let c = orphan("/Library/LaunchDaemons/c.plist")
                let canonical = [a, b, c]

                // --- pathsNotDeleted: the mixed-batch rule (finding A4) ---
                #expect(LaunchdPlistInspector.pathsNotDeleted(results: [(a.path, .success), (b.path, .success)]).isEmpty,
                      "pathsNotDeleted: an all-success batch restores nothing")
                #expect(LaunchdPlistInspector.pathsNotDeleted(
                        results: [(a.path, .success), (b.path, .cancelled), (c.path, .cancelled)]) == [b.path, c.path],
                      "pathsNotDeleted: mixed batch restores only the cancelled system-level paths")
                #expect(LaunchdPlistInspector.pathsNotDeleted(
                        results: [(a.path, .failed("boom")), (b.path, .cancelled)]) == [a.path, b.path],
                      "pathsNotDeleted: failed and cancelled both restore")
                #expect(LaunchdPlistInspector.pathsNotDeleted(
                        results: [(a.path, .success), (b.path, .timedOut), (c.path, .timedOut)]) == [b.path, c.path],
                      "pathsNotDeleted: a timed-out system batch keeps its rows like a cancelled one")
                #expect(LaunchdPlistInspector.pathsNotDeleted(results: []).isEmpty,
                      "pathsNotDeleted: empty results restore nothing")

                // --- restoredOrphanList: where a row comes back (finding A3) ---
                #expect(LaunchdPlistInspector.restoredOrphanList(display: [a, c], restoring: [], canonical: canonical) == [a, c],
                      "restoredOrphanList: an empty restore set is the identity")
                #expect(LaunchdPlistInspector.restoredOrphanList(display: [a, c], restoring: [b.path], canonical: canonical) == [a, b, c],
                      "restoredOrphanList: a middle row comes back in the middle")
                #expect(LaunchdPlistInspector.restoredOrphanList(display: [b, c], restoring: [a.path], canonical: canonical) == [a, b, c],
                      "restoredOrphanList: the first row comes back at the front")
                #expect(LaunchdPlistInspector.restoredOrphanList(display: [a, b], restoring: [c.path], canonical: canonical) == [a, b, c],
                      "restoredOrphanList: the last row comes back at the end")
                #expect(LaunchdPlistInspector.restoredOrphanList(display: [], restoring: [a.path, b.path, c.path], canonical: canonical) == canonical,
                      "restoredOrphanList: a whole bulk batch comes back in canonical order")
                #expect(LaunchdPlistInspector.restoredOrphanList(display: [a, c], restoring: [c.path], canonical: canonical) == [a, c],
                      "restoredOrphanList: an already-displayed path is not duplicated")
                #expect(LaunchdPlistInspector.restoredOrphanList(display: [b, c], restoring: [a.path], canonical: [b, c]) == [b, c],
                      "restoredOrphanList: a path the model no longer lists is NOT resurrected")
                #expect(LaunchdPlistInspector.restoredOrphanList(display: [], restoring: [a.path, b.path, c.path], canonical: [b, c]) == [b, c],
                      "restoredOrphanList: mixed batch — the successfully deleted path stays gone")

                // --- the signal itself ---
                #expect(PlistDeleteRestoreSignal(paths: [a.path], stamp: 1) != PlistDeleteRestoreSignal(paths: [a.path], stamp: 2),
                      "PlistDeleteRestoreSignal: Equatable includes `stamp`, so the same failure twice is two signals")

                // --- AppleScriptResult: the -128 rule (finding A5) ---
                #expect(AppleScriptResult.classify(error: nil) == .ok,
                      "AppleScriptResult: no error dictionary is a clean run")
                #expect(AppleScriptResult.classify(error: [NSAppleScript.errorNumber: -128]) == .cancelled,
                      "AppleScriptResult: -128 is a cancel, not a failure")
                #expect(AppleScriptResult.classify(
                        error: [NSAppleScript.errorNumber: -1728, NSAppleScript.errorMessage: "Finder got an error"])
                        == .failed(message: "Finder got an error"),
                      "AppleScriptResult: any other error carries Finder's own message")
                #expect(AppleScriptResult.classify(error: [:]) == .failed(message: nil),
                      "AppleScriptResult: an empty error dictionary is a failure, never a success")
                #expect(AppleScriptResult.classify(error: [NSAppleScript.errorNumber: -1743]) == .notPermitted,
                      "AppleScriptResult: -1743 is a declined Automation grant, not a generic failure")
                #expect(AppleScriptResult.classify(
                        error: [NSAppleScript.errorNumber: -1743, NSAppleScript.errorMessage: "Not authorized"])
                        == .notPermitted,
                      "AppleScriptResult: -1743 wins over Finder's own message")

                // --- PrivilegedRunner: cancellation is the ERROR NUMBER, not a substring ---
                #expect(PrivilegedRunner.isUserCancellation(exitCode: 1, stderr: "0:79: execution error: User canceled. (-128)\n"),
                      "isUserCancellation: osascript's -128 error line is a cancel")
                #expect(PrivilegedRunner.isUserCancellation(exitCode: 1, stderr: "0:79: execution error: Пользователь отменил операцию. (-128)"),
                      "isUserCancellation: locale-independent — the number, not the message")
                #expect(!PrivilegedRunner.isUserCancellation(
                        exitCode: 1,
                        stderr: "0:126: execution error: rm: /Users/x/Library/LaunchAgents/com.foo-128.plist: Operation not permitted (1)"),
                      "isUserCancellation: a path containing -128 in a genuinely FAILED delete is not a cancel")
                #expect(!PrivilegedRunner.isUserCancellation(exitCode: 0, stderr: ""),
                      "isUserCancellation: a clean run is not a cancel")
                #expect(!PrivilegedRunner.isUserCancellation(exitCode: 1, stderr: ""),
                      "isUserCancellation: empty stderr is not a cancel")

                // --- PrivilegedRunner: isSudoOwnFailure distinguishes sudo's own errors from a
                // privileged command that ran and failed (V21-HONEST-EXITS) ---
                #expect(PrivilegedRunner.isSudoOwnFailure(exitCode: 1, stderr: "sudo: a password is required\n"),
                      "isSudoOwnFailure: \"sudo: a password is required\" ⇒ true")
                #expect(PrivilegedRunner.isSudoOwnFailure(exitCode: 1, stderr: "sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper\n"),
                      "isSudoOwnFailure: \"sudo: a terminal is required...\" ⇒ true")
                #expect(!PrivilegedRunner.isSudoOwnFailure(exitCode: 1, stderr: "rm: /Library/LaunchDaemons/x.plist: Operation not permitted\n"),
                      "isSudoOwnFailure: command ran and failed (no sudo: line) ⇒ false")
                #expect(!PrivilegedRunner.isSudoOwnFailure(exitCode: 1, stderr: ""),
                      "isSudoOwnFailure: empty stderr ⇒ false")
                #expect(!PrivilegedRunner.isSudoOwnFailure(exitCode: 127, stderr: "sudo: command not found\n"),
                      "isSudoOwnFailure: only exit 1 is sudo's own error code ⇒ false")
                #expect(!PrivilegedRunner.isSudoOwnFailure(exitCode: 0, stderr: ""),
                      "isSudoOwnFailure: exit 0 ⇒ false")
            }
        }
    }
}
