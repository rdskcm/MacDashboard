// Tests/MoonportTests/ReaderStatusLiveCanaryTests.swift
// READER-STATUS: opt-in live canary. Runs a real report-probe pass on this Mac, prints the whole status table and
// checks it against independent readings.
// Run: MACDASH_LIVE=1 swift test --filter liveCanaryReaderStatus. Reads only. Every line printed here starts with `liveCanary`.
import Foundation
import Testing
@testable import Moonport

private let liveEnabled = ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"

extension SerialTests {
    @MainActor struct ReaderStatusLiveCanaryTests {
        @Test(.enabled(if: liveEnabled))
        func liveCanaryReaderStatus() async throws {
            let report = await ReportCollector().collect(skipSlow: true) { _ in }
            print("liveCanary readerStatus chip=\(report.system?.chip ?? "nil") model=\(report.system?.modelId ?? "nil") build=\(report.system?.osBuild ?? "nil")")
            let lines = ReaderStatusLine.ordered(report.readerStatus, by: ReaderID.macOrder)
            for l in lines {
                let id = l.reader.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0)
                var text = "liveCanary readerStatus \(id) "
                switch l.status {
                case .ok: text += "ok"
                case .notApplicable(let r): text += "notApplicable: \(r.text)"
                case .failed(let r): text += "failed: \(r.text)"
                }
                if let reading = l.reading { text += " (\(reading))" }
                print(text)
            }

            #expect(lines.map(\.reader) == ReaderID.macOrder)
            for l in lines {
                if case .timedOut? = l.status.reason { Issue.record("\(l.reader.rawValue) timed out") }
            }
            func status(_ id: ReaderID) throws -> ReaderStatus { try #require(lines.first { $0.reader == id }).status }
            for id in [ReaderID.smcConnection, .smcPower, .smcSensors, .cpuFrequency, .cpuTopology, .cpuCoreTicks,
                       .gpuUtilization, .gpuCoreCount, .gpuClients, .systemCPULoad, .systemLoadAverage, .systemMemory,
                       .systemSwap, .systemMemoryPressure, .systemVolume, .systemCPUBrand,
                       .systemVersion, .systemHardwareProfile, .diskInternalInfo, .diskExternalList] {
                #expect(try status(id) == .ok, "\(id.rawValue) is not ok on this Mac")
            }

            // Independent agreement with the live entry points.
            #expect((try status(.smcPower) == .ok) == (SMCReader.readSystemPowerW() != nil))
            #expect((try status(.hidTemperature) == .ok)
                    == ThermalHIDReader.readTemperatureSensors().contains { ThermalSensors.isValidReading($0.value) })
            let chipValid = SMCReader.readTemperatures(keys: TemperatureSensors.chipKeys)?.values.contains(where: TemperatureSensors.isValid) == true
            if chipValid {
                #expect(try status(.smcChipTemperature) == .ok)
            } else if case .notApplicable = try status(.smcChipTemperature) {
            } else {
                Issue.record("smc.chipTemperature is neither ok nor not applicable although no chip key is valid")
            }
            func reading(_ id: ReaderID) throws -> String? { try #require(lines.first { $0.reader == id }).reading }
            let sysctlOut = await CommandRunner.run("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"], timeout: 5)
            #expect(try reading(.systemCPUBrand) == sysctlOut.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(try reading(.gpuCoreCount) == "\(try #require(GPUStats.cachedCoreCount)) cores")
            #expect(try reading(.cpuTopology)
                    == CoreTopology.cached.map { "\($0.name ?? "unknown") \($0.count)" }.joined(separator: ", "))
            let hasBattery = LiveCollector().collectFast().battery != nil
            if hasBattery {
                #expect(try status(.batteryPowerSources) == .ok)
            } else if case .notApplicable = try status(.batteryPowerSources) {
            } else {
                Issue.record("battery.powerSources is neither ok nor not applicable on a Mac without a battery")
            }
            let smartctlFound = ReportCollector.findSmartctl() != nil
            if smartctlFound {
                #expect(try status(.diskInternalSmart) == .ok)
            } else if case .notApplicable = try status(.diskInternalSmart) {
            } else {
                Issue.record("disk.internalSmart is neither ok nor not applicable although smartctl is absent")
            }
            for id in [ReaderID.batteryPmset, .batterySystemProfiler, .batteryIoreg] {
                if hasBattery {
                    #expect(try status(id) == .ok, "\(id.rawValue) is not ok on a Mac with a battery")
                } else if case .notApplicable = try status(id) {
                } else {
                    Issue.record("\(id.rawValue) is neither ok nor not applicable on a Mac without a battery")
                }
            }
            #expect(CPUFrequencyReader.shared != nil, "the probe broke the live frequency setup")
        }
    }
}
