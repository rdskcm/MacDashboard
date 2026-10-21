// tools/harness/scenario_backups.swift
// REDESIGN-BACKUPS render scenario: the Time Machine card in its states (A–J), the Claude card in its states
// (K–O) and the page bar (P). Russian by default; BACKUPS_LANG=en renders English; BACKUPS_VIEW=narrow renders
// the narrow layout (width 904) for B and D only. See tools/harness/README.md (render.sh).

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    let env = ProcessInfo.processInfo.environment
    L10nStore.shared.language = env["BACKUPS_LANG"] == "en" ? .en : .ru

    @MainActor func model(_ tweak: (DashboardModel) -> Void) -> DashboardModel {
        let m = DashboardModel()
        m.applyVisualFixture()
        tweak(m)
        return m
    }
    let ref = VisualFixture.referenceDate
    func dest(last: Date?, mounted: Bool, schedule: TMSchedule? = .automatic(intervalSeconds: 3600)) -> TMDestination {
        TMDestination(name: "Backup SSD", kind: "Local", mountPoint: mounted ? "/Volumes/Backup SSD" : nil,
                      quotaBytes: nil, lastBackup: last.map { Parsers.formatTMBackupDate($0) },
                      lastBackupDate: last, freeBytes: mounted ? 612_000_000_000 : nil, schedule: schedule)
    }
    @MainActor func tm(_ d: TMDestination, backup: TMBackupProgress? = nil, action: TMActionState = .idle) -> DashboardModel {
        model { $0.report.tmDest = .some(d); $0.applyFixtureTimeMachine(backup: backup, action: action) }
    }
    let sample = TMBackupProgress(running: true, stopping: false, phase: "Copying", percent: 0.140625,
                                  bytesDone: 1_800_000_000, bytesTotal: 12_800_000_000, secondsRemaining: 600,
                                  destinationMountPoint: "/Volumes/Backup")

    let notset = model { _ in }
    let ok = tm(dest(last: ref - 50 * 60, mounted: true))
    let okNoFDA = tm(dest(last: ref - 50 * 60, mounted: true, schedule: nil))
    let over7Off = tm(dest(last: ref - 9 * 86_400, mounted: false))
    let over30Off = tm(dest(last: ref - 34 * 86_400, mounted: false))
    let over7On = tm(dest(last: ref - 9 * 86_400, mounted: true))
    let backingDest = dest(last: ref - 86_400 - 2 * 3600, mounted: true)
    let backing = tm(backingDest, backup: sample)
    let stopping = tm(backingDest, backup: sample, action: .stopping)
    let preparing = tm(backingDest, backup: TMBackupProgress(running: true, stopping: false, phase: "PreparingSourceVolumes"))
    let findingChanges = tm(backingDest, backup: TMBackupProgress(running: true, stopping: false, phase: "FindingChanges", changedItems: 31_711, scanFraction: 0.53))
    let failed = tm(dest(last: ref - 9 * 86_400, mounted: true), action: .failed(L.bkStartDidNotBegin))
    @MainActor func claude(_ s: ClaudeBackupStatus?) -> DashboardModel { model { $0.claudeBackup = s } }

    if env["BACKUPS_VIEW"] == "narrow" {
        harnessRender(width: 904) {
            HarnessSection(label: "B: ok (narrow)") { BackupsTimeMachineCard(model: ok, narrow: true) }
            HarnessSection(label: "D: overdue 7, unmounted (narrow)") { BackupsTimeMachineCard(model: over7Off, narrow: true) }
        }
        return
    }

    harnessRender(width: 1094) {
        HarnessSection(label: "A: not set up") { BackupsTimeMachineCard(model: notset, narrow: false) }
        HarnessSection(label: "B: ok") { BackupsTimeMachineCard(model: ok, narrow: false) }
        HarnessSection(label: "C: ok, schedule unreadable (no FDA)") { BackupsTimeMachineCard(model: okNoFDA, narrow: false) }
        HarnessSection(label: "D: overdue 7 d, unmounted") { BackupsTimeMachineCard(model: over7Off, narrow: false) }
        HarnessSection(label: "E: overdue 30 d, unmounted") { BackupsTimeMachineCard(model: over30Off, narrow: false) }
        HarnessSection(label: "F: overdue 7 d, mounted") { BackupsTimeMachineCard(model: over7On, narrow: false) }
        HarnessSection(label: "G: backing up 14 %") { BackupsTimeMachineCard(model: backing, narrow: false) }
        HarnessSection(label: "H: stopping") { BackupsTimeMachineCard(model: stopping, narrow: false) }
        HarnessSection(label: "I: preparing (no percent)") { BackupsTimeMachineCard(model: preparing, narrow: false) }
        HarnessSection(label: "I2: looking for changes (31 711, 53 %)") { BackupsTimeMachineCard(model: findingChanges, narrow: false) }
        HarnessSection(label: "J: start failed") { BackupsTimeMachineCard(model: failed, narrow: false) }
        HarnessSection(label: "K: Claude ok") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600))) }
        HarnessSection(label: "L: Claude stale") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 4 * 86_400))) }
        HarnessSection(label: "M: Claude none") { BackupsClaudeCard(model: claude(.noSuccessFound)) }
        HarnessSection(label: "N: Claude missing") { BackupsClaudeCard(model: claude(nil)) }
        HarnessSection(label: "O: Claude unreadable") { BackupsClaudeCard(model: claude(.unreadable)) }
        HarnessSection(label: "P1: bar, not set up") { BackupsPageBar(model: notset) {} }
        HarnessSection(label: "P2: bar, ok") { BackupsPageBar(model: ok) {} }
        HarnessSection(label: "P3: bar, overdue 30") { BackupsPageBar(model: over30Off) {} }
        HarnessSection(label: "P4: bar, backing up") { BackupsPageBar(model: backing) {} }
    }
}
