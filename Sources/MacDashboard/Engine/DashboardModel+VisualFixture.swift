// Engine/DashboardModel+VisualFixture.swift
// VISUAL-COVERAGE: applies the fixed VisualFixture dataset to a fresh
// DashboardModel instead of starting live collection. App-only (not symlinked
// into Checks — DashboardModel is @MainActor/@Observable, out of scope there).

import Foundation

extension DashboardModel {
    /// Fills every field the live loop would normally produce, from the fixed
    /// fixture dataset, and starts no background task.
    func applyVisualFixture() {
        let d = VisualFixture.make()
        load = d.load
        cpu = d.cpu
        mem = d.mem
        swap = d.swap
        disk = d.disk
        battery = d.battery
        socTempC = d.socTempC
        topCPU = d.topCPU
        topMem = d.topMem
        cpuHistory = d.cpuHistory
        report = d.report
        assessment = d.assessment
        history = d.history
        reportText = d.reportText
        reportUpdatedAt = VisualFixture.referenceDate
        smartUpdatedAt = VisualFixture.referenceDate
        lastSampleAt = VisualFixture.referenceDate
        isCollectingReport = false
    }
}
