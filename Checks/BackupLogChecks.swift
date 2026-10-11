// Checks/BackupLogChecks.swift
// BACKUP-AGE: the backup-log parser, tail reader, status mapping, staleness rule,
// duration text, setting resolution and the `Assess.assess` branch in both languages.
// Temp files only (temporaryDirectory/<UUID>); never touches ~/Library/Logs.
import Foundation

func runBackupLogChecks() {
    let utc = TimeZone(identifier: "UTC")!
    func utcDate(_ s: String, _ fmt: String = "yyyy-MM-dd HH:mm:ss") -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = utc; f.dateFormat = fmt
        return f.date(from: s)!
    }

    // 1. Sample from the real log shape: max of the OK time and the Snapshot stamp.
    let sample = """
    2026-10-09 18:43:40  START: /Volumes/Samsung SSD 9100 PRO 1TB Data
    2026-10-09 18:44:14  OK
        Snapshot done: /Volumes/Samsung SSD 9100 PRO 1TB Data/ClaudeProjectBackups/2026-10-09_184340
        Snapshots kept: 31
    2026-10-09 18:44:14  FREE: 248Gi
    2026-10-09 21:59:37  SKIP: newest snapshot is 3h old (cooldown 6h)
    """
    check(BackupLog.latestSuccess(in: sample, timeZone: utc) == utcDate("2026-10-09 18:44:14"),
          "BackupLog: sample -> 2026-10-09 18:44:14 (max of OK and Snapshot done)")

    // 2. Single markers and negatives.
    check(BackupLog.latestSuccess(in: "    Snapshot done: /x/ClaudeProjectBackups/2026-10-09_184340\n", timeZone: utc)
          == utcDate("2026-10-09 18:43:40"), "BackupLog: only Snapshot done -> its stamp")
    check(BackupLog.latestSuccess(in: "2026-10-09 18:44:14  OK\n", timeZone: utc) == utcDate("2026-10-09 18:44:14"),
          "BackupLog: only OK -> its time")
    let negatives = [
        "2026-10-09 18:44:14  FAILED (exit 1)", "2026-10-09 21:59:37  SKIP: newest snapshot is 3h old",
        "2026-10-09 18:43:40  START: /Volumes/X", "2026-10-09 18:44:14  OKAY",
        "2026-13-45 99:99:99  OK", "2026-10-0", "    Snapshot done: /x/notastamp", "",
    ]
    for n in negatives {
        check(BackupLog.latestSuccess(in: n, timeZone: utc) == nil, "BackupLog: negative line -> nil (\(n))")
    }

    // 2b. BACKUP-LOG-TIDY: the cached formatters follow the zone passed on each call,
    // sequentially and concurrently. Asia/Tokyo = UTC+9 with no DST.
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let okLine = "2026-10-09 18:44:14  OK\n"
    let stampLine = "    Snapshot done: /x/ClaudeProjectBackups/2026-10-09_184340\n"
    let okUTC = utcDate("2026-10-09 18:44:14"), okTokyo = utcDate("2026-10-09 09:44:14")
    check(BackupLog.latestSuccess(in: okLine, timeZone: utc) == okUTC
          && BackupLog.latestSuccess(in: okLine, timeZone: tokyo) == okTokyo
          && BackupLog.latestSuccess(in: okLine, timeZone: utc) == okUTC,
          "BackupLog: OK line UTC -> Tokyo -> UTC each parsed in its own zone")
    check(BackupLog.latestSuccess(in: stampLine, timeZone: tokyo) == utcDate("2026-10-09 09:43:40")
          && BackupLog.latestSuccess(in: stampLine, timeZone: utc) == utcDate("2026-10-09 18:43:40"),
          "BackupLog: Snapshot stamp Tokyo -> UTC each parsed in its own zone")
    let badLock = NSLock()
    var bad = 0
    DispatchQueue.concurrentPerform(iterations: 400) { i in
        let even = i.isMultiple(of: 2)
        if BackupLog.latestSuccess(in: okLine, timeZone: even ? utc : tokyo) != (even ? okUTC : okTokyo) {
            badLock.lock(); bad += 1; badLock.unlock()
        }
    }
    check(bad == 0, "BackupLog: 400 concurrent calls alternating UTC/Tokyo all correct (bad \(bad))")

    // 3-5. File-based checks in a temp dir.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let main = dir.appendingPathComponent("claude-backup.log")
    let rot = dir.appendingPathComponent("claude-backup.log.1")
    func write(_ s: String, to u: URL) { try? s.write(to: u, atomically: true, encoding: .utf8) }
    func rm(_ u: URL) { try? FileManager.default.removeItem(at: u) }
    // Local-time wall clock: status() parses with .current.
    func localDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)!
    }
    let okA = "2026-10-01 10:00:00  OK\n"
    let okB = "2026-10-05 12:30:00  OK\n"
    let filler = "2026-10-06 03:00:00  SKIP: newest snapshot is 3h old (cooldown 6h)\n"

    check(BackupLog.status(logURL: main, rotatedURL: rot) == nil, "BackupLog: neither file -> nil")
    write(okA, to: main)
    check(BackupLog.status(logURL: main, rotatedURL: rot) == .lastSuccess(localDate("2026-10-01 10:00:00")),
          "BackupLog: main with success -> lastSuccess")
    rm(main); write(okB, to: rot)
    check(BackupLog.status(logURL: main, rotatedURL: rot) == .lastSuccess(localDate("2026-10-05 12:30:00")),
          "BackupLog: only .1 with success -> lastSuccess")
    // Success within the first 10 KiB of a > 64 KiB file -> found at the 2 MiB step.
    rm(rot)
    write(okA + String(repeating: filler, count: 1300), to: main)   // ~ 85 KiB
    let mainSize = (try? FileManager.default.attributesOfItem(atPath: main.path)[.size] as? Int) ?? 0
    check(mainSize > 64 * 1024, "BackupLog: big file fixture > 64 KiB (got \(mainSize))")
    check(BackupLog.status(logURL: main, rotatedURL: rot) == .lastSuccess(localDate("2026-10-01 10:00:00")),
          "BackupLog: success only in first 10 KiB of a >64 KiB file -> found by the 2 MiB step")
    // Main without success, .1 with one -> the .1 date.
    write(filler, to: main); write(okB, to: rot)
    check(BackupLog.status(logURL: main, rotatedURL: rot) == .lastSuccess(localDate("2026-10-05 12:30:00")),
          "BackupLog: main without success + .1 with success -> .1 date")
    write(filler, to: rot)
    check(BackupLog.status(logURL: main, rotatedURL: rot) == .noSuccessFound, "BackupLog: both without success -> noSuccessFound")
    rm(rot)
    if getuid() == 0 {
        print("NOTE BackupLog: running as root, skipping mode-000 unreadable sub-check")
    } else {
        write(okA, to: main)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: main.path)
        check(BackupLog.status(logURL: main, rotatedURL: rot) == .unreadable, "BackupLog: mode 000 sole file -> unreadable")
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: main.path)
    }

    // 4. Window cut mid-line: never starts with a partial line, success still found.
    let fillerLine = "2026-10-06 03:00:00  SKIP: newest snapshot is 3h old (cooldown 6h)"
    var big = String(repeating: fillerLine + "\n", count: 1100)   // ~ 74 KiB
    big += okB
    write(big, to: main)
    if let tail = try? BackupLog.tailText(of: main, maxBytes: 64 * 1024) {
        check(tail.text.components(separatedBy: "\n").first == fillerLine, "BackupLog: cut window starts at a full line")
        check(!tail.coversWholeFile, "BackupLog: cut window does not cover whole file")
        check(BackupLog.latestSuccess(in: tail.text, timeZone: .current) == localDate("2026-10-05 12:30:00"),
              "BackupLog: success found in cut window")
    } else { check(false, "BackupLog: tailText on temp file did not throw") }

    // 5. Invalid UTF-8 in the filler neither throws nor hides a later success.
    var bytes = Data(String(repeating: fillerLine + "\n", count: 10).utf8)
    bytes.append(contentsOf: [0xFF, 0xFE, 0xC0, 0x0A])
    bytes.append(Data(okB.utf8))
    try? bytes.write(to: main)
    check(BackupLog.status(logURL: main, rotatedURL: rot) == .lastSuccess(localDate("2026-10-05 12:30:00")),
          "BackupLog: invalid UTF-8 does not hide a later success")

    // 6. isStale.
    let now = Date()
    func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }
    check(!BackupLog.isStale(.lastSuccess(ago(47)), thresholdHours: 48, now: now), "BackupLog: 47 h / 48 -> not stale")
    check(BackupLog.isStale(.lastSuccess(ago(48)), thresholdHours: 48, now: now), "BackupLog: 48 h / 48 -> stale")
    check(!BackupLog.isStale(.lastSuccess(now.addingTimeInterval(3600)), thresholdHours: 48, now: now), "BackupLog: future date -> not stale")
    check(BackupLog.isStale(.noSuccessFound, thresholdHours: 48, now: now), "BackupLog: noSuccessFound -> stale")
    check(!BackupLog.isStale(.unreadable, thresholdHours: 48, now: now), "BackupLog: unreadable -> not stale")

    // 7-9 touch the language; restore afterwards.
    let originalLang = L10nStore.shared.language
    defer { L10nStore.shared.language = originalLang }

    let durations: [(Int, String, String)] = [
        (0, "0 мин", "0 min"), (59 * 60, "59 мин", "59 min"), (5 * 3600, "5 ч", "5 h"),
        (24 * 3600, "1 дн", "1 d"), (27 * 3600, "1 дн 3 ч", "1 d 3 h"),
    ]
    for (secs, ru, en) in durations {
        L10nStore.shared.language = .ru
        check(BackupLog.durationText(seconds: secs) == ru, "BackupLog: durationText(\(secs)) RU == \(ru) (got \(BackupLog.durationText(seconds: secs)))")
        L10nStore.shared.language = .en
        check(BackupLog.durationText(seconds: secs) == en, "BackupLog: durationText(\(secs)) EN == \(en) (got \(BackupLog.durationText(seconds: secs)))")
    }

    // 8. Setting resolution.
    check(AppSettings.resolveBackupStaleHours(raw: 0) == 48, "backupStaleHours: 0 -> 48")
    check(AppSettings.resolveBackupStaleHours(raw: 24) == 24, "backupStaleHours: 24 -> 24")
    check(AppSettings.resolveBackupStaleHours(raw: 168) == 168, "backupStaleHours: 168 -> 168")
    check(AppSettings.resolveBackupStaleHours(raw: 50) == 48, "backupStaleHours: 50 -> 48")

    // 9. Assess branch.
    for lang in AppLanguage.allCases {
        L10nStore.shared.language = lang
        func items(_ s: ClaudeBackupStatus?) -> [AttentionItem] {
            Assess.assess(report: FullReport(), live: LiveSnapshot(), claudeBackup: s, backupStaleHours: 48, now: now)
                .items.filter { $0.kind == .claudeBackup }
        }
        let stale = items(.lastSuccess(ago(60)))
        check(stale.count == 1, "Assess backup (\(lang)): stale lastSuccess -> one item (got \(stale.count))")
        if let it = stale.first {
            check(it.sev == .warn, "Assess backup (\(lang)): severity warn")
            check(it.action == .revealPath(BackupLog.logURL.path), "Assess backup (\(lang)): action reveals the log")
            check(!it.label.isEmpty && !it.detail.isEmpty && !it.fullText.isEmpty, "Assess backup (\(lang)): label/detail/fullText non-empty")
        }
        check(items(.lastSuccess(ago(1))).isEmpty, "Assess backup (\(lang)): fresh -> none")
        check(items(.unreadable).isEmpty, "Assess backup (\(lang)): unreadable -> none")
        check(items(nil).isEmpty, "Assess backup (\(lang)): nil -> none")
        let none = items(.noSuccessFound)
        check(none.count == 1 && none[0].detail == L.attnDetailClaudeBackupNone, "Assess backup (\(lang)): noSuccessFound -> one item with the none detail")
    }
}
