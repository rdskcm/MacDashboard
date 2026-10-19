// Engine/DashboardModel+VisualFixture.swift
// VISUAL-COVERAGE: applies the fixed VisualFixture dataset to a fresh
// DashboardModel instead of starting live collection. App-only (not covered by
// Tests/MacDashboardTests — DashboardModel is @MainActor/@Observable, out of scope there).

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
        claudeBackup = d.claudeBackup
        fixtureNow = VisualFixture.referenceDate
        reportUpdatedAt = VisualFixture.referenceDate
        smartUpdatedAt = VisualFixture.referenceDate
        lastSampleAt = VisualFixture.referenceDate
        isCollectingReport = false
        // REDESIGN-HOME: Home's CPU tile «Processes» and the scan state («checked at 10:30»).
        processCount = 412
        applyFixturePressure(.normal)
        applyFixtureScan({
            var s = BlockState(.scan, createdAt: VisualFixture.referenceDate)
            s.begin(at: VisualFixture.referenceDate.addingTimeInterval(-20), showsLoading: false)
            s.succeed(at: VisualFixture.referenceDate)
            return s
        }())
        // REDESIGN-CPU: an ok CPU block, so the CPU page renders live values in the fixture.
        let ref = VisualFixture.referenceDate
        applyFixtureCPU({
            var s = BlockState(.cpu, createdAt: ref.addingTimeInterval(-4))
            s.begin(at: ref.addingTimeInterval(-2), showsLoading: false)
            s.succeed(at: ref)
            return s
        }(), highSince: nil)
        // REDESIGN-STORAGE: smartmontools present (the SMART card shows its tiles) and an ok folder-count block.
        applyFixtureSmartTools(.installed, installing: false, failure: nil)
        applyFixtureFolders(VisualFixture.folderSizes(), block: {
            var s = BlockState(.folders, createdAt: ref.addingTimeInterval(-14))
            s.begin(at: ref.addingTimeInterval(-12), showsLoading: false)
            s.succeed(at: ref)
            return s
        }())
        // REDESIGN-MEMORY: an ok memory block, so the Memory page renders live values in the fixture.
        applyFixtureMemory({
            var s = BlockState(.memory, createdAt: ref.addingTimeInterval(-4))
            s.begin(at: ref.addingTimeInterval(-2), showsLoading: false)
            s.succeed(at: ref)
            return s
        }())
    }
}
