// Tests/MoonportTests/ClaudeBackupJobTests.swift
// BACKUP-CARD-FAILURE R5, R6: the job plist reader, launch arguments, the next-run calendar and the cooldown skip.
import Foundation
import Testing
@testable import Moonport

extension SerialTests {
    struct ClaudeBackupJobTests {
        private var utcCal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
        private func at(_ s: String) -> Date {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.date(from: s)!
        }
        private func tempDir() -> URL {
            let d = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBackupJobTests-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            return d
        }
        private func plist(_ d: [String: Any], named name: String = "com.example.claude-backup.plist", in dir: URL) {
            let data = try! PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
            try? data.write(to: dir.appendingPathComponent(name))
        }
        private func program(_ dir: URL, bundle: Bool = true) -> String {
            let app = dir.appendingPathComponent("ClaudeBackup.app")
            if bundle { try? FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true) }
            return app.path + "/Contents/MacOS/ClaudeBackup"
        }

        @Test func realShape() {
            let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
            plist(["Label": "com.example.claude-backup", "ProgramArguments": [program(d)], "StartOnMount": true, "RunAtLoad": true,
                   "StartCalendarInterval": ["Hour": 13, "Minute": 0]], in: d)
            let job = ClaudeBackupJob.read(agentsDir: d)
            #expect(job?.appPath == d.appendingPathComponent("ClaudeBackup.app").path)
            #expect(job?.schedule == [.init(minute: 0, hour: 13)])
            #expect(job?.startsOnMount == true && job?.label == "com.example.claude-backup")
        }

        @Test func variants() {
            func job(_ extra: [String: Any], bundle: Bool = true, program prog: String? = nil, file: String = "com.example.claude-backup.plist") -> ClaudeBackupJob? {
                let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
                var dict: [String: Any] = ["Label": "x", "ProgramArguments": [prog ?? program(d, bundle: bundle)]]
                dict.merge(extra) { $1 }
                plist(dict, named: file, in: d)
                return ClaudeBackupJob.read(agentsDir: d)
            }
            #expect(job(["StartCalendarInterval": [["Hour": 13, "Minute": 0], ["Hour": 20]]])?.schedule.count == 2)
            #expect(job(["StartCalendarInterval": ["Hour": 13], "Disabled": true])?.schedule == [])
            #expect(job([:])?.schedule == [])
            #expect(job(["StartCalendarInterval": [String: Any]()])?.schedule == [])
            #expect(job([:], program: "/usr/bin/plain")?.appPath == nil)
            #expect(job([:], bundle: false)?.appPath == nil)
            #expect(job([:], file: "com.other.thing.plist") == nil)
            #expect(ClaudeBackupJob.read(agentsDir: FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")) == nil)
        }

        @Test func launchArguments() {
            #expect(ClaudeBackupJob.launchArguments(appPath: "/a/B.app") == ["-n", "-g", "/a/B.app", "--args", "--force"])
        }

        @Test func launchEnvironmentKeepsLocalTimeZone() async {
            let out = await CommandRunner.run("/bin/date", ["+%z"], timeout: 5, environment: ClaudeBackupJob.launchEnvironment)
            let secs = TimeZone.current.secondsFromGMT()
            let sign = secs < 0 ? "-" : "+"
            let hh = String(format: "%02d", abs(secs) / 3600)
            let mm = String(format: "%02d", (abs(secs) % 3600) / 60)
            #expect(out.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "\(sign)\(hh)\(mm)")
        }

        @Test func nextRun() {
            let cal = utcCal
            let e = ClaudeBackupJob.CalendarEntry(minute: 0, hour: 13)
            #expect(ClaudeBackupJob.nextRun([e], after: at("2026-11-03 12:00:00"), calendar: cal) == at("2026-11-03 13:00:00"))
            #expect(ClaudeBackupJob.nextRun([e], after: at("2026-11-03 13:00:00"), calendar: cal) == at("2026-11-04 13:00:00"))
            #expect(ClaudeBackupJob.nextRun([e], after: at("2026-11-03 13:01:00"), calendar: cal) == at("2026-11-04 13:00:00"))
            let two = [e, ClaudeBackupJob.CalendarEntry(minute: 30, hour: 9)]
            #expect(ClaudeBackupJob.nextRun(two, after: at("2026-11-03 08:00:00"), calendar: cal) == at("2026-11-03 09:30:00"))
            for wd in [0, 7] {
                let n = ClaudeBackupJob.nextRun([.init(minute: 0, hour: 1, weekday: wd)], after: at("2026-11-03 00:00:00"), calendar: cal)!
                #expect(cal.component(.weekday, from: n) == 1, "weekday \(wd) is a Sunday")
            }
            #expect(ClaudeBackupJob.nextRun([], after: at("2026-11-03 12:00:00"), calendar: cal) == nil)
        }

        @Test func nextCopyingRunSkipsTheCooldown() {
            let cal = utcCal, e = [ClaudeBackupJob.CalendarEntry(minute: 0, hour: 13)]
            let now = at("2026-11-03 12:00:00")
            #expect(ClaudeBackupJob.nextCopyingRun(e, now: now, newestSuccess: at("2026-11-03 11:00:00"), calendar: cal) == at("2026-11-04 13:00:00"))
            #expect(ClaudeBackupJob.nextCopyingRun(e, now: now, newestSuccess: at("2026-11-03 06:00:00"), calendar: cal) == at("2026-11-03 13:00:00"))
            #expect(ClaudeBackupJob.nextCopyingRun(e, now: now, newestSuccess: nil, calendar: cal) == at("2026-11-03 13:00:00"))
        }

        @Test func sourceHasNoUsername() throws {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Moonport/Engine")
            for name in ["ClaudeBackupJob.swift", "BackupLog.swift", "ClaudeBackupController.swift"] {
                let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
                #expect(!text.contains("rdskcm"), "\(name)")
            }
        }
    }
}
