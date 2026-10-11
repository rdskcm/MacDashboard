// Engine/ParkedRunLoopThread.swift
// One thread with a parked run loop, started on init and kept for the process
// lifetime. Shared by the AppleScript runner (AdviceActionRunner) and the
// MobileDevice transport: both need a single serial owner thread with a run loop
// (NSAppleScript instances must stay on their thread; MobileDevice delivers its
// notification callbacks on the subscribing thread's run loop).
import Foundation

/// Blocks queue on this thread's run loop, so two blocks can never overlap and no
/// lock is needed.
final class ParkedRunLoopThread {
    private var runLoop: CFRunLoop?

    init(name: String) {
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
        thread.name = name
        thread.stackSize = 512 * 1024
        thread.start()
        // Bounded by a thread start (no I/O): the run loop must exist before the
        // first block can be posted to it.
        ready.wait()
    }

    /// Runs `body` on the owning thread, asynchronously. Returns false if the run loop
    /// is somehow missing — unreachable (the `ready.wait()` semaphore guarantees it),
    /// but this is the only place in the trash flow that could lose a completion and
    /// strand the capsule on a spinner for the rest of the session.
    @discardableResult
    func async(_ body: @escaping () -> Void) -> Bool {
        guard let runLoop else {
            assertionFailure("ParkedRunLoopThread.runLoop is nil after ready.wait()")
            return false
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, body)
        CFRunLoopWakeUp(runLoop)
        return true
    }
}
