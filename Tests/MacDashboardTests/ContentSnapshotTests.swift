// Tests/MacDashboardTests/ContentSnapshotTests.swift
// HARNESS-REDESIGN-RETARGET: offscreen content states (dark + light) rendered from the fixed VisualFixture dataset.
// Runs only through tools/visual/snapshots.sh (MACDASH_SNAPSHOTS set); a plain `swift test` skips it.
// Add one `run.snap` per new visible state (Live constraint "Visual fixture coverage").

import AppKit
import SwiftUI
import Testing
@testable import MacDashboard


/// The История section as the old Overview stacked it: kicker, restart
/// notice, card (NEWMAC-HISTORY-EMPTY).
struct HistorySectionSpecimen: View {
    let model: DashboardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.overviewKickerHistory).dsKicker()
            HistoryRestartNotice(model: model)
            HistoryCard(model: model)
        }
    }
}

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
            let saved = (settings.fastIntervalSeconds, settings.ignoredWakeHolders, settings.backupStaleHours)
            settings.fastIntervalSeconds = AppSettings.resolveFastInterval(raw: 0)
            settings.ignoredWakeHolders = []
            settings.backupStaleHours = AppSettings.resolveBackupStaleHours(raw: 0)
            defer { (settings.fastIntervalSeconds, settings.ignoredWakeHolders, settings.backupStaleHours) = saved }
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
            let fixtureDays = m.history.mac_history
            let historyNoDays = fixtureHistory([])
            let historyOneDay = fixtureHistory(Array(fixtureDays.suffix(1)))
            let historyRestarted = fixtureHistory(Array(fixtureDays.suffix(1)),
                                                  backup: "mac_check_state.json.unreadable-20260115-103000")
            let historyTwoDays = fixtureHistory(Array(fixtureDays.suffix(2)))

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
                run.snap("content-folders-home", mode, width: 589) {
                    FoldersCard(model: m, initialTab: .home)
                }
                run.snap("content-folders-service", mode, width: 589) {
                    FoldersCard(model: m, initialTab: .service)
                }
                run.snap("content-claude-backup", mode, width: 589) {
                    ClaudeBackupCard(model: m)
                }
                run.snap("content-history-disk", mode, width: 1150) {
                    HistoryCard(model: m, initialMetric: .disk, initialRange: .month)
                }
                run.snap("content-history-battery", mode, width: 1150) {
                    HistoryCard(model: m, initialMetric: .battery, initialRange: .month)
                }
                run.snap("content-history-cycles", mode, width: 1150) {
                    HistoryCard(model: m, initialMetric: .cycles, initialRange: .month)
                }
                run.snap("content-history-swap", mode, width: 1150) {
                    HistoryCard(model: m, initialMetric: .swap, initialRange: .month)
                }
                run.snap("content-history-disk-quarter", mode, width: 1150) {
                    HistoryCard(model: m, initialMetric: .disk, initialRange: .quarter)
                }
                run.snap("content-history-disk-year", mode, width: 1150) {
                    HistoryCard(model: m, initialMetric: .disk, initialRange: .year)
                }
                run.snap("content-history-disk-all", mode, width: 1150) {
                    HistoryCard(model: m, initialMetric: .disk, initialRange: .all)
                }
                run.snap("content-history-fresh", mode, width: 1150) {
                    VStack(alignment: .leading, spacing: 24) {
                        HarnessSection(label: "History: no days recorded (new Mac)") {
                            HistorySectionSpecimen(model: historyNoDays)
                        }
                        HarnessSection(label: "History: one day recorded") {
                            HistorySectionSpecimen(model: historyOneDay)
                        }
                        HarnessSection(label: "History: started over, one day recorded (notice + placeholder)") {
                            HistorySectionSpecimen(model: historyRestarted)
                        }
                        HarnessSection(label: "History: two days recorded (full card)") {
                            HistorySectionSpecimen(model: historyTwoDays)
                        }
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
                run.snap("content-settings-monitoring", mode, width: 720) {
                    SettingsView(model: m, startSection: .monitoring)
                }
                run.snap("content-settings-backup", mode, width: 720) {
                    SettingsView(model: m, startSection: .backup)
                }
            }
            try run.finish()
        }
    }
}
