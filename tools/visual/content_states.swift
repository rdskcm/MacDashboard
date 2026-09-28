// tools/visual/content_states.swift
// VISUAL-COVERAGE: offscreen content stage — cards that sit below the fold of
// the real 1150xH window (Processes/Folders segments, История metrics/ranges)
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
    }
}
