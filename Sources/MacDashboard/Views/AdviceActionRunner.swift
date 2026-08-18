// Views/AdviceActionRunner.swift
// Executes the system-facing AdviceActions for the Рекомендации card. UI-owned
// confirmations happen BEFORE these calls; model-owned actions (brewUpgrade,
// enableFirewall) never reach here.
import AppKit

/// Serial owner of the `NSAppleScript` used by `AdviceActionRunner.emptyTrash`:
/// ONE thread with a parked run loop, started lazily on first empty-trash and
/// kept for the process lifetime.
///
/// Why not the main actor (the shape this replaces): `executeAndReturnError`
/// blocks until Finder is done — which includes Finder's own "permanently
/// erase?" confirmation, the first-run automation permission prompt, and the
/// whole time a multi-gigabyte Trash takes. The window stopped redrawing and our
/// own confirmation dialog sat on screen undismissed.
/// Why not a global queue: `NSAppleScript` is not thread-safe, wants a run loop,
/// and an instance must stay on the thread that created it — a queue hands out a
/// different thread per call.
/// Blocks queue on this thread's run loop, so two empty-trash runs can never
/// overlap and no lock is needed.
private final class AppleScriptThread {
    static let shared = AppleScriptThread()

    private var runLoop: CFRunLoop?

    private init() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            ready.signal()
            // A run loop with no input source returns immediately, so the port is
            // what parks this thread instead of spinning it.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            while true {
                // `run(mode:before:)` returns false only if the mode has no input
                // source at all. The port above guarantees one; the sleep is a
                // backstop so a degenerate case can never become a busy loop
                // (idle CPU is a standing constraint in this app).
                if !RunLoop.current.run(mode: .default, before: .distantFuture) {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
        thread.name = "com.macdashboard.applescript"
        thread.stackSize = 512 * 1024
        thread.start()
        // Bounded by a thread start (no I/O): the run loop must exist before the
        // first block can be posted to it.
        ready.wait()
    }

    /// Runs `body` on the owning thread, asynchronously.
    func async(_ body: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, body)
        CFRunLoopWakeUp(runLoop)
    }
}

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

    /// Empties the Trash via Finder (our own confirmation dialog precedes this and
    /// is dismissed before the call — see `AdviceActionDispatch.confirmEmptyTrash`).
    /// Runs on `AppleScriptThread` (see its doc comment for why not main / not a
    /// queue); `completion` is delivered on the main actor exactly once.
    @MainActor
    static func emptyTrash(completion: @escaping @MainActor (TrashOutcome) -> Void) {
        AppleScriptThread.shared.async {
            // Created AND executed on the owning thread — an NSAppleScript
            // instance must not travel between threads.
            guard let script = NSAppleScript(source: "tell application \"Finder\" to empty trash") else {
                // A nil script must NOT read as success: with the old
                // optional-chained call `error` stayed nil, so the UI showed the
                // done state while the Trash was never touched.
                deliver(.failed(detail: nil), to: completion)
                return
            }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            switch AppleScriptResult.classify(error: error as? [AnyHashable: Any]) {
            case .ok: deliver(.emptied, to: completion)
            case .cancelled: deliver(.cancelled, to: completion)
            case .failed(let message): deliver(.failed(detail: message), to: completion)
            }
        }
    }

    /// The only way `emptyTrash` ever calls its completion: one hop back to the
    /// main actor.
    private static func deliver(_ outcome: TrashOutcome,
                                to completion: @escaping @MainActor (TrashOutcome) -> Void) {
        Task { @MainActor in completion(outcome) }
    }
}
