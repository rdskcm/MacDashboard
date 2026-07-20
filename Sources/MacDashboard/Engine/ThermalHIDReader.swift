// Engine/ThermalHIDReader.swift
// Block N7: app-only reader for Apple Silicon temperature sensors via the private
// IOHIDEventSystemClient API (same technique as smctemp/Stats.app; symbols are
// exported by IOKit.framework but undeclared in public headers — declared here via
// @_silgen_name). No sudo needed. DELIBERATELY NOT symlinked into Checks: private
// IOKit calls are app-only per Checks/README.md; the pure classification logic it
// feeds lives in Engine/ThermalSensors.swift (which IS symlinked).
//
// Failure model: every step degrades to an empty result — Intel Macs / a future
// macOS that breaks the private API yield [], which ThermalSensors.socTemperature
// maps to nil, which the UI hides (honest-empty). Never throws, never prompts.
//
// Cost: one full create+match+read pass measured at 46.5-60.0 ms (n=15) on the
// target M3 Air — cheap enough for the fast (~2 s) live tick; called off-main by
// DashboardModel's fast task.

import Foundation
import IOKit

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
@discardableResult
private func IOHIDEventSystemClientSetMatching(_ client: CFTypeRef?, _ match: CFDictionary?) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef?) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: CFTypeRef?, _ property: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: CFTypeRef?, _ type: Int64,
                                         _ options: Int32, _ timeStamp: Int64) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef?, _ field: Int32) -> Double

enum ThermalHIDReader {
    private static let appleVendorPage = 0xff00        // kHIDPage_AppleVendor
    private static let temperatureUsage = 0x0005       // temperature sensor usage
    private static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    // IOHIDEventFieldBase(type) == type << 16
    private static let temperatureEventField = Int32(temperatureEventType << 16)

    /// One full enumeration+read pass. Unnamed services (no "Product" property —
    /// these read NaN anyway) are skipped; value filtering/classification is the
    /// caller's job (ThermalSensors).
    static func readTemperatureSensors() -> [ThermalSensors.Reading] {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        else { return [] }
        let match: [String: Int] = ["PrimaryUsagePage": appleVendorPage,
                                    "PrimaryUsage": temperatureUsage]
        IOHIDEventSystemClientSetMatching(client, match as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client)?
            .takeRetainedValue() as? [CFTypeRef] else { return [] }

        var out: [ThermalSensors.Reading] = []
        out.reserveCapacity(services.count)
        for service in services {
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String, !name.isEmpty else { continue }
            guard let event = IOHIDServiceClientCopyEvent(service, temperatureEventType, 0, 0)?
                .takeRetainedValue() else { continue }
            out.append(ThermalSensors.Reading(
                name: name,
                value: IOHIDEventGetFloatValue(event, temperatureEventField)))
        }
        return out
    }
}
