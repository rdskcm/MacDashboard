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
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init(), completionHandler: nil)
    }
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    /// Empties the Trash via Finder (our own confirmation dialog precedes this).
    /// Runs the AppleScript off-main; completion is delivered on the main actor.
    static func emptyTrash(completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
            script?.executeAndReturnError(&error)
            let ok = (error == nil)
            DispatchQueue.main.async { completion(ok) }
        }
    }
}
