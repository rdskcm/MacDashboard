// Tests/MacDashboardTests/FolderSizesTests.swift
// Port of Checks/FolderSizesChecks.swift (CHECKS-SWIFT-TESTING).
// Blocks SIZES-BACKGROUND, SERVICE-DIRS-TIMEOUT: pure-logic checks for the one-walk folder-size job
// (splitHomeWalk, the cache store, freshness/decision, the age string) plus a
// real-machine smoke test for descendantPIDs.
// Real file (not a symlink) — main.swift owns the single top-level-statements slot,
// so this exposes a plain function it calls (see README.md).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct FolderSizesTests {
        @Test func folderSizes() async {
            // MARK: - splitHomeWalk

            let home = "/Users/u"
            let fixtureLines: [DirSize] = [
                DirSize(path: "/Users/u", bytes: 100_000),
                DirSize(path: "/Users/u/Library", bytes: 40_000),
                DirSize(path: "/Users/u/Library/Caches", bytes: 10_000),
                DirSize(path: "/Users/u/Library/Containers", bytes: 20_000),
                DirSize(path: "/Users/u/.Trash", bytes: 5_000),
                DirSize(path: "/Users/u/Documents", bytes: 30_000),
                DirSize(path: "/Users/u/Documents/Deep", bytes: 15_000),
            ]
            let servicePaths = ReportCollector.homeServicePaths(home: home)
            let split1 = ReportCollector.splitHomeWalk(home: home, lines: fixtureLines, servicePaths: servicePaths)

            #expect(Set(split1.depth1.map(\.path)) == Set(["/Users/u", "/Users/u/Library", "/Users/u/.Trash", "/Users/u/Documents"]),
                  "splitHomeWalk: depth1 == home + its direct children (got \(split1.depth1.map(\.path)))")

            let serviceByPath = Dictionary(uniqueKeysWithValues: split1.service.map { ($0.path, $0.bytes) })
            #expect(serviceByPath["/Users/u/Library/Caches"] == 10_000, "splitHomeWalk: service Caches bytes match")
            #expect(serviceByPath["/Users/u/Library/Containers"] == 20_000, "splitHomeWalk: service Containers bytes match")
            #expect(serviceByPath["/Users/u/.Trash"] == 5_000, "splitHomeWalk: service .Trash bytes match")
            #expect(split1.service.count == 3, "splitHomeWalk: exactly the three present service entries (got \(split1.service.count))")

            let expectedMissing = ["/Users/u/Library/Application Support", "/Users/u/Library/Group Containers",
                                    "/Users/u/Library/Developer"]
            #expect(split1.missing == expectedMissing, "splitHomeWalk: missing == the three absent service paths in order (got \(split1.missing))")

            // Path-prefix trap: "CachesOld" must not match "Caches".
            let trapLines = [DirSize(path: "/Users/u/Library/CachesOld", bytes: 999)]
            let split2 = ReportCollector.splitHomeWalk(home: home, lines: trapLines, servicePaths: ["/Users/u/Library/Caches"])
            #expect(split2.service.isEmpty, "splitHomeWalk: 'CachesOld' does not match 'Caches' (service empty)")
            #expect(split2.missing == ["/Users/u/Library/Caches"], "splitHomeWalk: 'Caches' reported missing despite the 'CachesOld' line")

            // MARK: - FolderSizesCacheStore

            let tmp = FileManager.default.temporaryDirectory
            let countedAt = Date(timeIntervalSince1970: 1_760_000_000)
            let sizes = FolderSizes(homeDirs: [DirSize(path: "/Users/u/Documents", bytes: 30_000)],
                                    homeDirsUnreadable: [],
                                    serviceDirs: [DirSize(path: "/Users/u/Library/Caches", bytes: 10_000)],
                                    serviceDirsUnreadable: [],
                                    countedAt: countedAt, durationSeconds: 6.4)
            let file = tmp.appendingPathComponent("folder-sizes-cache-check-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                try FolderSizesCacheStore.save(sizes, to: file)
                #expect(FolderSizesCacheStore.load(from: file) == sizes, "FolderSizesCacheStore: save/load round trip")
                let mode = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue
                #expect(mode == 0o600, "FolderSizesCacheStore: file mode 0600 (got \(String(describing: mode)))")
            } catch {
                Issue.record( "FolderSizesCacheStore: save threw \(error)")
            }

            let schema0 = tmp.appendingPathComponent("folder-sizes-cache-schema0-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: schema0) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            struct Schema0: Codable { var schema: Int = 0; var homeDirs: [DirSize] = []; var homeDirsUnreadable: [String] = []
                var serviceDirs: [DirSize]?; var serviceDirsUnreadable: [String] = []; var countedAt: Date; var durationSeconds: Double }
            try? encoder.encode(Schema0(countedAt: countedAt, durationSeconds: 1)).write(to: schema0)
            #expect(FolderSizesCacheStore.load(from: schema0) == nil, "FolderSizesCacheStore: schema 0 -> nil")

            let garbage = tmp.appendingPathComponent("folder-sizes-cache-garbage-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: garbage) }
            try? "garbage".write(to: garbage, atomically: true, encoding: .utf8)
            #expect(FolderSizesCacheStore.load(from: garbage) == nil, "FolderSizesCacheStore: garbage bytes -> nil")

            #expect(FolderSizesCacheStore.load(from: tmp.appendingPathComponent("folder-sizes-missing-\(UUID().uuidString).json")) == nil,
                  "FolderSizesCacheStore: missing file -> nil")

            // MARK: - UpdatesCacheStore still round-trips through JSONCacheFile

            let uc = UpdatesCache(items: [], checkedAt: countedAt, durationSeconds: 2.1)
            let ucFile = tmp.appendingPathComponent("updates-cache-jsoncachefile-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: ucFile) }
            do {
                try UpdatesCacheStore.save(uc, to: ucFile)
                #expect(UpdatesCacheStore.load(from: ucFile) == uc, "UpdatesCacheStore via JSONCacheFile: save/load round trip")
                let mode = (try? FileManager.default.attributesOfItem(atPath: ucFile.path)[.posixPermissions] as? NSNumber)?.intValue
                #expect(mode == 0o600, "UpdatesCacheStore via JSONCacheFile: file mode 0600 (got \(String(describing: mode)))")
            } catch {
                Issue.record( "UpdatesCacheStore via JSONCacheFile: save threw \(error)")
            }

            // MARK: - isFolderSizesCacheFresh / shouldStartSizeCount

            let now = Date(timeIntervalSince1970: 1_760_000_000)
            #expect(ReportCollector.isFolderSizesCacheFresh(countedAt: now.addingTimeInterval(-59 * 60), now: now),
                  "isFolderSizesCacheFresh: 59 min -> true")
            #expect(!ReportCollector.isFolderSizesCacheFresh(countedAt: now.addingTimeInterval(-61 * 60), now: now),
                  "isFolderSizesCacheFresh: 61 min -> false")
            #expect(!ReportCollector.isFolderSizesCacheFresh(countedAt: now.addingTimeInterval(5 * 60), now: now),
                  "isFolderSizesCacheFresh: +5 min future -> false")
            #expect(!ReportCollector.isFolderSizesCacheFresh(countedAt: nil, now: now),
                  "isFolderSizesCacheFresh: nil -> false")

            let fresh = now.addingTimeInterval(-5 * 60)
            let stale = now.addingTimeInterval(-2 * 3600)
            #expect(ReportCollector.shouldStartSizeCount(trigger: .button, countedAt: fresh, failedAt: nil, inFlight: false, now: now),
                  "shouldStartSizeCount: (.button, fresh, inFlight: false) -> true")
            #expect(!ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: fresh, failedAt: nil, inFlight: false, now: now),
                  "shouldStartSizeCount: (.automatic, fresh, false) -> false")
            #expect(ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: stale, failedAt: nil, inFlight: false, now: now),
                  "shouldStartSizeCount: (.automatic, stale, false) -> true")
            #expect(!ReportCollector.shouldStartSizeCount(trigger: .button, countedAt: nil, failedAt: nil, inFlight: true, now: now),
                  "shouldStartSizeCount: (.button, nil, inFlight: true) -> false")

            // SIZES-FAIL-BACKOFF: the last failed attempt gates automatic triggers for 1 h.
            let failedRecently = now.addingTimeInterval(-5 * 60)
            let failedLongAgo = now.addingTimeInterval(-61 * 60)
            #expect(!ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: nil, failedAt: failedRecently, inFlight: false, now: now),
                  "shouldStartSizeCount: (.automatic, no cache, failed 5 min ago) -> false")
            #expect(!ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: stale, failedAt: failedRecently, inFlight: false, now: now),
                  "shouldStartSizeCount: (.automatic, stale cache, failed 5 min ago) -> false")
            #expect(ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: nil, failedAt: failedLongAgo, inFlight: false, now: now),
                  "shouldStartSizeCount: (.automatic, no cache, failed 61 min ago) -> true")
            #expect(ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: stale, failedAt: failedLongAgo, inFlight: false, now: now),
                  "shouldStartSizeCount: (.automatic, stale cache, failed 61 min ago) -> true")
            #expect(ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: nil, failedAt: now.addingTimeInterval(5 * 60), inFlight: false, now: now),
                  "shouldStartSizeCount: (.automatic, no cache, failedAt in the future) -> true (bad clock cannot block)")
            #expect(!ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: fresh, failedAt: failedLongAgo, inFlight: false, now: now),
                  "shouldStartSizeCount: (.automatic, fresh cache, old failure) -> false")
            #expect(ReportCollector.shouldStartSizeCount(trigger: .button, countedAt: nil, failedAt: failedRecently, inFlight: false, now: now),
                  "shouldStartSizeCount: (.button, no cache, failed 5 min ago) -> true (button forces)")
            #expect(!ReportCollector.shouldStartSizeCount(trigger: .button, countedAt: nil, failedAt: failedRecently, inFlight: true, now: now),
                  "shouldStartSizeCount: (.button, failed recently, inFlight: true) -> false")

            // MARK: - folderSizesAgeString

            #expect(folderSizesAgeString(countedAt: now.addingTimeInterval(-30), now: now) == L.foldersCountedJustNow,
                  "folderSizesAgeString: 30 s -> just-now string")
            #expect(folderSizesAgeString(countedAt: now.addingTimeInterval(-5 * 60), now: now).contains("5"),
                  "folderSizesAgeString: 5 min -> contains '5'")
            #expect(folderSizesAgeString(countedAt: now.addingTimeInterval(120), now: now) == L.foldersCountedJustNow,
                  "folderSizesAgeString: future -> just-now string")

            // MARK: - SERVICE-DIRS-TIMEOUT

            do {
                let T = "SERVICE-DIRS-TIMEOUT: "
                // 1. constants
                #expect(ReportCollector.folderSizesDeadline == 90, Comment(rawValue: T + "deadline == 90"))
                #expect(FolderSizes.currentSchema == 2, Comment(rawValue: T + "currentSchema == 2"))

                // 2. duRun
                func outcome(_ t: CommandOutcome.Termination, _ out: String) -> CommandOutcome {
                    CommandOutcome(termination: t, stdout: out, stdoutTruncated: false, stderrHead: "")
                }
                #expect(ReportCollector.duRun(outcome(.timedOut, "8\t/a\n16\t/Users/u/Docu"))
                      == ReportCollector.DuRun(lines: [DirSize(path: "/a", bytes: 8192)], cut: true),
                      Comment(rawValue: T + "duRun: killed run drops the unterminated last line"))
                #expect(ReportCollector.duRun(outcome(.timedOut, "8\t/a")) == ReportCollector.DuRun(lines: [], cut: true),
                      Comment(rawValue: T + "duRun: killed run without any newline -> no lines"))
                #expect(ReportCollector.duRun(outcome(.cancelled, "")) == ReportCollector.DuRun(lines: [], cut: true),
                      Comment(rawValue: T + "duRun: cancelled -> cut"))
                #expect(ReportCollector.duRun(outcome(.exited(0), "8\t/a"))
                      == ReportCollector.DuRun(lines: [DirSize(path: "/a", bytes: 8192)], cut: false),
                      Comment(rawValue: T + "duRun: finished run keeps its last line"))
                #expect(ReportCollector.duRun(outcome(.exited(1), "")) == ReportCollector.DuRun(lines: [], cut: false),
                      Comment(rawValue: T + "duRun: failed run with no output -> empty, not cut"))

                // 3-5. assembleFolderSizes
                typealias Run = ReportCollector.DuRun
                let h = "/Users/u"
                let walkLines = [DirSize(path: "/Users/u/Library/Caches", bytes: 10_000), DirSize(path: "/Users/u/Documents", bytes: 30_000)]
                let names = ["Documents", "Library", "Private", "notes.txt", "Music"]
                let outside = ["/o1", "/o2", "/o3", "/o4"]
                let accessMap: [String: DirAccess] = [
                    "/Users/u/Library": .readable, "/Users/u/Music": .readable, "/Users/u/Private": .denied,
                    "/Users/u/Library/Containers": .readable, "/Users/u/Library/Group Containers": .denied,
                    "/o2": .readable, "/o3": .denied, "/o4": .readable]
                let access: (String) -> DirAccess = { accessMap[$0] ?? .missing }
                func assemble(_ walk: Run, _ runs: [Run]) -> FolderSizes? {
                    ReportCollector.assembleFolderSizes(home: h, homeWalk: walk, outside: outside, outsideRuns: runs,
                                                        homeChildNames: names, access: access,
                                                        countedAt: Date(timeIntervalSince1970: 0), durationSeconds: 1)
                }
                let cutRuns = [Run(lines: [DirSize(path: "/o1", bytes: 5_000)], cut: false), Run(lines: [], cut: true),
                               Run(lines: [], cut: true), Run(lines: [], cut: false)]
                let cut = assemble(Run(lines: walkLines, cut: true), cutRuns)
                #expect(cut?.homeDirs == [DirSize(path: "/Users/u/Documents", bytes: 30_000)], Comment(rawValue: T + "assemble cut: homeDirs"))
                #expect(cut?.homeDirsUnreadable == ["/Users/u/Private"], Comment(rawValue: T + "assemble cut: homeDirsUnreadable"))
                #expect(cut?.homeDirsNotMeasured == ["/Users/u/Library", "/Users/u/Music"],
                      Comment(rawValue: T + "assemble cut: homeDirsNotMeasured (got \(String(describing: cut?.homeDirsNotMeasured)))"))
                #expect(cut?.serviceDirs == [DirSize(path: "/Users/u/Library/Caches", bytes: 10_000), DirSize(path: "/o1", bytes: 5_000)],
                      Comment(rawValue: T + "assemble cut: serviceDirs"))
                #expect(cut?.serviceDirsUnreadable == ["/Users/u/Library/Group Containers", "/o3"],
                      Comment(rawValue: T + "assemble cut: serviceDirsUnreadable (/o3 refused wins over cut)"))
                #expect(cut?.serviceDirsNotMeasured == ["/Users/u/Library/Containers", "/o2"],
                      Comment(rawValue: T + "assemble cut: serviceDirsNotMeasured, /o4 in no list (got \(String(describing: cut?.serviceDirsNotMeasured)))"))
                let fin = assemble(Run(lines: walkLines, cut: false), cutRuns.map { Run(lines: $0.lines, cut: false) })
                #expect(fin?.homeDirsNotMeasured == [] && fin?.serviceDirsNotMeasured == [], Comment(rawValue: T + "assemble finished: empty not-measured lists"))
                #expect(fin?.homeDirsUnreadable == cut?.homeDirsUnreadable && fin?.serviceDirsUnreadable == cut?.serviceDirsUnreadable,
                      Comment(rawValue: T + "assemble finished: unreadable lists unchanged"))
                #expect(assemble(Run(lines: [], cut: true), cutRuns) == nil, Comment(rawValue: T + "assemble: no complete home line (cut) -> nil"))
                #expect(assemble(Run(lines: [], cut: false), cutRuns) == nil, Comment(rawValue: T + "assemble: no complete home line (finished) -> nil"))

                // 6. cache round trip + schema 1 rejected
                let f2 = FileManager.default.temporaryDirectory.appendingPathComponent("sdt-cache-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: f2) }
                let withLists = FolderSizes(homeDirs: [], homeDirsUnreadable: [], serviceDirs: nil, serviceDirsUnreadable: [],
                                            homeDirsNotMeasured: ["/Users/u/Music"], serviceDirsNotMeasured: ["/o2"],
                                            countedAt: countedAt, durationSeconds: 90)
                do {
                    try FolderSizesCacheStore.save(withLists, to: f2)
                    #expect(FolderSizesCacheStore.load(from: f2) == withLists, Comment(rawValue: T + "cache round trip keeps the not-measured lists"))
                } catch { Issue.record( Comment(rawValue: T + "cache save threw \(error)")) }
                let f1 = FileManager.default.temporaryDirectory.appendingPathComponent("sdt-cache1-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: f1) }
                struct Schema1: Codable { var schema: Int = 1; var homeDirs: [DirSize] = []; var homeDirsUnreadable: [String] = []
                    var serviceDirs: [DirSize]?; var serviceDirsUnreadable: [String] = []; var countedAt: Date; var durationSeconds: Double }
                try? encoder.encode(Schema1(countedAt: countedAt, durationSeconds: 1)).write(to: f1)
                #expect(FolderSizesCacheStore.load(from: f1) == nil, Comment(rawValue: T + "schema 1 -> nil"))
            }

            // 7. Live deadline + no orphans (temp dirs and a stub du only)
            do {
                let T = "SERVICE-DIRS-TIMEOUT: live: "
                let fm = FileManager.default
                let root = fm.temporaryDirectory.appendingPathComponent("sdt-\(UUID().uuidString)")
                defer { try? fm.removeItem(at: root) }
                let home = root.appendingPathComponent("home").path
                let out1 = root.appendingPathComponent("out1").path
                for d in ["Library/Caches", "Library/Containers", "Documents"] {
                    try? fm.createDirectory(atPath: home + "/" + d, withIntermediateDirectories: true)
                }
                try? fm.createDirectory(atPath: out1, withIntermediateDirectories: true)
                let pids = root.appendingPathComponent("pids").path
                let stub = root.appendingPathComponent("fake-du").path
                let script = """
                #!/bin/sh
                for a; do last="$a"; done
                if [ "$1" = "-xk" ]; then
                  printf '8\\t%s/Library/Caches\\n' "$last"
                  printf '16\\t%s/Docu' "$last"
                fi
                /bin/sleep 30 &
                echo $! >> '\(pids)'
                wait
                """
                try? script.write(toFile: stub, atomically: true, encoding: .utf8)
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)
                let t0 = Date()
                let r = await ReportCollector().countFolderSizes(home: home, outside: [out1], deadline: 1, du: stub)
                let elapsed = Date().timeIntervalSince(t0)
                #expect(elapsed < 4, Comment(rawValue: T + "returns in < 4 s (was \(elapsed))"))
                #expect(r != nil, Comment(rawValue: T + "result is not nil"))
                #expect(r?.serviceDirs == [DirSize(path: home + "/Library/Caches", bytes: 8192)], Comment(rawValue: T + "serviceDirs (got \(String(describing: r?.serviceDirs)))"))
                #expect(r?.serviceDirsNotMeasured == [home + "/Library/Containers", out1],
                      Comment(rawValue: T + "serviceDirsNotMeasured (got \(String(describing: r?.serviceDirsNotMeasured)))"))
                #expect(r?.serviceDirsUnreadable == [], Comment(rawValue: T + "serviceDirsUnreadable empty"))
                #expect(r?.homeDirs == [], Comment(rawValue: T + "homeDirs empty"))
                #expect(r?.homeDirsNotMeasured == [home + "/Documents", home + "/Library"],
                      Comment(rawValue: T + "homeDirsNotMeasured (got \(String(describing: r?.homeDirsNotMeasured)))"))
                #expect(!((r?.homeDirs ?? []) + (r?.serviceDirs ?? [])).contains { $0.path.hasSuffix("/Docu") }, Comment(rawValue: T + "no bogus /Docu row"))
                let pidList = ((try? String(contentsOfFile: pids, encoding: .utf8)) ?? "")
                    .split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
                #expect(pidList.count == 2, Comment(rawValue: T + "two stub sleeps were started (got \(pidList.count))"))
                for pid in pidList {
                    var gone = false
                    let until = Date().addingTimeInterval(3)
                    while Date() < until {
                        if kill(pid, 0) == -1 && errno == ESRCH { gone = true; break }
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    #expect(gone, Comment(rawValue: T + "stub sleep pid \(pid) was killed with its group"))
                }
            }

            // MARK: - descendantPIDs (live)

            let sleeper = Process()
            sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
            sleeper.arguments = ["5"]
            do {
                try sleeper.run()
                let pid = sleeper.processIdentifier
                // Give proc_listpids a moment to see the freshly spawned child.
                Thread.sleep(forTimeInterval: 0.2)
                let descendants = ProcessSampler.descendantPIDs(of: getpid())
                #expect(descendants.contains(pid), "descendantPIDs: freshly spawned child is a descendant of our pid")
                #expect(!descendants.contains(getpid()), "descendantPIDs: our own pid is excluded")
                sleeper.terminate()
                sleeper.waitUntilExit()
                let afterExit = ProcessSampler.descendantPIDs(of: getpid())
                #expect(!afterExit.contains(pid), "descendantPIDs: exited child no longer present")
            } catch {
                Issue.record( "descendantPIDs: could not spawn /bin/sleep (\(error))")
            }
        }
    }
}
