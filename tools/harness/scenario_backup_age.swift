// tools/harness/scenario_backup_age.swift
// BACKUP-AGE render scenario: ClaudeBackupCard in its five states (3 h fresh, 51 h stale,
// no success in the log, unreadable, nil = renders nothing) plus the Settings «Бэкап» section.
// Russian by default; BACKUP_AGE_LANG=en renders English; BACKUP_AGE_VIEW=settings renders only the
// Settings window (wider than the cards, so it gets its own render). See tools/harness/README.md (render.sh).

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    L10nStore.shared.language = ProcessInfo.processInfo.environment["BACKUP_AGE_LANG"] == "en" ? .en : .ru

    @MainActor func model(_ s: ClaudeBackupStatus?) -> DashboardModel {
        let m = DashboardModel()
        m.claudeBackup = s
        return m
    }
    let now = Date()
    let fresh = model(.lastSuccess(now.addingTimeInterval(-3 * 3600)))
    let stale = model(.lastSuccess(now.addingTimeInterval(-51 * 3600)))
    let none = model(.noSuccessFound)
    let unreadable = model(.unreadable)
    let absent = model(nil)

    if ProcessInfo.processInfo.environment["BACKUP_AGE_VIEW"] == "settings" {
        harnessRender(width: 760) {
            HarnessSection(label: "F: Settings, Backup section") { SettingsView(model: fresh, startSection: .backup) }
        }
        return
    }

    harnessRender(width: 460) {
        HarnessSection(label: "A: 3 h ago (normal ink)") { ClaudeBackupCard(model: fresh) }
        HarnessSection(label: "B: 51 h ago (amber)") { ClaudeBackupCard(model: stale) }
        HarnessSection(label: "C: no success in the log (amber)") { ClaudeBackupCard(model: none) }
        HarnessSection(label: "D: unreadable (normal ink)") { ClaudeBackupCard(model: unreadable) }
        HarnessSection(label: "E: nil (must be empty)") { ClaudeBackupCard(model: absent) }
    }
}
