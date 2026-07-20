// tools/harness/scenario_smart_install.swift
// Block N8 render scenario: SmartDisksCard in its two "tools missing" states
// (.installable and .needsHomebrew), for headless screenshot verification of the
// install-smartmontools button/hint added above the disk list. See
// tools/harness/README.md for how to run this (render.sh) and for the general
// scenario pattern.

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    L10nStore.shared.language = .ru

    // A: Homebrew present, smartctl missing -> install button.
    let installable = DashboardModel()
    installable.smartToolsState = .installable
    installable.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good),
        SmartDisk(device: "/dev/disk4", title: "External HDD", status: "SMART недоступен", attrs: [], severity: .warn)
    ]

    // B: Homebrew present, smartctl missing, previous install attempt failed -> button + error line.
    let installableWithError = DashboardModel()
    installableWithError.smartToolsState = .installable
    installableWithError.smartInstallError = L.storageSmartInstallFailed("Error: Permission denied")
    installableWithError.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good)
    ]

    // C: Homebrew itself missing -> hint text only, no button.
    let needsHomebrew = DashboardModel()
    needsHomebrew.smartToolsState = .needsHomebrew
    needsHomebrew.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good)
    ]

    harnessRender(width: 460) {
        HarnessSection(label: "A: .installable (button)") {
            SmartDisksCard(model: installable)
        }
        HarnessSection(label: "B: .installable + smartInstallError") {
            SmartDisksCard(model: installableWithError)
        }
        HarnessSection(label: "C: .needsHomebrew (hint, no button)") {
            SmartDisksCard(model: needsHomebrew)
        }
    }
}
