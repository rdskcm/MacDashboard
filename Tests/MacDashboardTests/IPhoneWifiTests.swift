// Tests/MacDashboardTests/IPhoneWifiTests.swift
// IPHONE-WIFI: the link policy, the live-battery interval per link and the model's USB / Wi-Fi connection handling
// (priority, standby, promotion, the setting). Temp paths only, never `~/Library/Application Support/Moonport`;
// the default transport (`.shared`) is never started here, so any job on it fails with `.gone`.
import Foundation
import Testing
@testable import MacDashboard

@Suite struct IPhoneWifiTests {
    private let u = IPhoneHandle(raw: 11)
    private let w = IPhoneHandle(raw: 12)
    private let k = IPhoneData.deviceKey(udid: "x")

    @MainActor
    private func makeModel() -> (IPhoneModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-wifi-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = IPhoneModel(store: IPhoneStore(url: dir.appendingPathComponent("iphones.json")),
                            archiveRoot: dir.appendingPathComponent("archive"),
                            oldDefaultArchiveRoot: dir.appendingPathComponent("archive-old"),
                            logTypeStore: IPhoneLogTypeStore(url: dir.appendingPathComponent(IPhoneLogTypeStore.fileName)))
        return (m, dir)
    }

    private var snap: IPhoneSnapshot { IPhoneSnapshot(udid: "x", name: "t") }

    /// USB `u` and Wi-Fi `w` both identified as `k`, in the given order.
    @MainActor
    private func connectBoth(_ m: IPhoneModel, usbFirst: Bool) {
        let order: [(IPhoneHandle, IPhoneLink)] = usbFirst ? [(u, .usb), (w, .wifi)] : [(w, .wifi), (u, .usb)]
        for (h, link) in order {
            m.handle(.attached(h, link))
            m.apply(.success(snap), for: h, trigger: .user)
        }
    }

    @Test func attachPolicyTable() {
        #expect(IPhoneLinkPolicy.attach(interfaceType: 1, networkEnabled: true) == .report(.usb))
        #expect(IPhoneLinkPolicy.attach(interfaceType: 1, networkEnabled: false) == .report(.usb))
        #expect(IPhoneLinkPolicy.attach(interfaceType: 2, networkEnabled: true) == .report(.wifi))
        #expect(IPhoneLinkPolicy.attach(interfaceType: 2, networkEnabled: false) == .park)
        #expect(IPhoneLinkPolicy.attach(interfaceType: 0, networkEnabled: true) == .ignore)
        #expect(IPhoneLinkPolicy.attach(interfaceType: 3, networkEnabled: true) == .ignore)
        #expect(IPhoneLinkPolicy.attach(interfaceType: -1, networkEnabled: false) == .ignore)
    }

    @Test func usbBeatsWifi() {
        #expect(IPhoneLinkPolicy.replaces(.usb, .wifi))
        #expect(!IPhoneLinkPolicy.replaces(.wifi, .usb))
        #expect(!IPhoneLinkPolicy.replaces(.usb, .usb))
        #expect(!IPhoneLinkPolicy.replaces(.wifi, .wifi))
    }

    @Test func liveIntervalPerLink() {
        #expect(IPhoneLiveBattery.interval(for: .usb) == 10)
        #expect(IPhoneLiveBattery.interval(for: .wifi) == 60)
    }

    /// R19: an attach snapshot queues one storage read; a later `loadIdentity` does not repeat it once a value is held.
    @MainActor @Test func attachReadsStorageOnce() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.handle(.attached(u, .usb))
        m.apply(.success(snap), for: u, trigger: .attach)
        #expect(m.storage[k] == .waiting)
        m.storage[k] = .value("256 GB")
        m.loadIdentity(deviceKey: k)
        #expect(m.storage[k] == .value("256 GB"))
    }

    @MainActor @Test func usbThenWifiKeepsUsb() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        connectBoth(m, usbFirst: true)
        #expect(m.connected[k] == u)
        #expect(m.standbyHandle(k) == w)
        #expect(m.link(k) == .usb)
        #expect(m.devices.count == 1)
        #expect(m.pendingHandles.isEmpty)
    }

    @MainActor @Test func wifiThenUsbSwitchesToUsb() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        connectBoth(m, usbFirst: false)
        #expect(m.connected[k] == u)
        #expect(m.standbyHandle(k) == w)
        #expect(m.link(k) == .usb)
        #expect(m.devices.count == 1)
    }

    @MainActor @Test func unplugPromotesWifiAndKeepsState() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        connectBoth(m, usbFirst: true)
        m.logs[k] = []
        m.identity[k] = []
        m.handle(.detached(u))
        #expect(m.connected[k] == w)
        #expect(m.status[k] == .connected)
        #expect(m.link(k) == .wifi)
        #expect(m.logs[k] != nil)
        #expect(m.identity[k] != nil)
        #expect(m.lastSnapshot[k] != nil)
        #expect(m.standbyHandle(k) == nil)
    }

    @MainActor @Test func unplugWithoutStandbyClears() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.handle(.attached(u, .usb))
        m.apply(.success(snap), for: u, trigger: .user)
        m.logs[k] = []
        m.handle(.detached(u))
        #expect(m.connected[k] == nil)
        #expect(m.status[k] == .remembered)
        #expect(m.logs[k] == nil)
    }

    @MainActor @Test func standbyDetachKeepsUsb() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        connectBoth(m, usbFirst: true)
        m.handle(.detached(w))
        #expect(m.connected[k] == u)
        #expect(m.standbyHandle(k) == nil)
    }

    @MainActor @Test func settingOffDropsWifi() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.handle(.attached(w, .wifi))
        m.apply(.success(snap), for: w, trigger: .user)
        #expect(m.connected[k] == w)
        m.applyWifiSetting(false)
        #expect(m.connected[k] == nil)
        #expect(m.status[k] == .remembered)
        #expect(m.links[w] == nil)
        m.handle(.detached(w))   // the transport's own detach finds nothing
        #expect(m.connected[k] == nil)
        #expect(m.status[k] == .remembered)

        let (m2, dir2) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir2) }
        connectBoth(m2, usbFirst: true)
        m2.applyWifiSetting(false)
        #expect(m2.connected[k] == u)
        #expect(m2.standbyHandle(k) == nil)
    }

    @MainActor @Test func pendingWifiHiddenWhileUsbConnected() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let w2 = IPhoneHandle(raw: 13)
        m.handle(.attached(u, .usb))
        m.apply(.success(snap), for: u, trigger: .user)
        m.handle(.attached(w2, .wifi))
        m.apply(.failure(.failed(step: "t", code: 1)), for: w2, trigger: .attach)
        #expect(m.pendingHandles.contains(w2))
        #expect(!m.visiblePending.contains(w2))
        m.handle(.detached(u))
        #expect(m.visiblePending.contains(w2))
    }

    // MARK: - Stage A1: watchdog, ticket, lane

    /// Main-actor log the tickets post into.
    @MainActor private final class Log {
        var items: [String] = []
        var sentBefore: [Bool] = []
        var errors: [IPhoneReadError] = []
    }

    /// Thread-safe log for work running on a lane's queue.
    private final class ThreadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.withLock { items.append(s) } }
        var all: [String] { lock.withLock { items } }
    }

    /// One main-queue turn: everything posted to the main queue before this call has run after it.
    @MainActor private func mainTurn() async {
        await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
    }

    /// Polls `cond` on the main actor until it holds or `seconds` pass.
    @MainActor private func waitFor(_ seconds: Double, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return cond()
    }

    /// `DispatchSemaphore.wait` is unavailable inside async functions; this wrapper is synchronous.
    private func semWait(_ s: DispatchSemaphore, _ seconds: Double) -> Bool {
        s.wait(timeout: .now() + seconds) == .success
    }

    private func dummyLane(raw: Int = 1) -> IPhoneWifiLane {
        // No device framework call is made on this object; the lane releases its +1 in deinit.
        IPhoneWifiLane(raw: raw, retainedDev: Unmanaged.passRetained(NSObject()).toOpaque()) { _ in }
    }

    @Test func watchdogExpiry() {
        #expect(!IPhoneWifiWatchdog.expired(lastProgress: 0, now: 19_999_999_999, window: 20))
        #expect(IPhoneWifiWatchdog.expired(lastProgress: 0, now: 20_000_000_000, window: 20))
        #expect(!IPhoneWifiWatchdog.expired(lastProgress: 5, now: 4, window: 20))
        #expect(IPhoneWifiWatchdog.window(watching: true) == IPhoneWifiWatchdog.serviceWindow)
        #expect(IPhoneWifiWatchdog.serviceWindow == 20)
        #expect(IPhoneWifiWatchdog.window(watching: false) == IPhoneWifiWatchdog.lockdownWindow)
        #expect(IPhoneWifiWatchdog.lockdownWindow == 30)
    }

    @MainActor @Test func ticketOrder() async {
        let log = Log()
        let t = IPhoneJobTicket(fail: { e, sent in log.items.append("fail"); log.sentBefore.append(sent); log.errors.append(e) })
        t.send { log.items.append("s1") }
        t.send { log.items.append("s2") }
        t.abandon(.gone)
        t.send { log.items.append("late send") }
        t.finish { log.items.append("late finish") }
        await mainTurn()
        #expect(log.items == ["s1", "s2", "fail"])
        #expect(log.sentBefore == [true])
        #expect(log.errors == [.gone])

        let log2 = Log()
        let t2 = IPhoneJobTicket(fail: { _, _ in log2.items.append("fail") })
        t2.finish { log2.items.append("finish") }
        t2.abandon(.gone)
        await mainTurn()
        #expect(log2.items == ["finish"])
    }

    @MainActor @Test func laneCloseFailsWaitingAndRunning() async {
        let lane = dummyLane()
        let log = Log()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let t1 = IPhoneJobTicket(fail: { e, _ in log.items.append("fail1"); log.errors.append(e) })
        let t2 = IPhoneJobTicket(fail: { e, _ in log.items.append("fail2"); log.errors.append(e) })
        #expect(lane.enqueue(.interactive, t1) { t in
            started.signal()
            release.wait()
            t.finish { log.items.append("late finish1") }
        })
        #expect(lane.enqueue(.interactive, t2) { t in t.finish { log.items.append("finish2") } })
        #expect(semWait(started, 2))   // job 1 runs, job 2 waits behind it
        lane.close()
        #expect(await waitFor(1) { log.items.count == 2 })
        #expect(Set(log.items) == ["fail1", "fail2"])
        #expect(log.errors == [.gone, .gone])
        release.signal()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await mainTurn()
        #expect(Set(log.items) == ["fail1", "fail2"])   // job 1's late finish never arrives
        #expect(lane.isClosed)
        let t3 = IPhoneJobTicket(fail: { _, _ in })
        #expect(!lane.enqueue(.interactive, t3) { _ in })
    }

    @MainActor @Test func laneUrgencyOrder() async {
        let lane = dummyLane()
        let order = ThreadLog()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let ticket = { IPhoneJobTicket(fail: { _, _ in }) }
        #expect(lane.enqueue(.user, ticket()) { t in
            started.signal()
            release.wait()
            order.add("A")
            t.finish {}
        })
        #expect(semWait(started, 2))
        #expect(lane.enqueue(.background, ticket()) { t in order.add("B"); t.finish {}; done.signal() })
        #expect(lane.enqueue(.interactive, ticket()) { t in order.add("C"); t.finish {}; done.signal() })
        release.signal()
        #expect(semWait(done, 2))
        #expect(semWait(done, 2))
        #expect(order.all == ["A", "C", "B"])
        lane.close()
    }

    // MARK: D15, the Wi-Fi stall note (the delay is shortened to 50 ms)

    @MainActor private func connectWifiOnly(_ m: IPhoneModel) {
        m.wifiStallDelay = 0.05
        m.handle(.attached(w, .wifi))
        m.apply(.success(snap), for: w, trigger: .user)
    }

    @MainActor private func settle() async { try? await Task.sleep(for: .milliseconds(300)) }

    @MainActor @Test func wifiDropShowsStallNote() async {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        connectWifiOnly(m)
        m.handle(.detached(w))
        await settle()
        #expect(m.wifiStalled.contains(k))
    }

    @MainActor @Test func wifiReturnClearsStall() async {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let w2 = IPhoneHandle(raw: 14)
        connectWifiOnly(m)
        m.handle(.detached(w))
        await settle()
        #expect(m.wifiStalled.contains(k))
        m.handle(.attached(w2, .wifi))
        m.apply(.success(snap), for: w2, trigger: .attach)
        #expect(!m.wifiStalled.contains(k))
    }

    @MainActor @Test func wifiReattachInTimeNoNote() async {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let w2 = IPhoneHandle(raw: 14)
        connectWifiOnly(m)
        m.handle(.detached(w))
        m.handle(.attached(w2, .wifi))
        m.apply(.success(snap), for: w2, trigger: .attach)
        await settle()
        #expect(!m.wifiStalled.contains(k))
    }

    @MainActor @Test func settingOffNoStall() async {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        connectWifiOnly(m)
        m.applyWifiSetting(false)
        await settle()
        #expect(m.wifiStalled.isEmpty)
    }

    @MainActor @Test func usbDropNoStall() async {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.wifiStallDelay = 0.05
        m.handle(.attached(u, .usb))
        m.apply(.success(snap), for: u, trigger: .user)
        m.handle(.detached(u))
        await settle()
        #expect(m.wifiStalled.isEmpty)
    }

    @MainActor @Test func promotionNoStall() async {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.wifiStallDelay = 0.05
        connectBoth(m, usbFirst: true)
        m.handle(.detached(u))
        await settle()
        #expect(m.connected[k] == w)
        #expect(m.wifiStalled.isEmpty)
    }

    @Test func headerRetryBatchFields() {
        let b = IPhoneLogTypeBatch()
        #expect(b.failures.isEmpty)
        #expect(b.recovered.isEmpty)
        #expect(b.isEmpty)
    }

    /// The kernel behaviour the watchdog relies on: `cut` wakes a blocked `recv` with end-of-file and a later write
    /// fails with EPIPE instead of raising SIGPIPE (no device involved).
    @Test func watchdogCutWakesBlockedRecv() throws {
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        let (a, b) = (pair[0], pair[1])
        defer { close(a); close(b) }
        let done = DispatchSemaphore(value: 0)
        final class Outcome: @unchecked Sendable { var rc = -99; var elapsed = 0.0 }
        let out = Outcome()
        let t = Thread {
            var byte: UInt8 = 0
            let t0 = Date()
            out.rc = recv(a, &byte, 1, 0)
            out.elapsed = Date().timeIntervalSince(t0)
            done.signal()
        }
        t.start()
        Thread.sleep(forTimeInterval: 0.2)
        IPhoneWifiWatchdog.cut(a)
        #expect(done.wait(timeout: .now() + 2) == .success)
        #expect(out.rc == 0)
        #expect(out.elapsed >= 0.15)
        var byte: UInt8 = 1
        errno = 0
        #expect(send(a, &byte, 1, 0) == -1)
        #expect(errno == EPIPE)
    }
}
