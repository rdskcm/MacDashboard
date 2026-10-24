// Tests/MacDashboardTests/ContentSnapshotTests.swift
// HARNESS-REDESIGN-RETARGET: offscreen content states (dark + light) rendered from the fixed VisualFixture dataset.
// Runs only through tools/visual/snapshots.sh (MACDASH_SNAPSHOTS set); a plain `swift test` skips it.
// Add one `run.snap` per new visible state (Live constraint "Visual fixture coverage").

import AppKit
import SwiftUI
import Testing
@testable import MacDashboard


extension SerialTests {
    @Suite(.enabled(if: SnapshotEnv.outDir != nil, "set MACDASH_SNAPSHOTS: run tools/visual/snapshots.sh"))
    struct SnapshotTests {
        @Test @MainActor func contentStates() throws {
            let outDir = try #require(SnapshotEnv.outDir)
            // D7: never against the real home (DashboardModel() reads the history file at init).
            let realHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? ""
            try #require(!realHome.isEmpty && NSHomeDirectory() != realHome,
                         "run through tools/visual/snapshots.sh (CFFIXED_USER_HOME bench home)")
            VisualFixture.forced = true
            defer { VisualFixture.forced = false }
            // D8: Settings panes render with AppSettings at their unset defaults.
            let settings = AppSettings.shared
            let saved = (settings.fastIntervalSeconds, settings.ignoredWakeHolderEntries, settings.backupStaleDays, settings.lowSpacePercent, settings.appearance, settings.orbsEnabled, settings.snapshotMinutes, settings.claudeLogPath)
            settings.fastIntervalSeconds = AppSettings.resolveFastInterval(raw: 0)
            settings.ignoredWakeHolderEntries = []
            settings.backupStaleDays = AppSettings.defaultBackupStaleDays
            settings.lowSpacePercent = AppSettings.defaultLowSpacePercent
            settings.appearance = .system
            settings.orbsEnabled = true
            settings.snapshotMinutes = AppSettings.defaultSnapshotMinutes
            settings.claudeLogPath = nil
            defer { (settings.fastIntervalSeconds, settings.ignoredWakeHolderEntries, settings.backupStaleDays, settings.lowSpacePercent, settings.appearance, settings.orbsEnabled, settings.snapshotMinutes, settings.claudeLogPath) = saved }
            L10nStore.shared.language = .en
            let run = try SnapshotRun(out: outDir)
            let m = DashboardModel()
            m.applyVisualFixture()

            let ipStore = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-visual-iphone-\(ProcessInfo.processInfo.processIdentifier)")
                .appendingPathComponent("iphones.json")
            @MainActor func fixtureIPhone(_ tweak: (IPhoneModel) -> Void = { _ in }) -> IPhoneModel {
                let m = IPhoneModel(store: IPhoneStore(url: ipStore))
                m.applyVisualFixture()
                tweak(m)
                return m
            }
            let ivan = IPhoneModel.fixtureIvanKey
            let vic = IPhoneModel.fixtureVictoriaKey
            let longArchive = "sysdiagnose_2026.01.15_09-15-02+0300_iPhone-OS_iPhone_23E254.tar.gz"
            // NEWMAC-HISTORY-EMPTY: the same fixture with only `history` replaced. One model per
            // state, because a view reads `model.history` when it renders, not when the closure is
            // built. `DashboardModel()` only reads the real history file at init; nothing is written.
            @MainActor func fixtureHistory(_ entries: [MacHistoryEntry], backup: String? = nil) -> DashboardModel {
                let h = DashboardModel()
                h.applyVisualFixture()
                h.history = HistoryState(last_run: entries.last?.date, mac_history: entries, unreadable_backup: backup)
                h.fixtureNow = VisualFixture.referenceDate   // History year labels must not follow the wall clock
                return h
            }
            // REDESIGN-HOME: the same fixture with one thing changed per Home state (one model per state).
            @MainActor func fixtureHome(_ tweak: (DashboardModel) -> Void) -> DashboardModel {
                let h = DashboardModel()
                h.applyVisualFixture()
                tweak(h)
                return h
            }
            let homeRef = VisualFixture.referenceDate
            let homeFirstScan = BlockState(.scan, createdAt: homeRef)
            /// Scan that answered at 09:12 (ref − 78 min), then a user-pressed pass that timed out.
            let homeFailedScan: BlockState = {
                var s = BlockState(.scan, createdAt: homeRef.addingTimeInterval(-3600 * 2))
                s.begin(at: homeRef.addingTimeInterval(-80 * 60), showsLoading: false)
                s.succeed(at: homeRef.addingTimeInterval(-78 * 60))
                s.begin(at: homeRef.addingTimeInterval(-31), showsLoading: true)
                s.fail(.timedOut)
                return s
            }()
            // REDESIGN-CPU: CPU page states (ok / failed with a last good reading / first sample pending).
            let cpuOK: BlockState = {
                var s = BlockState(.cpu, createdAt: homeRef.addingTimeInterval(-4))
                s.begin(at: homeRef.addingTimeInterval(-2), showsLoading: false)
                s.succeed(at: homeRef)
                return s
            }()
            let cpuFailed: BlockState = {
                var s = BlockState(.cpu, createdAt: homeRef.addingTimeInterval(-60))
                s.begin(at: homeRef.addingTimeInterval(-40), showsLoading: false)
                s.succeed(at: homeRef.addingTimeInterval(-38))
                s.begin(at: homeRef.addingTimeInterval(-5), showsLoading: true)
                s.fail(.timedOut)
                return s
            }()
            let cpuHigh = fixtureHome {
                $0.cpu = CPUUsage(user: 71, sys: 20, idle: 9)
                $0.socTempC = 93
                $0.applyFixtureCPU(cpuOK, highSince: homeRef.addingTimeInterval(-4 * 60))
            }
            // HOME-LEFTOVERS: cpuHigh's 93 °C is now the warm SoC state (CPULoad.socLevel); cpuHot keeps the hot tile covered.
            let cpuHot = fixtureHome {
                $0.cpu = CPUUsage(user: 71, sys: 20, idle: 9)
                $0.socTempC = 97
                $0.applyFixtureCPU(cpuOK, highSince: homeRef.addingTimeInterval(-4 * 60))
            }
            let cpuFail = fixtureHome { $0.applyFixtureCPU(cpuFailed, highSince: nil) }
            let cpuLoading = fixtureHome { $0.applyFixtureCPU(BlockState(.cpu, createdAt: homeRef), highSince: nil) }
            // REDESIGN-MEMORY: Memory page states (fixture = low pressure, swap 25 %).
            let memFailedBlock: BlockState = {
                var s = BlockState(.memory, createdAt: homeRef.addingTimeInterval(-60))
                s.begin(at: homeRef.addingTimeInterval(-40), showsLoading: false)
                s.succeed(at: homeRef.addingTimeInterval(-38))
                s.begin(at: homeRef.addingTimeInterval(-5), showsLoading: false)
                s.fail(.timedOut)
                return s
            }()
            let memMedium = fixtureHome {
                $0.applyFixturePressure(.warn)
                $0.swap = SwapInfo(total: 8 << 30, used: Int64(5.2 * Double(1 << 30)), free: (8 << 30) - Int64(5.2 * Double(1 << 30)))
            }
            let memHigh = fixtureHome { $0.applyFixturePressure(.critical) }
            let memUnknown = fixtureHome { $0.applyFixturePressure(nil) }
            let memFail = fixtureHome { $0.applyFixtureMemory(memFailedBlock) }
            let memLoading = fixtureHome { $0.applyFixtureMemory(BlockState(.memory, createdAt: homeRef)) }
            // REDESIGN-STORAGE: Storage page states. The fixture disk is 256 GB, 30 % free (ok); each state changes one thing.
            let stBlockOK: BlockState = {
                var s = BlockState(.folders, createdAt: homeRef.addingTimeInterval(-14))
                s.begin(at: homeRef.addingTimeInterval(-12), showsLoading: false)
                s.succeed(at: homeRef)
                return s
            }()
            @MainActor func storageDisk(freePercent: Double) -> DiskInfo {
                DiskInfo(size: 256_000_000_000, avail: Int64(2_560_000_000 * freePercent),
                         dataUsed: 160_000_000_000, sysUsed: 18_000_000_000, purgeable: 3_100_000_000)
            }
            @MainActor func reassess(_ h: DashboardModel) {
                h.assessment = Assess.assess(report: h.report,
                                             live: LiveSnapshot(t: homeRef, load: h.load, cpu: h.cpu, mem: h.mem,
                                                                swap: h.swap, disk: h.disk, battery: h.battery),
                                             memPressure: .normal, now: homeRef)
            }
            /// Folder count done, no home folder refused (the plain `ok` page).
            @MainActor func storageOK(_ tweak: (DashboardModel) -> Void = { _ in }) -> DashboardModel {
                fixtureHome {
                    $0.applyFixtureFolders(VisualFixture.folderSizes(unreadable: []), block: stBlockOK)
                    tweak($0)
                }
            }
            let stOK = storageOK()
            let stLow = storageOK { $0.disk = storageDisk(freePercent: 15) }
            let stCritical = storageOK { $0.disk = storageDisk(freePercent: 8) }
            let stNoDisk = storageOK { $0.disk = nil; $0.report.smart = nil }
            let stCounting = fixtureHome { $0.applyFixtureFolders(nil, block: BlockState(.folders, createdAt: homeRef)) }
            let stTimeout = fixtureHome {
                var s = BlockState(.folders, createdAt: homeRef.addingTimeInterval(-12))
                s.begin(at: homeRef.addingTimeInterval(-11), showsLoading: true)
                s.fail(.timedOut)
                $0.applyFixtureFolders(nil, block: s)
            }
            let stNoResult = fixtureHome {
                var s = BlockState(.folders, createdAt: homeRef.addingTimeInterval(-12))
                s.begin(at: homeRef.addingTimeInterval(-11), showsLoading: true)
                s.fail(.noReading)
                $0.applyFixtureFolders(nil, block: s)
            }
            let stFDA = storageOK { $0.applyFixtureFDA(denied: Array(ProtectedLocations.table.prefix(5))) }
            let stWornHealth: SmartHealth = {
                var h = VisualFixture.internalHealth
                h.percentageUsed = 82
                return h
            }()
            let stWorn = storageOK {
                $0.report.smart = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: "VERIFIED",
                                             attrs: [("Percentage Used", "82%")], health: stWornHealth)]
                reassess($0)
            }
            let stFailing = storageOK {
                $0.report.smart = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: "VERIFIED",
                                             health: VisualFixture.internalHealth), VisualFixture.externalFailingDisk]
                reassess($0)
            }
            /// smartmontools missing: no health anywhere, every drive «no data».
            @MainActor func storageTools(_ state: ReportCollector.SmartToolsAvailability, installing: Bool = false,
                                         failure: SmartInstallFailure? = nil) -> DashboardModel {
                storageOK {
                    $0.report.smartctlPresent = false
                    $0.report.smart = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: "VERIFIED"),
                                       SmartDisk(device: "/dev/disk4", title: "External SSD", status: "NO ACCESS")]
                    $0.applyFixtureSmartTools(state, installing: installing, failure: failure)
                }
            }
            let stInstallable = storageTools(.installable)
            let stInstalling = storageTools(.installable, installing: true)
            let stInstallFailed = storageTools(.installable, failure: .exitCode(1))
            let stNeedsBrew = storageTools(.needsHomebrew)
            /// smartctl present, the external bridge passes nothing through.
            let stUnavailable = storageOK {
                $0.report.smart = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: "VERIFIED",
                                             health: VisualFixture.internalHealth),
                                   SmartDisk(device: "/dev/disk4", title: "External SSD", status: "NO ACCESS")]
            }
            let stNoDisks = storageOK { $0.report.smart = [] }
            // REDESIGN-BATTERY: Battery page states. The fixture detail is charging + worn (76 %); each state changes one thing.
            let batOKBlock: BlockState = {
                var s = BlockState(.battery, createdAt: homeRef.addingTimeInterval(-4))
                s.begin(at: homeRef.addingTimeInterval(-3), showsLoading: false)
                s.succeed(at: homeRef)
                return s
            }()
            let batFailedBlock: BlockState = {
                var s = BlockState(.battery, createdAt: homeRef.addingTimeInterval(-60))
                s.begin(at: homeRef.addingTimeInterval(-40), showsLoading: false)
                s.succeed(at: homeRef.addingTimeInterval(-38))
                s.begin(at: homeRef.addingTimeInterval(-5), showsLoading: false)
                s.fail(.timedOut)
                return s
            }()
            @MainActor func battery(_ tweak: (inout BatteryDetail) -> Void = { _ in }, condition: String = "Normal",
                                    block: BlockState? = nil) -> DashboardModel {
                fixtureHome {
                    var d = VisualFixture.batteryDetail
                    tweak(&d)
                    $0.report.battery?.condition = condition
                    $0.applyFixtureBattery(d, block: block ?? batOKBlock)
                }
            }
            let batWorn = battery()                                              // charging, 76 % → amber note
            let batNormal = battery { $0.maxCapacityMAh = 4491; $0.currentCapacityMAh = 3683; $0.healthPercent = 88 }
            let batOnBattery = battery {
                $0.externalConnected = false; $0.isCharging = false; $0.adapter = nil; $0.charger = nil
                $0.percent = 64; $0.amperageMA = -604; $0.powerW = -7.9; $0.timeToFullMin = nil; $0.timeToEmptyMin = 380
            }
            let batService = battery({ $0.maxCapacityMAh = 3623; $0.currentCapacityMAh = 2319; $0.healthPercent = 71
                                       $0.cycleCount = 1012; $0.externalConnected = false; $0.isCharging = false
                                       $0.adapter = nil; $0.charger = nil; $0.percent = 64; $0.amperageMA = -604
                                       $0.powerW = -7.9; $0.timeToFullMin = nil; $0.timeToEmptyMin = 230
                                       $0.lifetime?.totalOperatingTimeH = 11920 },
                                     condition: "Service Recommended")
            let batReading = fixtureHome { $0.applyFixtureBattery(nil, block: BlockState(.battery, createdAt: homeRef)) }
            let batFailedSaved = battery(block: batFailedBlock)
            let batFailedEmpty = fixtureHome { $0.applyFixtureBattery(nil, block: {
                var s = BlockState(.battery, createdAt: homeRef.addingTimeInterval(-6))
                s.begin(at: homeRef.addingTimeInterval(-5), showsLoading: true)
                s.fail(.noReading)
                return s
            }()) }
            // REDESIGN-SECURITY: Security page states. Fixture = FV/GK/SIP on, firewall off, no updates (checked 5 min ago), one Xcode crash.
            let secHome = FileManager.default.homeDirectoryForCurrentUser.path
            @MainActor func security(_ tweak: (DashboardModel) -> Void = { _ in }) -> DashboardModel { fixtureHome(tweak) }
            let secFirewallOff = security()
            let secAllOn = security { $0.report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true); $0.report.crashes = [] }
            let secEnabling = security { $0.applyFixtureSecurity(action: .enabling(.firewall)) }
            let secTimeout = security { $0.applyFixtureSecurity(action: .failed(.firewall, .timedOut)) }
            let secCancelled = security { $0.report.security = SecurityState(fileVault: true, gatekeeper: false, sip: true, firewall: true); $0.applyFixtureSecurity(action: .failed(.gatekeeper, .cancelled)) }
            let secOffStates = security { $0.report.security = SecurityState(fileVault: false, gatekeeper: true, sip: false, firewall: true) }
            let secUnknown = security { $0.report.security = SecurityState() }
            let secCollecting = security { $0.report.security = nil; $0.report.crashes = nil }
            let secUpdates = security { $0.report.updates = VisualFixture.securityUpdates }
            let secChecking = security { $0.report.updates = nil; $0.report.updatesCheckedAt = nil; $0.applyFixtureSecurity(action: .idle, checkingUpdates: true) }
            let secCheckFailed = security { $0.report.updates = nil; $0.report.updatesCheckedAt = nil }
            let secCrashes = security { $0.report.crashes = VisualFixture.securityCrashes(home: secHome, now: homeRef) }
            let secRefreshing = security { $0.applyFixtureSecurity(action: .idle, refreshing: true) }
            // REDESIGN-BACKUPS: Backups page states. Reference instants are relative to the fixture clock (2026-01-15 10:30).
            @MainActor func backups(_ tweak: (DashboardModel) -> Void = { _ in }) -> DashboardModel { fixtureHome(tweak) }
            func bkDest(last: Date?, mounted: Bool, schedule: TMSchedule? = .automatic(intervalSeconds: 3600)) -> TMDestination {
                TMDestination(name: "Backup SSD", kind: "Local", mountPoint: mounted ? "/Volumes/Backup SSD" : nil,
                              quotaBytes: nil, lastBackup: last.map { Parsers.formatTMBackupDate($0) },
                              lastBackupDate: last, freeBytes: mounted ? 612_000_000_000 : nil, schedule: schedule)
            }
            let bkSample = TimeMachineStatus.parse(text: (try? String(
                contentsOf: fixturesRoot.appendingPathComponent("tmutil-status/tmutil-status-backing-synthetic.txt"),
                encoding: .utf8)) ?? "")!
            let bkNotSet = backups()
            let bkOk = backups { $0.report.tmDest = .some(bkDest(last: homeRef - 50 * 60, mounted: true)) }
            let bkOkNoFDA = backups { $0.report.tmDest = .some(bkDest(last: homeRef - 50 * 60, mounted: true, schedule: nil)) }
            let bkOverdue7 = backups { $0.report.tmDest = .some(bkDest(last: homeRef - 9 * 86_400, mounted: false)) }
            let bkOverdue30 = backups { $0.report.tmDest = .some(bkDest(last: homeRef - 34 * 86_400, mounted: false)) }
            let bkOverdue7Mounted = backups { $0.report.tmDest = .some(bkDest(last: homeRef - 9 * 86_400, mounted: true)) }
            let bkBackingDest = bkDest(last: homeRef - 86_400 - 2 * 3600, mounted: true)
            let bkBacking = backups { $0.report.tmDest = .some(bkBackingDest); $0.applyFixtureTimeMachine(backup: bkSample, action: .idle) }
            let bkStopping = backups { $0.report.tmDest = .some(bkBackingDest); $0.applyFixtureTimeMachine(backup: bkSample, action: .stopping) }
            let bkPreparing = backups {
                $0.report.tmDest = .some(bkBackingDest)
                $0.applyFixtureTimeMachine(backup: TMBackupProgress(running: true, stopping: false, phase: "PreparingSourceVolumes"), action: .idle)
            }
            let bkFindingChanges = backups {
                $0.report.tmDest = .some(bkBackingDest)
                $0.applyFixtureTimeMachine(backup: TMBackupProgress(running: true, stopping: false, phase: "FindingChanges", changedItems: 31_711, scanFraction: 0.53), action: .idle)
            }
            let bkStartFailed = backups {
                $0.report.tmDest = .some(bkDest(last: homeRef - 9 * 86_400, mounted: true))
                $0.applyFixtureTimeMachine(backup: nil, action: .failed(L.bkStartDidNotBegin))
            }
            let bkClaudeStale = backups { $0.claudeBackup = .lastSuccess(homeRef - 4 * 86_400) }
            let bkClaudeNone = backups { $0.claudeBackup = .noSuccessFound }
            let bkClaudeMissing = backups { $0.claudeBackup = nil }
            let bkClaudeUnreadable = backups { $0.claudeBackup = .unreadable }
            let bkWait = backups { $0.report.tmDest = nil }
            // REDESIGN-SYSTEM: System page states. Fixture = caffeinate (amber) + backupd (system), brew outdated (3), nothing checked.
            @MainActor func system(_ tweak: (DashboardModel) -> Void = { _ in }) -> DashboardModel { fixtureHome(tweak) }
            let sysHome = FileManager.default.homeDirectoryForCurrentUser.path
            let sysFixtureAutostart = VisualFixture.autostart(home: sysHome)
            let sysOrphanPaths = (sysFixtureAutostart.userAgents + sysFixtureAutostart.systemAgents + sysFixtureAutostart.systemDaemons)
                .filter(\.isOrphan).map(\.path)
            let sysChecked20 = homeRef.addingTimeInterval(-20)
            let sysDefault = system()
            let sysNone = system { $0.applyFixtureWakeHolders(user: [], system: [], sampled: true) }
            let sysWait = system { $0.applyFixtureWakeHolders(user: [], system: [], sampled: false) }
            let sysChecked = system { $0.applyFixtureStartup(checkedAt: sysChecked20, removed: 0, checking: false, deleting: [], failure: nil) }
            let sysDeleting = system { $0.applyFixtureStartup(checkedAt: sysChecked20, removed: 0, checking: false, deleting: Set(sysOrphanPaths), failure: nil) }
            let sysRemoved = system {
                var a = sysFixtureAutostart
                a.userAgents.removeAll(where: \.isOrphan); a.systemAgents.removeAll(where: \.isOrphan)
                $0.report.autostart = a
                $0.applyFixtureStartup(checkedAt: sysChecked20, removed: 2, checking: false, deleting: [], failure: nil)
            }
            func sysFailed(_ f: PrivilegedActionFailure) -> DashboardModel {
                system { $0.applyFixtureStartup(checkedAt: sysChecked20, removed: 0, checking: false, deleting: [], failure: f) }
            }
            let sysFailError = sysFailed(.error("permission denied"))
            let sysFailCancelled = sysFailed(.cancelled)
            let sysFailTimedOut = sysFailed(.timedOut)
            let sysBrewUpdating = system { $0.applyFixtureBrew(checkedAt: homeRef, upgrading: true, progress: nil, error: nil, notice: nil, stoppable: true) }
            let sysBrewOK = system { $0.report.brewOutdated = []; $0.report.brewOutdatedDetail = [] }
            let sysBrewNone = system { $0.report.brewStatus = .notInstalled }
            let sysBrewCheckFailed = system { $0.report.brewOutdated = nil; $0.report.brewOutdatedDetail = nil }
            let sysBrewUpgradeFailed = system {
                $0.applyFixtureBrew(checkedAt: homeRef, upgrading: false, progress: nil,
                                    error: "Update failed: Error: node: checksum mismatch", notice: nil, stoppable: false)
            }
            let sysBrewStopped = system {
                $0.report.brewOutdated = ["node", "python@3.13"]
                $0.report.brewOutdatedDetail = Array(($0.report.brewOutdatedDetail ?? []).dropFirst())
                $0.applyFixtureBrew(checkedAt: homeRef, upgrading: false, progress: nil, error: nil,
                                    notice: "Upgrade stopped: 1 of 3 packages upgraded", stoppable: false)
            }
            let sysEnergyApplied = system { $0.applyFixtureEnergyApply(.applied) }
            let sysEnergyCancelled = system { $0.applyFixtureEnergyApply(.failed(.cancelled)) }
            let sysEnergyTimedOut = system { $0.applyFixtureEnergyApply(.failed(.timedOut)) }
            let sysEnergyError = system { $0.applyFixtureEnergyApply(.failed(.error("code 1"))) }
            let sysPending = [EnergyChange(bucket: .battery, key: "displaysleep", value: "5"),
                              EnergyChange(bucket: .ac, key: "powernap", value: "0")]
            let sysBarStale = system {
                $0.applyFixtureWakeHolders(user: [], system: [], sampled: true)
                $0.applyFixtureStartup(checkedAt: sysChecked20, removed: 0, checking: false, deleting: [], failure: nil)
            }
            let sysBarUpdating = system {
                $0.applyFixtureWakeHolders(user: [], system: [], sampled: true)
                $0.applyFixtureBrew(checkedAt: homeRef, upgrading: true, progress: nil, error: nil, notice: nil, stoppable: true)
            }
            let sysBarApplyFailed = system { $0.applyFixtureEnergyApply(.failed(.error("code 1"))) }
            let sysBarClear = system {
                $0.applyFixtureWakeHolders(user: [], system: [], sampled: true)
                $0.report.brewOutdated = []; $0.report.brewOutdatedDetail = []
            }
            let sysBarNoneOutdated = system {
                $0.applyFixtureWakeHolders(user: [], system: [], sampled: true)
            }
            let fixtureDays = m.history.mac_history
            let historyAll = fixtureHistory(fixtureDays)
            let historyNoDays = fixtureHistory([])
            let historyOneDay = fixtureHistory(Array(fixtureDays.suffix(1)))
            let historyRestarted = fixtureHistory(Array(fixtureDays.suffix(1)),
                                                  backup: "mac_check_state.json.unreadable-20260115-103000")
            let historyTwoDays = fixtureHistory(Array(fixtureDays.suffix(2)))
            let history122 = fixtureHistory(Array(fixtureDays.suffix(122)))
            let historyUnreadable = fixtureHistory([]); historyUnreadable.applyFixtureHistory(unreadable: true, refreshing: false)
            let historyReading = fixtureHistory([]); historyReading.applyFixtureHistory(unreadable: true, refreshing: true)
            let historyNoBattery = fixtureHistory(fixtureDays.map { var e = $0; e.battery_pct = nil; e.cycles = nil; return e })
            /// Index of the largest swap value inside the 1M window (the «top» tooltip pin).
            let swapTopIndex: Int = {
                let pts = HistoryPageModel.visiblePoints(fixtureDays, metric: .swap, range: .month, calendar: .current)
                return pts.indices.max { pts[$0].value < pts[$1].value } ?? 0
            }()

            for mode in ["dark", "light"] {

                run.snap("content-processes-cpu", mode, width: 589) {
                    ProcessListCard(model: m, initialMetric: .cpu)
                }
                run.snap("content-processes-mem", mode, width: 589) {
                    ProcessListCard(model: m, initialMetric: .mem)
                }
                // 1094 = 1150 window - 2 x 28 page padding.
                run.snap("content-cpu-live", mode, width: 1094) {
                    CPUUsageCard(model: m)
                }
                run.snap("content-cpu-high", mode, width: 1094) {
                    CPUUsageCard(model: cpuHigh)
                }
                run.snap("content-cpu-hot", mode, width: 1094) {
                    CPUUsageCard(model: cpuHot)
                }
                run.snap("content-cpu-failed", mode, width: 1094) {
                    CPUUsageCard(model: cpuFail)
                }
                run.snap("content-cpu-loading", mode, width: 1094) {
                    CPUUsageCard(model: cpuLoading)
                }
                run.snap("content-cpu-bars", mode, width: 1150) {
                    VStack(spacing: 12) {
                        CPUPageBar(model: m) {}
                        CPUPageBar(model: cpuHigh) {}
                        CPUPageBar(model: cpuFail) {}
                        CPUPageBar(model: cpuLoading) {}
                    }
                }
                run.snap("content-memory-usage-live", mode, width: 1094) {
                    MemoryUsageCard(model: m, narrow: false)
                }
                run.snap("content-memory-usage-medium", mode, width: 1094) {
                    MemoryUsageCard(model: memMedium, narrow: false)
                }
                run.snap("content-memory-usage-high", mode, width: 1094) {
                    MemoryUsageCard(model: memHigh, narrow: false)
                }
                run.snap("content-memory-usage-narrow", mode, width: 904) {
                    MemoryUsageCard(model: m, narrow: true)
                }
                run.snap("content-memory-usage-failed", mode, width: 1094) {
                    MemoryUsageCard(model: memFail, narrow: false)
                }
                run.snap("content-memory-usage-loading", mode, width: 1094) {
                    MemoryUsageCard(model: memLoading, narrow: false)
                }
                run.snap("content-memory-comp-chart", mode, width: 1094) {
                    MemoryCompositionCard(model: m, narrow: false)
                }
                run.snap("content-memory-comp-table", mode, width: 1094) {
                    MemoryCompositionCard(model: m, narrow: false, initialView: .table)
                }
                run.snap("content-memory-comp-narrow", mode, width: 904) {
                    MemoryCompositionCard(model: m, narrow: true)
                }
                run.snap("content-memory-comp-failed", mode, width: 1094) {
                    VStack(spacing: 12) {
                        MemoryCompositionCard(model: memFail, narrow: false)
                        MemoryCompositionCard(model: memFail, narrow: false, initialView: .table)
                    }
                }
                run.snap("content-memory-procs", mode, width: 1094) {
                    ProcessListCard(model: m, memoryPage: true)
                }
                run.snap("content-memory-bars", mode, width: 1150) {
                    VStack(spacing: 12) {
                        MemoryPageBar(model: m) {}
                        MemoryPageBar(model: memMedium) {}
                        MemoryPageBar(model: memHigh) {}
                        MemoryPageBar(model: memUnknown) {}
                        MemoryPageBar(model: memFail) {}
                        MemoryPageBar(model: memLoading) {}
                    }
                }
                run.snap("content-processes-cpu-open", mode, width: 589) {
                    ProcessListCard(model: m, initialMetric: .cpu,
                                    rowFixture: ProcessRowFixture(pid: 101, detail: VisualFixture.procDetailWindowServer, phase: .open))
                }
                run.snap("content-processes-cpu-confirm", mode, width: 589) {
                    ProcessListCard(model: m, initialMetric: .cpu,
                                    rowFixture: ProcessRowFixture(pid: 103, detail: VisualFixture.procDetailXcode, phase: .confirm))
                }
                run.snap("content-processes-cpu-quitting", mode, width: 589) {
                    ProcessListCard(model: m, initialMetric: .cpu,
                                    rowFixture: ProcessRowFixture(pid: 103, detail: VisualFixture.procDetailXcode, phase: .quitting))
                }
                // REDESIGN-STORAGE: Storage page states (1094 = 1150 window - 2 x 28 page padding; 924 = 980 - 56).
                run.snap("content-storage-ok", mode, width: 1094) {
                    VStack(spacing: 16) {
                        StorageDiskCard(model: stOK)
                        StorageFoldersCard(model: stOK, router: NavigationRouter())
                        StorageSmartCard(model: stOK, windowWidth: 1150)
                    }
                }
                run.snap("content-storage-low", mode, width: 1094) {
                    StorageDiskCard(model: stLow)
                }
                run.snap("content-storage-critical", mode, width: 1094) {
                    StorageDiskCard(model: stCritical)
                }
                run.snap("content-storage-bars", mode, width: 1150) {
                    VStack(spacing: 12) {
                        StoragePageBar(model: stOK) {}
                        StoragePageBar(model: stLow) {}
                        StoragePageBar(model: stCritical) {}
                        StoragePageBar(model: stWorn) {}
                        StoragePageBar(model: stFailing) {}
                        StoragePageBar(model: stNoDisk) {}
                    }
                }
                run.snap("content-storage-loading", mode, width: 1094) {
                    VStack(spacing: 16) {
                        StorageDiskCard(model: stNoDisk)
                        StorageSmartCard(model: stNoDisk, windowWidth: 1150)
                        StorageSmartCard(model: stNoDisks, windowWidth: 1150)
                    }
                }
                run.snap("content-storage-folders-counting", mode, width: 1094) {
                    StorageFoldersCard(model: stCounting, router: NavigationRouter())
                }
                run.snap("content-storage-folders-timeout", mode, width: 1094) {
                    VStack(spacing: 16) {
                        StorageFoldersCard(model: stTimeout, router: NavigationRouter())
                        StorageFoldersCard(model: stNoResult, router: NavigationRouter())
                    }
                }
                run.snap("content-storage-folders-system", mode, width: 1094) {
                    StorageFoldersCard(model: stOK, router: NavigationRouter(), initialSegment: .system)
                }
                run.snap("content-storage-fda-missing", mode, width: 1094) {
                    StorageFoldersCard(model: stFDA, router: NavigationRouter())
                }
                run.snap("content-storage-trash-confirm", mode, width: 1094) {
                    VStack(spacing: 16) {
                        StorageFoldersCard(model: stOK, router: NavigationRouter(), initialConfirm: StorageTrashConfirmFixture(count: 37))
                        StorageFoldersCard(model: stOK, router: NavigationRouter(), initialConfirm: StorageTrashConfirmFixture(count: nil))
                    }
                }
                run.snap("content-storage-trash-counting", mode, width: 1094) {
                    StorageFoldersCard(model: stOK, router: NavigationRouter(), initialCounting: true)
                }
                run.snap("content-storage-smart-wear", mode, width: 1094) {
                    StorageSmartCard(model: stWorn, windowWidth: 1150)
                }
                run.snap("content-storage-smart-failing", mode, width: 1094) {
                    VStack(spacing: 16) {
                        StorageSmartCard(model: stFailing, windowWidth: 1150, initialSelection: "/dev/disk4")
                        StorageSmartCard(model: stUnavailable, windowWidth: 1150, initialSelection: "/dev/disk4")
                    }
                }
                run.snap("content-storage-tools-installable", mode, width: 1094) {
                    StorageSmartCard(model: stInstallable, windowWidth: 1150)
                }
                run.snap("content-storage-tools-installing", mode, width: 1094) {
                    StorageSmartCard(model: stInstalling, windowWidth: 1150)
                }
                run.snap("content-storage-tools-failed", mode, width: 1094) {
                    StorageSmartCard(model: stInstallFailed, windowWidth: 1150)
                }
                run.snap("content-storage-tools-needsbrew", mode, width: 1094) {
                    StorageSmartCard(model: stNeedsBrew, windowWidth: 1150)
                }
                run.snap("content-storage-narrow", mode, width: 924) {
                    VStack(spacing: 16) {
                        StorageSmartCard(model: stFailing, windowWidth: 980)
                        StorageSmartCard(model: stInstallable, windowWidth: 980)
                    }
                }
                run.snap("content-battery-worn", mode, width: 1094) {
                    VStack(spacing: 16) { BatteryNowCard(model: batWorn, narrow: false); BatteryHealthCard(model: batWorn, narrow: false); BatteryChargingCard(model: batWorn) }
                }
                run.snap("content-battery-rest", mode, width: 1094) {
                    VStack(spacing: 16) { BatteryLifetimeCard(model: batWorn); BatteryPassportCard(model: batWorn); BatteryHistoryCard(model: batWorn, router: NavigationRouter()) }
                }
                run.snap("content-battery-normal", mode, width: 1094) {
                    BatteryHealthCard(model: batNormal, narrow: false)
                }
                run.snap("content-battery-on-battery", mode, width: 1094) {
                    VStack(spacing: 16) { BatteryNowCard(model: batOnBattery, narrow: false); BatteryChargingCard(model: batOnBattery) }
                }
                run.snap("content-battery-service", mode, width: 1094) {
                    VStack(spacing: 16) { BatteryNowCard(model: batService, narrow: false); BatteryHealthCard(model: batService, narrow: false) }
                }
                run.snap("content-battery-reading", mode, width: 1094) {
                    VStack(spacing: 16) { BatteryNowCard(model: batReading, narrow: false); BatteryHealthCard(model: batReading, narrow: false) }
                }
                run.snap("content-battery-failed", mode, width: 1094) {
                    VStack(spacing: 16) { BatteryNowCard(model: batFailedSaved, narrow: false); BatteryHealthCard(model: batFailedSaved, narrow: false); BatteryNowCard(model: batFailedEmpty, narrow: false) }
                }
                run.snap("content-battery-narrow", mode, width: 904) {
                    VStack(spacing: 16) { BatteryNowCard(model: batWorn, narrow: true); BatteryHealthCard(model: batWorn, narrow: true); BatteryNowCard(model: batFailedSaved, narrow: true) }
                }
                run.snap("content-battery-bars", mode, width: 1150) {
                    VStack(spacing: 12) { BatteryPageBar(model: batWorn) {}; BatteryPageBar(model: batNormal) {}; BatteryPageBar(model: batService) {}; BatteryPageBar(model: batReading) {}; BatteryPageBar(model: batFailedSaved) {} }
                }
                run.snap("content-security-firewall-off", mode, width: 1094) {
                    VStack(spacing: 16) { SecurityProtectionCard(model: secFirewallOff, narrow: false); SecurityUpdatesCard(model: secFirewallOff); SecurityCrashesCard(model: secFirewallOff) }
                }
                run.snap("content-security-all-on", mode, width: 1094) {
                    VStack(spacing: 16) { SecurityProtectionCard(model: secAllOn, narrow: false); SecurityCrashesCard(model: secAllOn) }
                }
                run.snap("content-security-enabling", mode, width: 1094) {
                    SecurityProtectionCard(model: secEnabling, narrow: false)
                }
                run.snap("content-security-banners", mode, width: 1094) {
                    VStack(spacing: 16) { SecurityProtectionCard(model: secTimeout, narrow: false); SecurityProtectionCard(model: secCancelled, narrow: false) }
                }
                run.snap("content-security-off-states", mode, width: 1094) {
                    SecurityProtectionCard(model: secOffStates, narrow: false, initialFileVaultOpened: true)
                }
                run.snap("content-security-unknown", mode, width: 1094) {
                    VStack(spacing: 16) { SecurityProtectionCard(model: secUnknown, narrow: false); SecurityProtectionCard(model: secCollecting, narrow: false); SecurityCrashesCard(model: secCollecting) }
                }
                run.snap("content-security-updates", mode, width: 1094) {
                    VStack(spacing: 16) { SecurityUpdatesCard(model: secUpdates); SecurityUpdatesCard(model: secChecking); SecurityUpdatesCard(model: secCheckFailed) }
                }
                run.snap("content-security-crashes", mode, width: 1094) {
                    VStack(spacing: 16) {
                        SecurityCrashesCard(model: secCrashes)
                        SecurityCrashesCard(model: secCrashes, initialOpenedReport: secHome + "/Library/Logs/DiagnosticReports/MacDashboard-2026-01-15-094112.ips")
                    }
                }
                run.snap("content-security-narrow", mode, width: 904) {
                    SecurityProtectionCard(model: secFirewallOff, narrow: true)
                }
                run.snap("content-security-bars", mode, width: 1150) {
                    VStack(spacing: 12) {
                        SecurityPageBar(model: secAllOn) {}; SecurityPageBar(model: secFirewallOff) {}; SecurityPageBar(model: secEnabling) {}
                        SecurityPageBar(model: secOffStates) {}; SecurityPageBar(model: secUpdates) {}; SecurityPageBar(model: secCrashes) {}
                        SecurityPageBar(model: secCollecting) {}; SecurityPageBar(model: secRefreshing) {}
                    }
                }
                run.snap("content-backups-notset", mode, width: 1094) {
                    VStack(spacing: 16) { BackupsTimeMachineCard(model: bkNotSet, narrow: false); BackupsClaudeCard(model: bkNotSet) }
                }
                run.snap("content-backups-ok", mode, width: 1094) {
                    VStack(spacing: 16) { BackupsTimeMachineCard(model: bkOk, narrow: false); BackupsTimeMachineCard(model: bkOkNoFDA, narrow: false) }
                }
                run.snap("content-backups-overdue", mode, width: 1094) {
                    VStack(spacing: 16) {
                        BackupsTimeMachineCard(model: bkOverdue7, narrow: false); BackupsTimeMachineCard(model: bkOverdue30, narrow: false)
                        BackupsTimeMachineCard(model: bkOverdue7Mounted, narrow: false)
                    }
                }
                run.snap("content-backups-backing", mode, width: 1094) {
                    VStack(spacing: 16) {
                        BackupsTimeMachineCard(model: bkBacking, narrow: false); BackupsTimeMachineCard(model: bkStopping, narrow: false)
                        BackupsTimeMachineCard(model: bkPreparing, narrow: false); BackupsTimeMachineCard(model: bkFindingChanges, narrow: false)
                        BackupsTimeMachineCard(model: bkStartFailed, narrow: false)
                    }
                }
                run.snap("content-backups-claude", mode, width: 1094) {
                    VStack(spacing: 16) {
                        BackupsClaudeCard(model: bkClaudeStale); BackupsClaudeCard(model: bkClaudeNone)
                        BackupsClaudeCard(model: bkClaudeMissing); BackupsClaudeCard(model: bkClaudeUnreadable)
                    }
                }
                run.snap("content-backups-wait", mode, width: 1094) {
                    BackupsTimeMachineCard(model: bkWait, narrow: false)
                }
                run.snap("content-backups-narrow", mode, width: 904) {
                    VStack(spacing: 16) { BackupsTimeMachineCard(model: bkOk, narrow: true); BackupsTimeMachineCard(model: bkOverdue7, narrow: true) }
                }
                run.snap("content-backups-bars", mode, width: 1150) {
                    VStack(spacing: 12) {
                        BackupsPageBar(model: bkNotSet) {}; BackupsPageBar(model: bkOk) {}; BackupsPageBar(model: bkOverdue7) {}
                        BackupsPageBar(model: bkOverdue30) {}; BackupsPageBar(model: bkBacking) {}; BackupsPageBar(model: bkClaudeStale) {}
                        BackupsPageBar(model: bkClaudeMissing) {}; BackupsPageBar(model: bkWait) {}
                    }
                }
                run.snap("content-system-sleep", mode, width: 1094) {
                    VStack(spacing: 16) {
                        SystemSleepCard(model: sysDefault, initialHidden: VisualFixture.hiddenHolders, initialHiddenOpen: true)
                        SystemSleepCard(model: sysNone, initialHidden: VisualFixture.hiddenHolders)
                        SystemSleepCard(model: sysWait)
                    }
                }
                run.snap("content-system-startup", mode, width: 1094) {
                    VStack(spacing: 16) {
                        SystemStartupCard(model: sysDefault, router: NavigationRouter())
                        SystemStartupCard(model: sysChecked, router: NavigationRouter(), initialOpen: [.login, .userAgents, .systemAgents])
                    }
                }
                run.snap("content-system-startup-flow", mode, width: 1094) {
                    VStack(spacing: 16) {
                        SystemStartupCard(model: sysChecked, router: NavigationRouter(), initialOpen: [.login, .userAgents, .systemAgents], initialConfirm: true)
                        SystemStartupCard(model: sysDeleting, router: NavigationRouter(), initialOpen: [.login, .userAgents, .systemAgents])
                        SystemStartupCard(model: sysRemoved, router: NavigationRouter())
                    }
                }
                run.snap("content-system-startup-fail", mode, width: 1094) {
                    VStack(spacing: 16) {
                        SystemStartupCard(model: sysFailError, router: NavigationRouter(), initialOpen: [.userAgents])
                        SystemStartupCard(model: sysFailCancelled, router: NavigationRouter(), initialOpen: [.userAgents])
                        SystemStartupCard(model: sysFailTimedOut, router: NavigationRouter(), initialOpen: [.userAgents])
                    }
                }
                run.snap("content-system-brew", mode, width: 1094) {
                    VStack(spacing: 16) {
                        SystemBrewCard(model: sysDefault); SystemBrewCard(model: sysBrewUpdating); SystemBrewCard(model: sysBrewOK)
                        SystemBrewCard(model: sysBrewNone); SystemBrewCard(model: sysBrewCheckFailed)
                        SystemBrewCard(model: sysBrewUpgradeFailed); SystemBrewCard(model: sysBrewStopped)
                    }
                }
                run.snap("content-system-energy", mode, width: 1094) {
                    VStack(spacing: 16) {
                        SystemEnergyCard(model: sysDefault, router: NavigationRouter())
                        SystemEnergyCard(model: sysDefault, router: NavigationRouter(), initialPending: sysPending, initialInfoKey: "sleep")
                        SystemEnergyCard(model: sysDefault, router: NavigationRouter(), initialPending: sysPending, initialConfirm: true)
                    }
                }
                run.snap("content-system-energy-result", mode, width: 1094) {
                    VStack(spacing: 16) {
                        SystemEnergyCard(model: sysEnergyApplied, router: NavigationRouter())
                        SystemEnergyCard(model: sysEnergyCancelled, router: NavigationRouter())
                        SystemEnergyCard(model: sysEnergyTimedOut, router: NavigationRouter())
                        SystemEnergyCard(model: sysEnergyError, router: NavigationRouter())
                    }
                }
                run.snap("content-system-narrow", mode, width: 904) {
                    VStack(spacing: 16) {
                        SystemSleepCard(model: sysDefault, initialHidden: VisualFixture.hiddenHolders, initialHiddenOpen: true)
                        SystemStartupCard(model: sysChecked, router: NavigationRouter(), initialOpen: [.login, .userAgents, .systemAgents])
                    }
                }
                run.snap("content-system-bars", mode, width: 1150) {
                    VStack(spacing: 12) {
                        SystemPageBar(model: sysDefault) {}; SystemPageBar(model: sysBarNoneOutdated) {}; SystemPageBar(model: sysBarUpdating) {}
                        SystemPageBar(model: sysBarStale) {}; SystemPageBar(model: sysBarApplyFailed) {}; SystemPageBar(model: sysBarClear) {}
                    }
                }
                let nav = NavigationRouter()
                run.snap("content-history-disk", mode, width: 1094) { HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .disk, initialRange: .month) }
                run.snap("content-history-battery", mode, width: 1094) { HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .battery, initialRange: .month) }
                run.snap("content-history-cycles", mode, width: 1094) { HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .cycles, initialRange: .month) }
                run.snap("content-history-swap", mode, width: 1094) { HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .swap, initialRange: .month) }
                run.snap("content-history-disk-quarter", mode, width: 1094) { HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .disk, initialRange: .quarter) }
                run.snap("content-history-disk-year", mode, width: 1094) { HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .disk, initialRange: .year) }
                run.snap("content-history-disk-all", mode, width: 1094) { HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .disk, initialRange: .all) }
                run.snap("content-history-tooltip", mode, width: 1094) {
                    VStack(spacing: 16) {
                        HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .disk, initialRange: .month, initialHover: 0)
                        HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .cycles, initialRange: .month, initialHover: 29)
                        HistoryCardView(model: historyAll, router: nav, narrow: false, initialMetric: .swap, initialRange: .month, initialHover: swapTopIndex)
                    }
                }
                run.snap("content-history-table", mode, width: 1094) {
                    VStack(spacing: 16) {
                        HistoryCardView(model: historyAll, router: nav, narrow: false, initialRange: .month, initialView: .table)
                        HistoryCardView(model: historyAll, router: nav, narrow: false, initialRange: .month, initialView: .table, initialShowAll: true)
                    }
                }
                run.snap("content-history-narrow", mode, width: 844) {
                    VStack(spacing: 16) {
                        HistoryCardView(model: historyAll, router: nav, narrow: true, initialRange: .month, initialView: .table)
                        HistoryCardView(model: historyAll, router: nav, narrow: true, initialMetric: .disk, initialRange: .year)
                    }
                }
                run.snap("content-history-states", mode, width: 1094) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "History: 122 days, 1Y disabled, selected 1Y falls back to All") { HistoryCardView(model: history122, router: nav, narrow: false, initialRange: .year) }
                        HarnessSection(label: "History: two days recorded (only All enabled)") { HistoryCardView(model: historyTwoDays, router: nav, narrow: false) }
                        HarnessSection(label: "History: one day recorded") { HistoryCardView(model: historyOneDay, router: nav, narrow: false) }
                        HarnessSection(label: "History: no days recorded (new Mac)") { HistoryCardView(model: historyNoDays, router: nav, narrow: false) }
                        HarnessSection(label: "History: started over, one day recorded (notice + panel)") { HistoryCardView(model: historyRestarted, router: nav, narrow: false) }
                        HarnessSection(label: "History: file unreadable") { HistoryCardView(model: historyUnreadable, router: nav, narrow: false) }
                        HarnessSection(label: "History: reading…") { HistoryCardView(model: historyReading, router: nav, narrow: false) }
                        HarnessSection(label: "History: no battery data, Battery metric") { HistoryCardView(model: historyNoBattery, router: nav, narrow: false, initialMetric: .battery) }
                    }
                }
                run.snap("content-history-bars", mode, width: 1150) {
                    VStack(spacing: 12) {
                        HistoryPageBar(model: historyAll) {}; HistoryPageBar(model: historyOneDay) {}; HistoryPageBar(model: historyNoDays) {}
                        HistoryPageBar(model: historyUnreadable) {}; HistoryPageBar(model: historyReading) {}
                    }
                }
                run.snap("content-home-attention", mode, width: 1094) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "Home: critical, 6 tasks") {
                            HomeAttentionCard(model: m, router: NavigationRouter(), windowWidth: 1150)
                        }
                        HarnessSection(label: "Home: Show all expanded") {
                            HomeAttentionCard(model: m, router: NavigationRouter(), windowWidth: 1150, initialShowAll: true)
                        }
                        HarnessSection(label: "Home: all good") {
                            HomeAttentionSlot(model: fixtureHome { $0.assessment = Assessment() },
                                              router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                        }
                        HarnessSection(label: "Home: first scan") {
                            HomeAttentionSlot(model: fixtureHome { $0.applyFixtureScan(homeFirstScan) },
                                              router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                        }
                        HarnessSection(label: "Home: scan failed (banner + kept tasks)") {
                            let failed = fixtureHome { $0.applyFixtureScan(homeFailedScan) }
                            VStack(alignment: .leading, spacing: 18) {
                                HomeScanBannerSlot(model: failed)
                                HomeAttentionSlot(model: failed, router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                            }
                        }
                    }
                }
                run.snap("content-home-sections", mode, width: 1094) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "Home: sections") {
                            VStack(alignment: .leading, spacing: 18) {
                                HomeSectionsHeader(model: m)
                                HomeSectionsGrid(model: m, router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                            }
                        }
                        HarnessSection(label: "Home: first scan (skeleton)") {
                            HomeSectionsGrid(model: fixtureHome { $0.applyFixtureScan(homeFirstScan) },
                                             router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                        }
                        HarnessSection(label: "Home: scan failed (last check)") {
                            HomeSectionsGrid(model: fixtureHome { $0.applyFixtureScan(homeFailedScan) },
                                             router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                        }
                        HarnessSection(label: "Home: no battery (7 tiles)") {
                            VStack(alignment: .leading, spacing: 18) {
                                let noBattery = fixtureHome { $0.battery = nil; $0.report.battery = nil }
                                HomeSectionsHeader(model: noBattery)
                                HomeSectionsGrid(model: noBattery, router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                            }
                        }
                    }
                }
                run.snap("content-report-sheet", mode, width: 740) {
                    let ref = VisualFixture.referenceDate
                    let text = m.reportText
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "Report sheet: ready") {
                            ReportSheetContent(state: ReportSheetState(phase: .ready, text: text, updatedAt: ref, now: ref),
                                               reportURL: m.reportURL, onRetry: {}, onDone: {})
                        }
                        HarnessSection(label: "Report sheet: generating") {
                            ReportSheetContent(state: ReportSheetState(phase: .generating, text: text, updatedAt: ref, now: ref),
                                               reportURL: m.reportURL, onRetry: {}, onDone: {})
                        }
                        HarnessSection(label: "Report sheet: failed, previous report kept") {
                            ReportSheetContent(state: ReportSheetState(phase: .failed(.timedOut), text: text,
                                                                       updatedAt: ref.addingTimeInterval(-78 * 60), now: ref),
                                               reportURL: m.reportURL, onRetry: {}, onDone: {})
                        }
                        HarnessSection(label: "Report sheet: failed, no report yet") {
                            ReportSheetContent(state: ReportSheetState(phase: .failed(.noReading), text: nil, updatedAt: nil, now: ref),
                                               reportURL: m.reportURL, onRetry: {}, onDone: {})
                        }
                    }
                }
                run.snap("content-home-now", mode, width: 1300) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "Now, 1150") {
                            HomeNowCard(model: m, router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                        }
                        HarnessSection(label: "Now, 1280") {
                            HomeNowCard(model: m, router: NavigationRouter(), windowWidth: 1280, animatesEntrance: false)
                                .frame(width: 1224)
                        }
                        HarnessSection(label: "Now, 900 (2×2)") {
                            HomeNowCard(model: m, router: NavigationRouter(), windowWidth: 900, animatesEntrance: false)
                                .frame(width: 844)
                        }
                        HarnessSection(label: "No battery (3 columns)") {
                            HomeNowCard(model: fixtureHome { $0.battery = nil; $0.report.battery = nil },
                                        router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                        }
                        HarnessSection(label: "Collecting (—)") {
                            HomeNowCard(model: fixtureHome {
                                $0.cpu = nil; $0.mem = nil; $0.disk = nil
                                $0.battery?.maxCapacity = nil; $0.report.battery?.maxCapacity = nil
                            }, router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                        }
                        HarnessSection(label: "Task tones") {
                            HomeNowCard(model: fixtureHome {
                                $0.report.smart = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: "SMART: errors",
                                                             attrs: [("Media and Data Integrity Errors", "3")], severity: .crit)]
                                $0.report.battery?.condition = "Service Recommended"
                                $0.applyFixturePressure(.critical)
                                $0.assessment = Assess.assess(report: $0.report,
                                                              live: LiveSnapshot(t: VisualFixture.referenceDate, load: $0.load, cpu: $0.cpu, mem: $0.mem,
                                                                                 swap: $0.swap, disk: $0.disk, battery: $0.battery),
                                                              memPressure: .critical, now: VisualFixture.referenceDate)
                            }, router: NavigationRouter(), windowWidth: 1150, animatesEntrance: false)
                        }
                    }
                }
                run.snap("content-iphone-tiles", mode, width: 1134) {
                    let ip = fixtureIPhone()
                    let ivanRecord = ip.devices.first { $0.id == ivan }!
                    HarnessSection(label: "iPhone tiles: reading / needs trust / read failed / pending") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                            IPhoneTileView(record: ivanRecord, status: .reading, snapshot: nil, storage: nil) {}
                            IPhoneTileView(record: ivanRecord, status: .needsTrust, snapshot: nil, storage: nil) {}
                            IPhoneTileView(record: ivanRecord, status: .readFailed(L.iphoneStatusFailed),
                                           snapshot: nil, storage: nil) {}
                            IPhonePendingTileView(status: .needsTrust) {}
                            IPhonePendingTileView(status: .readFailed(L.iphoneStatusFailed)) {}
                        }
                    }
                }
                run.snap("content-iphone-notices", mode, width: 1134) {
                    HarnessSection(label: "iPhone banners and notices") {
                        VStack(alignment: .leading, spacing: 16) {
                            IPhoneListBanner(kind: .error(L.iphoneRestartFailed("authorization was cancelled")))
                            IPhoneListBanner(kind: .restarting)
                            IPhoneNotice(kind: .empty)
                            IPhoneNotice(kind: .unavailable)
                        }
                    }
                }
                run.snap("content-iphone-battery", mode, width: 1134) {
                    let ip = fixtureIPhone()
                    let rec = ip.devices.first { $0.id == ivan }
                    let noBattery: IPhoneSnapshot = {
                        var s = ip.lastSnapshot[ivan]!
                        s.battery = nil
                        return s
                    }()
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "iPhone battery: history hero (no connection)") {
                            IPhoneBatteryCard(record: rec, snapshot: nil)
                        }
                        HarnessSection(label: "iPhone battery: nothing to show") {
                            IPhoneBatteryCard(record: nil, snapshot: nil)
                        }
                        HarnessSection(label: "iPhone battery: snapshot without battery data") {
                            IPhoneBatteryCard(record: rec, snapshot: noBattery)
                        }
                    }
                }
                run.snap("content-iphone-history", mode, width: 1134) {
                    let ip = fixtureIPhone()
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "iPhone history: chart with the hover tooltip") {
                            IPhoneBatteryHistoryCard(points: ip.devices.first { $0.id == ivan }!.battery, initialHover: 100)
                        }
                        HarnessSection(label: "iPhone history: table") {
                            IPhoneBatteryHistoryCard(points: ip.devices.first { $0.id == vic }!.battery, initialView: .table)
                        }
                        HarnessSection(label: "iPhone history: empty") {
                            IPhoneBatteryHistoryCard(points: [])
                        }
                    }
                }
                run.snap("content-iphone-logs", mode, width: 1134) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "iPhone logs: from archive") {
                            IPhoneLogsCard(model: fixtureIPhone(), deviceKey: ivan, initialSource: .archive)
                        }
                        HarnessSection(label: "iPhone logs: loading") {
                            IPhoneLogsCard(model: fixtureIPhone {
                                $0.logs[ivan] = nil
                                _ = $0.logsLoading.begin(ivan, handle: IPhoneHandle(raw: 1))
                            }, deviceKey: ivan)
                        }
                        HarnessSection(label: "iPhone logs: failed") {
                            IPhoneMessagePanel(text: L.iphoneSectionReadFailed, tone: .error)
                        }
                        HarnessSection(label: "iPhone logs: disconnected") {
                            IPhoneLogsCard(model: fixtureIPhone {
                                $0.logs[ivan] = nil
                                $0.connected[ivan] = nil
                                $0.archiveLogs = [:]
                            }, deviceKey: ivan)
                        }
                        HarnessSection(label: "iPhone logs: empty") {
                            IPhoneLogsCard(model: fixtureIPhone {
                                $0.logs[ivan] = []
                                $0.archiveLogs = [:]
                            }, deviceKey: ivan)
                        }
                    }
                }
                run.snap("content-iphone-import", mode, width: 1134) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "iPhone import: copying") {
                            IPhoneImportCard(model: fixtureIPhone {
                                $0.importing[ivan] = .copying(done: 125_000_000, total: 298_000_000)
                            }, deviceKey: ivan)
                        }
                        HarnessSection(label: "iPhone import: extracting") {
                            IPhoneImportCard(model: fixtureIPhone { $0.importing[ivan] = .extracting }, deviceKey: ivan)
                        }
                        HarnessSection(label: "iPhone import: success") {
                            IPhoneImportCard(model: fixtureIPhone {
                                $0.importResult[ivan] = .success((name: longArchive, summary: ImportSummary(
                                    batteryPoints: 12, skippedRows: 0, logFiles: 37,
                                    keptPath: URL(fileURLWithPath: "/tmp/kept.tar.gz"))))
                            }, deviceKey: ivan)
                        }
                        HarnessSection(label: "iPhone import: failure") {
                            IPhoneImportCard(model: fixtureIPhone {
                                $0.importResult[ivan] = .failure(.tarFailed(.exitCode(1)))
                            }, deviceKey: ivan)
                        }
                        HarnessSection(label: "iPhone import: cancelled") {
                            IPhoneImportCard(model: fixtureIPhone { $0.importResult[ivan] = .failure(.cancelled) }, deviceKey: ivan)
                        }
                    }
                }
                run.snap("content-iphone-identity", mode, width: 1264) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "iPhone identity: wide, one serial revealed, one copied") {
                            IPhoneIdentityCard(model: fixtureIPhone(), deviceKey: ivan, wide: true,
                                               initiallyRevealed: ["serial"], initiallyCopied: "imei")
                        }
                        HarnessSection(label: "iPhone identity: narrow") {
                            IPhoneIdentityCard(model: fixtureIPhone(), deviceKey: ivan, wide: false)
                        }
                        HarnessSection(label: "iPhone identity: loading") {
                            IPhoneIdentityCard(model: fixtureIPhone {
                                $0.identity[ivan] = nil
                                _ = $0.identityLoading.begin(ivan, handle: IPhoneHandle(raw: 1))
                            }, deviceKey: ivan)
                        }
                        HarnessSection(label: "iPhone identity: failed") {
                            IPhoneMessagePanel(text: L.iphoneSectionReadFailed, tone: .error)
                        }
                        HarnessSection(label: "iPhone identity: disconnected") {
                            IPhoneIdentityCard(model: fixtureIPhone {
                                $0.identity[ivan] = nil
                                $0.connected[ivan] = nil
                            }, deviceKey: ivan)
                        }
                    }
                }
                run.snap("content-iphone-dialogs", mode, width: 460) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "iPhone dialogs: restart confirmation") {
                            IPhoneRestartConfirm(onCancel: {}, onConfirm: {}).background(DS3.overlay)
                        }
                        HarnessSection(label: "iPhone dialogs: parse choice") {
                            IPhoneImportChoiceSheet(
                                title: L.iphoneImportConfirmTitle(longArchive, into: "Ivan’s iPhone"),
                                onCancel: {}, onParse: {}, onKeep: {})
                                .background(DS3.overlay)
                        }
                        HarnessSection(label: "iPhone dialogs: another-phone warning") {
                            IPhoneMismatchSheet(
                                q: ImportIdentityQuestion(
                                    archiveName: "sysdiagnose_2026.01.11_20-55-10+0300_iPhone-OS_iPhone_23D60.tar.gz",
                                    archiveMAh: [4441], deviceMAh: 5030, targetName: "Ivan’s iPhone",
                                    ownerName: "Victoria’s iPhone"),
                                onProceed: {}, onCancel: {})
                                .background(DS3.overlay)
                        }
                    }
                }
                // Settings states: the window frame (680 x 420) is owned by the test, not by SettingsView.
                func settingsState(_ name: String, _ section: SettingsSection, _ model: DashboardModel, launch: AppLanguage = .en) {
                    run.snap(name, mode, width: 680) {
                        SettingsView(model: model, startSection: section, launchLanguage: launch).frame(width: 680, height: 420)
                    }
                }
                let mMissing = DashboardModel(); mMissing.applyVisualFixture(); mMissing.claudeBackup = nil
                let mPerm = DashboardModel(); mPerm.applyVisualFixture(); mPerm.claudeBackup = .unreadable
                settingsState("content-settings-general", .general, m)
                settingsState("content-settings-general-relaunch", .general, m, launch: .ru)
                settingsState("content-settings-monitoring", .monitoring, m)
                settingsState("content-settings-backup", .backup, m)
                settingsState("content-settings-backup-missing", .backup, mMissing)
                settingsState("content-settings-backup-permission", .backup, mPerm)
                settingsState("content-settings-iphone", .iphone, m)
                settingsState("content-settings-about", .about, m)
            }
            try run.finish()
        }
    }
}
