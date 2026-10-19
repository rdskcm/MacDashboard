// tools/harness/scenario_smart_install.swift
// Block N8 render scenario, reworked for REDESIGN-STORAGE: StorageSmartCard in its "tools missing"
// states (.installable, install failed and .needsHomebrew), for headless screenshot verification of the
// install-smartmontools note on the Storage page. See tools/harness/README.md for how to run this (render.sh) and for the general
// scenario pattern.

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    L10nStore.shared.language = .ru

    // A: Homebrew present, smartctl missing -> install button.
    let installable = DashboardModel()
    installable.smartToolsState = .installable
    installable.report.smartctlPresent = false
    installable.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good),
        SmartDisk(device: "/dev/disk4", title: "External HDD", status: "SMART недоступен", attrs: [], severity: .warn)
    ]

    // B: Homebrew present, smartctl missing, previous install attempt failed -> button + error line.
    let installableWithError = DashboardModel()
    installableWithError.smartToolsState = .installable
    installableWithError.applyFixtureSmartTools(.installable, installing: false, failure: .exitCode(1))
    installableWithError.report.smartctlPresent = false
    installableWithError.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good)
    ]

    // C: Homebrew itself missing -> hint text only, no button.
    let needsHomebrew = DashboardModel()
    needsHomebrew.smartToolsState = .needsHomebrew
    needsHomebrew.report.smartctlPresent = false
    needsHomebrew.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good)
    ]

    harnessRender(width: 1094) {
        HarnessSection(label: "A: .installable (button)") {
            StorageSmartCard(model: installable, windowWidth: 1150)
        }
        HarnessSection(label: "B: .installable + smartInstallFailure") {
            StorageSmartCard(model: installableWithError, windowWidth: 1150)
        }
        HarnessSection(label: "C: .needsHomebrew (hint, no button)") {
            StorageSmartCard(model: needsHomebrew, windowWidth: 1150)
        }
    }
}
