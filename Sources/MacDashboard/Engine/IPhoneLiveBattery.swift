// Engine/IPhoneLiveBattery.swift
// IPHONE-LIVE-BATTERY: the battery card's 10 s refresh — when the loop may run, how long it waits, what a read writes to history.
// Pure decisions; IPhoneModel owns the loop (specs/IPHONE-LIVE-BATTERY.md D1-D12).
import Foundation
import os

enum IPhoneLiveBattery {
    /// Seconds between the end of one battery reading and the next live read (user decision 2026-11-11).
    static let interval: TimeInterval = 10

    /// Debug-level outcome lines for counting reads (`log stream --level debug`); no identifier, no value (D11).
    static let log = Logger(subsystem: "com.rdskcm.perf", category: "iphone.live")

    /// R2: the loop may exist only while the device page is mounted, the window is not paused, the transport reports the
    /// phone attached, a snapshot of it exists and automatic reading is on.
    static func shouldRun(pageShown: Bool, windowPaused: Bool, attached: Bool, hasSnapshot: Bool, autoRead: Bool) -> Bool {
        pageShown && !windowPaused && attached && hasSnapshot && autoRead
    }

    /// Seconds to wait before the next live read; 0 = read now. A read already queued or running waits a full interval
    /// (R3); a reading time in the future (clock set back) waits at most one interval.
    static func wait(lastChecked: Date?, now: Date, inFlight: Bool, interval: TimeInterval = interval) -> TimeInterval {
        if inFlight { return interval }
        guard let last = lastChecked else { return 0 }
        return min(interval, max(0, interval - now.timeIntervalSince(last)))
    }

    /// The day's history point a battery reading stores (moved verbatim from `IPhoneModel.apply`); nil when the reading has
    /// neither a health figure nor a cycle count.
    static func historyPoint(_ b: BatteryDetail, points: [BatteryPoint], now: Date) -> BatteryPoint? {
        guard b.healthPercent != nil || b.cycleCount != nil else { return nil }
        return BatteryPoint(day: IPhoneData.historyDay(now),
                            cycles: b.cycleCount,
                            healthPercent: IPhoneData.historyHealthPercent(b, points: points),
                            maxCapacityMAh: b.maxCapacityMAh,
                            designCapacityMAh: b.designCapacityMAh,
                            source: "live")
    }

    /// R4: the history after a live reading, or nil when it would not change (then nothing is saved).
    static func updatedHistory(_ points: [BatteryPoint], battery b: BatteryDetail, now: Date) -> [BatteryPoint]? {
        guard let p = historyPoint(b, points: points, now: now) else { return nil }
        let updated = IPhoneData.upsertLive(points, p)
        return updated == points ? nil : updated
    }
}
