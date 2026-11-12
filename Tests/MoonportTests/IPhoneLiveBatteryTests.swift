// Tests/MoonportTests/IPhoneLiveBatteryTests.swift
// IPHONE-LIVE-BATTERY: the pure gate / schedule / history decisions (`IPhoneLiveBattery`) and the model's loop
// (exists only while the gate holds, `no-unseen-work`) and merge (`applyLiveBattery`). The default transport (`.shared`)
// is never started here, so `devices` in the transport is empty and any job fails with `.gone`. Temp paths only, never
// `~/Library/Application Support/Moonport`.
import Foundation
import Testing
@testable import Moonport

@Suite struct IPhoneLiveBatteryTests {
    @MainActor
    private func makeModel() -> (IPhoneModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-livebat-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = IPhoneModel(store: IPhoneStore(url: dir.appendingPathComponent("iphones.json")),
                            archiveRoot: dir.appendingPathComponent("archive"),
                            oldDefaultArchiveRoot: dir.appendingPathComponent("archive-old"),
                            logTypeStore: IPhoneLogTypeStore(url: dir.appendingPathComponent(IPhoneLogTypeStore.fileName)))
        return (m, dir)
    }

    private func battery(percent: Int? = 80, cycleCount: Int? = 100, healthPercent: Int? = 95) -> BatteryDetail {
        BatteryDetail(
            percent: percent, voltageMV: 3930, amperageMA: 1200, powerW: 4.716, temperatureC: 30.5,
            cellVoltagesMV: [], externalConnected: true, isCharging: true, fullyCharged: false,
            timeToEmptyMin: nil, timeToFullMin: nil, currentCapacityMAh: nil, maxCapacityMAh: 4928,
            designCapacityMAh: 5030, cycleCount: cycleCount, designCycleCount: nil, healthPercent: healthPercent,
            adapter: nil, charger: nil, lifetime: nil)
    }

    private func record(key: String, battery: [BatteryPoint]) -> IPhoneDeviceRecord {
        IPhoneDeviceRecord(id: key, name: "t", marketingName: nil, productType: nil, enclosureColor: nil,
                           osVersion: nil, lastSeen: Date(), battery: battery, keptArchives: [])
    }

    @Test func gateTable() {
        func run(_ page: Bool = true, _ paused: Bool = false, _ att: Bool = true, _ snap: Bool = true, _ auto: Bool = true) -> Bool {
            IPhoneLiveBattery.shouldRun(pageShown: page, windowPaused: paused, attached: att, hasSnapshot: snap, autoRead: auto)
        }
        #expect(run())
        #expect(!run(false))
        #expect(!run(true, true))
        #expect(!run(true, false, false))
        #expect(!run(true, false, true, false))
        #expect(!run(true, false, true, true, false))
    }

    @Test func waitSchedule() {
        let now = Date()
        #expect(IPhoneLiveBattery.wait(lastChecked: nil, now: now, inFlight: false) == 0)
        #expect(IPhoneLiveBattery.wait(lastChecked: now.addingTimeInterval(-3), now: now, inFlight: false) == 7)
        #expect(IPhoneLiveBattery.wait(lastChecked: now.addingTimeInterval(-10), now: now, inFlight: false) == 0)
        #expect(IPhoneLiveBattery.wait(lastChecked: now.addingTimeInterval(-25), now: now, inFlight: false) == 0)
        #expect(IPhoneLiveBattery.wait(lastChecked: nil, now: now, inFlight: true) == 10)
        #expect(IPhoneLiveBattery.wait(lastChecked: now.addingTimeInterval(-3), now: now, inFlight: true) == 10)
        #expect(IPhoneLiveBattery.wait(lastChecked: now.addingTimeInterval(5), now: now, inFlight: false) == 10)
    }

    @Test func historyOnlyOnChange() throws {
        let now = Date()
        let b = battery()
        let first = try #require(IPhoneLiveBattery.updatedHistory([], battery: b, now: now))
        #expect(first.count == 1)
        #expect(first[0].source == "live")
        #expect(first[0].cycles == b.cycleCount)
        #expect(first[0].healthPercent == b.healthPercent)
        #expect(first[0].maxCapacityMAh == b.maxCapacityMAh)
        #expect(first[0].designCapacityMAh == b.designCapacityMAh)
        #expect(IPhoneLiveBattery.updatedHistory(first, battery: b, now: now) == nil)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let next = try #require(IPhoneLiveBattery.updatedHistory(first, battery: b, now: tomorrow))
        #expect(next.count == 2)
        let bumped = try #require(IPhoneLiveBattery.updatedHistory(first, battery: battery(cycleCount: 101), now: now))
        #expect(bumped.count == 1)
        #expect(bumped[0].cycles == 101)
        #expect(IPhoneLiveBattery.updatedHistory(first, battery: battery(cycleCount: nil, healthPercent: nil), now: now) == nil)
    }

    @Test func historyPointMatchesApply() throws {
        let now = Date()
        let b = battery()
        let points = [BatteryPoint(day: "2020-01-01", cycles: 50, healthPercent: 99, maxCapacityMAh: 5000,
                                   designCapacityMAh: 5030, source: "import")]
        let p = try #require(IPhoneLiveBattery.historyPoint(b, points: points, now: now))
        #expect(p == BatteryPoint(day: IPhoneData.historyDay(now), cycles: b.cycleCount,
                                  healthPercent: IPhoneData.historyHealthPercent(b, points: points),
                                  maxCapacityMAh: b.maxCapacityMAh, designCapacityMAh: b.designCapacityMAh,
                                  source: "live"))
    }

    @Test @MainActor func loopFollowsGate() throws {
        try #require(AppSettings.shared.iphoneAutoRead, "test host has auto-read off")
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let k = "k", h = IPhoneHandle(raw: 7)
        m.handle(.attached(h))
        m.connected[k] = h
        m.lastSnapshot[k] = IPhoneSnapshot(udid: "t", name: "t", battery: battery())
        m.setPaused(false)
        #expect(!m.isLiveBatteryRunning(deviceKey: k))
        m.setBatteryCardShown(deviceKey: k, true)
        #expect(m.isLiveBatteryRunning(deviceKey: k))
        m.setPaused(true)
        #expect(!m.isLiveBatteryRunning(deviceKey: k))
        m.setPaused(false)
        #expect(m.isLiveBatteryRunning(deviceKey: k))
        m.setBatteryCardShown(deviceKey: k, false)
        #expect(!m.isLiveBatteryRunning(deviceKey: k))
        m.setBatteryCardShown(deviceKey: k, true)
        #expect(m.isLiveBatteryRunning(deviceKey: k))
        m.handle(.detached(h))
        #expect(!m.isLiveBatteryRunning(deviceKey: k))
        #expect(m.lastSnapshot[k] == nil)
        m.setBatteryCardShown(deviceKey: k, false)
    }

    @Test @MainActor func fixtureLikeStateNeverRuns() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let k = "k"
        m.connected[k] = IPhoneHandle(raw: 9)
        m.lastSnapshot[k] = IPhoneSnapshot(udid: "t", name: "t", battery: battery())
        m.setBatteryCardShown(deviceKey: k, true)
        m.setPaused(false)
        #expect(!m.isLiveBatteryRunning(deviceKey: k))
        m.setBatteryCardShown(deviceKey: k, false)
    }

    @Test @MainActor func applyWritesOnlyOnChange() throws {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("iphones.json")
        let k = "k", h = IPhoneHandle(raw: 7)
        let b = battery()
        // A run that crosses local midnight between the calls below can fail once.
        m.handle(.attached(h))
        m.connected[k] = h
        m.lastSnapshot[k] = IPhoneSnapshot(udid: "t", name: "t", battery: b)
        m.devices = [record(key: k, battery: try #require(IPhoneLiveBattery.updatedHistory([], battery: b, now: Date())))]
        m.status[k] = .connected
        func unchangedAround() {
            #expect(m.status[k] == .connected)
            #expect(m.identity[k] == nil)
            #expect(m.logs[k] == nil)
        }
        #expect(m.applyLiveBattery(.success(b), deviceKey: k, handle: h) == "unchanged")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(m.lastSnapshot[k]?.battery == b)
        unchangedAround()
        let b2 = battery(percent: 79)
        #expect(m.applyLiveBattery(.success(b2), deviceKey: k, handle: h) == "changed")
        #expect(m.lastSnapshot[k]?.battery == b2)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        unchangedAround()
        let b3 = battery(percent: 79, cycleCount: 101)
        #expect(m.applyLiveBattery(.success(b3), deviceKey: k, handle: h) == "changed+saved")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(m.devices.first?.battery.last?.cycles == 101)
        unchangedAround()
        #expect(m.applyLiveBattery(.failure(.gone), deviceKey: k, handle: h) == "failed")
        #expect(m.applyLiveBattery(.success(nil), deviceKey: k, handle: h) == "nodata")
        #expect(m.lastSnapshot[k]?.battery == b3)
        unchangedAround()
        m.handle(.detached(h))
        #expect(m.applyLiveBattery(.success(b), deviceKey: k, handle: h) == "dropped")
    }
}
