// Engine/MobileDeviceTransport.swift
// IPHONE-MODULE: the transport (USB, and Wi-Fi through usbmuxd since IPHONE-WIFI) to a paired iPhone, through Apple's private
// MobileDevice.framework bound at runtime with dlopen/dlsym (the failure model of
// ThermalHIDReader.loadSymbols(): all symbols or none, never dlclose'd).
//
// READ-ONLY CONTRACT (R10, amended by DEVICE-ARCHIVE-CLEANUP). This file never writes, renames, pairs, unpairs,
// sets a value, restarts/shuts down/sleeps the phone or moves crash logs. It deletes exactly one kind of file: a
// sysdiagnose archive the app itself requested, through the ONE AFC remove call site `AFCSession.removeOwnArchive`,
// which refuses every path `SysdiagnoseDir.isOwnArchivePath` rejects; the model calls it only after a full import
// of a claimed archive (SPEC.md §1 item 6, row 9). It has exactly one AFC file-open call site (`openReadOnly`),
// with the mode literal 1 (read-only). The only diagnostics_relay requests are the shapes `IPhoneData.relayMessage`
// can build. Gates G1-G4: specs/DEVICE-ARCHIVE-CLEANUP.md § Verification (while open), then the CHANGELOG entry.
//
// Not covered by tests: private framework, app-only (same as ThermalHIDReader).
// The pure parts (relay request shapes, value extraction, key hashing) are in
// IPhoneData.swift, which Checks cover.
//
// Threading (D2): EVERY framework call runs on ONE dedicated parked-run-loop thread,
// because session reads block for seconds and the subscription delivers its callbacks on
// the subscribing thread's run loop. Results return to the caller on the main thread.
// Device pointers and the subscription are touched only on that thread, so detach events
// cannot release a device while a read is using it (reads and callbacks are serialised).
// Device jobs are queued by urgency through `IPhoneJobRunner` and still run one at a time on that thread.
// IPHONE-WIFI D14: a Wi-Fi device's jobs run on its own lane (IPhoneWifiLane: one serial queue per device, own urgency
// queue, own watchdog). Discovery and USB jobs stay on this thread. A Wi-Fi job never touches the thread-confined state
// below; it uses its lane's retained device.

import Foundation

/// Opaque device handle handed to the model: the AMDevice pointer's address.
struct IPhoneHandle: Hashable {
    let raw: Int
}

enum IPhoneTransportEvent {
    case attached(IPhoneHandle, IPhoneLink = .usb)
    case detached(IPhoneHandle)
}

enum IPhoneReadError: Error, Equatable {
    case unavailable
    case gone
    case needsTrust
    case failed(step: String, code: Int32)
}

/// Identity read of a connected phone. `udid` is used by the model only to compute the
/// device key and is never stored (R13).
struct IPhoneSnapshot {
    var udid: String
    var name: String
    var marketingName: String?
    var productType: String?
    var osVersion: String?
    var build: String?
    var enclosureColor: String?
    var battery: BatteryDetail?
    /// False when the read skipped the battery on purpose (auto-read off); the Battery card then says so
    /// instead of «no data».
    var batteryRead: Bool = true
}

final class MobileDeviceTransport: @unchecked Sendable {
    static let shared = MobileDeviceTransport()

    typealias Ptr = UnsafeMutableRawPointer

    // MARK: - C signatures (verified by IPHONE-SPIKE)

    private typealias NotifCb = @convention(c) (Ptr?, Ptr?) -> Void
    private typealias SubscribeFn = @convention(c) (NotifCb, UInt32, UInt32, Ptr?, UnsafeMutablePointer<Ptr?>) -> Int32
    private typealias UnsubscribeFn = @convention(c) (Ptr?) -> Int32
    private typealias DevFn = @convention(c) (Ptr?) -> Int32
    private typealias CopyValueFn = @convention(c) (Ptr?, CFString?, CFString?) -> Unmanaged<CFTypeRef>?
    private typealias SecureStartFn = @convention(c) (Ptr?, CFString, CFDictionary?, UnsafeMutablePointer<Ptr?>) -> Int32
    private typealias SendMsgFn = @convention(c) (Ptr?, CFTypeRef, Int) -> Int32
    private typealias RecvMsgFn = @convention(c) (Ptr?, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>, UnsafeMutablePointer<Int>) -> Int32
    private typealias GetSocketFn = @convention(c) (Ptr?) -> Int32
    private typealias GetCtxFn = @convention(c) (Ptr?) -> Ptr?
    private typealias InvalidateFn = @convention(c) (Ptr?) -> Void
    private typealias AfcOpenFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Ptr?>) -> Int32
    private typealias AfcSetCtxFn = @convention(c) (Ptr?, Ptr?) -> Void
    private typealias AfcCloseFn = @convention(c) (Ptr?) -> Int32
    private typealias AfcPathOpenFn = @convention(c) (Ptr?, UnsafePointer<CChar>, UnsafeMutablePointer<Ptr?>) -> Int32
    private typealias AfcDirReadFn = @convention(c) (Ptr?, Ptr?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
    private typealias AfcHandleCloseFn = @convention(c) (Ptr?, Ptr?) -> Int32
    private typealias AfcKVReadFn = @convention(c) (Ptr?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
    private typealias AfcKVCloseFn = @convention(c) (Ptr?) -> Int32
    private typealias AfcFileOpenFn = @convention(c) (Ptr?, UnsafePointer<CChar>, UInt64, UnsafeMutablePointer<Ptr?>) -> Int32
    /// `len` is a size_t in/out slot: a 4-byte slot let the framework read 4 stray stack bytes as the
    /// high half of the requested length (seen in a debug build: every file over the buffer size came back whole).
    private typealias AfcFileReadFn = @convention(c) (Ptr?, Ptr?, Ptr?, UnsafeMutablePointer<UInt>) -> Int32
    private typealias AfcRemoveFn = @convention(c) (Ptr?, UnsafePointer<CChar>) -> Int32

    /// Every function this block uses, resolved all-or-nothing (R16).
    private struct Syms {
        let subscribe: SubscribeFn
        let unsubscribe: UnsubscribeFn
        let connect: DevFn
        let isPaired: DevFn
        let validatePairing: DevFn
        let startSession: DevFn
        let stopSession: DevFn
        let disconnect: DevFn
        let getInterfaceType: DevFn
        let copyValue: CopyValueFn
        let secureStart: SecureStartFn
        let sendMsg: SendMsgFn
        let recvMsg: RecvMsgFn
        let getSocket: GetSocketFn
        let getSecureCtx: GetCtxFn
        let invalidate: InvalidateFn
        let afcConnOpen: AfcOpenFn
        let afcSetSecureCtx: AfcSetCtxFn
        let afcConnClose: AfcCloseFn
        let afcDirOpen: AfcPathOpenFn
        let afcFileInfoOpen: AfcPathOpenFn
        let afcDirRead: AfcDirReadFn
        let afcDirClose: AfcHandleCloseFn
        let afcKVRead: AfcKVReadFn
        let afcKVClose: AfcKVCloseFn
        let afcFileRefOpen: AfcFileOpenFn
        let afcFileRefRead: AfcFileReadFn
        let afcFileRefClose: AfcHandleCloseFn
        /// Optional (DEVICE-ARCHIVE-CLEANUP): its absence disables only the delete, never the transport.
        let afcRemovePath: AfcRemoveFn?
    }

    private static func loadSyms() -> Syms? {
        // The handle is intentionally NEVER dlclose()d: the resolved pointers must stay
        // valid for the whole process lifetime.
        guard let h = dlopen("/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
                             RTLD_LAZY) else { return nil }
        // dlsym takes the UNMANGLED name (no leading underscore).
        guard let subscribe = dlsym(h, "AMDeviceNotificationSubscribe"),
              let unsubscribe = dlsym(h, "AMDeviceNotificationUnsubscribe"),
              let connect = dlsym(h, "AMDeviceConnect"),
              let isPaired = dlsym(h, "AMDeviceIsPaired"),
              let validatePairing = dlsym(h, "AMDeviceValidatePairing"),
              let startSession = dlsym(h, "AMDeviceStartSession"),
              let stopSession = dlsym(h, "AMDeviceStopSession"),
              let disconnect = dlsym(h, "AMDeviceDisconnect"),
              let getInterfaceType = dlsym(h, "AMDeviceGetInterfaceType"),
              let copyValue = dlsym(h, "AMDeviceCopyValue"),
              let secureStart = dlsym(h, "AMDeviceSecureStartService"),
              let sendMsg = dlsym(h, "AMDServiceConnectionSendMessage"),
              let recvMsg = dlsym(h, "AMDServiceConnectionReceiveMessage"),
              let getSocket = dlsym(h, "AMDServiceConnectionGetSocket"),
              let getSecureCtx = dlsym(h, "AMDServiceConnectionGetSecureIOContext"),
              let invalidate = dlsym(h, "AMDServiceConnectionInvalidate"),
              let afcConnOpen = dlsym(h, "AFCConnectionOpen"),
              let afcSetSecureCtx = dlsym(h, "AFCConnectionSetSecureContext"),
              let afcConnClose = dlsym(h, "AFCConnectionClose"),
              let afcDirOpen = dlsym(h, "AFCDirectoryOpen"),
              let afcFileInfoOpen = dlsym(h, "AFCFileInfoOpen"),
              let afcDirRead = dlsym(h, "AFCDirectoryRead"),
              let afcDirClose = dlsym(h, "AFCDirectoryClose"),
              let afcKVRead = dlsym(h, "AFCKeyValueRead"),
              let afcKVClose = dlsym(h, "AFCKeyValueClose"),
              let afcFileRefOpen = dlsym(h, "AFCFileRefOpen"),
              let afcFileRefRead = dlsym(h, "AFCFileRefRead"),
              let afcFileRefClose = dlsym(h, "AFCFileRefClose")
        else { return nil }   // partial resolution => the whole set fails closed
        let afcRemove = dlsym(h, "AFCRemovePath")

        return Syms(
            subscribe: unsafeBitCast(subscribe, to: SubscribeFn.self),
            unsubscribe: unsafeBitCast(unsubscribe, to: UnsubscribeFn.self),
            connect: unsafeBitCast(connect, to: DevFn.self),
            isPaired: unsafeBitCast(isPaired, to: DevFn.self),
            validatePairing: unsafeBitCast(validatePairing, to: DevFn.self),
            startSession: unsafeBitCast(startSession, to: DevFn.self),
            stopSession: unsafeBitCast(stopSession, to: DevFn.self),
            disconnect: unsafeBitCast(disconnect, to: DevFn.self),
            getInterfaceType: unsafeBitCast(getInterfaceType, to: DevFn.self),
            copyValue: unsafeBitCast(copyValue, to: CopyValueFn.self),
            secureStart: unsafeBitCast(secureStart, to: SecureStartFn.self),
            sendMsg: unsafeBitCast(sendMsg, to: SendMsgFn.self),
            recvMsg: unsafeBitCast(recvMsg, to: RecvMsgFn.self),
            getSocket: unsafeBitCast(getSocket, to: GetSocketFn.self),
            getSecureCtx: unsafeBitCast(getSecureCtx, to: GetCtxFn.self),
            invalidate: unsafeBitCast(invalidate, to: InvalidateFn.self),
            afcConnOpen: unsafeBitCast(afcConnOpen, to: AfcOpenFn.self),
            afcSetSecureCtx: unsafeBitCast(afcSetSecureCtx, to: AfcSetCtxFn.self),
            afcConnClose: unsafeBitCast(afcConnClose, to: AfcCloseFn.self),
            afcDirOpen: unsafeBitCast(afcDirOpen, to: AfcPathOpenFn.self),
            afcFileInfoOpen: unsafeBitCast(afcFileInfoOpen, to: AfcPathOpenFn.self),
            afcDirRead: unsafeBitCast(afcDirRead, to: AfcDirReadFn.self),
            afcDirClose: unsafeBitCast(afcDirClose, to: AfcHandleCloseFn.self),
            afcKVRead: unsafeBitCast(afcKVRead, to: AfcKVReadFn.self),
            afcKVClose: unsafeBitCast(afcKVClose, to: AfcKVCloseFn.self),
            afcFileRefOpen: unsafeBitCast(afcFileRefOpen, to: AfcFileOpenFn.self),
            afcFileRefRead: unsafeBitCast(afcFileRefRead, to: AfcFileReadFn.self),
            afcFileRefClose: unsafeBitCast(afcFileRefClose, to: AfcHandleCloseFn.self),
            afcRemovePath: afcRemove.map { unsafeBitCast($0, to: AfcRemoveFn.self) })
    }

    // MARK: - State

    // @unchecked Sendable (SWIFT6-MODE D9): `syms`, `runner`, `laneLock`, `gateLock` are immutable (`runner` is itself @unchecked Sendable, IPhoneJobQueue.swift:52); `thread` is guarded by `threadLock` (in `onThread`); `lanes` by `laneLock`; `gateOn` and `eventHandler` by `gateLock`; `started`, `notification`, `devices`, `links`, `parked`, `lost` are touched only inside `onThread`/`enqueue` bodies and the subscription callback, all of which run on the one transport thread (header "Threading (D2)"). Results reach the caller through `onMain`.
    private let syms: Syms?
    /// false when the framework or any required symbol is missing (R16).
    var isAvailable: Bool { syms != nil }

    /// D7 live test only: the longest silence between completed steps on `h`'s lane since the last call, per phase.
    func takeWifiStepGaps(_ h: IPhoneHandle) -> (service: TimeInterval, lockdown: TimeInterval)? {
        laneLock.withLock { lanes[h.raw] }?.watchdog.takeLongestGaps()
    }

    /// Created on first use, so building the singleton (which `IPhoneModel`'s default
    /// argument does) starts no thread.
    private let threadLock = NSLock()
    private var thread: ParkedRunLoopThread?
    private let runner = IPhoneJobRunner()

    // Confined to the transport thread from here down (except `eventHandler` and `lanes`, see the comment above).
    /// Guarded by `gateLock` (D14: `laneDied` emits from a watchdog queue).
    private var eventHandler: (@MainActor (IPhoneTransportEvent) -> Void)?
    private var started = false
    private var notification: Ptr?
    /// Retained AMDevice objects by handle that the model knows about.
    private var devices: [Int: Ptr] = [:]
    /// Link of every handle in `devices`.
    private var links: [Int: IPhoneLink] = [:]
    /// Network devices held while «Connect over Wi-Fi» is off: retained, never reported, no job runs on them (D1).
    private var parked: [Int: Ptr] = [:]
    /// D7: Wi-Fi devices whose lane died: retained until usbmuxd detaches them or «Search again»; the model was told.
    private var lost: [Int: Ptr] = [:]
    /// D14: the lane of every reported Wi-Fi device, by handle. Guarded by `laneLock` (read by `submit` on any thread).
    private let laneLock = NSLock()
    private var lanes: [Int: IPhoneWifiLane] = [:]

    private let gateLock = NSLock()
    private var gateOn = false
    /// «Connect over Wi-Fi» as the transport sees it; set at once by `setNetworkEnabled`, read per chunk by long jobs.
    private var networkEnabled: Bool { gateLock.withLock { gateOn } }

    private init() {
        syms = Self.loadSyms()
    }

    /// Runs `body` on the transport thread; false when the framework is unavailable.
    @discardableResult
    private func onThread(_ body: @escaping () -> Void) -> Bool {
        guard syms != nil else { return false }
        threadLock.lock()
        let t = thread ?? ParkedRunLoopThread(name: "app.moonport.mobiledevice")
        thread = t
        threadLock.unlock()
        return t.async(body)
    }

    /// Queues a device job by urgency (R1); false when the framework is unavailable.
    @discardableResult
    private func enqueue(_ p: IPhoneJobPriority, _ body: @escaping () -> Void) -> Bool {
        guard syms != nil else { return false }
        return runner.enqueue(p, body) { self.onThread($0) }
    }

    /// D14: what a running job gets: its handle, its completion guard and, on a Wi-Fi lane, the lane.
    private struct JobContext {
        let h: IPhoneHandle
        let ticket: IPhoneJobTicket
        let lane: IPhoneWifiLane?
        var wd: IPhoneWifiWatchdog? { lane?.watchdog }
    }

    /// D14: queues a job for `h` on its Wi-Fi lane when it has one, else on the USB runner (this thread, today's path).
    /// `fail` is posted instead of the job's own end when nothing could be queued (`.unavailable`) or the lane closed
    /// under it (`.gone`); `sentBefore` says whether the job had already posted an intermediate result.
    private func submit(_ h: IPhoneHandle, _ p: IPhoneJobPriority,
                        fail: @escaping @MainActor (IPhoneReadError, _ sentBefore: Bool) -> Void,
                        _ work: @escaping (JobContext) -> Void) {
        let ticket = IPhoneJobTicket(fail: fail)
        if let lane = laneLock.withLock({ lanes[h.raw] }) {
            if !lane.enqueue(p, ticket, { t in work(JobContext(h: h, ticket: t, lane: lane)) }) { ticket.abandon(.gone) }
            return
        }
        if !enqueue(p, { work(JobContext(h: h, ticket: ticket, lane: nil)) }) { ticket.abandon(.unavailable) }
    }

    /// A Wi-Fi job stops at its next step: lane closed or «Connect over Wi-Fi» off (D6). Never true on USB.
    private func stopped(_ ctx: JobContext) -> Bool { ctx.lane.map { $0.isClosed || !networkEnabled } ?? false }

    /// The header loop yields to a more urgent job of the same runner or lane.
    private func morePressing(_ ctx: JobContext) -> Bool {
        ctx.lane?.hasPending(moreUrgentThan: .background) ?? runner.hasPending(moreUrgentThan: .background)
    }

    private static func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }

    // MARK: - Discovery

    /// Idempotent. Subscribes once; attach/detach events arrive on the main actor.
    func start(networkEnabled: Bool = false, onEvent: @escaping @MainActor (IPhoneTransportEvent) -> Void) {
        gateLock.withLock { gateOn = networkEnabled }
        onThread { [self] in
            guard !started, let s = syms else { return }
            // Stays true even when subscribe fails: restartDiscovery ("Search again") is the retry and needs it.
            started = true
            gateLock.withLock { eventHandler = onEvent }
            notification = subscribe(s)
        }
    }

    /// IPHONE-WIFI: «Connect over Wi-Fi» changed. Off: every Wi-Fi device is detached and parked. On: every parked
    /// device is reported. The flag flips at once (a running Wi-Fi copy stops at its next chunk); the device set changes
    /// on the transport thread after the running job.
    func setNetworkEnabled(_ on: Bool) {
        gateLock.withLock { gateOn = on }
        onThread { [self] in
            guard started, on == networkEnabled else { return }   // a later call flipped it back and queued its own block
            if on {
                // The model may have dropped these synchronously on an "off" whose block never ran (off-then-on).
                for (raw, link) in links where link == .wifi { emit(.attached(IPhoneHandle(raw: raw), .wifi)) }
                for (raw, dev) in parked {
                    devices[raw] = dev
                    links[raw] = .wifi
                    openLane(raw, dev)
                    emit(.attached(IPhoneHandle(raw: raw), .wifi))
                }
                parked.removeAll()
            } else {
                for (raw, link) in links where link == .wifi {
                    if let dev = devices.removeValue(forKey: raw) { parked[raw] = dev }
                    links[raw] = nil
                    emit(.detached(IPhoneHandle(raw: raw)))
                    closeLane(raw)
                }
            }
        }
    }

    /// Unsubscribe, report every known device as detached and release it, subscribe again.
    /// A no-op before `start`.
    func restartDiscovery() {
        onThread { [self] in
            guard started, let s = syms else { return }
            if let n = notification { _ = s.unsubscribe(n) }
            notification = nil
            for (raw, dev) in devices {
                emit(.detached(IPhoneHandle(raw: raw)))
                if links[raw] == .wifi { closeLane(raw) }
                Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).release()
            }
            devices.removeAll()
            for (_, dev) in parked { Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).release() }
            parked.removeAll()
            for (_, dev) in lost { Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).release() }
            lost.removeAll()
            links.removeAll()
            notification = subscribe(s)
        }
    }

    private func subscribe(_ s: Syms) -> Ptr? {
        // The C callback cannot capture context; it reaches the singleton directly.
        let cb: NotifCb = { info, _ in MobileDeviceTransport.shared.handleNotification(info) }
        var notif: Ptr?
        let rc = s.subscribe(cb, 0, 0, nil, &notif)
        return rc == 0 ? notif : nil
    }

    /// Runs on the transport thread (the subscribing thread's run loop). `info` is a struct
    /// with the device pointer at byte 0 and the message UInt32 at byte 8.
    private func handleNotification(_ info: Ptr?) {
        guard let info, let s = syms, let dev = info.load(as: Ptr?.self) else { return }
        let message = info.load(fromByteOffset: 8, as: UInt32.self)
        let handle = IPhoneHandle(raw: Int(bitPattern: dev))
        switch message {
        case 1:   // attached
            // R11 amended by IPHONE-WIFI: USB always, network only while the setting is on.
            guard devices[handle.raw] == nil, parked[handle.raw] == nil, lost[handle.raw] == nil else { return }
            switch IPhoneLinkPolicy.attach(interfaceType: s.getInterfaceType(dev), networkEnabled: networkEnabled) {
            case .ignore:
                return
            case .park:
                _ = Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).retain()
                parked[handle.raw] = dev
            case .report(let link):
                _ = Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).retain()
                devices[handle.raw] = dev
                links[handle.raw] = link
                if link == .wifi { openLane(handle.raw, dev) }
                emit(.attached(handle, link))
            }
        case 2:   // detached
            if let known = devices.removeValue(forKey: handle.raw) {
                let link = links.removeValue(forKey: handle.raw)
                emit(.detached(handle))
                if link == .wifi { closeLane(handle.raw) }
                Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(known)).release()
            } else if let known = parked.removeValue(forKey: handle.raw) {
                Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(known)).release()
            } else if let known = lost.removeValue(forKey: handle.raw) {
                // The model was told when the lane died: no event.
                Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(known)).release()
            }
        default:
            // Only 1 (attached) and 2 (detached) change the device set; any other message is ignored on purpose.
            break
        }
    }

    private func emit(_ event: IPhoneTransportEvent) {
        guard let handler = gateLock.withLock({ eventHandler }) else { return }
        Self.onMain { handler(event) }
    }

    /// D14: transport thread, right before a Wi-Fi device's `.attached` is posted. The lane takes its own +1 on `dev`.
    private func openLane(_ raw: Int, _ dev: Ptr) {
        _ = Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).retain()
        let lane = IPhoneWifiLane(raw: raw, retainedDev: dev) { [weak self] dead in self?.laneDied(dead) }
        let old = laneLock.withLock { () -> IPhoneWifiLane? in
            defer { lanes[raw] = lane }
            return lanes[raw]
        }
        old?.close()
    }

    /// D14: any thread, AFTER the caller posted the device's `.detached`: the lane leaves the table and closes, so its
    /// jobs' failures reach main after the detach.
    private func closeLane(_ raw: Int) {
        laneLock.withLock { lanes.removeValue(forKey: raw) }?.close()
    }

    /// D7: a lane's watchdog declared its link dead (watchdog queue). Detach first, then the lane's failures; the device
    /// bookkeeping follows on the transport thread. A lane that was already replaced or removed is only closed.
    private func laneDied(_ lane: IPhoneWifiLane) {
        let current = laneLock.withLock { () -> Bool in
            guard lanes[lane.raw] === lane else { return false }
            lanes[lane.raw] = nil
            return true
        }
        guard current else { lane.close(); return }
        emit(.detached(IPhoneHandle(raw: lane.raw)))
        lane.close()
        let raw = lane.raw
        onThread { [self] in
            // usbmuxd's detach or the setting may have removed it first.
            guard links[raw] == .wifi, let dev = devices.removeValue(forKey: raw) else { return }
            links[raw] = nil
            lost[raw] = dev
        }
    }

    // MARK: - Session

    /// A Wi-Fi job runs on its lane with the lane's retained device and never reads the thread-confined tables; a USB job
    /// runs here as before, and a Wi-Fi handle is refused here (D14).
    private func withSession<T>(_ ctx: JobContext, _ body: (Ptr) throws -> T) -> Result<T, IPhoneReadError> {
        guard let s = syms else { return .failure(.unavailable) }
        if let lane = ctx.lane {
            guard !stopped(ctx) else { return .failure(.gone) }
            return runSession(s, lane.dev, ctx.wd, body)
        }
        guard let dev = devices[ctx.h.raw], links[ctx.h.raw] != .wifi else { return .failure(.gone) }
        return runSession(s, dev, nil, body)
    }

    /// connect -> pairing check -> startSession -> body -> stopSession -> disconnect. `wd` (Wi-Fi only) hears every
    /// completed lockdown step (D7).
    private func runSession<T>(_ s: Syms, _ dev: Ptr, _ wd: IPhoneWifiWatchdog?,
                               _ body: (Ptr) throws -> T) -> Result<T, IPhoneReadError> {
        let c = s.connect(dev)
        wd?.progress()
        guard c == 0 else { return .failure(.failed(step: "connect", code: c)) }
        defer { _ = s.disconnect(dev) }
        if wd != nil {
            // D16: no Trust prompt exists over Wi-Fi (it needs the cable), so a failed check is a read failure.
            let paired = s.isPaired(dev)
            wd?.progress()
            guard paired == 1 else { return .failure(.failed(step: "isPaired", code: paired)) }
            let valid = s.validatePairing(dev)
            wd?.progress()
            guard valid == 0 else { return .failure(.failed(step: "validatePairing", code: valid)) }
        } else {
            guard s.isPaired(dev) == 1, s.validatePairing(dev) == 0 else { return .failure(.needsTrust) }
        }
        let st = s.startSession(dev)
        wd?.progress()
        guard st == 0 else { return .failure(.failed(step: "startSession", code: st)) }
        defer { _ = s.stopSession(dev) }   // runs before the disconnect above
        do {
            return .success(try body(dev))
        } catch let e as IPhoneReadError {
            return .failure(e)
        } catch {
            return .failure(.failed(step: "read", code: -1))
        }
    }

    /// A lockdown value; `domain` nil = default domain, `key` nil = the whole domain.
    private func copyValue(_ dev: Ptr, domain: String?, key: String?, _ wd: IPhoneWifiWatchdog?) -> Any? {
        guard let s = syms else { return nil }
        let value = s.copyValue(dev, domain as CFString?, key as CFString?)?.takeRetainedValue()
        wd?.progress()
        return value
    }

    private func lockdownString(_ dev: Ptr, _ key: String, _ wd: IPhoneWifiWatchdog?) -> String? {
        IPhoneData.stringValue(copyValue(dev, domain: nil, key: key, wd))
    }

    // MARK: - diagnostics_relay

    /// Starts the relay service, runs `body` with a function that sends one request and
    /// returns its reply (nil when the send or receive failed), then says Goodbye and
    /// invalidates. nil when the service did not start. Inside a session, transport thread only.
    private func withRelay<T>(_ dev: Ptr, _ wd: IPhoneWifiWatchdog?,
                              _ body: ((IPhoneRelayRequest) -> [String: Any]?) -> T) -> T? {
        guard let s = syms else { return nil }
        var conn: Ptr?
        guard s.secureStart(dev, "com.apple.mobile.diagnostics_relay" as CFString, nil, &conn) == 0,
              let conn else { return nil }
        wd?.progress()
        let fd = s.getSocket(conn)
        if fd >= 0 { wd?.watch(fd) }
        defer {
            _ = s.sendMsg(conn, IPhoneData.relayMessage(.goodbye) as CFDictionary, 200)
            if fd >= 0 { wd?.unwatch(fd) }   // before invalidate closes the fd (D7 fd handoff)
            s.invalidate(conn)
        }
        var broken = false
        return body { request in
            guard !broken else { return nil }
            guard s.sendMsg(conn, IPhoneData.relayMessage(request) as CFDictionary, 200) == 0 else { broken = true; return nil }
            var out: Unmanaged<CFTypeRef>?
            var format = 0
            guard s.recvMsg(conn, &out, &format) == 0 else { broken = true; return nil }
            wd?.progress()
            // takeUnretainedValue is the verified ownership; it may leak one reply per read.
            return out?.takeUnretainedValue() as? [String: Any]
        }
    }

    /// The battery registry payload: the `AppleSmartBattery` entry, completed from the `AppleSmartBatteryPack` and
    /// `AppleChargerData` class nodes when the entry lacks the live keys (iOS 27 moved temperature, voltage,
    /// amperage and the charger data there — IPHONE-BATTERY-DETAILS). One relay connection, one to three requests
    /// in order, all of the existing `IORegistry` shape (R10). nil when the service did not start or the main
    /// reply had no payload; a failed per-class request only leaves its keys missing.
    private func readBatteryPayload(_ dev: Ptr, _ wd: IPhoneWifiWatchdog?) -> [String: Any]? {
        withRelay(dev, wd) { send -> [String: Any]? in
            guard let main = IPhoneData.relayPayload(send(.ioRegistryName("AppleSmartBattery"))) else { return nil }
            guard IPhoneData.batteryNeedsPerClassQueries(main) else { return main }
            let pack = IPhoneData.relayPayload(send(.ioRegistryClass("AppleSmartBatteryPack")))
            let charger = IPhoneData.relayPayload(send(.ioRegistryClass("AppleChargerData")))
            return IPhoneData.mergeBatteryPayloads(main: main, pack: pack, charger: charger)
        } ?? nil
    }

    // MARK: - Crash-log AFC (read-only)

    /// One AFC connection to the crash-report service. Transport thread only.
    private final class AFCSession {
        private let s: Syms
        private let afc: Ptr
        /// IPHONE-WIFI D7: tells the lane's watchdog a step completed; does nothing on USB.
        private let tick: () -> Void

        fileprivate init(_ s: Syms, _ afc: Ptr, tick: @escaping () -> Void) {
            self.s = s
            self.afc = afc
            self.tick = tick
        }

        /// Depth-first listing from "/", depth <= 8, skipping "." and "..".
        func list() -> [IPhoneAFCEntry] {
            var out: [IPhoneAFCEntry] = []
            walk("/", depth: 0, into: &out)
            return out
        }

        /// Entries directly in `dir`, no recursion and no header reads; nil when `dir` cannot be opened and its parent
        /// does not show it missing. A directory the parent lists as absent is empty (a phone that never made a
        /// sysdiagnose has no `/DiagnosticLogs/sysdiagnose`).
        func listDirectory(_ dir: String) -> [IPhoneAFCEntry]? {
            if let names = names(in: dir) {
                return names.compactMap { info(dir == "/" ? "/" + $0 : dir + "/" + $0) }
            }
            let parent = (dir as NSString).deletingLastPathComponent
            guard let siblings = names(in: parent.isEmpty ? "/" : parent) else { return nil }
            return siblings.contains((dir as NSString).lastPathComponent) ? nil : []
        }

        private func names(in dir: String) -> [String]? {
            var handle: Ptr?
            guard s.afcDirOpen(afc, dir, &handle) == 0, let handle else { return nil }
            defer { _ = s.afcDirClose(afc, handle) }
            var out: [String] = []
            while true {
                var name: UnsafeMutablePointer<CChar>?
                guard s.afcDirRead(afc, handle, &name) == 0, let name else { break }
                tick()
                let n = String(cString: name)
                if n != "." && n != ".." { out.append(n) }
            }
            return out
        }

        /// The ONLY AFC remove call site in the app (DEVICE-ARCHIVE-CLEANUP): one app-requested sysdiagnose archive,
        /// checked against its claimed size right before the remove and confirmed gone after it.
        func removeOwnArchive(path: String, expectedSize: Int64) -> PhoneCleanup {
            guard SysdiagnoseDir.isOwnArchivePath(path) else { return .failed(-1) }
            guard let remove = s.afcRemovePath else { return .unavailable }
            guard let e = info(path) else { return .alreadyGone }
            guard !e.isDirectory, e.size == expectedSize else { return .changed }
            let rc = remove(afc, path)
            guard rc == 0 else { return .failed(rc) }
            return info(path) == nil ? .deleted : .failed(0)
        }

        private func walk(_ dir: String, depth: Int, into out: inout [IPhoneAFCEntry]) {
            guard depth <= 8 else { return }
            var handle: Ptr?
            guard s.afcDirOpen(afc, dir, &handle) == 0, let handle else { return }
            var names: [String] = []
            while true {
                var name: UnsafeMutablePointer<CChar>?
                guard s.afcDirRead(afc, handle, &name) == 0, let name else { break }
                tick()
                let n = String(cString: name)
                if n != "." && n != ".." { names.append(n) }
            }
            _ = s.afcDirClose(afc, handle)
            for n in names {
                let path = dir == "/" ? "/" + n : dir + "/" + n
                guard let entry = info(path) else { continue }
                out.append(entry)
                if entry.isDirectory { walk(path, depth: depth + 1, into: &out) }
            }
        }

        func info(_ path: String) -> IPhoneAFCEntry? {
            var handle: Ptr?
            guard s.afcFileInfoOpen(afc, path, &handle) == 0, let handle else { return nil }
            tick()
            defer { _ = s.afcKVClose(handle) }
            var isDir = false, size: Int64 = 0, modified: Date?
            while true {
                var key: UnsafeMutablePointer<CChar>?
                var val: UnsafeMutablePointer<CChar>?
                guard s.afcKVRead(handle, &key, &val) == 0, let key, let val else { break }
                let v = String(cString: val)
                switch String(cString: key) {
                case "st_ifmt": isDir = (v == "S_IFDIR")
                case "st_size": size = Int64(v) ?? 0
                case "st_mtime": modified = IPhoneData.date(fromAFCMtime: v)
                default: break
                }
            }
            return IPhoneAFCEntry(path: path, isDirectory: isDir, size: size, modified: modified)
        }

        /// The ONLY AFC file-open call site in the app (R10): mode 1 = read-only. `rc` gets the framework's return code.
        private func openReadOnly(_ path: String, rc: inout Int32) -> Ptr? {
            var ref: Ptr?
            rc = s.afcFileRefOpen(afc, path, 1, &ref)
            guard rc == 0 else { return nil }
            return ref
        }

        /// Up to `limit` bytes from the start of `path` (fewer if the file is shorter); on failure the AFC step and the
        /// framework's return code (D18).
        func readPrefix(path: String, limit: Int) -> Result<Data, IPhoneHeaderReadFailure> {
            guard limit > 0 else { return .failure(.init(step: "limit", code: 0)) }
            var openRC: Int32 = 0
            guard let ref = openReadOnly(path, rc: &openRC) else { return .failure(.init(step: "open", code: openRC)) }
            defer { _ = s.afcFileRefClose(afc, ref) }
            var data = Data()
            var buf = [UInt8](repeating: 0, count: min(limit, 1 << 20))
            while data.count < limit {
                var len = UInt(min(buf.count, limit - data.count))
                let rc = buf.withUnsafeMutableBytes { s.afcFileRefRead(afc, ref, $0.baseAddress, &len) }
                guard rc == 0 else { return .failure(.init(step: "read", code: rc)) }
                if len == 0 { break }   // EOF
                data.append(contentsOf: buf[0..<Int(len)])
                tick()
            }
            return .success(data)
        }

        /// Copies `size` bytes of `path` to the local `url` (1 MiB reads), reporting bytes
        /// done. false on any read/write error or a short file; the caller removes `url`.
        func copy(path: String, size: Int64, to url: URL, shouldStop: () -> Bool = { false },
                  progress: (Int) -> Void) -> Bool {
            var openRC: Int32 = 0
            guard let ref = openReadOnly(path, rc: &openRC) else { return false }
            defer { _ = s.afcFileRefClose(afc, ref) }
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]),
                  let out = try? FileHandle(forWritingTo: url) else { return false }
            defer { try? out.close() }
            var buf = [UInt8](repeating: 0, count: 1 << 20)
            var total: Int64 = 0
            while total < size {
                if shouldStop() { return false }
                var len = UInt(buf.count)
                let rc = buf.withUnsafeMutableBytes { s.afcFileRefRead(afc, ref, $0.baseAddress, &len) }
                guard rc == 0, len > 0 else { return false }
                do { try out.write(contentsOf: Data(buf[0..<Int(len)])) } catch { return false }
                total += Int64(len)
                tick()
                progress(Int(total))
            }
            return true
        }
    }

    /// Opens the crash-report AFC service inside a session and runs `body`; nil when the
    /// service or the AFC connection cannot be opened. Transport thread only.
    private func withCrashAFC<T>(_ dev: Ptr, _ wd: IPhoneWifiWatchdog?, _ body: (AFCSession) -> T) -> T? {
        guard let s = syms else { return nil }
        var cc: Ptr?
        guard s.secureStart(dev, "com.apple.crashreportcopymobile" as CFString, nil, &cc) == 0,
              let cc else { return nil }
        wd?.progress()
        defer { s.invalidate(cc) }
        let fd = s.getSocket(cc)
        var afc: Ptr?
        guard s.afcConnOpen(fd, 0, &afc) == 0, let afc else { return nil }
        defer { _ = s.afcConnClose(afc) }
        if let ctx = s.getSecureCtx(cc) { s.afcSetSecureCtx(afc, ctx) }
        if fd >= 0 { wd?.watch(fd) }
        defer { if fd >= 0 { wd?.unwatch(fd) } }   // declared last, so it runs first: before afcConnClose and invalidate
        return body(AFCSession(s, afc, tick: { wd?.progress() }))
    }

    // MARK: - Public async API (runs on the transport thread, completes on main)

    /// Identity keys + the AppleSmartBattery registry entry. `battery` is nil when the
    /// relay did not answer with Status Success, or when `includeBattery` is false (then `batteryRead` is false).
    /// On iOS 27 the live keys come from the per-class nodes (`readBatteryPayload`).
    func readSnapshot(_ h: IPhoneHandle,
                      includeBattery: Bool = true,
                      completion: @escaping @MainActor (Result<IPhoneSnapshot, IPhoneReadError>) -> Void) {
        submit(h, .interactive, fail: { e, _ in completion(.failure(e)) }) { [self] ctx in
            let result = withSession(ctx) { dev -> IPhoneSnapshot in
                guard let udid = lockdownString(dev, "UniqueDeviceID", ctx.wd) else {
                    throw IPhoneReadError.failed(step: "UniqueDeviceID", code: 0)
                }
                var battery: BatteryDetail?
                if includeBattery {
                    battery = readBatteryPayload(dev, ctx.wd).map { BatteryInspector.parse(dict: $0) }
                }
                return IPhoneSnapshot(
                    udid: udid,
                    name: lockdownString(dev, "DeviceName", ctx.wd) ?? "iPhone",
                    marketingName: lockdownString(dev, "MarketingName", ctx.wd),
                    productType: lockdownString(dev, "ProductType", ctx.wd),
                    osVersion: lockdownString(dev, "ProductVersion", ctx.wd),
                    build: lockdownString(dev, "BuildVersion", ctx.wd),
                    enclosureColor: lockdownString(dev, "DeviceEnclosureColor", ctx.wd),
                    battery: battery,
                    batteryRead: includeBattery)
            }
            ctx.ticket.finish { completion(result) }
        }
    }

    /// IPHONE-LIVE-BATTERY: the battery registry payload only (no identity keys), parsed on the transport thread, at the
    /// snapshot's urgency. `.success(nil)` when the relay did not answer with a payload.
    func readBattery(_ h: IPhoneHandle,
                     completion: @escaping @MainActor (Result<BatteryDetail?, IPhoneReadError>) -> Void) {
        submit(h, .interactive, fail: { e, _ in completion(.failure(e)) }) { [self] ctx in
            let result = withSession(ctx) { dev -> BatteryDetail? in
                readBatteryPayload(dev, ctx.wd).map { BatteryInspector.parse(dict: $0) }
            }
            ctx.ticket.finish { completion(result) }
        }
    }

    /// Identity and parts without storage (read by `readStorage`): lockdown keys and registry entries
    /// over one relay connection. Values are returned to the caller only; nothing is stored or logged here.
    func readIdentity(_ h: IPhoneHandle, language: AppLanguage,
                      completion: @escaping @MainActor (Result<[IPhoneIdentityField], IPhoneReadError>) -> Void) {
        submit(h, .interactive, fail: { e, _ in completion(.failure(e)) }) { [self] ctx in
            let result = withSession(ctx) { dev -> [IPhoneIdentityField] in
                var lockdown: [String: Any] = [:]
                for key in ["MarketingName", "ModelNumber", "RegionInfo", "RegulatoryModelNumber",
                            "HardwareModel", "ProductVersion", "BuildVersion", "DeviceEnclosureColor",
                            "DeviceColor", "SerialNumber", "MLBSerialNumber",
                            "InternationalMobileEquipmentIdentity", "InternationalMobileEquipmentIdentity2"] {
                    if let v = copyValue(dev, domain: nil, key: key, ctx.wd) { lockdown[key] = v }
                }
                let payloads = withRelay(dev, ctx.wd) { send -> [[String: Any]?] in
                    let battery = IPhoneData.relayPayload(send(.ioRegistryName("AppleSmartBattery")))
                    let panel = IPhoneData.relayPayload(send(.ioRegistryClass("AppleCLCD2")))
                    let product = IPhoneData.relayPayload(send(.ioRegistryName("product")))
                    var camera: [String: Any]?
                    for cls in ["AppleH16CamIn", "AppleH17CamIn", "AppleH18CamIn", "AppleH13CamIn"] {
                        camera = IPhoneData.relayPayload(send(.ioRegistryClass(cls)))
                        if camera != nil { break }
                    }
                    return [battery, panel, product, camera]
                } ?? [nil, nil, nil, nil]
                return IPhoneData.identityFields(lockdown: lockdown, diskUsage: nil, battery: payloads[0],
                                                 panel: payloads[1], product: payloads[2], camera: payloads[3],
                                                 language: language)
            }
            ctx.ticket.finish { completion(result) }
        }
    }

    /// `TotalDiskCapacity` in bytes, in its own job at the lowest urgency (R5). `onStart` is posted to
    /// main when the job begins (the model's 2 s deadline counts from then). The call can block for
    /// up to ~20 s on a phone-side stall (findings C5); only jobs queued after it wait.
    func readStorage(_ h: IPhoneHandle,
                     onStart: @escaping @MainActor () -> Void,
                     completion: @escaping @MainActor (Result<Int64?, IPhoneReadError>) -> Void) {
        submit(h, .last, fail: { e, _ in completion(.failure(e)) }) { [self] ctx in
            ctx.ticket.send { onStart() }
            let result = withSession(ctx) { dev -> Int64? in
                IPhoneData.storageBytes(diskUsage: copyValue(dev, domain: "com.apple.disk_usage", key: nil, ctx.wd) as? [String: Any])
            }
            ctx.ticket.finish { completion(result) }
        }
    }

    /// Walks the crash-log tree and posts the listing at once (`onListing`, R2), then reads the
    /// headers of files not in `knownHeaders` (cache key → parsed header) in the same session, posting `onTypes` per batch.
    /// The read loop yields to any more urgent job; the rest is queued at `.background` (D5, D6).
    func listLogs(_ h: IPhoneHandle, knownHeaders: [String: IPhoneLogHeader],
                  onListing: @escaping @MainActor (Result<IPhoneLogListing, IPhoneReadError>) -> Void,
                  onTypes: @escaping @MainActor (IPhoneLogTypeBatch) -> Void) {
        // IPHONE-WIFI D14: when the lane closes after the listing went out, the header keys not yet reported must still
        // reach the model as `failed`, so no row stays `.pending`. Every batch of this chain goes through `tracked`.
        let tracker = PendingTypeKeys()
        let tracked: @MainActor (IPhoneLogTypeBatch) -> Void = { b in
            var b = b
            b.failed = tracker.keep(b.failed)   // a key already reported stays out of a second batch
            tracker.remove(Set(b.read.keys).union(b.failed))
            if !b.isEmpty { onTypes(b) }
        }
        submit(h, .user, fail: { e, sent in
            if !sent {
                onListing(.failure(e))
            } else {
                var b = IPhoneLogTypeBatch()
                b.failed = tracker.all
                tracked(b)
            }
        }) { [self] ctx in
            var posted = false
            let result = withSession(ctx) { dev -> Void in
                let walked: Bool? = withCrashAFC(dev, ctx.wd) { afc -> Bool in
                    let (listing, pending) = IPhoneLogTypes.split(afc.list(), known: knownHeaders)
                    let keys = Set(pending.map { IPhoneData.logCacheKey(path: $0.path, size: $0.size, modified: $0.modified) })
                    ctx.ticket.send { tracker.set(keys); onListing(.success(listing)) }
                    posted = true
                    finishTypes(ctx, afc, pending[...], tracked)
                    return true
                }
                guard walked != nil else { throw IPhoneReadError.failed(step: "crashreportcopymobile", code: 0) }
            }
            if case .failure(let err) = result, !posted {
                ctx.ticket.finish { onListing(.failure(err)) }
            } else {
                ctx.ticket.finish {}
            }
        }
    }

    /// The header keys of one `listLogs` chain that no batch has reported yet (read from main closures and the lane).
    private final class PendingTypeKeys: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: Set<String> = []
        func set(_ k: Set<String>) { lock.withLock { keys = k } }
        var all: Set<String> { lock.withLock { keys } }
        func keep(_ k: Set<String>) -> Set<String> { lock.withLock { k.intersection(keys) } }
        func remove(_ k: Set<String>) { lock.withLock { keys.subtract(k) } }
    }

    /// Reads headers in order until done, stopped, or a more urgent job waits; retries this batch's failures once (D18);
    /// posts the batch and queues the rest at `.background`. Inside a crash-AFC session, on the job's runner or lane.
    private func finishTypes(_ ctx: JobContext, _ afc: AFCSession, _ files: ArraySlice<IPhoneAFCEntry>,
                             _ onTypes: @escaping @MainActor (IPhoneLogTypeBatch) -> Void) {
        func readHeader(_ f: IPhoneAFCEntry) -> Result<Data, IPhoneHeaderReadFailure> {
            let head = afc.readPrefix(path: f.path, limit: 4096)
            if case .success(let d) = head, f.size > 4096, !d.contains(0x0A) {
                return afc.readPrefix(path: f.path, limit: 65536)
            }
            return head
        }
        var batch = IPhoneLogTypeBatch()
        var rest = files
        var retry: [(entry: IPhoneAFCEntry, key: String, first: IPhoneHeaderReadFailure)] = []
        while let f = rest.first {
            if stopped(ctx) || morePressing(ctx) { break }
            rest = rest.dropFirst()
            let key = IPhoneData.logCacheKey(path: f.path, size: f.size, modified: f.modified)
            switch readHeader(f) {
            case .success(let head): batch.read[key] = IPhoneCrashLog.logHeader(fromHeader: head)
            case .failure(let e): retry.append((f, key, e))
            }
        }
        // D18: one more try, same session. A key still failing is reported failed (not cached, read again next listing).
        for r in retry {
            switch stopped(ctx) ? .failure(r.first) : readHeader(r.entry) {
            case .success(let head):
                batch.read[r.key] = IPhoneCrashLog.logHeader(fromHeader: head)
                batch.recovered.insert(r.key)
            case .failure(let e):
                batch.failed.insert(r.key)
                batch.failures[r.key] = e
            }
        }
        let done = batch
        if !done.isEmpty { ctx.ticket.send { onTypes(done) } }
        guard !rest.isEmpty else { return }
        let remaining = Array(rest)
        if stopped(ctx) {
            ctx.ticket.send { onTypes(Self.failedBatch(remaining)) }
            return
        }
        submit(ctx.h, .background, fail: { _, _ in onTypes(Self.failedBatch(remaining)) }) { [self] next in
            fillTypes(next, remaining, onTypes)
        }
    }

    /// The queued rest: own session + crash AFC, then `finishTypes`; a failed session or AFC open
    /// posts every key of `files` in `failed`.
    private func fillTypes(_ ctx: JobContext, _ files: [IPhoneAFCEntry],
                           _ onTypes: @escaping @MainActor (IPhoneLogTypeBatch) -> Void) {
        let result = withSession(ctx) { dev -> Bool in
            withCrashAFC(dev, ctx.wd) { afc -> Bool in
                finishTypes(ctx, afc, files[...], onTypes)
                return true
            } != nil
        }
        if case .success(true) = result {
            ctx.ticket.finish {}
        } else {
            ctx.ticket.finish { onTypes(Self.failedBatch(files)) }
        }
    }

    private static func failedBatch(_ files: [IPhoneAFCEntry]) -> IPhoneLogTypeBatch {
        var b = IPhoneLogTypeBatch()
        for f in files { b.failed.insert(IPhoneData.logCacheKey(path: f.path, size: f.size, modified: f.modified)) }
        return b
    }

    /// Copies one phone file (read-only) to `url`; `progress` gets bytes done, on main.
    func copyFile(_ h: IPhoneHandle, remotePath: String, size: Int64, to url: URL,
                  progress: @escaping @MainActor (Int) -> Void,
                  completion: @escaping @MainActor (Bool) -> Void) {
        submit(h, .user, fail: { _, _ in completion(false) }) { [self] ctx in
            let result = withSession(ctx) { dev -> Bool in
                withCrashAFC(dev, ctx.wd) { afc in
                    afc.copy(path: remotePath, size: size, to: url, shouldStop: { [self] in stopped(ctx) }) { done in
                        ctx.ticket.send { progress(done) }
                    }
                } ?? false
            }
            let ok: Bool
            if case .success(true) = result { ok = true } else { ok = false }
            ctx.ticket.finish { completion(ok) }
        }
    }

    /// Files directly in `/DiagnosticLogs/sysdiagnose` (DEVICE-ARCHIVE-CLEANUP request baseline and polling): one
    /// session, one directory read, no header reads. `.user` urgency: the user clicked and is waiting (Decision 8).
    func listSysdiagnoseDir(_ h: IPhoneHandle,
                            completion: @escaping @MainActor (Result<[IPhoneAFCEntry], IPhoneReadError>) -> Void) {
        submit(h, .user, fail: { e, _ in completion(.failure(e)) }) { [self] ctx in
            let result = withSession(ctx) { dev -> [IPhoneAFCEntry] in
                guard let listed = withCrashAFC(dev, ctx.wd, { $0.listDirectory(SysdiagnoseDir.path) }), let entries = listed else {
                    throw IPhoneReadError.failed(step: "crashreportcopymobile", code: 0)
                }
                return entries
            }
            ctx.ticket.finish { completion(result) }
        }
    }

    /// Deletes one app-requested archive (see `AFCSession.removeOwnArchive`); the size re-check and the remove are
    /// one job, so nothing runs between them. Completes on main.
    func removeOwnArchive(_ h: IPhoneHandle, path: String, expectedSize: Int64,
                          completion: @escaping @MainActor (PhoneCleanup) -> Void) {
        submit(h, .user, fail: { e, _ in completion(e == .unavailable ? .unavailable : .notConnected) }) { [self] ctx in
            let result = withSession(ctx) { dev -> PhoneCleanup in
                withCrashAFC(dev, ctx.wd) { $0.removeOwnArchive(path: path, expectedSize: expectedSize) } ?? .failed(0)
            }
            let outcome: PhoneCleanup
            switch result {
            case .success(let c): outcome = c
            case .failure(.failed(_, let code)): outcome = .failed(code)
            case .failure(.gone): outcome = .notConnected
            case .failure: outcome = .failed(0)
            }
            ctx.ticket.finish { completion(outcome) }
        }
    }
}
