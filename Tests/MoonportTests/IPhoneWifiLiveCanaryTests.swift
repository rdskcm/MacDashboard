// Tests/MoonportTests/IPhoneWifiLiveCanaryTests.swift
// IPHONE-WIFI R10 opt-in live test: MACDASH_LIVE=1 swift test --filter liveCanaryIPhoneWifi (cable out, phone on the same Wi-Fi).
// Runs the transport against the attached phone and prints what it read. Reads only:
// no stores, no file writes. Never prints serials, IMEIs, part ids or the UDID.
// V3b: MACDASH_LIVE=1 MACDASH_WIFI_DROP=<idle|battery|copy|sysdiagnose> swift test --filter liveCanaryIPhoneWifiDrop — one scenario per run; the user switches the phone's Wi-Fi off and on when told.
// V3c: MACDASH_LIVE=1 swift test --filter liveCanaryIPhoneWifiUsbConcurrent (cable IN, phone on the same Wi-Fi) — USB reads while a Wi-Fi lane copies and while its link dies.
import Foundation
import Testing
@testable import Moonport

extension SerialTests {
    @MainActor
    final class IPhoneWifiLiveBox {
        struct Event {
            var at: ContinuousClock.Instant
            var handle: IPhoneHandle
            var link: IPhoneLink?   // nil = detached
        }
        var events: [Event] = []
    }

    @MainActor
    final class IPhoneWifiSlot<T> {
        var value: T?
        var finished: ContinuousClock.Instant?
        /// Completions delivered (V3b `late_posts`: everything after the first is a late post).
        var completions = 0
    }

    struct IPhoneWifiLiveCanaryTests {
        /// One box for the whole suite: `MobileDeviceTransport.start` keeps only the first handler.
        @MainActor static let box = IPhoneWifiLiveBox()
        static let capSeconds = 180.0

        /// Polls `done` every 20 ms; false after `seconds`.
        @MainActor
        static func wait(_ seconds: Double, until done: () -> Bool) async -> Bool {
            let t0 = ContinuousClock.now
            while !done() {
                if ContinuousClock.now - t0 > .seconds(seconds) { return false }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return true
        }

        static func ms(_ since: ContinuousClock.Instant, to end: ContinuousClock.Instant = ContinuousClock.now) -> Int {
            let d = end - since
            return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
        }

        /// One transport call with a wait cap; `ms` is the time to completion (the cap when it never completed).
        @MainActor
        static func run<T>(cap: Double, _ start: (@escaping @MainActor (T) -> Void) -> Void)
            async -> (value: T?, ms: Int, start: ContinuousClock.Instant, end: ContinuousClock.Instant, slot: IPhoneWifiSlot<T>) {
            let slot = IPhoneWifiSlot<T>()
            let t0 = ContinuousClock.now
            start {
                slot.completions += 1
                if slot.value == nil { slot.value = $0; slot.finished = ContinuousClock.now }
            }
            _ = await wait(cap) { slot.value != nil }
            let end = slot.finished ?? ContinuousClock.now
            return (slot.value, ms(t0, to: end), t0, end, slot)
        }

        static func describe<T>(_ r: Result<T, IPhoneReadError>?) -> String {
            switch r {
            case nil: return "none"
            case .success?: return "ok"
            case .failure(.gone)?: return "gone"
            case .failure(.needsTrust)?: return "needsTrust"
            case .failure(.unavailable)?: return "unavailable"
            case .failure(.failed(let step, let code))?: return "failed:\(step):\(code)"
            }
        }

        /// Starts the transport with the network on (once per process) and records every event.
        @MainActor
        static func startTransport() {
            let box = Self.box
            let t = MobileDeviceTransport.shared
            t.start(networkEnabled: true) { event in
                switch event {
                case .attached(let h, let link): box.events.append(.init(at: .now, handle: h, link: link))
                case .detached(let h): box.events.append(.init(at: .now, handle: h, link: nil))
                }
            }
            t.setNetworkEnabled(true)
        }

        /// Waits for a Wi-Fi attach recorded after `index`; returns it with the wait in ms (nil on the cap).
        @MainActor
        static func waitWifiAttach(after index: Int, cap: Double) async -> (handle: IPhoneHandle, ms: Int, event: Int)? {
            let t0 = ContinuousClock.now
            var found: Int?
            let ok = await wait(cap) {
                found = box.events.indices.first { $0 >= index && box.events[$0].link == .wifi }
                return found != nil
            }
            guard ok, let i = found else { return nil }
            return (box.events[i].handle, ms(t0), i)
        }

        static func action(_ text: String) {
            let line = Data("liveWifiDrop ACTION: \(text)\n".utf8)
            FileHandle.standardError.write(line)
            // `swift test` holds the test's output until the run ends, so a prompt also goes to a file the
            // orchestrator's runner watches live.
            if let path = ProcessInfo.processInfo.environment["MACDASH_WIFI_ACTION_FILE"],
               let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile(); fh.write(line); try? fh.close()
            }
        }

        /// Every string value under a key named `transportType`, at any depth.
        static func transportTypes(in json: Any) -> [String] {
            var out: [String] = []
            if let d = json as? [String: Any] {
                for (k, v) in d {
                    if k == "transportType", let s = v as? String { out.append(s) } else { out += transportTypes(in: v) }
                }
            } else if let a = json as? [Any] {
                for v in a { out += transportTypes(in: v) }
            }
            return out
        }

        /// `xcrun devicectl list devices` into a temp file, bounded to 60 s; the transport types it reports.
        @MainActor
        static func devicectlTransportTypes() async -> [String]? {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-wifi-live-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let out = dir.appendingPathComponent("dc.json")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            p.arguments = ["devicectl", "list", "devices", "--json-output", out.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            if !(await wait(60) { !p.isRunning }) { p.terminate(); return nil }
            guard let data = try? Data(contentsOf: out), let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return transportTypes(in: json)
        }

        /// The largest live `.ips` of at most 2 MB, through the listing as V3 step 7 runs it.
        @MainActor
        static func largestIps(_ h: IPhoneHandle) async -> IPhoneLogEntry? {
            let listed = await run(cap: capSeconds) { (done: @escaping @MainActor (Result<IPhoneLogListing, IPhoneReadError>) -> Void) in
                MobileDeviceTransport.shared.listLogs(h, knownHeaders: [:], onListing: done, onTypes: { _ in })
            }
            guard case .success(let listing)? = listed.value else { return nil }
            return listing.entries.filter { $0.path.hasSuffix(".ips") && $0.size > 0 && $0.size <= 2_000_000 }
                .max(by: { $0.size < $1.size })
        }

        @MainActor
        static func largestSysdiagnose(_ h: IPhoneHandle) async -> IPhoneAFCEntry? {
            let listed = await run(cap: 60) { (done: @escaping @MainActor (Result<[IPhoneAFCEntry], IPhoneReadError>) -> Void) in
                MobileDeviceTransport.shared.listSysdiagnoseDir(h, completion: done)
            }
            guard case .success(let entries)? = listed.value else { return nil }
            return entries.filter {
                let n = ($0.path as NSString).lastPathComponent
                return n.hasPrefix("sysdiagnose_") && !n.hasPrefix(SysdiagnoseDir.inProgressPrefix)
            }.max(by: { $0.size < $1.size })
        }

        struct CopyOutcome {
            var ok: Bool?
            var start: ContinuousClock.Instant
            var end: ContinuousClock.Instant
            var lastProgress: ContinuousClock.Instant?
            var progressCalls: Int
            var maxBytes: Int
            var state: CopyState
        }

        @MainActor
        final class CopyState {
            var ok: Bool?
            var end: ContinuousClock.Instant?
            var lastProgress: ContinuousClock.Instant?
            var calls = 0
            var maxBytes = 0
            /// Completions delivered (V3b `late_posts`).
            var completions = 0
        }

        /// Copies one phone file to a fresh temp dir (removed afterwards), waiting at most `cap` seconds.
        /// `onProgress` gets the bytes done.
        @MainActor
        static func copyOnce(_ h: IPhoneHandle, path: String, size: Int64, cap: Double,
                             onProgress: @escaping @MainActor (Int) -> Void = { _ in }) async -> CopyOutcome {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-wifi-live-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let dest = dir.appendingPathComponent((path as NSString).lastPathComponent)
            let st = CopyState()
            let t0 = ContinuousClock.now
            MobileDeviceTransport.shared.copyFile(h, remotePath: path, size: size, to: dest, progress: {
                st.calls += 1
                st.lastProgress = .now
                st.maxBytes = max(st.maxBytes, $0)
                onProgress($0)
            }, completion: { st.completions += 1; if st.ok == nil { st.ok = $0; st.end = .now } })
            _ = await wait(cap) { st.ok != nil }
            let sizeOK = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) == size
            return CopyOutcome(ok: st.ok.map { $0 && sizeOK }, start: t0, end: st.end ?? .now, lastProgress: st.lastProgress,
                               progressCalls: st.calls, maxBytes: st.maxBytes, state: st)
        }

        // MARK: V3

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        @MainActor
        func liveCanaryIPhoneWifi() async {
            let transport = MobileDeviceTransport.shared
            let box = Self.box

            // 1. Wi-Fi attach
            let t0 = ContinuousClock.now
            Self.startTransport()
            let attach = await Self.waitWifiAttach(after: 0, cap: 30)
            let usb = box.events.filter { $0.link == .usb }.count
            let wifi = box.events.filter { $0.link == .wifi }.count
            print("liveWifi attach wifi=\(wifi) usb=\(usb) ms=\(Self.ms(t0))")
            #expect(usb == 0, "unplug the cable")
            guard let attach else {
                Issue.record("no Wi-Fi attach within 30 s: phone unlocked, on the same Wi-Fi, Finder's «Show this iPhone when on Wi-Fi» on?")
                return
            }
            let h = attach.handle
            /// D7 window rule input: the longest silence per phase on this lane since the last call.
            func gap(_ step: String) {
                if let g = transport.takeWifiStepGaps(h) {
                    print("liveWifi gap \(step) serviceMs=\(Int(g.service * 1000)) lockdownMs=\(Int(g.lockdown * 1000))")
                } else {
                    print("liveWifi gap \(step) serviceMs=nil lockdownMs=nil")
                }
            }

            // 2. independent reading of the link
            let types = await Self.devicectlTransportTypes()
            print("liveWifi devicectl transportType=\(types.map { String(describing: $0) } ?? "nil")")
            #expect(types?.contains("localNetwork") == true)
            #expect(types?.contains("wired") != true)

            // 3. snapshot
            let snapRun = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<IPhoneSnapshot, IPhoneReadError>) -> Void) in
                transport.readSnapshot(h, includeBattery: true, completion: done)
            }
            guard case .success(let snap)? = snapRun.value, let ref = snap.battery else {
                Issue.record("snapshot failed: \(Self.describe(snapRun.value))")
                return
            }
            print("liveWifi snapshot ms=\(snapRun.ms) os=\(snap.osVersion ?? "nil") cycles=\(String(describing: ref.cycleCount)) health=\(String(describing: ref.healthPercent))")
            #expect((ref.cycleCount ?? 0) > 0)
            #expect((ref.designCapacityMAh ?? 0) > 0)
            gap("snapshot")

            // 4. battery x3
            for i in 0..<3 {
                let r = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<BatteryDetail?, IPhoneReadError>) -> Void) in
                    transport.readBattery(h, completion: done)
                }
                print("liveWifi battery i=\(i) ms=\(r.ms)")
                guard case .success(let b?)? = r.value else {
                    Issue.record("battery read \(i) failed: \(Self.describe(r.value))")
                    return
                }
                #expect(b.cycleCount == ref.cycleCount, "cycle count equals the snapshot's")
            }
            gap("battery")

            // 5. identity
            let id = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<[IPhoneIdentityField], IPhoneReadError>) -> Void) in
                transport.readIdentity(h, language: .en, completion: done)
            }
            if case .success(let fields)? = id.value {
                print("liveWifi identity fields=\(fields.count) ms=\(id.ms)")
                #expect(!fields.isEmpty)
            } else {
                Issue.record("identity failed: \(Self.describe(id.value))")
            }
            gap("identity")

            // 6. storage, three reads 2 s apart (D17: a nil total is printed, not failed)
            var storageValues: [Int64] = []
            for i in 0..<3 {
                if i > 0 { try? await Task.sleep(for: .seconds(2)) }
                let sto = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<Int64?, IPhoneReadError>) -> Void) in
                    transport.readStorage(h, onStart: {}, completion: done)
                }
                var gb = "nil"
                if case .success(let bytes)? = sto.value {
                    if let bytes {
                        gb = String(bytes / 1_000_000_000)
                        #expect(bytes > 32_000_000_000)
                        storageValues.append(bytes)
                    }
                } else {
                    Issue.record("storage read \(i) failed: \(Self.describe(sto.value))")
                }
                print("liveWifi storage n=\(i) ms=\(sto.ms) gb=\(gb)")
            }
            #expect(Set(storageValues).count <= 1, "every non-nil storage value is equal")
            gap("storage")

            // 7. crash logs: listing, then the header batches until nothing is pending
            let listStart = ContinuousClock.now
            let batches = IPhoneWifiSlot<[IPhoneLogTypeBatch]>()
            batches.value = []
            let listing = IPhoneWifiSlot<Result<IPhoneLogListing, IPhoneReadError>>()
            transport.listLogs(h, knownHeaders: [:], onListing: { listing.value = $0; listing.finished = .now },
                               onTypes: { batches.value?.append($0) })
            _ = await Self.wait(60) { listing.value != nil }
            guard case .success(let l)? = listing.value else {
                Issue.record("listing failed: \(Self.describe(listing.value))")
                return
            }
            let listMs = Self.ms(listStart, to: listing.finished ?? .now)
            var entries = l.entries
            var applied = 0
            var read = 0
            var failed = 0
            var recovered = 0
            var headerFails = 0
            var sizeByKey: [String: Int64] = [:]
            for e in l.entries { sizeByKey[IPhoneData.logCacheKey(path: e.path, size: e.size, modified: e.modified)] = e.size }
            func absorb() {
                while applied < (batches.value?.count ?? 0) {
                    let b = batches.value![applied]
                    applied += 1
                    entries = IPhoneLogTypes.merge(entries, b)
                    read += b.read.count
                    failed += b.failed.count
                    recovered += b.recovered.count
                    // D18: one line per failed read, by index and size only (no file name).
                    for (key, f) in b.failures.sorted(by: { $0.key < $1.key }) {
                        headerFails += 1
                        print("liveWifi headerFail n=\(headerFails) size=\(sizeByKey[key].map { String($0) } ?? "nil") step=\(f.step) code=\(f.code)")
                    }
                }
            }
            let settled = await Self.wait(180) { absorb(); return !entries.contains { $0.category == .pending } }
            absorb()
            print("liveWifi logs entries=\(l.entries.count) read=\(read) failed=\(failed) recovered=\(recovered) listMs=\(listMs) typesMs=\(Self.ms(listStart))")
            #expect(settled, "entries still pending after 180 s")
            #expect(failed == 0, "after the D18 retry no header read may stay failed; the headerFail lines above are the diagnosis input")
            gap("logs")

            // 8. one crash-log copy
            if let e = l.entries.filter({ $0.path.hasSuffix(".ips") && $0.size > 0 && $0.size <= 2_000_000 }).max(by: { $0.size < $1.size }) {
                let c = await Self.copyOnce(h, path: e.path, size: e.size, cap: 120)
                print("liveWifi copy bytes=\(e.size) ms=\(Self.ms(c.start, to: c.end))")
                #expect(c.ok == true)
            } else {
                print("liveWifi copy none")
            }
            gap("copy")

            // 9. sysdiagnose directory and, when an archive exists, its copy
            let dirRun = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<[IPhoneAFCEntry], IPhoneReadError>) -> Void) in
                transport.listSysdiagnoseDir(h, completion: done)
            }
            if case .success(let dirEntries)? = dirRun.value {
                print("liveWifi sysdiagnoseDir count=\(dirEntries.count) ms=\(dirRun.ms)")
                let archive = dirEntries.filter {
                    let n = ($0.path as NSString).lastPathComponent
                    return n.hasPrefix("sysdiagnose_") && !n.hasPrefix(SysdiagnoseDir.inProgressPrefix)
                }.max(by: { $0.size < $1.size })
                let free = IPhoneCrashLog.availableBytes(at: FileManager.default.temporaryDirectory) ?? 0
                if let a = archive, free >= 2 * a.size {
                    let c = await Self.copyOnce(h, path: a.path, size: a.size, cap: 900)
                    let seconds = max(0.001, Double(Self.ms(c.start, to: c.end)) / 1000)
                    let mb = Double(a.size) / 1_000_000
                    print("liveWifi sysdiagnose MB=\(Int(mb)) s=\(Int(seconds)) MBps=\(String(format: "%.1f", mb / seconds))")
                    #expect(c.ok == true)
                } else {
                    print("liveWifi sysdiagnose none")
                }
            } else {
                Issue.record("sysdiagnose listing failed: \(Self.describe(dirRun.value))")
            }
            gap("sysdiagnose")

            // 10. the gate, live
            let before = box.events.count
            let g0 = ContinuousClock.now
            transport.setNetworkEnabled(false)
            let detached = await Self.wait(5) { box.events[before...].contains { $0.handle == h && $0.link == nil } }
            print("liveWifi gate off detached=\(detached) ms=\(Self.ms(g0))")
            #expect(detached)
            let mid = box.events.count
            let g1 = ContinuousClock.now
            transport.setNetworkEnabled(true)
            let again = await Self.waitWifiAttach(after: mid, cap: 5)
            print("liveWifi gate on attached=\(again != nil) ms=\(Self.ms(g1))")
            #expect(again != nil)
        }

        // MARK: V3b

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"
                       && ProcessInfo.processInfo.environment["MACDASH_WIFI_DROP"] != nil))
        @MainActor
        func liveCanaryIPhoneWifiDrop() async {
            let scenario = ProcessInfo.processInfo.environment["MACDASH_WIFI_DROP"] ?? ""
            guard ["idle", "battery", "copy", "sysdiagnose"].contains(scenario) else {
                Issue.record("MACDASH_WIFI_DROP must be idle, battery, copy or sysdiagnose")
                return
            }
            let transport = MobileDeviceTransport.shared
            let box = Self.box
            func line(_ s: String) { print("liveWifiDrop \(scenario) \(s)") }
            func capped(_ ms: Int) -> String { Double(ms) >= Self.capSeconds * 1000 ? ">180000" : String(ms) }

            Self.startTransport()
            guard let attach = await Self.waitWifiAttach(after: 0, cap: 30) else {
                Issue.record("no Wi-Fi attach within 30 s (cable out, phone on the same Wi-Fi)")
                return
            }
            let h = attach.handle
            #expect(!box.events.contains { $0.link == .usb }, "unplug the cable")

            /// True when `.detached(h)` was recorded at or before `instant`.
            func detachedBefore(_ instant: ContinuousClock.Instant) -> Bool {
                box.events.contains { $0.handle == h && $0.link == nil && $0.at <= instant }
            }

            /// The 60 s re-attach wait after ACTION ON: only printed (usbmuxd does not re-attach, D15). The run ends after it.
            func reattach() async {
                Self.action("turn the phone's Wi-Fi ON now")
                let mark = box.events.count
                if let back = await Self.waitWifiAttach(after: mark, cap: 60) {
                    line("reattach_ms=\(back.ms) same_handle=\(back.handle == h)")
                } else {
                    line("reattach_ms=>60000")
                }
            }

            /// `late_posts`: completions of the failing call that arrive after its failure, counted until 150 s after it.
            func lateReport(failedAt: ContinuousClock.Instant, late: @MainActor () -> Int) async {
                let remaining = 150 - Double(Self.ms(failedAt)) / 1000
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                let n = late()
                line("late_posts=\(n)")
                #expect(n == 0, "the ticket drops every completion after the failure (D14)")
            }

            /// After the cut: the queue check, the re-attach wait, the late-post count.
            func afterCut(failedAt: ContinuousClock.Instant, late: @MainActor () -> Int) async {
                let next = await Self.run(cap: Self.capSeconds) { (done: @escaping @MainActor (Result<BatteryDetail?, IPhoneReadError>) -> Void) in
                    transport.readBattery(h, completion: done)
                }
                line("next_ms=\(capped(next.ms)) next_result=\(Self.describe(next.value))")
                #expect(Self.describe(next.value) == "gone", "the queue check after a cut fails with gone")
                #expect(next.ms <= 1000, "the queue check answers within 1 s")
                await reattach()
                await lateReport(failedAt: failedAt, late: late)
            }

            switch scenario {
            case "idle":
                Self.action("turn the phone's Wi-Fi OFF now")
                let t0 = ContinuousClock.now
                let mark = box.events.count
                var lockdown: (failedAt: ContinuousClock.Instant, late: @MainActor () -> Int)?
                _ = await Self.wait(10) { box.events[mark...].contains { $0.handle == h && $0.link == nil } }
                if box.events[mark...].contains(where: { $0.handle == h && $0.link == nil }) {
                    print("liveWifiDrop idle lockdown skipped detached_first")
                } else {
                    let r = await Self.run(cap: Self.capSeconds) { (done: @escaping @MainActor (Result<IPhoneSnapshot, IPhoneReadError>) -> Void) in
                        transport.readSnapshot(h, includeBattery: false, completion: done)
                    }
                    line("lockdown_ms=\(capped(r.ms)) result=\(Self.describe(r.value))")
                    #expect(r.ms <= 34_000, "the lockdown window ends the call")
                    #expect(Self.describe(r.value) != "needsTrust", "no Trust advice over Wi-Fi (D16)")
                    lockdown = (r.end, { r.slot.completions - 1 })
                }
                let detached = await Self.wait(max(1, 180 - Double(Self.ms(t0)) / 1000)) {
                    box.events[mark...].contains { $0.handle == h && $0.link == nil }
                }
                if detached, let ev = box.events[mark...].first(where: { $0.handle == h && $0.link == nil }) {
                    line("detach_ms=\(Self.ms(t0, to: ev.at))")
                } else {
                    line("detach_ms=>180000")
                    Issue.record("no detach within 180 s of switching Wi-Fi off")
                    return
                }
                await reattach()
                if let lockdown {
                    await lateReport(failedAt: lockdown.failedAt, late: lockdown.late)
                } else {
                    line("late_posts=none (no call was made)")
                }

            case "battery":
                for _ in 0..<3 {
                    let r = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<BatteryDetail?, IPhoneReadError>) -> Void) in
                        transport.readBattery(h, completion: done)
                    }
                    guard case .success? = r.value else {
                        Issue.record("warm-up battery read failed: \(Self.describe(r.value))")
                        return
                    }
                }
                Self.action("turn the phone's Wi-Fi OFF now")
                let t0 = ContinuousClock.now
                while true {
                    let r = await Self.run(cap: Self.capSeconds) { (done: @escaping @MainActor (Result<BatteryDetail?, IPhoneReadError>) -> Void) in
                        transport.readBattery(h, completion: done)
                    }
                    if r.value == nil {
                        line("cut_ms=>180000")
                        Issue.record("a battery read did not return within 180 s")
                        return
                    }
                    if case .success? = r.value { continue }
                    let result = Self.describe(r.value)
                    let detachFirst = detachedBefore(r.end)
                    line("cut_ms=\(r.ms) since_off_ms=\(Self.ms(t0, to: r.end)) result=\(result) detach_first=\(detachFirst)")
                    #expect(r.ms <= 34_000, "the lockdown window (30 s + check + one step) ends the call")
                    #expect(result != "needsTrust", "no Trust advice over Wi-Fi (D16)")
                    if result == "gone" { #expect(detachFirst, "gone is posted after the detach") }
                    await afterCut(failedAt: r.end, late: { r.slot.completions - 1 })
                    break
                }

            case "copy":
                guard let e = await Self.largestIps(h) else {
                    Issue.record("no .ips of at most 2 MB on the phone")
                    return
                }
                for _ in 0..<2 {
                    let c = await Self.copyOnce(h, path: e.path, size: e.size, cap: 120)
                    guard c.ok == true else {
                        Issue.record("warm-up copy failed")
                        return
                    }
                }
                Self.action("turn the phone's Wi-Fi OFF now")
                let t0 = ContinuousClock.now
                while true {
                    let c = await Self.copyOnce(h, path: e.path, size: e.size, cap: Self.capSeconds)
                    if c.ok == nil {
                        line("cut_ms=>180000")
                        Issue.record("a copy did not return within 180 s")
                        return
                    }
                    if c.ok == true { continue }
                    let base = max(c.start, c.lastProgress ?? c.start)   // the later of the call's start and its last progress
                    let service = c.progressCalls > 0
                    let cut = Self.ms(base, to: c.end)
                    line("cut_ms=\(cut) phase=\(service ? "service" : "lockdown") since_off_ms=\(Self.ms(t0, to: c.end)) detach_first=\(detachedBefore(c.end))")
                    #expect(cut <= (service ? 22_000 : 34_000), "service cut within 20 s + check, lockdown end within 30 s + check + a step")
                    let st = c.state
                    await afterCut(failedAt: c.end, late: { st.completions - 1 })
                    break
                }

            default:   // sysdiagnose
                guard let a = await Self.largestSysdiagnose(h) else {
                    print("liveWifiDrop sysdiagnose none")
                    Issue.record("no sysdiagnose archive on the phone: make one with the app's sysdiagnose request over the cable first")
                    return
                }
                let free = IPhoneCrashLog.availableBytes(at: FileManager.default.temporaryDirectory) ?? 0
                guard free >= 2 * a.size else {
                    Issue.record("not enough free space in the temp volume")
                    return
                }
                let off = IPhoneWifiSlot<ContinuousClock.Instant>()
                let c = await Self.copyOnce(h, path: a.path, size: a.size, cap: Self.capSeconds) { done in
                    if off.value == nil, done > 20_000_000 {
                        off.value = .now
                        Self.action("turn the phone's Wi-Fi OFF now")
                    }
                }
                guard let t0 = off.value else {
                    Issue.record("the copy ended before 20 MB (\(c.maxBytes) bytes)")
                    return
                }
                if c.ok == nil {
                    line("cut_ms=>180000")
                    Issue.record("the copy did not return within 180 s")
                    return
                }
                let base = max(c.start, c.lastProgress ?? c.start)   // the later of the call's start and its last progress
                let cut = Self.ms(base, to: c.end)
                line("mb_at_cut=\(c.maxBytes / 1_000_000) cut_ms=\(cut) since_off_ms=\(Self.ms(t0, to: c.end)) detach_first=\(detachedBefore(c.end))")
                #expect(c.ok == false, "the copy must fail on a dead link")
                #expect(cut <= 22_000, "a service-phase cut within 20 s + check")
                let st = c.state
                await afterCut(failedAt: c.end, late: { st.completions - 1 })
            }
        }

        // MARK: V3c

        /// USB reads stay healthy while a Wi-Fi lane copies, and while that lane's link dies (D14).
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        @MainActor
        func liveCanaryIPhoneWifiUsbConcurrent() async {
            let transport = MobileDeviceTransport.shared
            let box = Self.box
            func line(_ s: String) { print("liveWifiUsb \(s)") }

            // 1. both links up, same phone?
            Self.startTransport()
            let haveUsb = await Self.wait(30) { box.events.contains { $0.link == .usb } }
            guard haveUsb, let u = box.events.first(where: { $0.link == .usb })?.handle else {
                Issue.record("no USB attach within 30 s (cable IN, phone unlocked)")
                return
            }
            guard await Self.waitWifiAttach(after: 0, cap: 30) != nil else {
                line("wifi=none")
                return
            }
            // Another Apple device on the network may attach first: give every Wi-Fi device 5 s to attach,
            // then pick the one with the cabled phone's UDID (compared in memory, never printed).
            try? await Task.sleep(for: .seconds(5))
            let usbSnap = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<IPhoneSnapshot, IPhoneReadError>) -> Void) in
                transport.readSnapshot(u, includeBattery: false, completion: done)
            }
            guard case .success(let us)? = usbSnap.value else {
                Issue.record("snapshot failed: usb=\(Self.describe(usbSnap.value))")
                return
            }
            var wifiHandles: [IPhoneHandle] = []
            for e in box.events where e.link == .wifi && !wifiHandles.contains(e.handle) { wifiHandles.append(e.handle) }
            var match: IPhoneHandle?
            for cand in wifiHandles {
                let snap = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<IPhoneSnapshot, IPhoneReadError>) -> Void) in
                    transport.readSnapshot(cand, includeBattery: false, completion: done)
                }
                if case .success(let ws)? = snap.value, ws.udid == us.udid { match = cand; break }
            }
            let same = match != nil
            let w = match ?? wifiHandles[0]
            line("wifi=\(same ? "same" : "other")")

            guard let ips = await Self.largestIps(w) else {
                Issue.record("no .ips of at most 2 MB on the Wi-Fi device")
                return
            }

            // 2. healthy, 60 s: a USB battery loop next to a Wi-Fi copy loop
            struct Loop { var count = 0; var maxMs = 0; var failures = 0 }
            let end = ContinuousClock.now + .seconds(60)
            let usbTask = Task { @MainActor () -> Loop in
                var l = Loop()
                while ContinuousClock.now < end {
                    let r = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<BatteryDetail?, IPhoneReadError>) -> Void) in
                        transport.readBattery(u, completion: done)
                    }
                    l.count += 1
                    l.maxMs = max(l.maxMs, r.ms)
                    if case .success? = r.value {} else { l.failures += 1 }
                }
                return l
            }
            let wifiTask = Task { @MainActor () -> Loop in
                var l = Loop()
                while ContinuousClock.now < end {
                    let c = await Self.copyOnce(w, path: ips.path, size: ips.size, cap: 120)
                    l.count += 1
                    l.maxMs = max(l.maxMs, Self.ms(c.start, to: c.end))
                    if c.ok != true { l.failures += 1 }
                }
                return l
            }
            let usbLoop = await usbTask.value
            let wifiLoop = await wifiTask.value
            line("healthy usbReads=\(usbLoop.count) usbMaxMs=\(usbLoop.maxMs) wifiCopies=\(wifiLoop.count) wifiMaxMs=\(wifiLoop.maxMs)")
            #expect(usbLoop.failures == 0, "every USB read succeeds")
            #expect(wifiLoop.failures == 0, "every Wi-Fi copy succeeds")

            // 3. the Wi-Fi link dies while the cable stays in (same phone only)
            guard same else { return }
            let mark = box.events.count
            Self.action("turn the phone's Wi-Fi OFF now")
            let t0 = ContinuousClock.now
            let dropEnd = t0 + .seconds(90)
            var firstWifiQueued: ContinuousClock.Instant?
            let wifiPoster = Task { @MainActor in
                // One Wi-Fi battery read every 5 s; the lane's watchdog or usbmuxd ends them.
                while ContinuousClock.now < dropEnd {
                    if firstWifiQueued == nil { firstWifiQueued = .now }
                    transport.readBattery(w, completion: { _ in })
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            var dropReads = Loop()
            while ContinuousClock.now < dropEnd {
                let r = await Self.run(cap: 60) { (done: @escaping @MainActor (Result<BatteryDetail?, IPhoneReadError>) -> Void) in
                    transport.readBattery(u, completion: done)
                }
                dropReads.count += 1
                dropReads.maxMs = max(dropReads.maxMs, r.ms)
                if case .success? = r.value {} else {
                    dropReads.failures += 1
                    // Diagnosis aid: when and how a USB read failed during the drop, and what u/w saw so far.
                    let evs = box.events[mark...].map { "\($0.handle == u ? "u" : $0.handle == w ? "w" : "x"):\($0.link.map { "\($0)" } ?? "detach")" }
                    line("drop usbFail at_ms=\(Self.ms(t0)) ms=\(r.ms) result=\(Self.describe(r.value)) events=\(evs)")
                }
            }
            await wifiPoster.value
            line("drop usbReads=\(dropReads.count) usbMaxMsDuringDrop=\(dropReads.maxMs) failures=\(dropReads.failures)")
            #expect(dropReads.failures == 0, "every USB read succeeds while the Wi-Fi link dies")
            #expect(dropReads.maxMs <= 2 * usbLoop.maxMs + 500, "USB latency during the drop stays within 2x the healthy maximum + 500 ms")
            if let queued = firstWifiQueued,
               let ev = box.events[mark...].first(where: { $0.handle == w && $0.link == nil }) {
                let ms = Self.ms(queued, to: ev.at)
                line("drop wifiDetachedMs=\(ms) (since the first Wi-Fi job queued after OFF)")
                #expect(ms <= 45_000, ".detached(w) within 45 s of the first Wi-Fi job queued after OFF")
            } else {
                line("drop wifiDetachedMs=none")
                Issue.record("no .detached(w) after the Wi-Fi link died")
            }
            Self.action("turn the phone's Wi-Fi ON now")
        }
    }
}
