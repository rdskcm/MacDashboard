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
