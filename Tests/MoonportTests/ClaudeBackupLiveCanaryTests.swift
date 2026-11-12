// Tests/MoonportTests/ClaudeBackupLiveCanaryTests.swift
// BACKUP-CARD-FAILURE R13 opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanaryClaudeBackup
// Reads the real job plist, log, lock and mount on this Mac and checks them against plutil, grep, launchctl and mount.
// Read-only: starts no backup and writes nothing.
import Foundation
import Testing
@testable import Moonport

extension SerialTests {
    struct ClaudeBackupLiveCanaryTests {
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryClaudeBackup() async {
            let now = Date()
            // 1. the job
            guard let job = await ClaudeBackupJob.load() else { print("liveCanary no job on this Mac"); return }
            print("liveCanary job label = \(job.label ?? "nil"), appPath = \(job.appPath ?? "nil"), schedule = \(job.schedule), startsOnMount = \(job.startsOnMount)")

            // 2. plutil agrees with the parsed calendar
            let dir = ClaudeBackupJob.defaultAgentsDir
            let name = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(ClaudeBackupJob.plistSuffix) }.sorted().first ?? ""
            let plistPath = dir.appendingPathComponent(name).path
            let hour = await CommandRunner.run("/usr/bin/plutil", ["-extract", "StartCalendarInterval.Hour", "raw", "-o", "-", plistPath], timeout: 5)
            let minute = await CommandRunner.run("/usr/bin/plutil", ["-extract", "StartCalendarInterval.Minute", "raw", "-o", "-", plistPath], timeout: 5)
            print("liveCanary plutil Hour = \(hour.stdout.trimmingCharacters(in: .whitespacesAndNewlines)), Minute = \(minute.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            #expect(Int(hour.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) == job.schedule.first?.hour)
            #expect(Int(minute.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) == job.schedule.first?.minute)

            // 3. launchctl agrees on whether the job is loaded
            let lc = await CommandRunner.run("/bin/launchctl", ["print", "gui/\(getuid())/\(job.label ?? "")"], timeout: 5)
            var code: Int32 = -1
            if case .exited(let c) = lc.termination { code = c }
            print("liveCanary launchctl print exit = \(code), schedule empty = \(job.schedule.isEmpty)")
            #expect((code == 0) == !job.schedule.isEmpty)

            // 4. next runs
            let status = BackupLog.status()
            var newest: Date? = nil
            if case .lastSuccess(let d)? = status { newest = d }
            let next = ClaudeBackupJob.nextRun(job.schedule, after: now)
            let copying = ClaudeBackupJob.nextCopyingRun(job.schedule, now: now, newestSuccess: newest)
            print("liveCanary nextRun = \(String(describing: next)), nextCopyingRun = \(String(describing: copying))")
            if let next, let copying {
                #expect(next > now && next <= now.addingTimeInterval(8 * 86_400) && copying >= next)
            } else {
                #expect(job.schedule.isEmpty, "no next run only for an empty schedule")
            }

            // 5. the app bundle
            if let app = job.appPath {
                let macos = app + "/Contents/MacOS"
                let files = (try? FileManager.default.contentsOfDirectory(atPath: macos)) ?? []
                let hasExec = files.contains { FileManager.default.isExecutableFile(atPath: macos + "/" + $0) }
                print("liveCanary app = \(app), executables in Contents/MacOS = \(files)")
                #expect(app.hasSuffix(".app") && hasExec)
            }

            // 6. the last attempt against grep
            let attempt = await BackupLog.readAttempt(now: now)
            print("liveCanary attempt at = \(String(describing: attempt?.at)), result = \(String(describing: attempt?.result)), mount = \(attempt?.mount ?? "nil")")
            let pattern = "^[0-9-]{10} [0-9:]{8}  (START: |OK$|FAILED \\(exit )"
            var grepLine = ""
            for url in [BackupLog.logURL, BackupLog.rotatedURL] {
                let g = await CommandRunner.run("/usr/bin/grep", ["-E", pattern, url.path], timeout: 10)
                if let last = g.stdout.split(separator: "\n").last { grepLine = String(last); break }
            }
            print("liveCanary grep last event line = \(grepLine)")
            if let attempt {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                #expect(String(grepLine.prefix(19)) == f.string(from: attempt.at))
                if grepLine.dropFirst(21).hasPrefix("FAILED (exit "), case .failed(let exit, _) = attempt.result {
                    #expect(Int(grepLine.dropFirst(34).prefix { $0.isNumber }) == exit)
                }
            } else {
                #expect(grepLine.isEmpty)
            }

            // 7. status
            print("liveCanary status = \(String(describing: status))")
            if let newest { #expect(newest <= now) }
            if case .ok? = attempt?.result, let a = attempt, let newest { #expect(abs(a.at.timeIntervalSince(newest)) <= 60) }

            // 8. lock
            let pid = BackupLog.lockPID(at: BackupLog.lockPIDURL)
            let alive = pid.map(BackupLog.isProcessAlive)
            print("liveCanary lockPID = \(String(describing: pid)), isProcessAlive = \(String(describing: alive))")
            if attempt?.result == .running { #expect(alive == true) }

            // 9. mount
            if let mount = attempt?.mount {
                let m = await CommandRunner.run("/sbin/mount", [], timeout: 5)
                let inMount = m.stdout.contains(" on \(mount) (")
                let exists = await BackupLog.pathExists(mount)
                print("liveCanary mount \(mount): in mount output = \(inMount), pathExists = \(exists)")
                #expect(inMount == exists)
            }
        }
    }
}
