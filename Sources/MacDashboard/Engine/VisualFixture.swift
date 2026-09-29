// Engine/VisualFixture.swift
// VISUAL-COVERAGE: a pure, fixed dataset used both by the real app (via a launch
// argument, `DashboardModel+VisualFixture.swift`) and by the offscreen content
// render stage (`tools/visual/content_states.swift`), so `main-*` and every
// `content-*` visual reference is built from the same deterministic input
// instead of live machine state. No `Date()`, no random — only the user's
// home-directory path (needed so home-relative paths look real).

import Foundation

enum VisualFixture {
    /// `-visualFixture` on the command line requests fixture mode.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-visualFixture")
    }

    /// Always in the past, so `reportUpdatedTimeString` takes its stable
    /// "date + time" branch (not the "same day as now" time-only branch).
    static let referenceDate: Date = Calendar.current.date(
        from: DateComponents(year: 2026, month: 1, day: 15, hour: 10, minute: 30)
    )!

    private static let GiB: Int64 = 1 << 30

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

        let disk = DiskInfo(size: 460 * GiB, avail: 60 * GiB, dataUsed: nil, sysUsed: nil)

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
        report.homeDirs = [
            DirSize(path: home + "/Downloads", bytes: 14 * GiB),
            DirSize(path: home + "/Library", bytes: 22 * GiB),
            DirSize(path: home + "/Documents", bytes: 9 * GiB),
            DirSize(path: home + "/Pictures", bytes: 6 * GiB),
            DirSize(path: home + "/Movies", bytes: 4 * GiB),
            DirSize(path: home + "/.Trash", bytes: Int64(1.5 * Double(GiB))),
            DirSize(path: home + "/Desktop", bytes: Int64(0.8 * Double(GiB))),
            DirSize(path: home + "/Music", bytes: Int64(0.5 * Double(GiB))),
        ]
        report.serviceDirs = [
            DirSize(path: home + "/Library/Caches", bytes: Int64(4.2 * Double(GiB))),
            DirSize(path: home + "/Library/Application Support", bytes: Int64(7.5 * Double(GiB))),
            DirSize(path: home + "/Library/Containers", bytes: Int64(5.1 * Double(GiB))),
            DirSize(path: "/Library/Caches", bytes: Int64(1.1 * Double(GiB))),
        ]
        report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
        report.tmDest = .some(nil)
        report.updates = []
        report.updatesCheckedAt = nil
        report.folderSizesCountedAt = nil
        report.crashes = []
        report.brewStatus = .installed(version: "Homebrew 4.6.0")
        report.brewOutdated = ["git", "node", "python@3.13"]
        report.smart = [SmartDisk(device: "internal", title: "APPLE SSD AP0512Z", status: "VERIFIED")]
        report.progress = ["homeDirs": true, "serviceDirs": true]
        report.battery = battery

        let wakeHolders = [WakeHolder(owner: "caffeinate", requester: "Terminal", ageSeconds: 5400)]

        let live = LiveSnapshot(
            t: referenceDate, load: load, cpu: cpu,
            topCPU: topCPU, topMem: topMem, mem: mem, swap: swap, disk: disk, battery: battery
        )
        let assessment = Assess.assess(report: report, live: live, memPressure: nil, topApps: [], wakeHolders: wakeHolders)

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

        let reportText = """
        MacDashboard report (visual fixture)

        System
        ------
        macOS 26.1 (25B78) on MacBook Air (Mac15,12)
        Chip: Apple M3 — 8 (4 performance and 4 efficiency)
        Memory: 16 GB
        Uptime: 3 days 4 hours
        Host: fixture-mac
        SoC temperature: 48°C

        CPU / Load
        ----------
        Load average: 2.10, 1.85, 1.60
        User 18.5% · System 7.2% · Idle 74.3%
        Top CPU: WindowServer 14.2%, Safari 9.8%, Xcode 7.5%, Mail 3.1%

        Memory
        ------
        Total 16.0 GB, free 1.2 GB
        Active 6.0 GB · Inactive 4.5 GB · Wired 2.5 GB
        Compressor 1.0 GB · Purgeable 0.2 GB · File-backed 3.0 GB
        Swap: 512 MB used of 2.0 GB

        Disk
        ----
        Volume size 460 GB, 60 GB available
        Home folders: Downloads 14 GB, Library 22 GB, Documents 9 GB, Pictures 6 GB
        Service folders: Caches 4.2 GB, Application Support 7.5 GB, Containers 5.1 GB

        Battery
        -------
        Source: AC Power (charging)
        Charge: 82% · Cycles: 312 · Condition: Normal
        Max capacity: 76%

        Security
        --------
        FileVault: on · Gatekeeper: on · SIP: on
        Firewall: off

        Homebrew
        --------
        Homebrew 4.6.0 — outdated: git, node, python@3.13

        Storage health
        --------------
        internal (APPLE SSD AP0512Z): VERIFIED

        Wake holders
        ------------
        caffeinate holds the system awake for Terminal (1h 30m)

        This is a fixed fixture report used only for the visual baseline; it does
        not reflect this Mac's real state.
        """

        return Dataset(
            load: load, cpu: cpu, mem: mem, swap: swap, disk: disk, battery: battery,
            socTempC: socTempC, topCPU: topCPU, topMem: topMem, cpuHistory: cpuHistory,
            report: report, wakeHolders: wakeHolders, assessment: assessment,
            history: history, reportText: reportText
        )
    }
}
