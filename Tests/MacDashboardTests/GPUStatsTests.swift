// Tests/MacDashboardTests/GPUStatsTests.swift
// GPU-UTILIZATION: parsing of the IOAccelerator `PerformanceStatistics` dictionary, the read cost, and the live canary.
import Foundation
import Testing
@testable import MacDashboard

// Values verbatim from inputs/GPU-UTILIZATION-capture/ioaccel-idle.plist and ioaccel-loaded.plist
// (macOS 27.2, MacBook Air, arm64, 2026-11-05).
private var idleStats: [String: Any] { [
    "Alloc system memory": 1733017600, "Allocated PB Size": 40894464, "Device Utilization %": 2,
    "In use system memory": 284950528, "In use system memory (driver)": 0, "Renderer Utilization %": 2,
    "SplitSceneCount": 0, "TiledSceneBytes": 688128, "Tiler Utilization %": 2, "lastRecoveryTime": 0, "recoveryCount": 0,
] }
private var loadedStats: [String: Any] { [
    "Alloc system memory": 1773862912, "Allocated PB Size": 40894464, "Device Utilization %": 99,
    "In use system memory": 348127232, "In use system memory (driver)": 0, "Renderer Utilization %": 28,
    "SplitSceneCount": 0, "TiledSceneBytes": 786432, "Tiler Utilization %": 28, "lastRecoveryTime": 0, "recoveryCount": 0,
] }

struct GPUStatsTests {
    @Test func captureValues() {
        #expect(GPUStats.deviceUtilization(performanceStatistics: idleStats) == 2)
        #expect(GPUStats.deviceUtilization(performanceStatistics: loadedStats) == 99)
    }

    @Test func missingOrWrongType() {
        var noKey = idleStats; noKey.removeValue(forKey: "Device Utilization %")
        #expect(GPUStats.deviceUtilization(performanceStatistics: noKey) == nil)
        #expect(GPUStats.deviceUtilization(performanceStatistics: [:]) == nil)
        #expect(GPUStats.deviceUtilization(performanceStatistics: ["Device Utilization %": "5"]) == nil)
    }

    @Test func clampAndNumberTypes() {
        #expect(GPUStats.deviceUtilization(performanceStatistics: ["Device Utilization %": 130]) == 100)
        #expect(GPUStats.deviceUtilization(performanceStatistics: ["Device Utilization %": -1]) == 0)
        #expect(GPUStats.deviceUtilization(performanceStatistics: ["Device Utilization %": NSNumber(value: 7)]) == 7)
        #expect(GPUStats.deviceUtilization(performanceStatistics: ["Device Utilization %": 42.0]) == 42)
    }

    @Test func exactKeyMatchOnly() {
        #expect(GPUStats.deviceUtilization(performanceStatistics: ["Device Utilization % (driver)": 50]) == nil)
    }
}

extension SerialTests {
    struct GPUStatsLiveTests {
        private static func timedReads() -> (median: Double, max: Double) {
            var ms: [Double] = []
            for _ in 0..<20 {
                let d = ContinuousClock().measure { _ = GPUStats.readDeviceUtilization() }
                ms.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
            }
            ms.sort()
            return ((ms[9] + ms[10]) / 2, ms[19])
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func readCost() {
            let r = Self.timedReads()
            print("gpu read median=\(r.median) max=\(r.max) ms")
            #expect(r.median <= 5)
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryGPUStats() throws {
            let app = GPUStats.readDeviceUtilization()
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            p.arguments = ["-r", "-d", "1", "-c", "IOAccelerator", "-a"]
            let pipe = Pipe()
            p.standardOutput = pipe
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
            let first = try #require(plist?.first)
            let stats = first["PerformanceStatistics"] as? [String: Any] ?? [:]
            let ioreg = GPUStats.deviceUtilization(performanceStatistics: stats)
            print("liveCanary gpu app=\(String(describing: app)) ioreg=\(String(describing: ioreg)) class=\(String(describing: first["IOClass"]))")
            let r = Self.timedReads()
            print("liveCanary gpu read median=\(r.median) max=\(r.max) ms")
            #expect(app != nil && ioreg != nil)
            #expect((0...100).contains(app!))
            #expect(abs(app! - ioreg!) <= 25)
        }
    }
}
