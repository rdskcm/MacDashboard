// tools/visual/content_states.swift
// VISUAL-COVERAGE: offscreen content stage — cards that sit below the fold of
// the real 1150xH window (Processes/Folders segments, История metrics/ranges,
// the Claude backup card, the iPhone states: content-iphone-tiles / notices / battery / history / logs / import / identity / dialogs)
// rendered directly from the fixed VisualFixture dataset, dark+light, via the
// harness (tools/harness/render.sh). Pattern: scenario_ds_specimen.swift.
// argv[1] = the output DIRECTORY (run.sh's raw/); each state writes
// "<dir>/<state>-<mode>.png".

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    guard CommandLine.arguments.count > 1 else {
        FileHandle.standardError.write(Data("ERROR: content_states needs an output directory as argv[1]\n".utf8))
        exit(1)
    }
    let outDir = CommandLine.arguments[1]

    L10nStore.shared.language = .en
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

    for mode in ["dark", "light"] {
        NSApplication.shared.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)

        harnessRender(width: 589, to: "\(outDir)/content-processes-cpu-\(mode).png") {
            ProcessListCard(model: m, initialMetric: .cpu)
        }
        harnessRender(width: 589, to: "\(outDir)/content-processes-mem-\(mode).png") {
            ProcessListCard(model: m, initialMetric: .mem)
        }
        harnessRender(width: 589, to: "\(outDir)/content-folders-home-\(mode).png") {
            FoldersCard(model: m, initialTab: .home)
        }
        harnessRender(width: 589, to: "\(outDir)/content-folders-service-\(mode).png") {
            FoldersCard(model: m, initialTab: .service)
        }
        harnessRender(width: 589, to: "\(outDir)/content-claude-backup-\(mode).png") {
            ClaudeBackupCard(model: m)
        }
        harnessRender(width: 1150, to: "\(outDir)/content-history-disk-\(mode).png") {
            HistoryCard(model: m, initialMetric: .disk, initialRange: .month)
        }
        harnessRender(width: 1150, to: "\(outDir)/content-history-battery-\(mode).png") {
            HistoryCard(model: m, initialMetric: .battery, initialRange: .month)
        }
        harnessRender(width: 1150, to: "\(outDir)/content-history-cycles-\(mode).png") {
            HistoryCard(model: m, initialMetric: .cycles, initialRange: .month)
        }
        harnessRender(width: 1150, to: "\(outDir)/content-history-swap-\(mode).png") {
            HistoryCard(model: m, initialMetric: .swap, initialRange: .month)
        }
        harnessRender(width: 1150, to: "\(outDir)/content-history-disk-quarter-\(mode).png") {
            HistoryCard(model: m, initialMetric: .disk, initialRange: .quarter)
        }
        harnessRender(width: 1150, to: "\(outDir)/content-history-disk-year-\(mode).png") {
            HistoryCard(model: m, initialMetric: .disk, initialRange: .year)
        }
        harnessRender(width: 1150, to: "\(outDir)/content-history-disk-all-\(mode).png") {
            HistoryCard(model: m, initialMetric: .disk, initialRange: .all)
        }
        harnessRender(width: 1134, to: "\(outDir)/content-iphone-tiles-\(mode).png") {
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
        harnessRender(width: 1134, to: "\(outDir)/content-iphone-notices-\(mode).png") {
            HarnessSection(label: "iPhone banners and notices") {
                VStack(alignment: .leading, spacing: 16) {
                    IPhoneListBanner(kind: .error(L.iphoneRestartFailed("authorization was cancelled")))
                    IPhoneListBanner(kind: .restarting)
                    IPhoneNotice(kind: .empty)
                    IPhoneNotice(kind: .unavailable)
                }
            }
        }
        harnessRender(width: 1134, to: "\(outDir)/content-iphone-battery-\(mode).png") {
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
        harnessRender(width: 1134, to: "\(outDir)/content-iphone-history-\(mode).png") {
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
        harnessRender(width: 1134, to: "\(outDir)/content-iphone-logs-\(mode).png") {
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
        harnessRender(width: 1134, to: "\(outDir)/content-iphone-import-\(mode).png") {
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
        harnessRender(width: 1264, to: "\(outDir)/content-iphone-identity-\(mode).png") {
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
        harnessRender(width: 460, to: "\(outDir)/content-iphone-dialogs-\(mode).png") {
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
    }
}
