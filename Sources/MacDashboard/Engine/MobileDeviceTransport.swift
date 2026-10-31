// Engine/MobileDeviceTransport.swift
// IPHONE-MODULE: the USB transport to a paired iPhone, through Apple's private
// MobileDevice.framework bound at runtime with dlopen/dlsym (the failure model of
// ThermalHIDReader.loadSymbols(): all symbols or none, never dlclose'd).
//
// READ-ONLY CONTRACT (R10). This file never writes, deletes, renames, pairs, unpairs,
// sets a value, restarts/shuts down/sleeps the phone or moves crash logs. It has exactly
// one AFC file-open call site (`openReadOnly`), with the mode literal 1 (read-only). The
// only diagnostics_relay requests are the shapes `IPhoneData.relayMessage` can build. The
// gate commands G1-G3 (forbidden-symbol grep, one-open-site count, request-string grep)
// are in the Verification section of the IPHONE-MODULE spec; run them after every change.
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

import Foundation

/// Opaque device handle handed to the model: the AMDevice pointer's address.
struct IPhoneHandle: Hashable {
    let raw: Int
}

enum IPhoneTransportEvent {
    case attached(IPhoneHandle)
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

final class MobileDeviceTransport {
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
            afcFileRefClose: unsafeBitCast(afcFileRefClose, to: AfcHandleCloseFn.self))
    }

    // MARK: - State

    private let syms: Syms?
    /// false when the framework or any required symbol is missing (R16).
    var isAvailable: Bool { syms != nil }

    /// Created on first use, so building the singleton (which `IPhoneModel`'s default
    /// argument does) starts no thread.
    private let threadLock = NSLock()
    private var thread: ParkedRunLoopThread?
    private let runner = IPhoneJobRunner()

    // Confined to the transport thread from here down.
    private var eventHandler: (@MainActor (IPhoneTransportEvent) -> Void)?
    private var started = false
    private var notification: Ptr?
    /// Retained AMDevice objects by handle (USB only).
    private var devices: [Int: Ptr] = [:]

    private init() {
        syms = Self.loadSyms()
    }

    /// Runs `body` on the transport thread; false when the framework is unavailable.
    @discardableResult
    private func onThread(_ body: @escaping () -> Void) -> Bool {
        guard syms != nil else { return false }
        threadLock.lock()
        let t = thread ?? ParkedRunLoopThread(name: "com.macdashboard.mobiledevice")
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

    private static func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }

    // MARK: - Discovery

    /// Idempotent. Subscribes once; attach/detach events arrive on the main actor.
    func start(onEvent: @escaping @MainActor (IPhoneTransportEvent) -> Void) {
        onThread { [self] in
            guard !started, let s = syms else { return }
            // Stays true even when subscribe fails: restartDiscovery («Искать снова») is the retry and needs it.
            started = true
            eventHandler = onEvent
            notification = subscribe(s)
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
                Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).release()
            }
            devices.removeAll()
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
            // R11: USB only. Interface type 1 = USB, 2 = network (ignored).
            guard s.getInterfaceType(dev) == 1, devices[handle.raw] == nil else { return }
            _ = Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).retain()
            devices[handle.raw] = dev
            emit(.attached(handle))
        case 2:   // detached
            guard let known = devices.removeValue(forKey: handle.raw) else { return }
            emit(.detached(handle))
            Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(known)).release()
        default:
            // Only 1 (attached) and 2 (detached) change the device set; any other message is ignored on purpose.
            break
        }
    }

    private func emit(_ event: IPhoneTransportEvent) {
        guard let handler = eventHandler else { return }
        Self.onMain { handler(event) }
    }

    // MARK: - Session

    /// connect -> isPaired == 1 -> validatePairing == 0 -> startSession -> body ->
    /// stopSession -> disconnect. Transport thread only.
    private func withSession<T>(_ h: IPhoneHandle, _ body: (Ptr) throws -> T) -> Result<T, IPhoneReadError> {
        guard let s = syms else { return .failure(.unavailable) }
        guard let dev = devices[h.raw] else { return .failure(.gone) }
        let c = s.connect(dev)
        guard c == 0 else { return .failure(.failed(step: "connect", code: c)) }
        defer { _ = s.disconnect(dev) }
        guard s.isPaired(dev) == 1, s.validatePairing(dev) == 0 else { return .failure(.needsTrust) }
        let st = s.startSession(dev)
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
    private func copyValue(_ dev: Ptr, domain: String?, key: String?) -> Any? {
        guard let s = syms else { return nil }
        return s.copyValue(dev, domain as CFString?, key as CFString?)?.takeRetainedValue()
    }

    private func lockdownString(_ dev: Ptr, _ key: String) -> String? {
        IPhoneData.stringValue(copyValue(dev, domain: nil, key: key))
    }

    // MARK: - diagnostics_relay

    /// Starts the relay service, runs `body` with a function that sends one request and
    /// returns its reply (nil when the send or receive failed), then says Goodbye and
    /// invalidates. nil when the service did not start. Inside a session, transport thread only.
    private func withRelay<T>(_ dev: Ptr, _ body: ((IPhoneRelayRequest) -> [String: Any]?) -> T) -> T? {
        guard let s = syms else { return nil }
        var conn: Ptr?
        guard s.secureStart(dev, "com.apple.mobile.diagnostics_relay" as CFString, nil, &conn) == 0,
              let conn else { return nil }
        defer {
            _ = s.sendMsg(conn, IPhoneData.relayMessage(.goodbye) as CFDictionary, 200)
            s.invalidate(conn)
        }
        var broken = false
        return body { request in
            guard !broken else { return nil }
            guard s.sendMsg(conn, IPhoneData.relayMessage(request) as CFDictionary, 200) == 0 else { broken = true; return nil }
            var out: Unmanaged<CFTypeRef>?
            var format = 0
            guard s.recvMsg(conn, &out, &format) == 0 else { broken = true; return nil }
            // takeUnretainedValue is the verified ownership; it may leak one reply per read.
            return out?.takeUnretainedValue() as? [String: Any]
        }
    }

    /// One relay connection, each request in order; nil replies for failures.
    private func relay(_ dev: Ptr, _ requests: [IPhoneRelayRequest]) -> [[String: Any]?] {
        withRelay(dev) { send in requests.map { send($0) } } ?? [[String: Any]?](repeating: nil, count: requests.count)
    }

    // MARK: - Crash-log AFC (read-only)

    /// One AFC connection to the crash-report service. Transport thread only.
    private final class AFCSession {
        private let s: Syms
        private let afc: Ptr

        fileprivate init(_ s: Syms, _ afc: Ptr) {
            self.s = s
            self.afc = afc
        }

        /// Depth-first listing from "/", depth <= 8, skipping "." and "..".
        func list() -> [IPhoneAFCEntry] {
            var out: [IPhoneAFCEntry] = []
            walk("/", depth: 0, into: &out)
            return out
        }

        private func walk(_ dir: String, depth: Int, into out: inout [IPhoneAFCEntry]) {
            guard depth <= 8 else { return }
            var handle: Ptr?
            guard s.afcDirOpen(afc, dir, &handle) == 0, let handle else { return }
            var names: [String] = []
            while true {
                var name: UnsafeMutablePointer<CChar>?
                guard s.afcDirRead(afc, handle, &name) == 0, let name else { break }
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

        private func info(_ path: String) -> IPhoneAFCEntry? {
            var handle: Ptr?
            guard s.afcFileInfoOpen(afc, path, &handle) == 0, let handle else { return nil }
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

        /// The ONLY AFC file-open call site in the app (R10): mode 1 = read-only.
        private func openReadOnly(_ path: String) -> Ptr? {
            var ref: Ptr?
            guard s.afcFileRefOpen(afc, path, 1, &ref) == 0 else { return nil }
            return ref
        }

        /// Up to `limit` bytes from the start of `path` (fewer if the file is shorter).
        func readPrefix(path: String, limit: Int) -> Data? {
            guard limit > 0, let ref = openReadOnly(path) else { return nil }
            defer { _ = s.afcFileRefClose(afc, ref) }
            var data = Data()
            var buf = [UInt8](repeating: 0, count: min(limit, 1 << 20))
            while data.count < limit {
                var len = UInt(min(buf.count, limit - data.count))
                let rc = buf.withUnsafeMutableBytes { s.afcFileRefRead(afc, ref, $0.baseAddress, &len) }
                guard rc == 0 else { return nil }
                if len == 0 { break }   // EOF
                data.append(contentsOf: buf[0..<Int(len)])
            }
            return data
        }

        /// Copies `size` bytes of `path` to the local `url` (1 MiB reads), reporting bytes
        /// done. false on any read/write error or a short file; the caller removes `url`.
        func copy(path: String, size: Int64, to url: URL, progress: (Int) -> Void) -> Bool {
            guard let ref = openReadOnly(path) else { return false }
            defer { _ = s.afcFileRefClose(afc, ref) }
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]),
                  let out = try? FileHandle(forWritingTo: url) else { return false }
            defer { try? out.close() }
            var buf = [UInt8](repeating: 0, count: 1 << 20)
            var total: Int64 = 0
            while total < size {
                var len = UInt(buf.count)
                let rc = buf.withUnsafeMutableBytes { s.afcFileRefRead(afc, ref, $0.baseAddress, &len) }
                guard rc == 0, len > 0 else { return false }
                do { try out.write(contentsOf: Data(buf[0..<Int(len)])) } catch { return false }
                total += Int64(len)
                progress(Int(total))
            }
            return true
        }
    }

    /// Opens the crash-report AFC service inside a session and runs `body`; nil when the
    /// service or the AFC connection cannot be opened. Transport thread only.
    private func withCrashAFC<T>(_ dev: Ptr, _ body: (AFCSession) -> T) -> T? {
        guard let s = syms else { return nil }
        var cc: Ptr?
        guard s.secureStart(dev, "com.apple.crashreportcopymobile" as CFString, nil, &cc) == 0,
              let cc else { return nil }
        defer { s.invalidate(cc) }
        var afc: Ptr?
        guard s.afcConnOpen(s.getSocket(cc), 0, &afc) == 0, let afc else { return nil }
        defer { _ = s.afcConnClose(afc) }
        if let ctx = s.getSecureCtx(cc) { s.afcSetSecureCtx(afc, ctx) }
        return body(AFCSession(s, afc))
    }

    // MARK: - Public async API (runs on the transport thread, completes on main)

    /// Identity keys + the AppleSmartBattery registry entry. `battery` is nil when the
    /// relay did not answer with Status Success, or when `includeBattery` is false (then `batteryRead` is false).
    func readSnapshot(_ h: IPhoneHandle,
                      includeBattery: Bool = true,
                      completion: @escaping @MainActor (Result<IPhoneSnapshot, IPhoneReadError>) -> Void) {
        let queued = enqueue(.interactive) { [self] in
            let result = withSession(h) { dev -> IPhoneSnapshot in
                guard let udid = lockdownString(dev, "UniqueDeviceID") else {
                    throw IPhoneReadError.failed(step: "UniqueDeviceID", code: 0)
                }
                var battery: BatteryDetail?
                if includeBattery {
                    let reply = relay(dev, [.ioRegistryName("AppleSmartBattery")]).first ?? nil
                    battery = IPhoneData.relayPayload(reply).map { BatteryInspector.parse(dict: $0) }
                }
                return IPhoneSnapshot(
                    udid: udid,
                    name: lockdownString(dev, "DeviceName") ?? "iPhone",
                    marketingName: lockdownString(dev, "MarketingName"),
                    productType: lockdownString(dev, "ProductType"),
                    osVersion: lockdownString(dev, "ProductVersion"),
                    build: lockdownString(dev, "BuildVersion"),
                    enclosureColor: lockdownString(dev, "DeviceEnclosureColor"),
                    battery: battery,
                    batteryRead: includeBattery)
            }
            Self.onMain { completion(result) }
        }
        if !queued { Self.onMain { completion(.failure(.unavailable)) } }
    }

    /// Identity and parts without storage (read by `readStorage`): lockdown keys and registry entries
    /// over one relay connection. Values are returned to the caller only; nothing is stored or logged here.
    func readIdentity(_ h: IPhoneHandle,
                      completion: @escaping @MainActor (Result<[IPhoneIdentityField], IPhoneReadError>) -> Void) {
        let queued = enqueue(.interactive) { [self] in
            let result = withSession(h) { dev -> [IPhoneIdentityField] in
                var lockdown: [String: Any] = [:]
                for key in ["MarketingName", "ModelNumber", "RegionInfo", "RegulatoryModelNumber",
                            "HardwareModel", "ProductVersion", "BuildVersion", "DeviceEnclosureColor",
                            "DeviceColor", "SerialNumber", "MLBSerialNumber",
                            "InternationalMobileEquipmentIdentity", "InternationalMobileEquipmentIdentity2"] {
                    if let v = copyValue(dev, domain: nil, key: key) { lockdown[key] = v }
                }
                let payloads = withRelay(dev) { send -> [[String: Any]?] in
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
                                                 panel: payloads[1], product: payloads[2], camera: payloads[3])
            }
            Self.onMain { completion(result) }
        }
        if !queued { Self.onMain { completion(.failure(.unavailable)) } }
    }

    /// `TotalDiskCapacity` in bytes, in its own job at the lowest urgency (R5). `onStart` is posted to
    /// main when the job begins (the model's 2 s deadline counts from then). The call can block for
    /// up to ~20 s on a phone-side stall (findings C5); only jobs queued after it wait.
    func readStorage(_ h: IPhoneHandle,
                     onStart: @escaping @MainActor () -> Void,
                     completion: @escaping @MainActor (Result<Int64?, IPhoneReadError>) -> Void) {
        let queued = enqueue(.last) { [self] in
            Self.onMain { onStart() }
            let result = withSession(h) { dev -> Int64? in
                IPhoneData.storageBytes(diskUsage: copyValue(dev, domain: "com.apple.disk_usage", key: nil) as? [String: Any])
            }
            Self.onMain { completion(result) }
        }
        if !queued { Self.onMain { completion(.failure(.unavailable)) } }
    }

    /// Walks the crash-log tree and posts the listing at once (`onListing`, R2), then reads the
    /// headers of files not in `knownHeaders` in the same session, posting `onTypes` per batch.
    /// The read loop yields to any more urgent job; the rest is queued at `.background` (D5, D6).
    func listLogs(_ h: IPhoneHandle, knownHeaders: [String: String],
                  onListing: @escaping @MainActor (Result<IPhoneLogListing, IPhoneReadError>) -> Void,
                  onTypes: @escaping @MainActor (IPhoneLogTypeBatch) -> Void) {
        let queued = enqueue(.user) { [self] in
            var posted = false
            let result = withSession(h) { dev -> Void in
                let walked: Bool? = withCrashAFC(dev) { afc -> Bool in
                    let (listing, pending) = IPhoneLogTypes.split(afc.list(), known: knownHeaders)
                    Self.onMain { onListing(.success(listing)) }
                    posted = true
                    finishTypes(h, afc, pending[...], onTypes)
                    return true
                }
                guard walked != nil else { throw IPhoneReadError.failed(step: "crashreportcopymobile", code: 0) }
            }
            if case .failure(let err) = result, !posted { Self.onMain { onListing(.failure(err)) } }
        }
        if !queued { Self.onMain { onListing(.failure(.unavailable)) } }
    }

    /// Reads headers in order until done or a more urgent job waits; posts one batch (if non-empty)
    /// and queues the rest at `.background`. Transport thread only, inside a crash-AFC session.
    private func finishTypes(_ h: IPhoneHandle, _ afc: AFCSession, _ files: ArraySlice<IPhoneAFCEntry>,
                             _ onTypes: @escaping @MainActor (IPhoneLogTypeBatch) -> Void) {
        var batch = IPhoneLogTypeBatch()
        var rest = files
        while let f = rest.first {
            if runner.hasPending(moreUrgentThan: .background) { break }
            rest = rest.dropFirst()
            let key = IPhoneData.logCacheKey(path: f.path, size: f.size, modified: f.modified)
            var head = afc.readPrefix(path: f.path, limit: 4096)
            if let d = head, f.size > 4096, !d.contains(0x0A) {
                head = afc.readPrefix(path: f.path, limit: 65536)
            }
            // nil = the read failed: reported as failed, so it is not cached and the next listing reads it again.
            if let head {
                batch.read[key] = IPhoneData.bugType(fromHeader: head) ?? ""
            } else {
                batch.failed.insert(key)
            }
        }
        if !batch.isEmpty { Self.onMain { onTypes(batch) } }
        guard !rest.isEmpty else { return }
        let remaining = Array(rest)
        if !enqueue(.background, { [self] in fillTypes(h, remaining, onTypes) }) {
            Self.onMain { onTypes(Self.failedBatch(remaining)) }
        }
    }

    /// The queued rest: own session + crash AFC, then `finishTypes`; a failed session or AFC open
    /// posts every key of `files` in `failed`.
    private func fillTypes(_ h: IPhoneHandle, _ files: [IPhoneAFCEntry],
                           _ onTypes: @escaping @MainActor (IPhoneLogTypeBatch) -> Void) {
        let result = withSession(h) { dev -> Bool in
            withCrashAFC(dev) { afc -> Bool in
                finishTypes(h, afc, files[...], onTypes)
                return true
            } != nil
        }
        if case .success(true) = result { return }
        Self.onMain { onTypes(Self.failedBatch(files)) }
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
        let queued = enqueue(.user) { [self] in
            let result = withSession(h) { dev -> Bool in
                withCrashAFC(dev) { afc in
                    afc.copy(path: remotePath, size: size, to: url) { done in
                        Self.onMain { progress(done) }
                    }
                } ?? false
            }
            let ok: Bool
            if case .success(true) = result { ok = true } else { ok = false }
            Self.onMain { completion(ok) }
        }
        if !queued { Self.onMain { completion(false) } }
    }
}
