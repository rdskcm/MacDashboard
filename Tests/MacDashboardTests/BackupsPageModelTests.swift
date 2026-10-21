// Tests/MacDashboardTests/BackupsPageModelTests.swift
// REDESIGN-BACKUPS: Backups page state, texts, tones, tiles and tag (pure model; no tmutil, no store access).
import Foundation
import Testing
@testable import MacDashboard

/// Local noon on a fixed day, so «50 min ago» / «2 h ago» never cross midnight in any time zone.
private let t0: Date = {
    var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 9; c.hour = 12; c.minute = 0
    return Calendar.current.date(from: c)!
}()
private let min = 60.0, hr = 3600.0, dy = 86_400.0

private func dest(name: String? = "Backup SSD", mount: String? = "/Volumes/Backup SSD", last: Date?,
                  free: Int64? = 612_000_000_000, schedule: TMSchedule? = .automatic(intervalSeconds: 3600),
                  reason: TMBackupUnavailableReason? = nil) -> TMDestination {
    TMDestination(name: name, kind: "Local", mountPoint: mount, quotaBytes: nil, lastBackup: nil,
                  lastBackupUnavailableReason: reason, lastBackupDate: last, freeBytes: free, schedule: schedule)
}

private func input(_ d: TMDestination??, snapshots: [String]? = nil, backup: TMBackupProgress? = nil,
                   action: TMActionState = .idle, updatedAt: Date? = nil, claude: ClaudeBackupStatus? = nil,
                   warn: Int = 48) -> BackupsPageModel.Input {
    .init(tmDest: d, snapshots: snapshots, backup: backup, action: action, updatedAt: updatedAt, claudeBackup: claude,
          claudeLogPath: BackupLog.logURL.path, warnAfterHours: warn, now: t0)
}

private func withLanguage(_ lang: AppLanguage, _ body: () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

private func state(_ d: TMDestination, backup: TMBackupProgress? = nil, action: TMActionState = .idle) -> TMCardState {
    BackupsPageModel.tmState(dest: d, backup: backup, action: action, now: t0)
}

extension SerialTests {
    struct BackupsPageModelTests {
        // MARK: state

        @Test func overdueThresholds() {
            #expect(state(dest(last: t0 - (7 * dy - hr))) == .ok)
            #expect(state(dest(last: t0 - 7 * dy)) == .ok, "exactly 7 d is not overdue")
            #expect(state(dest(last: t0 - (7 * dy + hr))) == .overdue7)
            #expect(state(dest(last: t0 - 30 * dy)) == .overdue7, "exactly 30 d is still amber")
            #expect(state(dest(last: t0 - (30 * dy + hr))) == .overdue30)
            #expect(state(dest(last: nil)) == .ok, "unknown age is not overdue")
            #expect(BackupsPageModel.daysSince(t0 + 3 * dy, now: t0) == 0, "a future date never goes negative")
            #expect(BackupsPageModel.daysSince(t0 - (9 * dy + hr), now: t0) == 9)
        }

        @Test func backingBeatsOverdue() {
            let old = dest(last: t0 - 40 * dy)
            #expect(state(old, backup: TMBackupProgress(running: true, stopping: false)) == .backing)
            #expect(state(old, action: .starting) == .backing)
            #expect(state(old, action: .stopping) == .backing)
            #expect(state(old, backup: TMBackupProgress(running: false, stopping: false)) == .overdue30)
            #expect(state(old, action: .failed("x")) == .overdue30, "a failed start leaves the card in its normal state")
        }

        @Test func makeStates() {
            withLanguage(.en) {
                #expect(BackupsPageModel.make(input(nil)).tmState == .wait)
                let ns = BackupsPageModel.make(input(.some(nil), snapshots: ["com.apple.TimeMachine.2026-05-09-090000.local"]))
                #expect(ns.tmState == .notSet)
                #expect(ns.tmTiles.map(\.id) == ["snaps", "purgeable", "dest"])
                #expect(ns.tmNote?.button == .setUp)
                let ok = BackupsPageModel.make(input(.some(.some(dest(last: t0 - 50 * min)))))
                #expect(ok.tmTiles.map(\.id) == ["last", "next", "dest", "snaps"])
                #expect(ok.tmNote == nil)
                #expect(ok.tmFailure == nil)
                let failed = BackupsPageModel.make(input(.some(.some(dest(last: t0 - 9 * dy))), action: .failed("boom")))
                #expect(failed.tmFailure == "boom")
                #expect(failed.tmNote?.button == .backUpNow(enabled: true), "a failed start may be retried")
            }
        }

        // MARK: last backup

        @Test func lastBackupTexts() {
            withLanguage(.en) {
                let cal = Calendar.current
                #expect(BackupsPageModel.lastBackupText(t0 - 50 * min, now: t0, calendar: cal) == "today, 11:10")
                #expect(BackupsPageModel.lastBackupText(t0 - dy, now: t0, calendar: cal) == "yesterday, 12:00")
                #expect(BackupsPageModel.lastBackupText(t0 - 5 * dy, now: t0, calendar: cal) == L.shortDateTime(t0 - 5 * dy))
                let ok = BackupsPageModel.lastBackupTile(dest: dest(last: t0 - 50 * min), state: .ok, now: t0)
                #expect(ok.value == "today, 11:10")
                #expect(ok.dot == .green)
                #expect(ok.note == "50 min ago")
                #expect(ok.noteTone == .green)
                let fresh = BackupsPageModel.lastBackupTile(dest: dest(last: t0 - 20), state: .ok, now: t0)
                #expect(fresh.note == L.claudeBackupJustNow)
            }
        }

        @Test func lastBackupDaysEnAndRu() {
            let cases: [(Int, String, String)] = [
                (9, "9 days ago", "9 дней назад"), (1, "1 day ago", "1 день назад"),
                (34, "34 days ago", "34 дня назад"), (25, "25 days ago", "25 дней назад"),
                (11, "11 days ago", "11 дней назад"), (22, "22 days ago", "22 дня назад"),
            ]
            for (n, en, ru) in cases {
                withLanguage(.en) { #expect(L.bkDaysAgo(n) == en) }
                withLanguage(.ru) { #expect(L.bkDaysAgo(n) == ru) }
            }
            withLanguage(.ru) {
                let t = BackupsPageModel.lastBackupTile(dest: dest(last: t0 - 50 * min), state: .ok, now: t0)
                #expect(t.note == "50 мин назад")
            }
            withLanguage(.en) {
                let o7 = BackupsPageModel.lastBackupTile(dest: dest(last: t0 - 9 * dy), state: .overdue7, now: t0)
                #expect(o7.value == "9 days ago"); #expect(o7.valueTone == .amber); #expect(o7.dot == .amber); #expect(o7.noteTone == .amber)
                let o30 = BackupsPageModel.lastBackupTile(dest: dest(last: t0 - 34 * dy), state: .overdue30, now: t0)
                #expect(o30.valueTone == .hot); #expect(o30.dot == .hot)
            }
        }

        @Test func lastBackupWithoutDate() {
            withLanguage(.en) {
                let none = BackupsPageModel.lastBackupTile(dest: dest(last: nil), state: .ok, now: t0)
                #expect(none.value == "—"); #expect(none.valueTone == .neutral)
                let noBackups = BackupsPageModel.lastBackupTile(dest: dest(last: nil, reason: .noBackupsYet), state: .ok, now: t0)
                #expect(noBackups.value == TMBackupUnavailableReason.noBackupsYet.localizedText)
                #expect(noBackups.valueTone == .neutral)
                let fda = BackupsPageModel.lastBackupTile(dest: dest(last: nil, reason: .dateUnavailableNoFDA), state: .ok, now: t0)
                #expect(fda.valueTone == .amber); #expect(fda.note == "Full Disk Access needed"); #expect(fda.noteTone == .amber)
            }
        }

        // MARK: next backup

        @Test func nextBackup() {
            withLanguage(.en) {
                func next(_ d: TMDestination, _ st: TMCardState = .ok) -> BackupsTile { BackupsPageModel.nextBackupTile(dest: d, state: st, now: t0) }
                #expect(next(dest(last: t0 - 50 * min)).value == "in 10 min")
                #expect(next(dest(last: t0 - 2 * hr)).value == "soon")
                #expect(next(dest(mount: nil, last: t0 - 50 * min)).value == "when connected")
                #expect(next(dest(last: t0 - 50 * min), .backing).value == "after this one")
                let noFDA = next(dest(last: t0 - 50 * min, schedule: nil))
                #expect(noFDA.value == "—"); #expect(noFDA.note == "Full Disk Access needed")
                let manual = next(dest(last: t0 - 50 * min, schedule: .manual))
                #expect(manual.value == "—"); #expect(manual.note == "automatic backups are off")
                #expect(next(dest(last: nil)).value == "soon", "automatic without a date")
            }
        }

        // MARK: destination, snapshots

        @Test func destinationTile() {
            withLanguage(.en) {
                let t = BackupsPageModel.destinationTile(dest: dest(last: nil))
                #expect(t.value == "Backup SSD"); #expect(t.note == "612 GB free")
                let off = BackupsPageModel.destinationTile(dest: dest(mount: nil, last: nil, free: nil), state: .overdue30)
                #expect(off.note == "not connected"); #expect(off.noteTone == .hot)
                #expect(BackupsPageModel.destinationTile(dest: dest(mount: nil, last: nil), state: .overdue7).noteTone == .amber)
                #expect(BackupsPageModel.destinationTile(dest: dest(mount: nil, last: nil), state: .ok).noteTone == nil)
                #expect(BackupsPageModel.destinationTile(dest: dest(last: nil, free: nil)).note == nil, "statfs failed")
                let unnamed = BackupsPageModel.destinationTile(dest: dest(name: nil, last: nil))
                #expect(unnamed.value == "—"); #expect(unnamed.valueTone == .neutral)
            }
            withLanguage(.ru) {
                #expect(BackupsPageModel.destinationTile(dest: dest(last: nil)).note == "свободно 612 ГБ")
            }
        }

        @Test func snapshotsTile() {
            withLanguage(.en) {
                let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
                let day = df.string(from: t0)
                let names = ["com.apple.TimeMachine.\(day)-060000.local", "com.apple.TimeMachine.\(day)-090000.local",
                             "com.apple.TimeMachine.\(day)-070000.local"]
                let t = BackupsPageModel.snapshotsTile(names: names, now: t0)
                #expect(t.value == "3")
                #expect(t.note == "latest today at 09:00")
                #expect(BackupsPageModel.snapshotsTile(names: nil, now: t0).value == "—")
                let none = BackupsPageModel.snapshotsTile(names: [], now: t0)
                #expect(none.value == "0"); #expect(none.note == nil)
                let old = BackupsPageModel.snapshotsTile(names: ["com.apple.TimeMachine.2026-05-01-090000.local"], now: t0)
                #expect(old.note?.hasPrefix("latest ") == true); #expect(old.note?.contains("today") == false)
            }
        }

        // MARK: caption

        @Test func caption() {
            withLanguage(.en) {
                func cap(_ d: TMDestination, _ st: TMCardState = .ok, updated: Date? = nil) -> String? {
                    BackupsPageModel.caption(dest: d, state: st, updatedAt: updated)
                }
                #expect(cap(dest(last: nil)) == "automatic · every hour")
                #expect(cap(dest(mount: nil, last: nil)) == "automatic · every hour · disk not connected")
                #expect(cap(dest(mount: nil, last: nil, schedule: nil)) == "disk not connected")
                #expect(cap(dest(last: nil, schedule: nil), updated: t0 - 90 * min) == "updated 10:30")
                #expect(cap(dest(last: nil, schedule: nil)) == nil)
                #expect(cap(dest(last: nil, schedule: .manual)) == "manual")
                #expect(cap(dest(last: nil, schedule: .automatic(intervalSeconds: 7200))) == "automatic · every 2 h")
                #expect(cap(dest(last: nil, schedule: .automatic(intervalSeconds: 86_400))) == "automatic · every day")
                #expect(cap(dest(last: nil, schedule: .automatic(intervalSeconds: 604_800))) == "automatic · every week")
                #expect(cap(dest(last: nil), .backing) == "backup in progress")
                #expect(cap(dest(last: nil), .notSet, updated: t0) == "updated 12:00")
                #expect(cap(dest(last: nil), .wait, updated: nil) == nil)
            }
        }

        // MARK: overdue note, progress

        @Test func overdueNote() {
            withLanguage(.en) {
                let off = BackupsPageModel.overdueNote(dest: dest(mount: nil, last: nil), days: 9, hot: false)
                #expect(off.text == "The last backup was 9 days ago. Connect Backup SSD to continue.")
                #expect(off.button == .backUpNow(enabled: false)); #expect(off.tone == .amber)
                let on = BackupsPageModel.overdueNote(dest: dest(last: nil), days: 9, hot: false)
                #expect(on.text == "The last backup was 9 days ago. Back up now to catch up.")
                #expect(on.button == .backUpNow(enabled: true))
                let hot = BackupsPageModel.overdueNote(dest: dest(last: nil), days: 34, hot: true)
                #expect(hot.tone == .hot); #expect(hot.text == "The last backup was 34 days ago, more than a month. Back up now.")
                let busy = BackupsPageModel.overdueNote(dest: dest(last: nil), days: 9, hot: false, action: .starting)
                #expect(busy.button == .backUpNow(enabled: false))
                let unnamed = BackupsPageModel.overdueNote(dest: dest(name: nil, mount: nil, last: nil), days: 9, hot: false)
                #expect(unnamed.text.contains("the backup disk"))
            }
            withLanguage(.ru) {
                #expect(BackupsPageModel.overdueNote(dest: dest(last: nil), days: 22, hot: false).text
                        == "Последняя копия была 22 дня назад. Создайте копию сейчас.")
            }
        }

        @Test func progressCaption() {
            withLanguage(.en) {
                #expect(BackupsPageModel.bytesCaption(done: 1_800_000_000, total: 12_800_000_000, secondsRemaining: 600)
                        == "1.8 of 12.8 GB · about 10 min left")
                #expect(BackupsPageModel.bytesCaption(done: 900_000_000_000, total: 1_200_000_000_000, secondsRemaining: 60)
                        == "900 GB of 1.2 TB · about 1 min left")
                #expect(BackupsPageModel.bytesCaption(done: 1, total: nil, secondsRemaining: 5) == "preparing…")
                #expect(BackupsPageModel.bytesCaption(done: 1, total: 0, secondsRemaining: 5) == "preparing…")
                #expect(BackupsPageModel.bytesCaption(done: 1_800_000_000, total: 12_800_000_000, secondsRemaining: 0) == "1.8 of 12.8 GB")
                let d = dest(last: nil)
                let running = TMBackupProgress(running: true, stopping: false, percent: 0.14, bytesDone: 1_800_000_000, bytesTotal: 12_800_000_000)
                let p = BackupsPageModel.progress(dest: d, backup: running, action: .idle)
                #expect(p.text == "Backing up to Backup SSD"); #expect(p.fraction == 0.14); #expect(!p.stopping)
                #expect(BackupsPageModel.progress(dest: d, backup: running, action: .stopping).caption == "stopping…")
                #expect(BackupsPageModel.progress(dest: d, backup: TMBackupProgress(running: true, stopping: true), action: .idle).stopping)
                #expect(BackupsPageModel.progress(dest: d, backup: .idle, action: .starting).caption == "preparing…")
            }
            withLanguage(.ru) {
                #expect(BackupsPageModel.bytesCaption(done: 1_800_000_000, total: 12_800_000_000, secondsRemaining: 600)
                        == "1,8 из 12,8 ГБ · осталось около 10 мин")
            }
        }

        // MARK: Claude

        @Test func claudeStates() {
            withLanguage(.en) {
                let missing = BackupsPageModel.make(input(nil, claude: nil))
                #expect(missing.claudeState == .missing); #expect(missing.claudeNote?.button == .openSettingsBackups)
                #expect(missing.claudeNote?.tone == .neutral)
                #expect(missing.claudeNote?.text == "Log not found: ~/Library/Logs/claude-backup.log")
                #expect(missing.claudeCaption == "from ~/Library/Logs/claude-backup.log")
                let unreadable = BackupsPageModel.make(input(nil, claude: .unreadable))
                #expect(unreadable.claudeState == .unreadable); #expect(unreadable.claudeNote?.button == .openFullDiskAccess)
                #expect(unreadable.claudeNote?.tone == .amber)
                let none = BackupsPageModel.make(input(nil, claude: .noSuccessFound))
                #expect(none.claudeState == .noneFound); #expect(none.claudeNote?.tone == .amber)
                #expect(none.claudeTiles[0].valueTone == .amber)
                let ok = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr)))
                #expect(ok.claudeState == .ok); #expect(ok.claudeNote == nil)
                #expect(ok.claudeTiles.map(\.id) == ["age", "lastSnap", "warn"])
                #expect(ok.claudeTiles[0].value == "5 h ago"); #expect(ok.claudeTiles[0].dot == .green)
                #expect(ok.claudeTiles[0].note == "OK")
                #expect(ok.claudeTiles[2].value == "2 d"); #expect(ok.claudeTiles[2].note == "change in Settings")
                let stale = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 4 * dy)))
                #expect(stale.claudeState == .stale); #expect(stale.claudeNote?.tone == .amber)
                #expect(stale.claudeNote?.text.contains("2 d") == true)
                #expect(stale.claudeTiles[0].valueTone == .amber); #expect(stale.claudeTiles[0].note == "over the limit")
            }
        }

        // MARK: tag

        @Test func tagTable() {
            withLanguage(.en) {
                let table: [(TMCardState, ClaudeCardState, BackupsTone, String)] = [
                    (.ok, .ok, .green, "All good"),
                    (.wait, .missing, .neutral, "Collecting data…"),
                    (.wait, .ok, .neutral, "Collecting data…"),
                    (.notSet, .ok, .amber, "Time Machine not set up"),
                    (.notSet, .stale, .amber, "Time Machine not set up"),
                    (.ok, .stale, .amber, "Claude backup is stale"),
                    (.ok, .noneFound, .amber, "Claude backup is stale"),
                    (.ok, .missing, .neutral, "Claude log not found"),
                    (.ok, .unreadable, .neutral, "Claude log unreadable"),
                    (.overdue7, .ok, .amber, "Backup overdue"),
                    (.overdue30, .ok, .hot, "Backup overdue"),
                    (.overdue30, .stale, .hot, "Backup overdue"),
                    (.backing, .ok, .accent, "Backing up…"),
                    (.backing, .missing, .accent, "Backing up…"),
                    (.backing, .stale, .amber, "Claude backup is stale"),
                ]
                for (tm, cl, tone, text) in table {
                    let r = BackupsPageModel.tag(tm: tm, claude: cl)
                    #expect(r.0 == tone && r.1 == text, "\(tm) + \(cl) → \(r)")
                }
            }
        }

        // MARK: plist, paths

        @Test func plistSchedule() {
            #expect(Parsers.tmPlistSchedule(["AutoBackup": true]) == .automatic(intervalSeconds: 3600))
            #expect(Parsers.tmPlistSchedule(["AutoBackup": 1, "AutoBackupInterval": 86_400]) == .automatic(intervalSeconds: 86_400))
            #expect(Parsers.tmPlistSchedule(["AutoBackup": true, "AutoBackupInterval": 0]) == .automatic(intervalSeconds: 3600))
            #expect(Parsers.tmPlistSchedule(["AutoBackup": false]) == .manual)
            #expect(Parsers.tmPlistSchedule(["AutoBackup": false, "AutoBackupInterval": 7200]) == .manual, "the switch wins")
            #expect(Parsers.tmPlistSchedule([:]) == nil)
            #expect(Parsers.tmPlistSchedule(["AutoBackup": "yes"]) == nil)
        }

        @Test func abbreviateHome() {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            #expect(BackupsPageModel.abbreviateHome(home + "/Library/Logs/claude-backup.log") == "~/Library/Logs/claude-backup.log")
            #expect(BackupsPageModel.abbreviateHome("/var/log/x.log") == "/var/log/x.log")
            #expect(BackupsPageModel.abbreviateHome(home + "other/x") == home + "other/x", "a sibling directory is not under home")
        }

        @Test func volumeFreeBytes() {
            let free = ReportCollector.volumeFreeBytes(atPath: "/")
            #expect(free != nil && free! > 0)
            #expect(ReportCollector.volumeFreeBytes(atPath: "/definitely/not/a/path") == nil)
        }
    }
}
