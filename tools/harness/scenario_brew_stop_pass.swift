// tools/harness/scenario_brew_stop_pass.swift
// BREW-STOP-VISIBLE render scenario: the progress row and Stop stay mounted while a report
// pass has blanked or re-landed the brew section mid-upgrade. Russian; BREW_STOP_LANG=en for English.
// See tools/harness/README.md for how to run this (render.sh).

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    L10nStore.shared.language = ProcessInfo.processInfo.environment["BREW_STOP_LANG"] == "en" ? .en : .ru

    let progress = BrewProgress(phase: .upgrading, formula: "python@3.13", completed: 1, total: 3, downloadsDone: 3)

    @MainActor func upgrading() -> DashboardModel {
        let m = DashboardModel()
        m.brewUpgrading = true
        m.brewUpgradeStoppable = true
        m.brewProgress = progress
        return m
    }

    // E: report pass running, brew section not landed yet (brewStatus nil).
    let passRunning = upgrading()

    // F: pass landed `brew outdated` = [] while the upgrade still runs.
    let allFresh = upgrading()
    allFresh.report.brewStatus = .installed(version: "Homebrew 4.6.0")
    allFresh.report.brewOutdated = []

    // G: pass landed a failed check (brewOutdated nil) while the upgrade still runs.
    let checkFailed = upgrading()
    checkFailed.report.brewStatus = .installed(version: "Homebrew 4.6.0")
    checkFailed.report.brewOutdated = nil

    // H: control — pass running, no upgrade: spinner only, no row.
    let idle = DashboardModel()

    harnessRender(width: 460) {
        HarnessSection(label: "E: brewStatus nil, upgrading (row + Stop)") { MaintenanceCard(model: passRunning) }
        HarnessSection(label: "F: outdated [], upgrading (row + Stop)") { MaintenanceCard(model: allFresh) }
        HarnessSection(label: "G: check failed, upgrading (row + Stop)") { MaintenanceCard(model: checkFailed) }
        HarnessSection(label: "H: brewStatus nil, idle (no row)") { MaintenanceCard(model: idle) }
    }
}
