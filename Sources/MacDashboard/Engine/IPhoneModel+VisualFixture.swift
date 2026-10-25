// Engine/IPhoneModel+VisualFixture.swift
// IPHONE-DESIGN: fixed iPhone dataset for `-visualFixture` and tools/visual/content_states.swift.
// Memory only: never starts the transport, never saves the store. All values are invented.
import Foundation

extension IPhoneModel {
    static let fixtureIvanKey = IPhoneData.deviceKey(udid: "fixture-ivan")
    static let fixtureIvanKeptArchive = "sysdiagnose_2026.01.09_01-34-55+0300_iPhone-OS_iPhone_23E254.tar.gz"
    static let fixtureVictoriaKey = IPhoneData.deviceKey(udid: "fixture-victoria")

    func applyVisualFixture() {
        let now = VisualFixture.referenceDate
        let cal = Calendar.current
        func day(_ back: Int) -> Date { cal.date(byAdding: .day, value: -back, to: now)! }

        func history(n: Int, endBack: Int, steps: [(Double, Int)], last: Int,
                     c0: Int, c1: Int, design: Int, live: Int) -> [BatteryPoint] {
            (0..<n).map { i in
                let f = Double(i) / Double(n - 1)
                let health = steps.first(where: { f < $0.0 })?.1 ?? last
                let cycles = Int((Double(c0) + Double(i) * Double(c1 - c0) / Double(n - 1)).rounded())
                return BatteryPoint(
                    day: IPhoneData.historyDay(day(endBack + n - 1 - i)),
                    cycles: cycles,
                    healthPercent: health,
                    maxCapacityMAh: nil,
                    designCapacityMAh: design,
                    source: i >= n - live ? "live" : "import"
                )
            }
        }

        devices = [
            IPhoneDeviceRecord(
                id: Self.fixtureIvanKey, name: "Ivan’s iPhone", marketingName: "iPhone 17 Pro Max",
                productType: "iPhone18,2", enclosureColor: "2", osVersion: "26.4.1", lastSeen: now,
                battery: history(n: 180, endBack: 0, steps: [(0.5, 101), (0.627, 100), (0.874, 99)], last: 98,
                                 c0: 70, c1: 269, design: 5030, live: 2),
                keptArchives: [Self.fixtureIvanKeptArchive]
            ),
            IPhoneDeviceRecord(
                id: Self.fixtureVictoriaKey, name: "Victoria’s iPhone", marketingName: "iPhone 15 Pro Max",
                productType: "iPhone16,2", enclosureColor: "1", osVersion: "26.3.1", lastSeen: day(1),
                battery: history(n: 120, endBack: 1,
                                 steps: [(0.25, 100), (0.4, 99), (0.52, 98), (0.68, 96), (0.82, 94), (0.93, 93), (0.995, 92)],
                                 last: 91, c0: 238, c1: 412, design: 4441, live: 3),
                keptArchives: []
            ),
        ]
        transportAvailable = true
        connected = [Self.fixtureIvanKey: IPhoneHandle(raw: 1)]
        status = [Self.fixtureIvanKey: .connected, Self.fixtureVictoriaKey: .remembered]
        pendingHandles = []
        pendingStatus = [:]
        restartingService = false
        restartError = nil
        selectedDeviceKey = nil

        lastSnapshot = [Self.fixtureIvanKey: IPhoneSnapshot(
            udid: "fixture-ivan", name: "Ivan’s iPhone", marketingName: "iPhone 17 Pro Max",
            productType: "iPhone18,2", osVersion: "26.4.1", build: "23E254", enclosureColor: "2",
            battery: BatteryDetail(
                percent: 34, voltageMV: 3930, amperageMA: 1200, powerW: nil, temperatureC: 40.6,
                cellVoltagesMV: [], externalConnected: true, isCharging: true, fullyCharged: false,
                timeToEmptyMin: nil, timeToFullMin: nil, currentCapacityMAh: nil, maxCapacityMAh: 4928,
                designCapacityMAh: 5030, cycleCount: 269, designCycleCount: nil, healthPercent: 98,
                adapter: nil, charger: nil, lifetime: nil
            )
        )]

        // Live logs.
        let categories: [(LogCategory, [String], Int, String)] = [
            (.appCrash, ["MiHomeDesktopWidgetExtension", "ServiceExtension", "Pedometer"], 11, ".ips"),
            (.exceptionFault, ["ExcUserFault_Telegram", "ExcUserFault_Safari", "ExcUserFault_Mail", "ExcUserFault_WhatsApp"], 8, ".ips"),
            (.jetsam, ["JetsamEvent"], 16, ".ips"),
            (.diskWrites, ["Photos.diskwrites_resource", "Maps.diskwrites_resource", "Music.diskwrites_resource", "YouTube.diskwrites_resource"], 8, ".ips"),
            (.cpuResource, ["Instagram.cpu_resource", "mediaanalysisd.cpu_resource"], 2, ".ips"),
            (.stackshot, ["stacks"], 1, ".ips"),
            (.analytics, ["Analytics-Journal"], 12, ".ips.ca"),
            (.other, ["log-aggregated", "xp_amp_app_usage_dnu", "WiFiLQMMetrics", "powerlog"], 17, ".log"),
        ]
        var entries: [IPhoneLogEntry] = []
        for (c, (cat, prefixes, count, ext)) in categories.enumerated() {
            for i in 0..<count {
                let d = day(i * 30 / count)
                let stamp = String(format: "%02d%02d%02d", (i * 7) % 24, (i * 13) % 60, (i * 29) % 60)
                let name = "\(prefixes[i % prefixes.count])-\(IPhoneData.historyDay(d))-\(stamp)\(ext)"
                entries.append(IPhoneLogEntry(
                    path: "/" + name, size: Int64(4000 + (i * 7919 + c * 104729) % 90000),
                    modified: d, bugType: nil, category: cat, source: .live
                ))
            }
        }
        entries.append(IPhoneLogEntry(
            path: "/DiagnosticLogs/sysdiagnose/sysdiagnose_2026.01.15_09-15-02+0300_iPhone-OS_iPhone_23E254.tar.gz",
            size: 298_000_000, modified: now, bugType: nil, category: .other, source: .live
        ))
        logs = [Self.fixtureIvanKey: entries]
        logsFailed = []

        let archiveName = "sysdiagnose_2025.12.15_10-02-11+0300_iPhone-OS_iPhone_22E240.tar.gz"
        let archived: [(String, Int64, Int, LogCategory)] = [
            ("Safari-2025-12-14-112233.ips", 174_000, 32, .appCrash),
            ("Notes-2025-12-02-090455.ips", 139_000, 44, .appCrash),
            ("JetsamEvent-2025-12-10-231105.ips", 492_000, 36, .jetsam),
        ]
        archiveLogs = [Self.fixtureIvanKey: archived.map {
            IPhoneLogEntry(path: "/" + $0.0, size: $0.1, modified: day($0.2), bugType: nil,
                           category: $0.3, source: .archive(name: archiveName))
        }]

        let values: [IdentityLabel: String] = [
            .marketingName: "iPhone 17 Pro Max", .modelNumber: "MFXG4 LL/A", .regulatoryModel: "A3257",
            .hardwareModel: "V54AP", .ios: "26.4.1 (23E254)", .storage: fmtCapacity(256_000_000_000), .colorCode: "2",
            .serial: "D7LXK24PYM", .logicBoard: "F3Y52830M1T0YE6", .imei: "350917284615406",
            .imei2: "350917284627747", .battery: "FQ14231D6K15Y0", .displayPanel: "GVC4282PL7Z0BBA",
            .displayRawPanel: "GVC4282PL7Z0BBA", .coverGlass: "FX94271R2Q0000", .backGlass: "0904119357110",
            .nova: "LCS43017HB12WY", .ambientLight: "9714480021276", .backCamera: "DNM4311XE40RYP",
            .backSuperWide: "GCF4302LW0R9R", .backTele: "F0W4307QK0JS7", .frontCamera: "GCF4319MD0NGT",
            .frontIR: "HNQ4316AV0P8L", .faceIDProjector: "A0742218J95A2",
        ]
        identity = [Self.fixtureIvanKey: IdentityLabel.allCases.map {
            IPhoneIdentityField(id: $0.rawValue, label: $0, value: values[$0]!, isSecret: $0.isSecret)
        }]
        identityFailed = []

        importing = [:]
        importResult = [:]
        importQuestion = [:]
    }
}
