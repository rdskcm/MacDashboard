// Tests/MacDashboardTests/HomeModelTests.swift
// REDESIGN-HOME stage A: the Home derivations (tasks, status, scan, chips, tiles, small helpers).
import Foundation
import Testing
@testable import MacDashboard

private func homeBadFixture(diskPct: Double) -> (FullReport, LiveSnapshot) {
    var report = FullReport()
    report.security = SecurityState(fileVault: false, gatekeeper: false, sip: false, firewall: false)
    report.updates = [upd("macOS Tahoe 26.1.1-25B90")]
    report.crashes = [CrashGroup(process: AppInfo.name, count: 2, directory: userCrashDir)]
    report.tmDest = .some(.none)
    report.smart = [
        SmartDisk(device: "internal", title: "Boot SSD", status: .mediaErrors,
                  attrs: [("Media and Data Integrity Errors", "3")], severity: .crit),
        SmartDisk(device: "/dev/disk4", title: "External SSD", status: .wearHigh,
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

private let tmLate: TMDestination = {
    var d = TMDestination(name: "Backup", kind: "Local", mountPoint: "/Volumes/B", quotaBytes: nil, lastBackup: nil)
    d.lastBackupDate = Date().addingTimeInterval(-10 * 86_400)
    return d
}()

@MainActor private func homeAssess(_ report: FullReport, _ live: LiveSnapshot, wake: Bool = true) -> Assessment {
    Assess.assess(report: report, live: live, language: L10nStore.shared.language, memPressure: .critical,
                  wakeHolders: wake ? [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)] : [],
                  claudeBackup: .noSuccessFound)
}

@MainActor private func homeInput(_ report: FullReport, _ live: LiveSnapshot, assessment: Assessment? = nil,
                       scan: BlockState = BlockState(.scan), hasBattery: Bool = true,
                       history: [MacHistoryEntry] = [], now: Date = Date()) -> HomeInput {
    HomeInput(assessment: assessment ?? homeAssess(report, live), report: report, scan: scan,
              load: [2.1, 1, 1], ncpu: 8, processCount: 412, mem: live.mem, swap: live.swap, disk: live.disk,
              hasBattery: hasBattery, battery: live.battery, system: SystemInfo(chip: "Apple M3", memBytes: 16 * GIB),
              claudeBackup: nil, backupStaleHours: 24, lowSpacePercent: AppSettings.defaultLowSpacePercent, history: history, now: now)
}

private func dayString(_ offset: Int, from base: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = .current; df.dateFormat = "yyyy-MM-dd"
    return df.string(from: Calendar.current.date(byAdding: .day, value: offset, to: base)!)
}

extension SerialTests {
    @MainActor struct HomeModelTests {
        @Test func taskTable() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            var seen = Set<AttentionKind>()
            for pct in [0.94, 0.87] {
                var (report, live) = homeBadFixture(diskPct: pct)
                // No report holds both TM kinds: the 0.87 pass carries the overdue one (D7).
                if pct == 0.87 { report.tmDest = .some(.some(tmLate)) }
                if pct == 0.87 { report.battery?.condition = "Normal" }   // service supersedes worn (BATTERY-HEALTH-UNIFY): this pass raises batteryCapacity
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
                    case .timeMachineOverdue: expected = (.backups, .tm, L.commonShow)
                    case .wakeHolders: expected = (.system, .sleep, L.commonShow)
                    case .batteryCapacity, .batteryCondition: expected = (.battery, .bathero, L.homeVerbDetails)
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
                    if t.kind == .sipOff { #expect(t.help == L.homeSipHelp + " " + L.attnWhySip, "sip help") } else { #expect(t.help == item.fullTextWithWhy, "help \(t.kind)") }
                    if t.kind == .timeMachineOverdue { #expect(t.tileTag == L.bkTagOverdue, "tag \(t.kind)") }
                }
            }
            #expect(seen == Set(AttentionKind.allCases), "all kinds exercised (got \(seen.count))")

            let (report, live) = homeBadFixture(diskPct: 0.94)
            let tasks = HomeModel.tasks(homeAssess(report, live), report: report, disk: live.disk, battery: live.battery)
            func state(_ k: AttentionKind) -> (String, String)? { tasks.first { $0.kind == k }.map { ($0.object, $0.state) } }
            #expect(state(.diskFull)?.1 == "94% full", "disk state")
            #expect(state(.wakeHolders)?.0 == "caffeinate", "wake object")
            #expect(state(.updates)?.0 == "macOS 26.1.1" && state(.updates)?.1 == "update available", "updates object/state")
            #expect(state(.batteryCondition)?.1 == L.commonServiceRecommended, "battery condition state")
            #expect(state(.crashes)?.1 == "2 reports", "crashes state")
            #expect(state(.smartWear)?.1 == "85%", "smart wear state")
            var (lateReport, lateLive) = homeBadFixture(diskPct: 0.87)
            lateReport.tmDest = .some(.some(tmLate))
            let lateTasks = HomeModel.tasks(homeAssess(lateReport, lateLive), report: lateReport, disk: lateLive.disk, battery: lateLive.battery)
            #expect(lateTasks.first { $0.kind == .timeMachineOverdue }?.state == "10 days ago", "TM overdue state")
        }

        @Test func updateObject() {
            #expect(HomeModel.updateObject(["macOS Tahoe 26.1.1-25B90"]) == "macOS 26.1.1")
            #expect(HomeModel.updateObject(["Safari18.4-18.4"]) == "Safari18.4")
            #expect(HomeModel.updateObject([]) == "macOS")
            #expect(HomeModel.updateObject(["a", "b"]) == "macOS")
            #expect(HomeModel.updateObject(nil) == "macOS")
        }

        @Test func status() {
            let (report, live) = homeBadFixture(diskPct: 0.87)
            let tasks = HomeModel.tasks(homeAssess(report, live), report: report, disk: live.disk, battery: live.battery)
            let amberOnly = tasks.filter { $0.tone == .amber }
            let now = Date()
            #expect(HomeModel.status(scan: .firstScan, tasks: tasks) == .checking)
            #expect(HomeModel.status(scan: .ok(at: now), tasks: []) == .good)
            #expect(HomeModel.status(scan: .ok(at: now), tasks: amberOnly) == .attention)
            #expect(HomeModel.status(scan: .ok(at: now), tasks: tasks) == .critical)
            #expect(HomeModel.status(scan: .refreshing(lastGoodAt: now), tasks: amberOnly) == .attention)
            var fwReport = FullReport()
            fwReport.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
            let fwA = Assess.assess(report: fwReport, live: LiveSnapshot(), language: L10nStore.shared.language)
            let fwTasks = HomeModel.tasks(fwA, report: fwReport, disk: nil, battery: nil)
            #expect(fwTasks.map(\.kind) == [.firewallOff] && HomeModel.status(scan: .ok(at: now), tasks: fwTasks) == .attention,
                    "a firewall-only task list is attention, not critical")
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
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            let (r, live) = homeBadFixture(diskPct: 0.87)   // 13 % free: low, so the snapshots chip shows
            var report = r
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            report.homeDirs = [DirSize(path: home + "/Downloads", bytes: 14 * GIB),
                               DirSize(path: home + "/.Trash", bytes: GIB + GIB / 2)]
            report.homeCaches = DirSize(path: home + "/Library/Caches", bytes: 4 * GIB + GIB / 5)
            report.snapshots = ["a", "b", "c"]
            report.homeDirsUnreadable = ["/x"]
            let chips = HomeModel.chips(homeInput(report, live))
            #expect(chips.map(\.id) == ["freeUp", "snapshots", "brew", "fda"])
            let sum = 14 * GIB + GIB + GIB / 2 + 4 * GIB + GIB / 5
            #expect(chips[0].value == fmtBytes(sum))
            #expect(chips[1].value == "3 snapshots" && chips[2].value == "(3)" && chips[3].value == nil)
            #expect(chips.map(\.object) == ["Free up", "Delete", "Update Homebrew", "Grant Full Disk Access"])
            #expect(chips.map(\.accessibilityText) == ["Free up 19.7 GB", "Delete 3 snapshots", "Update Homebrew (3)", "Grant Full Disk Access"])
            #expect(chips.map(\.opensDeleteConfirm) == [false, true, false, false])
            #expect(chips[1].destination == Destination(.backups, focus: .tm))
            #expect(chips[2].destination == Destination(.system, focus: .brew))
            #expect(chips[3].destination == Destination(.storage, focus: .folders, foldersSegment: .home))
            #expect(StringsEN().homeBrewOutdatedShort(3) == "3 outdated", "the System tile keeps its text")
            #expect(StringsRU().homeBrewOutdatedShort(3) == "3 устар.", "the System tile keeps its text")
            L10nStore.shared.language = .ru
            #expect(HomeModel.chips(homeInput(report, live)).map(\.accessibilityText)
                    == ["Освободить 19,7 ГБ", "Удалить 3 снимка", "Обновить Homebrew (3)", "Дать полный доступ к диску"])
            L10nStore.shared.language = .en
            #expect(chips[0].destination == Destination(.storage, focus: .folders, foldersSegment: .home))
            report.homeDirs = [DirSize(path: home + "/Downloads", bytes: 5 * GIB)]
            report.homeCaches = nil
            #expect(!HomeModel.chips(homeInput(report, live)).contains { $0.id == "freeUp" }, "5 GiB Downloads: no chip")
            // D8: with space ok, Downloads and Caches drop out; Trash stays, no snapshots chip.
            var roomy = r
            roomy.homeDirs = [DirSize(path: home + "/Downloads", bytes: 14 * GIB),
                              DirSize(path: home + "/.Trash", bytes: GIB + GIB / 2)]
            roomy.homeCaches = DirSize(path: home + "/Library/Caches", bytes: 4 * GIB + GIB / 5)
            roomy.snapshots = ["a", "b", "c"]
            roomy.homeDirsUnreadable = ["/x"]
            let (_, roomyLive) = homeBadFixture(diskPct: 0.50)
            let roomyChips = HomeModel.chips(homeInput(roomy, roomyLive))
            #expect(roomyChips.first { $0.id == "freeUp" }?.value == fmtBytes(GIB + GIB / 2), "space ok: freeUp is the Trash alone")
            #expect(!roomyChips.contains { $0.id == "snapshots" }, "space ok: no snapshots chip")
            #expect(roomyChips.map(\.id) == ["freeUp", "brew", "fda"], "space ok: brew and fda stay")
        }


        @Test func snapshotsChipShowsOnlyWhenSpaceIsShort() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            func text(diskPct: Double, names: [String]?) -> String? {
                let (r, live) = homeBadFixture(diskPct: diskPct)
                var report = r
                report.snapshots = names
                return HomeModel.chips(homeInput(report, live)).first { $0.id == "snapshots" }?.accessibilityText
            }
            let three = ["a", "b", "c"]
            #expect(text(diskPct: 0.50, names: three) == nil, "space ok")
            #expect(text(diskPct: 0.87, names: three) == "Delete 3 snapshots", "low")
            #expect(text(diskPct: 0.95, names: three) == "Delete 3 snapshots", "critical")
            #expect(text(diskPct: 0.87, names: ["a"]) == "Delete 1 snapshot")
            #expect(text(diskPct: 0.87, names: []) == nil)
            #expect(text(diskPct: 0.87, names: nil) == nil)
            var (report, live) = homeBadFixture(diskPct: 0.87)
            report.snapshots = three
            var strict = homeInput(report, live)
            strict.lowSpacePercent = 10
            #expect(!HomeModel.chips(strict).contains { $0.id == "snapshots" }, "13 % free is fine at a 10 % setting")
            live.disk = nil
            #expect(!HomeModel.chips(homeInput(report, live)).contains { $0.id == "snapshots" }, "disk not read yet")
            #expect((1...2).map { StringsRU().bkSnapshotCount($0) } == ["1 снимок", "2 снимка"])
            #expect([3, 5, 11, 21].map { StringsRU().bkDeleteSnapshots($0) } == ["Удалить 3 снимка", "Удалить 5 снимков", "Удалить 11 снимков", "Удалить 21 снимок"])
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
            #expect(sec.tagTone == .amber && sec.tagText == "Firewall off" && !sec.hotRing)
            #expect(sec.destination == Destination(.security, focus: .protect))
            let stor = tiles.first { $0.page == .storage }!
            #expect(stor.tagTone == .hot && stor.tagText == "drive failing", "storage tag from its first (hottest) task")
            let cpu = tiles.first { $0.page == .cpu }!
            #expect(cpu.kvs[0].label == L.homeKVLoad15 && cpu.kvs[0].value == fmtFixed(1, decimals: 2) && cpu.kvs[1].value == "412" && cpu.sub == "Apple M3 · 8 cores")
            #expect(cpu.socRow?.kind == .empty, "no thermal reading: the SoC tile's row is empty and the old tag is not spoken")
            #expect(cpu.accessibilityText == "\(cpu.name), Apple M3 · 8 cores, Load 15 min \(fmtFixed(1, decimals: 2)), Processes 412")
            let sysTile = tiles.first { $0.page == .system }!
            let brewKV = sysTile.kvs.first { $0.label == "Homebrew" }
            #expect(brewKV?.value == L.homeBrewOutdatedShort(3) && brewKV?.tone == nil, "Homebrew KV is not amber at 3 outdated")
            let mem = tiles.first { $0.page == .memory }!
            #expect(mem.kvs.map(\.label) == [L.memPurgeable, L.memFileCache])
            #expect(mem.kvs[0].value == fmtBytes(live.mem!.purgeable) && mem.kvs[1].value == fmtBytes(live.mem!.fileBacked))
            let bat = tiles.first { $0.page == .battery }!
            #expect(bat.kvs.map(\.label) == [L.batteryCapCondition, L.batteryCapMax])
            #expect(bat.kvs[1].value == "—", "no battery read yet")
            var withMAh = input; withMAh.batteryMaxMAh = 3874
            #expect(HomeModel.tiles(withMAh, tasks: tasks, scan: .ok(at: now)).first { $0.page == .battery }!.kvs[1].value == L.batMAh(fmtGrouped(3874)))
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            var withTrash = report; withTrash.homeDirs = [DirSize(path: home + "/.Trash", bytes: 1_500_000_000)]
            let storTrash = HomeModel.tiles(homeInput(withTrash, live), tasks: tasks, scan: .ok(at: now)).first { $0.page == .storage }!
            #expect(storTrash.kvs[0].label == L.storageTrashLabel && storTrash.kvs[0].value == fmtCapacity(1_500_000_000))
            #expect(stor.kvs[0].value == "—", "no home folder count yet")

            let skel = HomeModel.tiles(input, tasks: tasks, scan: .firstScan)
            #expect(skel.allSatisfy { $0.accessibilityText == [$0.name, $0.sub].filter { !$0.isEmpty }.joined(separator: ", ") })
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

        @Test func protectionTone() {
            #expect(HomeModel.protectionTone(SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)) == nil)
            #expect(HomeModel.protectionTone(SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)) == .amber)
            #expect(HomeModel.protectionTone(SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: true)) == .hot)
            #expect(HomeModel.protectionTone(SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: false)) == .hot)
            #expect(HomeModel.protectionTone(nil) == nil)
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
            let digest = HomeModel.historyDigest(rising)
            #expect(digest.count == 91 && digest.diskPerMonth == rate && digest.batteryPerMonth == nil)
            var (report, live) = homeBadFixture(diskPct: 0.80)
            report.security = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)
            var withDigest = homeInput(report, live)
            withDigest.historyDigest = digest
            let fromEntries = homeInput(report, live, history: rising)
            let t1 = HomeModel.tiles(withDigest, tasks: [], scan: .ok(at: base)).first { $0.page == .history }!
            let t2 = HomeModel.tiles(fromEntries, tasks: [], scan: .ok(at: base)).first { $0.page == .history }!
            #expect(t1.tagText == t2.tagText && t1.kvs.map(\.value) == t2.kvs.map(\.value), "cached digest == derived")
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

        @Test func dayNumber() {
            #expect(HomeModel.dayNumber("1970-01-01") == 0)
            #expect(HomeModel.dayNumber("2026-03-01")! - HomeModel.dayNumber("2026-02-28")! == 1)
            #expect(HomeModel.dayNumber("2024-03-01")! - HomeModel.dayNumber("2024-02-28")! == 2)   // leap year
            #expect(HomeModel.dayNumber("2027-01-01")! - HomeModel.dayNumber("2026-01-01")! == 365)
            #expect(HomeModel.dayNumber("2026-1-01") == nil && HomeModel.dayNumber("2026-13-01") == nil && HomeModel.dayNumber("x") == nil)
        }

        @Test func plurals() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .ru
            #expect([1, 3, 5, 11, 21].map { L.homeTaskCount($0) } == ["1 задача", "3 задачи", "5 задач", "11 задач", "21 задача"])
            #expect(L.homeStateReports(4) == "4 отчёта")
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

        // MARK: HOME-C: the Now card

        private func nowFixture() -> (FullReport, LiveSnapshot) {
            var report = FullReport()
            report.battery = BatteryInfo(source: nil, charge: 64, state: .discharging, cycles: 1, condition: "Normal", maxCapacity: 76)
            var live = LiveSnapshot()
            live.disk = DiskInfo(size: 256 * GIB, avail: 150 * GIB, dataUsed: nil, sysUsed: nil)
            live.swap = SwapInfo(total: 8 * GIB, used: 1 * GIB, free: 7 * GIB)
            live.mem = memFixture(total: 16 * GIB, compressor: GIB + GIB / 2)
            live.battery = report.battery
            return (report, live)
        }

        private func nowCells(_ report: FullReport, _ live: LiveSnapshot, pressure: MemoryPressureLevel?,
                              tasks: [HomeTask]? = nil, hasBattery: Bool = true, cpu: CPUUsage? = CPUUsage(user: 20.2, sys: 5.5, idle: 74.3),
                              short: Bool = false, narrow: Bool = false, gpu: Int? = 23) -> [HomeNowCell] {
            let a = Assess.assess(report: report, live: live, language: L10nStore.shared.language, memPressure: pressure)
            let input = homeInput(report, live, assessment: a, hasBattery: hasBattery)
            let t = tasks ?? HomeModel.tasks(a, report: report, disk: live.disk, battery: live.battery)
            return HomeModel.nowCells(input, tasks: t, memPressure: pressure, socTempC: 48, gpuUtil: gpu, cpu: cpu, short: short, narrow: narrow)
        }

        @Test func nowCellsDiskSegmentsOneBasis() {
            let gb: (Double) -> Int64 = { Int64($0 * 1e9) }
            var (report, live) = nowFixture()
            live.disk = DiskInfo(size: gb(245.1), avail: gb(132.3), dataUsed: gb(84.4), sysUsed: gb(13.7), purgeable: gb(64.3))
            let cell = nowCells(report, live, pressure: .normal)[2]
            let v = cell.segments.map(\.value)
            #expect(v.count == 4 && abs(v[2] - Double(gb(14.7))) < 0.2e9, "Other ~14.7-14.8 GB, got \(v)")
            #expect(abs(v.reduce(0, +) - Double(gb(245.1))) < 1, "segments + free = size")
        }

        @Test func nowCellsValues() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            let (report, live) = nowFixture()
            let cells = nowCells(report, live, pressure: .normal)
            #expect(cells.map(\.kind) == [.cpu, .memory, .storage, .battery])
            #expect(cells[0].figures[0].value == "26%" && cells[0].chipText == "48 °C" && cells[0].chipTone == .green)
            #expect(cells[0].foot == "load 2.10 · 8 cores")
            #expect(cells[1].big == "9.5 GB" && cells[1].tone == .neutral && cells[1].chipText == "pressure low")
            #expect(cells[1].of == "of 16" && cells[1].foot == "swap 1 GB of 8 GB · compressed 1.5 GB")
            #expect(cells[2].big == fmtCapacity(150 * GIB) && cells[2].of == "free" && cells[2].chipText == "healthy")
            #expect(cells[3].big == "76%" && cells[3].of == "of new" && cells[3].foot == "1 cycle · now 64%, discharging")
            // 76 % with 1 cycle is an early-wear (warn) task: amber cell, "worn" chip, amber fill.
            #expect(cells[3].tone == .amber && cells[3].chipText == "worn")
            #expect(cells[3].batteryBar == HomeBatteryBar(fraction: 0.76, fill: .amber, tick: 0.8, tickLabel: "80%",
                                                          spoken: "wear threshold 80%", help: "80% — Apple’s wear threshold"))
            #expect(cells[3].segments.isEmpty && cells[3].legend.isEmpty)
            #expect(cells[0...2].allSatisfy { $0.batteryBar == nil })
            #expect(HomeModel.nowCells(homeInput(report, live), tasks: [], memPressure: nil, socTempC: nil, gpuUtil: nil, cpu: CPUUsage(user: 1, sys: 1, idle: 98),
                                       short: false, narrow: false)[0].chipText == nil)
            let short = nowCells(report, live, pressure: .normal, short: true)
            #expect(short[1].legend[0].text == "act. 4")
            // 4-in-a-row keeps three items; the compressed item appears in 2x2 and 3-column layouts only.
            #expect(cells[1].legend.map(\.series) == [.s1, .s2, .s4] && short[1].legend.count == 3)
            let two = nowCells(report, live, pressure: .normal, narrow: true)
            #expect(two[1].legend.map(\.series) == [.s1, .s2, .s6, .s4])
            #expect(two[1].legend[2].text == "compressed 1.5")
            let three = nowCells(report, live, pressure: .normal, hasBattery: false)
            #expect(three[1].legend.map(\.series) == [.s1, .s2, .s6, .s4])
        }


        @Test func sectionFacesDoNotRepeatNow() {
            var (report, live) = nowFixture()
            // memFixture sets fileBacked == inactive (both total / 8): a fixture coincidence, not a repeat.
            live.mem?.fileBacked = 3 * GIB
            let cells = nowCells(report, live, pressure: .normal)
            let tiles = HomeModel.tiles(homeInput(report, live), tasks: [], scan: .ok(at: Date()))
            for (page, kind) in [(Page.cpu, HomeNowKind.cpu), (.memory, .memory), (.storage, .storage), (.battery, .battery)] {
                guard let t = tiles.first(where: { $0.page == page }), let c = cells.first(where: { $0.kind == kind }) else { continue }
                let nowText = ([c.big, c.of, c.foot] + c.legend.map(\.text)).joined(separator: " | ")
                for kv in t.kvs where kv.value != "—" {
                    #expect(!nowText.contains(kv.value), "\(page): «\(kv.value)» already in Now")
                }
            }
        }
        @Test func dataSegmentsAreNeverWarningColoured() {
            let (report, live) = nowFixture()
            let cells = nowCells(report, live, pressure: .normal)
            let data: Set<HomeSeries> = [.s1, .s2, .s4, .s5, .sfree, .s6, .track]
            for c in cells where c.kind == .memory || c.kind == .storage {
                #expect(c.segments.allSatisfy { data.contains($0.series) }, "\(c.kind) segments")
                #expect(c.legend.allSatisfy { data.contains($0.series) }, "\(c.kind) legend")
            }
        }

        @Test func nowCellAccessibilityText() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            let (report, live) = nowFixture()
            let cells = nowCells(report, live, pressure: .normal)
            #expect(cells[0].accessibilityText == "SoC, CPU 26%, GPU 23%, 48 °C, load 2.10 · 8 cores")
            let m = cells[1]
            #expect(m.accessibilityText == (["Memory", "9.5 GB of 16", "pressure low"] + m.legend.map(\.text)
                                            + ["swap 1 GB of 8 GB · compressed 1.5 GB"]).joined(separator: ", "))
            #expect(cells[2].accessibilityText.hasPrefix("Storage, \(fmtCapacity(150 * GIB)) free, healthy, data "))
            #expect(cells[3].accessibilityText == "Battery, 76% of new, worn, wear threshold 80%, 1 cycle · now 64%, discharging")
            L10nStore.shared.language = .ru
            let ru = nowCells(report, live, pressure: .normal)[3]
            #expect(ru.batteryBar?.tickLabel == "80 %")
            #expect(ru.accessibilityText == "Батарея, 76 % от новой, износ, порог износа 80 %, \(ru.foot)")
            L10nStore.shared.language = .en
            let loading = nowCells(report, live, pressure: nil, cpu: nil)[0]
            #expect(loading.accessibilityText == "SoC, Collecting data…")
        }

        @Test func nowCellsBatteryMergesReportStatics() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            var (report, live) = nowFixture()
            report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: 300, condition: "Normal", maxCapacity: 86)
            live.battery = BatteryInfo(source: nil, charge: 55, state: .charging, cycles: nil, condition: nil, maxCapacity: nil)
            let cell = nowCells(report, live, pressure: .normal)[3]
            #expect(cell.loading == false && cell.big == "86%")
            #expect(cell.foot.contains("300 cycles") && cell.foot.contains("now 55%"), "foot \(cell.foot)")
            #expect(cell.batteryBar?.fraction == 0.86 && cell.batteryBar?.fill == .green)
        }

        @Test func batteryMergedHelper() {
            let live = BatteryInfo(source: .ac, charge: 50, state: .charging, cycles: nil, condition: nil, maxCapacity: nil)
            let rep = BatteryInfo(source: .battery, charge: 10, state: .other("old"), cycles: 300, condition: "Normal", maxCapacity: 86)
            #expect(BatteryInfo.merged(live: nil, report: nil) == nil)
            #expect(BatteryInfo.merged(live: live, report: nil) == live)
            #expect(BatteryInfo.merged(live: nil, report: rep) == rep)
            #expect(BatteryInfo.merged(live: live, report: rep) ==
                    BatteryInfo(source: .ac, charge: 50, state: .charging, cycles: 300, condition: "Normal", maxCapacity: 86))
        }

        @Test func wornTaskUsesMergedCapacity() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            // Report battery without max capacity, live sample with it: both Assessment and the task fall back to live.
            var report = FullReport()
            report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: 100, condition: "Normal", maxCapacity: nil)
            var live = LiveSnapshot()
            live.battery = BatteryInfo(source: nil, charge: 50, state: nil, cycles: nil, condition: nil, maxCapacity: 65)
            var a = Assess.assess(report: report, live: live, language: L10nStore.shared.language, memPressure: nil)
            #expect(a.items.contains { $0.kind == .batteryCapacity && $0.sev == .warn }, "live capacity raises the item")
            var t = HomeModel.tasks(a, report: report, disk: nil, battery: live.battery).first { $0.kind == .batteryCapacity }
            #expect(t?.state == "35% worn", "fallback state \(String(describing: t?.state))")
            // Both carry it: the report value wins.
            report.battery?.maxCapacity = 60
            a = Assess.assess(report: report, live: live, language: L10nStore.shared.language, memPressure: nil)
            t = HomeModel.tasks(a, report: report, disk: nil, battery: live.battery).first { $0.kind == .batteryCapacity }
            #expect(t?.state == "40% worn", "report state \(String(describing: t?.state))")
        }

        @Test func batteryRawSwitchOnHome() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            var (report, live) = nowFixture()
            report.battery?.maxCapacity = 82
            report.battery?.cycles = 100
            live.battery = report.battery
            let raw = Assess.assess(report: report, live: live, language: .en, memPressure: nil, batteryRawPercent: 78, batteryPrefersRaw: true)
            #expect(raw.battShownPercent == 78)
            let rawTasks = HomeModel.tasks(raw, report: report, disk: live.disk, battery: live.battery)
            #expect(rawTasks.first { $0.kind == .batteryCapacity }?.state == "22% worn")
            var input = homeInput(report, live, assessment: raw)
            input.batteryRawPercent = 78
            input.batteryPrefersRaw = true
            let cell = HomeModel.nowCells(input, tasks: rawTasks, memPressure: nil, socTempC: 48, gpuUtil: 23,
                                          cpu: CPUUsage(user: 20.2, sys: 5.5, idle: 74.3), short: false, narrow: false)[3]
            #expect(cell.big == "78%" && cell.chipText == "worn" && cell.batteryBar?.fraction == 0.78)

            let apple = Assess.assess(report: report, live: live, language: .en, memPressure: nil, batteryRawPercent: 78, batteryPrefersRaw: false)
            #expect(apple.battShownPercent == 82)
            #expect(!apple.items.contains { $0.kind == .batteryCapacity })
            var appleInput = homeInput(report, live, assessment: apple)
            appleInput.batteryRawPercent = 78
            let appleCell = HomeModel.nowCells(appleInput, tasks: HomeModel.tasks(apple, report: report, disk: live.disk, battery: live.battery),
                                               memPressure: nil, socTempC: 48, gpuUtil: 23,
                                               cpu: CPUUsage(user: 20.2, sys: 5.5, idle: 74.3), short: false, narrow: false)[3]
            #expect(appleCell.big == "82%" && appleCell.chipText == "healthy")
        }

        @Test func nowCellsTones() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            var (report, live) = nowFixture()
            // Critical pressure with a serious swapHigh task: memory tinted hot.
            live.swap = SwapInfo(total: 8 * GIB, used: 7 * GIB, free: 1 * GIB)
            let crit = nowCells(report, live, pressure: .critical)
            #expect(crit[1].tone == .hot && crit[1].chipText == "pressure high" && crit[1].chipTone == .hot)
            // SMART errors: storage hot, focus smart. Battery service: hot, chip "service".
            report.smart = [SmartDisk(device: "internal", title: "Boot SSD", status: .mediaErrors,
                                      attrs: [("Media and Data Integrity Errors", "3")], severity: .crit)]
            report.battery?.condition = "Service Recommended"
            live.battery = report.battery
            let bad = nowCells(report, live, pressure: .normal)
            #expect(bad[2].tone == .hot && bad[2].chipText == "drive failing" && bad[2].destination.focus == .smart)
            #expect(bad[3].tone == .hot && bad[3].chipText == "service")
            #expect(bad[3].batteryBar?.fill == .hot)
        }

        @Test func nowCellsMissing() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            let (report, live) = nowFixture()
            #expect(nowCells(report, live, pressure: nil, hasBattery: false).count == 3)
            let cells = nowCells(report, live, pressure: nil, cpu: nil)
            #expect(cells[0].loading && cells[0].big == "—" && cells[0].figures.map(\.value) == ["—", "—"] && cells[0].foot == "Collecting data…" && cells[0].chipText == nil)
            #expect(cells[0].segments == [HomeNowSegment(series: .track, value: 1)] && cells[0].legend.isEmpty)
            #expect(cells[1].chipText == nil, "no pressure level, no chip")
        }

        @Test func socChipSharesCPUPageLevels() {
            let (report, live) = nowFixture()
            func chip(_ t: Int) -> HomeTone? {
                HomeModel.nowCells(homeInput(report, live), tasks: [], memPressure: nil, socTempC: t, gpuUtil: 23,
                                   cpu: CPUUsage(user: 1, sys: 1, idle: 98), short: false, narrow: false)[0].chipTone
            }
            #expect(chip(84) == .green && chip(85) == .amber && chip(94) == .amber && chip(95) == .hot, "Home chip 84/85/94/95")
            for t in [48, 84, 85, 94, 95, 100] {
                let expected: HomeTone
                switch CPULoad.socLevel(t) {
                case .normal: expected = .green
                case .warm: expected = .amber
                case .hot: expected = .hot
                }
                #expect(chip(t) == expected, "Home chip follows CPULoad.socLevel at \(t) °C")
            }
        }

        @Test func nowSoCFigures() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            let (report, live) = nowFixture()
            let cells = nowCells(report, live, pressure: .normal)
            #expect(cells[0].label == "SoC" && cells[0].figures.count == 2)
            #expect(cells[0].figures[0].kicker == "CPU" && cells[0].figures[0].value == "26%")
            #expect(cells[0].figures[1].kicker == "GPU" && cells[0].figures[1].value == "23%")
            #expect(cells[0].accessibilityText == "SoC, CPU 26%, GPU 23%, 48 °C, \(cells[0].foot)")
            let none = nowCells(report, live, pressure: .normal, gpu: nil)[0]
            #expect(none.figures[1].value == "—" && none.figures[1].dimmed)
            #expect(none.figures[1].spoken == "GPU: Not available on this Mac")
            L10nStore.shared.language = .ru
            let ru = nowCells(report, live, pressure: .normal)[0]
            #expect(ru.figures[0].kicker == "Процессор" && ru.figures[1].kicker == "Графика")
        }

        /// SOC-DETAILS 4.1: fraction, bar colour and gauge of the SoC cell.
        @Test func nowSoCBarsAndGauge() {
            let (report, live) = nowFixture()
            let a = Assess.assess(report: report, live: live, language: L10nStore.shared.language, memPressure: .normal)
            func cell(temp: Int?, gpu: Int?, high: Bool, cpu: CPUUsage? = CPUUsage(user: 60.2, sys: 25.5, idle: 14.3)) -> HomeNowCell {
                HomeModel.nowCells(homeInput(report, live, assessment: a), tasks: [], memPressure: .normal, socTempC: temp, gpuUtil: gpu,
                                   cpu: cpu, cpuHigh: high, short: false, narrow: false)[0]
            }
            let calm = cell(temp: 58, gpu: 23, high: false)
            #expect(abs(calm.figures[0].fraction - 0.857) < 0.001 && calm.figures[0].bar == .s1)
            #expect(abs(calm.figures[1].fraction - 0.23) < 0.001 && calm.figures[1].bar == .s6)
            #expect(calm.chipGauge == HomeChipGauge(zone: 0, markerX: SocReadout.markerX(celsius: 58)))
            #expect(cell(temp: 90, gpu: 23, high: false).chipGauge?.zone == 1)
            #expect(cell(temp: 97, gpu: 23, high: false).chipGauge?.zone == 2)
            #expect(cell(temp: 97, gpu: 23, high: false).chipGauge?.markerX == SocReadout.markerX(celsius: 97))
            #expect(cell(temp: nil, gpu: 23, high: false).chipGauge == nil && cell(temp: nil, gpu: 23, high: false).chipText == nil)
            #expect(cell(temp: 58, gpu: 23, high: true).figures[0].bar == .amber, "high load turns the CPU bar amber")
            #expect(cell(temp: 58, gpu: 23, high: true).figures[1].bar == .s6)
            let noGPU = cell(temp: 58, gpu: nil, high: false).figures[1]
            #expect(noGPU.fraction == 0 && noGPU.dimmed)
            #expect(cell(temp: 58, gpu: 23, high: false, cpu: CPUUsage(user: 90, sys: 30, idle: 0)).figures[0].fraction == 1, "clamped")
        }

        /// SOC-DETAILS 4.3: the Sections SoC row, design 7.13 tone rule.
        @Test func socRowCases() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            func row(_ th: ThermalLevel?, _ t: Int?, high: Bool = false, narrow: Bool = false) -> HomeSocRow {
                HomeModel.socRow(thermal: th, socTempC: t, cpuHigh: high, highMinutes: high ? 3 : nil, cpuPct: 91, narrow: narrow)
            }
            func step(_ r: HomeSocRow) -> Int? { if case .thermal(let s, _, _) = r.kind { return s } else { return nil } }
            func text(_ r: HomeSocRow) -> String? {
                switch r.kind { case .thermal(_, let t, _), .highLoad(let t, _): return t; case .empty: return nil }
            }
            let nom58 = row(.nominal, 58)
            #expect(step(nom58) == 0 && text(nom58) == "normal" && nom58.rightText == "58 °C")
            #expect(nom58.rowTone == .green && nom58.textTone == .green && nom58.rightTone == .green)
            let el58 = row(.fair, 58)
            #expect(step(el58) == 1 && text(el58) == "elevated" && el58.rowTone == .green && el58.textTone == .neutral && el58.rightTone == .neutral)
            let nom97 = row(.nominal, 97)
            #expect(nom97.rowTone == .hot && nom97.textTone == .green && nom97.rightTone == .hot, "normal and 97 °C: hot row, hot value")
            let el88 = row(.fair, 88)
            #expect(el88.rowTone == .amber && el88.textTone == .neutral && el88.rightTone == .amber)
            let hi58 = row(.serious, 58)
            #expect(step(hi58) == 2 && hi58.rowTone == .amber && hi58.textTone == .amber && hi58.rightTone == .amber)
            let hi88 = row(.serious, 88)
            #expect(hi88.rowTone == .amber && hi88.rightTone == .amber)
            let crit97 = row(.critical, 97)
            #expect(step(crit97) == 3 && crit97.rowTone == .hot && crit97.textTone == .hot && crit97.rightTone == .hot)
            let crit58 = row(.critical, 58)
            #expect(crit58.rowTone == .hot && crit58.rightTone == .hot, "no temperature tone: the right value follows the thermal text")
            let load = row(.nominal, 97, high: true)
            #expect(load.kind == .highLoad(text: "High load", help: "High load for 3 min") && load.rightText == "91%")
            #expect(load.rowTone == .amber && load.textTone == .amber && load.rightTone == .amber, "high load wins over temperature")
            #expect(row(nil, 58).kind == .empty && row(nil, nil).kind == .empty && row(nil, 58).rightText == nil)
            #expect(row(.nominal, nil).rightText == nil && step(row(.nominal, nil)) == 0)
            #expect(text(row(.nominal, 58, narrow: false)) == "normal" && text(row(.nominal, 58, narrow: true)) == "thermal: normal")
            if case .thermal(_, _, let help) = row(.nominal, 58, narrow: true).kind { #expect(help.hasPrefix("thermal: normal. ")) }
            L10nStore.shared.language = .ru
            let ru = row(.critical, 97, narrow: true)
            #expect(text(ru) == "нагрев: критический" && ru.rightText == "97 °C")
            #expect(row(.nominal, 58, high: true).rightText == "91 %")
        }

        @Test func tileCarriesSocRowOnlyOnCPU() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            let (report, live) = nowFixture()
            var input = homeInput(report, live)
            input.thermal = .fair; input.socTempC = 58; input.cpu = CPUUsage(user: 10, sys: 5, idle: 85)
            let tasks = HomeModel.tasks(input.assessment, report: report, disk: live.disk, battery: live.battery)
            let tiles = HomeModel.tiles(input, tasks: tasks, scan: .ok(at: input.now))
            #expect(tiles.filter { $0.socRow != nil }.map(\.page) == [.cpu])
            #expect(tiles[0].socRow?.rightText == "58 °C")
            #expect(tiles[0].accessibilityText.contains("elevated 58 °C"))
            input.cpu = CPUUsage(user: 70, sys: 20, idle: 10)
            input.cpuHighSince = input.now.addingTimeInterval(-190)
            let high = HomeModel.tiles(input, tasks: tasks, scan: .ok(at: input.now))[0].socRow
            #expect(high?.kind == .highLoad(text: L.cpuTagHigh, help: L.cpuHighLoadFor(3)) && high?.rightText == "90%")
            input.cpuHighSince = input.now.addingTimeInterval(-20)   // under a minute: not high yet
            if case .thermal? = HomeModel.tiles(input, tasks: tasks, scan: .ok(at: input.now))[0].socRow?.kind {} else { Issue.record("expected thermal row") }
        }

        @Test func nowRu() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .ru
            #expect(L.homeLoadCores(fmtFixed(2.1, decimals: 2), 8) == "нагрузка 2,10 · 8 ядер")
            #expect(L.homeBatteryFoot(cycles: 21, charge: nil, state: nil, short: false) == "21 цикл")
        }
    }
}

private func upd(_ label: String) -> SoftwareUpdate {
    SoftwareUpdate(label: label, title: label, version: nil, sizeBytes: nil, restartRequired: false)
}
