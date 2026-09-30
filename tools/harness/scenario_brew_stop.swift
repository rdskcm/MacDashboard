// tools/harness/scenario_brew_stop.swift
// BREW-CANCEL render scenario: the Stop control and the stop phases on MaintenanceCard's
// Homebrew section. States A-D in Russian; run with BREW_STOP_LANG=en for the same four
// states in English (state E: L is read at render time, so one process renders one language).
// See tools/harness/README.md for how to run this (render.sh).

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    L10nStore.shared.language = ProcessInfo.processInfo.environment["BREW_STOP_LANG"] == "en" ? .en : .ru

    let all = ["git", "node", "python@3.13"]

    @MainActor func model(outdated: [String] = all) -> DashboardModel {
        let m = DashboardModel()
        m.report.brewStatus = .installed(version: "Homebrew 4.6.0")
        m.report.brewOutdated = outdated
        return m
    }
    let progress = BrewProgress(phase: .upgrading, formula: "python@3.13", completed: 1, total: 3, downloadsDone: 3)

    // A: upgrading, Stop enabled.
    let upgrading = model()
    upgrading.brewUpgrading = true
    upgrading.brewUpgradeStoppable = true
    upgrading.brewProgress = progress

    // B: Stop pressed, brew still exiting.
    let stopping = model()
    stopping.brewUpgrading = true
    stopping.brewUpgradeStoppable = true
    stopping.brewStopRequested = true
    stopping.brewProgress = progress

    // C: brew exited, re-check running.
    let rechecking = model()
    rechecking.brewUpgrading = true
    rechecking.brewUpgradeStoppable = false
    rechecking.brewStopRequested = true
    rechecking.brewProgress = progress

    // D: stopped, neutral notice.
    let stopped = model(outdated: ["python@3.13"])
    stopped.brewUpgradeNotice = BrewUpgrader.stoppedNotice(before: all, after: ["python@3.13"])

    harnessRender(width: 460) {
        HarnessSection(label: "A: upgrading (Stop enabled)") { MaintenanceCard(model: upgrading) }
        HarnessSection(label: "B: stopping (Stop dimmed)") { MaintenanceCard(model: stopping) }
        HarnessSection(label: "C: re-checking (Stop dimmed)") { MaintenanceCard(model: rechecking) }
        HarnessSection(label: "D: stopped (neutral notice)") { MaintenanceCard(model: stopped) }
    }
}
