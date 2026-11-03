// Engine/Strings/Strings+Backups.swift
// Time Machine card, Claude backup card and Backups page: the `BackupsStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol BackupsStrings {
    // MARK: Time Machine card
    var timeMachineNotConfigured: String { get }
    var timeMachineDestination: String { get }
    var timeMachineType: String { get }
    var timeMachineTypeLocal: String { get }
    var timeMachineQuota: String { get }
    var timeMachineLastBackup: String { get }
    /// V2-TM-CONNSTATE: label + value of the row shown only while the destination has no
    /// mount point (disk unplugged, or network share not mounted).
    var timeMachineConnection: String { get }
    var timeMachineConnectionNone: String { get }
    var timeMachineSnapshots: String { get }
    var timeMachineSnapshotsNone: String { get }
    func timeMachineSnapshotsCount(_ n: Int) -> String
    func timeMachineSnapshotsLast(_ date: String) -> String
    var timeMachinePurgeable: String { get }
    /// Records the constraint the tip text encodes: the number is a VOLUME total that also
    /// covers caches, and a per-snapshot size is not a real number because snapshots share
    /// disk blocks (BACKLOG F1).
    var timeMachinePurgeableTip: String { get }

    // MARK: Claude backup card (BACKUP-AGE)
    var claudeBackupCardTitle: String { get }
    var claudeBackupAgeLabel: String { get }
    var claudeBackupLastLabel: String { get }
    var claudeBackupLimitLabel: String { get }
    func claudeBackupAgo(_ age: String) -> String
    var claudeBackupJustNow: String { get }
    var claudeBackupNoneFound: String { get }
    var claudeBackupUnreadable: String { get }

    // MARK: Backups page (REDESIGN-BACKUPS)
    var bkSub: String { get }
    var bkTagTMNotSet: String { get }
    var bkTagOverdue: String { get }
    var bkTagBacking: String { get }
    var bkTagClaudeStale: String { get }
    var bkTagClaudeMissing: String { get }
    var bkTagClaudeUnreadable: String { get }
    var bkCaptionAutoHourly: String { get }
    var bkCaptionAutoDaily: String { get }
    var bkCaptionAutoWeekly: String { get }
    func bkCaptionAutoEveryHours(_ n: Int) -> String
    var bkCaptionManual: String { get }
    var bkCaptionDiskNotConnected: String { get }
    var bkCaptionBacking: String { get }
    var bkNoteNotSet: String { get }
    func bkNoteOverdueDisconnected(_ days: Int, _ disk: String) -> String
    func bkNoteOverdueDisconnectedHot(_ days: Int, _ disk: String) -> String
    func bkNoteOverdueConnected(_ days: Int) -> String
    func bkNoteOverdueConnectedHot(_ days: Int) -> String
    var bkTheBackupDisk: String { get }
    func bkDaysAgo(_ n: Int) -> String
    func bkToday(_ t: String) -> String
    func bkYesterday(_ t: String) -> String
    var bkLastBackup: String { get }
    var bkNextBackup: String { get }
    func bkNextIn(_ d: String) -> String
    var bkNextSoon: String { get }
    var bkNextWhenConnected: String { get }
    var bkNextAfterThis: String { get }
    var bkNextAutoOff: String { get }
    func bkFree(_ s: String) -> String
    var bkNotConnected: String { get }
    var bkPurgeable: String { get }
    var bkPurgeableNote: String { get }
    func bkLatestSnapshotToday(_ t: String) -> String
    func bkLatestSnapshot(_ d: String) -> String
    var bkBackUpNow: String { get }
    var bkBackUpNowA11y: String { get }
    func bkConnectFirst(_ disk: String) -> String
    var bkStop: String { get }
    var bkStopA11y: String { get }
    var bkSetUpA11y: String { get }
    func bkBackingTo(_ disk: String) -> String
    func bkProgressBytes(_ done: String, _ total: String) -> String
    func bkTimeLeft(_ d: String) -> String
    var bkPreparing: String { get }
    var bkFinishing: String { get }
    func bkFindingChanges(_ count: String) -> String
    var bkFindingChangesNoCount: String { get }
    var bkStopping: String { get }
    func bkStartFailed(_ why: String) -> String
    var bkStartDidNotBegin: String { get }
    func bkStopFailed(_ why: String) -> String
    var bkFailedNoReason: String { get }
    func bkClaudeCaption(_ path: String) -> String
    var bkAgeOK: String { get }
    var bkOverLimit: String { get }
    var bkChangeInSettings: String { get }
    func bkNoteClaudeStale(_ limit: String) -> String
    var bkNoteClaudeNone: String { get }
    func bkNoteClaudeMissing(_ path: String) -> String
    var bkOpenSettingsBackups: String { get }
    var bkOpenSettingsBackupsA11y: String { get }
    func bkNoteClaudeUnreadable(_ path: String) -> String
    var bkOpenPrivacy: String { get }
    var bkOpenPrivacyA11y: String { get }
    // BACKUP-CARD-FAILURE
    var bkClaudeAttemptLabel: String { get }
    var bkClaudeNextLabel: String { get }
    var bkClaudeSizeLabel: String { get }
    var bkClaudeSizeNone: String { get }
    func bkClaudeSizeNote(added: String, total: String) -> String
    var bkClaudeAttemptOK: String { get }
    func bkClaudeAttemptFailed(_ exit: Int) -> String
    func bkClaudeAttemptRunning(_ d: String) -> String
    var bkClaudeAttemptInterrupted: String { get }
    func bkTomorrow(_ t: String) -> String
    var bkClaudeNextIfDisk: String { get }
    var bkClaudeNextDiskOn: String { get }
    var bkClaudeNextNoSchedule: String { get }
    var bkClaudeNextNoJob: String { get }
    func bkNoteClaudeFailed(_ reason: String) -> String
    var bkNoteClaudeInterrupted: String { get }
    var bkClaudeProgressText: String { get }
    var bkClaudeProgressFinishing: String { get }
    func bkNoteClaudeStaleNoRun(_ limit: String) -> String
    var bkClaudeReasonDiskGone: String { get }
    var bkClaudeReasonDiskError: String { get }
    var bkClaudeReasonNoSpace: String { get }
    var bkClaudeReasonNoPermission: String { get }
    var bkClaudeReasonFilesChanged: String { get }
    func bkClaudeReasonOther(_ exit: Int) -> String
    var bkTagClaudeFailed: String { get }
    var bkTagClaudeInterrupted: String { get }
    var bkTagClaudeRunning: String { get }
    var bkClaudeClickNoDisk: String { get }
    var bkClaudeClickAlreadyRunning: String { get }
    var bkClaudeClickNoResponse: String { get }
    var bkClaudeClickLaunchFailed: String { get }
    var bkClaudeBackUpNowA11y: String { get }
}

extension StringsEN: BackupsStrings {
    // MARK: Time Machine card
    var timeMachineNotConfigured: String { "Time Machine is not configured" }
    var timeMachineDestination: String { "Destination" }
    var timeMachineType: String { "Type" }
    var timeMachineTypeLocal: String { "local disk" }
    var timeMachineQuota: String { "Quota" }
    var timeMachineLastBackup: String { "Last backup" }
    var timeMachineConnection: String { "Connection" }
    var timeMachineConnectionNone: String { "not connected right now" }
    var timeMachineSnapshots: String { "Local snapshots" }
    var timeMachineSnapshotsNone: String { "none" }
    func timeMachineSnapshotsCount(_ n: Int) -> String { "\(n)" }
    func timeMachineSnapshotsLast(_ date: String) -> String { ", last \(date)" }
    var timeMachinePurgeable: String { "Purgeable space" }
    var timeMachinePurgeableTip: String { "Space macOS frees on its own when it is needed: Time Machine local snapshots and caches. A per-snapshot size cannot be computed — snapshots share disk blocks." }

    // MARK: Claude backup card (BACKUP-AGE)
    var claudeBackupCardTitle: String { "Claude backup" }
    var claudeBackupAgeLabel: String { "Age" }
    var claudeBackupLastLabel: String { "Last snapshot" }
    var claudeBackupLimitLabel: String { "Warn after" }
    func claudeBackupAgo(_ age: String) -> String { "\(age) ago" }
    var claudeBackupJustNow: String { "just now" }
    var claudeBackupNoneFound: String { "no successful snapshot in the log" }
    var claudeBackupUnreadable: String { "the log could not be read" }

    // MARK: Backups page (REDESIGN-BACKUPS)
    var bkSub: String { "Time Machine and Claude backup" }
    var bkTagTMNotSet: String { "Time Machine not set up" }
    var bkTagOverdue: String { "Backup overdue" }
    var bkTagBacking: String { "Backing up…" }
    var bkTagClaudeStale: String { "Claude backup is stale" }
    var bkTagClaudeMissing: String { "Claude log not found" }
    var bkTagClaudeUnreadable: String { "Claude log unreadable" }
    var bkCaptionAutoHourly: String { "automatic · every hour" }
    var bkCaptionAutoDaily: String { "automatic · every day" }
    var bkCaptionAutoWeekly: String { "automatic · every week" }
    func bkCaptionAutoEveryHours(_ n: Int) -> String { "automatic · every \(n) h" }
    var bkCaptionManual: String { "manual" }
    var bkCaptionDiskNotConnected: String { "disk not connected" }
    var bkCaptionBacking: String { "backup in progress" }
    var bkNoteNotSet: String { "Time Machine is not set up — there are no backups of this Mac." }
    func bkNoteOverdueDisconnected(_ days: Int, _ disk: String) -> String { "The last backup was \(days) \(days == 1 ? "day" : "days") ago. Connect \(disk) to continue." }
    func bkNoteOverdueDisconnectedHot(_ days: Int, _ disk: String) -> String { "The last backup was \(days) days ago, more than a month. Connect \(disk) and back up now." }
    func bkNoteOverdueConnected(_ days: Int) -> String { "The last backup was \(days) \(days == 1 ? "day" : "days") ago. Back up now to catch up." }
    func bkNoteOverdueConnectedHot(_ days: Int) -> String { "The last backup was \(days) days ago, more than a month. Back up now." }
    var bkTheBackupDisk: String { "the backup disk" }
    func bkDaysAgo(_ n: Int) -> String { "\(n) \(n == 1 ? "day" : "days") ago" }
    func bkToday(_ t: String) -> String { "today, \(t)" }
    func bkYesterday(_ t: String) -> String { "yesterday, \(t)" }
    var bkLastBackup: String { "Last backup" }
    var bkNextBackup: String { "Next backup" }
    func bkNextIn(_ d: String) -> String { "in \(d)" }
    var bkNextSoon: String { "soon" }
    var bkNextWhenConnected: String { "when connected" }
    var bkNextAfterThis: String { "after this one" }
    var bkNextAutoOff: String { "automatic backups are off" }
    func bkFree(_ s: String) -> String { "\(s) free" }
    var bkNotConnected: String { "not connected" }
    var bkPurgeable: String { "Purgeable" }
    var bkPurgeableNote: String { "snapshots and caches" }
    func bkLatestSnapshotToday(_ t: String) -> String { "latest today at \(t)" }
    func bkLatestSnapshot(_ d: String) -> String { "latest \(d)" }
    var bkBackUpNow: String { "Back up now" }
    var bkBackUpNowA11y: String { "Start a Time Machine backup now" }
    func bkConnectFirst(_ disk: String) -> String { "Connect \(disk) first" }
    var bkStop: String { "Stop" }
    var bkStopA11y: String { "Stop the running Time Machine backup" }
    var bkSetUpA11y: String { "Open Time Machine settings" }
    func bkBackingTo(_ disk: String) -> String { "Backing up to \(disk)" }
    func bkProgressBytes(_ done: String, _ total: String) -> String { "\(done) of \(total)" }
    func bkTimeLeft(_ d: String) -> String { "about \(d) left" }
    var bkPreparing: String { "preparing…" }
    var bkFinishing: String { "finishing…" }
    func bkFindingChanges(_ count: String) -> String { "Looking for changes · found \(count)" }
    var bkFindingChangesNoCount: String { "Looking for changes…" }
    var bkStopping: String { "stopping…" }
    func bkStartFailed(_ why: String) -> String { "Couldn’t start the backup: \(why)" }
    var bkStartDidNotBegin: String { "The backup did not start. Check Time Machine in System Settings." }
    func bkStopFailed(_ why: String) -> String { "Couldn’t stop the backup: \(why)" }
    var bkFailedNoReason: String { "tmutil gave no reason" }
    func bkClaudeCaption(_ path: String) -> String { "from \(path)" }
    var bkAgeOK: String { "OK" }
    var bkOverLimit: String { "over the limit" }
    var bkChangeInSettings: String { "change in Settings" }
    func bkNoteClaudeStale(_ limit: String) -> String { "The last Claude backup is older than \(limit). Check that the backup job still runs." }
    var bkNoteClaudeNone: String { "No successful Claude backup in the log. Check that the backup job still runs." }
    func bkNoteClaudeMissing(_ path: String) -> String { "Log not found: \(path)" }
    var bkOpenSettingsBackups: String { "Settings › Backup location" }
    var bkOpenSettingsBackupsA11y: String { "Open MacDashboard Settings on the Backup section" }
    func bkNoteClaudeUnreadable(_ path: String) -> String { "Can’t read \(path). Full Disk Access may be needed." }
    var bkOpenPrivacy: String { "Open Privacy settings…" }
    var bkOpenPrivacyA11y: String { "Open System Settings › Privacy & Security › Full Disk Access" }
    // BACKUP-CARD-FAILURE
    var bkClaudeAttemptLabel: String { "Last attempt" }
    var bkClaudeNextLabel: String { "Next run" }
    var bkClaudeSizeLabel: String { "Size" }
    var bkClaudeSizeNone: String { "appears after the next backup" }
    func bkClaudeSizeNote(added: String, total: String) -> String { "\(added) new · all snapshots \(total)" }
    var bkClaudeAttemptOK: String { "succeeded" }
    func bkClaudeAttemptFailed(_ exit: Int) -> String { "failed, code \(exit)" }
    func bkClaudeAttemptRunning(_ d: String) -> String { "running for \(d)" }
    var bkClaudeAttemptInterrupted: String { "did not finish" }
    func bkTomorrow(_ t: String) -> String { "tomorrow, \(t)" }
    var bkClaudeNextIfDisk: String { "if the disk is connected" }
    var bkClaudeNextDiskOn: String { "disk connected" }
    var bkClaudeNextNoSchedule: String { "no schedule" }
    var bkClaudeNextNoJob: String { "no scheduled job found" }
    func bkNoteClaudeFailed(_ reason: String) -> String { "The last backup attempt failed: \(reason). Older snapshots were not touched." }
    var bkNoteClaudeInterrupted: String { "The last backup attempt did not finish: it stopped before reporting a result. Older snapshots were not touched." }
    var bkClaudeProgressText: String { "Creating a backup" }
    var bkClaudeProgressFinishing: String { "finishing" }
    func bkNoteClaudeStaleNoRun(_ limit: String) -> String { "The last Claude backup is older than \(limit), and no run has started since. Check that the backup disk is connected." }
    var bkClaudeReasonDiskGone: String { "the disk disconnected during the copy" }
    var bkClaudeReasonDiskError: String { "the disk reported a read or write error" }
    var bkClaudeReasonNoSpace: String { "the backup disk is full" }
    var bkClaudeReasonNoPermission: String { "macOS refused access to the disk or to files" }
    var bkClaudeReasonFilesChanged: String { "files changed while they were being copied" }
    func bkClaudeReasonOther(_ exit: Int) -> String { "the copy stopped with error code \(exit)" }
    var bkTagClaudeFailed: String { "Claude backup failed" }
    var bkTagClaudeInterrupted: String { "Claude backup did not finish" }
    var bkTagClaudeRunning: String { "Claude backup running" }
    var bkClaudeClickNoDisk: String { "The backup disk is not connected, so no backup started. Connect it and try again." }
    var bkClaudeClickAlreadyRunning: String { "A backup is already running, so a second one did not start." }
    var bkClaudeClickNoResponse: String { "The backup did not start within 30 seconds. The disk may not be connected." }
    var bkClaudeClickLaunchFailed: String { "Couldn’t start the backup app. It may have been moved or removed." }
    var bkClaudeBackUpNowA11y: String { "Start a Claude backup now, without waiting for the 6-hour pause" }
}

extension StringsRU: BackupsStrings {
    // MARK: Time Machine card
    var timeMachineNotConfigured: String { "Time Machine не настроен" }
    var timeMachineDestination: String { "Назначение" }
    var timeMachineType: String { "Тип" }
    var timeMachineTypeLocal: String { "локальный диск" }
    var timeMachineQuota: String { "Квота" }
    var timeMachineLastBackup: String { "Последний бэкап" }
    var timeMachineConnection: String { "Подключение" }
    var timeMachineConnectionNone: String { "сейчас нет подключения" }
    var timeMachineSnapshots: String { "Локальные снапшоты" }
    var timeMachineSnapshotsNone: String { "нет" }
    func timeMachineSnapshotsCount(_ n: Int) -> String { "\(n) шт." }
    func timeMachineSnapshotsLast(_ date: String) -> String { ", последний \(date)" }
    var timeMachinePurgeable: String { "Очищаемое место" }
    var timeMachinePurgeableTip: String { "Место, которое macOS освободит сама, когда оно понадобится: локальные снапшоты Time Machine и кэши. Размер отдельного снапшота посчитать нельзя — снапшоты делят общие блоки диска." }

    // MARK: Claude backup card (BACKUP-AGE)
    var claudeBackupCardTitle: String { "Бэкап Claude" }
    var claudeBackupAgeLabel: String { "Возраст" }
    var claudeBackupLastLabel: String { "Последний снимок" }
    var claudeBackupLimitLabel: String { "Предупреждать после" }
    func claudeBackupAgo(_ age: String) -> String { "\(age) назад" }
    var claudeBackupJustNow: String { "только что" }
    var claudeBackupNoneFound: String { "успешных снимков в журнале нет" }
    var claudeBackupUnreadable: String { "журнал не удалось прочитать" }

    // MARK: Backups page (REDESIGN-BACKUPS)
    var bkSub: String { "Time Machine и бэкап Claude" }
    var bkTagTMNotSet: String { "Time Machine не настроена" }
    var bkTagOverdue: String { "Копия просрочена" }
    var bkTagBacking: String { "Идёт копирование…" }
    var bkTagClaudeStale: String { "Бэкап Claude устарел" }
    var bkTagClaudeMissing: String { "Лог Claude не найден" }
    var bkTagClaudeUnreadable: String { "Лог Claude не читается" }
    var bkCaptionAutoHourly: String { "автоматически · каждый час" }
    var bkCaptionAutoDaily: String { "автоматически · каждый день" }
    var bkCaptionAutoWeekly: String { "автоматически · каждую неделю" }
    func bkCaptionAutoEveryHours(_ n: Int) -> String { "автоматически · каждые \(n) ч" }
    var bkCaptionManual: String { "вручную" }
    var bkCaptionDiskNotConnected: String { "диск не подключён" }
    var bkCaptionBacking: String { "идёт резервное копирование" }
    var bkNoteNotSet: String { "Time Machine не настроена — копий этого Mac нет." }
    func bkNoteOverdueDisconnected(_ days: Int, _ disk: String) -> String { "Последняя копия была \(days) \(ruDays(days)) назад. Подключите \(disk), чтобы продолжить." }
    func bkNoteOverdueDisconnectedHot(_ days: Int, _ disk: String) -> String { "Последняя копия была \(days) \(ruDays(days)) назад — больше месяца. Подключите \(disk) и создайте копию." }
    func bkNoteOverdueConnected(_ days: Int) -> String { "Последняя копия была \(days) \(ruDays(days)) назад. Создайте копию сейчас." }
    func bkNoteOverdueConnectedHot(_ days: Int) -> String { "Последняя копия была \(days) \(ruDays(days)) назад — больше месяца. Создайте копию сейчас." }
    var bkTheBackupDisk: String { "диск для копий" }
    func bkDaysAgo(_ n: Int) -> String { "\(n) \(ruDays(n)) назад" }
    func bkToday(_ t: String) -> String { "сегодня, \(t)" }
    func bkYesterday(_ t: String) -> String { "вчера, \(t)" }
    var bkLastBackup: String { "Последняя копия" }
    var bkNextBackup: String { "Следующая копия" }
    func bkNextIn(_ d: String) -> String { "через \(d)" }
    var bkNextSoon: String { "скоро" }
    var bkNextWhenConnected: String { "при подключении" }
    var bkNextAfterThis: String { "после текущей" }
    var bkNextAutoOff: String { "автоматические копии выключены" }
    func bkFree(_ s: String) -> String { "свободно \(s)" }
    var bkNotConnected: String { "не подключён" }
    var bkPurgeable: String { "Очищаемое место" }
    var bkPurgeableNote: String { "снимки и кэши" }
    func bkLatestSnapshotToday(_ t: String) -> String { "последний сегодня в \(t)" }
    func bkLatestSnapshot(_ d: String) -> String { "последний \(d)" }
    var bkBackUpNow: String { "Создать копию" }
    var bkBackUpNowA11y: String { "Начать резервное копирование Time Machine сейчас" }
    func bkConnectFirst(_ disk: String) -> String { "Сначала подключите \(disk)" }
    var bkStop: String { "Остановить" }
    var bkStopA11y: String { "Остановить текущее копирование Time Machine" }
    var bkSetUpA11y: String { "Открыть настройки Time Machine" }
    func bkBackingTo(_ disk: String) -> String { "Копирование на \(disk)" }
    func bkProgressBytes(_ done: String, _ total: String) -> String { "\(done) из \(total)" }
    func bkTimeLeft(_ d: String) -> String { "осталось около \(d)" }
    var bkPreparing: String { "подготовка…" }
    var bkFinishing: String { "завершение…" }
    func bkFindingChanges(_ count: String) -> String { "Поиск изменений · найдено \(count)" }
    var bkFindingChangesNoCount: String { "Поиск изменений…" }
    var bkStopping: String { "остановка…" }
    func bkStartFailed(_ why: String) -> String { "Не удалось начать копирование: \(why)" }
    var bkStartDidNotBegin: String { "Копирование не началось. Проверьте Time Machine в Системных настройках." }
    func bkStopFailed(_ why: String) -> String { "Не удалось остановить копирование: \(why)" }
    var bkFailedNoReason: String { "tmutil не сообщил причину" }
    func bkClaudeCaption(_ path: String) -> String { "из \(path)" }
    var bkAgeOK: String { "в норме" }
    var bkOverLimit: String { "старше порога" }
    var bkChangeInSettings: String { "меняется в Настройках" }
    func bkNoteClaudeStale(_ limit: String) -> String { "Последний бэкап Claude старше \(limit). Проверьте, что задача резервного копирования запускается." }
    var bkNoteClaudeNone: String { "В журнале нет успешных бэкапов Claude. Проверьте, что задача резервного копирования запускается." }
    func bkNoteClaudeMissing(_ path: String) -> String { "Лог не найден: \(path)" }
    var bkOpenSettingsBackups: String { "Настройки › Расположение бэкапа" }
    var bkOpenSettingsBackupsA11y: String { "Открыть настройки MacDashboard, раздел «Бэкап»" }
    func bkNoteClaudeUnreadable(_ path: String) -> String { "Не удалось прочитать \(path). Возможно, нужен полный доступ к диску." }
    var bkOpenPrivacy: String { "Открыть «Конфиденциальность»…" }
    var bkOpenPrivacyA11y: String { "Открыть Системные настройки › Конфиденциальность › Полный доступ к диску" }
    private func ruDays(_ n: Int) -> String {
        let r = n % 100, d = n % 10
        if r >= 11 && r <= 14 { return "дней" }
        if d == 1 { return "день" }
        if (2...4).contains(d) { return "дня" }
        return "дней"
    }
    // BACKUP-CARD-FAILURE
    var bkClaudeAttemptLabel: String { "Последняя попытка" }
    var bkClaudeNextLabel: String { "Следующий запуск" }
    var bkClaudeSizeLabel: String { "Размер" }
    var bkClaudeSizeNone: String { "появится после следующей копии" }
    func bkClaudeSizeNote(added: String, total: String) -> String { "новых \(added) · все снимки \(total)" }
    var bkClaudeAttemptOK: String { "успешно" }
    func bkClaudeAttemptFailed(_ exit: Int) -> String { "ошибка, код \(exit)" }
    func bkClaudeAttemptRunning(_ d: String) -> String { "идёт \(d)" }
    var bkClaudeAttemptInterrupted: String { "не завершилась" }
    func bkTomorrow(_ t: String) -> String { "завтра, \(t)" }
    var bkClaudeNextIfDisk: String { "если диск подключён" }
    var bkClaudeNextDiskOn: String { "диск подключён" }
    var bkClaudeNextNoSchedule: String { "нет расписания" }
    var bkClaudeNextNoJob: String { "задача не найдена" }
    func bkNoteClaudeFailed(_ reason: String) -> String { "Последняя попытка бэкапа не удалась: \(reason). Старые снимки не затронуты." }
    var bkNoteClaudeInterrupted: String { "Последняя попытка бэкапа не завершилась: она остановилась, не сообщив результат. Старые снимки не затронуты." }
    var bkClaudeProgressText: String { "Создаётся копия" }
    var bkClaudeProgressFinishing: String { "завершение" }
    func bkNoteClaudeStaleNoRun(_ limit: String) -> String { "Последний бэкап Claude старше \(limit), и с тех пор запусков не было. Проверьте, подключён ли диск для копий." }
    var bkClaudeReasonDiskGone: String { "диск отключился во время копирования" }
    var bkClaudeReasonDiskError: String { "диск сообщил об ошибке чтения или записи" }
    var bkClaudeReasonNoSpace: String { "на диске для копий нет места" }
    var bkClaudeReasonNoPermission: String { "macOS не дала доступ к диску или файлам" }
    var bkClaudeReasonFilesChanged: String { "файлы менялись во время копирования" }
    func bkClaudeReasonOther(_ exit: Int) -> String { "копирование остановилось с кодом ошибки \(exit)" }
    var bkTagClaudeFailed: String { "Бэкап Claude не удался" }
    var bkTagClaudeInterrupted: String { "Бэкап Claude не завершился" }
    var bkTagClaudeRunning: String { "Идёт бэкап Claude" }
    var bkClaudeClickNoDisk: String { "Диск для копий не подключён, поэтому бэкап не начался. Подключите его и попробуйте снова." }
    var bkClaudeClickAlreadyRunning: String { "Бэкап уже идёт, поэтому второй не запущен." }
    var bkClaudeClickNoResponse: String { "Бэкап не начался за 30 секунд. Возможно, диск не подключён." }
    var bkClaudeClickLaunchFailed: String { "Не удалось запустить приложение бэкапа. Возможно, оно перемещено или удалено." }
    var bkClaudeBackUpNowA11y: String { "Начать бэкап Claude сейчас, не дожидаясь конца 6-часовой паузы" }
}
