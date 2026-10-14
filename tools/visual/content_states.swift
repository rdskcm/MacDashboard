// tools/visual/content_states.swift
// VISUAL-COVERAGE: offscreen content stage — cards that sit below the fold of
// the real 1150xH window (Processes/Folders segments, История metrics/ranges and its 0/1/2-day states)
// rendered directly from the fixed VisualFixture dataset, dark+light, via the
// harness (tools/harness/render.sh). Pattern: scenario_ds_specimen.swift.
// argv[1] = the output DIRECTORY (run.sh's raw/); each state writes
// "<dir>/<state>-<mode>.png".

import AppKit
import SwiftUI

/// The История section as `MainDashboardView.overview` stacks it: kicker, card
/// (NEWMAC-HISTORY-EMPTY).
struct HistorySectionSpecimen: View {
    let model: DashboardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.overviewKickerHistory).dsKicker()
            HistoryCard(model: model)
        }
    }
}

MainActor.assumeIsolated {
    guard CommandLine.arguments.count > 1 else {
        FileHandle.standardError.write(Data("ERROR: content_states needs an output directory as argv[1]\n".utf8))
        exit(1)
    }
    let outDir = CommandLine.arguments[1]

    L10nStore.shared.language = .en
    let m = DashboardModel()
    m.applyVisualFixture()
    // NEWMAC-HISTORY-EMPTY: the same fixture with only `history` replaced. One model per
    // state, because a view reads `model.history` when it renders, not when the closure is
    // built. `DashboardModel()` only reads the real history file at init; nothing is written.
    @MainActor func fixtureHistory(_ entries: [MacHistoryEntry]) -> DashboardModel {
        let h = DashboardModel()
        h.applyVisualFixture()
        h.history = HistoryState(last_run: entries.last?.date, mac_history: entries)
        return h
    }
    let fixtureDays = m.history.mac_history
    let historyNoDays = fixtureHistory([])
    let historyOneDay = fixtureHistory(Array(fixtureDays.suffix(1)))
    let historyTwoDays = fixtureHistory(Array(fixtureDays.suffix(2)))

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
        harnessRender(width: 1150, to: "\(outDir)/content-history-fresh-\(mode).png") {
            VStack(alignment: .leading, spacing: 24) {
                HarnessSection(label: "History: no days recorded (new Mac)") {
                    HistorySectionSpecimen(model: historyNoDays)
                }
                HarnessSection(label: "History: one day recorded") {
                    HistorySectionSpecimen(model: historyOneDay)
                }
                HarnessSection(label: "History: two days recorded (full card)") {
                    HistorySectionSpecimen(model: historyTwoDays)
                }
            }
        }
    }
}
