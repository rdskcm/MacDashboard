// Engine/AppleScriptResult.swift
// Pure classification of one `NSAppleScript` execution result. Lives in Engine
// (and is symlinked into Checks) so the rule that matters — AppleEvent -128 is
// the user backing out, NOT a failure — is covered by a check instead of resting
// on an `if` buried in a view-layer helper. Sole production caller:
// `AdviceActionRunner.emptyTrash`.
import Foundation

enum AppleScriptResult: Equatable {
    case ok
    /// AppleEvent error -128, the standard "user cancelled" code. Finder raises
    /// it when its own "permanently erase?" confirmation is declined.
    case cancelled
    /// `message` is Finder's own localized error text when AppleScript supplied one.
    case failed(message: String?)
    /// AppleEvent error -1743 (`errAEEventNotPermitted`): the Automation grant for
    /// this target app was declined. TCC records a decline persistently and never
    /// re-prompts, so this is NOT a transient Finder failure — it needs its own UI
    /// (a route to System Settings → Privacy & Security → Automation), not Finder's
    /// raw error text.
    case notPermitted

    /// `error` is `NSAppleScript.executeAndReturnError`'s out-dictionary, nil when
    /// the script ran cleanly. An EMPTY dictionary is still an error (the script
    /// reported something we cannot name), never `.ok`.
    static func classify(error: [AnyHashable: Any]?) -> AppleScriptResult {
        guard let error else { return .ok }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
        if (error[NSAppleScript.errorNumber] as? Int) == -1743 { return .notPermitted }
        return .failed(message: error[NSAppleScript.errorMessage] as? String)
    }
}
