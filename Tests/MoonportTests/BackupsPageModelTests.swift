// Tests/MoonportTests/BackupsPageModelTests.swift
// REDESIGN-BACKUPS: Backups page state, texts, tones, tiles and tag (pure model; no tmutil, no store access).
import Foundation
import Testing
@testable import Moonport

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
                   warn: Int = 48, attempt: ClaudeBackupAttempt? = nil, job: ClaudeBackupJob? = nil, disk: Bool? = nil,
                   clickAction: ClaudeBackupAction = .idle, defaultLog: Bool = true, progress: Double? = nil) -> BackupsPageModel.Input {
    .init(tmDest: d, snapshots: snapshots, backup: backup, action: action, updatedAt: updatedAt, claudeBackup: claude,
          claudeLogPath: BackupLog.logURL.path, warnAfterHours: warn, now: t0,
          claudeAttempt: attempt, claudeProgress: progress, claudeJob: job, claudeDiskConnected: disk, claudeAction: clickAction, claudeUsesDefaultLog: defaultLog)
}

private let runJob = ClaudeBackupJob(label: "x", appPath: "/Apps/ClaudeBackup.app", schedule: [.init(minute: 0, hour: 13)], startsOnMount: true)
private func att(_ r: ClaudeBackupAttempt.Result, ago: Double = 3 * 3600) -> ClaudeBackupAttempt {
    .init(at: t0 - ago, result: r, mount: "/Volumes/Backup SSD")
}

@MainActor private func withLanguage(_ lang: AppLanguage, _ body: @MainActor () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

private func state(_ d: TMDestination, backup: TMBackupProgress? = nil, action: TMActionState = .idle) -> TMCardState {
    BackupsPageModel.tmState(dest: d, backup: backup, action: action, now: t0)
}

extension SerialTests {
    @MainActor struct BackupsPageModelTests {
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
                #expect(failed.tmNote?.button == nil, "the overdue note has no button; the header button retries")
                #expect(failed.tmButton?.enabled == true, "a failed start may be retried")
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
                @MainActor func next(_ d: TMDestination, _ st: TMCardState = .ok) -> BackupsTile { BackupsPageModel.nextBackupTile(dest: d, state: st, now: t0) }
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

        @Test func deleteSnapshotsButton() {
            let names = (1...3).map { "com.apple.TimeMachine.2026-05-09-0\($0)0000.local" }
            func make(_ d: TMDestination??, names: [String]?, backup: TMBackupProgress? = nil, delete: SnapshotDeleteState = .idle, open: Bool = false) -> BackupsPageModel {
                var i = input(d, backup: backup)
                i.deleteNames = names; i.snapshotDelete = delete; i.deleteConfirmOpen = open
                return BackupsPageModel.make(i)
            }
            let ok: TMDestination?? = .some(.some(dest(last: t0 - 2 * hr)))
            let running = TMBackupProgress(running: true, stopping: false, phase: "Copying")
            withLanguage(.en) {
                let enabled = BackupsTMDeleteButton(title: "Delete 3 snapshots", enabled: true, busy: false, help: nil)
                #expect(make(ok, names: names).tmDeleteButton == enabled)
                #expect(make(.some(nil), names: names).tmDeleteButton == enabled, "not set up: snapshots may remain")
                #expect(make(.some(nil), names: names).tmButton == nil)
                #expect(make(.some(.some(dest(mount: nil, last: t0 - 40 * dy))), names: names).tmDeleteButton == enabled, "overdue, disk away")
                #expect(make(ok, names: ["com.apple.TimeMachine.2026-05-09-010000.local"]).tmDeleteButton?.title == "Delete 1 snapshot")
                #expect(make(nil, names: names).tmDeleteButton == nil, "wait")
                #expect(make(ok, names: []).tmDeleteButton == nil, "none")
                #expect(make(ok, names: nil).tmDeleteButton == BackupsTMDeleteButton(title: "Delete snapshots", enabled: false, busy: false, help: "The snapshot list hasn’t been read yet."))
                #expect(make(ok, names: names, backup: running).tmDeleteButton == BackupsTMDeleteButton(title: "Delete 3 snapshots", enabled: false, busy: false, help: "A backup is running. Delete snapshots when it finishes."))
                let busy = make(ok, names: names, delete: .deleting)
                #expect(busy.tmDeleteButton == BackupsTMDeleteButton(title: "Delete 3 snapshots", enabled: false, busy: true, help: nil))
                #expect(busy.tmButton?.enabled == false && busy.tmButton?.help == "Snapshots are being deleted.")
                #expect(make(ok, names: [], delete: .deleting).tmDeleteButton?.busy == true, "the re-read landed before the run ended")
                #expect(make(ok, names: names).tmSnapshotsExplanation != nil, "the Stage 1 line stays")
            }
            withLanguage(.ru) {
                #expect(make(ok, names: names).tmDeleteButton?.title == "Удалить 3 снимка")
            }
        }

        @Test func deleteConfirmation() {
            let names = (1...3).map { "com.apple.TimeMachine.2026-05-09-0\($0)0000.local" }
            func make(_ d: TMDestination??, names: [String]?, backup: TMBackupProgress? = nil, open: Bool) -> BackupsPageModel {
                var i = input(d, backup: backup)
                i.deleteNames = names; i.deleteConfirmOpen = open
                return BackupsPageModel.make(i)
            }
            let ok: TMDestination?? = .some(.some(dest(last: t0 - 2 * hr)))
            withLanguage(.en) {
                let c = make(ok, names: names, open: true).tmDeleteConfirm
                #expect(c?.title == "Delete 3 local snapshots?")
                #expect(c?.text == "Deleted snapshots can’t be brought back. Backups on an external disk are not touched. While automatic backups are on, macOS creates new snapshots, so the count will go up again.")
                #expect(c?.confirmA11y == "Delete 3 snapshots" && c?.names == names)
                #expect(make(ok, names: names, open: false).tmDeleteConfirm == nil)
                #expect(make(ok, names: nil, open: true).tmDeleteConfirm == nil, "unread")
                #expect(make(ok, names: [], open: true).tmDeleteConfirm == nil, "none left")
                #expect(make(ok, names: names, backup: TMBackupProgress(running: true, stopping: false, phase: "Copying"), open: true).tmDeleteConfirm == nil, "backup running")
                #expect(make(.some(nil), names: names, open: true).tmDeleteConfirm?.names == names, "not set up")
            }
            withLanguage(.ru) {
                let c = make(ok, names: names, open: true).tmDeleteConfirm
                #expect(c?.title == "Удалить 3 локальных снимка?")
                #expect(c?.text == "Удалённые снимки нельзя вернуть. Копии на внешнем диске не затрагиваются. Пока включено автоматическое копирование, macOS создаёт новые снимки, поэтому их число снова вырастет.")
                #expect(make(ok, names: ["com.apple.TimeMachine.2026-05-09-010000.local"], open: true).tmDeleteConfirm?.title == "Удалить 1 локальный снимок?")
            }
        }

        @Test func deleteOutcomeNotes() {
            func note(_ deleted: Int, _ failed: Int, _ failure: SnapshotDeleteFailure?) -> BackupsNote? {
                BackupsPageModel.tmDeleteNote(.finished(SnapshotDeleteResult(deleted: deleted, failed: failed, failure: failure)))
            }
            let line = "Failed to delete local snapshot '2026-11-03-043250'"
            #expect(BackupsPageModel.tmDeleteNote(.idle) == nil && BackupsPageModel.tmDeleteNote(.deleting) == nil)
            withLanguage(.en) {
                #expect(note(3, 0, nil) == BackupsNote(tone: .green, text: "Deleted 3 snapshots.", button: nil))
                #expect(note(1, 0, nil)?.text == "Deleted 1 snapshot.")
                #expect(note(0, 0, nil) == BackupsNote(tone: .green, text: "macOS has already removed these snapshots.", button: nil))
                #expect(note(1, 2, .tool(line)) == BackupsNote(tone: .hot, text: "Deleted 1 of 3 snapshots. The others are still on the disk: \(line)", button: nil))
                #expect(note(0, 3, .tool(line)) == BackupsNote(tone: .hot, text: "Couldn’t delete 3 snapshots: \(line). Check that the app has Full Disk Access.", button: .openFullDiskAccess))
                #expect(note(0, 3, .tool(nil))?.text == "Couldn’t delete 3 snapshots: tmutil gave no reason. Check that the app has Full Disk Access.")
                #expect(note(0, 3, .tool("Operation failed."))?.text == "Couldn’t delete 3 snapshots: Operation failed. Check that the app has Full Disk Access.")
                let unreadable = BackupsPageModel.tmDeleteNote(.finished(SnapshotDeleteResult(deleted: 0, failed: 2, failure: .tool(nil), unparsable: 2)))
                #expect(unreadable?.button == nil && unreadable?.text.contains("Full Disk Access") == false, "unreadable names are not an access problem")
                let mixed = BackupsPageModel.tmDeleteNote(.finished(SnapshotDeleteResult(deleted: 0, failed: 3, failure: .tool(line), unparsable: 1)))
                #expect(mixed?.button == .openFullDiskAccess, "tmutil itself failed on one")
                #expect(note(0, 3, .permission) == BackupsNote(tone: .hot, text: "Couldn’t delete 3 snapshots: the app needs Full Disk Access. Turn it on in Privacy & Security, then try again.", button: .openFullDiskAccess))
                #expect(note(1, 2, .permission)?.button == .openFullDiskAccess)
                #expect(note(0, 1, .backupRunning) == BackupsNote(tone: .hot, text: "Couldn’t delete 1 snapshot: a backup is running. Try again when it finishes.", button: nil))
                #expect(note(0, 2, .timedOut)?.button == nil)
                #expect(note(0, 2, .timedOut)?.text == "Couldn’t delete 2 snapshots: tmutil did not answer in 60 s.")
            }
            withLanguage(.ru) {
                #expect(note(1, 0, nil)?.text == "Удалён 1 снимок.")
                #expect(note(3, 0, nil)?.text == "Удалено 3 снимка.")
                #expect(note(5, 0, nil)?.text == "Удалено 5 снимков.")
                #expect(note(1, 2, .tool(line))?.text == "Удалено 1 из 3. Остальные снимки остались на диске: \(line)")
                #expect(note(0, 3, .permission)?.text == "Не удалось удалить 3 снимка: приложению нужен полный доступ к диску. Включите его в разделе «Конфиденциальность и безопасность» и повторите.")
            }
        }

        @Test func snapshotsExplanation() {
            let textEN = "Restore points on this Mac’s disk. macOS deletes them on its own when it needs the space."
            let textRU = "Точки восстановления на диске этого Mac. macOS удаляет их сама, когда нужно место."
            func shown(_ s: TMSchedule?) -> String? {
                BackupsPageModel.make(input(.some(.some(dest(last: t0 - 50 * min, schedule: s))))).tmSnapshotsExplanation
            }
            withLanguage(.en) {
                #expect(shown(.automatic(intervalSeconds: 3600)) == textEN)
                #expect(shown(.automatic(intervalSeconds: 86_400)) == textEN)
                #expect(shown(.automatic(intervalSeconds: 604_800)) == textEN)
                #expect(shown(.manual) == textEN)
                #expect(shown(nil) == textEN, "schedule unreadable without Full Disk Access")
                #expect(BackupsPageModel.make(input(nil)).tmSnapshotsExplanation == nil, "wait: no tiles")
                let snap = ["com.apple.TimeMachine.2026-05-09-090000.local"]
                #expect(BackupsPageModel.make(input(.some(nil), snapshots: snap)).tmSnapshotsExplanation == textEN, "not set, with old snapshots")
                let overdue = BackupsPageModel.make(input(.some(.some(dest(mount: nil, last: t0 - 40 * dy)))))
                #expect(overdue.tmState == .overdue30); #expect(overdue.tmSnapshotsExplanation == textEN)
                let backing = BackupsPageModel.make(input(.some(.some(dest(last: t0 - 2 * hr))), action: .starting))
                #expect(backing.tmState == .backing); #expect(backing.tmSnapshotsExplanation == textEN)
                let unread = BackupsPageModel.make(input(.some(.some(dest(last: t0 - 2 * hr))), snapshots: nil))
                #expect(unread.tmTiles.first { $0.id == "snaps" }?.value == "—"); #expect(unread.tmSnapshotsExplanation == textEN)
                let zero = BackupsPageModel.make(input(.some(.some(dest(last: t0 - 2 * hr))), snapshots: []))
                #expect(zero.tmTiles.first { $0.id == "snaps" }?.value == "0"); #expect(zero.tmSnapshotsExplanation == textEN)
            }
            withLanguage(.ru) { #expect(shown(.automatic(intervalSeconds: 3600)) == textRU) }
        }

        // MARK: caption

        @Test func caption() {
            withLanguage(.en) {
                @MainActor func cap(_ d: TMDestination, _ st: TMCardState = .ok, updated: Date? = nil) -> String? {
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
                #expect(off.button == nil); #expect(off.tone == .amber)
                let on = BackupsPageModel.overdueNote(dest: dest(last: nil), days: 9, hot: false)
                #expect(on.text == "The last backup was 9 days ago. Back up now to catch up.")
                #expect(on.button == nil)
                let hot = BackupsPageModel.overdueNote(dest: dest(last: nil), days: 34, hot: true)
                #expect(hot.tone == .hot); #expect(hot.text == "The last backup was 34 days ago, more than a month. Back up now.")
                let unnamed = BackupsPageModel.overdueNote(dest: dest(name: nil, mount: nil, last: nil), days: 9, hot: false)
                #expect(unnamed.text.contains("the backup disk"))
            }
            withLanguage(.ru) {
                #expect(BackupsPageModel.overdueNote(dest: dest(last: nil), days: 22, hot: false).text
                        == "Последняя копия была 22 дня назад. Создайте копию сейчас.")
            }
        }

        @Test func tmButtonRules() {
            func button(_ d: TMDestination, backup: TMBackupProgress? = nil, action: TMActionState = .idle) -> BackupsTMButton? {
                BackupsPageModel.make(input(.some(.some(d)), backup: backup, action: action)).tmButton
            }
            let fresh = dest(last: t0 - 50 * min), overdue = dest(last: t0 - 9 * dy), hot = dest(last: t0 - 34 * dy)
            let off = dest(mount: nil, last: t0 - 50 * min), offOverdue = dest(mount: nil, last: t0 - 9 * dy), offHot = dest(mount: nil, last: t0 - 34 * dy)
            let running = TMBackupProgress(running: true, stopping: false)
            let ready = BackupsTMButton(enabled: true, busy: false, primary: false, help: nil)
            let attention = BackupsTMButton(enabled: true, busy: false, primary: true, help: nil)
            let waiting = BackupsTMButton(enabled: false, busy: false, primary: false, help: nil)
            let spinning = BackupsTMButton(enabled: false, busy: true, primary: false, help: nil)
            withLanguage(.en) {
                let noDisk = BackupsTMButton(enabled: false, busy: false, primary: false, help: "Connect Backup SSD first")
                // No destination, or not read yet: no button.
                #expect(BackupsPageModel.make(input(nil)).tmButton == nil)
                #expect(BackupsPageModel.make(input(.some(nil))).tmButton == nil)
                // Idle.
                #expect(button(fresh) == ready)
                #expect(button(dest(last: nil)) == ready, "unknown age is not overdue")
                #expect(button(fresh, backup: .idle) == ready, "a poll that found nothing running")
                #expect(button(overdue) == attention)
                #expect(button(hot) == attention)
                // Disk not connected: disabled, never primary, tooltip names the disk.
                #expect(button(off) == noDisk)
                #expect(button(offOverdue) == noDisk)
                #expect(button(offHot) == noDisk)
                #expect(button(dest(name: nil, mount: nil, last: nil))?.help == "Connect the backup disk first")
                // Starting: spinner, never primary.
                #expect(button(fresh, action: .starting) == spinning)
                #expect(button(overdue, action: .starting) == spinning)
                // Running and stopping: disabled, no spinner, no tooltip, even when the stored mount lags.
                #expect(button(fresh, backup: running) == waiting)
                #expect(button(overdue, backup: running) == waiting)
                #expect(button(off, backup: running) == waiting)
                #expect(button(off, backup: TMBackupProgress(running: true, stopping: false, destinationMountPoint: "/Volumes/Backup SSD")) == waiting)
                #expect(button(fresh, backup: TMBackupProgress(running: true, stopping: true)) == waiting)
                #expect(button(fresh, backup: running, action: .stopping) == waiting)
                // Failed: retry allowed; a failed Stop during a backup stays disabled.
                #expect(button(fresh, action: .failed("x")) == ready)
                #expect(button(overdue, action: .failed("x")) == attention)
                #expect(button(off, action: .failed("x")) == noDisk)
                #expect(button(fresh, backup: running, action: .failed("x")) == waiting)
            }
            withLanguage(.ru) {
                #expect(button(off)?.help == "Сначала подключите Backup SSD")
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
                let running = TMBackupProgress(running: true, stopping: false, phase: "Copying", percent: 0.14, bytesDone: 1_800_000_000, bytesTotal: 12_800_000_000)
                let p = BackupsPageModel.progress(dest: d, backup: running, action: .idle)
                #expect(p.text == "Backing up to Backup SSD"); #expect(abs((p.fraction ?? -1) - 0.226) < 1e-9); #expect(!p.stopping)
                #expect(BackupsPageModel.progress(dest: d, backup: running, action: .stopping).caption == "stopping…")
                #expect(BackupsPageModel.progress(dest: d, backup: TMBackupProgress(running: true, stopping: true), action: .idle).stopping)
                #expect(BackupsPageModel.progress(dest: d, backup: .idle, action: .starting).caption == "preparing…")
            }
            withLanguage(.ru) {
                #expect(BackupsPageModel.bytesCaption(done: 1_800_000_000, total: 12_800_000_000, secondsRemaining: 600)
                        == "1,8 из 12,8 ГБ · осталось около 10 мин")
            }
        }

        @Test func captionShowsMegabytesUnderOneGigabyte() {
            func cap(_ done: Int64?, _ total: Int64, _ secs: Int? = nil) -> String {
                BackupsPageModel.bytesCaption(done: done, total: total, secondsRemaining: secs)
            }
            let total: Int64 = 146_952_908_800
            withLanguage(.en) {
                #expect(cap(45_465_600, total) == "45.5 MB of 147 GB")
                #expect(cap(21_577_728, total) == "21.6 MB of 147 GB")
                #expect(cap(0, total) == "0 MB of 147 GB")
                #expect(cap(nil, total) == "0 MB of 147 GB")
                #expect(cap(40_000, total) == "0.1 MB of 147 GB")
                #expect(cap(999_900_000, total) == "999.9 MB of 147 GB")
                #expect(cap(999_960_000, total) == "1 of 147 GB", "rounds up to a whole GB")
                #expect(cap(12_000_000, 800_000_000) == "12 of 800 MB")
                #expect(cap(45_465_600, 12_800_000_000, 600) == "45.5 MB of 12.8 GB · about 10 min left")
            }
            withLanguage(.ru) {
                #expect(cap(45_465_600, total) == "45,5 МБ из 147 ГБ")
                #expect(cap(12_000_000, 800_000_000) == "12 из 800 МБ")
            }
        }

        @Test func fmtCapacityStaysInGigabytes() {
            withLanguage(.en) {
                #expect(fmtCapacity(45_465_600) == "0 GB")
                #expect(fmtCapacityParts(45_465_600).unit == "GB")
            }
        }

        @Test func aRunningBackupsMountPointBeatsTheStoredRead() {
            let stale = dest(mount: nil, last: nil, free: nil)
            let live = TMBackupProgress(running: true, stopping: false, phase: "Copying", destinationMountPoint: "/Volumes/Live")
            #expect(BackupsPageModel.effectiveDestination(stale, backup: live).mountPoint == "/Volumes/Live")
            #expect(BackupsPageModel.effectiveDestination(dest(mount: "/Volumes/Old", last: nil), backup: live).mountPoint == "/Volumes/Live")
            #expect(BackupsPageModel.effectiveDestination(stale, backup: nil).mountPoint == nil)
            let finished = TMBackupProgress(running: false, stopping: false, destinationMountPoint: "/Volumes/Live")
            #expect(BackupsPageModel.effectiveDestination(stale, backup: finished).mountPoint == nil, "an idle sample proves nothing")
        }

        /// R2: every way into `.backing`, each with a stored read that says «not connected».
        @Test func aBackupInProgressNeverSaysNotConnected() {
            withLanguage(.en) {
                let stale = dest(mount: nil, last: nil, free: nil)
                let withKey = TMBackupProgress(running: true, stopping: false, phase: "Copying", destinationMountPoint: "/Volumes/Live")
                let withoutKey = TMBackupProgress(running: true, stopping: false, phase: "PreparingSourceVolumes")
                let cases: [(TMBackupProgress?, TMActionState)] = [
                    (withKey, .idle), (withoutKey, .idle), (withKey, .stopping), (withoutKey, .stopping), (nil, .starting),
                ]
                for (backup, action) in cases {
                    let m = BackupsPageModel.make(input(.some(.some(stale)), backup: backup, action: action))
                    #expect(m.tmState == .backing)
                    #expect(m.tmTiles.first { $0.id == "dest" }?.note != L.bkNotConnected)
                    #expect(m.tmTiles.first { $0.id == "next" }?.value != L.bkNextWhenConnected)
                    #expect(m.tmCaption?.contains(L.bkCaptionDiskNotConnected) != true)
                    #expect(m.tmNote == nil)
                }
                // The same stored read with no backup still says it: the correction is not global.
                let idle = BackupsPageModel.make(input(.some(.some(stale)), backup: .idle))
                #expect(idle.tmTiles.first { $0.id == "dest" }?.note == L.bkNotConnected)
            }
        }

        @Test func findingChangesCaption() {
            let d = dest(last: nil)
            let fc = TMBackupProgress(running: true, stopping: false, phase: "FindingChanges", changedItems: 31_711, scanFraction: 0.53)
            let none = TMBackupProgress(running: true, stopping: false, phase: "FindingChanges")
            withLanguage(.en) {
                let p = BackupsPageModel.progress(dest: d, backup: fc, action: .idle)
                #expect(p.caption == "Looking for changes · found 31,711"); #expect(abs((p.fraction ?? -1) - 0.053) < 1e-9); #expect(p.text == "Backing up to Backup SSD")
                let n = BackupsPageModel.progress(dest: d, backup: none, action: .idle)
                #expect(n.caption == "Looking for changes…"); #expect(n.fraction == nil)
                #expect(BackupsPageModel.progress(dest: d, backup: fc, action: .stopping).caption == "stopping…")
            }
            withLanguage(.ru) {
                #expect(BackupsPageModel.progress(dest: d, backup: fc, action: .idle).caption == "Поиск изменений · найдено 31\u{2009}711")
                #expect(BackupsPageModel.progress(dest: d, backup: none, action: .idle).caption == "Поиск изменений…")
            }
        }

        @Test func finishingPhasesCaption() {
            let d = dest(last: nil)
            let thin = TMBackupProgress(running: true, stopping: false, phase: "ThinningPostBackup")
            let fin = TMBackupProgress(running: true, stopping: false, phase: "Finishing")
            let prep = TMBackupProgress(running: true, stopping: false, phase: "PreparingSourceVolumes")
            withLanguage(.en) {
                for b in [thin, fin] {
                    let p = BackupsPageModel.progress(dest: d, backup: b, action: .idle)
                    #expect(p.caption == L.bkFinishing); #expect(p.fraction == nil)
                }
                #expect(BackupsPageModel.progress(dest: d, backup: thin, action: .stopping).caption == L.bkStopping)
                #expect(BackupsPageModel.progress(dest: d, backup: prep, action: .idle).caption == L.bkPreparing)
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
                #expect(ok.claudeTiles[2].value == "2 days"); #expect(ok.claudeTiles[2].note == "change in Settings")
                let stale = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 4 * dy)))
                #expect(stale.claudeState == .stale); #expect(stale.claudeNote?.tone == .amber)
                #expect(stale.claudeNote?.text.contains("2 days") == true)
                #expect(stale.claudeTiles[0].valueTone == .amber); #expect(stale.claudeTiles[0].note == "over the limit")
            }
        }


        // MARK: Claude attempt (BACKUP-CARD-FAILURE)

        @Test func claudeFailedNoteTexts() {
            let table: [(ClaudeBackupAttempt.Reason, String, String)] = [
                (.diskDisconnected, "the disk disconnected during the copy", "диск отключился во время копирования"),
                (.diskError, "the disk reported a read or write error", "диск сообщил об ошибке чтения или записи"),
                (.noSpace, "the backup disk is full", "на диске для копий нет места"),
                (.noPermission, "macOS refused access to the disk or to files", "macOS не дала доступ к диску или файлам"),
                (.filesChanged, "files changed while they were being copied", "файлы менялись во время копирования"),
                (.other, "the copy stopped with error code 23", "копирование остановилось с кодом ошибки 23"),
            ]
            for (reason, en, ru) in table {
                withLanguage(.en) {
                    let m = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr), attempt: att(.failed(exit: 23, reason: reason)), job: runJob))
                    #expect(m.claudeNote?.text == "The last backup attempt failed: \(en). Older snapshots were not touched.")
                    #expect(m.claudeNote?.tone == .amber && m.claudeNote?.text.contains("job") == false)
                }
                withLanguage(.ru) {
                    let m = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr), attempt: att(.failed(exit: 23, reason: reason)), job: runJob))
                    #expect(m.claudeNote?.text == "Последняя попытка бэкапа не удалась: \(ru). Старые снимки не затронуты.")
                }
            }
        }

        @Test func claudeRunProgressPanel() {
            func run(_ p: Double?, _ r: ClaudeBackupAttempt.Result = .running) -> BackupsPageModel {
                BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr), attempt: att(r, ago: 300), job: runJob, progress: p))
            }
            withLanguage(.en) {
                let a = run(0.62)
                #expect(a.claudeRunProgress?.caption == "62 %" && a.claudeRunProgress?.fraction == 0.62)
                #expect(a.claudeRunProgress?.text == L.bkClaudeProgressText && a.claudeRunProgress?.stopping == false)
                #expect(a.claudeNote == nil)
                #expect(run(0.99).claudeRunProgress?.caption == L.bkClaudeProgressFinishing)
                let n = run(nil)
                #expect(n.claudeRunProgress != nil && n.claudeRunProgress?.fraction == nil && n.claudeRunProgress?.caption == "")
                #expect(run(0.5, .ok).claudeRunProgress == nil)
                #expect(run(nil, .interrupted).claudeRunProgress == nil)
            }
        }

        @Test func claudeNoteChoice() {
            for lang in AppLanguage.allCases {
                withLanguage(lang) {
                    let stale = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 4 * dy), attempt: att(.ok, ago: 4 * dy), job: runJob))
                    #expect(stale.claudeNote?.text.contains(L.settingsWarnAfterDays(2)) == true)
                    #expect(stale.claudeNote?.text == L.bkNoteClaudeStaleNoRun(L.settingsWarnAfterDays(2)))
                    let noJob = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 4 * dy)))
                    #expect(noJob.claudeNote?.text == L.bkNoteClaudeStale(L.settingsWarnAfterDays(2)))
                    let staleFailed = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 4 * dy), attempt: att(.failed(exit: 1, reason: .other)), job: runJob))
                    #expect(staleFailed.claudeNote?.text == L.bkNoteClaudeFailed(BackupLog.reasonText(.other, exit: 1, language: L10nStore.shared.language)))
                    let noneFailed = BackupsPageModel.make(input(nil, claude: .noSuccessFound, attempt: att(.failed(exit: 1, reason: .other)), job: runJob))
                    #expect(noneFailed.claudeNote?.text == L.bkNoteClaudeFailed(BackupLog.reasonText(.other, exit: 1, language: L10nStore.shared.language)))
                    let fresh = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr), attempt: att(.failed(exit: 1, reason: .other)), job: runJob))
                    #expect(fresh.claudeState == .ok && fresh.claudeNote?.text == L.bkNoteClaudeFailed(BackupLog.reasonText(.other, exit: 1, language: L10nStore.shared.language)))
                    let intr = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr), attempt: att(.interrupted), job: runJob))
                    #expect(intr.claudeNote?.text == L.bkNoteClaudeInterrupted)
                    let run = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr), attempt: att(.running, ago: 300), job: runJob))
                    #expect(run.claudeNote == nil)
                    let missing = BackupsPageModel.make(input(nil, claude: nil, attempt: att(.ok), job: runJob))
                    #expect(missing.claudeNote?.button == .openSettingsBackups)
                    let unreadable = BackupsPageModel.make(input(nil, claude: .unreadable, attempt: att(.failed(exit: 1, reason: .other)), job: runJob))
                    #expect(unreadable.claudeNote?.button == .openFullDiskAccess)
                }
            }
        }

        @Test func claudeRunTilesAndAttemptTile() {
            withLanguage(.en) {
                let none = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr)))
                #expect(none.claudeRunTiles.isEmpty)
                let withJob = BackupsPageModel.make(input(nil, claude: .lastSuccess(t0 - 5 * hr), job: runJob))
                #expect(withJob.claudeRunTiles.map(\.id) == ["attempt", "next", "size"] && withJob.claudeTiles.map(\.id) == ["age", "lastSnap", "warn"])
                #expect(withJob.claudeRunTiles[0].value == BackupsPageModel.dash)
                let noSize = BackupsPageModel.claudeSizeTile(nil)
                #expect(noSize.id == "size" && noSize.value == BackupsPageModel.dash && noSize.note == "appears after the next backup")
                let size = ClaudeBackupSize(snapshotBytes: 28_548_000_000, addedBytes: 467_000_000, totalBytes: 38_654_000_000)
                let sized = BackupsPageModel.claudeSizeTile(size)
                #expect(sized.value == fmtBytes(size.snapshotBytes) && sized.valueTone == nil)
                #expect(sized.note == "\(fmtBytes(size.addedBytes)) new · all snapshots \(fmtBytes(size.totalBytes))")
                let ok = BackupsPageModel.claudeAttemptTile(att(.ok), now: t0)
                #expect(ok.value == "today, 09:00" && ok.dot == .green && ok.note == "succeeded" && ok.noteTone == .green)
                let run = BackupsPageModel.claudeAttemptTile(att(.running, ago: 7 * min), now: t0)
                #expect(run.dot == .accent && run.note == "running for 7 min" && run.noteTone == .accent)
                let intr = BackupsPageModel.claudeAttemptTile(att(.interrupted), now: t0)
                #expect(intr.dot == .amber && intr.note == "did not finish" && intr.noteTone == .amber)
                let fail = BackupsPageModel.claudeAttemptTile(att(.failed(exit: 23, reason: .filesChanged)), now: t0)
                #expect(fail.dot == .amber && fail.note == "failed, code 23" && fail.noteTone == .amber)
            }
        }

        @Test func claudeNextTile() {
            withLanguage(.en) {
                @MainActor func next(job: ClaudeBackupJob? = runJob, _ a: ClaudeBackupAttempt? = nil, success: Double? = 7 * hr, disk: Bool? = true) -> BackupsTile {
                    BackupsPageModel.claudeNextTile(job: job, attempt: a, status: success.map { .lastSuccess(t0 - $0) }, diskConnected: disk, now: t0)
                }
                #expect(next(job: nil).note == "no scheduled job found")
                #expect(next(att(.running, ago: 60)).value == "after this one")
                var t = next(disk: false)                                           // past the 6 h pause, disk off
                #expect(t.value == "when connected" && t.note == "disk not connected" && t.noteTone == .amber)
                t = next(success: 3 * hr, disk: false)                              // inside the pause
                #expect(t.value == "tomorrow, 13:00" && t.note == "if the disk is connected")
                t = next(); #expect(t.value == "today, 13:00" && t.note == "disk connected")
                t = next(disk: nil); #expect(t.value == "today, 13:00" && t.note == "if the disk is connected")
                let none = ClaudeBackupJob(label: nil, appPath: nil, schedule: [], startsOnMount: false)
                #expect(next(job: none).value == "no schedule")
                let later = ClaudeBackupJob(label: nil, appPath: nil, schedule: [.init(minute: 0, hour: 13, day: 12)], startsOnMount: false)
                #expect(next(job: later).value == L.shortDateTime(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 13))!))
            }
        }

        @Test func claudeButtonRules() {
            let noApp = ClaudeBackupJob(label: nil, appPath: nil, schedule: [], startsOnMount: false)
            func button(job: ClaudeBackupJob? = runJob, _ status: ClaudeBackupStatus? = .lastSuccess(t0 - 5 * hr), a: ClaudeBackupAttempt? = nil,
                        action: ClaudeBackupAction = .idle, defaultLog: Bool = true) -> BackupsClaudeButton? {
                BackupsPageModel.make(input(nil, claude: status, attempt: a, job: job, clickAction: action, defaultLog: defaultLog)).claudeButton
            }
            #expect(button(job: nil) == nil && button(job: noApp) == nil && button(defaultLog: false) == nil && button(.unreadable) == nil)
            #expect(button(nil) == BackupsClaudeButton(busy: false, primary: false))
            #expect(button(action: .starting)?.busy == true && button(a: att(.running, ago: 60))?.busy == true)
            #expect(button(.lastSuccess(t0 - 4 * dy))?.primary == true && button(.noSuccessFound)?.primary == true)
            #expect(button(a: att(.failed(exit: 1, reason: .other)))?.primary == true && button(a: att(.interrupted))?.primary == true)
            #expect(button(a: att(.ok))?.primary == false)
        }

        @Test func claudeActionNotes() {
            for lang in AppLanguage.allCases {
                withLanguage(lang) {
                    #expect(BackupsPageModel.claudeActionNote(.idle) == nil && BackupsPageModel.claudeActionNote(.starting) == nil)
                    let n = BackupsPageModel.claudeActionNote
                    #expect(n(.diskNotConnected) == BackupsNote(tone: .amber, text: L.bkClaudeClickNoDisk, button: nil))
                    #expect(n(.alreadyRunning) == BackupsNote(tone: .neutral, text: L.bkClaudeClickAlreadyRunning, button: nil))
                    #expect(n(.noResponse) == BackupsNote(tone: .amber, text: L.bkClaudeClickNoResponse, button: nil))
                    #expect(n(.launchFailed) == BackupsNote(tone: .hot, text: L.bkClaudeClickLaunchFailed, button: nil))
                }
            }
            withLanguage(.en) { #expect(L.bkClaudeClickNoDisk == "The backup disk is not connected, so no backup started. Connect it and try again.") }
        }

        @Test func claudeTagWithAttempt() {
            withLanguage(.en) {
                typealias R = ClaudeBackupAttempt.Result
                @MainActor func tag(_ tm: TMCardState, _ cl: ClaudeCardState, _ r: R?) -> (BackupsTone, String) { BackupsPageModel.tag(tm: tm, claude: cl, attempt: r) }
                #expect(tag(.ok, .ok, .failed(exit: 1, reason: .other)) == (.amber, "Claude backup failed"))
                #expect(tag(.ok, .stale, .running) == (.accent, "Claude backup running"))
                #expect(tag(.ok, .ok, .interrupted) == (.amber, "Claude backup did not finish"))
                #expect(tag(.backing, .ok, .running) == (.accent, "Backing up…"))
                #expect(tag(.overdue30, .ok, .failed(exit: 1, reason: .other)) == (.hot, "Backup overdue"))
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

        // MARK: destination facts (REDESIGN-INFO-RESTORE)

        private func destKind(_ kind: String?, quota: Int64?) -> TMDestination {
            var d = dest(last: t0 - 50 * min); d.kind = kind; d.quotaBytes = quota; return d
        }

        @Test func kindText() {
            withLanguage(.en) {
                #expect(BackupsPageModel.kindText("Local") == "Local disk")
                #expect(BackupsPageModel.kindText("Network") == "Network disk")
                #expect(BackupsPageModel.kindText(" network\n") == "Network disk")
                #expect(BackupsPageModel.kindText("LOCAL") == "Local disk")
                #expect(BackupsPageModel.kindText("Cloud") == "Cloud")
                #expect(BackupsPageModel.kindText(nil) == nil)
                #expect(BackupsPageModel.kindText("") == nil)
                #expect(BackupsPageModel.kindText("  ") == nil)
            }
            withLanguage(.ru) {
                #expect(BackupsPageModel.kindText("Local") == "Локальный диск")
                #expect(BackupsPageModel.kindText("Network") == "Сетевой диск")
            }
        }

        @Test func destinationFactsLines() {
            let q: Int64 = 500_000_000_000
            withLanguage(.en) {
                #expect(BackupsPageModel.destinationFacts(destKind("Local", quota: nil)) == [SectionFactLine(label: "Type", text: "Local disk")])
                #expect(BackupsPageModel.destinationFacts(destKind("Network", quota: q))
                        == [.init(label: "Type", text: "Network disk"), .init(label: "Quota", text: fmtCapacity(q))])
                #expect(fmtCapacity(q).hasPrefix("500"))
                #expect(BackupsPageModel.destinationFacts(destKind(nil, quota: q)) == [.init(label: "Quota", text: fmtCapacity(q))])
                #expect(BackupsPageModel.destinationFacts(destKind(nil, quota: nil)).isEmpty)
                #expect(BackupsPageModel.destinationFacts(destKind("Local", quota: 0)) == [.init(label: "Type", text: "Local disk")])
            }
            withLanguage(.ru) {
                #expect(BackupsPageModel.destinationFacts(destKind("Network", quota: q))
                        == [.init(label: "Тип", text: "Сетевой диск"), .init(label: "Квота", text: fmtCapacity(q))])
            }
        }

        @Test func destinationFactsByState() {
            withLanguage(.en) {
                let net = BackupsPageModel.make(input(.some(destKind("Network", quota: 500_000_000_000))))
                #expect(net.tmDestinationFacts.count == 2)
                let gone = BackupsPageModel.make(input(.some(dest(mount: nil, last: t0 - 34 * dy))))
                #expect(gone.tmState == .overdue30)
                #expect(gone.tmDestinationFacts == [.init(label: "Type", text: "Local disk")])
                let backing = BackupsPageModel.make(input(.some(destKind("Local", quota: nil)),
                                                          backup: TMBackupProgress(running: true, stopping: false, phase: "Copying")))
                #expect(backing.tmState == .backing)
                #expect(backing.tmDestinationFacts == [.init(label: "Type", text: "Local disk")])
                let notSet = BackupsPageModel.make(input(.some(nil)))
                #expect(notSet.tmDestinationFacts.isEmpty && notSet.tmSnapshotsExplanation != nil)
                #expect(BackupsPageModel.make(input(nil)).tmDestinationFacts.isEmpty)
            }
        }
    }
}
