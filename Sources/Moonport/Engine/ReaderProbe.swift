// Engine/ReaderProbe.swift
// READER-STATUS: the report pass's one-shot reads of every hardware reader, off the main thread, bounded (spec D7).
// Runs only inside report generation (rule no-unseen-work).
import Foundation
import os

enum ReaderProbe {
    static let hardwareTimeout: TimeInterval = 10

    /// The rows `hardwareLines()` emits, in its order; also the rows a timeout marks failed.
    static let hardwareIDs: [ReaderID] = [
        .systemCPUBrand, .smcConnection, .smcChipTemperature, .smcPower, .smcSensors, .hidTemperature, .cpuTopology,
        .cpuCoreTicks, .cpuFrequency, .gpuUtilization, .gpuCoreCount, .gpuClients, .systemCPULoad, .systemLoadAverage,
        .systemMemory, .systemSwap, .systemMemoryPressure, .systemVolume, .batteryPowerSources,
    ]

    /// True while a probe's GCD block is still running, also after its deadline passed: a hung IOKit call must not
    /// make every later report pass park one more thread behind it.
    private static let running = OSAllocatedUnfairLock(initialState: false)

    /// Every report-probe row (the command-based rows come from their own report jobs).
    static func collect() async -> [ReaderStatusLine] {
        let claimed = running.withLock { busy -> Bool in
            if busy { return false }
            busy = true
            return true
        }
        let hardware: [ReaderStatusLine]
        if !claimed {
            hardware = timedOutLines(hardwareIDs, seconds: hardwareTimeout)
        } else {
            hardware = await runOffMain(timeout: hardwareTimeout) {
                defer { running.withLock { $0 = false } }
                return hardwareLines()
            } ?? timedOutLines(hardwareIDs, seconds: hardwareTimeout)
        }
        // READER-STATUS S4: sequential, the ioreg run has its own 5 s deadline.
        let battery = await BatteryInspector.readWithStatus().status
        return hardware + [battery]
    }

    /// Synchronous IOKit / sysctl / dlsym reads. Call off the main thread only (`collect` does).
    static func hardwareLines() -> [ReaderStatusLine] {
        var lines = [ReaderStatusMac.cpuBrandLine(SysctlRead.string("machdep.cpu.brand_string"))]
        lines += ReaderStatusMac.smcLines(SMCReader.probe())
        lines.append(ReaderStatusMac.hidLine(ThermalHIDReader.readTemperatureSensorsResult()))
        lines.append(ReaderStatusMac.topologyLine(CoreTopology.readResolution()))
        lines.append(ReaderStatusMac.coreTicksLine(CoreLoadReader.readTicksResult()))
        lines.append(ReaderStatusMac.frequencyLine(CPUFrequencyReader.probe(),
                                                   expected: ReaderStatusMac.expectedFrequencyKeys(CoreTopology.cached)))
        lines.append(ReaderStatusMac.gpuUtilizationLine(GPUStats.readDeviceUtilizationResult()))
        lines.append(ReaderStatusMac.gpuCoreCountLine(GPUStats.readCoreCountResult()))
        lines.append(ReaderStatusMac.gpuClientsLine(GPUStats.readClientsResult()))
        lines.append(ReaderStatusMac.simpleLine(.systemCPULoad, LiveCollector.readCPUTicksResult()))
        lines.append(ReaderStatusMac.simpleLine(.systemLoadAverage, LiveCollector.readLoadResult()))
        lines.append(ReaderStatusMac.simpleLine(.systemMemory, LiveCollector.readMemoryResult()))
        lines.append(ReaderStatusMac.simpleLine(.systemSwap, LiveCollector.readSwapResult()))
        lines.append(ReaderStatusMac.memoryPressureLine(LiveCollector.readMemoryPressureResult()))
        lines.append(ReaderStatusMac.simpleLine(.systemVolume, LiveCollector.readDiskResult()))
        lines.append(ReaderStatusMac.powerSourcesLine(LiveCollector.readBatteryResult()))
        return lines
    }

    /// Pure. Every id `failed: no answer within <seconds> s`.
    static func timedOutLines(_ ids: [ReaderID], seconds: TimeInterval) -> [ReaderStatusLine] {
        ids.map { ReaderStatusLine(reader: $0, status: .failed(.timedOut(seconds: Int(seconds)))) }
    }

    /// Runs `work` on `queue`; nil when it has not finished within `timeout` (its late result is dropped).
    static func runOffMain<T: Sendable>(timeout: TimeInterval, queue: DispatchQueue = .global(qos: .userInitiated),
                                        _ work: @escaping @Sendable () -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (T?) -> Void = { value in
                let first = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if first { continuation.resume(returning: value) }
            }
            queue.async { finish(work()) }
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}
