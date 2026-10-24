// Engine/VisualFixture.swift
// VISUAL-COVERAGE: a pure, fixed dataset used both by the real app (via a launch
// argument, `DashboardModel+VisualFixture.swift`) and by the offscreen content
// render stage (`tools/visual/content_states.swift`), so `main-*` and every
// `content-*` visual reference is built from the same deterministic input
// instead of live machine state. No `Date()`, no random — only the user's
// home-directory path (needed so home-relative paths look real).

import Foundation

enum VisualFixture {
    /// HARNESS-REDESIGN-RETARGET: test hook. The offscreen snapshot suite cannot add a launch argument to its
    /// own process, so it sets this for the duration of its render (and restores it). Never set by the app.
    static var forced = false

    /// `-visualFixture` on the command line (or `forced` in the snapshot tests) requests fixture mode.
    static var isRequested: Bool {
        forced || ProcessInfo.processInfo.arguments.contains("-visualFixture")
    }

    /// Always in the past, so `reportUpdatedTimeString` takes its stable
    /// "date + time" branch (not the "same day as now" time-only branch).
    static let referenceDate: Date = Calendar.current.date(
        from: DateComponents(year: 2026, month: 1, day: 15, hour: 10, minute: 30)
    )!

    /// REDESIGN-CPU: fixed process details for the expanded-row states (fixture pids: WindowServer 101, Xcode 103).
    static let procDetailWindowServer = ProcDetail(path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", owner: "_windowserver")
    static let procDetailXcode = ProcDetail(path: "/Applications/Xcode.app/Contents/MacOS/Xcode", owner: "ivan")

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
        device: "/dev/disk4", title: "External SSD", status: "FAILING",
        attrs: [("Critical Warning", "0x01"), ("Media and Data Integrity Errors", "27"), ("Percentage Used", "104%")],
        severity: .crit,
        health: SmartHealth(
            temperatureC: 72, percentageUsed: 104, availableSpare: 4, spareThreshold: 10, powerOnHours: 9812,
            powerCycles: 1406, unsafeShutdowns: 31, dataUnitsRead: 80_664_062, dataUnitsWritten: 231_640_625,
            mediaErrors: 27, errorLogEntries: 112, criticalWarning: 1))

    /// REDESIGN-SECURITY: sample updates for the Security page snapshot states (the fixture report keeps `updates = []`).
    // REDESIGN-SYSTEM: the System page fixtures (Sleep, Startup items, Energy settings).
    static func autostart(home: String) -> AutostartInfo {
        func info(_ path: String, orphan: Bool = false, description: String? = nil, exe: String? = nil) -> LaunchdPlistInfo {
            LaunchdPlistInfo(path: path, label: nil, executablePath: exe, isOrphan: orphan, description: description)
        }
        let user = home + "/Library/LaunchAgents/"
        return AutostartInfo(
            loginItems: ["Claude", "Rectangle", "Dropbox", "iStat Menus"],
            userAgents: [info(user + "com.google.keystone.agent.plist"),
                         info(user + "com.dropbox.DropboxMacUpdate.agent.plist"),
                         info(user + "homebrew.mxcl.postgresql@14.plist", orphan: true, description: "PostgreSQL 14 server",
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

    /// One fixed, pure snapshot of everything a `DashboardModel` normally
    /// collects live.
    struct Dataset {
        var load: [Double]
        var cpu: CPUUsage
        var mem: MemSnapshot
        var swap: SwapInfo
        var disk: DiskInfo
        var battery: BatteryInfo
        var socTempC: Int?
        var topCPU: [ProcEntry]
        var topMem: [ProcEntry]
        var cpuHistory: [(Date, Double)]
        var report: FullReport
        var wakeHolders: [WakeHolder]
        var assessment: Assessment
        var history: HistoryState
        var reportText: String
        var claudeBackup: ClaudeBackupStatus
    }

    static func make() -> Dataset {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let load: [Double] = [2.10, 1.85, 1.60]
        let cpu = CPUUsage(user: 18.5, sys: 7.2, idle: 74.3)
        let socTempC = 48

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
            source: "AC Power", charge: 82, state: "charging",
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

        var cpuHistory: [(Date, Double)] = []
        for i in 0..<60 {
            let t = referenceDate.addingTimeInterval(-Double(59 - i) * 2)
            cpuHistory.append((t, 12 + Double((i * 7) % 23)))
        }

        var report = FullReport()
        report.createdAt = referenceDate
        report.system = SystemInfo(
            osName: "macOS", osVersion: "26.1", osBuild: "25B78",
            modelName: "MacBook Air", modelId: "Mac15,12", chip: "Apple M3",
            cores: "8 (4 performance and 4 efficiency)", memBytes: 16 * GiB,
            uptime: "3 days 4 hours", hostName: "fixture-mac"
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
        report.smart = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: "VERIFIED", health: internalHealth)]
        report.progress = ["homeDirs": true, "serviceDirs": true]
        report.battery = battery

        let wakeHolders = [WakeHolder(owner: "caffeinate", requester: "Terminal", ageSeconds: 5400)]

        // VISUAL-HARNESS-STALE: fresh Claude backup, 2 h before the reference date, so the
        // Settings Backups row and the Backups page's Claude card are in the baseline. Age is pinned by
        // assessing at `now: referenceDate` here and by DashboardModel.fixtureNow in the views.
        let claudeBackup = ClaudeBackupStatus.lastSuccess(referenceDate.addingTimeInterval(-2 * 3600))

        let live = LiveSnapshot(
            t: referenceDate, load: load, cpu: cpu,
            topCPU: topCPU, topMem: topMem, mem: mem, swap: swap, disk: disk, battery: battery
        )
        let assessment = Assess.assess(report: report, live: live, memPressure: nil, topApps: [], wakeHolders: wakeHolders,
                                       claudeBackup: claudeBackup, now: referenceDate)

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
                swap: "\((i * 37) % 1500 + 200)MB/2048MB",
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
            security: report.security, claudeBackup: claudeBackup, snapshotCount: report.snapshots?.count,
            now: referenceDate, parseFailures: [],
            details: ReportDetails(report: report, live: live)))

        return Dataset(
            load: load, cpu: cpu, mem: mem, swap: swap, disk: disk, battery: battery,
            socTempC: socTempC, topCPU: topCPU, topMem: topMem, cpuHistory: cpuHistory,
            report: report, wakeHolders: wakeHolders, assessment: assessment,
            history: history, reportText: reportText, claudeBackup: claudeBackup
        )
    }
}
