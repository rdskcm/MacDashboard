// Engine/GPUStats.swift
// GPU-UTILIZATION: whole-machine GPU load from the IOAccelerator registry entry's `PerformanceStatistics`
// (`Device Utilization %`). Undocumented key, matched exactly; absent → nil → the UI shows «—».
import Foundation
import IOKit

enum GPUStats {
    static let deviceUtilizationKey = "Device Utilization %"

    /// Pure. nil when the key is absent or not a number. Clamped to 0...100.
    static func deviceUtilization(performanceStatistics: [String: Any]) -> Int? {
        guard let n = performanceStatistics[deviceUtilizationKey] as? NSNumber else { return nil }
        return min(100, max(0, n.intValue))
    }

    /// IOKit. Max `Device Utilization %` over every IOAccelerator entry; nil when none has it. Never throws.
    static func readDeviceUtilization() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS,
              iterator != 0 else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Int? = nil
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            guard let cf = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                  let dict = cf.takeRetainedValue() as? [String: Any],
                  let v = deviceUtilization(performanceStatistics: dict) else { continue }
            best = max(best ?? v, v)
        }
        return best
    }
}
