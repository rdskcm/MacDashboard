// Engine/DiskReadSchedule.swift
// IDLE-WORK-TRIM: when the fast tick re-reads free space. The read (`LiveCollector.readDisk()`, one IOKit round trip of
// about 15 ms) ran on every 2 s tick for a value whose visible consumers are a threshold (header pill) and GB figures;
// now it runs every `interval` and at once after the app itself changed free space (`requestRead()`).
import Foundation

struct DiskReadSchedule: Equatable {
    /// Scheduled cadence while visible. 30 s: the figures shown are decimal GB with one decimal, and a forced read
    /// covers every change the app causes; the hidden 60 s tick reads on its own.
    static let interval: TimeInterval = 30

    private(set) var lastReadAt: Date? = nil
    /// Set by `requestRead()`; the first tick reads.
    private(set) var forced = true

    /// The next `shouldRead` answers true: snapshot deletion, Trash emptied, volume mount/unmount, gate resume.
    mutating func requestRead() { forced = true }

    /// One answer per tick. `true` records the read at `now`; the caller then reads. A clock that moved backwards
    /// (negative elapsed) counts as due, so a clock change can never silence the read.
    mutating func shouldRead(now: Date) -> Bool {
        var due = forced
        if let last = lastReadAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < 0 || elapsed >= Self.interval { due = true }
        } else {
            due = true
        }
        guard due else { return false }
        forced = false
        lastReadAt = now
        return true
    }
}
