// Engine/PerfSignposts.swift
// PERF-SIGNPOSTS: names the app's own work in Instruments traces. One OSSignposter in category Points of Interest —
// the category the night templates (SwiftUI, Time Profiler) record. Interval names: `<scope>.<element>[.<step>]`,
// lowercase; <scope> is a `Page` raw value for work that runs only while that page is shown, or `app` for work that
// runs on every page (PAGE-BUDGETS groups by it). Marks only: no state, no timers, no tasks, no thread change.
// Off the recording path a begin/end is an enabled check plus an ID; no message is formatted.
import os

enum PerfSignposts {
    /// Fixed, brand-neutral subsystem: the same in the installed app and in the night bench copy (own bundle id).
    static let signposter = OSSignposter(subsystem: "com.rdskcm.perf", category: .pointsOfInterest)

    // MARK: app — runs whatever page is shown
    static let liveFastRead: StaticString = "app.live.fast.read"
    static let liveFastApply: StaticString = "app.live.fast.apply"
    static let liveFastAssess: StaticString = "app.live.fast.assess"
    static let liveSlowProcs: StaticString = "app.live.slow.procs"
    static let liveSlowWake: StaticString = "app.live.slow.wake"
    static let liveSlowApply: StaticString = "app.live.slow.apply"
    static let reportPass: StaticString = "app.report.pass"
    static let reportSection: StaticString = "app.report.section"
    static let reportCommit: StaticString = "app.report.commit"
    static let smartCollect: StaticString = "app.smart.collect"
    static let smartLand: StaticString = "app.smart.land"
    static let foldersCount: StaticString = "app.folders.count"
    /// Event, message = the page's raw value.
    static let navShow: StaticString = "app.nav.show"

    // MARK: pages — run only while that page is shown
    static let homeInput: StaticString = "home.input"
    static let homeTiles: StaticString = "home.tiles"
    static let cpuMake: StaticString = "cpu.make"
    static let cpuSocRead: StaticString = "cpu.soc.read"
    static let cpuSocPublish: StaticString = "cpu.soc.publish"
    static let cpuChartSeries: StaticString = "cpu.chart.series"
    static let cpuChartTip: StaticString = "cpu.chart.tip"
    static let memoryMake: StaticString = "memory.make"
    static let batteryMake: StaticString = "battery.make"
    static let batteryRead: StaticString = "battery.read"
    static let securityMake: StaticString = "security.make"
    static let backupsMake: StaticString = "backups.make"
    static let systemMake: StaticString = "system.make"
    static let historyMake: StaticString = "history.make"
    static let historyChartTip: StaticString = "history.chart.tip"

    /// Begins an interval with its own ID (intervals of one name may overlap). End it with `end()` on the token, on the
    /// same thread or after an `await`.
    static func begin(_ name: StaticString) -> PerfInterval {
        PerfInterval(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()))
    }

    /// `app.nav.show`: which page the main window now shows. The message is built only while a tool records.
    static func pageShown(_ page: Page) {
        signposter.emitEvent(navShow, "\(page.rawValue, privacy: .public)")
    }
}

/// One open interval. Value type, no shared state.
struct PerfInterval {
    let name: StaticString
    let state: OSSignpostIntervalState

    func end() { PerfSignposts.signposter.endInterval(name, state) }
}
