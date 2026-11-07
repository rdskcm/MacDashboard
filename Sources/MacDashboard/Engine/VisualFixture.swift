// Engine/VisualFixture.swift
// VISUAL-COVERAGE: a pure, fixed dataset used both by the real app (via a launch
// argument, `AppModel+VisualFixture.swift`) and by the offscreen content
// render stage (`Tests/MacDashboardTests/ContentSnapshotTests.swift`), so `main-*` and every
// `content-*` visual reference is built from the same deterministic input
// instead of live machine state. No `Date()`, no random — only the user's
// home-directory path (needed so home-relative paths look real).

import Foundation
import Synchronization

enum VisualFixture {
    /// HARNESS-REDESIGN-RETARGET: test hook. The offscreen snapshot suite cannot add a launch argument to its
    /// own process, so it sets this for the duration of its render (and restores it). Never set by the app.
    /// Backed by a lock: the snapshot suite (SerialTests) writes it; main-actor code and detached pass code read it (SWIFT6-MODE D5).
    private static let forcedFlag = Mutex(false)
    static var forced: Bool {
        get { forcedFlag.withLock { $0 } }
        set { forcedFlag.withLock { $0 = newValue } }
    }

    /// `-visualFixture` on the command line (or `forced` in the snapshot tests) requests fixture mode.
    static var isRequested: Bool {
        forced || ProcessInfo.processInfo.arguments.contains("-visualFixture")
    }

    /// GPU-UTILIZATION: `-fixtureGPUUnavailable 1` on the command line makes the fixture's GPU figure nil (bench review
    /// of the honest-empty GPU card and Home figure). Read only under `-visualFixture`.
    static var gpuUnavailableRequested: Bool { ProcessInfo.processInfo.arguments.contains("-fixtureGPUUnavailable") }

    /// Always in the past, so `reportUpdatedTimeString` takes its stable
    /// "date + time" branch (not the "same day as now" time-only branch).
    static let referenceDate: Date = Calendar.current.date(
        from: DateComponents(year: 2026, month: 1, day: 15, hour: 10, minute: 30)
    )!

    /// REDESIGN-CPU: fixed process details for the expanded-row states (fixture pids: WindowServer 101, Xcode 103).
    static let procDetailWindowServer = ProcDetail(path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", owner: "_windowserver")
    static let procDetailXcode = ProcDetail(path: "/Applications/Xcode.app/Contents/MacOS/Xcode", owner: "alex")

    private static let GiB: Int64 = 1 << 30
    /// REDESIGN-STORAGE: decimal gigabytes (what `fmtCapacity` shows).
    private static func GB(_ v: Double) -> Int64 { Int64(v * 1e9) }

    /// REDESIGN-STORAGE: the internal drive's health record (model values, not the design mock-up's).
    static let internalHealth = SmartHealth(
        temperatureC: 41, percentageUsed: 3, availableSpare: 100, spareThreshold: 99, powerOnHours: 1204,
        powerCycles: 812, unsafeShutdowns: 14, dataUnitsRead: 74_609_375, dataUnitsWritten: 57_812_500,
        mediaErrors: 0, errorLogEntries: 0, criticalWarning: 0)

    /// REDESIGN-BATTERY: the ioreg detail the Battery page renders in the fixture (charging on a 35 W adapter, worn
    /// battery — health 76 % matches `make().battery.maxCapacity` and Home's «Battery 24% worn» task).
    static let batteryDetail = BatteryDetail(
        percent: 82, voltageMV: 13270, amperageMA: 2140, powerW: 28.4, temperatureC: 31.2,
        cellVoltagesMV: [4421, 4425, 4423], externalConnected: true, isCharging: true, fullyCharged: false,
        timeToEmptyMin: nil, timeToFullMin: 70, currentCapacityMAh: 3177, maxCapacityMAh: 3874,
        designCapacityMAh: 5103, cycleCount: 312, designCycleCount: 1000, healthPercent: 76,
        adapter: BatteryAdapterInfo(watts: 35, voltageMV: 20000, currentMA: 1750, name: "Apple 35W Dual USB-C",
                                    manufacturer: "Apple", adapterDescription: nil, isWireless: false,
                                    pdProfiles: [PDProfile(index: 0, maxVoltageMV: 5000, maxCurrentMA: 3000),
                                                 PDProfile(index: 1, maxVoltageMV: 9000, maxCurrentMA: 3000),
                                                 PDProfile(index: 2, maxVoltageMV: 15000, maxCurrentMA: 2330),
                                                 PDProfile(index: 3, maxVoltageMV: 20000, maxCurrentMA: 1750)],
                                    selectedProfileIndex: 3),
        charger: BatteryChargerInfo(chargingVoltageMV: 13300, chargingCurrentMA: 2140, notChargingReason: 0,
                                    slowChargingReason: 0, timeChargingThermallyLimited: 0),
        lifetime: BatteryLifetimeInfo(maxTemperatureC: 47, minTemperatureC: 12, avgTemperatureC: 29.0,
                                      maxChargeCurrentMA: 3960, maxDischargeCurrentMA: 5210,
                                      maxPackVoltageMV: 13100, minPackVoltageMV: 10200, totalOperatingTimeH: 6480),
        serial: "F8Y4213A7Q1MXLKA", manufacturerCode: "SDI", mfgYear: 2024, mfgWeek: 10, mfgCode: "2410",
        lowPowerMode: false)

    /// REDESIGN-STORAGE: a failing external drive (the `storage-smart-failing` state).
    static let externalFailingDisk = SmartDisk(
        device: "/dev/disk4", title: "External SSD", status: .mediaErrors,
        attrs: [("Critical Warning", "0x01"), ("Media and Data Integrity Errors", "27"), ("Percentage Used", "104%")],
        severity: .crit,
        health: SmartHealth(
            temperatureC: 72, percentageUsed: 104, availableSpare: 4, spareThreshold: 10, powerOnHours: 9812,
            powerCycles: 1406, unsafeShutdowns: 31, dataUnitsRead: 80_664_062, dataUnitsWritten: 231_640_625,
            mediaErrors: 27, errorLogEntries: 112, criticalWarning: 1))

    /// REDESIGN-SECURITY: sample updates for the Security page snapshot states (the fixture report keeps `updates = []`).
    // REDESIGN-SYSTEM: the System page fixtures (Sleep, Startup items, Energy settings).
    static func autostart(home: String) -> AutostartInfo {
        func info(_ path: String, label: String? = nil, orphan: Bool = false, exe: String? = nil) -> LaunchdPlistInfo {
            LaunchdPlistInfo(path: path, label: label, executablePath: exe, isOrphan: orphan)
        }
        let user = home + "/Library/LaunchAgents/"
        return AutostartInfo(
            loginItems: ["Claude", "Rectangle", "Dropbox", "iStat Menus"],
            userAgents: [info(user + "com.google.keystone.agent.plist"),
                         info(user + "com.dropbox.DropboxMacUpdate.agent.plist"),
                         info(user + "homebrew.mxcl.postgresql@14.plist", label: "homebrew.mxcl.postgresql@14", orphan: true,
                              exe: "/opt/homebrew/opt/postgresql@14/bin/postgres")],
            systemAgents: [info("/Library/LaunchAgents/com.adobe.ARMDCHelper.plist", orphan: true),
                           info("/Library/LaunchAgents/com.microsoft.update.agent.plist")],
            systemDaemons: [info("/Library/LaunchDaemons/com.docker.vmnetd.plist"),
                            info("/Library/LaunchDaemons/com.objective-see.lulu.plist"),
                            info("/Library/LaunchDaemons/org.cups.cupsd.plist"),
                            info("/Library/LaunchDaemons/com.microsoft.autoupdate.helper.plist"),
                            info("/Library/LaunchDaemons/com.adobe.acc.installer.v2.plist")],
            background: [(pid: "1123", label: "Dropbox"), (pid: "2290", label: "Docker")])
    }

    /// No battery `womp` on purpose: that cell shows «—», as in the handoff table.
    static let energy = EnergySettings(
        battery: [("displaysleep", "2"), ("sleep", "1"), ("disksleep", "10"), ("powernap", "0"), ("lowpowermode", "0"),
                  ("standby", "1"), ("hibernatemode", "3"), ("tcpkeepalive", "1"), ("lidwake", "1")],
        ac: [("displaysleep", "10"), ("sleep", "0"), ("disksleep", "10"), ("powernap", "1"), ("lowpowermode", "0"),
             ("standby", "1"), ("womp", "1"), ("hibernatemode", "3"), ("tcpkeepalive", "1"), ("lidwake", "1")])

    /// A system service holding the Mac awake: listed, never warned about.
    static let systemWakeHolders = [WakeHolder(owner: "backupd", requester: nil, ageSeconds: 720)]

    static let hiddenHolders = [
        IgnoredWakeHolder(key: WakeHolderKey(owner: "Zoom", requester: nil), since: referenceDate.addingTimeInterval(-3 * 86_400)),
        IgnoredWakeHolder(key: WakeHolderKey(owner: "backupd", requester: "Time Machine"), since: nil)]

    static let securityUpdates: [SoftwareUpdate] = [
        SoftwareUpdate(label: "macOS Tahoe 26.1.1-25B90", title: "macOS Tahoe 26.1.1", version: "26.1.1",
                       sizeBytes: 3_276_800 * 1024, restartRequired: true),
        SoftwareUpdate(label: "Safari26.2-26.2", title: "Safari 26.2", version: "26.2",
                       sizeBytes: 188_416 * 1024, restartRequired: false),
    ]

    /// REDESIGN-SECURITY: sample crash groups for the Security page snapshot states.
    static func securityCrashes(home: String, now: Date) -> [CrashGroup] {
        let cal = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let user = home + "/Library/Logs/DiagnosticReports"
        return [
            CrashGroup(process: "MacDashboard", count: 2, directory: user, lastReportAt: at(0, 9, 41),
                       newestReportPath: user + "/MacDashboard-2026-01-15-094112.ips",
                       reportPaths: [user + "/MacDashboard-2026-01-15-094112.ips", user + "/MacDashboard-2026-01-14-181530.ips"]),
            CrashGroup(process: "Kernel", count: 1, isPanic: true, directory: "/Library/Logs/DiagnosticReports",
                       lastReportAt: at(3, 22, 17),
                       newestReportPath: "/Library/Logs/DiagnosticReports/panic-full-2026-01-12-221704.panic",
                       reportPaths: ["/Library/Logs/DiagnosticReports/panic-full-2026-01-12-221704.panic"]),
            CrashGroup(process: "Xcode", count: 1, directory: user, lastReportAt: at(5, 16, 5),
                       newestReportPath: user + "/Xcode-2026-01-10-160512.ips",
                       reportPaths: [user + "/Xcode-2026-01-10-160512.ips"]),
        ]
    }

    /// CRASH-REPORT-DISMISS: reports the user hid — one per-user group, one from the system folder.
    static func securityHiddenCrashes(home: String, now: Date) -> [CrashGroup] {
        let cal = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let user = home + "/Library/Logs/DiagnosticReports"
        let system = "/Library/Logs/DiagnosticReports"
        return [
            CrashGroup(process: "diffscore", count: 3, directory: user, lastReportAt: at(1, 14, 2),
                       newestReportPath: user + "/diffscore-2026-01-14-140210.ips",
                       reportPaths: [user + "/diffscore-2026-01-14-140210.ips", user + "/diffscore-2026-01-13-101500.ips",
                                     user + "/diffscore-2026-01-12-083000.ips"]),
            CrashGroup(process: "activatehelper", count: 1, directory: system, lastReportAt: at(4, 7, 50),
                       newestReportPath: system + "/activatehelper-2026-01-11-075012.ips",
                       reportPaths: [system + "/activatehelper-2026-01-11-075012.ips"]),
        ]
    }

    /// REDESIGN-STORAGE: the folder-count result the Storage page shows (home walk + the six System paths).
    /// `unreadable` = home folders the count could not read.
    static func folderSizes(unreadable: [String]? = nil) -> FolderSizes {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return FolderSizes(
            homeDirs: [
                DirSize(path: home + "/Library", bytes: GB(48.2)),
                DirSize(path: home + "/Documents", bytes: GB(31)),
                DirSize(path: home + "/Downloads", bytes: GB(14)),
                DirSize(path: home + "/Movies", bytes: GB(9.8)),
                DirSize(path: home + "/Pictures", bytes: GB(7.4)),
                DirSize(path: home + "/Developer", bytes: GB(6.1)),
                DirSize(path: home + "/.Trash", bytes: GB(1.5)),
            ],
            homeDirsUnreadable: unreadable ?? [home + "/Library/Mail"],
            serviceDirs: [
                DirSize(path: "/Applications", bytes: GB(24.6)),
                DirSize(path: "/Library", bytes: GB(9.3)),
                DirSize(path: "/private/var", bytes: GB(6.8)),
                DirSize(path: "/usr/local", bytes: GB(2.1)),
                DirSize(path: "/opt/homebrew", bytes: GB(8.2)),
                DirSize(path: "/Users/Shared", bytes: GB(0.4)),
            ],
            serviceDirsUnreadable: [],
            countedAt: referenceDate, durationSeconds: 12,
            homeCaches: DirSize(path: home + "/Library/Caches", bytes: GB(4.2)))
    }

    /// One fixed, pure snapshot of everything a `AppModel` normally
    /// collects live.
    struct Dataset {
        var load: [Double]
        var cpu: CPUUsage
        var mem: MemSnapshot
        var swap: SwapInfo
        var disk: DiskInfo
        var battery: BatteryInfo
        var socTempC: Int?
        var gpuUtil: Int?
        var topCPU: [ProcEntry]
        var topMem: [ProcEntry]
        var cpuHistory: [(Date, Double)]
        /// SOC-DETAILS: GPU load of the same 61 instants as `cpuHistory` (values 0...30).
        var gpuHistory: [(Date, Int?)]
        /// SOC-DETAILS: the reference page-tick state (logic 3.1, 3.5, 3.6, 3.8, 3.4); `socLive(options:)` derives variants.
        var socLive: SocLiveFixture
        var report: FullReport
        var assessment: Assessment
        var history: HistoryState
        var reportText: String
        var claudeBackup: ClaudeBackupStatus
        var claudeAttempt: ClaudeBackupAttempt
        var claudeSize: ClaudeBackupSize
        var claudeJob: ClaudeBackupJob
    }

    @MainActor static func make() -> Dataset {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let load: [Double] = [2.10, 1.85, 1.60]
        let cpu = CPUUsage(user: 18.5, sys: 7.2, idle: 74.3)
        let socTempC = 48
        let gpuUtil = 23

        let mem = MemSnapshot(
            total: 16 * GiB, pageSize: 16384,
            free: Int64(1.2 * Double(GiB)), active: Int64(6.0 * Double(GiB)),
            inactive: Int64(4.5 * Double(GiB)), speculative: Int64(0.3 * Double(GiB)),
            wired: Int64(2.5 * Double(GiB)), compressor: Int64(1.0 * Double(GiB)),
            purgeable: Int64(0.2 * Double(GiB)), fileBacked: Int64(3.0 * Double(GiB))
        )

        let swapTotal: Int64 = 2 * GiB
        let swapUsed: Int64 = 512 * (1 << 20)
        let swap = SwapInfo(total: swapTotal, used: swapUsed, free: swapTotal - swapUsed)

        // REDESIGN-STORAGE: 256 GB volume, 30 % free (ok); Storage states tweak it for low / critical.
        let disk = DiskInfo(size: GB(256), avail: GB(76.8), dataUsed: GB(160), sysUsed: GB(18), purgeable: GB(3.1))

        let battery = BatteryInfo(
            source: .ac, charge: 82, state: .charging,
            cycles: 312, condition: "Normal", maxCapacity: 76
        )

        // rank 1...8, pid 101...108, in CPU-sorted order.
        let byCPUOrder: [(String, Double, Double)] = [
            ("WindowServer", 14.2, 1.1), ("Safari", 9.8, 2.4), ("Xcode", 7.5, 3.2),
            ("Mail", 3.1, 0.6), ("Finder", 2.4, 0.3), ("Music", 1.9, 0.5),
            ("Notes", 1.2, 0.4), ("Terminal", 0.8, 0.2),
        ]
        let topCPU: [ProcEntry] = byCPUOrder.enumerated().map { i, e in
            ProcEntry(rank: i + 1, name: e.0, cpu: e.1, memBytes: Int64(e.2 * Double(GiB)), pid: Int32(101 + i))
        }
        let topMemSorted = topCPU.sorted { ($0.memBytes ?? 0) > ($1.memBytes ?? 0) }
        let topMem: [ProcEntry] = topMemSorted.enumerated().map { i, e in
            var e2 = e; e2.rank = i + 1; return e2
        }

        // SOC-DETAILS D5: 61 samples at 2 s reach the left edge of the 2-minute chart; the GPU series steps 0...30.
        var cpuHistory: [(Date, Double)] = []
        var gpuHistory: [(Date, Int?)] = []
        for i in 0..<61 {
            let t = referenceDate.addingTimeInterval(-Double(60 - i) * 2)
            cpuHistory.append((t, 12 + Double((i * 7) % 23)))
            gpuHistory.append((t, (i * 5) % 31))
        }

        var report = FullReport()
        report.createdAt = referenceDate
        report.system = SystemInfo(
            osName: "macOS", osVersion: "26.1", osBuild: "25B78",
            modelName: "MacBook Air", modelId: "Mac15,12", chip: "Apple M3",
            cores: "8 (4 performance and 4 efficiency)", memBytes: 16 * GiB,
            uptimeSeconds: 3 * 86_400 + 4 * 3600
        )
        let counted = folderSizes()
        report.homeDirs = counted.homeDirs
        report.homeCaches = counted.homeCaches
        report.serviceDirs = counted.serviceDirs
        report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
        report.tmDest = .some(nil)
        report.updates = []
        // REDESIGN-SECURITY: Security page — «checked 5 min ago», one third-party crash row and a Hidden group of two (no attention, not on the Home tile).
        report.updatesCheckedAt = referenceDate.addingTimeInterval(-5 * 60)
        report.folderSizesCountedAt = nil
        report.crashes = [CrashGroup(process: "Xcode", count: 1, directory: home + "/Library/Logs/DiagnosticReports",
                                     lastReportAt: referenceDate.addingTimeInterval(-3 * 86_400 - 2 * 3600),
                                     newestReportPath: home + "/Library/Logs/DiagnosticReports/Xcode-2026-01-12-083000.ips",
                                     reportPaths: [home + "/Library/Logs/DiagnosticReports/Xcode-2026-01-12-083000.ips"])]
        report.crashesHidden = securityHiddenCrashes(home: home, now: referenceDate)
        report.brewStatus = .installed(version: "Homebrew 4.6.0")
        report.brewOutdated = ["git", "node", "python@3.13"]
        // REDESIGN-SYSTEM: versions and the installed count for the System page's Homebrew card.
        report.brewOutdatedDetail = [BrewOutdatedPackage(name: "git", current: "2.46.0", latest: "2.47.0"),
                                     BrewOutdatedPackage(name: "node", current: "22.9.0", latest: "22.11.0"),
                                     BrewOutdatedPackage(name: "python@3.13", current: "3.13.0", latest: "3.13.1")]
        report.brewInstalledCount = 48
        report.autostart = autostart(home: home)
        report.energy = energy
        // REDESIGN-HOME: the Home "You can" chips — local snapshots (Backups) and the Full Disk Access notice.
        report.snapshots = ["com.apple.TimeMachine.2026-01-15-090000.local",
                            "com.apple.TimeMachine.2026-01-15-080000.local",
                            "com.apple.TimeMachine.2026-01-15-070000.local"]
        report.homeDirsUnreadable = [home + "/Library/Mail"]
        report.smart = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: .verified, health: internalHealth)]
        report.progress = ["homeDirs": true, "serviceDirs": true]
        report.battery = battery

        let wakeHolders = [WakeHolder(owner: "caffeinate", requester: "Terminal", ageSeconds: 5400)]

        // VISUAL-HARNESS-STALE: fresh Claude backup, 2 h before the reference date, so the
        // Settings Backups row and the Backups page's Claude card are in the baseline. Age is pinned by
        // assessing at `now: referenceDate` here and by AppModel.fixtureNow in the views.
        let claudeBackup = ClaudeBackupStatus.lastSuccess(referenceDate.addingTimeInterval(-2 * 3600))
        let claudeAttempt = ClaudeBackupAttempt(at: referenceDate.addingTimeInterval(-2 * 3600), result: .ok, mount: "/Volumes/Backup SSD")
        let claudeSize = ClaudeBackupSize(snapshotBytes: 28_548_000_000, addedBytes: 467_000_000, totalBytes: 38_654_000_000)
        let claudeJob = ClaudeBackupJob(label: "com.example.claude-backup", appPath: home + "/Applications/ClaudeBackup.app",
                                        schedule: [.init(minute: 0, hour: 13)], startsOnMount: true)

        let live = LiveSnapshot(
            t: referenceDate, load: load, cpu: cpu,
            topCPU: topCPU, topMem: topMem, mem: mem, swap: swap, disk: disk, battery: battery
        )
        let assessment = Assess.assess(report: report, live: live, language: L10nStore.shared.language, memPressure: nil, topApps: [], wakeHolders: wakeHolders,
                                       claudeBackup: claudeBackup, claudeAttempt: claudeAttempt, now: referenceDate)

        var history = HistoryState()
        var entries: [MacHistoryEntry] = []
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        let refDay = Calendar.current.startOfDay(for: referenceDate)
        for i in 0..<500 {
            let date = Calendar.current.date(byAdding: .day, value: -(499 - i), to: refDay)!
            let used = 300 + i / 5 + (i * 7) % 9
            entries.append(MacHistoryEntry(
                date: dayFormatter.string(from: date),
                disk_used_gb: used,
                disk_free_gb: 460 - used,
                battery_pct: 100 - i / 40,
                cycles: 100 + i * 2 / 3,
                // CHART-RANGE-START: Swap starts 60 days before the reference date, so Swap at 3M, 1Y and All show the «since» note.
                swap: i < 440 ? nil : "\((i * 37) % 1500 + 200)MB/2048MB",
                macos: i < 250 ? "15.6" : "26.1"
            ))
        }
        history.mac_history = entries
        history.last_run = entries.last?.date

        let fixtureTasks = HomeModel.tasks(assessment, report: report, disk: disk, battery: battery)
        let reportText = ReportWriter.render(ReportSummaryInput(
            generatedAt: referenceDate, system: report.system,
            status: HomeModel.status(scan: .ok(at: referenceDate), tasks: fixtureTasks), tasks: fixtureTasks,
            cpu: cpu, load: load, ncpu: 8, socTempC: socTempC,
            mem: mem, memPressure: .normal, swap: swap, disk: disk,
            hasBattery: true, battery: BatteryInfo.merged(live: battery, report: report.battery),
            security: report.security, claudeBackup: claudeBackup, claudeAttempt: claudeAttempt, snapshotCount: report.snapshots?.count,
            now: referenceDate, parseFailures: [],
            details: ReportDetails(report: report, live: live)),
            language: L10nStore.shared.language)

        return Dataset(
            load: load, cpu: cpu, mem: mem, swap: swap, disk: disk, battery: battery,
            socTempC: socTempC, gpuUtil: gpuUtil, topCPU: topCPU, topMem: topMem, cpuHistory: cpuHistory,
            gpuHistory: gpuHistory, socLive: referenceSocLive(),
            report: report, assessment: assessment,
            history: history, reportText: reportText, claudeBackup: claudeBackup,
            claudeAttempt: claudeAttempt, claudeSize: claudeSize, claudeJob: claudeJob
        )
    }
}

// MARK: - SoC page states (SOC-DETAILS Stage 2, design/mockups SoC.dc.html fixture bar)

extension VisualFixture {
    /// The reference page-tick state: 4P + 4E, P 3.95 GHz and E 1.27 GHz, five GPU rows at rest, 6.8 W, 8 GPU cores.
    /// Placeholder values from the reference Mac (logic 3.1, 3.5, 3.6, 3.8).
    static func referenceSocLive() -> SocLiveFixture { socLive(SocFixtureOptions()) }

    private static func performanceGroup(count: Int, firstIndex: Int) -> CoreGroup {
        CoreGroup(name: "Performance", count: count, coreIndices: Array(firstIndex..<(firstIndex + count)))
    }

    private static func efficiencyGroup(count: Int) -> CoreGroup {
        CoreGroup(name: "Efficiency", count: count, coreIndices: Array(0..<count))
    }

    /// Rows with pids 108, 101, 105, 109, 110 for the reference five (any other name gets 200...). A nil share is the
    /// "above 101 %" row, shown as "—".
    private static func gpuRows(_ rows: [(String, Double?)]) -> [GPUProcessRow] {
        let pids: [Int32] = [108, 101, 105, 109, 110]
        return rows.enumerated().map { i, r in
            GPUProcessRow(id: i < pids.count ? pids[i] : Int32(200 + i), name: r.0, sharePct: r.1)
        }
    }

    /// Launch-argument variants (read only under `-visualFixture`, pattern `gpuUnavailableRequested`) and the same
    /// values the snapshot suite sets directly. `AppModel.applySocFixture(_:)` applies them.
    struct SocFixtureOptions: Equatable {
        /// `-fixtureCores 16P+4E | 3types | unknown | notyet | unavailable`
        enum Cores: String { case reference, p16e4 = "16P+4E", threeTypes = "3types", unknown, notYet = "notyet", unavailable }
        /// `-fixtureFreq idle | unavailable | notyet`
        enum Freq: String { case reference, idle, unavailable, notYet = "notyet" }
        /// `-fixtureGPUList load | idle | longnames | empty | unavailable | notyet`
        enum GPUList: String { case reference, load, idle, longNames = "longnames", empty, unavailable, notYet = "notyet" }
        /// `-fixtureTemp warm | hot | unavailable`
        enum Temp: String { case reference, warm, hot, unavailable }
        /// `-fixtureThermal elevated | high | critical | unknown`
        enum Thermal: String { case reference, elevated, high, critical, unknown }
        /// `-fixtureCPU high | failed | notyet`
        enum CPU: String { case reference, high, failed, notYet = "notyet" }
        /// `-fixtureChart partial | gap | gpumissing | collecting | unavailable`
        enum Chart: String { case reference, partial, gap, gpuMissing = "gpumissing", collecting, unavailable }

        var cores: Cores = .reference
        var freq: Freq = .reference
        var gpuList: GPUList = .reference
        var temp: Temp = .reference
        var thermal: Thermal = .reference
        var cpu: CPU = .reference
        var chart: Chart = .reference
        /// `-fixturePower unavailable`
        var powerUnavailable = false
        /// `-fixtureWide 1`: 3-digit values (128.00 load, 128 GPU cores, 128.4 W).
        var wide = false

        /// Unknown or missing values keep the reference state.
        static func fromLaunchArguments(_ args: [String] = ProcessInfo.processInfo.arguments) -> SocFixtureOptions {
            func value(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            var o = SocFixtureOptions()
            if let v = value("-fixtureCores").flatMap(Cores.init(rawValue:)) { o.cores = v }
            if let v = value("-fixtureFreq").flatMap(Freq.init(rawValue:)) { o.freq = v }
            if let v = value("-fixtureGPUList").flatMap(GPUList.init(rawValue:)) { o.gpuList = v }
            if let v = value("-fixtureTemp").flatMap(Temp.init(rawValue:)) { o.temp = v }
            if let v = value("-fixtureThermal").flatMap(Thermal.init(rawValue:)) { o.thermal = v }
            if let v = value("-fixtureCPU").flatMap(CPU.init(rawValue:)) { o.cpu = v }
            if let v = value("-fixtureChart").flatMap(Chart.init(rawValue:)) { o.chart = v }
            o.powerUnavailable = value("-fixturePower") == "unavailable"
            o.wide = args.contains("-fixtureWide")
            return o
        }
    }

    /// Chip temperature of a variant; the reference is the dataset's 48 °C.
    static func socTempC(_ o: SocFixtureOptions, reference: Int?) -> Int? {
        switch o.temp {
        case .reference: return reference
        case .warm: return 88
        case .hot: return 97
        case .unavailable: return nil
        }
    }

    /// macOS thermal state of a variant; the reference is nominal, `.unknown` shows no thermal segment.
    static func thermal(_ o: SocFixtureOptions) -> ThermalLevel? {
        switch o.thermal {
        case .reference: return .nominal
        case .elevated: return .fair
        case .high: return .serious
        case .critical: return .critical
        case .unknown: return nil
        }
    }

    /// The page-tick state of a variant. Under `-fixtureCPU high` the cores, the E frequency and the power follow the
    /// mockup's high-load numbers (a busy Mac).
    static func socLive(_ o: SocFixtureOptions) -> SocLiveFixture {
        let high = o.cpu == .high
        func groups(_ spec: [(CoreGroup, [Int?], [Int?], Double)]) -> [CoreGroupLoad] {
            spec.map { CoreGroupLoad(group: $0.0, loads: high ? $0.2 : $0.1, frequency: frequency(o, mhz: $0.3, group: $0.0)) }
        }
        /// Deterministic busy loads for the layout the mockup has no numbers for.
        func busy(_ n: Int) -> [Int?] { (0..<n).map { 88 + ($0 * 5) % 12 } }
        let eMHz = high ? 2420.0 : 1270.0
        var f = SocLiveFixture()
        switch o.cores {
        case .reference, .notYet, .unavailable:
            f.cores = groups([(performanceGroup(count: 4, firstIndex: 4), [13, 1, 2, 1], [98, 96, 99, 97], 3950),
                              (efficiencyGroup(count: 4), [14, 14, 9, 6], [91, 88, 93, 90], eMHz)])
        case .p16e4:
            f.cores = groups([(performanceGroup(count: 16, firstIndex: 4),
                               [62, 8, 3, 41, 12, 0, 5, 1, 77, 2, nil, 9, 4, 15, 1, 6], busy(16), 3950),
                              (efficiencyGroup(count: 4), [21, 17, 9, 11], [93, 90, 88, 95], eMHz)])
        case .threeTypes:
            f.cores = groups([(CoreGroup(name: "Super", count: 2, coreIndices: [8, 9]), [41, 7], [97, 95], 4100),
                              (performanceGroup(count: 4, firstIndex: 4), [13, 1, 2, 1], [98, 96, 99, 97], 3950),
                              (efficiencyGroup(count: 4), [14, 14, 9, 6], [91, 88, 93, 90], eMHz)])
        case .unknown:
            // Type unknown (logic 3.1): one unnamed group, no frequency channel.
            f.cores = [CoreGroupLoad(group: CoreGroup(name: nil, count: 8, coreIndices: Array(0..<8)),
                                     loads: high ? [91, 88, 93, 90, 98, 96, 99, 97] : [14, 14, 9, 6, 13, 1, 2, 1],
                                     frequency: .unavailable)]
        }
        if o.cores == .notYet || o.cores == .unavailable {
            f.cores = f.cores?.map { CoreGroupLoad(group: $0.group, loads: Array(repeating: nil, count: $0.group.count),
                                                    frequency: $0.frequency) }
            f.hasCoreReading = o.cores != .notYet
            f.coreLoadsFailed = o.cores == .unavailable
        }
        switch o.gpuList {
        case .reference:
            f.gpuRows = .rows(gpuRows([("Terminal", 0.2), ("WindowServer", 0.2), ("Finder", 0), ("Dock", 0), ("loginwindow", 0)]))
        case .load:
            f.gpuRows = .rows(gpuRows([("gpu-bench", 61.4), ("WindowServer", 8.2), ("Terminal", 0.6), ("Dock", 0.1), ("Finder", 0)]))
        case .idle:
            f.gpuRows = .rows(gpuRows([("WindowServer", 0), ("Terminal", 0), ("Finder", 0), ("Dock", 0), ("loginwindow", 0)]))
        case .longNames:
            f.gpuRows = .rows(gpuRows([("com.apple.appkit.xpc.openAndSavePanelService", 1.2), ("ThemeWidgetContr", 0.4),
                                       ("WindowServer", nil), ("Terminal", 0.2), ("Finder", 0)]))
        case .empty: f.gpuRows = .empty
        case .unavailable: f.gpuRows = .unavailable
        case .notYet: f.gpuRows = .notYet
        }
        f.powerW = o.powerUnavailable ? nil : (o.wide ? 128.4 : (high ? 14.1 : 6.8))
        f.gpuCoreCount = o.wide ? 128 : 8
        return f
    }

    /// Frequency of one group in a variant. The reference E is 1.27 GHz, P 3.95 GHz; `-fixtureFreq idle` idles P only
    /// (the E cores are active even at rest, logic 3.8). A group of unknown type has no channel.
    private static func frequency(_ o: SocFixtureOptions, mhz: Double, group: CoreGroup) -> FrequencyState {
        switch o.freq {
        case .reference: return .mhz(mhz)
        case .idle: return group.name?.hasPrefix("Efficiency") == true ? .mhz(mhz) : .idle
        case .unavailable: return .unavailable
        case .notYet: return .notYet
        }
    }

    /// Load average of a variant (3 digits before the decimal point under `wide`).
    static func loadAverage(_ o: SocFixtureOptions, reference: [Double]) -> [Double] {
        if o.wide { return [128.00, 96.41, 64.12] }
        return o.cpu == .high ? [3.13, 2.50, 2.04] : reference
    }

    /// The history of a variant: `partial` keeps the newest 20 samples, `gap` removes 10 in the middle, `collecting`
    /// keeps one, `gpumissing` turns every GPU value into nil, `unavailable` has no CPU value and nil GPU values.
    static func socHistory(_ o: SocFixtureOptions, cpu: [(Date, Double)], gpu: [(Date, Int?)])
        -> (cpu: [(Date, Double)], gpu: [(Date, Int?)]) {
        func shape<T>(_ a: [T]) -> [T] {
            switch o.chart {
            case .reference, .gpuMissing, .unavailable: return a
            case .partial: return Array(a.suffix(20))
            case .gap: return Array(a.prefix(20)) + Array(a.dropFirst(30))
            case .collecting: return Array(a.suffix(1))
            }
        }
        let gpuShaped = shape(gpu)
        let gpuNil = o.chart == .gpuMissing || o.chart == .unavailable
        return (o.chart == .unavailable ? [] : shape(cpu), gpuNil ? gpuShaped.map { ($0.0, nil) } : gpuShaped)
    }
}
