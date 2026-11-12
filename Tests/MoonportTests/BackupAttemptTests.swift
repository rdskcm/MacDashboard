// Tests/MoonportTests/BackupAttemptTests.swift
// BACKUP-CARD-FAILURE R1-R4: the last-attempt parser, the failure-reason classifier, the running/interrupted rule,
// the file readers (rotated log, split START/result, big blocks) and the click outcome. Temp files only.
import Foundation
import Testing
@testable import Moonport

extension SerialTests {
    struct BackupAttemptTests {
        private let utc = TimeZone(identifier: "UTC")!
        private let M = "/Volumes/Samsung SSD 9100 PRO 1TB Data"
        private func date(_ s: String) -> Date {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = utc; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.date(from: s)!
        }
        private func attempt(_ text: String) -> ClaudeBackupAttempt? { BackupLog.lastAttempt(in: text, timeZone: utc) }
        /// A failed block: START, FAILED(23), then `lines` as output.
        private func failed(_ lines: [String]) -> String {
            (["2026-10-31 14:51:08  START: \(M)", "2026-10-31 15:04:05  FAILED (exit 23)"] + lines).joined(separator: "\n") + "\n"
        }
        private func reason(_ line: String) -> ClaudeBackupAttempt.Reason? {
            guard case .failed(_, let r)? = attempt(failed([line]))?.result else { return nil }
            return r
        }
        private func tempDir() -> URL {
            let d = FileManager.default.temporaryDirectory.appendingPathComponent("BackupAttemptTests-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            return d
        }
        private func write(_ s: String, to url: URL) { try? s.write(to: url, atomically: true, encoding: .utf8) }

        @Test func okRun() {
            let t = """
            2026-11-03 16:15:20  START: \(M)
            2026-11-03 16:16:05  OK
                Snapshot done: \(M)/ClaudeProjectBackups/2026-11-03_161549
            2026-11-03 16:16:05  FREE: 468Gi
            """
            #expect(attempt(t) == ClaudeBackupAttempt(at: date("2026-11-03 16:16:05"), result: .ok, mount: M))
        }

        @Test func failedRunWithFilesChanged() {
            let t = failed(["    rsync(13284): error: /Users/x/p/.git/refs/heads/a: open (2) in /: No such file or directory"])
            #expect(attempt(t) == ClaudeBackupAttempt(at: date("2026-10-31 15:04:05"), result: .failed(exit: 23, reason: .filesChanged), mount: M))
        }

        @Test func reasonTable() {
            let table: [(String, ClaudeBackupAttempt.Reason?)] = [
                ("    Volume not mounted: \(M)", .diskDisconnected),
                ("    rsync(1848): error: .git/: mkpathat: Device not configured", .diskDisconnected),
                ("    rsync: .git/objects/pack/p.pack: copy file: Device not configured", .diskDisconnected),
                ("    rsync(50551): error: a: write: Input/output error", .diskError),
                ("    mkdir: \(M)/ClaudeProjectBackups/x: Operation not permitted", .noPermission),
                ("    mkdir: \(M)/ClaudeProjectBackups: Permission denied", .noPermission),
                ("    rsync: write failed: No space left on device", .noSpace),
                ("    rsync(23484): error: hard link '\(M)/l/a': No such file or directory", nil),
                ("    rsync(23484): error: .git/a: fstatat: Not a directory", nil),
            ]
            for (line, expected) in table {
                #expect(BackupLog.reason(forOutputLine: Substring(line)) == expected, "\(line)")
                #expect(reason(line) == (expected ?? .other), "through lastAttempt: \(line)")
            }
            #expect(reason("    rsync(64961): error: a: utimensat (2): Not a directory\n    rsync(64960): error: unexpected end of file") == .other)
        }

        @Test func reasonPriorityIgnoresOrder() {
            let nsf = "    rsync(1): error: a: open (2) in /: No such file or directory"
            let dnc = "    rsync(1): error: b: mkpathat: Device not configured"
            #expect(reason(nsf + "\n" + dnc) == .diskDisconnected)
            #expect(reason(dnc + "\n" + nsf) == .diskDisconnected)
        }

        @Test func skipLinesAreNotAttempts() {
            let ok = "2026-11-03 16:15:20  START: \(M)\n2026-11-03 16:16:05  OK\n"
            let t = ok + "2026-11-03 17:00:00  SKIP: newest snapshot is 0h old (cooldown 6h)\n2026-11-03 17:01:00  SKIP: another run is in progress (pid 12)\n"
            #expect(attempt(t)?.result == .ok)
            let only = """
            2026-11-03 17:00:00  SKIP: newest snapshot is 0h old (cooldown 6h)
            2026-11-03 17:00:01  PRUNED: x
            2026-11-03 17:00:02  FREE: 468Gi
            2026-11-03 17:00:03  NOTE: y
            """
            #expect(attempt(only) == nil)
        }

        @Test func laterBlockDoesNotChangeTheReason() {
            let t = failed(["    rsync(1): error: a: open (2) in /: No such file or directory",
                            "2026-10-31 15:05:00  LS-PRUNE (exit 0)", "    No space left on device"])
            guard case .failed(_, let r)? = attempt(t)?.result else { Issue.record("not failed"); return }
            #expect(r != .noSpace)
        }

        @Test func startWithNothingAfterIsRunning() {
            #expect(attempt("2026-11-03 16:15:20  START: \(M)\n") == ClaudeBackupAttempt(at: date("2026-11-03 16:15:20"), result: .running, mount: M))
            let two = "2026-11-03 10:00:00  START: /a\n2026-11-03 11:00:00  START: /b\n"
            #expect(attempt(two)?.at == date("2026-11-03 11:00:00") && attempt(two)?.mount == "/b")
            let afterFail = "2026-11-03 10:00:00  START: /a\n2026-11-03 10:05:00  FAILED (exit 1)\n2026-11-03 11:00:00  START: /a\n"
            #expect(attempt(afterFail)?.result == .running)
        }

        @Test func settledRule() {
            let start = date("2026-11-03 10:00:00")
            let run = ClaudeBackupAttempt(at: start, result: .running, mount: M)
            #expect(BackupLog.settled(run, lockPIDAlive: true, now: start.addingTimeInterval(600)).result == .running)
            #expect(BackupLog.settled(run, lockPIDAlive: false, now: start.addingTimeInterval(600)).result == .interrupted)
            #expect(BackupLog.settled(run, lockPIDAlive: true, now: start.addingTimeInterval(3 * 3600)).result == .interrupted)
            let ok = ClaudeBackupAttempt(at: start, result: .ok, mount: M)
            #expect(BackupLog.settled(ok, lockPIDAlive: false, now: start) == ok)
        }

        @Test func lockPIDAndLiveness() {
            let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
            let f = d.appendingPathComponent("pid")
            write("123\n", to: f); #expect(BackupLog.lockPID(at: f) == 123)
            write("abc", to: f); #expect(BackupLog.lockPID(at: f) == nil)
            #expect(BackupLog.lockPID(at: d.appendingPathComponent("missing")) == nil)
            #expect(BackupLog.isProcessAlive(getpid()))
            #expect(!BackupLog.isProcessAlive(0))
        }

        @Test func progressFractionParsing() {
            #expect(BackupLog.progressFraction(in: "50 100\n") == 0.5)
            #expect(BackupLog.progressFraction(in: "150 100") == 0.99)
            for bad in ["5 0", "", "abc", "1 2 3", "-1 100"] { #expect(BackupLog.progressFraction(in: bad) == nil) }
        }

        @Test func readProgressFromFile() async {
            let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
            let f = d.appendingPathComponent("progress")
            #expect(await BackupLog.readProgress(at: f) == nil)
            write("25 100\n", to: f)
            #expect(await BackupLog.readProgress(at: f) == 0.25)
        }

        @Test func filesAcrossTheRotatedLog() async {
            let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
            let log = d.appendingPathComponent("c.log"), rot = d.appendingPathComponent("c.log.1"), pid = d.appendingPathComponent("pid")
            #expect(BackupLog.attempt(logURL: log, rotatedURL: rot) == nil)
            write("2026-11-03 17:00:00  SKIP: newest snapshot is 0h old (cooldown 6h)\n", to: log)
            write(failed([]), to: rot)
            #expect(BackupLog.attempt(logURL: log, rotatedURL: rot)?.result == .failed(exit: 23, reason: .other))
            // result in the main log, START in the rotated one
            write("2026-11-03 16:16:05  OK\n", to: log)
            write("2026-11-03 16:15:20  START: \(M)\n", to: rot)
            let split = BackupLog.attempt(logURL: log, rotatedURL: rot)
            #expect(split?.result == .ok && split?.mount == nil)
            // unterminated START
            write("2026-11-03 17:00:00  SKIP: newest snapshot is 0h old (cooldown 6h)\n", to: log)
            let startedAt = Date().addingTimeInterval(-60)
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            write("\(f.string(from: startedAt))  START: \(M)\n", to: rot)
            let dead = await BackupLog.readAttempt(logURL: log, rotatedURL: rot, lockPIDURL: pid, now: Date())
            #expect(dead?.result == .interrupted)
            write("\(getpid())\n", to: pid)
            let alive = await BackupLog.readAttempt(logURL: log, rotatedURL: rot, lockPIDURL: pid, now: Date())
            #expect(alive?.result == .running)
        }

        @Test func bigBlocksAreFoundByLaterWindows() {
            let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
            let log = d.appendingPathComponent("c.log"), rot = d.appendingPathComponent("c.log.1")
            let noise = "    rsync(1): error: a: fstatat: Not a directory\n"
            for bytes in [100 * 1024, 3 * 1024 * 1024] {
                let body = String(repeating: noise, count: bytes / noise.utf8.count)
                let text = "2026-10-31 14:51:08  START: \(M)\n2026-10-31 15:04:05  FAILED (exit 20)\n    rsync: x: copy file: Device not configured\n"
                    + body + "2026-11-03 17:00:00  SKIP: newest snapshot is 0h old (cooldown 6h)\n"
                write(text, to: log)
                let a = BackupLog.attempt(logURL: log, rotatedURL: rot)
                #expect(a?.result == .failed(exit: 20, reason: .diskDisconnected), "block of \(bytes) bytes")
            }
        }

        @Test func invalidUTF8DoesNotHideTheAttempt() {
            let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
            let log = d.appendingPathComponent("c.log")
            var data = Data([0xFF, 0xFE, 0xC3, 0x0A])
            data.append(Data("2026-11-03 16:16:05  OK\n".utf8))
            try? data.write(to: log)
            #expect(BackupLog.attempt(logURL: log, rotatedURL: d.appendingPathComponent("none"))?.result == .ok)
        }

        @Test func clickOutcomeReadsOnlyForcedSkips() {
            let since = date("2026-11-03 17:00:00").addingTimeInterval(0.6)
            func out(_ t: String) -> ClaudeBackupClickOutcome? { BackupLog.clickOutcome(in: t, since: since, timeZone: utc) }
            #expect(out("2026-11-03 17:00:00  SKIP: disk not connected (forced run)\n") == .diskNotConnected)   // same second as a fractional `since`
            #expect(out("2026-11-03 16:59:59  SKIP: disk not connected (forced run)\n") == nil)
            #expect(out("2026-11-03 17:00:05  SKIP: another run is in progress (pid 9)\n") == .alreadyRunning)
            #expect(out("2026-11-03 17:00:05  SKIP: newest snapshot is 1h old (cooldown 6h)\n") == nil)
        }

        @Test func latestSizeReadsTheLastLine() {
            let one = "2026-11-03 16:16:09  SIZE: snapshot=100 added=10 total=1000\n"
            #expect(BackupLog.latestSize(in: one) == ClaudeBackupSize(snapshotBytes: 102_400, addedBytes: 10_240, totalBytes: 1_024_000))
            let two = one + "2026-11-03 22:16:09  SIZE: snapshot=200 added=20 total=2000\n"
            #expect(BackupLog.latestSize(in: two)?.snapshotBytes == 204_800)
            let bad = one + "2026-11-03 22:16:09  SIZE: snapshot=abc added=20 total=2000\n2026-11-03 22:17:09  SIZE: snapshot=1 added=2\n"
            #expect(BackupLog.latestSize(in: bad)?.snapshotBytes == 102_400)
            #expect(BackupLog.latestSize(in: "2026-11-03 22:16:09  SIZE: snapshot=9223372036854775807 added=1 total=1\n") == nil)
            #expect(BackupLog.latestSize(in: "2026-11-03 16:16:05  OK\n") == nil)
            #expect(BackupLog.latestSize(in: "") == nil)
        }

        @Test func sizeIsFoundInTheRotatedLogAndSurvivesAFailedRun() {
            let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
            let log = d.appendingPathComponent("c.log"), rot = d.appendingPathComponent("c.log.1")
            #expect(BackupLog.size(logURL: log, rotatedURL: rot) == nil)
            write("2026-11-03 16:16:05  OK\n2026-11-03 16:16:09  SIZE: snapshot=100 added=10 total=1000\n", to: rot)
            write("2026-11-03 17:00:00  SKIP: newest snapshot is 0h old (cooldown 6h)\n", to: log)
            #expect(BackupLog.size(logURL: log, rotatedURL: rot)?.totalBytes == 1_024_000)
            // a failed run after the SIZE line keeps the size and is still the last attempt
            write("2026-11-03 16:16:09  SIZE: snapshot=100 added=10 total=1000\n" + failed([]), to: log)
            #expect(BackupLog.size(logURL: log, rotatedURL: rot)?.snapshotBytes == 102_400)
            #expect(BackupLog.attempt(logURL: log, rotatedURL: rot)?.result == .failed(exit: 23, reason: .other))
        }

        @Test func aSizeLineAfterOKDoesNotChangeTheAttempt() {
            let t = "2026-11-03 16:15:20  START: \(M)\n2026-11-03 16:16:05  OK\n2026-11-03 16:16:09  SIZE: snapshot=100 added=10 total=1000\n"
            #expect(attempt(t) == ClaudeBackupAttempt(at: date("2026-11-03 16:16:05"), result: .ok, mount: M))
        }

        @Test func latestSuccessIsUnchangedForAFailedSample() {
            let t = "2026-10-31 14:51:08  START: \(M)\n2026-10-31 14:51:30  OK\n"
                + failed(["    rsync(1): error: a: open (2) in /: No such file or directory"]).replacingOccurrences(of: "14:51:08", with: "14:55:00")
            #expect(BackupLog.latestSuccess(in: t, timeZone: utc) == date("2026-10-31 14:51:30"))
        }
    }
}
