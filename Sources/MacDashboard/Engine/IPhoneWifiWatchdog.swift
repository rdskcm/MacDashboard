// Engine/IPhoneWifiWatchdog.swift
// IPHONE-WIFI D7: declares a Wi-Fi lane's link dead when its running job completes no step for a window: 20 s while a
// service socket is open (that socket is then shut down, so a blocked receive returns end-of-file), 30 s in the
// lockdown phase (no fd exists; the call stays on its abandoned worker). It never closes or invalidates anything; the
// job's own defers stay the only close. After an expiry the sockets are cut by `stop()`, which the lane's `close()`
// calls once the detach is posted and its tickets are abandoned. Tests: `expired`, `window(watching:)` and `cut` in
// IPhoneWifiTests, the trip on a real phone in the live test V3b.
import Foundation

final class IPhoneWifiWatchdog: @unchecked Sendable {
    /// Seconds without a completed step while a service socket is open (D7; the D7 window rule may change it).
    static let serviceWindow: TimeInterval = 20
    /// Seconds without a completed lockdown step; above the 20.0 s healthy disk-usage stall (D7).
    static let lockdownWindow: TimeInterval = 30

    // @unchecked Sendable: `lock` and `queue` are immutable; every var below is read and written only under `lock`.
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.macdashboard.mobiledevice.watchdog", qos: .utility)
    private var onDead: (@Sendable () -> Void)?
    private var fds: Set<Int32> = []
    private var busy = false
    private var finished = false              // fired or stopped: never fires again, cuts every socket it is given
    private var lastProgress: UInt64 = 0      // DispatchTime uptime nanoseconds
    private var timer: DispatchSourceTimer?
    private var longestService: UInt64 = 0
    private var longestLockdown: UInt64 = 0

    /// Set once by the lane right after init.
    func setOnDead(_ f: @escaping @Sendable () -> Void) { lock.withLock { onDead = f } }

    /// Which window applies: the service one while a socket is watched.
    static func window(watching: Bool) -> TimeInterval { watching ? serviceWindow : lockdownWindow }

    /// The step has been silent for the whole window.
    static func expired(lastProgress: UInt64, now: UInt64, window: TimeInterval) -> Bool {
        now >= lastProgress && now - lastProgress >= UInt64(window * 1_000_000_000)
    }

    /// `SO_NOSIGPIPE` first: later framework writes on this socket fail with EPIPE instead of raising SIGPIPE, which
    /// the app does not ignore. `shutdown(SHUT_RDWR)` wakes a blocked `recv` with 0. Internal for tests.
    static func cut(_ fd: Int32) {
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = shutdown(fd, SHUT_RDWR)
    }

    /// Lane queue, right before a job runs. The 1 s check runs only while a job runs (no idle timer).
    func begin() {
        lock.withLock {
            guard !finished else { return }
            busy = true
            lastProgress = Self.now()
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
            t.setEventHandler { [weak self] in self?.check() }
            timer = t
            t.resume()
        }
    }

    /// Lane queue, after the job returned (an abandoned job that returns late makes this a no-op).
    func end() {
        lock.withLock {
            busy = false
            timer?.cancel()
            timer = nil
        }
    }

    /// The job, right after a service connection opened. Once fired or stopped, the socket is cut at once.
    func watch(_ fd: Int32) {
        lock.withLock {
            if finished { Self.cut(fd); return }
            note(Self.now())
            fds.insert(fd)
        }
    }

    /// The job, BEFORE anything can close `fd`. After this returns the watchdog never touches `fd` again.
    func unwatch(_ fd: Int32) {
        lock.withLock {
            guard fds.contains(fd) else { return }
            note(Self.now())
            fds.remove(fd)
        }
    }

    /// The job, after every completed step.
    func progress() {
        lock.withLock { if busy { note(Self.now()) } }
    }

    /// The lane closed: cut what is watched, never fire.
    func stop() {
        lock.withLock {
            finished = true
            for fd in fds { Self.cut(fd) }
            timer?.cancel()
            timer = nil
        }
    }

    /// Live test (D7 window rule): the longest silences since the last call, in seconds, per phase. Clears them.
    func takeLongestGaps() -> (service: TimeInterval, lockdown: TimeInterval) {
        lock.withLock {
            defer { longestService = 0; longestLockdown = 0 }
            return (TimeInterval(longestService) / 1_000_000_000, TimeInterval(longestLockdown) / 1_000_000_000)
        }
    }

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// Caller holds `lock`: records the silence that just ended in the current phase and restarts the clock.
    private func note(_ now: UInt64) {
        if now > lastProgress {
            let gap = now - lastProgress
            if fds.isEmpty { longestLockdown = max(longestLockdown, gap) } else { longestService = max(longestService, gap) }
        }
        lastProgress = now
    }

    private func check() {
        let fire: (@Sendable () -> Void)? = lock.withLock {
            guard busy, !finished,
                  Self.expired(lastProgress: lastProgress, now: Self.now(), window: Self.window(watching: !fds.isEmpty))
            else { return nil }
            finished = true
            timer?.cancel()
            timer = nil
            return onDead
        }
        // Outside the lock. No cut here: `laneDied` posts the detach, the lane's `close()` abandons its tickets and then
        // calls `stop()`, which cuts the watched sockets. So the detach and the abandon reach main before any result of
        // the woken job. A `watch()` after this point still cuts at once (`finished`).
        fire?()
    }
}
