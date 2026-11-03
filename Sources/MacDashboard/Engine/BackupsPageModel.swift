// Engine/BackupsPageModel.swift
// REDESIGN-BACKUPS: pure state, texts, tones and tiles of the Backups page (handoff 08-backups).
// The shape of SecurityPageModel: `make(Input)` computes everything, BackupsPage.swift only draws it.
import Foundation

enum BackupsTone: Equatable { case green, amber, hot, neutral, accent }
enum TMCardState: Equatable { case wait, notSet, ok, overdue7, overdue30, backing }
enum ClaudeCardState: Equatable { case ok, stale, noneFound, missing, unreadable }
/// The one in-flight / last-failed Back up now or Stop; `.failed` carries an already localized reason.
enum TMActionState: Equatable, Sendable { case idle, starting, stopping, failed(String) }

struct BackupsTile: Equatable {
    var id: String            // "last", "next", "dest", "snaps", "purgeable", "age", "lastSnap", "warn"
    var label: String
    var value: String
    var valueTone: BackupsTone? = nil   // nil → DS3.ink; .neutral → DS3.muted; others → their -ink
    var dot: BackupsTone? = nil
    var note: String? = nil
    var noteTone: BackupsTone? = nil    // nil → DS3.muted
}

/// The Claude card's Back up now button; nil = not shown.
struct BackupsClaudeButton: Equatable { var busy: Bool; var primary: Bool }

/// The Time Machine card's Back up now button; nil = not shown (no destination, or not read yet). `help` = why it is disabled.
struct BackupsTMButton: Equatable { var enabled: Bool; var busy: Bool; var primary: Bool; var help: String? }

struct BackupsNote: Equatable {
    enum Button: Equatable { case setUp, openSettingsBackups, openFullDiskAccess }
    var tone: BackupsTone; var text: String; var button: Button?
}

struct BackupsProgress: Equatable { var text: String; var caption: String; var fraction: Double?; var stopping: Bool }

struct BackupsPageModel: Equatable {
    struct Input {
        var tmDest: TMDestination??          // nil = not checked yet; .some(nil) = not configured
        var snapshots: [String]?             // nil = not collected / failed
        var backup: TMBackupProgress?        // last poll; nil = never probed on this visit
        var action: TMActionState
        var updatedAt: Date?                 // model.timeMachine.updatedAt → «updated HH:MM»
        var claudeBackup: ClaudeBackupStatus? // nil = log file absent
        var claudeLogPath: String            // BackupLog.logURL.path
        var warnAfterHours: Int
        var now: Date
        var claudeAttempt: ClaudeBackupAttempt? = nil
        var claudeSize: ClaudeBackupSize? = nil
        var claudeProgress: Double? = nil
        var claudeJob: ClaudeBackupJob? = nil
        var claudeDiskConnected: Bool? = nil
        var claudeAction: ClaudeBackupAction = .idle
        var claudeUsesDefaultLog = true
    }

    var tag: BackupsTone = .neutral; var tagText = ""; var sub = ""
    var tmState: TMCardState = .wait; var tmCaption: String? = nil
    var tmNote: BackupsNote? = nil; var tmProgress: BackupsProgress? = nil
    var tmTiles: [BackupsTile] = []           // notset: 3 tiles (snaps, purgeable, dest); else 4 (last, next, dest, snaps)
    var tmFailure: String? = nil              // hot note from TMActionState.failed
    var tmButton: BackupsTMButton? = nil      // nil in .wait and .notSet
    var claudeState: ClaudeCardState = .missing; var claudeCaption = ""
    var claudeRunProgress: BackupsProgress? = nil
    var claudeNote: BackupsNote? = nil; var claudeTiles: [BackupsTile] = []
    var claudeRunTiles: [BackupsTile] = []     // BACKUP-CARD-FAILURE: last attempt + next run; empty on a Mac without the job
    var claudeActionNote: BackupsNote? = nil   // the outcome of the last Back up now click
    var claudeButton: BackupsClaudeButton? = nil

    static let dash = "—"
    static let overdueAmberDays = 7, overdueHotDays = 30
    static let hour = 3600, day = 86_400, week = 604_800

    // MARK: make

    static func make(_ i: Input) -> BackupsPageModel {
        var m = BackupsPageModel()
        m.sub = L.bkSub

        // Time Machine card
        switch i.tmDest {
        case .none:
            m.tmState = .wait
            m.tmCaption = updatedCaption(i.updatedAt)
        case .some(.none):
            m.tmState = .notSet
            m.tmCaption = updatedCaption(i.updatedAt)
            m.tmNote = BackupsNote(tone: .amber, text: L.bkNoteNotSet, button: .setUp)
            m.tmTiles = [
                snapshotsTile(names: i.snapshots, now: i.now),
                BackupsTile(id: "purgeable", label: L.bkPurgeable, value: dash, valueTone: .neutral,
                            note: L.bkPurgeableNote),
                BackupsTile(id: "dest", label: L.timeMachineDestination, value: dash, valueTone: .neutral),
            ]
        case .some(.some(let stored)):
            let dest = effectiveDestination(stored, backup: i.backup)
            let state = tmState(dest: dest, backup: i.backup, action: i.action, now: i.now)
            m.tmState = state
            m.tmCaption = caption(dest: dest, state: state, updatedAt: i.updatedAt)
            m.tmButton = tmButton(dest: dest, state: state, action: i.action)
            switch state {
            case .overdue7, .overdue30:
                let days = dest.lastBackupDate.map { daysSince($0, now: i.now) } ?? 0
                m.tmNote = overdueNote(dest: dest, days: days, hot: state == .overdue30)
            case .backing:
                m.tmProgress = progress(dest: dest, backup: i.backup ?? .idle, action: i.action)
            default: break
            }
            m.tmTiles = [
                lastBackupTile(dest: dest, state: state, now: i.now),
                nextBackupTile(dest: dest, state: state, now: i.now),
                destinationTile(dest: dest, state: state),
                snapshotsTile(names: i.snapshots, now: i.now),
            ]
        }
        if case .failed(let msg) = i.action { m.tmFailure = msg }

        // Claude card
        m.claudeState = claudeState(i.claudeBackup, warnAfterHours: i.warnAfterHours, now: i.now)
        m.claudeCaption = L.bkClaudeCaption(abbreviateHome(i.claudeLogPath))
        m.claudeNote = claudeNote(state: m.claudeState, path: i.claudeLogPath, warnAfterHours: i.warnAfterHours,
                                  attempt: i.claudeAttempt, hasJob: i.claudeJob != nil)
        m.claudeTiles = claudeTiles(status: i.claudeBackup, state: m.claudeState, warnAfterHours: i.warnAfterHours, now: i.now)
        m.claudeRunTiles = (i.claudeJob == nil && i.claudeAttempt == nil) ? [] : [
            claudeAttemptTile(i.claudeAttempt, now: i.now),
            claudeNextTile(job: i.claudeJob, attempt: i.claudeAttempt, status: i.claudeBackup, diskConnected: i.claudeDiskConnected, now: i.now),
            claudeSizeTile(i.claudeSize),
        ]
        if i.claudeAttempt?.result == .running {
            let caption: String
            if let f = i.claudeProgress { caption = f >= 0.99 ? L.bkClaudeProgressFinishing : "\(Int(f * 100)) %" } else { caption = "" }
            m.claudeRunProgress = BackupsProgress(text: L.bkClaudeProgressText, caption: caption, fraction: i.claudeProgress, stopping: false)
        }
        m.claudeActionNote = claudeActionNote(i.claudeAction)
        m.claudeButton = claudeButton(job: i.claudeJob, usesDefaultLog: i.claudeUsesDefaultLog, state: m.claudeState,
                                      attempt: i.claudeAttempt, action: i.claudeAction)

        (m.tag, m.tagText) = tag(tm: m.tmState, claude: m.claudeState, attempt: i.claudeAttempt?.result)
        return m
    }

    // MARK: Time Machine helpers

    /// A running backup's own mount point beats the stored read, which can lag the mount (DISK-MOUNT-LIVE).
    static func effectiveDestination(_ stored: TMDestination, backup: TMBackupProgress?) -> TMDestination {
        guard backup?.running == true, let live = backup?.destinationMountPoint else { return stored }
        var dest = stored
        dest.mountPoint = live
        return dest
    }

    /// floor(seconds / 86400), never negative.
    static func daysSince(_ d: Date, now: Date) -> Int {
        Int(max(0, now.timeIntervalSince(d)) / Double(day))
    }

    /// `.wait` / `.notSet` are decided by `make` (no destination to look at).
    static func tmState(dest: TMDestination, backup: TMBackupProgress?, action: TMActionState, now: Date) -> TMCardState {
        if backup?.running == true || action == .starting || action == .stopping { return .backing }
        guard let last = dest.lastBackupDate else { return .ok }   // unknown age is not overdue
        // Strictly more than 7 / 30 days of elapsed time (exactly 7 d is not overdue); `daysSince` is for display.
        let elapsed = now.timeIntervalSince(last)
        if elapsed > Double(overdueHotDays * day) { return .overdue30 }
        if elapsed > Double(overdueAmberDays * day) { return .overdue7 }
        return .ok
    }

    /// today, HH:mm / yesterday, HH:mm / short date and time. «Today» is relative to `now` (the fixture clock in snapshots).
    static func lastBackupText(_ d: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return L.bkToday(hhmm(d)) }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) {
            return L.bkYesterday(hhmm(d))
        }
        return L.shortDateTime(d)
    }

    static func lastBackupTile(dest: TMDestination, state: TMCardState, now: Date) -> BackupsTile {
        var t = BackupsTile(id: "last", label: L.bkLastBackup, value: dash)
        let reason = dest.lastBackupUnavailableReason
        guard let d = dest.lastBackupDate else {
            t.value = reason?.localizedText ?? dash
            t.valueTone = .neutral
            if state != .backing, reason == .dateUnavailableNoFDA {
                t.valueTone = .amber
                t.note = L.commonFullDiskAccessNeeded
                t.noteTone = .amber
            }
            return t
        }
        t.value = lastBackupText(d, now: now)
        switch state {
        case .overdue7, .overdue30:
            let tone: BackupsTone = state == .overdue30 ? .hot : .amber
            t.value = L.bkDaysAgo(daysSince(d, now: now))
            t.valueTone = tone; t.dot = tone
            t.note = L.shortDateTime(d); t.noteTone = tone
        case .backing:
            break
        default:
            let age = Int(max(0, now.timeIntervalSince(d)))
            t.dot = .green
            t.note = age < 60 ? L.claudeBackupJustNow : L.claudeBackupAgo(BackupLog.durationText(seconds: age))
            t.noteTone = .green
        }
        return t
    }

    static func nextBackupTile(dest: TMDestination, state: TMCardState, now: Date) -> BackupsTile {
        var t = BackupsTile(id: "next", label: L.bkNextBackup, value: dash)
        if state == .backing { t.value = L.bkNextAfterThis; return t }
        if dest.mountPoint == nil { t.value = L.bkNextWhenConnected; return t }
        switch dest.schedule {
        case .none:
            t.valueTone = .neutral
            t.note = L.commonFullDiskAccessNeeded
        case .manual?:
            t.valueTone = .neutral
            t.note = L.bkNextAutoOff
        case .automatic(let seconds)?:
            if let last = dest.lastBackupDate {
                let next = last.addingTimeInterval(TimeInterval(seconds))
                t.value = next > now
                    ? L.bkNextIn(BackupLog.durationText(seconds: Int(next.timeIntervalSince(now))))
                    : L.bkNextSoon
            } else {
                t.value = L.bkNextSoon
            }
        }
        return t
    }

    /// `state` colours the «not connected» note (amber when overdue, red when long overdue) and removes it during a backup.
    static func destinationTile(dest: TMDestination, state: TMCardState = .ok) -> BackupsTile {
        var t = BackupsTile(id: "dest", label: L.timeMachineDestination, value: dest.name ?? dash)
        if dest.name == nil { t.valueTone = .neutral }
        if dest.mountPoint != nil {
            if let free = dest.freeBytes { t.note = L.bkFree(fmtCapacity(free)) }
        } else if state != .backing {   // a backup in progress proves the destination is there
            t.note = L.bkNotConnected
            t.noteTone = state == .overdue30 ? .hot : (state == .overdue7 ? .amber : nil)
        }
        return t
    }

    static func snapshotsTile(names: [String]?, now: Date, calendar: Calendar = .current) -> BackupsTile {
        var t = BackupsTile(id: "snaps", label: L.commonLocalSnapshots, value: dash, valueTone: .neutral)
        guard let names else { return t }
        t.value = "\(names.count)"
        t.valueTone = nil
        if let newest = names.max(), let d = Parsers.tmLatestBackupDate(fromPath: newest) {
            t.note = calendar.isDate(d, inSameDayAs: now) ? L.bkLatestSnapshotToday(hhmm(d)) : L.bkLatestSnapshot(L.shortDateTime(d))
        }
        return t
    }

    static func updatedCaption(_ updatedAt: Date?) -> String? {
        updatedAt.map { L.storageSmartUpdatedCaption(hhmm($0)) }
    }

    /// Schedule word · connection word, else «updated HH:MM» (D15).
    static func caption(dest: TMDestination, state: TMCardState, updatedAt: Date?) -> String? {
        switch state {
        case .wait, .notSet: return updatedCaption(updatedAt)
        case .backing: return L.bkCaptionBacking
        default: break
        }
        var parts: [String] = []
        switch dest.schedule {
        case .automatic(let s)?:
            switch s {
            case hour: parts.append(L.bkCaptionAutoHourly)
            case day: parts.append(L.bkCaptionAutoDaily)
            case week: parts.append(L.bkCaptionAutoWeekly)
            default: parts.append(L.bkCaptionAutoEveryHours(max(1, s / hour)))
            }
        case .manual?: parts.append(L.bkCaptionManual)
        case .none: break
        }
        if dest.mountPoint == nil { parts.append(L.bkCaptionDiskNotConnected) }
        return parts.isEmpty ? updatedCaption(updatedAt) : parts.joined(separator: " · ")
    }

    static func overdueNote(dest: TMDestination, days: Int, hot: Bool) -> BackupsNote {
        let name = dest.name ?? L.bkTheBackupDisk
        let text: String
        if dest.mountPoint == nil {
            text = hot ? L.bkNoteOverdueDisconnectedHot(days, name) : L.bkNoteOverdueDisconnected(days, name)
        } else {
            text = hot ? L.bkNoteOverdueConnectedHot(days) : L.bkNoteOverdueConnected(days)
        }
        return BackupsNote(tone: hot ? .hot : .amber, text: text, button: nil)
    }

    /// Mirrors TimeMachineController.startBackupNow: needs a mounted destination and no start or stop in flight. `.backing`
    /// also covers a running backup, which the controller does not check. A failed action counts as idle: it may be retried.
    /// `dest` is the effective destination: while no backup runs it equals the stored one the controller reads.
    static func tmButton(dest: TMDestination, state: TMCardState, action: TMActionState) -> BackupsTMButton {
        let connected = dest.mountPoint != nil
        let backing = state == .backing
        let enabled = connected && !backing
        let overdue = state == .overdue7 || state == .overdue30
        return BackupsTMButton(enabled: enabled, busy: action == .starting, primary: enabled && overdue,
                               help: connected || backing ? nil : L.bkConnectFirst(dest.name ?? L.bkTheBackupDisk))
    }

    static func progress(dest: TMDestination, backup: TMBackupProgress, action: TMActionState) -> BackupsProgress {
        let stopping = action == .stopping || backup.stopping
        let caption: String
        let finding = backup.phase == "FindingChanges"
        if stopping { caption = L.bkStopping }
        else if finding { caption = backup.changedItems.map { L.bkFindingChanges(fmtGrouped($0)) } ?? L.bkFindingChangesNoCount }
        else if backup.phase == "ThinningPostBackup" || backup.phase == "Finishing" { caption = L.bkFinishing }
        else if action == .starting && !backup.running { caption = L.bkPreparing }
        else { caption = bytesCaption(done: backup.bytesDone, total: backup.bytesTotal, secondsRemaining: backup.secondsRemaining) }
        return BackupsProgress(text: L.bkBackingTo(dest.name ?? L.bkTheBackupDisk), caption: caption,
                               fraction: finding && stopping ? nil : TimeMachineStatus.overallFraction(backup), stopping: stopping)
    }

    static func bytesCaption(done: Int64?, total: Int64?, secondsRemaining: Int?) -> String {
        guard let total, total > 0 else { return L.bkPreparing }
        let d = fmtBackupBytesParts(done ?? 0), t = fmtBackupBytesParts(total)
        var s = d.unit == t.unit
            ? L.bkProgressBytes(d.value, "\(t.value) \(t.unit)")
            : L.bkProgressBytes("\(d.value) \(d.unit)", "\(t.value) \(t.unit)")
        if let secs = secondsRemaining, secs > 0 {
            s += " · " + L.bkTimeLeft(BackupLog.durationText(seconds: secs))
        }
        return s
    }

    // MARK: Claude helpers

    static func claudeState(_ s: ClaudeBackupStatus?, warnAfterHours: Int, now: Date) -> ClaudeCardState {
        guard let s else { return .missing }
        switch s {
        case .unreadable: return .unreadable
        case .noSuccessFound: return .noneFound
        case .lastSuccess:
            return BackupLog.isStale(s, thresholdHours: warnAfterHours, now: now) ? .stale : .ok
        }
    }

    static func claudeNote(state: ClaudeCardState, path: String, warnAfterHours: Int,
                           attempt: ClaudeBackupAttempt? = nil, hasJob: Bool = false) -> BackupsNote? {
        switch state {
        case .missing:
            return BackupsNote(tone: .neutral, text: L.bkNoteClaudeMissing(abbreviateHome(path)), button: .openSettingsBackups)
        case .unreadable:
            return BackupsNote(tone: .amber, text: L.bkNoteClaudeUnreadable(abbreviateHome(path)), button: .openFullDiskAccess)
        case .ok, .stale, .noneFound:
            break
        }
        switch attempt?.result {
        case .failed(let exit, let reason)?:
            return BackupsNote(tone: .amber, text: L.bkNoteClaudeFailed(BackupLog.reasonText(reason, exit: exit)), button: nil)
        case .interrupted?:
            return BackupsNote(tone: .amber, text: L.bkNoteClaudeInterrupted, button: nil)
        case .ok?, .running?, nil:
            break
        }
        switch state {
        case .stale:
            let limit = L.settingsWarnAfterDays(warnAfterHours / 24)
            let text = (hasJob && attempt?.result == .ok) ? L.bkNoteClaudeStaleNoRun(limit) : L.bkNoteClaudeStale(limit)
            return BackupsNote(tone: .amber, text: text, button: nil)
        case .noneFound:
            return BackupsNote(tone: .amber, text: L.bkNoteClaudeNone, button: nil)
        default:
            return nil
        }
    }

    static func claudeSizeTile(_ s: ClaudeBackupSize?) -> BackupsTile {
        var t = BackupsTile(id: "size", label: L.bkClaudeSizeLabel, value: dash, valueTone: .neutral)
        guard let s else { t.note = L.bkClaudeSizeNone; return t }
        t.value = fmtBytes(s.snapshotBytes)
        t.valueTone = nil
        t.note = L.bkClaudeSizeNote(added: fmtBytes(s.addedBytes), total: fmtBytes(s.totalBytes))
        return t
    }

    static func claudeAttemptTile(_ a: ClaudeBackupAttempt?, now: Date) -> BackupsTile {
        var t = BackupsTile(id: "attempt", label: L.bkClaudeAttemptLabel, value: dash, valueTone: .neutral)
        guard let a else { return t }
        t.value = lastBackupText(a.at, now: now)
        t.valueTone = nil
        switch a.result {
        case .ok:
            t.dot = .green; t.note = L.bkClaudeAttemptOK; t.noteTone = .green
        case .running:
            let secs = max(60, Int(now.timeIntervalSince(a.at)))
            t.dot = .accent; t.note = L.bkClaudeAttemptRunning(BackupLog.durationText(seconds: secs)); t.noteTone = .accent
        case .interrupted:
            t.dot = .amber; t.note = L.bkClaudeAttemptInterrupted; t.noteTone = .amber
        case .failed(let exit, _):
            t.dot = .amber; t.note = L.bkClaudeAttemptFailed(exit); t.noteTone = .amber
        }
        return t
    }

    static func claudeNextTile(job: ClaudeBackupJob?, attempt: ClaudeBackupAttempt?, status: ClaudeBackupStatus?,
                               diskConnected: Bool?, now: Date) -> BackupsTile {
        var t = BackupsTile(id: "next", label: L.bkClaudeNextLabel, value: dash, valueTone: .neutral)
        guard let job else { t.note = L.bkClaudeNextNoJob; return t }
        if attempt?.result == .running { t.value = L.bkNextAfterThis; t.valueTone = nil; return t }
        var newest: Date? = nil
        if case .lastSuccess(let d)? = status { newest = d }
        let cooling = newest.map { $0.addingTimeInterval(TimeInterval(ClaudeBackupJob.cooldownHours * 3600)) > now } ?? false
        if diskConnected == false, job.startsOnMount, !cooling {
            t.value = L.bkNextWhenConnected; t.valueTone = nil
            t.note = L.bkCaptionDiskNotConnected; t.noteTone = .amber
            return t
        }
        guard let next = ClaudeBackupJob.nextCopyingRun(job.schedule, now: now, newestSuccess: newest) else {
            t.value = L.bkClaudeNextNoSchedule
            return t
        }
        t.value = nextRunText(next, now: now)
        t.valueTone = nil
        t.note = diskConnected == true ? L.bkClaudeNextDiskOn : L.bkClaudeNextIfDisk
        return t
    }

    /// today, HH:mm / tomorrow, HH:mm / short date and time.
    static func nextRunText(_ d: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return L.bkToday(hhmm(d)) }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(d, inSameDayAs: t) {
            return L.bkTomorrow(hhmm(d))
        }
        return L.shortDateTime(d)
    }

    static func claudeActionNote(_ a: ClaudeBackupAction) -> BackupsNote? {
        switch a {
        case .idle, .starting: return nil
        case .diskNotConnected: return BackupsNote(tone: .amber, text: L.bkClaudeClickNoDisk, button: nil)
        case .alreadyRunning: return BackupsNote(tone: .neutral, text: L.bkClaudeClickAlreadyRunning, button: nil)
        case .noResponse: return BackupsNote(tone: .amber, text: L.bkClaudeClickNoResponse, button: nil)
        case .launchFailed: return BackupsNote(tone: .hot, text: L.bkClaudeClickLaunchFailed, button: nil)
        }
    }

    /// nil = no button: no runnable job, another log in use, or a log the card cannot read (D16).
    static func claudeButton(job: ClaudeBackupJob?, usesDefaultLog: Bool, state: ClaudeCardState,
                             attempt: ClaudeBackupAttempt?, action: ClaudeBackupAction) -> BackupsClaudeButton? {
        guard job?.appPath != nil, usesDefaultLog, state != .unreadable else { return nil }
        let result = attempt?.result
        var problem = state == .stale || state == .noneFound || result == .interrupted
        if case .failed? = result { problem = true }
        return BackupsClaudeButton(busy: action == .starting || result == .running, primary: problem)
    }

    static func claudeTiles(status: ClaudeBackupStatus?, state: ClaudeCardState, warnAfterHours: Int, now: Date) -> [BackupsTile] {
        var age = BackupsTile(id: "age", label: L.claudeBackupAgeLabel, value: dash, valueTone: .neutral)
        var last = BackupsTile(id: "lastSnap", label: L.claudeBackupLastLabel, value: dash, valueTone: .neutral)
        let warn = BackupsTile(id: "warn", label: L.claudeBackupLimitLabel,
                               value: L.settingsWarnAfterDays(warnAfterHours / 24), note: L.bkChangeInSettings)
        switch state {
        case .ok, .stale:
            if case .lastSuccess(let d)? = status {
                let secs = Int(max(0, now.timeIntervalSince(d)))
                age.value = secs < 60 ? L.claudeBackupJustNow : L.claudeBackupAgo(BackupLog.durationText(seconds: secs))
                last.value = L.shortDateTime(d)
                last.valueTone = nil
            }
            if state == .ok {
                age.valueTone = nil; age.dot = .green
                age.note = L.bkAgeOK; age.noteTone = .green
            } else {
                age.valueTone = .amber; age.dot = .amber
                age.note = L.bkOverLimit; age.noteTone = .amber
            }
        case .noneFound:
            age.value = L.claudeBackupNoneFound
            age.valueTone = .amber; age.dot = .amber
        case .missing:
            break
        case .unreadable:
            age.value = L.claudeBackupUnreadable
        }
        return [age, last, warn]
    }

    // MARK: Tag

    private static func rank(_ t: BackupsTone) -> Int {
        switch t {
        case .hot: return 4
        case .amber: return 3
        case .accent: return 2
        case .neutral: return 1
        case .green: return 0
        }
    }

    /// The more severe card wins; on a tie the Time Machine card wins (both green → «All good»).
    static func tag(tm: TMCardState, claude: ClaudeCardState, attempt: ClaudeBackupAttempt.Result? = nil) -> (BackupsTone, String) {
        let t: (BackupsTone, String)
        switch tm {
        case .wait: t = (.neutral, L.commonCollectingData)
        case .notSet: t = (.amber, L.bkTagTMNotSet)
        case .ok: t = (.green, L.commonAllGood)
        case .overdue7: t = (.amber, L.bkTagOverdue)
        case .overdue30: t = (.hot, L.bkTagOverdue)
        case .backing: t = (.accent, L.bkTagBacking)
        }
        var c: (BackupsTone, String)
        switch claude {
        case .ok: c = (.green, "")
        case .stale, .noneFound: c = (.amber, L.bkTagClaudeStale)
        case .missing: c = (.neutral, L.bkTagClaudeMissing)
        case .unreadable: c = (.neutral, L.bkTagClaudeUnreadable)
        }
        switch attempt {
        case .failed?: c = (.amber, L.bkTagClaudeFailed)
        case .interrupted?: c = (.amber, L.bkTagClaudeInterrupted)
        case .running?: c = (.accent, L.bkTagClaudeRunning)
        case .ok?, nil: break
        }
        return rank(c.0) > rank(t.0) ? c : t
    }

    // MARK: Text helpers

    /// "/Users/x/Library/…" → "~/Library/…" (the real home directory).
    static func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// "HH:mm" in the current zone.
    static func hhmm(_ d: Date) -> String { SecurityPageModel.hhmm(d) }
}
