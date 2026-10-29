// Engine/TimeSource.swift
// ARCH-MODEL-SPLIT: the clock and the sleep every coordinator/controller loop uses, so a default-run test can
// drive a 15 s bound in microseconds. `.live` is the wall clock; tests build one over a virtual clock.
import Foundation

struct TimeSource {
    var now: @MainActor () -> Date
    /// Returns at once in a cancelled Task; every loop over it must check `Task.isCancelled`.
    var sleep: @MainActor (Duration) async -> Void

    static let live = TimeSource(
        now: { Date() },
        sleep: { duration in _ = try? await Task.sleep(for: duration) })
}
