// Tests/MacDashboardTests/SmartToolsControllerTests.swift
// ARCH-MODEL-SPLIT block 5: the SMART sampler, the re-check and the smartmontools install through injected closures —
// no diskutil, no smartctl, no brew, no coordinator. Host and clock fakes: ControllerTestSupport.swift.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeSmart {
    static let exit0 = CommandOutcome(termination: .exited(0), stdout: "", stdoutTruncated: false, stderrHead: "")
    static func ended(_ t: CommandOutcome.Termination) -> CommandOutcome {
        CommandOutcome(termination: t, stdout: "", stdoutTruncated: false, stderrHead: "")
    }

    var disks = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: "VERIFIED")]
    var tmDest: TMDestination?? = .some(nil)
    var smartctl: String? = nil
    var brew: String? = "/opt/homebrew/bin/brew"
    var installResult = FakeSmart.exit0
    /// Where smartctl appears after an install that exited 0.
    var smartctlAfterInstall = "/opt/homebrew/bin/smartctl"
    /// When set, `collect` / `install` park until released (not cancellation-aware, like a running process).
    var holdCollect = false
    var holdInstall = false
    private(set) var collectCalls = 0
    private(set) var installs: [String] = []
    private(set) var recorded: [TMDestination??] = []
    private(set) var installParked = false
    private var collectGates: [CheckedContinuation<Void, Never>] = []
    private var installGate: CheckedContinuation<Void, Never>?

    func releaseCollect() { for g in collectGates { g.resume() }; collectGates = [] }
    func releaseInstall() { installGate?.resume(); installGate = nil }

    var deps: SmartToolsController.Dependencies {
        SmartToolsController.Dependencies(
            collect: {
                self.collectCalls += 1
                if self.holdCollect { await withCheckedContinuation { self.collectGates.append($0) } }
                return (self.disks, self.tmDest)
            },
            install: { brew in
                self.installs.append(brew)
                if self.holdInstall { await withCheckedContinuation { self.installGate = $0; self.installParked = true } }
                if self.installResult.termination == .exited(0) { self.smartctl = self.smartctlAfterInstall }
                return self.installResult
            },
            findSmartctl: { self.smartctl },
            findBrew: { self.brew },
            markTMUpdated: { self.recorded.append($0) })
    }
}

extension SerialTests {
    @MainActor struct SmartToolsControllerTests {
        /// Default fake: brew present, smartctl missing → `.installable`.
        private func make() -> (SmartToolsController, FakeHost, FakeSmart, VirtualClock) {
            let host = FakeHost(), fake = FakeSmart(), clock = VirtualClock()
            return (SmartToolsController(host: host.host, time: clock.source, deps: fake.deps), host, fake, clock)
        }

        // 1 (R5)
        @Test func toolsStateFollowsTheProbesAndMarkUpdatedUsesTheClock() async {
            let host = FakeHost(), fake = FakeSmart(), clock = VirtualClock()
            fake.brew = nil
            let c = SmartToolsController(host: host.host, time: clock.source, deps: fake.deps)
            #expect(c.toolsState == .needsHomebrew)
            fake.brew = "/opt/homebrew/bin/brew"; c.recomputeToolsState()
            #expect(c.toolsState == .installable)
            fake.smartctl = "/opt/homebrew/bin/smartctl"; c.recomputeToolsState()
            #expect(c.toolsState == .installed)
            await clock.source.sleep(.seconds(60))
            c.markUpdated()
            #expect(c.updatedAt == clock.now && host.updateCalls == 0)
        }
        // 2 (R3, R7): sleeps 300 s first, then lands one read after the pass and stamps
        @Test func samplerSleepsFirstThenWritesAfterThePassAndStamps() async {
            let (c, host, fake, clock) = make()
            clock.onSleep = { n in if n == 2 { c.stop() } }
            c.startSampling()
            let sampler = c.samplerTask
            await sampler?.value
            #expect(clock.sleeps == [.seconds(300), .seconds(300)])
            #expect(fake.collectCalls == 1 && host.awaitCalls == 1 && host.updateCalls == 1)
            #expect(host.report.smart == fake.disks && fake.recorded == [.some(nil)])
            #expect(host.claudeRefreshCalls == 1 && host.reassessCalls == 0)
            #expect(c.updatedAt == clock.base.addingTimeInterval(300) && c.samplerTask == nil)
        }
        // 3 (R3, R12): paused → nothing spawns; 2 s, then the full interval again
        @Test func samplerSpawnsNothingWhilePaused() async {
            let (c, host, fake, clock) = make()
            host.paused = true
            clock.onSleep = { n in if n == 4 { c.stop() } }
            c.startSampling()
            let sampler = c.samplerTask
            await sampler?.value
            #expect(fake.collectCalls == 0 && fake.recorded.isEmpty && c.updatedAt == nil)
            #expect(clock.sleeps == [.seconds(300), .seconds(2), .seconds(300), .seconds(2)])
        }
        // 4 (R3): an unchanged SMART read costs no report mutation; the TM record and the stamp still happen
        @Test func samplerWritesOnlyAChangedSmartSection() async {
            let (c, host, fake, clock) = make()
            host.report.smart = fake.disks
            clock.onSleep = { n in if n == 2 { c.stop() } }
            c.startSampling()
            let sampler = c.samplerTask
            await sampler?.value
            #expect(host.updateCalls == 0 && fake.recorded.count == 1 && c.updatedAt != nil)
        }
        // 5 (R6, D11)
        @Test func startSamplingReplacesTheRunningSampler() async {
            let (c, _, _, _) = make()
            c.startSampling(); let first = c.samplerTask
            c.startSampling(); let second = c.samplerTask
            #expect(first?.isCancelled == true && second != nil && second != first)
            c.stop()
            await first?.value; await second?.value
            #expect(second?.isCancelled == true && c.samplerTask == nil)
        }
        // 6 (R4)
        @Test func refreshNowLandsAfterThePassAndIsIgnoredWhileRefreshing() async {
            let (c, host, fake, clock) = make()
            fake.holdCollect = true
            c.refreshNow()
            await settle { fake.collectCalls == 1 }
            c.refreshNow()
            fake.releaseCollect(); await c.refreshTask?.value
            #expect(fake.collectCalls == 1 && host.awaitCalls == 1 && host.report.smart == fake.disks)
            #expect(fake.recorded == [.some(nil)] && host.claudeRefreshCalls == 1 && host.reassessCalls == 0)
            #expect(c.updatedAt == clock.now)
        }
        // 7 (R4)
        @Test func installSuccessFlipsToInstalledAndRechecksSmart() async {
            let (c, host, fake, _) = make()
            #expect(c.toolsState == .installable)
            c.installNow()
            #expect(c.installing)
            await c.installTask?.value
            await c.refreshTask?.value
            #expect(fake.installs == ["/opt/homebrew/bin/brew"] && c.toolsState == .installed)
            #expect(c.installFailure == nil && !c.installing && fake.collectCalls == 1 && host.report.smart == fake.disks)
        }
        // 8 (R4)
        @Test func installFailureIsTypedByTermination() async {
            let (c, _, fake, _) = make()
            let cases: [(CommandOutcome.Termination, SmartInstallFailure)] = [
                (.exited(1), .exitCode(1)), (.timedOut, .timedOut), (.signaled(9), .exitCode(-1)),
                (.launchFailed(2), .exitCode(-1)), (.cancelled, .exitCode(-1))]
            for (termination, failure) in cases {
                fake.installResult = FakeSmart.ended(termination)
                c.installNow(); await c.installTask?.value
                #expect(c.installFailure == failure && c.toolsState == .installable && !c.installing)
            }
            #expect(fake.installs.count == 5 && fake.collectCalls == 0)
        }
        // 9 (R4): success is "smartctl found afterwards", whatever brew's exit status
        @Test func installCountsAsSuccessWheneverSmartctlIsFoundAfterwards() async {
            let (c, _, fake, _) = make()
            fake.installResult = FakeSmart.ended(.exited(1))
            c.installNow()
            fake.smartctl = "/opt/homebrew/bin/smartctl"              // e.g. installed by hand meanwhile
            await c.installTask?.value; await c.refreshTask?.value
            #expect(c.toolsState == .installed && c.installFailure == nil && fake.collectCalls == 1)
        }
        // 10 (R4)
        @Test func installWithoutBrewFailsWithNoBrewAndRunsNothing() async {
            let (c, _, fake, _) = make()
            fake.brew = nil
            c.installNow(); await c.installTask?.value
            #expect(c.installFailure == .noBrew && fake.installs.isEmpty && !c.installing)
        }
        // 11 (R4)
        @Test func installClearsTheLastFailureAndIsIgnoredWhileInstalling() async {
            let (c, _, fake, _) = make()
            c.applyFixture(updatedAt: nil, tools: .installable, installing: false, failure: .exitCode(1))
            fake.holdInstall = true
            c.installNow()
            #expect(c.installing && c.installFailure == nil)
            await settle { fake.installParked }
            c.installNow()
            fake.releaseInstall(); await c.installTask?.value; await c.refreshTask?.value
            #expect(fake.installs.count == 1 && c.toolsState == .installed && !c.installing)
        }
        // 12 (R6): stop() cancels all three; none writes anything afterwards; the guards are released
        @Test func stopCancelsTheSamplerTheRecheckAndTheInstallAndNothingIsWritten() async {
            let (c, host, fake, _) = make()
            fake.holdCollect = true; fake.holdInstall = true
            fake.installResult = FakeSmart.ended(.exited(1))
            c.startSampling(); c.refreshNow(); c.installNow()
            await settle { fake.collectCalls == 2 && fake.installParked }
            let tasks = [c.samplerTask, c.refreshTask, c.installTask]
            c.stop()
            #expect(c.samplerTask == nil && c.refreshTask == nil && c.installTask == nil)
            #expect(tasks.allSatisfy { $0?.isCancelled == true })
            fake.releaseCollect(); fake.releaseInstall()
            for t in tasks { await t?.value }
            #expect(host.awaitCalls == 0 && host.updateCalls == 0 && host.claudeRefreshCalls == 0 && fake.recorded.isEmpty)
            #expect(c.updatedAt == nil && c.installFailure == nil && !c.installing && c.toolsState == .installable)
            #expect(fake.collectCalls == 2)                            // the cancelled sampler did not loop again
            fake.holdCollect = false
            c.refreshNow(); await c.refreshTask?.value                 // the re-check guard was released
            #expect(fake.collectCalls == 3 && host.updateCalls == 1)
        }
        // 13 (R8)
        @Test func applyFixtureSetsAllFourFields() {
            let (c, _, _, clock) = make()
            c.applyFixture(updatedAt: clock.now, tools: .needsHomebrew, installing: true, failure: .timedOut)
            #expect(c.updatedAt == clock.now && c.toolsState == .needsHomebrew && c.installing && c.installFailure == .timedOut)
        }
        // 14 (R11) Opt-in: MACDASH_LIVE=1 swift test --filter liveCanarySmartTools
        // Runs the production probes and the SMART + TM read on this Mac. Reads only: never runs `brew install`.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanarySmartTools() async {
            let live = SmartToolsController.Dependencies.live(markTMUpdated: { _ in })
            let smartctl = live.findSmartctl(), brew = live.findBrew()
            print("liveCanary smartctl=\(smartctl ?? "-") brew=\(brew ?? "-")")
            if let smartctl {                                          // the found path is a working smartctl
                let v = await CommandRunner.run(smartctl, ["--version"], timeout: 15)
                print("liveCanary smartctl --version: \(v.stdout.split(separator: "\n").first.map(String.init) ?? "-")")
                #expect(v.termination == .exited(0) && v.stdout.hasPrefix("smartctl"))
            }
            if let brew {                                              // the found path is a working brew
                let env = CommandRunner.environment(prependingPATH: [(brew as NSString).deletingLastPathComponent])
                let v = await CommandRunner.run(brew, ["--version"], timeout: 30, environment: env)
                print("liveCanary brew --version: \(v.stdout.split(separator: "\n").first.map(String.init) ?? "-")")
                #expect(v.termination == .exited(0) && v.stdout.hasPrefix("Homebrew"))
            }
            // Independent reading: Homebrew's own smartctl locations on Apple Silicon.
            let onDisk = ["/opt/homebrew/sbin/smartctl", "/opt/homebrew/bin/smartctl"]
                .contains { FileManager.default.isExecutableFile(atPath: $0) }
            if onDisk { #expect(smartctl != nil) }
            let c = SmartToolsController(host: FakeHost().host, time: .live, deps: live)
            print("liveCanary toolsState=\(c.toolsState) onDisk=\(onDisk)")
            #expect(c.toolsState == ReportCollector.smartToolsAvailability(smartctl: smartctl, brew: brew))
            let (disks, tmDest) = await live.collect()
            print("liveCanary disks=\(disks.map { "\($0.device)|\($0.title)|\($0.status)|\($0.severity)" }) tmDest=\(String(describing: tmDest))")
            let internalDisk = disks.first { $0.device == "internal" }
            #expect(internalDisk != nil)                               // diskutil info disk0 answers on every Mac
            #expect(tmDest != nil)                                     // destinationinfo answered (.some(nil) = none configured)
            // Independent reading: diskutil's own SMART line for disk0 agrees with the parsed severity.
            let du = await CommandRunner.run("/usr/sbin/diskutil", ["info", "disk0"], timeout: 15)
            let smartLine = du.stdout.split(separator: "\n").first { $0.contains("SMART Status:") }.map(String.init) ?? "-"
            print("liveCanary diskutil: \(smartLine.trimmingCharacters(in: .whitespaces))")
            #expect(du.termination == .exited(0))
            if smartLine.lowercased().contains("verified") { #expect(internalDisk?.severity == .good) }
        }
    }
}
