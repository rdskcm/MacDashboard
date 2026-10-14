// Tests/MacDashboardTests/PrivacyTests.swift
// Port of Checks/main.swift lines 2999-3116 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

private func v21PosixMode(_ path: String) -> UInt16? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let mode = attrs[.posixPermissions] as? NSNumber else { return nil }
    return mode.uint16Value & 0o777
}

extension SerialTests {
    struct PrivacyTests {
        @Test func privacy() async throws {
            // =====================================================================
            // MARK: - Block V21-PRIVACY-CI: file permissions, output caps, TCC strings
            // =====================================================================

            do {
                // Block A: N6 (file permissions on 0600 files and 0700 directory)
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("macdashboard-v21-\(UUID().uuidString)", isDirectory: true)
                defer {
                    try? FileManager.default.removeItem(at: root)
                }

                // Case 1: upgrade path (pre-existing 0755 directory is tightened)
                do {
                    let dir = root.appendingPathComponent("old/MacDashboard", isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o755])
                    let file = dir.appendingPathComponent("mac_report.txt")
                    do {
                        try ReportWriter.write(text: "x", to: file)
                    } catch {
                        Issue.record("ReportWriter.write: upgrade path created file (\(error))")
                    }
                    #expect(v21PosixMode(dir.path) == 0o700, "ReportWriter.write: pre-existing 0755 directory is tightened to 0700")
                    #expect(v21PosixMode(file.path) == 0o600, "ReportWriter.write: file created 0600")
                }

                // Case 2: fresh path (non-existent directory is created 0700)
                do {
                    let dir = root.appendingPathComponent("new/MacDashboard", isDirectory: true)
                    let file = dir.appendingPathComponent("mac_report.txt")
                    do {
                        try ReportWriter.write(text: "x", to: file)
                    } catch {
                        Issue.record("ReportWriter.write: fresh path created file (\(error))")
                    }
                    #expect(v21PosixMode(dir.path) == 0o700, "ReportWriter.write: fresh directory created 0700")
                    #expect(v21PosixMode(file.path) == 0o600, "ReportWriter.write: file created 0600")
                }

                // Case 3: HistoryStore (same permissions as ReportWriter)
                do {
                    let dir = root.appendingPathComponent("history/MacDashboard", isDirectory: true)
                    let file = dir.appendingPathComponent("mac_check_state.json")
                    let store = HistoryStore(url: file)
                    do {
                        try store.save()
                    } catch {
                        Issue.record("HistoryStore.save: file created (\(error))")
                    }
                    #expect(v21PosixMode(file.path) == 0o600, "HistoryStore.save: file created 0600")
                    #expect(v21PosixMode(dir.path) == 0o700, "HistoryStore.save: directory remains 0700")
                }

                // Case 4: HistoryStore keeps every day — no entry cap (HISTORY-UNCAP)
                do {
                    let dir = root.appendingPathComponent("uncap/MacDashboard", isDirectory: true)
                    let file = dir.appendingPathComponent("mac_check_state.json")
                    var utcCal = Calendar(identifier: .gregorian)
                    utcCal.timeZone = TimeZone(identifier: "UTC")!
                    let dayFmt = DateFormatter()
                    dayFmt.dateFormat = "yyyy-MM-dd"
                    dayFmt.locale = Locale(identifier: "en_US_POSIX")
                    dayFmt.timeZone = utcCal.timeZone
                    let start = utcCal.date(from: DateComponents(year: 2020, month: 1, day: 1))!
                    // 70 past days, 2020-01-01 ... 2020-03-10, written newest-first to exercise the sort.
                    let seeded: [[String: Any]] = (0..<70).reversed().map { i in
                        ["date": dayFmt.string(from: utcCal.date(byAdding: .day, value: i, to: start)!), "cycles": i]
                    }
                    let legacy: [String: Any] = ["last_run": "2020-03-10", "mac_history": seeded, "nvme_history": [1, 2, 3]]
                    do {
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        try JSONSerialization.data(withJSONObject: legacy).write(to: file)

                        let store = HistoryStore(url: file)
                        #expect(store.load().mac_history.count == 70, "HistoryStore.load: 70 seeded entries decoded")
                        store.upsertToday(from: FullReport(), live: LiveSnapshot())
                        store.upsertToday(from: FullReport(), live: LiveSnapshot())   // same day again ⇒ replace, not append
                        let h = store.state.mac_history
                        #expect(h.count == 71, "HistoryStore.upsertToday: 70 past days + today ⇒ 71 entries kept (no cap), got \(h.count)")
                        #expect(h.first?.date == "2020-01-01", "HistoryStore.upsertToday: oldest day survives")
                        #expect(h.map(\.date) == h.map(\.date).sorted(), "HistoryStore.upsertToday: entries sorted by date")
                        #expect(h.last?.date == store.state.last_run, "HistoryStore.upsertToday: today is the last entry")

                        try store.save()
                        let reloaded = HistoryStore(url: file).load()
                        #expect(reloaded.mac_history.count == 71, "HistoryStore.save→load: all 71 entries persisted")
                        #expect(reloaded.mac_history.first?.date == "2020-01-01", "HistoryStore.save→load: oldest day persisted")
                        let rawObj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any]
                        #expect((rawObj?["nvme_history"] as? [Int]) == [1, 2, 3], "HistoryStore.save: unknown legacy key nvme_history passes through")
                    } catch {
                        Issue.record("HistoryStore uncap check: temp file setup/save failed (\(error))")
                    }
                }

                // Block B: N5 (stdout cap at outputCap with lineBufferCap enforcement)
                let collector = LockedLines()
                let result = await runCommand("/bin/sh", ["-c", "head -c 9000000 /dev/zero | tr '\\0' 'x'"],
                                        timeout: 30, onLine: { line, _ in
                    collector.append(line, false)
                }).text
                #expect(result != nil, "CommandRunner.run(onLine): 9 MB output ⇒ non-nil (not truncated to empty)")
                #expect(result?.utf8.count == CommandRunner.outputCap, "CommandRunner.run(onLine): 9 MB output ⇒ byte count == outputCap")
                let lineCount = collector.lines.count
                #expect(lineCount >= 2, "CommandRunner.run(onLine): 9 MB newline-free stream ⇒ \(lineCount) delivered lines (>= 2, lineBufferCap flushed)")
                let totalDelivered = collector.lines.map { $0.0.utf8.count }.reduce(0, +)
                #expect(totalDelivered > CommandRunner.outputCap, "CommandRunner.run(onLine): delivered line count (\(totalDelivered) bytes) > outputCap (proof onLine gets bytes past cap)")

                // Check the small-output path is untouched
                let smallResult = await runCommand("/bin/sh", ["-c", "printf 'a\\nb\\n'"], timeout: 10, onLine: { _, _ in
                }).text
                #expect(smallResult == "a\nb\n", "CommandRunner.run(onLine): small output under cap ⇒ full output preserved")
            }
        }
    }
}
