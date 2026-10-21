// Tests/MacDashboardTests/BrewAndUpdatesTests.swift
// Port of Checks/main.swift lines 1737-1997 (CHECKS-SWIFT-TESTING). BrewProgressParser, brew cache freshness and the report caption time.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct BrewAndUpdatesTests {
        @Test func brewProgressParser() async {
            // =====================================================================
            // MARK: - BrewProgressParser
            // =====================================================================

            do {
                var parser = BrewProgressParser(total: 3)

                let ok1 = parser.consume(line: "==> Fetching downloads for: docker, git and node", isStderr: false)
                #expect(ok1,
                      "BrewProgressParser: Fetching downloads header -> changed=true")
                #expect(parser.progress?.phase == .downloading,
                      "BrewProgressParser: Fetching downloads header -> phase .downloading")

                _ = parser.consume(line: "✔︎ Bottle Manifest docker (28.0.1)", isStderr: true)
                #expect(parser.progress?.downloadsDone == 1, "BrewProgressParser: first ✔︎ line -> downloadsDone 1")
                #expect(parser.progress?.formula == "docker", "BrewProgressParser: first ✔︎ line -> formula \"docker\"")

                _ = parser.consume(line: "✔︎ Bottle docker (28.0.1)", isStderr: true)
                #expect(parser.progress?.downloadsDone == 2, "BrewProgressParser: second ✔︎ line -> downloadsDone 2")

                let ok2 = parser.consume(line: "random noise", isStderr: false)
                #expect(!ok2,
                      "BrewProgressParser: unrecognized line -> changed=false")

                let ok3 = parser.consume(line: "==> Upgrading docker", isStderr: false)
                #expect(ok3,
                      "BrewProgressParser: \"==> Upgrading docker\" -> changed=true")
                #expect(parser.progress?.phase == .upgrading, "BrewProgressParser: Upgrading docker -> phase .upgrading")
                #expect(parser.progress?.completed == 1, "BrewProgressParser: Upgrading docker -> completed 1")
                #expect(parser.progress?.formula == "docker", "BrewProgressParser: Upgrading docker -> formula \"docker\"")

                let ok4 = parser.consume(line: "  27.0 -> 28.0.1", isStderr: false)
                #expect(!ok4,
                      "BrewProgressParser: version line -> changed=false")

                let ok5 = parser.consume(line: "==> Pouring docker--28.0.1.arm64_tahoe.bottle.tar.gz", isStderr: false)
                #expect(!ok5,
                      "BrewProgressParser: Pouring line -> changed=false")

                let ok6 = parser.consume(line: "==> Upgrading 2 dependents of upgraded formulae:", isStderr: false)
                #expect(!ok6,
                      "BrewProgressParser: dependents header ignored -> changed=false")

                let ok7 = parser.consume(line: "==> Installing node dependency: icu4c", isStderr: false)
                #expect(ok7,
                      "BrewProgressParser: Installing dependency line -> changed=true")
                #expect(parser.progress?.completed == 1,
                      "BrewProgressParser: Installing dependency line -> completed unchanged at 1")
                #expect(parser.progress?.formula == "icu4c", "BrewProgressParser: Installing dependency line -> formula \"icu4c\"")

                let ok8 = parser.consume(line: "==> Upgrading node", isStderr: false)
                #expect(ok8,
                      "BrewProgressParser: \"==> Upgrading node\" -> changed=true")
                #expect(parser.progress?.completed == 2, "BrewProgressParser: Upgrading node -> completed 2")
                #expect(parser.progress?.formula == "node", "BrewProgressParser: Upgrading node -> formula \"node\"")
            }

            do {
                // total=0 (unknown outdated count): no crash, no percent math — that's the UI's job.
                var parser = BrewProgressParser(total: 0)
                let ok9 = parser.consume(line: "==> Upgrading foo", isStderr: false)
                #expect(ok9,
                      "BrewProgressParser: total=0 -> Upgrading foo changed=true")
                #expect(parser.progress?.total == 0, "BrewProgressParser: total=0 -> progress.total == 0")
                #expect(parser.progress?.completed == 1, "BrewProgressParser: total=0 -> completed 1")
            }

            do {
                // No "Fetching downloads for:" header seen — a lone ✔︎ line still starts the
                // downloading phase.
                var parser = BrewProgressParser(total: 1)
                let ok10 = parser.consume(line: "✔︎ Formula hello (1.0)", isStderr: true)
                #expect(ok10,
                      "BrewProgressParser: lone ✔︎ line (no Fetching header) -> changed=true")
                #expect(parser.progress?.phase == .downloading,
                      "BrewProgressParser: lone ✔︎ line (no Fetching header) -> phase .downloading")
            }

            do {
                var parser = BrewProgressParser(total: 1)
                let ok11 = parser.consume(line: "✘ Bottle foo (1.0)", isStderr: true)
                #expect(!ok11,
                      "BrewProgressParser: ✘ (failed download) line -> changed=false")
            }
        }

        @Test func brewCacheAndUpdates() async {
            // =====================================================================
            // MARK: - Block N5: brew cache freshness, report caption time, cancellation scope
            // =====================================================================

            do {
                let now = Date(timeIntervalSince1970: 1_760_000_000)
                #expect(!ReportCollector.isBrewCacheFresh(collectedAt: nil, now: now),
                      "isBrewCacheFresh: nil collectedAt -> false")
                #expect(ReportCollector.isBrewCacheFresh(collectedAt: now.addingTimeInterval(-300), now: now),
                      "isBrewCacheFresh: 5 min old -> true")
                #expect(!ReportCollector.isBrewCacheFresh(collectedAt: now.addingTimeInterval(-660), now: now),
                      "isBrewCacheFresh: 11 min old -> false")
                #expect(!ReportCollector.isBrewCacheFresh(collectedAt: now.addingTimeInterval(-600), now: now),
                      "isBrewCacheFresh: exactly window-old -> false (strict <)")
                #expect(!ReportCollector.isBrewCacheFresh(collectedAt: now.addingTimeInterval(60), now: now),
                      "isBrewCacheFresh: future timestamp (clock rollback) -> false")
            }

            // COLLECT-FASTPATH: update-check cache rules, trigger mapping, softwareupdate parsing, cache store.
            do {
                let now = Date(timeIntervalSince1970: 1_760_000_000)
                let h6: TimeInterval = 6 * 60 * 60
                #expect(!ReportCollector.isUpdatesCacheFresh(checkedAt: nil, now: now), "isUpdatesCacheFresh: nil -> false")
                #expect(ReportCollector.isUpdatesCacheFresh(checkedAt: now, now: now), "isUpdatesCacheFresh: age 0 -> true")
                #expect(ReportCollector.isUpdatesCacheFresh(checkedAt: now.addingTimeInterval(-(h6 - 1)), now: now),
                      "isUpdatesCacheFresh: 6 h - 1 s -> true")
                #expect(!ReportCollector.isUpdatesCacheFresh(checkedAt: now.addingTimeInterval(-h6), now: now),
                      "isUpdatesCacheFresh: exactly 6 h -> false")
                #expect(!ReportCollector.isUpdatesCacheFresh(checkedAt: now.addingTimeInterval(60), now: now),
                      "isUpdatesCacheFresh: future timestamp -> false")

                let fresh = now.addingTimeInterval(-60), stale = now.addingTimeInterval(-h6 - 1)
                #expect(!ReportCollector.shouldStartUpdateCheck(trigger: .automatic, checkedAt: fresh, inFlight: false, now: now),
                      "shouldStartUpdateCheck: automatic + fresh -> false")
                #expect(ReportCollector.shouldStartUpdateCheck(trigger: .automatic, checkedAt: stale, inFlight: false, now: now),
                      "shouldStartUpdateCheck: automatic + stale -> true")
                #expect(ReportCollector.shouldStartUpdateCheck(trigger: .automatic, checkedAt: nil, inFlight: false, now: now),
                      "shouldStartUpdateCheck: automatic + no cache -> true")
                #expect(ReportCollector.shouldStartUpdateCheck(trigger: .button, checkedAt: fresh, inFlight: false, now: now),
                      "shouldStartUpdateCheck: button + fresh -> true")
                #expect(!ReportCollector.shouldStartUpdateCheck(trigger: .button, checkedAt: nil, inFlight: true, now: now),
                      "shouldStartUpdateCheck: in flight -> false (button)")
                #expect(!ReportCollector.shouldStartUpdateCheck(trigger: .automatic, checkedAt: stale, inFlight: true, now: now),
                      "shouldStartUpdateCheck: in flight -> false (automatic)")

                #expect(CollectTrigger.button.commandQoS == .userInitiated, "CollectTrigger.button -> userInitiated")
                #expect(CollectTrigger.automatic.commandQoS == .utility, "CollectTrigger.automatic -> utility")
                #expect(CollectTrigger.merged(nil, .automatic) == .automatic, "CollectTrigger.merged(nil, automatic) == automatic")
                #expect(CollectTrigger.merged(.automatic, .button) == .button, "CollectTrigger.merged(automatic, button) == button")
                #expect(CollectTrigger.merged(.button, .automatic) == .button, "CollectTrigger.merged(button, automatic) == button")

                func outcome(_ t: CommandOutcome.Termination, out: String = "", err: String = "") -> CommandOutcome {
                    CommandOutcome(termination: t, stdout: out, stdoutTruncated: false, stderrHead: err)
                }
                let header = "Software Update Tool\n\nFinding available software\n"
                let none = "No new software available.\n"
                #expect(ReportCollector.parseSoftwareUpdate(outcome(.exited(0), out: header, err: none)) == [],
                      "parseSoftwareUpdate: 'no new software' on stderr -> []")
                #expect(ReportCollector.parseSoftwareUpdate(outcome(.exited(0), out: header + none)) == [],
                      "parseSoftwareUpdate: 'no new software' on stdout -> []")
                #expect(ReportCollector.parseSoftwareUpdate(outcome(.exited(0), out: header + "* Label: macOS Foo 27.0.1-27A1\n\tTitle: macOS Foo, Version: 27.0.1\n"))
                        == [SoftwareUpdate(label: "macOS Foo 27.0.1-27A1", title: "macOS Foo", version: "27.0.1", sizeBytes: nil, restartRequired: false)],
                        "parseSoftwareUpdate: label extracted")
                let sized = ReportCollector.parseSoftwareUpdate(outcome(.exited(0), out: header
                    + "* Label: macOS Foo 27.0.1-27A1\n\tTitle: macOS Foo, Version: 27.0.1, Size: 3276800KiB, Recommended: YES, Action: restart,\n"))
                #expect(sized?.first?.sizeBytes == 3_276_800 * 1024 && sized?.first?.restartRequired == true,
                        "parseSoftwareUpdate: Size + Action: restart parsed")
                #expect(ReportCollector.parseSoftwareUpdate(outcome(.exited(0), out: header + "* Label: Bar-1.0\n"))
                        == [SoftwareUpdate(label: "Bar-1.0", title: "Bar-1.0", version: nil, sizeBytes: nil, restartRequired: false)],
                        "parseSoftwareUpdate: label without Title line -> title = label")
                let two = ReportCollector.parseSoftwareUpdate(outcome(.exited(0), out: header
                    + "* Label: A-1\n\tTitle: A, Version: 1, Size: 10K, Action: restart,\n* Label: B-2\n\tTitle: B, Version: 2, Size: 5MiB,\n"))
                #expect(two?.map(\.label) == ["A-1", "B-2"] && two?.map(\.restartRequired) == [true, false]
                        && two?.map(\.sizeBytes) == [10 * 1024, 5 * 1_048_576], "parseSoftwareUpdate: two labels, per-item fields")
                func tl(_ s: String) -> (title: String?, version: String?, sizeBytes: Int64?, restart: Bool) {
                    ReportCollector.parseSoftwareUpdateTitleLine(s)
                }
                #expect(tl("Title: X, Version: 1, Size: 7K,").sizeBytes == Int64(7 * 1024), "title line: K")
                #expect(tl("Title: X, Size: 7KiB").sizeBytes == Int64(7 * 1024), "title line: KiB")
                #expect(tl("Title: X, Size: 3MiB").sizeBytes == Int64(3 * 1_048_576), "title line: MiB")
                #expect(tl("Title: X, Size: 2GiB").sizeBytes == Int64(2 * 1_073_741_824), "title line: GiB")
                #expect(tl("Title: X, Size: 123").sizeBytes == Int64(123), "title line: no unit = bytes")
                #expect(tl("Title: X, Size: 5TB").sizeBytes == nil, "title line: unknown unit -> nil")
                #expect(tl("Title: X, Action: Restart,").restart && !tl("Title: X, Action: shut down,").restart, "title line: Action restart, case-insensitive")
                #expect(tl("Title: , Version: 1").title == nil && tl("Title: X, Version: 1").title == "X", "title line: empty title -> nil")
                #expect(ReportCollector.parseSoftwareUpdate(outcome(.exited(0), out: header)) == nil,
                      "parseSoftwareUpdate: unclassifiable output -> nil")
                #expect(ReportCollector.parseSoftwareUpdate(outcome(.exited(1), out: header, err: "Can't connect")) == nil,
                      "parseSoftwareUpdate: network error -> nil")
                #expect(ReportCollector.parseSoftwareUpdate(outcome(.timedOut)) == nil, "parseSoftwareUpdate: timeout -> nil")
                #expect(ReportCollector.parseSoftwareUpdate(.launchFailed(2)) == nil, "parseSoftwareUpdate: launch failure -> nil")

                #expect(ReportCollector.parseBrewOutdated(outcome(.exited(0), out: "git\n  node \n\n")) == ["git", "node"],
                      "parseBrewOutdated: exit 0 with list -> names")
                #expect(ReportCollector.parseBrewOutdated(outcome(.exited(0))) == [], "parseBrewOutdated: exit 0, empty -> []")
                #expect(ReportCollector.parseBrewOutdated(outcome(.exited(0), out: " \n\n")) == [], "parseBrewOutdated: exit 0, blank -> []")
                #expect(ReportCollector.parseBrewOutdated(outcome(.exited(1))) == nil, "parseBrewOutdated: exit 1, empty -> nil")
                #expect(ReportCollector.parseBrewOutdated(outcome(.exited(1), out: "git\n", err: "Error: x")) == nil,
                      "parseBrewOutdated: exit 1 with output -> nil")
                #expect(ReportCollector.parseBrewOutdated(outcome(.timedOut)) == nil, "parseBrewOutdated: timeout -> nil")
                #expect(ReportCollector.parseBrewOutdated(outcome(.timedOut, out: "git\n")) == nil, "parseBrewOutdated: timeout with output -> nil")
                #expect(ReportCollector.parseBrewOutdated(outcome(.cancelled)) == nil, "parseBrewOutdated: cancelled -> nil")
                #expect(ReportCollector.parseBrewOutdated(.launchFailed(2)) == nil, "parseBrewOutdated: launch failure -> nil")
                #expect(ReportCollector.parseBrewOutdated(outcome(.signaled(9), out: "git\n")) == nil, "parseBrewOutdated: signaled -> nil")
                #expect(ReportCollector.parseBrewOutdated(outcome(.signaled(0), out: "git\n")) == nil, "parseBrewOutdated: status unknown -> nil")
                #expect(ReportCollector.parseBrewOutdated(CommandOutcome(termination: .exited(0), stdout: "git\n",
                                                                       stdoutTruncated: true, stderrHead: "")) == nil,
                      "parseBrewOutdated: truncated stdout -> nil")
                #expect(ReportCollector.brewCheckFailed(status: .installed(version: "Homebrew 4.6.0"), outdated: nil),
                      "brewCheckFailed: version ok + outdated nil -> true")
                #expect(!ReportCollector.brewCheckFailed(status: .installed(version: "Homebrew 4.6.0"), outdated: []),
                      "brewCheckFailed: version ok + [] -> false")
                #expect(ReportCollector.brewCheckFailed(status: .installed(version: nil), outdated: []),
                      "brewCheckFailed: version unknown + [] -> true")
                #expect(ReportCollector.brewCheckFailed(status: .installed(version: nil), outdated: nil),
                      "brewCheckFailed: version unknown + nil -> true")
                #expect(!ReportCollector.brewCheckFailed(status: .notInstalled, outdated: nil),
                      "brewCheckFailed: not installed -> false")
                #expect(!ReportCollector.brewCheckFailed(status: nil, outdated: nil),
                      "brewCheckFailed: not collected -> false")
                #expect(ReportCollector.parseBrewVersion(outcome(.exited(0), out: "Homebrew 4.6.0\nHomebrew/homebrew-core (git revision abc)\n"))
                        == "Homebrew 4.6.0", "parseBrewVersion: exit 0 -> first line")
                #expect(ReportCollector.parseBrewVersion(outcome(.exited(0), out: "\n  Homebrew 4.6.0  \n")) == "Homebrew 4.6.0",
                      "parseBrewVersion: leading blank line + spaces -> trimmed first non-empty line")
                #expect(ReportCollector.parseBrewVersion(outcome(.exited(0))) == nil, "parseBrewVersion: exit 0, empty -> nil")
                #expect(ReportCollector.parseBrewVersion(outcome(.exited(0), out: " \n\n")) == nil, "parseBrewVersion: exit 0, blank -> nil")
                #expect(ReportCollector.parseBrewVersion(outcome(.exited(1), out: "Homebrew 4.6.0\n", err: "Error: x")) == nil,
                      "parseBrewVersion: exit 1 with output -> nil")
                #expect(ReportCollector.parseBrewVersion(outcome(.timedOut, out: "Homebrew 4.6.0\n")) == nil, "parseBrewVersion: timeout -> nil")
                #expect(ReportCollector.parseBrewVersion(outcome(.cancelled)) == nil, "parseBrewVersion: cancelled -> nil")
                #expect(ReportCollector.parseBrewVersion(.launchFailed(2)) == nil, "parseBrewVersion: launch failure -> nil")
                #expect(ReportCollector.parseBrewVersion(outcome(.signaled(9), out: "Homebrew 4.6.0\n")) == nil, "parseBrewVersion: signaled -> nil")

                #expect(ReportCollector.seconds(.milliseconds(1500)) == 1.5, "ReportCollector.seconds(1500 ms) == 1.5")

                let tmp = FileManager.default.temporaryDirectory
                let file = tmp.appendingPathComponent("updates-cache-check-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: file) }
                let cache = UpdatesCache(items: [SoftwareUpdate(label: "macOS Foo 27.0.1-27A1", title: "macOS Foo", version: "27.0.1", sizeBytes: nil, restartRequired: false)],
                                         checkedAt: Date(timeIntervalSince1970: 1_760_000_000), durationSeconds: 5.63)
                do {
                    try UpdatesCacheStore.save(cache, to: file)
                    #expect(UpdatesCacheStore.load(from: file) == cache, "UpdatesCacheStore: save/load round trip")
                    let mode = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue
                    #expect(mode == 0o600, "UpdatesCacheStore: file mode 0600 (got \(String(describing: mode)))")
                } catch {
                    Issue.record("UpdatesCacheStore: save threw \(error)")
                }
                #expect(UpdatesCacheStore.load(from: tmp.appendingPathComponent("updates-cache-missing-\(UUID().uuidString).json")) == nil,
                      "UpdatesCacheStore: missing file -> nil")
                let old = tmp.appendingPathComponent("updates-cache-old-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: old) }
                try? Data(#"{"items":["a"],"checkedAt":"2025-10-01T00:00:00Z","durationSeconds":1}"#.utf8).write(to: old)
                #expect(UpdatesCacheStore.load(from: old) == nil, "UpdatesCacheStore: old [String] items shape -> nil (never checked)")
                let bad = tmp.appendingPathComponent("updates-cache-bad-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: bad) }
                try? "garbage".write(to: bad, atomically: true, encoding: .utf8)
                #expect(UpdatesCacheStore.load(from: bad) == nil, "UpdatesCacheStore: garbage file -> nil")

            // COLLECT-FASTPATH Step 5: Updates age string, seconds formatting, timings section.
            do {
                let now = Date(timeIntervalSince1970: 1_760_000_000)
                #expect(updatesAgeString(checkedAt: now, now: now) == L.updatesCheckedJustNow, "updatesAgeString: now -> just now")
                #expect(updatesAgeString(checkedAt: now.addingTimeInterval(120), now: now) == L.updatesCheckedJustNow,
                      "updatesAgeString: future -> just now")
                #expect(updatesAgeString(checkedAt: now.addingTimeInterval(-59), now: now) == L.updatesCheckedJustNow,
                      "updatesAgeString: 59 s -> just now")
                #expect(updatesAgeString(checkedAt: now.addingTimeInterval(-60), now: now) == L.updatesCheckedAgo("1 \(L.uptimeUnitMinute)"),
                      "updatesAgeString: 60 s -> 1 minute")
                #expect(updatesAgeString(checkedAt: now.addingTimeInterval(-3 * 3600), now: now) == L.updatesCheckedAgo("3 \(L.uptimeUnitHour)"),
                      "updatesAgeString: 3 h -> hours")
                #expect(updatesAgeString(checkedAt: now.addingTimeInterval(-2 * 86_400), now: now) == L.updatesCheckedAgo("2 \(L.uptimeUnitDay)"),
                      "updatesAgeString: 2 d -> days")
                #expect(ReportWriter.fmtSeconds(5.63) == "5\(L.decimalSeparator)6 \(L.uptimeUnitSecond)", "fmtSeconds: 5.63")
                #expect(ReportWriter.fmtSeconds(-1).hasPrefix("0"), "fmtSeconds: negative clamps to 0")

                var unchecked = FullReport()
                unchecked.updates = nil
                let t1 = ReportWriter.render(report: unchecked, live: LiveSnapshot(), history: HistoryState())
                #expect(t1.contains(L.reportNotChecked) && !t1.contains("No new software available."),
                      "ReportWriter: updates nil -> not checked, never 'no updates'")

                var timed = FullReport()
                timed.updates = []
                timed.updatesCheckedAt = now
                timed.sectionDurations = ["system": 0.2]
                timed.passDuration = 7.0
                timed.folderSizesCountedAt = now
                timed.folderSizesCountDuration = 6.4
                timed.homeDirs = [DirSize(path: "/Users/u/Documents", bytes: 1024)]
                let t2 = ReportWriter.render(report: timed, live: LiveSnapshot(), history: HistoryState())
                #expect(t2.contains(L.reportSectionTimings), "ReportWriter: timings header present")
                #expect(t2.contains(L.reportTimingsPass(ReportWriter.fmtSeconds(7.0))), "ReportWriter: whole-pass line present")
                #expect(t2.contains(L.reportTimingsFolderSizes(ReportWriter.fmtSeconds(6.4), reportUpdatedTimeString(now))),
                      "ReportWriter: EN folder-sizes timing line present (SIZES-BACKGROUND)")
                #expect(t2.contains(L.reportFoldersCountedAt(reportUpdatedTimeString(now))),
                      "ReportWriter: '(counted …)' line present (SIZES-BACKGROUND)")
                #expect(!t2.contains("homeDirs:"), "ReportWriter: COLLECTION TIMES has no homeDirs: row (SIZES-BACKGROUND)")
            }

            }
        }

        @Test func reportUpdatedTime() async {
            do {
                let cal = Calendar.current
                let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
                let sameDay = cal.date(bySettingHour: 9, minute: 30, second: 0, of: now)!
                let older = now.addingTimeInterval(-48 * 3600)
                #expect(reportUpdatedTimeString(sameDay, now: now, calendar: cal)
                          == sameDay.formatted(date: .omitted, time: .shortened),
                      "reportUpdatedTimeString: same day -> time-only branch")
                #expect(reportUpdatedTimeString(older, now: now, calendar: cal)
                          == older.formatted(date: .abbreviated, time: .shortened),
                      "reportUpdatedTimeString: older day -> date+time branch")
            }
        }
    }
}
