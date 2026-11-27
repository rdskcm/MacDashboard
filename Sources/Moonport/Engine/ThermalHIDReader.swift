// Engine/ThermalHIDReader.swift
// Block N7: app-only reader for Apple Silicon temperature sensors via the private
// IOHIDEventSystemClient API (same technique as smctemp/Stats.app; the symbols are
// exported by IOKit.framework but undeclared in its public headers). No sudo needed.
// DELIBERATELY app-only, not covered by tests: private IOKit calls; the pure
// classification logic this feeds lives in Engine/ThermalSensors.swift (which IS covered).
//
// Linkage: the six private symbols are resolved at RUNTIME via dlopen/dlsym and are
// never linked against. This is load-bearing, not stylistic. An earlier version
// declared them with @_silgen_name, which made them undefined symbols that dyld
// HARD-BOUND at process launch (`nm -u` listed them; `dyld_info -fixups` showed
// `__DATA_CONST __got ... bind IOKit/_IOHID...`). Under that scheme a future macOS
// that stopped exporting even ONE of the six would have killed the entire app at
// launch with "Symbol not found, Expected in: IOKit" — before any Swift code ran, so
// no amount of in-code guarding could have degraded gracefully.
//
// Failure model: the symbols are looked up ONCE, lazily, on first use. If dlopen
// fails, or if ANY one of the six dlsym lookups returns NULL, the whole set fails
// closed (never partially) and the nil result is cached — it is never retried.
// readTemperatureSensors() then returns [] on every call, exactly like the Intel-Mac
// and no-sensors-found paths. ThermalSensors.socTemperature maps [] to nil, which the
// UI hides (honest-empty). Never throws, never prompts, never fails at launch.
//
// Cost: one full create+match+read pass measured at 46.5-60.0 ms (n=15) on the
// target M3 Air — cheap enough for the fast (~2 s) live tick; called off-main by
// AppModel's fast task. The one-time dlopen+6x dlsym adds microseconds, on the
// first pass only.

import Foundation
import IOKit

enum ThermalHIDReader {
    private static let appleVendorPage = 0xff00        // kHIDPage_AppleVendor
    private static let temperatureUsage = 0x0005       // temperature sensor usage
    private static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    // IOHIDEventFieldBase(type) == type << 16
    private static let temperatureEventField = Int32(temperatureEventType << 16)

    // MARK: - Private IOKit symbols (resolved at runtime, never linked)

    // Exact C signatures of the six undocumented IOKit exports, as Swift C-convention
    // function-pointer shapes. Three distinct return shapes — keep them distinct:
    // Unmanaged<CFTypeRef>? (Create/CopyProperty/CopyEvent, all follow the CF "Create/
    // Copy" rule so the caller must takeRetainedValue()), Unmanaged<CFArray>?
    // (CopyServices — CFArray, not CFTypeRef, so the `as? [CFTypeRef]` bridge works),
    // Int32 (SetMatching, result unused), and Double (GetFloatValue; IOHIDFloat is
    // double on 64-bit).
    private typealias ClientCreateFn         = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias ClientSetMatchingFn    = @convention(c) (CFTypeRef?, CFDictionary?) -> Int32
    private typealias ClientCopyServicesFn   = @convention(c) (CFTypeRef?) -> Unmanaged<CFArray>?
    private typealias ServiceCopyPropertyFn  = @convention(c) (CFTypeRef?, CFString) -> Unmanaged<CFTypeRef>?
    private typealias ServiceCopyEventFn     = @convention(c) (CFTypeRef?, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias EventGetFloatValueFn   = @convention(c) (CFTypeRef?, Int32) -> Double

    /// All six resolved function pointers. Constructed all-or-nothing: `symbolLoad`
    /// succeeds only when dlopen AND all six dlsym lookups succeeded, so no
    /// caller can ever observe a partially-resolved set.
    private struct HIDSymbols {
        let clientCreate: ClientCreateFn
        let clientSetMatching: ClientSetMatchingFn
        let clientCopyServices: ClientCopyServicesFn
        let serviceCopyProperty: ServiceCopyPropertyFn
        let serviceCopyEvent: ServiceCopyEventFn
        let eventGetFloatValue: EventGetFloatValueFn
    }

    static let libraryPath = "/System/Library/Frameworks/IOKit.framework/IOKit"
    // NOTE: dlsym takes the UNMANGLED name — no leading underscore. `nm` prints
    // `_IOHIDEventSystemClientCreate`; that underscore is Mach-O mangling.
    static let symbolNames = ["IOHIDEventSystemClientCreate", "IOHIDEventSystemClientSetMatching",
                              "IOHIDEventSystemClientCopyServices", "IOHIDServiceClientCopyProperty",
                              "IOHIDServiceClientCopyEvent", "IOHIDEventGetFloatValue"]

    /// Resolved exactly once, on first access, by Swift's lazy static initialization
    /// (swift_once) — that is already thread-safe, so no lock/dispatch_once is needed
    /// even though readTemperatureSensors() is called from a background queue. A failure
    /// is cached like any other value: dlopen/dlsym are NEVER retried. READER-STATUS D10/D11: the failure keeps
    /// the first missing symbol or the dlerror text (`SymbolLoader`). RTLD_LAZY: IOKit is already loaded in-process,
    /// so this is a refcount bump. The handle is intentionally NEVER dlclose()d — the resolved pointers must stay
    /// valid for the whole process lifetime. Partial resolution => the whole set fails closed.
    private static let symbolLoad: Result<HIDSymbols, ReaderReason> =
        SymbolLoader.load(path: libraryPath, mode: RTLD_LAZY, symbols: symbolNames).map { p in
            HIDSymbols(
                clientCreate:        unsafeBitCast(p[0], to: ClientCreateFn.self),
                clientSetMatching:   unsafeBitCast(p[1], to: ClientSetMatchingFn.self),
                clientCopyServices:  unsafeBitCast(p[2], to: ClientCopyServicesFn.self),
                serviceCopyProperty: unsafeBitCast(p[3], to: ServiceCopyPropertyFn.self),
                serviceCopyEvent:    unsafeBitCast(p[4], to: ServiceCopyEventFn.self),
                eventGetFloatValue:  unsafeBitCast(p[5], to: EventGetFloatValueFn.self))
        }

    /// One full enumeration+read pass. Unnamed services (no "Product" property —
    /// these read NaN anyway) are skipped; value filtering/classification is the
    /// caller's job (ThermalSensors). Private API unavailable on this OS (dlopen failed, or one of the six symbols
    /// is gone) — honest-empty, same as "no sensors found".
    static func readTemperatureSensors() -> [ThermalSensors.Reading] {
        (try? readTemperatureSensorsResult().get()) ?? []
    }

    /// READER-STATUS: the same pass, with the reason when it could not run (missing symbol, no client, no service list).
    static func readTemperatureSensorsResult() -> Result<[ThermalSensors.Reading], ReaderReason> {
        let hid: HIDSymbols
        switch symbolLoad {
        case .failure(let r): return .failure(r)
        case .success(let h): hid = h
        }

        guard let client = hid.clientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        else { return .failure(.nullResult(call: "IOHIDEventSystemClientCreate")) }
        let match: [String: Int] = ["PrimaryUsagePage": appleVendorPage,
                                    "PrimaryUsage": temperatureUsage]
        _ = hid.clientSetMatching(client, match as CFDictionary)
        guard let services = hid.clientCopyServices(client)?
            .takeRetainedValue() as? [CFTypeRef] else { return .failure(.nullResult(call: "IOHIDEventSystemClientCopyServices")) }

        var out: [ThermalSensors.Reading] = []
        out.reserveCapacity(services.count)
        for service in services {
            guard let name = hid.serviceCopyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String, !name.isEmpty else { continue }
            guard let event = hid.serviceCopyEvent(service, temperatureEventType, 0, 0)?
                .takeRetainedValue() else { continue }
            out.append(ThermalSensors.Reading(
                name: name,
                value: hid.eventGetFloatValue(event, temperatureEventField)))
        }
        return .success(out)
    }
}
