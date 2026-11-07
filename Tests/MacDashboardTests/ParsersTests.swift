// Tests/MacDashboardTests/ParsersTests.swift
// Port of Checks/main.swift lines 152-526 (CHECKS-SWIFT-TESTING). The Parsers.* / TM / purgeable / snapshot / SMART / launchctl / pmset / security fixtures.
import Foundation
import Testing
@testable import MacDashboard

struct ParsersTests {
    @Test func parseSize() async {
        // =====================================================================
        // MARK: - Parsers.parseSize
        // =====================================================================

        #expect(Parsers.parseSize("62G") == 62 * GIB, "parseSize: 62G")
        #expect(Parsers.parseSize("228Gi") == 228 * GIB, "parseSize: 228Gi")
        #expect(Parsers.parseSize("4.0K") == Int64((4.0 * 1024).rounded()), "parseSize: 4.0K")
        #expect(Parsers.parseSize("0B") == 0, "parseSize: 0B")
        #expect(Parsers.parseSize("545M+") == 545 * MIB, "parseSize: 545M+")
        let ok = Parsers.parseSize("3808K-") == 3808 * 1024
        #expect(ok, "parseSize: 3808K-")
        #expect(Parsers.parseSize("abc") == nil, "parseSize: abc ⇒ nil")
        #expect(Parsers.parseSize("") == nil, "parseSize: empty ⇒ nil")
    }

    @Test func swapUsage() async {
        // =====================================================================
        // MARK: - Parsers.swapUsage
        // =====================================================================

        do {
            let line = "vm.swapusage: total = 2048.00M  used = 430.44M  free = 1617.56M  (encrypted)"
            let swap = Parsers.swapUsage(line: line)
            let mib = 1024.0 * 1024.0
            #expect(swap?.total == Int64(2048.00 * mib), "swapUsage: total bytes")
            #expect(swap?.used == Int64(430.44 * mib), "swapUsage: used bytes")
            #expect(swap?.free == Int64(1617.56 * mib), "swapUsage: free bytes")
            #expect(Parsers.swapUsage(line: "vm.swapusage: nothing relevant here") == nil, "swapUsage: line without fields ⇒ nil")
        }
    }

    @Test func batteryPmset() async {
        // =====================================================================
        // MARK: - Parsers.batteryPmset
        // =====================================================================

        do {
            let laptopCharging = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=4390321)\t91%; charging; 0:12 remaining present: true"
            let b = Parsers.batteryPmset(laptopCharging)
            #expect(b?.source == .ac, "batteryPmset: AC source")
            #expect(b?.charge == 91, "batteryPmset: charge 91")
            #expect(b?.state == .charging, "batteryPmset: charging state")

            let laptopDischarging = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=4390321)\t63%; discharging; 2:30 remaining present: true"
            #expect(Parsers.batteryPmset(laptopDischarging)?.state == .discharging, "batteryPmset: discharging state")

            let acAttachedNotCharging = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=4390321)\t100%; AC attached; not charging; present: true"
            #expect(Parsers.batteryPmset(acAttachedNotCharging)?.state == .notCharging, "batteryPmset: split AC-attached/not-charging clauses")

            // Desktop-representative fixture: no battery/power fields recognizable at all.
            let desktopNoBattery = "No relevant power information available.\n"
            #expect(Parsers.batteryPmset(desktopNoBattery) == nil, "batteryPmset: no battery-related fields ⇒ nil")
        }
    }

    @Test func batteryPowerProfile() async {
        // =====================================================================
        // MARK: - Parsers.batteryPowerProfile
        // =====================================================================

        do {
            let profile = "      Cycle Count: 334\n      Condition: Normal\n      Maximum Capacity: 86%"
            let (cycles, condition, maxCap) = Parsers.batteryPowerProfile(profile)
            #expect(cycles == 334, "batteryPowerProfile: cycles 334")
            #expect(condition == "Normal", "batteryPowerProfile: condition Normal")
            #expect(maxCap == 86, "batteryPowerProfile: maxCapacity 86")
        }
    }

    @Test func hardwareProfile() async {
        // =====================================================================
        // MARK: - Parsers.hardwareProfile
        // =====================================================================

        do {
            func hwJSON(_ item: String) -> Data { Data("{\"SPHardwareDataType\":[{\(item)}]}".utf8) }
            let asItem = "\"machine_name\":\"MacBook Pro\",\"machine_model\":\"Mac15,3\",\"chip_type\":\"Apple M3\","
                + "\"number_processors\":\"proc 8:0:4:4\",\"physical_memory\":\"8 GB\""
            let info = Parsers.hardwareProfile(json: hwJSON(asItem))
            #expect(info?.modelName == "MacBook Pro", "hardwareProfile: modelName")
            #expect(info?.modelId == "Mac15,3", "hardwareProfile: modelId")
            #expect(info?.chip == "Apple M3", "hardwareProfile: Apple Silicon chip")
            #expect(info?.cores == "8 (4 Performance and 4 Efficiency)", "hardwareProfile: cores from proc 8:0:4:4")
            #expect(info?.memBytes == 8 * GIB, "hardwareProfile: Apple Silicon memBytes == 8 GiB")
            let three = Parsers.hardwareProfile(json: hwJSON(asItem.replacingOccurrences(of: "proc 8:0:4:4", with: "proc 8:4:4")))
            #expect(three?.cores == "8 (4 Performance and 4 Efficiency)", "hardwareProfile: three-field proc form, same cores")

            let intel = "\"cpu_type\":\"6-Core Intel Core i7\",\"number_processors\":6,\"physical_memory\":\"16 GB\""
            let intelInfo = Parsers.hardwareProfile(json: hwJSON(intel))
            #expect(intelInfo?.chip == "6-Core Intel Core i7", "hardwareProfile: Intel chip from cpu_type")
            #expect(intelInfo?.cores == "6", "hardwareProfile: Intel cores == 6")
            #expect(intelInfo?.memBytes == 16 * GIB, "hardwareProfile: Intel memBytes")

            func cores(_ proc: String, _ levels: [Parsers.PerfLevel] = []) -> String? {
                Parsers.hardwareProfile(json: hwJSON(asItem.replacingOccurrences(of: "proc 8:0:4:4", with: proc)),
                                        perfLevels: levels)?.cores
            }
            typealias PL = Parsers.PerfLevel
            let thisMac = [PL(name: "Performance", count: 4), PL(name: "Efficiency", count: 4)]
            #expect(cores("proc 8:0:4:4", thisMac) == "8 (4 Performance and 4 Efficiency)", "cores: this Mac with OS perflevels, unchanged")
            #expect(cores("proc 8:4:4", thisMac) == "8 (4 Performance and 4 Efficiency)", "cores: 3-field with OS perflevels")
            #expect(cores("proc 8:0:4:4", [PL(name: "", count: 4), PL(name: "", count: 4)]) == "8 (4 Performance and 4 Efficiency)",
                  "cores: empty OS names ⇒ verified built-in names")
            #expect(cores("proc 8:8:0") == "8 (8 Performance)", "cores: zero tier omitted")
            let superPerf = [PL(name: "Super", count: 6), PL(name: "Performance", count: 12)]
            #expect(cores("proc 18:6:12:0", superPerf) == "18 (6 Super and 12 Performance)", "cores: non-zero 2nd field named by OS")
            #expect(cores("proc 18:6:12:0") == "18", "cores: non-zero 2nd field, no perflevels ⇒ total")
            #expect(cores("proc 18:6:12:0", thisMac) == "18", "cores: perflevel counts mismatch ⇒ total")
            let threeTiers = [PL(name: "Super", count: 6), PL(name: "Performance", count: 6), PL(name: "Efficiency", count: 6)]
            #expect(cores("proc 18:6:6:6", threeTiers) == "18 (6 Super, 6 Performance and 6 Efficiency)", "cores: three tiers named by OS")
            #expect(cores("proc 18:6:6:6") == "18", "cores: three tiers, no perflevels ⇒ total")
            for (odd, want) in [("proc 10:x:2", "10"), ("proc 18:6:8:4", "18"), ("proc 8:0:4:4:1", "8"),
                                ("proc 8:0:4:5", "8"), ("proc 8", "8"), ("proc 8:", "8"), ("proc 8:4:-4", "8")] {
                let r = Parsers.hardwareProfile(json: hwJSON(asItem.replacingOccurrences(of: "proc 8:0:4:4", with: odd)))
                #expect(r?.cores == want && r?.chip == "Apple M3", "hardwareProfile: '\(odd)' ⇒ total '\(want)', other fields set")
            }
            for bad in ["8 cores", "", "proc ", "proc x:4:4", "proc 0:0:0:0", "PROC 8:4:4", "proc 9999999:1:1"] {
                let r = Parsers.hardwareProfile(json: hwJSON(asItem.replacingOccurrences(of: "proc 8:0:4:4", with: bad)))
                #expect(r != nil && r?.cores == nil && r?.chip == "Apple M3", "hardwareProfile: '\(bad)' ⇒ cores nil, other fields set")
            }
            #expect(Parsers.hardwareProfile(json: hwJSON("\"chip_type\":\"Apple M3\",\"number_processors\":0"))?.cores == nil,
                  "hardwareProfile: Int 0 ⇒ cores nil")
            #expect(Parsers.hardwareProfile(json: hwJSON("\"chip_type\":\"Apple M3\",\"number_processors\":true")) == nil,
                  "hardwareProfile: number_processors bool ⇒ nil")
            #expect(Parsers.hardwareProfile(json: Data("{\"SPHardwareDataType\":[]}".utf8)) == nil, "hardwareProfile: empty array ⇒ nil")
            #expect(Parsers.hardwareProfile(json: Data()) == nil, "hardwareProfile: empty data ⇒ nil")
            #expect(Parsers.hardwareProfile(json: Data("garbage".utf8)) == nil, "hardwareProfile: garbage ⇒ nil")
            let full = hwJSON(asItem)
            #expect(Parsers.hardwareProfile(json: full.prefix(full.count / 2)) == nil, "hardwareProfile: truncated ⇒ nil")
        }
    }

    @Test func systemVersion() async {
        // =====================================================================
        // MARK: - Parsers.systemVersion
        // =====================================================================

        do {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>ProductName</key><string>macOS</string>
            <key>ProductVersion</key><string>26.5.2</string>
            <key>ProductBuildVersion</key><string>25F84</string>
            </dict></plist>
            """
            let info = Parsers.systemVersion(plist: Data(plist.utf8))
            #expect(info?.osName == "macOS", "systemVersion: osName")
            #expect(info?.osVersion == "26.5.2", "systemVersion: osVersion")
            #expect(info?.osBuild == "25F84", "systemVersion: osBuild")
            #expect(Parsers.systemVersion(plist: Data("garbage".utf8)) == nil, "systemVersion: garbage ⇒ nil")
            #expect(Parsers.systemVersion(plist: Data()) == nil, "systemVersion: empty ⇒ nil")
            let live = FileManager.default.contents(atPath: "/System/Library/CoreServices/SystemVersion.plist")
                .flatMap { Parsers.systemVersion(plist: $0) }
            #expect(live?.osName == "macOS" && live?.osVersion != nil && live?.osBuild != nil, "systemVersion: real file smoke")
        }
    }

    @Test func uptimeSeconds() async {
        // =====================================================================
        // MARK: - Parsers.uptimeSeconds + fmtUptime(seconds:language:)
        // =====================================================================

        func line(_ segment: String) -> String { "21:50  up \(segment), 2 users, load averages: 1.20 1.15 1.10" }
        // (uptime(1) segment, seconds, RU text, EN text)
        let cases: [(String, Int, String, String)] = [
            ("10 days, 22:32", 10 * 86_400 + 22 * 3600 + 32 * 60, "10 дн 22 ч 32 мин", "10 d 22 h 32 min"),
            ("2 days, 3 mins", 2 * 86_400 + 3 * 60, "2 дн 3 мин", "2 d 3 min"),
            ("1 day, 1 hr", 86_400 + 3600, "1 дн 1 ч", "1 d 1 h"),
            ("22:32", 22 * 3600 + 32 * 60, "22 ч 32 мин", "22 h 32 min"),
            ("5:12", 5 * 3600 + 12 * 60, "5 ч 12 мин", "5 h 12 min"),
            ("5 mins", 300, "5 мин", "5 min"),
            ("30 secs", 30, "30 с", "30 s"),
            ("3 days, 5 secs", 3 * 86_400 + 5, "3 дн 5 с", "3 d 5 s"),
        ]
        for (segment, seconds, ru, en) in cases {
            let parsed = Parsers.uptimeSeconds(line(segment))
            #expect(parsed == seconds, "uptimeSeconds: \(segment) -> \(seconds) (got \(String(describing: parsed)))")
            #expect(fmtUptime(seconds: seconds, language: .ru) == ru, "fmtUptime RU: \(segment)")
            #expect(fmtUptime(seconds: seconds, language: .en) == en, "fmtUptime EN: \(segment)")
        }
        #expect(Parsers.uptimeSeconds(line("3 weeks, 2 mins")) == nil, "uptimeSeconds: unknown unit -> nil")
        #expect(Parsers.uptimeSeconds(line("2 days, soon")) == nil, "uptimeSeconds: unrecognised part -> nil")
        #expect(Parsers.uptimeSeconds("no uptime here") == nil, "uptimeSeconds: no uptime line -> nil")
    }

    @Test func tmDestination() async {
        // =====================================================================
        // MARK: - Parsers.tmDestination
        // =====================================================================

        do {
            func tmPlist(_ body: String) -> Data {
                Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\(body)</dict></plist>".utf8)
            }
            func entry(_ f: String) -> String { "<dict>\(f)</dict>" }
            let x = "<key>Name</key><string>X</string><key>Kind</key><string>Local</string>"
                + "<key>MountPoint</key><string>/Volumes/Y</string><key>QuotaGB</key><integer>499</integer>"
            let two = tmPlist("<key>Destinations</key><array>\(entry(x))"
                + "\(entry("<key>Name</key><string>ShouldNotAppear</string><key>Kind</key><string>Network</string>"))</array>")
            if case .configured(let d) = Parsers.tmDestination(plist: two) {
                #expect(d.name == "X" && d.kind == "Local" && d.mountPoint == "/Volumes/Y", "tmDestination: FIRST entry fields")
                let ok = d.quotaBytes == 499 * 1_000_000_000
                #expect(ok, "tmDestination: QuotaGB integer 499 ⇒ decimal bytes")
            } else { Issue.record("tmDestination: two destinations ⇒ configured") }

            let real = tmPlist("<key>Destinations</key><array>\(entry("<key>Name</key><string>X</string><key>QuotaGB</key><real>499.5</real>"))</array>")
            if case .configured(let d) = Parsers.tmDestination(plist: real) {
                #expect(d.quotaBytes == 499_500_000_000, "tmDestination: QuotaGB real 499.5")
                #expect(d.mountPoint == nil, "tmDestination: no MountPoint ⇒ nil")
            } else { Issue.record("tmDestination: real quota ⇒ configured") }
            let noQuota = tmPlist("<key>Destinations</key><array>\(entry("<key>Name</key><string>X</string>"))</array>")
            if case .configured(let d) = Parsers.tmDestination(plist: noQuota) {
                #expect(d.quotaBytes == nil, "tmDestination: no QuotaGB ⇒ quotaBytes nil")
            } else { Issue.record("tmDestination: no quota ⇒ configured") }

            #expect(Parsers.tmDestination(plist: tmPlist("<key>Destinations</key><array/>")) == .notConfigured, "tmDestination: empty array ⇒ notConfigured")
            #expect(Parsers.tmDestination(plist: tmPlist("")) == .notConfigured, "tmDestination: no Destinations key ⇒ notConfigured")
            #expect(Parsers.tmDestination(plist: Data("No destinations configured.".utf8)) == .notConfigured, "tmDestination: text sentence ⇒ notConfigured")
            #expect(Parsers.tmDestination(plist: tmPlist("<key>Destinations</key><array>\(entry("<key>ID</key><string>Z</string>"))</array>")) == .undecodable,
                  "tmDestination: entry without the four keys ⇒ undecodable")
            #expect(Parsers.tmDestination(plist: Data("garbage".utf8)) == .undecodable, "tmDestination: garbage ⇒ undecodable")
            #expect(Parsers.tmDestination(plist: Data()) == .undecodable, "tmDestination: empty ⇒ undecodable")
            #expect(Parsers.tmDestination(plist: two.prefix(two.count / 2)) == .undecodable, "tmDestination: truncated ⇒ undecodable")
            #expect(Parsers.tmDestination(plist: tmPlist("<key>Destinations</key><array>\(entry("<key>Name</key><integer>5</integer>"))</array>")) == .undecodable,
                  "tmDestination: Name as integer ⇒ undecodable")
        }
    }

    @Test func purgeableBytes() async {
        // =====================================================================
        // MARK: - LiveCollector.purgeableBytes
        // =====================================================================

        do {
            #expect(LiveCollector.purgeableBytes(importantAvailable: 500_000_000_000, available: 420_000_000_000) == 80_000_000_000,
                  "purgeableBytes: importantAvailable - available")
            #expect(LiveCollector.purgeableBytes(importantAvailable: nil, available: 420_000_000_000) == nil,
                  "purgeableBytes: nil importantAvailable -> nil")
            #expect(LiveCollector.purgeableBytes(importantAvailable: 500_000_000_000, available: nil) == nil,
                  "purgeableBytes: nil available -> nil")
            #expect(LiveCollector.purgeableBytes(importantAvailable: 420_000_000_000, available: 420_000_000_000) == nil,
                  "purgeableBytes: equal inputs -> nil, not 0")
            #expect(LiveCollector.purgeableBytes(importantAvailable: 400_000_000_000, available: 420_000_000_000) == nil,
                  "purgeableBytes: important < available (nonsense reading) -> nil, never negative")
        }
    }

    @Test func decodeSpaceUsed() async {
        func buf(vol: UInt32, used: Int64, count: Int = 32) -> [UInt8] {
            var b = [UInt8](repeating: 0, count: 32)
            withUnsafeBytes(of: vol.littleEndian) { b.replaceSubrange(8..<12, with: $0) }
            withUnsafeBytes(of: used.littleEndian) { b.replaceSubrange(24..<32, with: $0) }
            return Array(b.prefix(count))
        }
        let bit = UInt32(ATTR_VOL_SPACEUSED)
        #expect(LiveCollector.decodeSpaceUsed(buf(vol: bit | UInt32(ATTR_VOL_INFO), used: 13_654_294_528)) == 13_654_294_528, "valid buffer")
        #expect(LiveCollector.decodeSpaceUsed(buf(vol: UInt32(ATTR_VOL_INFO), used: 5)) == nil, "SPACEUSED bit missing -> nil")
        #expect(LiveCollector.decodeSpaceUsed(buf(vol: bit, used: 5, count: 31)) == nil, "short buffer -> nil")
        #expect(LiveCollector.decodeSpaceUsed(buf(vol: bit, used: -1)) == nil, "negative value -> nil")
    }

    @Test func dataUsedExcludingPurgeable() async {
        #expect(LiveCollector.dataUsedExcludingPurgeable(raw: 100, purgeable: 30) == 70, "raw minus purgeable")
        #expect(LiveCollector.dataUsedExcludingPurgeable(raw: 100, purgeable: nil) == 100, "purgeable nil -> raw")
        #expect(LiveCollector.dataUsedExcludingPurgeable(raw: 100, purgeable: 150) == 0, "purgeable > raw clamps at 0")
        #expect(LiveCollector.dataUsedExcludingPurgeable(raw: nil, purgeable: 30) == nil, "nil raw -> nil")
    }

    @Test func localSnapshotNames() async {
        // =====================================================================
        // MARK: - ReportCollector.localSnapshotNames
        // =====================================================================

        do {
            let realistic = "Snapshots for volume group containing disk /:\n com.apple.TimeMachine.2026-09-06-101010.local\n com.apple.TimeMachine.2026-09-07-020304.local"
            let names = ReportCollector.localSnapshotNames(realistic)
            #expect(names.count == 2, "localSnapshotNames: realistic fixture -> 2 names")
            #expect(names.first == "com.apple.TimeMachine.2026-09-06-101010.local",
                  "localSnapshotNames: leading whitespace trimmed")
            #expect(names.allSatisfy { $0.hasPrefix("com.apple.TimeMachine.") },
                  "localSnapshotNames: every name has the TimeMachine prefix")
            #expect(ReportCollector.localSnapshotNames("") == [], "localSnapshotNames: empty output -> []")
            #expect(ReportCollector.localSnapshotNames("Snapshots for volume group containing disk /:") == [],
                  "localSnapshotNames: header-only output -> []")
            #expect(ReportCollector.localSnapshotNames("Snapshots for volume group containing disk /:\n com.apple.something.else") == [],
                  "localSnapshotNames: unrelated line dropped")
        }
    }

    @Test func diskutilSmart() async {
        // =====================================================================
        // MARK: - Parsers.diskutilSmart
        // =====================================================================

        do {
            func duPlist(_ body: String) -> Data {
                Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\(body)</dict></plist>".utf8)
            }
            let r = Parsers.diskutilSmart(plist: duPlist("<key>SMARTStatus</key><string>Verified</string><key>MediaName</key><string>APPLE SSD</string>"))
            #expect(r.status == "Verified" && r.mediaName == "APPLE SSD", "diskutilSmart: Verified + media name")
            let r2 = Parsers.diskutilSmart(plist: duPlist("<key>SMARTStatus</key><string>Not Supported</string><key>MediaName</key><string>External HDD</string>"))
            #expect(r2.status == "Not Supported" && r2.mediaName == "External HDD", "diskutilSmart: Not Supported variant")
            let r3 = Parsers.diskutilSmart(plist: Data("garbage".utf8))
            #expect(r3.status == nil && r3.mediaName == nil, "diskutilSmart: garbage ⇒ (nil, nil)")
            let r4 = Parsers.diskutilSmart(plist: Data())
            #expect(r4.status == nil && r4.mediaName == nil, "diskutilSmart: empty ⇒ (nil, nil)")

            let two = duPlist("<key>WholeDisks</key><array><string>disk4</string><string>disk6</string></array>")
            #expect(Parsers.externalPhysicalDisks(plist: two) == ["/dev/disk4", "/dev/disk6"], "externalPhysicalDisks: two disks")
            #expect(Parsers.externalPhysicalDisks(plist: duPlist("<key>WholeDisks</key><array/>")).isEmpty, "externalPhysicalDisks: empty array ⇒ []")
            #expect(Parsers.externalPhysicalDisks(plist: Data("garbage".utf8)).isEmpty, "externalPhysicalDisks: garbage ⇒ []")
            #expect(Parsers.externalPhysicalDisks(plist: two.prefix(two.count / 2)).isEmpty, "externalPhysicalDisks: truncated ⇒ []")
        }
    }

    @Test func smartctlAttrs() async {
        // =====================================================================
        // MARK: - Parsers.smartctlAttrs
        // =====================================================================

        do {
            func nvme(_ log: String) -> Data { Data("{\"nvme_smart_health_information_log\":{\(log)}}".utf8) }
            let full = nvme("\"percentage_used\":0,\"critical_warning\":0,\"power_on_hours\":1234,\"temperature\":39,"
                + "\"media_errors\":0,\"available_spare\":100,\"num_err_log_entries\":0,\"power_cycles\":120,\"unsafe_shutdowns\":3")
            let attrs = Parsers.smartctlAttrs(json: full)
            let expectedOrder = ["Critical Warning", "Temperature", "Available Spare", "Percentage Used",
                                  "Power Cycles", "Power On Hours", "Unsafe Shutdowns",
                                  "Media and Data Integrity Errors", "Error Information Log Entries"]
            #expect(attrs.map { $0.0 } == expectedOrder, "smartctlAttrs: canonical order regardless of source order")
            #expect(attrs.map { $0.1 } == ["0x00", "39 Celsius", "100%", "0%", "120", "1,234", "3", "0", "0"],
                  "smartctlAttrs: exact value strings")
            func value(_ log: String, _ label: String) -> String? {
                Parsers.smartctlAttrs(json: nvme(log)).first { $0.0 == label }?.1
            }
            #expect(value("\"critical_warning\":4", "Critical Warning") == "0x04", "smartctlAttrs: critical_warning 4 ⇒ 0x04")
            #expect(value("\"power_on_hours\":1234567", "Power On Hours") == "1,234,567", "smartctlAttrs: 1234567 grouped")
            #expect(value("\"power_on_hours\":999", "Power On Hours") == "999", "smartctlAttrs: 999 ungrouped")
            #expect(value("\"power_on_hours\":1000", "Power On Hours") == "1,000", "smartctlAttrs: 1000 grouped")
            #expect(value("\"critical_warning\":0", "Temperature") == "-", "smartctlAttrs: log without temperature ⇒ '-'")
            #expect(Parsers.smartctlAttrs(json: Data("{\"ata_smart_attributes\":{\"table\":[]}}".utf8)).isEmpty, "smartctlAttrs: ATA-shaped JSON ⇒ []")
            #expect(Parsers.smartctlAttrs(json: nvme("\"power_on_hours\":\"824\"")).isEmpty, "smartctlAttrs: string power_on_hours ⇒ []")
            #expect(Parsers.smartctlAttrs(json: Data()).isEmpty, "smartctlAttrs: empty ⇒ []")
            #expect(Parsers.smartctlAttrs(json: Data("garbage".utf8)).isEmpty, "smartctlAttrs: garbage ⇒ []")
            #expect(Parsers.smartctlAttrs(json: full.prefix(full.count / 2)).isEmpty, "smartctlAttrs: truncated ⇒ []")
        }
    }

    @Test func smartctlHealth() async {
        func nvme(_ log: String) -> Data { Data("{\"nvme_smart_health_information_log\":{\(log)}}".utf8) }
        let base = "\"percentage_used\":4,\"critical_warning\":0,\"power_on_hours\":1234,\"temperature\":39,"
            + "\"media_errors\":0,\"available_spare\":100,\"num_err_log_entries\":0,\"power_cycles\":120,\"unsafe_shutdowns\":3"
        let h = Parsers.smartctlHealth(json: nvme(base))
        #expect(h?.temperatureC == 39 && h?.percentageUsed == 4, "smartctlHealth: temperature/percentage match smartctlAttrs")
        #expect(h?.powerOnHours == 1234 && h?.powerCycles == 120 && h?.unsafeShutdowns == 3 && h?.availableSpare == 100,
              "smartctlHealth: counters")
        #expect(h?.spareThreshold == nil && h?.dataUnitsRead == nil, "smartctlHealth: absent keys are nil")
        let full = Parsers.smartctlHealth(json: nvme(base + ",\"available_spare_threshold\":10,\"data_units_read\":74609375,\"data_units_written\":1000"))
        #expect(full?.spareThreshold == 10 && full?.dataUnitsRead == 74_609_375 && full?.dataUnitsWritten == 1000,
              "smartctlHealth: threshold and data units")
        #expect(Parsers.smartctlHealth(json: Data("{\"ata_smart_attributes\":{\"table\":[]}}".utf8)) == nil, "smartctlHealth: ATA JSON ⇒ nil")
        #expect(Parsers.smartctlHealth(json: Data("garbage".utf8)) == nil, "smartctlHealth: garbage ⇒ nil")
    }

    @Test func launchctlNonApple() async {
        // =====================================================================
        // MARK: - Parsers.launchctlNonApple
        // =====================================================================

        do {
            let fixture = """
            PID\tStatus\tLabel
            111\t0\tcom.apple.foo
            222\t0\tapplication.ru.keepcoder.Telegram.5282392.5283387
            333\t0\tcom.rdskcm.mac-checkup
            """
            let items = Parsers.launchctlNonApple(fixture)
            let labels = Set(items.map { $0.label })
            #expect(!labels.contains("com.apple.foo"), "launchctlNonApple: com.apple.* excluded")
            #expect(labels.contains("ru.keepcoder.Telegram"), "launchctlNonApple: application. prefix + instance-id suffix stripped")
            #expect(labels.contains("com.rdskcm.mac-checkup"), "launchctlNonApple: plain non-Apple label kept")
            #expect(items.count == 2, "launchctlNonApple: header row skipped, deduped result (got \(items.count))")
        }
    }

    @Test func pmsetCustom() async {
        // =====================================================================
        // MARK: - Parsers.pmsetCustom
        // =====================================================================

        do {
            let fixture = "Battery Power:\n Sleep On Power Button 1\n displaysleep 10\nAC Power:\n displaysleep 20"
            let energy = Parsers.pmsetCustom(fixture)
            #expect(energy.battery.contains { $0.0 == "Sleep On Power Button" && $0.1 == "1" },
                  "pmsetCustom: multi-word key parsed")
            #expect(energy.battery.contains { $0.0 == "displaysleep" && $0.1 == "10" }, "pmsetCustom: battery displaysleep 10")
            #expect(energy.ac.contains { $0.0 == "displaysleep" && $0.1 == "20" }, "pmsetCustom: ac displaysleep 20")
        }
    }

    @Test func loginItems() async {
        // =====================================================================
        // MARK: - Parsers.loginItems
        // =====================================================================

        #expect(Parsers.loginItems("Stats, Foo") == ["Stats", "Foo"], "loginItems: comma-separated list")
        #expect(Parsers.loginItems("(error, no automation permission)") == nil, "loginItems: AppleScript error ⇒ nil")
        #expect(Parsers.loginItems("") == [], "loginItems: empty ⇒ []")
    }

    @Test func securityStatus() async {
        // =====================================================================
        // MARK: - Parsers security status fixtures
        // =====================================================================

        #expect(Parsers.fileVaultStatus("FileVault is On.") == true, "fileVaultStatus: On")
        #expect(Parsers.fileVaultStatus("FileVault is Off.") == false, "fileVaultStatus: Off")
        #expect(Parsers.gatekeeperStatus("assessments enabled") == true, "gatekeeperStatus: enabled")
        #expect(Parsers.gatekeeperStatus("assessments disabled") == false, "gatekeeperStatus: disabled")
        #expect(Parsers.sipStatus("System Integrity Protection status: enabled.") == true, "sipStatus: enabled")
        #expect(Parsers.sipStatus("System Integrity Protection status: disabled.") == false, "sipStatus: disabled")
        #expect(Parsers.firewallStatus("Firewall is enabled. (State = 1)") == true, "firewallStatus: prose enabled")
        #expect(Parsers.firewallStatus("Firewall is disabled. (State = 0)") == false, "firewallStatus: prose disabled")
        #expect(Parsers.firewallStatus("1") == true, "firewallStatus: numeric 1 ⇒ true")
        #expect(Parsers.firewallStatus("2") == true, "firewallStatus: numeric 2 ⇒ true")
    }

    /// Opt-in (R8): MACDASH_LIVE=1 swift test --filter liveCanaryUptime
    /// `/usr/bin/uptime` through `Parsers.uptimeSeconds` against `sysctl kern.boottime`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
    func liveCanaryUptime() async {
        let outcome = await runCommand("/usr/bin/uptime", [], timeout: 10)
        let stdout = outcome.nonEmptyText ?? ""
        let parsed = Parsers.uptimeSeconds(stdout)
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        let rc = sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        let boot = Date().timeIntervalSince(Date(timeIntervalSince1970: Double(tv.tv_sec)))
        let line = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        print("liveCanaryUptime raw=\(line) parsed=\(String(describing: parsed)) boottime=\(Int(boot))")
        #expect(rc == 0, "liveCanaryUptime: sysctl kern.boottime read")
        #expect(parsed != nil, "liveCanaryUptime: uptime output parses")
        if let parsed {
            // uptime(1) prints whole minutes, so allow a minute of rounding plus run latency.
            #expect(abs(Double(parsed) - boot) < 120, "liveCanaryUptime: parsed \(parsed) s vs kern.boottime \(Int(boot)) s")
        }
    }

    /// Opt-in (R8): MACDASH_LIVE=1 swift test --filter liveCanaryBatteryState
    /// IOKit (`LiveCollector.collectFast`) against `Parsers.batteryPmset` over real `pmset -g batt` output.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
    func liveCanaryBatteryState() async {
        let live = LiveCollector().collectFast().battery
        let outcome = await runCommand("/usr/bin/pmset", ["-g", "batt"], timeout: 10)
        let pm = Parsers.batteryPmset(outcome.nonEmptyText ?? "")
        print("liveCanaryBatteryState iokit source=\(String(describing: live?.source)) charge=\(String(describing: live?.charge)) state=\(String(describing: live?.state))")
        print("liveCanaryBatteryState pmset source=\(String(describing: pm?.source)) charge=\(String(describing: pm?.charge)) state=\(String(describing: pm?.state))")
        guard live != nil else {
            #expect(pm == nil, "liveCanaryBatteryState: desktop, pmset reports no battery either")
            return
        }
        #expect(live?.source == pm?.source, "liveCanaryBatteryState: power source matches")
        #expect(live?.state != nil && pm?.state != nil, "liveCanaryBatteryState: both read a state")
        func looseState(_ s: BatteryChargeState?) -> Bool {
            switch s {
            case .other, .finishingCharge, .charged: return true   // IOKit has no "finishing charge" and says .charged at 100 %
            default: return false
            }
        }
        if looseState(live?.state) || looseState(pm?.state) {
            print("liveCanaryBatteryState: states may legitimately differ here (other / finishing charge / charged)")
        } else {
            #expect(live?.state == pm?.state, "liveCanaryBatteryState: charge state matches")
        }
    }
}

/// The one test in this file that flips the process-wide UI language stays in the serialized suite.
extension SerialTests {
    struct ParsersSerialTests {
        @Test func tmBackupUnavailableReason() async {
            // =====================================================================
            // MARK: - TMBackupUnavailableReason
            // =====================================================================

            do {
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }

                let cases: [TMBackupUnavailableReason] = [.noBackupsYet, .diskNotConnected,
                                                          .noCompletedBackups, .dateUnavailableNoFDA]
                for lang in AppLanguage.allCases {
                    L10nStore.shared.language = lang
                    let texts = cases.map(\.localizedText)
                    #expect(texts.allSatisfy { !$0.isEmpty }, "TMBackupUnavailableReason \(lang): every case has text")
                    #expect(Set(texts).count == cases.count, "TMBackupUnavailableReason \(lang): texts are distinct")
                }

                // The regression this replaces: the reason used to be a stored localized string, so a
                // language switch broke the card's `== no-FDA` comparison. The case is language-free.
                var dest = TMDestination()
                L10nStore.shared.language = .ru
                dest.lastBackupUnavailableReason = .dateUnavailableNoFDA
                let ruText = dest.lastBackupUnavailableReason?.localizedText
                L10nStore.shared.language = .en
                #expect(ruText == StringsRU().reportCollectorDateUnavailableNoFDA,
                      "TMBackupUnavailableReason: stored case renders the RU sentence under .ru")
                #expect(dest.lastBackupUnavailableReason?.localizedText == StringsEN().reportCollectorDateUnavailableNoFDA,
                      "TMBackupUnavailableReason: the same stored case renders the EN sentence after a switch to .en")
            }
        }
    }
}
