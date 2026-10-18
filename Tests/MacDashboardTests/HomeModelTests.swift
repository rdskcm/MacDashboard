// Tests/MacDashboardTests/HomeModelTests.swift
// REDESIGN-HOME stage A: the Home derivations (tasks, status, scan, chips, tiles, small helpers).
import Foundation
import Testing
@testable import MacDashboard

private func homeBadFixture(diskPct: Double) -> (FullReport, LiveSnapshot) {
    var report = FullReport()
    report.security = SecurityState(fileVault: false, gatekeeper: false, sip: false, firewall: false)
    report.updates = ["macOS Tahoe 26.1.1-25B90"]
    report.crashes = [CrashGroup(process: AppInfo.name, count: 2, directory: userCrashDir)]
    report.tmDest = .some(.none)
    report.smart = [
        SmartDisk(device: "internal", title: "Boot SSD", status: "SMART: ошибки носителя",
                  attrs: [("Media and Data Integrity Errors", "3")], severity: .crit),
        SmartDisk(device: "/dev/disk4", title: "External SSD", status: "SMART: износ на исходе",
                  attrs: [("Percentage Used", "85")], severity: .warn),
    ]
    report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: 400, condition: "Replace Now", maxCapacity: 60)
    report.brewOutdated = ["a", "b", "c"]
    var live = LiveSnapshot()
    let size: Int64 = 256 * GIB
    live.disk = DiskInfo(size: size, avail: Int64(Double(size) * (1 - diskPct)), dataUsed: nil, sysUsed: nil)
    live.swap = SwapInfo(total: 8 * GIB, used: 5 * GIB, free: 3 * GIB)
    live.mem = memFixture(total: 16 * GIB)
    return (report, live)
}

private func homeAssess(_ report: FullReport, _ live: LiveSnapshot, wake: Bool = true) -> Assessment {
    Assess.assess(report: report, live: live, memPressure: .critical,
                  wakeHolders: wake ? [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)] : [],
                  claudeBackup: .noSuccessFound)
}

private func homeInput(_ report: FullReport, _ live: LiveSnapshot, assessment: Assessment? = nil,
                       scan: BlockState = BlockState(.scan), hasBattery: Bool = true,
                       history: [MacHistoryEntry] = [], now: Date = Date()) -> HomeInput {
    HomeInput(assessment: assessment ?? homeAssess(report, live), report: report, scan: scan,
              load: [2.1, 1, 1], ncpu: 8, processCount: 412, mem: live.mem, swap: live.swap, disk: live.disk,
              hasBattery: hasBattery, battery: live.battery, system: SystemInfo(chip: "Apple M3", memBytes: 16 * GIB),
              claudeBackup: nil, backupStaleHours: 24, history: history, now: now)
}

private func dayString(_ offset: Int, from base: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = .current; df.dateFormat = "yyyy-MM-dd"
    return df.string(from: Calendar.current.date(byAdding: .day, value: offset, to: base)!)
}

extension SerialTests {
    struct HomeModelTests {
        @Test func taskTable() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            var seen = Set<AttentionKind>()
            for pct in [0.94, 0.80] {
                let (report, live) = homeBadFixture(diskPct: pct)
                let a = homeAssess(report, live)
                let tasks = HomeModel.tasks(a, report: report, disk: live.disk, battery: live.battery)
                #expect(tasks.map(\.id) == a.items.map(\.id), "tasks keep assessment order")
                for t in tasks {
                    seen.insert(t.kind)
                    let item = a.items.first { $0.id == t.id }!
                    #expect(t.tone == ((item.sev == .crit || item.sev == .serious) ? .hot : .amber), "tone \(t.kind)")
                    let expected: (Page, CardID, String?)
                    switch t.kind {
                    case .firewallOff: expected = (.security, .protect, L.commonEnable)
                    case .smartErrors: expected = (.storage, .smart, L.homeVerbDetails)
                    case .diskFull, .diskFullSoon: expected = (.storage, .disk, L.homeVerbFreeUp)
                    case .timeMachine: expected = (.backups, .tm, L.commonSetUp)
                    case .wakeHolders: expected = (.system, .sleep, L.commonShow)
                    case .batteryCapacity, .batteryCondition: expected = (.battery, .bathero, L.homeVerbDetails)
                    case .brewOutdated: expected = (.system, .brew, L.homeVerbUpdate)
                    case .updates: expected = (.security, .updates, L.commonInstall)
                    case .swapHigh: expected = (.memory, .usage, L.commonShow)
                    case .fileVaultOff: expected = (.security, .protect, L.homeVerbSettings)
                    case .gatekeeperOff: expected = (.security, .protect, L.commonEnable)
                    case .sipOff: expected = (.security, .protect, nil)
                    case .crashes: expected = (.security, .crashes, L.commonShow)
                    case .smartWear: expected = (.storage, .smart, L.homeVerbDetails)
                    case .claudeBackup: expected = (.backups, .claude, L.commonShow)
                    }
                    #expect(t.section == expected.0 && t.destination == Destination(expected.0, focus: expected.1), "section/focus \(t.kind)")
                    #expect(t.verb == expected.2, "verb \(t.kind)")
                    if t.kind == .sipOff { #expect(t.help == L.homeSipHelp, "sip help") } else { #expect(t.help == item.fullText, "help \(t.kind)") }
                }
            }
            #expect(seen == Set(AttentionKind.allCases), "all 17 kinds exercised (got \(seen.count))")

            let (report, live) = homeBadFixture(diskPct: 0.94)
            let tasks = HomeModel.tasks(homeAssess(report, live), report: report, disk: live.disk, battery: live.battery)
            func state(_ k: AttentionKind) -> (String, String)? { tasks.first { $0.kind == k }.map { ($0.object, $0.state) } }
            #expect(state(.diskFull)?.1 == "94% full", "disk state")
            #expect(state(.wakeHolders)?.0 == "caffeinate", "wake object")
            #expect(state(.updates)?.0 == "macOS 26.1.1" && state(.updates)?.1 == "update available", "updates object/state")
            #expect(state(.brewOutdated)?.1 == "3 packages outdated", "brew state")
            #expect(state(.batteryCondition)?.1 == L.commonServiceRecommended, "battery condition state")
            #expect(state(.crashes)?.1 == "2 reports", "crashes state")
            #expect(state(.smartWear)?.1 == "85%", "smart wear state")
        }

        @Test func updateObject() {
            #expect(HomeModel.updateObject(["macOS Tahoe 26.1.1-25B90"]) == "macOS 26.1.1")
            #expect(HomeModel.updateObject(["Safari18.4-18.4"]) == "Safari18.4")
            #expect(HomeModel.updateObject([]) == "macOS")
            #expect(HomeModel.updateObject(["a", "b"]) == "macOS")
            #expect(HomeModel.updateObject(nil) == "macOS")
        }

        @Test func status() {
            let (report, live) = homeBadFixture(diskPct: 0.80)
            let tasks = HomeModel.tasks(homeAssess(report, live), report: report, disk: live.disk, battery: live.battery)
            let amberOnly = tasks.filter { $0.tone == .amber }
            let now = Date()
            #expect(HomeModel.status(scan: .firstScan, tasks: tasks) == .checking)
            #expect(HomeModel.status(scan: .ok(at: now), tasks: []) == .good)
            #expect(HomeModel.status(scan: .ok(at: now), tasks: amberOnly) == .attention)
            #expect(HomeModel.status(scan: .ok(at: now), tasks: tasks) == .critical)
            #expect(HomeModel.status(scan: .refreshing(lastGoodAt: now), tasks: amberOnly) == .attention)
        }

        @Test func scan() {
            var s = BlockState(.scan)
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            #expect(HomeModel.scan(s) == .firstScan)
            s.begin(at: t0, showsLoading: false)
            s.succeed(at: t0)
            #expect(HomeModel.scan(s) == .ok(at: t0))
            s.begin(at: t0, showsLoading: true)
            #expect(HomeModel.scan(s) == .refreshing(lastGoodAt: t0))
            s.fail(.timedOut)
            #expect(HomeModel.scan(s) == .failed(.timedOut, lastGoodAt: t0))
        }

        @Test func chips() {
            let (r, live) = homeBadFixture(diskPct: 0.80)
            var report = r
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            report.homeDirs = [DirSize(path: home + "/Downloads", bytes: 14 * GIB),
                               DirSize(path: home + "/.Trash", bytes: GIB + GIB / 2)]
            report.serviceDirs = [DirSize(path: home + "/Library/Caches", bytes: 4 * GIB + GIB / 5)]
            report.snapshots = ["a", "b", "c"]
            report.homeDirsUnreadable = ["/x"]
            let chips = HomeModel.chips(homeInput(report, live))
            #expect(chips.map(\.id) == ["freeUp", "snapshots", "brew", "fda"])
            let sum = 14 * GIB + GIB + GIB / 2 + 4 * GIB + GIB / 5
            #expect(chips[0].value == fmtBytes(sum))
            #expect(chips[1].value == "3" && chips[2].value == L.homeBrewOutdatedShort(3) && chips[3].value == nil)
            #expect(chips[0].destination == Destination(.storage, focus: .folders, foldersSegment: .home))
            report.homeDirs = [DirSize(path: home + "/Downloads", bytes: 5 * GIB)]
            report.serviceDirs = []
            #expect(!HomeModel.chips(homeInput(report, live)).contains { $0.id == "freeUp" }, "5 GiB Downloads: no chip")
        }

        @Test func tiles() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            var (report, live) = homeBadFixture(diskPct: 0.80)
            report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
            report.crashes = []; report.updates = []
            let input = homeInput(report, live)
            let tasks = HomeModel.tasks(input.assessment, report: report, disk: live.disk, battery: live.battery)
            let now = Date()
            let tiles = HomeModel.tiles(input, tasks: tasks, scan: .ok(at: now))
            #expect(tiles.count == 8)
            #expect(HomeModel.tiles(homeInput(report, live, hasBattery: false), tasks: tasks, scan: .ok(at: now)).count == 7)
            let sec = tiles.first { $0.page == .security }!
            #expect(sec.tagTone == .hot && sec.tagText == "Firewall off" && sec.hotRing)
            #expect(sec.destination == Destination(.security, focus: .protect))
            let stor = tiles.first { $0.page == .storage }!
            #expect(stor.tagTone == .hot && stor.tagText == "drive failing", "storage tag from its first (hottest) task")
            let cpu = tiles.first { $0.page == .cpu }!
            #expect(cpu.kvs[0].value == fmtFixed(2.1, decimals: 2) && cpu.kvs[1].value == "412" && cpu.sub == "Apple M3 · 8 cores")

            let skel = HomeModel.tiles(input, tasks: tasks, scan: .firstScan)
            #expect(skel.allSatisfy { $0.skeleton && !$0.hotRing && $0.kvs.allSatisfy { $0.value == "—" } })

            var comps = DateComponents(); comps.year = 2026; comps.month = 10; comps.day = 18; comps.hour = 9; comps.minute = 12
            let lastGood = Calendar.current.date(from: comps)!
            let failed = HomeModel.tiles(input, tasks: tasks, scan: .failed(.timedOut, lastGoodAt: lastGood))
            #expect(failed.allSatisfy { $0.sub == "last check 09:12" && $0.subIsFailure })
            let failedNoGood = HomeModel.tiles(input, tasks: tasks, scan: .failed(.timedOut, lastGoodAt: nil))
            #expect(failedNoGood.allSatisfy { !$0.subIsFailure })
        }

        @Test func protectionOn() {
            #expect(HomeModel.protectionOn(nil) == nil)
            #expect(HomeModel.protectionOn(SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)) == 4)
            #expect(HomeModel.protectionOn(SecurityState(fileVault: true, gatekeeper: true, sip: nil, firewall: false)) == 2)
        }

        @Test func monthlyRateAndSigned() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            let base = Date()
            let rising: [MacHistoryEntry] = (0..<91).map {
                MacHistoryEntry(date: dayString($0 - 90, from: base), disk_used_gb: 100 + $0, disk_free_gb: nil,
                                battery_pct: nil, cycles: nil, swap: nil, macos: nil)
            }
            let rate = HomeModel.monthlyRate(rising) { $0.disk_used_gb }
            #expect(rate != nil && abs(rate! - 30) < 0.01, "1 GB/day = +30 per month (got \(String(describing: rate)))")
            #expect(HomeModel.monthlyRate(rising) { $0.battery_pct } == nil, "no values")
            let close = [rising[0], rising[10]]
            #expect(HomeModel.monthlyRate(close) { $0.disk_used_gb } == nil, "10 days apart")
            #expect(HomeModel.monthlyRate([rising[0]]) { $0.disk_used_gb } == nil, "one entry")
            L10nStore.shared.language = .en
            #expect(HomeModel.signed(-1.23, decimals: 1) == "\u{2212}1.2")
            #expect(HomeModel.signed(30, decimals: 0) == "+30")
            #expect(HomeModel.signed(0, decimals: 0) == "0")
            L10nStore.shared.language = .ru
            #expect(HomeModel.signed(-1.23, decimals: 1) == "\u{2212}1,2")
        }

        @Test func plurals() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .ru
            #expect([1, 3, 5, 11, 21].map { L.homeTaskCount($0) } == ["1 задача", "3 задачи", "5 задач", "11 задач", "21 задача"])
            #expect(L.homeStateReports(4) == "4 отчёта")
            #expect(L.homeStatePackagesOutdated(3) == "3 пакета устарели")
            #expect(L.homeHistoryDays(98) == "98 дней")
            #expect(L.homeCPUSub("Apple M3", 8) == "Apple M3 · 8 ядер")
            L10nStore.shared.language = .en
            #expect(L.homeTaskCount(1) == "1 task" && L.homeTaskCount(5) == "5 tasks")
            #expect(L.homeScanFailed(timedOut: false, lastGood: "09:12") == "Couldn’t scan this Mac: system_profiler returned no data. Showing data from 09:12.")
        }

        @Test func processCount() async {
            let r = await LiveCollector().sampleProcesses(limit: 8)
            #expect(r.processCount > 0 && r.processCount >= r.topCPU.count, "processCount \(r.processCount)")
        }
    }
}
