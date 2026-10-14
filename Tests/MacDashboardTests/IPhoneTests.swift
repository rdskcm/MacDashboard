// Tests/MacDashboardTests/IPhoneTests.swift
// Port of Checks/IPhoneChecks.swift (CHECKS-SWIFT-TESTING).
// IPHONE-MODULE Stage 1: the pure iPhone helpers (IPhoneData.swift, symlinked) and the
// BatteryInspector.parse(dict:) split. The transport (private framework) is app-only and
// not covered here. The store checks write ONLY into a fresh temp directory.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct IPhoneTests {
        @Test func iPhone() async {
            // --- precise health / watt-hours ---
            #expect(abs((IPhoneData.preciseHealth(maxMAh: 4917, designMAh: 5030) ?? 0) - 97.753) < 0.001,
                  "iPhone: preciseHealth 4917/5030 is 97.753")
            #expect(IPhoneData.preciseHealth(maxMAh: 4917, designMAh: 0) == nil, "iPhone: preciseHealth with zero design is nil")
            #expect(abs(IPhoneData.wattHours(mAh: 5030) - 19.516) < 0.001, "iPhone: wattHours 5030 mAh is 19.516")
            #expect(abs(IPhoneData.wattHours(mAh: 4917) - 19.078) < 0.001, "iPhone: wattHours 4917 mAh is 19.078")

            // --- deviceKey ---
            let udid = "00008140-001A2B3C4D5E6F78"
            let key = IPhoneData.deviceKey(udid: udid)
            #expect(key == IPhoneData.deviceKey(udid: udid), "iPhone: deviceKey is deterministic")
            #expect(key.count == 16 && key.allSatisfy { "0123456789abcdef".contains($0) },
                  "iPhone: deviceKey is 16 lowercase hex chars (\(key))")
            #expect(!key.contains(udid) && !udid.lowercased().contains(key), "iPhone: deviceKey does not contain the input")
            #expect(key != IPhoneData.deviceKey(udid: udid + "0"), "iPhone: different inputs give different keys")

            // --- mask ---
            #expect(IPhoneData.mask("D7LABCDE4PYM") == "D7L•••4PYM", "iPhone: mask 12 chars -> first 3 + ••• + last 4")
            #expect(IPhoneData.mask("ABCDEFGH") == "ABC•••EFGH", "iPhone: mask 8 chars is the shortest unmasked-edge form")
            #expect(IPhoneData.mask("ABCDEFG") == "•••••••", "iPhone: mask 7 chars -> 7 bullets")
            #expect(IPhoneData.mask("") == "", "iPhone: mask empty -> empty")

            // --- bugType / hasJSONHeader ---
            func d(_ s: String) -> Data { Data(s.utf8) }
            #expect(IPhoneData.bugType(fromHeader: d("{\"bug_type\":\"309\",\"x\":1}\nbody")) == "309", "iPhone: bugType string 309")
            #expect(IPhoneData.bugType(fromHeader: d("{\"bug_type\":298}\n")) == "298", "iPhone: bugType numeric 298")
            #expect(IPhoneData.bugType(fromHeader: d("{\"bug_type\":\"309\"}")) == nil, "iPhone: bugType without newline -> nil")
            #expect(IPhoneData.bugType(fromHeader: d("garbage\n")) == nil, "iPhone: bugType non-JSON -> nil")
            #expect(IPhoneData.bugType(fromHeader: d("[1,2]\n")) == nil, "iPhone: bugType JSON array -> nil")
            #expect(IPhoneData.bugType(fromHeader: d("{\"a\":1}\n")) == nil && IPhoneData.hasJSONHeader(d("{\"a\":1}\n")),
                  "iPhone: JSON without bug_type -> nil, hasJSONHeader true")
            #expect(!IPhoneData.hasJSONHeader(d("garbage\n")) && !IPhoneData.hasJSONHeader(d("{\"a\":1}")),
                  "iPhone: hasJSONHeader false for non-JSON and for no newline")

            // --- category ---
            let table: [(String, LogCategory)] = [
                ("309", .appCrash), ("308", .exceptionFault), ("298", .jetsam), ("145", .diskWrites),
                ("202", .cpuResource), ("288", .stackshot),
                ("226", .analytics), ("237", .analytics), ("225", .analytics), ("233", .analytics),
                ("211", .analytics), ("303", .analytics),
                ("999", .otherReport),
            ]
            for (bt, expected) in table {
                #expect(IPhoneData.category(bugType: bt) == expected, "iPhone: category bug_type \(bt) -> \(expected)")
            }
            #expect(IPhoneData.category(bugType: nil) == .other, "iPhone: category nil -> other")
            #expect(LogCategory.allCases == [.appCrash, .exceptionFault, .jetsam, .diskWrites, .cpuResource,
                                           .stackshot, .otherReport, .analytics, .other],
                  "iPhone: LogCategory.allCases is the display order")

            // --- AFC mtime ---
            let t = IPhoneData.date(fromAFCMtime: "1791704227000000000")
            #expect(t?.timeIntervalSince1970 == 1791704227, "iPhone: AFC mtime ns -> Unix 1791704227")
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let c = t.map { utc.dateComponents([.year, .month, .day], from: $0) }
            #expect(c?.year == 2026 && c?.month == 10 && c?.day == 11, "iPhone: AFC mtime lands on 2026-10-11")
            #expect(IPhoneData.date(fromAFCMtime: "x") == nil, "iPhone: AFC mtime non-numeric -> nil")

            // --- battery history ---
            func pt(_ day: String, _ source: String, cycles: Int = 1) -> BatteryPoint {
                BatteryPoint(day: day, cycles: cycles, healthPercent: 98, maxCapacityMAh: 4933,
                             designCapacityMAh: 5030, source: source)
            }
            let live = IPhoneData.upsertLive([pt("2026-10-10", "import", cycles: 5), pt("2026-10-12", "live")],
                                             pt("2026-10-10", "live", cycles: 9))
            #expect(live.count == 2 && live[0].source == "live" && live[0].cycles == 9, "iPhone: upsertLive replaces an import on the same day")
            #expect(live.map(\.day) == ["2026-10-10", "2026-10-12"], "iPhone: upsertLive result is sorted by day")
            let live2 = IPhoneData.upsertLive(live, pt("2026-10-10", "live", cycles: 11))
            #expect(live2.count == 2 && live2[0].cycles == 11, "iPhone: second live read on the same day replaces the first")
            let merged = IPhoneData.mergeImported([pt("2026-10-10", "live", cycles: 9), pt("2026-10-09", "import", cycles: 3)],
                                                  [pt("2026-10-10", "import", cycles: 1), pt("2026-10-09", "import", cycles: 4),
                                                   pt("2026-10-01", "import", cycles: 2)])
            #expect(merged.first(where: { $0.day == "2026-10-10" })?.source == "live" &&
                  merged.first(where: { $0.day == "2026-10-10" })?.cycles == 9,
                  "iPhone: mergeImported does not replace a live point")
            #expect(merged.first(where: { $0.day == "2026-10-09" })?.cycles == 4, "iPhone: mergeImported newer import replaces older import")
            #expect(merged.map(\.day) == ["2026-10-01", "2026-10-09", "2026-10-10"], "iPhone: mergeImported result is sorted by day")

            // --- relay requests ---
            func eq(_ a: [String: Any], _ b: [String: String]) -> Bool { (a as? [String: String]) == b }
            #expect(eq(IPhoneData.relayMessage(.ioRegistryName("AppleSmartBattery")),
                     ["Request": "IORegistry", "EntryName": "AppleSmartBattery"]), "iPhone: relayMessage ioRegistryName shape")
            #expect(eq(IPhoneData.relayMessage(.ioRegistryClass("IOPMPowerSource")),
                     ["Request": "IORegistry", "EntryClass": "IOPMPowerSource"]), "iPhone: relayMessage ioRegistryClass shape")
            #expect(eq(IPhoneData.relayMessage(.goodbye), ["Request": "Goodbye"]), "iPhone: relayMessage goodbye shape")
            let ok: [String: Any] = ["Status": "Success", "Diagnostics": ["IORegistry": ["CycleCount": 268]]]
            #expect(IPhoneData.relayPayload(ok)?["CycleCount"] as? Int == 268, "iPhone: relayPayload returns the IORegistry dict on Success")
            #expect(IPhoneData.relayPayload(["Status": "Failure", "Diagnostics": ["IORegistry": ["a": 1]]]) == nil &&
                  IPhoneData.relayPayload(nil) == nil &&
                  IPhoneData.relayPayload(["Status": "Success", "Diagnostics": ["IORegistry": [String: Any]()]]) == nil,
                  "iPhone: relayPayload is nil for failure, missing reply and empty payload")

            // --- findValue / stringValue ---
            let nested: [String: Any] = ["a": ["b": ["Target": "found"]], "top": 1]
            #expect(IPhoneData.findValue("Target", in: nested) as? String == "found", "iPhone: findValue finds a key at depth 2")
            #expect(IPhoneData.findValue("Target", in: nested, maxDepth: 1) == nil, "iPhone: findValue respects maxDepth")
            #expect(IPhoneData.findValue("top", in: nested) as? Int == 1, "iPhone: findValue finds a top-level key")
            #expect(IPhoneData.stringValue(Data("ABC123\0".utf8)) == "ABC123", "iPhone: stringValue trims Data with a trailing NUL")
            #expect(IPhoneData.stringValue("  x \n") == "x", "iPhone: stringValue trims a String")
            #expect(IPhoneData.stringValue(42) == nil && IPhoneData.stringValue("  ") == nil && IPhoneData.stringValue(nil) == nil,
                  "iPhone: stringValue Int / blank / nil -> nil")

            // --- colour table ships empty (Needs-decision 1) ---
            #expect(IPhoneData.enclosureRGB(productType: "iPhone18,2", code: "2") == nil, "iPhone: enclosureRGB has no entry -> nil (neutral picture)")

            // --- BatteryInspector.parse(dict:) on an iPhone-shaped reply ---
            let fixture: [String: Any] = ["CycleCount": 268, "DesignCapacity": 5030, "AppleRawMaxCapacity": 4933,
                                          "CurrentCapacity": 80, "Temperature": 3089, "Voltage": 4234,
                                          "IsCharging": false, "ExternalConnected": true]
            let b = BatteryInspector.parse(dict: fixture)
            #expect(b.healthPercent == 98, "iPhone: parse(dict:) health 98% (got \(String(describing: b.healthPercent)))")
            #expect(b.cycleCount == 268 && b.percent == 80 && b.voltageMV == 4234, "iPhone: parse(dict:) cycles, charge, voltage")
            #expect(b.temperatureC == 30.89, "iPhone: parse(dict:) temperature 30.89 C")
            #expect(b.externalConnected && !b.isCharging && b.maxCapacityMAh == 4933 && b.designCapacityMAh == 5030,
                  "iPhone: parse(dict:) power state and capacities")

            // iOS 26.x shape: top-level AppleRawMaxCapacity wins even when BatteryData carries
            // NominalChargeCapacity (Nominal would give 97; Apple's Settings shows 98).
            let shape26: [String: Any] = ["CycleCount": 269, "CurrentCapacity": 79, "AppleRawMaxCapacity": 4915,
                                          "DesignCapacity": 5030,
                                          "BatteryData": ["DesignCapacity": 5030, "NominalChargeCapacity": 4865] as [String: Any]]
            let b26 = BatteryInspector.parse(dict: shape26)
            #expect(b26.healthPercent == 98 && b26.maxCapacityMAh == 4915 && b26.designCapacityMAh == 5030,
                  "iPhone: parse(dict:) 26.x shape keeps the AppleRawMaxCapacity basis (got \(String(describing: b26.healthPercent)))")

            // iOS 27.0 shape: no top-level capacities, no children; capacities in BatteryData.
            let shape27: [String: Any] = ["CycleCount": 666, "CurrentCapacity": 86, "MaxCapacity": 100,
                                          "BatteryData": ["DesignCapacity": 4395, "FullChargeCapacity": 3771,
                                                          "NominalChargeCapacity": 3732, "AbsoluteCapacity": 3282,
                                                          "RemainingCapacity": 3222, "CurrentCapacity": 86,
                                                          "MaxCapacity": 100] as [String: Any]]
            let b27 = BatteryInspector.parse(dict: shape27)
            #expect(b27.healthPercent == 86 && b27.maxCapacityMAh == 3771,
                  "iPhone: parse(dict:) iOS 27 health 86% from FullChargeCapacity 3771/4395 (got \(String(describing: b27.healthPercent)))")
            #expect(b27.designCapacityMAh == 4395 && b27.cycleCount == 666 && b27.percent == 86,
                  "iPhone: parse(dict:) iOS 27 design capacity, cycles, charge")
            #expect(b27.currentCapacityMAh == nil,
                  "iPhone: parse(dict:) iOS 27 RemainingCapacity is not mapped")

            // iOS 27.0 without FullChargeCapacity: health falls back to NominalChargeCapacity.
            let b27nominal = BatteryInspector.parse(dict: ["BatteryData": ["DesignCapacity": 4395, "NominalChargeCapacity": 3732] as [String: Any]])
            #expect(b27nominal.healthPercent == 85 && b27nominal.maxCapacityMAh == nil,
                  "iPhone: parse(dict:) iOS 27 without FullChargeCapacity -> Nominal basis 85%")

            // Nothing to compute from: no crash, nil health and capacities.
            let none = [BatteryInspector.parse(dict: [:]),
                        BatteryInspector.parse(dict: ["CycleCount": 5, "BatteryData": "x"]),
                        BatteryInspector.parse(dict: ["BatteryData": ["NominalChargeCapacity": 3732, "DesignCapacity": 0] as [String: Any]]),
                        BatteryInspector.parse(dict: ["BatteryData": ["NominalChargeCapacity": 3732] as [String: Any]])]
            #expect(none.allSatisfy { $0.healthPercent == nil && $0.maxCapacityMAh == nil },
                  "iPhone: parse(dict:) without usable capacities -> nil health, no crash")
            #expect(none[0].designCapacityMAh == nil && none[0].cycleCount == nil && none[1].cycleCount == 5,
                  "iPhone: parse(dict:) empty dict -> nil fields; non-dict BatteryData ignored")

            // --- IPhoneStore (temp dir only) ---
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("iphone-checks-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tmp) }
            let url = tmp.appendingPathComponent("iphones.json")
            let store = IPhoneStore(url: url)
            #expect(store.load().isEmpty, "iPhone: store missing file -> []")
            let r1 = IPhoneDeviceRecord(id: key, name: "Test Phone", marketingName: "iPhone 17 Pro Max",
                                        productType: "iPhone18,2", enclosureColor: "2", osVersion: "27.0",
                                        lastSeen: Date(timeIntervalSince1970: 1791704227),
                                        battery: [pt("2026-10-11", "live")], keptArchives: ["a.tar.gz"])
            let r2 = IPhoneDeviceRecord(id: IPhoneData.deviceKey(udid: "other"), name: "Second", marketingName: nil,
                                        productType: nil, enclosureColor: nil, osVersion: nil,
                                        lastSeen: Date(timeIntervalSince1970: 1700000000), battery: [], keptArchives: [])
            do {
                try store.save([r1, r2])
                let back = IPhoneStore(url: url).load()
                #expect(back == [r1, r2], "iPhone: store save + load round-trips two records")
                let mode = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
                #expect(mode == 0o600, "iPhone: store file mode is 0600 (got \(String(describing: mode)))")
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                #expect(!text.contains(udid), "iPhone: store file does not contain the UDID")
            } catch {
                Issue.record("iPhone: store save threw \(error)")
            }

            // An unreadable file is read as [] and renamed aside (bytes intact) by the next save.
            let badURL = tmp.appendingPathComponent("bad").appendingPathComponent("iphones.json")
            try? FileManager.default.createDirectory(at: badURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("not json".utf8).write(to: badURL)
            let badStore = IPhoneStore(url: badURL)
            #expect(badStore.load().isEmpty && badStore.loadedUnreadableFile, "iPhone: store unreadable file -> [] and flagged")
            do {
                try badStore.save([r1])
                let names = (try? FileManager.default.contentsOfDirectory(atPath: badURL.deletingLastPathComponent().path)) ?? []
                let aside = names.first { $0.hasPrefix("iphones.json.unreadable-") }
                let asideBytes = aside.flatMap { try? Data(contentsOf: badURL.deletingLastPathComponent().appendingPathComponent($0)) }
                #expect(asideBytes == Data("not json".utf8), "iPhone: store renames the unreadable file aside with its bytes intact")
                #expect(IPhoneStore(url: badURL).load() == [r1], "iPhone: store writes a valid file after setting the unreadable one aside")
            } catch {
                Issue.record("iPhone: store unreadable save threw \(error)")
            }

            // --- grouped (Stage 4) ---
            func le(_ path: String, _ cat: LogCategory, _ t: Double?) -> IPhoneLogEntry {
                IPhoneLogEntry(path: path, size: 1, modified: t.map { Date(timeIntervalSince1970: $0) },
                               bugType: nil, category: cat, source: .live)
            }
            let g = IPhoneData.grouped([le("/a", .other, 5), le("/b", .appCrash, 1), le("/c", .appCrash, 9),
                                        le("/d", .appCrash, nil), le("/e", .jetsam, 3)])
            #expect(g.map { $0.0 } == [.appCrash, .jetsam, .other], "iPhone: grouped keeps display order and drops empty categories")
            #expect(g.first?.1.map { $0.path } == ["/c", "/b", "/d"], "iPhone: grouped sorts newest first, nil dates last")
            #expect(IPhoneData.grouped([]).isEmpty, "iPhone: grouped of nothing is empty")
            let t0 = Date(timeIntervalSince1970: 1_700_000_000.5)
            #expect(IPhoneData.logCacheKey(path: "/x.ips", size: 42, modified: t0) == "/x.ips|42|1700000000500",
                  "iPhone: logCacheKey is path|size|mtime ms")
            #expect(IPhoneData.logCacheKey(path: "/x", size: 1, modified: nil) != IPhoneData.logCacheKey(path: "/x", size: 2, modified: nil),
                  "iPhone: logCacheKey changes with size")

            // --- sysdiagnose import (Stage 5) ---
            let hdr = "TimeStamp,WeightedRa,Qmax0,CycleCount,NominalChargeCapacity,TimeAtHighSoc,ChargingVoltage,BHServiceFlags,BHCalibrationFlags,MaxCapacityPercent"
            let bdc = [hdr,
                       "2026-07-16 09:00:00,58,5197,190,5015,ab12,4278,3,0,99",
                       "2026-07-16 17:43:43,58,5197,198,5015,ab12,4278,3,0,100",
                       "2026-06-18 17:42:09,57,5239,175,5062,ab12,4439,3,0,101",
                       "not-a-date,57,5239,175,5062,ab12,4439,3,0,98",
                       "2026-03-26 17:37:52,53,5272,117,5109,ab12,4054,8388611,0,0"].joined(separator: "\n") + "\n"
            let bdcOut = IPhoneData.parseBDCDaily(bdc)
            #expect(bdcOut.points.map(\.day) == ["2026-06-18", "2026-07-16"], "iPhone: BDC two days, sorted (\(bdcOut.points.map(\.day)))")
            #expect(bdcOut.skipped == 2, "iPhone: BDC malformed row and MaxCapacityPercent 0 row are skipped and counted (\(bdcOut.skipped))")
            #expect(bdcOut.points.last?.healthPercent == 100 && bdcOut.points.last?.cycles == 198, "iPhone: BDC keeps the last row of a day by timestamp")
            #expect(bdcOut.points.first?.healthPercent == 101, "iPhone: BDC stores 101 unclamped")
            #expect(bdcOut.points.allSatisfy { $0.source == "import" && $0.maxCapacityMAh == nil && $0.designCapacityMAh == nil },
                  "iPhone: BDC points are source import with no mAh")
            let bdcRev = IPhoneData.parseBDCDaily(([hdr,
                         "2026-07-16 17:43:43,58,5197,198,5015,ab12,4278,3,0,100",
                         "2026-07-16 09:00:00,58,5197,190,5015,ab12,4278,3,0,99"]).joined(separator: "\n"))
            #expect(bdcRev.points.first?.healthPercent == 100, "iPhone: BDC last-of-day is by timestamp, not file order")
            #expect(IPhoneData.parseBDCDaily("").points.isEmpty && IPhoneData.parseBDCDaily(hdr).points.isEmpty,
                  "iPhone: BDC empty input and header-only give no points")
            #expect(IPhoneData.parseBDCDaily("A,B\n1,2").points.isEmpty, "iPhone: BDC without the named columns gives no points")
            // --- archive identity (IPHONE-HISTORY-MIXUP) ---
            let onceHdr = "TimeStamp,DesignCapacity,Other"
            #expect(IPhoneData.parseBDCOnceDesignCapacities([onceHdr, "2026-09-16 21:25:58,4395,a"].joined(separator: "\n")) == [4395],
                  "iPhone: BDC_Once one row gives its design capacity")
            #expect(IPhoneData.parseBDCOnceDesignCapacities([onceHdr, "2026-03-26 17:37:52,5030,a", "2026-03-27 10:00:00,5030,a",
                                                           "x,0,a", "y,n/a,a", "z,4000"].joined(separator: "\n")) == [5030],
                  "iPhone: BDC_Once duplicates collapse; zero, non-numeric and short rows are ignored")
            #expect(IPhoneData.parseBDCOnceDesignCapacities("A,B\n1,2").isEmpty && IPhoneData.parseBDCOnceDesignCapacities("").isEmpty,
                  "iPhone: BDC_Once without the column or empty gives nothing")
            func bp(_ day: String, _ source: String, _ design: Int?) -> BatteryPoint {
                BatteryPoint(day: day, cycles: 1, healthPercent: 98, maxCapacityMAh: nil, designCapacityMAh: design, source: source)
            }
            func rec(_ id: String, _ marketing: String?, _ name: String, _ pts: [BatteryPoint]) -> IPhoneDeviceRecord {
                IPhoneDeviceRecord(id: id, name: name, marketingName: marketing, productType: nil, enclosureColor: nil,
                                   osVersion: nil, lastSeen: Date(timeIntervalSince1970: 1_700_000_000), battery: pts, keptArchives: [])
            }
            let r17 = rec("k17", "iPhone 17 Pro Max", "iPhone", [bp("2026-10-12", "live", 5030), bp("2026-10-01", "import", nil)])
            let r15 = rec("k15", "iPhone 15 Pro Max", "iPhone", [bp("2026-10-12", "live", 4395)])
            let rBare = rec("kb", nil, "Old phone", [bp("2026-10-01", "import", nil), bp("2026-10-02", "live", nil)])
            #expect(IPhoneData.designCapacity(of: r17) == 5030, "iPhone: designCapacity from the live point")
            #expect(IPhoneData.designCapacity(of: rec("x", nil, "x", [bp("2026-10-12", "live", 5030), bp("2026-10-10", "live", 4000)])) == 5030,
                  "iPhone: designCapacity takes the latest day, not the array order")
            #expect(IPhoneData.designCapacity(of: rBare) == nil, "iPhone: designCapacity nil without a stored value")
            #expect(IPhoneData.displayName(r17) == "iPhone 17 Pro Max" && IPhoneData.displayName(rBare) == "Old phone"
                  && IPhoneData.displayName(rec("e", "", "Named", [])) == "Named", "iPhone: displayName marketing name, else name")
            let all = [r17, r15, rBare]
            func ident(_ mAh: Set<Int>, _ key: String, _ devs: [IPhoneDeviceRecord]) -> ArchiveIdentity {
                IPhoneData.archiveIdentity(archiveName: "a.tar.gz", archiveMAh: mAh, deviceKey: key, devices: devs)
            }
            #expect(ident([5030], "k17", all) == .match, "iPhone: identity match")
            #expect(ident([4000, 5030], "k17", all) == .match, "iPhone: identity match when any archive capacity matches")
            #expect(ident([4395], "k17", all) == .mismatch(ImportIdentityQuestion(archiveName: "a.tar.gz", archiveMAh: [4395], deviceMAh: 5030,
                                                                            targetName: "iPhone 17 Pro Max", ownerName: "iPhone 15 Pro Max")),
                  "iPhone: identity mismatch names both phones")
            #expect(ident([5100, 4395], "k17", [r17, rBare]) == .mismatch(ImportIdentityQuestion(archiveName: "a.tar.gz", archiveMAh: [4395, 5100],
                                                                            deviceMAh: 5030, targetName: "iPhone 17 Pro Max", ownerName: nil)),
                  "iPhone: identity mismatch with no known owner; capacities sorted")
            let r15b = rec("k15b", "iPhone 15 Pro Max", "Second", [bp("2026-10-12", "live", 4395)])
            if case .mismatch(let q) = ident([4395], "k17", [r17, r15, r15b]) { #expect(q.ownerName == nil, "iPhone: identity two possible owners -> unnamed") }
            else { Issue.record("iPhone: identity two possible owners -> unnamed") }
            #expect(ident([], "k17", all) == .unknown, "iPhone: identity unknown when the archive has no capacity")
            #expect(ident([4395], "kb", all) == .unknown, "iPhone: identity unknown when the phone has no stored capacity")
            #expect(ident([4395], "missing", all) == .unknown, "iPhone: identity unknown without a record")
            #expect(StringsEN().iphoneImportConfirmTitle("a.tar.gz", into: "iPhone 17 Pro Max") == "Import “a.tar.gz” into iPhone 17 Pro Max",
                  "iPhone: EN confirm title names the phone")
            #expect(StringsRU().iphoneImportConfirmTitle("a.tar.gz", into: "iPhone 17 Pro Max") == "Импорт «a.tar.gz» в iPhone 17 Pro Max",
                  "iPhone: RU confirm title names the phone")
            let mEN = StringsEN().iphoneImportMismatchMessage(file: "a.tar.gz", owner: "iPhone 15 Pro Max", archiveMAh: [4395],
                                                              deviceMAh: 5030, target: "iPhone 17 Pro Max")
            #expect(mEN.contains("iPhone 15 Pro Max") && mEN.contains("iPhone 17 Pro Max") && mEN.contains("4395 mAh") && mEN.contains("5030 mAh"),
                  "iPhone: EN mismatch message names both phones and both capacities")
            #expect(StringsEN().iphoneImportMismatchMessage(file: "a", owner: nil, archiveMAh: [1], deviceMAh: 2, target: "T").contains("another iPhone")
                  && StringsRU().iphoneImportMismatchMessage(file: "a", owner: nil, archiveMAh: [1], deviceMAh: 2, target: "T").contains("другого iPhone"),
                  "iPhone: mismatch message without an owner says another iPhone")
            func af(_ path: String, dir: Bool = false, _ t: Double?) -> IPhoneAFCEntry {
                IPhoneAFCEntry(path: path, isDirectory: dir, size: 10, modified: t.map { Date(timeIntervalSince1970: $0) })
            }
            let arch = IPhoneData.sysdiagnoseArchives(in: [
                af("/DiagnosticLogs/sysdiagnose/a.tar.gz", 1), af("/DiagnosticLogs/sysdiagnose/b.tar.gz", 9),
                af("/DiagnosticLogs/sysdiagnose/c.log", 5), af("/DiagnosticLogs/sysdiagnose/d.tar.gz", dir: true, 7),
                af("/Retired/e.tar.gz", 8), af("/DiagnosticLogs/sysdiagnose/f.tar.gz", nil)])
            #expect(arch.map(\.path) == ["/DiagnosticLogs/sysdiagnose/b.tar.gz", "/DiagnosticLogs/sysdiagnose/a.tar.gz", "/DiagnosticLogs/sysdiagnose/f.tar.gz"],
                  "iPhone: sysdiagnoseArchives keeps regular .tar.gz files there, newest first")
            // Identity fields (fake values only)
            let idLock: [String: Any] = ["MarketingName": "iPhone 99", "ModelNumber": "MXXX1", "RegionInfo": "LL/A",
                                         "RegulatoryModelNumber": "A9999", "HardwareModel": "D99AP", "ProductVersion": "99.1",
                                         "BuildVersion": "99A1", "DeviceEnclosureColor": "2",
                                         "SerialNumber": "FAKESERIAL01", "MLBSerialNumber": "FAKEMLB0000000001",
                                         "InternationalMobileEquipmentIdentity": "000000000000001"]
            let idProduct: [String: Any] = ["coverglass-serial-number": Data("FAKECOVER001".utf8) + Data([0]),
                                            "nova-serial-num": Data("FAKENOVA".utf8)]
            let idCamera: [String: Any] = ["IOService": ["Props": ["BackCameraModuleSerialNumString": "FAKEBACKCAM1"]]]
            let idFields = IPhoneData.identityFields(lockdown: idLock, diskUsage: ["TotalDiskCapacity": 256_000_000_000 as Int64],
                                                     battery: ["BatteryData": ["Serial": "FAKEBATT"]], panel: ["Panel_ID": "FAKEPANEL"],
                                                     product: idProduct, camera: idCamera)
            let idByLabel = Dictionary(uniqueKeysWithValues: idFields.map { ($0.label, $0) })
            #expect(idByLabel[.modelNumber]?.value == "MXXX1 LL/A" && idByLabel[.ios]?.value == "99.1 (99A1)",
                  "iPhone: identity model number + region and iOS + build joined")
            #expect(idByLabel[.storage]?.value == fmtCapacity(256_000_000_000), "iPhone: identity storage uses fmtCapacity")
            #expect(idByLabel[.coverGlass]?.value == "FAKECOVER001" && idByLabel[.nova]?.value == "FAKENOVA",
                  "iPhone: identity Data-valued product keys decode (NUL dropped)")
            #expect(idByLabel[.backCamera]?.value == "FAKEBACKCAM1" && idByLabel[.battery]?.value == "FAKEBATT"
                  && idByLabel[.displayPanel]?.value == "FAKEPANEL", "iPhone: identity nested camera/battery/panel values found")
            #expect(idByLabel[.imei2] == nil && idByLabel[.frontCamera] == nil, "iPhone: identity missing values omit their field")
            #expect(idFields.map(\.label) == IdentityLabel.allCases.filter { idByLabel[$0] != nil }, "iPhone: identity order = allCases")
            #expect(idFields.allSatisfy { $0.isSecret == $0.label.isSecret } && idByLabel[.serial]?.isSecret == true
                  && idByLabel[.colorCode]?.isSecret == false, "iPhone: identity secret flag")
            #expect(IPhoneData.identityFields(lockdown: ["DeviceColor": "7"], diskUsage: nil, battery: nil, panel: nil,
                                            product: nil, camera: nil).map(\.value) == ["7"], "iPhone: identity colour falls back to DeviceColor")

            // --- history day helpers (IPHONE-REVIEW-LEFTOVERS) ---
            let dayNoon = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
            #expect(IPhoneData.historyDay(dayNoon) == "2026-03-07", "iPhone: historyDay is yyyy-MM-dd local")
            #expect(IPhoneData.historyDate("2026-03-07").map(IPhoneData.historyDay) == "2026-03-07", "iPhone: historyDate round-trips")
            #expect(IPhoneData.historyDate("2026-13-40") == nil && IPhoneData.historyDate("x") == nil, "iPhone: historyDate rejects invalid days")

            // --- stale import temp roots (scratch dir only, never the real temp root) ---
            let sweepDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacDashboardChecks-sweep-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: sweepDir.appendingPathComponent(IPhoneData.importTempPrefix + "A/x"), withIntermediateDirectories: true)
            try? Data("x".utf8).write(to: sweepDir.appendingPathComponent(IPhoneData.importTempPrefix + "B"))
            try? FileManager.default.createDirectory(at: sweepDir.appendingPathComponent("MacDashboardChecks-sysdiag-keep"), withIntermediateDirectories: true)
            try? Data("x".utf8).write(to: sweepDir.appendingPathComponent("other.txt"))
            IPhoneData.removeStaleImportRoots(in: sweepDir)
            let left = Set((try? FileManager.default.contentsOfDirectory(atPath: sweepDir.path)) ?? [])
            #expect(left == ["MacDashboardChecks-sysdiag-keep", "other.txt"], "iPhone: removeStaleImportRoots removes only the import prefix (\(left))")
            try? FileManager.default.removeItem(at: sweepDir)

            // --- archive group header (user report IPHONE-IMPORT-IOS27 #3) ---
            #expect(StringsRU().iphoneLogsFromArchive("sysdiagnose_x.tar.gz") == "Из архива sysdiagnose_x.tar.gz", "iPhone: RU archive header has no doubled word")
            #expect(StringsEN().iphoneLogsFromArchive("sysdiagnose_x.tar.gz") == "From archive sysdiagnose_x.tar.gz", "iPhone: EN archive header has no doubled word")

            #expect(IPhoneData.usbmuxdRestartCommand == "/usr/bin/killall usbmuxd", "iPhone: usbmuxd restart command exact")
            #expect(PrivilegedRunner.sudoInvocation(IPhoneData.usbmuxdRestartCommand).args
                  == ["/bin/sh", "-c", "/usr/bin/killall usbmuxd"], "iPhone: usbmuxd restart sudo invocation args")

            // --- battery history chart helpers (IPHONE-DESIGN) ---
            func utcDay(_ y: Int, _ m: Int, _ d: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d))! }
            #expect(IPhoneData.healthChartScale([98, 99, 100, 101])
                  == IPhoneData.HealthChartScale(lower: 96, upper: 102, step: 2, gridValues: [96, 98, 100, 102]), "iPhone chart: scale 98-101")
            #expect(IPhoneData.healthChartScale([91, 92, 93, 94, 96, 98, 99, 100])
                  == IPhoneData.HealthChartScale(lower: 87, upper: 101, step: 4, gridValues: [88, 92, 96, 100]), "iPhone chart: scale 91-100")
            #expect(IPhoneData.healthChartScale([98])
                  == IPhoneData.HealthChartScale(lower: 97, upper: 99, step: 1, gridValues: [97, 98, 99]), "iPhone chart: single value")
            #expect(IPhoneData.healthChartScale([]) == nil, "iPhone chart: empty scale is nil")
            let near = [utcDay(2026, 1, 10), utcDay(2026, 1, 12)]
            #expect(IPhoneData.nearestIndex(near, to: utcDay(2026, 1, 11)) == 0, "iPhone chart: nearest tie goes to the earlier sample")
            #expect(IPhoneData.nearestIndex(near, to: utcDay(2026, 1, 12)) == 1, "iPhone chart: nearest exact match")
            #expect(IPhoneData.nearestIndex([], to: utcDay(2026, 1, 1)) == nil, "iPhone chart: nearest of an empty list is nil")
            let weekly = IPhoneData.chartTicks(from: utcDay(2026, 1, 1), to: utcDay(2026, 1, 31), calendar: utc)
            #expect(weekly.count == 5 && weekly.last?.date == utcDay(2026, 1, 31) && weekly.first?.date == utcDay(2026, 1, 3)
                  && weekly.allSatisfy { if case .day = $0.tick { return true } else { return false } }, "iPhone chart: weekly ticks for a month")
            #expect(IPhoneData.chartTicks(from: utcDay(2026, 3, 27), to: utcDay(2026, 10, 12), calendar: utc).map(\.tick)
                  == [.month(4), .month(5), .month(6), .month(7), .month(8), .month(9), .month(10)], "iPhone chart: monthly ticks for seven months")
            let plot = CGSize(width: 600, height: 194)
            #expect(IPhoneData.tooltipOrigin(point: CGPoint(x: 10, y: 100), plot: plot).x == 0, "iPhone chart: tooltip clamped at the left edge")
            #expect(IPhoneData.tooltipOrigin(point: CGPoint(x: 590, y: 100), plot: plot).x == 432, "iPhone chart: tooltip clamped at the right edge")
            #expect(abs(IPhoneData.tooltipOrigin(point: CGPoint(x: 300, y: 73.72), plot: plot).y - 85.72) < 1e-6, "iPhone chart: tooltip below at the 38 % line")
            #expect(abs(IPhoneData.tooltipOrigin(point: CGPoint(x: 300, y: 75.66), plot: plot).y - (-10.34)) < 1e-6, "iPhone chart: tooltip above just past 38 %")
        }
    }
}
