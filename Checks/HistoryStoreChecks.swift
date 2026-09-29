// Checks/HistoryStoreChecks.swift
// COVERAGE-HISTORY: behaviour checks for Engine/HistoryStore.swift — load() on missing and
// corrupt files, format changes after an update, every field-mapping branch of upsertToday,
// and the atomic-replace / failed-write paths of save(). Every write goes to a fresh temp
// directory that is removed afterwards; nothing here touches the user's App Support.
// HISTORY-DECODE-LOSS: Section E — tolerant per-entry load, save() writes every stored element
// as parsed, and an unreadable file is renamed aside instead of overwritten.

import Foundation

fileprivate func hsWriteData(_ data: Data, to url: URL) {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    } catch { check(false, "HistoryStore: fixture write failed (\(error))") }
}

fileprivate func hsWrite(_ text: String, to url: URL) {
    hsWriteData(Data(text.utf8), to: url)
}

fileprivate func hsBytes(_ url: URL) -> Data? {
    try? Data(contentsOf: url)
}

fileprivate func hsObject(_ url: URL) -> [String: Any]? {
    guard let data = hsBytes(url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

fileprivate func hsMode(_ path: String) -> UInt16? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let mode = attrs[.posixPermissions] as? NSNumber else { return nil }
    return mode.uint16Value & 0o777
}

fileprivate func hsInode(_ path: String) -> UInt64? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let n = attrs[.systemFileNumber] as? NSNumber else { return nil }
    return n.uint64Value
}

/// Today's entry, found through last_run so the checks never compute the date themselves.
fileprivate func hsEntry(_ store: HistoryStore) -> MacHistoryEntry? {
    store.state.mac_history.first { $0.date == store.state.last_run }
}

/// true when save() throws.
fileprivate func hsSaveThrows(_ store: HistoryStore) -> Bool {
    do { try store.save(); return false } catch { return true }
}

/// Names of the unreadable-file backups save() left in `dir`.
fileprivate func hsBackups(_ dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        .filter { $0.hasPrefix("mac_check_state.json.unreadable-") }
}

/// The saved mac_history array as parsed, or [] if absent.
fileprivate func hsHistory(_ url: URL) -> [Any] {
    (hsObject(url)?["mac_history"] as? [Any]) ?? []
}

func runHistoryStoreChecks() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("macdashboard-historystore-\(UUID().uuidString)", isDirectory: true)
    precondition(!root.path.contains("/Library/Application Support/"), "HistoryStoreChecks: temp root must never be App Support")
    var immutablePaths: [String] = []
    var readOnlyDirs: [String] = []
    defer {
        for p in immutablePaths { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: p) }
        for p in readOnlyDirs { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: p) }
        let fix = Process()
        fix.executableURL = URL(fileURLWithPath: "/bin/chmod")
        fix.arguments = ["-R", "u+rwx", root.path]
        try? fix.run(); fix.waitUntilExit()
        try? FileManager.default.removeItem(at: root)
    }
    let fm = FileManager.default
    let gib: Int64 = 1 << 30, mib: Int64 = 1 << 20

    // ---- Section A: load on missing / corrupt files ----
    do {
        let url = root.appendingPathComponent("a1/mac_check_state.json")
        let s = HistoryStore(url: url)
        let st = s.load()
        check(st.mac_history.isEmpty && st.last_run == nil, "HistoryStore.load: missing file ⇒ empty state")
        check(s.state.mac_history.isEmpty, "HistoryStore.load: missing file ⇒ store.state empty too")
        check(!fm.fileExists(atPath: url.path), "HistoryStore.load: missing file is not created by load")
    }

    do {
        let truncSource = "{\"last_run\":\"2024-01-03\",\"mac_history\":[{\"date\":\"2024-01-01\",\"cycles\":1},{\"date\":\"2024-01-02\",\"cycles\":2},{\"date\":\"2024-01-03\",\"cycles\":3}]}"
        let full = (try? JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(truncSource.utf8)))) ?? Data(truncSource.utf8)
        let fixtures: [(String, Data)] = [
            ("empty file", Data()),
            ("truncated JSON", full.prefix(full.count / 2)),
            ("non-JSON garbage", Data("not json at all\u{0}\u{7f}".utf8)),
            ("top-level array", Data("[1,2,3]".utf8)),
            ("top-level string", Data("\"x\"".utf8)),
            ("top-level null", Data("null".utf8)),
            ("mac_history is an object", Data("{\"last_run\":\"2024-01-01\",\"mac_history\":{}}".utf8)),
        ]
        for (n, (label, bytes)) in fixtures.enumerated() {
            let url = root.appendingPathComponent("a2/\(n).json")
            hsWriteData(bytes, to: url)
            let before = hsBytes(url)
            let st = HistoryStore(url: url).load()
            check(st.mac_history.isEmpty && st.last_run == nil, "HistoryStore.load: \(label) ⇒ empty state")
            check(hsBytes(url) == before, "HistoryStore.load: \(label) ⇒ file bytes untouched by load")
        }
    }

    do {
        let url = root.appendingPathComponent("a3/mac_check_state.json")
        hsWrite("{\"last_run\":\"2024-01-01\",\"mac_history\":[{\"date\":\"2024-01-01\"}],\"stale_key\":1}", to: url)
        let s = HistoryStore(url: url)
        s.load()
        try? fm.removeItem(at: url)
        s.load()
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        do { try s.save() } catch { check(false, "HistoryStore.load: A3 save threw \(error)") }
        check(hsObject(url)?["stale_key"] == nil, "HistoryStore.load: missing file after a good load drops the previous file's keys")
        check((hsObject(url)?["mac_history"] as? [Any])?.count == 1, "HistoryStore.load: missing file after a good load ⇒ only today is saved")
    }

    // ---- Section B: format change after an update ----
    do {
        let url = root.appendingPathComponent("b1/s.json")
        hsWrite("{\"mac_history\":[{\"date\":\"2024-01-01\",\"cycles\":5}]}", to: url)
        let st = HistoryStore(url: url).load()
        check(st.mac_history.count == 1 && st.mac_history.first?.cycles == 5 && st.last_run == nil,
              "HistoryStore.load: file without last_run decodes entries, last_run nil")
    }

    do {
        let url = root.appendingPathComponent("b2/s.json")
        hsWrite("{\"last_run\":\"2024-01-02\",\"mac_history\":[{\"date\":\"2024-01-01\"},{\"date\":\"2024-01-02\",\"cycles\":7,\"gpu_temp_c\":41,\"future\":{\"a\":1}}]}", to: url)
        let st = HistoryStore(url: url).load()
        check(st.mac_history.count == 2, "HistoryStore.load: sparse and extended entries both decode")
        if st.mac_history.count == 2 {
            let e = st.mac_history[0]
            check(e.disk_used_gb == nil && e.disk_free_gb == nil && e.battery_pct == nil && e.cycles == nil && e.swap == nil && e.macos == nil,
                  "HistoryStore.load: entry with only date ⇒ every optional field nil")
            check(st.mac_history[1].cycles == 7, "HistoryStore.load: unknown fields inside an entry are ignored, known ones decoded")
        }
    }

    do {
        let url = root.appendingPathComponent("b3/s.json")
        hsWrite("{\"last_run\":\"2024-01-01\",\"mac_history\":[{\"date\":\"2024-01-01\"}],\"nvme_skip_streak\":3,\"nvme_rate_baseline\":{\"a\":1.5,\"b\":[1,2]},\"future_flag\":true,\"future_text\":\"é ü\",\"future_null\":null}", to: url)
        let extrasBefore = (hsObject(url) ?? [:]).filter { $0.key != "mac_history" && $0.key != "last_run" }
        let s = HistoryStore(url: url)
        s.load()
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        do { try s.save() } catch { check(false, "HistoryStore.save: B3 save threw \(error)") }
        let extrasAfter = (hsObject(url) ?? [:]).filter { $0.key != "mac_history" && $0.key != "last_run" }
        check(extrasBefore.count == 5 && NSDictionary(dictionary: extrasAfter).isEqual(to: extrasBefore),
              "HistoryStore.save: unknown top-level keys of every JSON type pass through unchanged")
        check((hsObject(url)?["mac_history"] as? [Any])?.count == 2, "HistoryStore.save: past entry kept next to today")
    }

    do {
        let url = root.appendingPathComponent("b4/s.json")
        hsWrite("{\"last_run\":\"2024-01-01\",\"nvme_history\":[1]}", to: url)
        let s = HistoryStore(url: url)
        check(s.load().mac_history.isEmpty, "HistoryStore.load: file without mac_history ⇒ empty history, no crash")
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        do { try s.save() } catch { check(false, "HistoryStore.save: B4 save threw \(error)") }
        check((hsObject(url)?["mac_history"] as? [Any])?.count == 1, "HistoryStore.save: file without mac_history gains today's entry")
        check((hsObject(url)?["nvme_history"] as? [Int]) == [1], "HistoryStore.save: file without mac_history keeps its other keys")
    }

    do {
        let url = root.appendingPathComponent("b5/s.json")
        let dates = ["2024-03-01", "2024-01-01", "2024-01-01", "2024-02-01"]
        let items = dates.enumerated().map { "{\"date\":\"\($1)\",\"cycles\":\($0 + 1)}" }.joined(separator: ",")
        hsWrite("{\"last_run\":\"2024-03-01\",\"mac_history\":[\(items)]}", to: url)
        let s = HistoryStore(url: url)
        s.load()
        check(s.state.mac_history.map(\.date) == dates, "HistoryStore.load: keeps file order and duplicate dates as stored")
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        let after = s.state.mac_history.map(\.date)
        check(after.count == 5, "HistoryStore.upsertToday: duplicate past dates are both kept")
        check(after == after.sorted(), "HistoryStore.upsertToday: out-of-order file is sorted")
        check(Array(after.prefix(2)) == ["2024-01-01", "2024-01-01"], "HistoryStore.upsertToday: duplicate past dates stay adjacent at the start")
    }

    do {
        let url = root.appendingPathComponent("b6/s.json")
        hsWrite("{\"last_run\":\"2999-12-31\",\"mac_history\":[{\"date\":\"2024-01-01\"},{\"date\":\"2999-12-31\"}]}", to: url)
        let s = HistoryStore(url: url)
        s.load()
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        check(s.state.mac_history.last?.date == "2999-12-31", "HistoryStore.upsertToday: future-dated entry sorts after today")
        check(s.state.last_run != "2999-12-31" && hsEntry(s) != nil, "HistoryStore.upsertToday: last_run is today, not the future date")
    }

    do {
        var result: (today: String, store: HistoryStore)? = nil
        for attempt in 0..<2 {
            let probe = HistoryStore(url: root.appendingPathComponent("b7/probe.json"))
            probe.upsertToday(from: FullReport(), live: LiveSnapshot())
            guard let t = probe.state.last_run else { break }
            let url = root.appendingPathComponent("b7/\(attempt).json")
            hsWrite("{\"last_run\":\"\(t)\",\"mac_history\":[{\"date\":\"2020-01-01\"},{\"date\":\"\(t)\",\"cycles\":111},{\"date\":\"\(t)\",\"cycles\":222}]}", to: url)
            let s = HistoryStore(url: url)
            s.load()
            var live = LiveSnapshot()
            live.battery = BatteryInfo(cycles: 7)
            s.upsertToday(from: FullReport(), live: live)
            if s.state.last_run == t { result = (t, s); break }
        }
        check(result != nil, "HistoryStore.upsertToday: day stable within two attempts")
        if let (t, s) = result {
            check(s.state.mac_history.filter { $0.date == t }.count == 1, "HistoryStore.upsertToday: two stored entries for today collapse to one")
            check(hsEntry(s)?.cycles == 7, "HistoryStore.upsertToday: today's entry is the fresh one")
            check(s.state.mac_history.count == 2, "HistoryStore.upsertToday: other days untouched when today is duplicated")
        }
    }

    // ---- Section C: upsertToday field mapping ----
    do {
        let s = HistoryStore(url: root.appendingPathComponent("c/1.json"))
        var report = FullReport()
        report.battery = BatteryInfo(cycles: 123, maxCapacity: 91)
        report.system = SystemInfo(osVersion: "26.0", osBuild: "25A354")
        var live = LiveSnapshot()
        live.battery = BatteryInfo(cycles: 1, maxCapacity: 50)
        live.disk = DiskInfo(size: 500 * gib, avail: 100 * gib, dataUsed: 350 * gib, sysUsed: nil)
        live.swap = SwapInfo(total: 2 * gib, used: 512 * mib, free: 1536 * mib)
        s.upsertToday(from: report, live: live)
        let e = hsEntry(s)
        check(e?.cycles == 123 && e?.battery_pct == 91, "HistoryStore.upsertToday: report battery wins over live")
        check(e?.disk_used_gb == 350, "HistoryStore.upsertToday: disk used prefers dataUsed")
        check(e?.disk_free_gb == 100, "HistoryStore.upsertToday: disk free from avail")
        check(e?.swap == "512MB/2048MB", "HistoryStore.upsertToday: swap string used/total in MB")
        check(e?.macos == "26.0 (25A354)", "HistoryStore.upsertToday: macos with build")
    }

    do {
        let s = HistoryStore(url: root.appendingPathComponent("c/2.json"))
        var report = FullReport()
        report.battery = nil
        report.system = SystemInfo(osVersion: "26.0")
        var live = LiveSnapshot()
        live.battery = BatteryInfo(cycles: 5, maxCapacity: 80)
        live.disk = DiskInfo(size: 500 * gib, avail: 100 * gib + gib / 2, dataUsed: nil, sysUsed: nil)
        live.swap = SwapInfo(total: 1024 * mib, used: 512 * mib + mib / 2, free: 0)
        s.upsertToday(from: report, live: live)
        let e = hsEntry(s)
        check(e?.cycles == 5 && e?.battery_pct == 80, "HistoryStore.upsertToday: live battery used when report has none")
        check(e?.disk_free_gb == 101, "HistoryStore.upsertToday: GiB rounds half away from zero")
        check(e?.disk_used_gb == 400, "HistoryStore.upsertToday: disk used falls back to size - avail")
        check(e?.swap == "513MB/1024MB", "HistoryStore.upsertToday: MiB rounds half away from zero")
        check(e?.macos == "26.0", "HistoryStore.upsertToday: macos without build")
    }

    do {
        let s = HistoryStore(url: root.appendingPathComponent("c/3.json"))
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        let e = hsEntry(s)
        check(e != nil && e?.disk_used_gb == nil && e?.disk_free_gb == nil && e?.battery_pct == nil
              && e?.cycles == nil && e?.swap == nil && e?.macos == nil,
              "HistoryStore.upsertToday: no inputs ⇒ only date set")
    }

    do {
        let s = HistoryStore(url: root.appendingPathComponent("c/4.json"))
        var report = FullReport()
        report.system = SystemInfo(osBuild: "25A354")
        s.upsertToday(from: report, live: LiveSnapshot())
        check(hsEntry(s) != nil && hsEntry(s)?.macos == nil, "HistoryStore.upsertToday: build without version ⇒ macos nil")
    }

    // ---- Section D: save — atomic replace and failed writes ----
    do {
        let dir = root.appendingPathComponent("d1", isDirectory: true)
        let url = dir.appendingPathComponent("mac_check_state.json")
        hsWrite("{\"last_run\":\"2024-01-01\",\"mac_history\":[{\"date\":\"2024-01-01\"}]}", to: url)
        let ino0 = hsInode(url.path)
        let s = HistoryStore(url: url)
        s.load()
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        do { try s.save() } catch { check(false, "HistoryStore.save: D1 save threw \(error)") }
        let ino1 = hsInode(url.path)
        check(ino0 != nil && ino1 != nil && ino1 != ino0, "HistoryStore.save: replaces the file atomically (new inode)")
        check((try? fm.contentsOfDirectory(atPath: dir.path)) == ["mac_check_state.json"], "HistoryStore.save: no temp files left after a successful save")
    }

    do {
        let blocker = root.appendingPathComponent("d2/blocker")
        hsWrite("keep", to: blocker)
        let s = HistoryStore(url: blocker.appendingPathComponent("mac_check_state.json"))
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        check(hsSaveThrows(s), "HistoryStore.save: throws when the parent path is a regular file")
        check(hsBytes(blocker) == Data("keep".utf8), "HistoryStore.save: blocker file bytes unchanged")
    }

    do {
        let ro = root.appendingPathComponent("d3/ro", isDirectory: true)
        try? fm.createDirectory(at: ro, withIntermediateDirectories: true)
        readOnlyDirs.append(ro.path)
        try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ro.path)
        let sub = ro.appendingPathComponent("sub", isDirectory: true)
        let s = HistoryStore(url: sub.appendingPathComponent("mac_check_state.json"))
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        let threw = hsSaveThrows(s)
        let created = fm.fileExists(atPath: sub.path)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ro.path)
        check(threw, "HistoryStore.save: throws when the parent cannot be created (read-only grandparent)")
        check(!created, "HistoryStore.save: nothing created under a read-only directory")
    }

    do {
        let dir = root.appendingPathComponent("d4/MacDashboard", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        readOnlyDirs.append(dir.path)
        try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        let url = dir.appendingPathComponent("mac_check_state.json")
        let s = HistoryStore(url: url)
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        check(!hsSaveThrows(s), "HistoryStore.save: existing 0500 directory is reset to 0700 and the save succeeds")
        check(hsMode(dir.path) == 0o700, "HistoryStore.save: existing 0500 directory ends up 0700")
        check(hsMode(url.path) == 0o600, "HistoryStore.save: saved file is 0600")
    }

    do {
        let dir = root.appendingPathComponent("d5", isDirectory: true)
        let url = dir.appendingPathComponent("mac_check_state.json")
        hsWrite("{\"last_run\":\"2024-01-03\",\"mac_history\":[{\"date\":\"2024-01-01\"},{\"date\":\"2024-01-02\"},{\"date\":\"2024-01-03\"}]}", to: url)
        let good = hsBytes(url)
        let s = HistoryStore(url: url)
        s.load()
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        immutablePaths.append(url.path)
        try? fm.setAttributes([.immutable: true], ofItemAtPath: url.path)
        check(hsSaveThrows(s), "HistoryStore.save: throws when the file cannot be replaced (immutable)")
        check(hsBytes(url) == good, "HistoryStore.save: failed save leaves the previous file byte-identical")
        check(s.state.mac_history.count == 4, "HistoryStore.save: in-memory state kept after a failed save")
        let listing = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        check(listing == ["mac_check_state.json"], "HistoryStore: D5 directory after a failed save: no extra files left in the directory")
        try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)
        check(!hsSaveThrows(s), "HistoryStore.save: retry succeeds once the obstacle is gone")
        check(HistoryStore(url: url).load().mac_history.count == 4, "HistoryStore.save: retry persists all entries")
    }

    // D6: destination is a non-empty directory. The atomic write fails, and the follow-up
    // chmod on the directory succeeds, so only the write itself can make save() throw.
    do {
        let target = root.appendingPathComponent("d6/mac_check_state.json", isDirectory: true)
        hsWrite("keep", to: target.appendingPathComponent("inner.txt"))
        let s = HistoryStore(url: target)
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        check(hsSaveThrows(s), "HistoryStore.save: throws when the destination is a non-empty directory")
        check(hsBytes(target.appendingPathComponent("inner.txt")) == Data("keep".utf8), "HistoryStore.save: directory content unchanged after a failed save")
    }

    // ---- Section E: load/save safety (HISTORY-DECODE-LOSS) ----
    // E1: the confirmed loss case — 3 good days + 1 wrong-typed entry.
    do {
        let dir = root.appendingPathComponent("e1", isDirectory: true)
        let url = dir.appendingPathComponent("mac_check_state.json")
        hsWrite("{\"last_run\":\"2024-01-04\",\"mac_history\":[{\"date\":\"2024-01-01\",\"cycles\":1},{\"date\":\"2024-01-02\",\"cycles\":\"12\"},{\"date\":\"2024-01-03\",\"cycles\":3},{\"date\":\"2024-01-04\",\"cycles\":4}]}", to: url)
        let s = HistoryStore(url: url)
        s.load()
        check(s.state.mac_history.map(\.date) == ["2024-01-01", "2024-01-03", "2024-01-04"] && s.state.last_run == "2024-01-04",
              "HistoryStore.load: one wrong-typed entry is skipped, the other days load")
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        do { try s.save() } catch { check(false, "HistoryStore.save: E1 save threw \(error)") }
        let saved = hsHistory(url)
        check(saved.count == 5, "HistoryStore.save: 4 stored elements + today are saved, got \(saved.count)")
        check(saved.contains { ($0 as? [String: Any])?["date"] as? String == "2024-01-02" && ($0 as? [String: Any])?["cycles"] as? String == "12" },
              "HistoryStore.save: the entry that did not decode is saved back unchanged")
        check(hsBackups(dir).isEmpty, "HistoryStore.save: a file with one bad entry is not treated as unreadable")
        check(HistoryStore(url: url).load().mac_history.count == 4, "HistoryStore.save→load: 3 good days + today")
    }

    // E2: wrong-typed last_run.
    do {
        let url = root.appendingPathComponent("e2/s.json")
        hsWrite("{\"last_run\":5,\"mac_history\":[{\"date\":\"2024-01-01\",\"cycles\":1}]}", to: url)
        let st = HistoryStore(url: url).load()
        check(st.last_run == nil && st.mac_history.map(\.date) == ["2024-01-01"],
              "HistoryStore.load: wrong-typed last_run ⇒ nil, entries still load")
    }

    // E3: elements without a date or not objects at all.
    do {
        let url = root.appendingPathComponent("e3/s.json")
        hsWrite("{\"mac_history\":[{\"cycles\":1},7,\"x\",null,{\"date\":\"2024-01-02\"}]}", to: url)
        let s = HistoryStore(url: url)
        check(s.load().mac_history.map(\.date) == ["2024-01-02"], "HistoryStore.load: elements without a date or not objects are skipped")
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        do { try s.save() } catch { check(false, "HistoryStore.save: E3 save threw \(error)") }
        let saved = NSArray(array: hsHistory(url))
        check(saved.count == 6 && saved.contains(NSDictionary(dictionary: ["cycles": 1])) && saved.contains(7)
              && saved.contains("x") && saved.contains(NSNull()),
              "HistoryStore.save: elements that are not entries are saved back unchanged")
        let dates = s.state.mac_history.map(\.date)
        check(dates.count == 2 && dates == dates.sorted(), "HistoryStore.upsertToday: decodable entries sorted, today added")
    }

    // E4: unknown fields inside past entries survive upsert + save.
    do {
        let url = root.appendingPathComponent("e4/s.json")
        hsWrite("{\"last_run\":\"2024-01-02\",\"mac_history\":[{\"date\":\"2024-01-01\",\"gpu_temp_c\":41,\"future\":{\"a\":[1,2]}},{\"date\":\"2024-01-02\",\"cycles\":7,\"note\":\"é\"}]}", to: url)
        let before = hsHistory(url)
        let s = HistoryStore(url: url)
        s.load()
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        do { try s.save() } catch { check(false, "HistoryStore.save: E4 save threw \(error)") }
        let after = hsHistory(url)
        check(before.count == 2 && after.count == 3 && NSArray(array: Array(after.prefix(2))).isEqual(to: before),
              "HistoryStore.save: unknown fields inside past entries survive upsert + save")
    }

    // E5: a stored today element that does not decode is replaced, not duplicated.
    do {
        var done = false
        for attempt in 0..<2 where !done {
            let probe = HistoryStore(url: root.appendingPathComponent("e5/probe.json"))
            probe.upsertToday(from: FullReport(), live: LiveSnapshot())
            guard let t = probe.state.last_run else { break }
            let url = root.appendingPathComponent("e5/\(attempt).json")
            hsWrite("{\"mac_history\":[{\"date\":\"2020-01-01\"},{\"date\":\"\(t)\",\"cycles\":\"bad\"}]}", to: url)
            let s = HistoryStore(url: url)
            s.load()
            var live = LiveSnapshot()
            live.battery = BatteryInfo(cycles: 7)
            s.upsertToday(from: FullReport(), live: live)
            guard s.state.last_run == t else { continue }
            done = true
            do { try s.save() } catch { check(false, "HistoryStore.save: E5 save threw \(error)") }
            let todays = hsHistory(url).filter { ($0 as? [String: Any])?["date"] as? String == t }
            check(todays.count == 1 && (todays.first as? [String: Any])?["cycles"] as? Int == 7,
                  "HistoryStore.upsertToday: a stored today element that did not decode is replaced, not duplicated")
        }
        check(done, "HistoryStore.upsertToday: E5 day stable within two attempts")
    }

    // E6: load → save with no change leaves the JSON content equal.
    do {
        let url = root.appendingPathComponent("e6/s.json")
        hsWrite("{\"last_run\":\"2024-01-03\",\"mac_history\":[{\"date\":\"2024-01-03\",\"cycles\":3,\"gpu\":1},{\"date\":\"2024-01-01\",\"cycles\":\"bad\"},5,{\"date\":\"2024-01-02\",\"extra\":{\"a\":[1,2]}}],\"k\":true}", to: url)
        let before = hsObject(url) ?? [:]
        let s = HistoryStore(url: url)
        s.load()
        do { try s.save() } catch { check(false, "HistoryStore.save: E6 save threw \(error)") }
        check(!before.isEmpty && NSDictionary(dictionary: hsObject(url) ?? [:]).isEqual(to: before),
              "HistoryStore.save: load→save without changes keeps order, bad entries and unknown fields")
    }

    // E7: unreadable files are renamed aside byte-identical, never overwritten.
    do {
        let three = "{\"last_run\":\"2024-01-03\",\"mac_history\":[{\"date\":\"2024-01-01\"},{\"date\":\"2024-01-02\"},{\"date\":\"2024-01-03\"}]}"
        let fixtures: [(String, Data)] = [
            ("truncated JSON", Data(three.utf8).prefix(three.utf8.count / 2)),
            ("non-JSON garbage", Data("not json at all\u{0}\u{7f}".utf8)),
            ("empty file", Data()),
            ("top-level array", Data("[{\"date\":\"2024-01-01\"}]".utf8)),
            ("mac_history is an object", Data("{\"last_run\":\"2024-01-01\",\"mac_history\":{\"2024-01-01\":{\"cycles\":1}},\"nvme_history\":[1]}".utf8)),
        ]
        for (n, (label, bytes)) in fixtures.enumerated() {
            let dir = root.appendingPathComponent("e7/\(n)", isDirectory: true)
            let url = dir.appendingPathComponent("mac_check_state.json")
            hsWriteData(bytes, to: url)
            let s = HistoryStore(url: url)
            check(s.load().mac_history.isEmpty, "HistoryStore.load: \(label) ⇒ empty state")
            s.upsertToday(from: FullReport(), live: LiveSnapshot())
            check(!hsSaveThrows(s), "HistoryStore.save: \(label) ⇒ save succeeds")
            let backups = hsBackups(dir)
            check(backups.count == 1 && hsBytes(dir.appendingPathComponent(backups.first ?? "-")) == bytes,
                  "HistoryStore.save: \(label) ⇒ the unreadable file is renamed aside byte-identical, not overwritten")
            check(hsHistory(url).count == 1, "HistoryStore.save: \(label) ⇒ the new file starts with today")
            check(!hsSaveThrows(s) && hsBackups(dir).count == 1, "HistoryStore.save: \(label) ⇒ a second save makes no second backup")
        }
        check((hsObject(root.appendingPathComponent("e7/4/mac_check_state.json"))?["nvme_history"] as? [Int]) == [1],
              "HistoryStore.save: other top-level keys of an object whose mac_history is not an array pass through")
    }

    // E8: a file that exists but cannot be read (mode 000) is not treated as missing.
    do {
        let dir = root.appendingPathComponent("e8", isDirectory: true)
        let url = dir.appendingPathComponent("mac_check_state.json")
        let good = Data("{\"last_run\":\"2024-01-02\",\"mac_history\":[{\"date\":\"2024-01-01\"},{\"date\":\"2024-01-02\"}]}".utf8)
        hsWriteData(good, to: url)
        try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let s = HistoryStore(url: url)
        check(s.load().mac_history.isEmpty, "HistoryStore.load: existing file that cannot be read ⇒ empty state")
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        check(!hsSaveThrows(s), "HistoryStore.save: save succeeds after loading a file that cannot be read")
        let backups = hsBackups(dir)
        if let b = backups.first { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent(b).path) }
        check(backups.count == 1 && hsBytes(dir.appendingPathComponent(backups.first ?? "-")) == good,
              "HistoryStore.save: a file that could not be read is renamed aside, not overwritten")
    }

    // E9: the rename fails (immutable file) ⇒ save throws, file stays; the retry still renames first.
    do {
        let dir = root.appendingPathComponent("e9", isDirectory: true)
        let url = dir.appendingPathComponent("mac_check_state.json")
        let junk = Data("not json".utf8)
        hsWriteData(junk, to: url)
        let s = HistoryStore(url: url)
        s.load()
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        immutablePaths.append(url.path)
        try? fm.setAttributes([.immutable: true], ofItemAtPath: url.path)
        check(hsSaveThrows(s), "HistoryStore.save: throws when the unreadable file cannot be renamed aside (immutable)")
        check(hsBytes(url) == junk && hsBackups(dir).isEmpty, "HistoryStore.save: a failed rename leaves the unreadable file in place, byte-identical")
        try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)
        check(!hsSaveThrows(s), "HistoryStore.save: retry succeeds once the obstacle is gone")
        let backups = hsBackups(dir)
        check(backups.count == 1 && hsBytes(dir.appendingPathComponent(backups.first ?? "-")) == junk,
              "HistoryStore.save: the retry still renames the unreadable file aside first")
    }

    // E10: a missing file is created without a backup.
    do {
        let dir = root.appendingPathComponent("e10", isDirectory: true)
        let s = HistoryStore(url: dir.appendingPathComponent("mac_check_state.json"))
        s.load()
        s.upsertToday(from: FullReport(), live: LiveSnapshot())
        check(!hsSaveThrows(s) && (try? fm.contentsOfDirectory(atPath: dir.path)) == ["mac_check_state.json"],
              "HistoryStore.save: a missing file is created without any backup")
    }
}
