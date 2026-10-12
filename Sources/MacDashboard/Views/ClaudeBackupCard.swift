// Views/ClaudeBackupCard.swift
// BACKUP-AGE: age of the last successful Claude backup, read from its log. Renders
// nothing at all when the log is absent (model.claudeBackup == nil), so a Mac without
// this backup sees no card and no spacing.
import SwiftUI

@MainActor
struct ClaudeBackupCard: View {
    let model: DashboardModel

    var body: some View {
        if let status = model.claudeBackup {
            CardChrome(title: L.claudeBackupCardTitle) {
                TimelineView(.everyMinute) { ctx in
                    rows(status, now: model.fixtureNow ?? ctx.date)
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ status: ClaudeBackupStatus, now: Date) -> some View {
        let limit = AppSettings.shared.backupStaleHours
        let stale = BackupLog.isStale(status, thresholdHours: limit, now: now)
        VStack(alignment: .leading, spacing: 10) {
            TMRow(label: L.claudeBackupAgeLabel, value: ageText(status, now: now),
                  valueColor: stale ? DS.amberInk : DS.inkSoft, tabularNumerals: true)
                .hoverTip(L.settingsBackupStaleNote)
            if case .lastSuccess(let d) = status {
                TMRow(label: L.claudeBackupLastLabel,
                      value: d.formatted(date: .abbreviated, time: .shortened), tabularNumerals: true)
            }
            TMRow(label: L.claudeBackupLimitLabel, value: L.settingsBackupStaleOption(limit))
        }
    }

    private func ageText(_ status: ClaudeBackupStatus, now: Date) -> String {
        switch status {
        case .lastSuccess(let d):
            let age = max(0, now.timeIntervalSince(d))
            return age < 60 ? L.claudeBackupJustNow : L.claudeBackupAgo(BackupLog.durationText(seconds: Int(age)))
        case .noSuccessFound: return L.claudeBackupNoneFound
        case .unreadable: return L.claudeBackupUnreadable
        }
    }
}
