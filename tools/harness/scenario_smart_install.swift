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
    installable.smart.applyFixture(updatedAt: nil, tools: .installable, installing: false, failure: nil)
    installable.report.smartctlPresent = false
    installable.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good),
        SmartDisk(device: "/dev/disk4", title: "External HDD", status: "SMART недоступен", attrs: [], severity: .warn)
    ]

    // B: Homebrew present, smartctl missing, previous install attempt failed -> button + error line.
    let installableWithError = DashboardModel()
    installableWithError.smart.applyFixture(updatedAt: nil, tools: .installable, installing: false, failure: .exitCode(1))
    installableWithError.report.smartctlPresent = false
    installableWithError.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good)
    ]

    // C: Homebrew itself missing -> hint text only, no button.
    let needsHomebrew = DashboardModel()
    needsHomebrew.smart.applyFixture(updatedAt: nil, tools: .needsHomebrew, installing: false, failure: nil)
    needsHomebrew.report.smartctlPresent = false
    needsHomebrew.report.smart = [
        SmartDisk(device: "internal", title: "Внутренний SSD", status: "SMART: подтверждён", attrs: [], severity: .good)
    ]

    harnessRender(width: 1094) {
        HarnessSection(label: "A: .installable (button)") {
            StorageSmartCard(model: installable, breakpoints: PageBreakpoints(width: 1150))
        }
        HarnessSection(label: "B: .installable + install failure") {
            StorageSmartCard(model: installableWithError, breakpoints: PageBreakpoints(width: 1150))
        }
        HarnessSection(label: "C: .needsHomebrew (hint, no button)") {
            StorageSmartCard(model: needsHomebrew, breakpoints: PageBreakpoints(width: 1150))
        }
    }
}
