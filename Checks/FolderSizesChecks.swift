// Checks/FolderSizesChecks.swift
// Block SIZES-BACKGROUND: pure-logic checks for the one-walk folder-size job
// (splitHomeWalk, the cache store, freshness/decision, the age string) plus a
// real-machine smoke test for descendantPIDs.
// Real file (not a symlink) — main.swift owns the single top-level-statements slot,
// so this exposes a plain function it calls (see README.md).

import Foundation

func runFolderSizesChecks() {
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

    check(Set(split1.depth1.map(\.path)) == Set(["/Users/u", "/Users/u/Library", "/Users/u/.Trash", "/Users/u/Documents"]),
          "splitHomeWalk: depth1 == home + its direct children (got \(split1.depth1.map(\.path)))")

    let serviceByPath = Dictionary(uniqueKeysWithValues: split1.service.map { ($0.path, $0.bytes) })
    check(serviceByPath["/Users/u/Library/Caches"] == 10_000, "splitHomeWalk: service Caches bytes match")
    check(serviceByPath["/Users/u/Library/Containers"] == 20_000, "splitHomeWalk: service Containers bytes match")
    check(serviceByPath["/Users/u/.Trash"] == 5_000, "splitHomeWalk: service .Trash bytes match")
    check(split1.service.count == 3, "splitHomeWalk: exactly the three present service entries (got \(split1.service.count))")

    let expectedMissing = ["/Users/u/Library/Application Support", "/Users/u/Library/Group Containers",
                            "/Users/u/Library/Developer"]
    check(split1.missing == expectedMissing, "splitHomeWalk: missing == the three absent service paths in order (got \(split1.missing))")

    // Path-prefix trap: "CachesOld" must not match "Caches".
    let trapLines = [DirSize(path: "/Users/u/Library/CachesOld", bytes: 999)]
    let split2 = ReportCollector.splitHomeWalk(home: home, lines: trapLines, servicePaths: ["/Users/u/Library/Caches"])
    check(split2.service.isEmpty, "splitHomeWalk: 'CachesOld' does not match 'Caches' (service empty)")
    check(split2.missing == ["/Users/u/Library/Caches"], "splitHomeWalk: 'Caches' reported missing despite the 'CachesOld' line")

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
        check(FolderSizesCacheStore.load(from: file) == sizes, "FolderSizesCacheStore: save/load round trip")
        let mode = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue
        check(mode == 0o600, "FolderSizesCacheStore: file mode 0600 (got \(String(describing: mode)))")
    } catch {
        check(false, "FolderSizesCacheStore: save threw \(error)")
    }

    let schema0 = tmp.appendingPathComponent("folder-sizes-cache-schema0-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: schema0) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    struct Schema0: Codable { var schema: Int = 0; var homeDirs: [DirSize] = []; var homeDirsUnreadable: [String] = []
        var serviceDirs: [DirSize]?; var serviceDirsUnreadable: [String] = []; var countedAt: Date; var durationSeconds: Double }
    try? encoder.encode(Schema0(countedAt: countedAt, durationSeconds: 1)).write(to: schema0)
    check(FolderSizesCacheStore.load(from: schema0) == nil, "FolderSizesCacheStore: schema 0 -> nil")

    let garbage = tmp.appendingPathComponent("folder-sizes-cache-garbage-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: garbage) }
    try? "garbage".write(to: garbage, atomically: true, encoding: .utf8)
    check(FolderSizesCacheStore.load(from: garbage) == nil, "FolderSizesCacheStore: garbage bytes -> nil")

    check(FolderSizesCacheStore.load(from: tmp.appendingPathComponent("folder-sizes-missing-\(UUID().uuidString).json")) == nil,
          "FolderSizesCacheStore: missing file -> nil")

    // MARK: - UpdatesCacheStore still round-trips through JSONCacheFile

    let uc = UpdatesCache(items: [], checkedAt: countedAt, durationSeconds: 2.1)
    let ucFile = tmp.appendingPathComponent("updates-cache-jsoncachefile-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: ucFile) }
    do {
        try UpdatesCacheStore.save(uc, to: ucFile)
        check(UpdatesCacheStore.load(from: ucFile) == uc, "UpdatesCacheStore via JSONCacheFile: save/load round trip")
        let mode = (try? FileManager.default.attributesOfItem(atPath: ucFile.path)[.posixPermissions] as? NSNumber)?.intValue
        check(mode == 0o600, "UpdatesCacheStore via JSONCacheFile: file mode 0600 (got \(String(describing: mode)))")
    } catch {
        check(false, "UpdatesCacheStore via JSONCacheFile: save threw \(error)")
    }

    // MARK: - isFolderSizesCacheFresh / shouldStartSizeCount

    let now = Date(timeIntervalSince1970: 1_760_000_000)
    check(ReportCollector.isFolderSizesCacheFresh(countedAt: now.addingTimeInterval(-59 * 60), now: now),
          "isFolderSizesCacheFresh: 59 min -> true")
    check(!ReportCollector.isFolderSizesCacheFresh(countedAt: now.addingTimeInterval(-61 * 60), now: now),
          "isFolderSizesCacheFresh: 61 min -> false")
    check(!ReportCollector.isFolderSizesCacheFresh(countedAt: now.addingTimeInterval(5 * 60), now: now),
          "isFolderSizesCacheFresh: +5 min future -> false")
    check(!ReportCollector.isFolderSizesCacheFresh(countedAt: nil, now: now),
          "isFolderSizesCacheFresh: nil -> false")

    let fresh = now.addingTimeInterval(-5 * 60)
    let stale = now.addingTimeInterval(-2 * 3600)
    check(ReportCollector.shouldStartSizeCount(trigger: .button, countedAt: fresh, inFlight: false, now: now),
          "shouldStartSizeCount: (.button, fresh, inFlight: false) -> true")
    check(!ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: fresh, inFlight: false, now: now),
          "shouldStartSizeCount: (.automatic, fresh, false) -> false")
    check(ReportCollector.shouldStartSizeCount(trigger: .automatic, countedAt: stale, inFlight: false, now: now),
          "shouldStartSizeCount: (.automatic, stale, false) -> true")
    check(!ReportCollector.shouldStartSizeCount(trigger: .button, countedAt: nil, inFlight: true, now: now),
          "shouldStartSizeCount: (.button, nil, inFlight: true) -> false")

    // MARK: - folderSizesAgeString

    check(folderSizesAgeString(countedAt: now.addingTimeInterval(-30), now: now) == L.foldersCountedJustNow,
          "folderSizesAgeString: 30 s -> just-now string")
    check(folderSizesAgeString(countedAt: now.addingTimeInterval(-5 * 60), now: now).contains("5"),
          "folderSizesAgeString: 5 min -> contains '5'")
    check(folderSizesAgeString(countedAt: now.addingTimeInterval(120), now: now) == L.foldersCountedJustNow,
          "folderSizesAgeString: future -> just-now string")

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
        check(descendants.contains(pid), "descendantPIDs: freshly spawned child is a descendant of our pid")
        check(!descendants.contains(getpid()), "descendantPIDs: our own pid is excluded")
        sleeper.terminate()
        sleeper.waitUntilExit()
        let afterExit = ProcessSampler.descendantPIDs(of: getpid())
        check(!afterExit.contains(pid), "descendantPIDs: exited child no longer present")
    } catch {
        check(false, "descendantPIDs: could not spawn /bin/sleep (\(error))")
    }
}
