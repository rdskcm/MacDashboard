// Views/AdviceActionRunner.swift
// Executes the system-facing AdviceActions for the Рекомендации card. UI-owned
// confirmations happen BEFORE these calls; model-owned actions (brewUpgrade,
// enableFirewall) never reach here.
import AppKit

enum AdviceActionRunner {
    static func openPane(_ url: String) {
        guard let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }
    static func openApp(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, error in
            // Nothing in the UI is waiting on this, but a nil handler swallowed launch
            // failure entirely — at least leave a trace in Console.
            if let error {
                NSLog("[MacDashboard] openApp failed for %@: %@", path, error.localizedDescription)
            }
        }
    }
    /// Reveals `path` in Finder. Regular directories are opened directly (users expect
    /// the folder itself, not its parent with the folder selected); files, missing paths,
    /// and file packages (bundles, .rtfd, etc.) use "select in enclosing folder" instead.
    /// This prevents opening a bundle, which would launch the app instead of revealing it.
    static func reveal(_ path: String) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue {
            // Check if this directory is actually a file package (bundle, .rtfd, etc.)
            let isPackage = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
            if isPackage {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }
    /// Outcome of `emptyTrash`. Deliberately not a `Bool`: "did not empty the Trash"
    /// and "the user backed out" need different UI, and a failure carries Finder's own
    /// message when it gave one.
    enum TrashOutcome {
        case emptied
        case cancelled
        /// `detail` is Finder's localized error message, when AppleScript supplied one.
        case failed(detail: String?)
    }

    /// Empties the Trash via Finder (our own confirmation dialog precedes this).
    ///
    /// Runs on the main actor. `NSAppleScript` is not documented as thread-safe and
    /// expects a run loop, and this call is fast and already gated by a dialog. If a
    /// large Trash ever makes it hang measurably, the correct escalation is
    /// `NSUserAppleScriptTask` or an instance confined to one dedicated run-loop
    /// thread — NOT moving it back to an arbitrary global queue.
    @MainActor
    static func emptyTrash(completion: @escaping @MainActor (TrashOutcome) -> Void) {
        // A nil script must NOT read as success: with the old optional-chained call
        // `error` stayed nil, so the UI showed the done state while the Trash was
        // never touched.
        guard let script = NSAppleScript(source: "tell application \"Finder\" to empty trash") else {
            completion(.failed(detail: nil))
            return
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else {
            completion(.emptied)
            return
        }
        // -128 is the standard "user cancelled" AppleEvent code; it is not an error
        // state and must not surface as one.
        if (error[NSAppleScript.errorNumber] as? Int) == -128 {
            completion(.cancelled)
            return
        }
        completion(.failed(detail: error[NSAppleScript.errorMessage] as? String))
    }
}
