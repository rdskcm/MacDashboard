// Engine/AppModel+VisualFixture.swift
// VISUAL-COVERAGE: applies the fixed VisualFixture dataset to a fresh
// AppModel instead of starting live collection. App-only (not covered by
// Tests/MoonportTests — AppModel is @MainActor/@Observable, out of scope there).

import Foundation

extension AppModel {
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
        gpuUtil = VisualFixture.gpuUnavailableRequested ? nil : d.gpuUtil
        topCPU = d.topCPU
        topMem = d.topMem
        cpuHistory = d.cpuHistory
        // SOC-DETAILS: GPU history of the same 61 instants and the reference page-tick state (the page's `.task` must
        // not overwrite it: `applyFixture` locks the sampler).
        gpuHistory = d.gpuHistory.map { ($0.0, VisualFixture.gpuUnavailableRequested ? nil : $0.1) }
        socLive.applyFixture(d.socLive)
        report = d.report
        assessment = d.assessment
        history.applyFixture(d.history)
        reportText = d.reportText
        claudeBackup = d.claudeBackup
        claudeRun.applyFixture(job: d.claudeJob, attempt: d.claudeAttempt, diskConnected: true, action: .idle, size: d.claudeSize)
        fixtureNow = VisualFixture.referenceDate
        reportUpdatedAt = VisualFixture.referenceDate
        lastSampleAt = VisualFixture.referenceDate
        isCollectingReport = false
        // REDESIGN-HOME: Home's CPU tile «Processes» and the scan state («checked at 10:30»).
        processCount = 412
        applyFixturePressure(.normal)
        applyFixtureThermal(.nominal)
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
        smart.applyFixture(updatedAt: ref, tools: .installed, installing: false, failure: nil)
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
        // REDESIGN-BATTERY: an ok battery block + the fixture detail, so the Battery page renders live values.
        applyFixtureBattery(VisualFixture.batteryDetail, block: {
            var s = BlockState(.battery, createdAt: ref.addingTimeInterval(-4))
            s.begin(at: ref.addingTimeInterval(-3), showsLoading: false)
            s.succeed(at: ref)
            return s
        }())
        // REDESIGN-SYSTEM: the System page — one user holder + one system holder (sampled), brew checked just now,
        // startup list never checked, no energy apply in flight.
        applyFixtureWakeHolders(user: [WakeHolder(owner: "caffeinate", requester: "Terminal", ageSeconds: 5400)],
                                system: VisualFixture.systemWakeHolders, sampled: true)
        brew.applyFixture(checkedAt: ref, upgrading: false, progress: nil, error: nil, notice: nil, stoppable: false)
        startupItems.applyFixture(checkedAt: nil, removed: 0, checking: false, deleting: [], failure: nil)
        energy.applyFixture(.idle)
        // REDESIGN-BACKUPS: destination collected at the reference time, no poll sample, no action in flight.
        timeMachine.applyFixture(updatedAt: ref, backup: nil, action: .idle)
        // SOC-DETAILS: launch-argument variants of the SoC page (`-fixtureCores`, `-fixtureTemp`, ...).
        let socOptions = VisualFixture.SocFixtureOptions.fromLaunchArguments()
        if socOptions != VisualFixture.SocFixtureOptions() { applySocFixture(socOptions) }
        // REDESIGN-INFO-RESTORE: `-fixtureTM` / `-fixtureSecurity` variants of the Backups and Security pages.
        let edge = VisualFixture.EdgeOptions.fromLaunchArguments()
        if let d = VisualFixture.edgeTMDestination(edge.tm) { report.tmDest = .some(d) }
        if edge.security == .mixed { report.security = VisualFixture.mixedSecurity }
    }

    /// SOC-DETAILS §2.7: one SoC page variant on top of the reference fixture (`applyVisualFixture` first). Each option
    /// maps to a `socLive.applyFixture`, `applyFixtureCPU` or `applyFixtureThermal` call, so the launch arguments and
    /// the snapshot suite (`fixtureHome { $0.applySocFixture(...) }`) set the same state.
    func applySocFixture(_ o: VisualFixture.SocFixtureOptions) {
        let ref = VisualFixture.referenceDate
        socTempC = VisualFixture.socTempC(o, reference: socTempC)
        applyFixtureThermal(VisualFixture.thermal(o))
        load = VisualFixture.loadAverage(o, reference: load ?? [])
        switch o.cpu {
        case .reference: break
        case .high:
            cpu = CPUUsage(user: 78.6, sys: 12.6, idle: 8.8)
            applyFixtureCPU(Self.fixtureCPUBlock(failed: false), highSince: ref.addingTimeInterval(-190))
        case .failed:
            applyFixtureCPU(Self.fixtureCPUBlock(failed: true), highSince: nil)
        case .notYet:
            applyFixtureCPU(BlockState(.cpu, createdAt: ref), highSince: nil)
        }
        let history = VisualFixture.socHistory(o, cpu: cpuHistory, gpu: gpuHistory)
        cpuHistory = history.cpu
        gpuHistory = history.gpu
        socLive.applyFixture(VisualFixture.socLive(o))
    }

    /// A CPU block that answered at the reference time, or one that failed 8 s later than its last good reading
    /// (the mockup's "last data 10:29:52").
    private static func fixtureCPUBlock(failed: Bool) -> BlockState {
        let ref = VisualFixture.referenceDate
        var s = BlockState(.cpu, createdAt: ref.addingTimeInterval(-60))
        s.begin(at: ref.addingTimeInterval(failed ? -40 : -2), showsLoading: false)
        s.succeed(at: ref.addingTimeInterval(failed ? -8 : 0))
        if failed {
            s.begin(at: ref.addingTimeInterval(-5), showsLoading: true)
            s.fail(.noReading)
        }
        return s
    }
}
