// Tests/MoonportTests/ReaderStatusMacTests.swift
// READER-STATUS S2: the pure mappings of the SMC, HID and CPU-frequency readers (spec T1 rows 4-8 and 11), built from
// literal probe values. Each test asserts the whole `ReaderStatusLine`.
import Foundation
import Testing
@testable import Moonport

private func leBytes(_ f: Float) -> [UInt8] {
    let b = f.bitPattern
    return [UInt8(b & 255), UInt8(b >> 8 & 255), UInt8(b >> 16 & 255), UInt8(b >> 24 & 255)]
}

private func flt(_ key: String, _ v: Float) -> SMCKeyOutcome {
    SMCKeyOutcome(key: key, read: .value(type: "flt ", bytes: leBytes(v)))
}

private func absent(_ key: String, _ result: UInt8 = 0x84) -> SMCKeyOutcome {
    SMCKeyOutcome(key: key, read: .missing(result: result))
}

private func line(_ id: ReaderID, _ lines: [ReaderStatusLine]) -> ReaderStatusLine {
    lines.first { $0.reader == id }!
}

private let sensorKeyList = "SMC sensor keys Te*, Tp*, Tg*, TB0T, TW0P, TH0x, TCHP"

struct ReaderStatusMacTests {
    // MARK: SMC

    @Test func smcOpenFailureMarksTheKeyRowsNotRun() {
        let reason = ReaderReason.serviceAbsent(className: "AppleSMC")
        let lines = ReaderStatusMac.smcLines(SMCProbe(openFailure: reason))
        let notRun = ReaderStatus.failed(.prerequisiteFailed(reader: .smcConnection))
        #expect(lines == [ReaderStatusLine(reader: .smcConnection, status: .failed(reason)),
                          ReaderStatusLine(reader: .smcChipTemperature, status: notRun),
                          ReaderStatusLine(reader: .smcPower, status: notRun),
                          ReaderStatusLine(reader: .smcSensors, status: notRun)])
    }

    @Test func smcLinesAreInRowOrderAndConnectionIsOk() {
        let lines = ReaderStatusMac.smcLines(SMCProbe(chip: [flt("TCMz", 45.25)], power: flt("PSTR", 6.5), sensorKeys: .success([]), sensors: []))
        #expect(lines.map(\.reader) == [.smcConnection, .smcChipTemperature, .smcPower, .smcSensors])
        #expect(lines[0] == ReaderStatusLine(reader: .smcConnection, status: .ok))
    }

    @Test func chipTemperatureFirstValidKeyWins() {
        let p = SMCProbe(chip: [absent("TCMz"), flt("TCMb", 51.5)], power: flt("PSTR", 1), sensorKeys: .success([]))
        #expect(line(.smcChipTemperature, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcChipTemperature, status: .ok, reading: "TCMb 51.5 °C"))
        let both = SMCProbe(chip: [flt("TCMz", 45.5), flt("TCMb", 51.5)], power: flt("PSTR", 1), sensorKeys: .success([]))
        #expect(line(.smcChipTemperature, ReaderStatusMac.smcLines(both))
                == ReaderStatusLine(reader: .smcChipTemperature, status: .ok, reading: "TCMz 45.5 °C"))
    }

    @Test func chipTemperatureBothKeysAbsentIsNotApplicable() {
        let p = SMCProbe(chip: [absent("TCMz"), absent("TCMb", 0x85)], power: flt("PSTR", 1), sensorKeys: .success([]))
        #expect(line(.smcChipTemperature, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcChipTemperature,
                                    status: .notApplicable(.several([.smcKeyAbsent(key: "TCMz", result: 0x84),
                                                                      .smcKeyAbsent(key: "TCMb", result: 0x85)]))))
    }

    @Test func chipTemperatureImplausibleIsFailed() {
        let p = SMCProbe(chip: [flt("TCMz", 3.5), absent("TCMb")], power: flt("PSTR", 1), sensorKeys: .success([]))
        #expect(line(.smcChipTemperature, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcChipTemperature,
                                    status: .failed(.several([.implausible(what: "TCMz", value: "3.5 °C", accepted: "(10, 150] °C"),
                                                              .smcKeyAbsent(key: "TCMb", result: 0x84)]))))
    }

    @Test func chipTemperatureUndecodableAndCallFailureAreFailed() {
        let odd = SMCKeyOutcome(key: "TCMz", read: .value(type: "ui32", bytes: [1, 2, 3, 4]))
        let broken = SMCKeyOutcome(key: "TCMb", read: .callFailed(kern: 5, result: 0))
        let p = SMCProbe(chip: [odd, broken], power: flt("PSTR", 1), sensorKeys: .success([]))
        #expect(line(.smcChipTemperature, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcChipTemperature,
                                    status: .failed(.several([.smcKeyUnsupported(key: "TCMz", type: "ui32", size: 4),
                                                              .kernReturn(call: "IOConnectCallStructMethod(SMC TCMb)", code: 5)]))))
    }

    @Test func powerMissingIsNotApplicable() {
        let p = SMCProbe(chip: [flt("TCMz", 40)], power: absent("PSTR", 0x84), sensorKeys: .success([]))
        #expect(line(.smcPower, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcPower, status: .notApplicable(.smcKeyAbsent(key: "PSTR", result: 0x84))))
    }

    @Test func powerFailuresAreFailed() {
        func power(_ read: SMCReader.KeyRead) -> ReaderStatusLine {
            line(.smcPower, ReaderStatusMac.smcLines(SMCProbe(chip: [], power: SMCKeyOutcome(key: "PSTR", read: read), sensorKeys: .success([]))))
        }
        #expect(power(.unsupported(type: "ch8*", size: 40))
                == ReaderStatusLine(reader: .smcPower, status: .failed(.smcKeyUnsupported(key: "PSTR", type: "ch8*", size: 40))))
        #expect(power(.callFailed(kern: 0, result: 0x85))
                == ReaderStatusLine(reader: .smcPower, status: .failed(.smcResult(key: "PSTR", result: 0x85))))
        #expect(power(.value(type: "ui32", bytes: [1, 2, 3, 4]))
                == ReaderStatusLine(reader: .smcPower, status: .failed(.smcKeyUnsupported(key: "PSTR", type: "ui32", size: 4))))
    }

    @Test func powerImplausibleIsFailed() {
        let p = SMCProbe(chip: [], power: flt("PSTR", 1500), sensorKeys: .success([]))
        #expect(line(.smcPower, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcPower,
                                    status: .failed(.implausible(what: "PSTR", value: "1500.00 W", accepted: "(0, 1000] W"))))
        let zero = SMCProbe(chip: [], power: flt("PSTR", 0), sensorKeys: .success([]))
        #expect(line(.smcPower, ReaderStatusMac.smcLines(zero))
                == ReaderStatusLine(reader: .smcPower,
                                    status: .failed(.implausible(what: "PSTR", value: "0.00 W", accepted: "(0, 1000] W"))))
    }

    @Test func powerOkReading() {
        let p = SMCProbe(chip: [], power: flt("PSTR", 6.421875), sensorKeys: .success([]))
        #expect(line(.smcPower, ReaderStatusMac.smcLines(p)) == ReaderStatusLine(reader: .smcPower, status: .ok, reading: "PSTR 6.42 W"))
    }

    @Test func sensorsEnumerationFailureIsFailed() {
        let reason = ReaderReason.kernReturn(call: "IOConnectCallStructMethod(SMC key index 0)", code: 5)
        let p = SMCProbe(chip: [], power: flt("PSTR", 1), sensorKeys: .failure(reason))
        #expect(line(.smcSensors, ReaderStatusMac.smcLines(p)) == ReaderStatusLine(reader: .smcSensors, status: .failed(reason)))
    }

    @Test func sensorsNoKeysIsNotApplicable() {
        let p = SMCProbe(chip: [], power: flt("PSTR", 1), sensorKeys: .success([]))
        #expect(line(.smcSensors, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcSensors, status: .notApplicable(.empty(what: sensorKeyList))))
    }

    @Test func sensorsNoValidValueIsFailed() {
        let p = SMCProbe(chip: [], power: flt("PSTR", 1), sensorKeys: .success(["Tp01", "Te05"]),
                         sensors: [flt("Tp01", 0), absent("Te05")])
        #expect(line(.smcSensors, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcSensors,
                                    status: .failed(.implausible(what: "SMC sensor keys", value: "2 read, 0 valid", accepted: "(10, 150] °C"))))
    }

    @Test func sensorsOkReadingCountsValidValues() {
        let p = SMCProbe(chip: [], power: flt("PSTR", 1), sensorKeys: .success(["Tp01", "Te05", "Tg0f"]),
                         sensors: [flt("Tp01", 48), flt("Te05", 0), flt("Tg0f", 41)])
        #expect(line(.smcSensors, ReaderStatusMac.smcLines(p))
                == ReaderStatusLine(reader: .smcSensors, status: .ok, reading: "3 keys, 2 valid"))
    }

    // MARK: HID

    @Test func hidSymbolMissingIsFailed() {
        let reason = ReaderReason.symbolMissing(library: ThermalHIDReader.libraryPath, symbol: "IOHIDEventSystemClientCreate")
        #expect(ReaderStatusMac.hidLine(.failure(reason)) == ReaderStatusLine(reader: .hidTemperature, status: .failed(reason)))
        let nullClient = ReaderReason.nullResult(call: "IOHIDEventSystemClientCopyServices")
        #expect(ReaderStatusMac.hidLine(.failure(nullClient)) == ReaderStatusLine(reader: .hidTemperature, status: .failed(nullClient)))
    }

    @Test func hidNoServicesIsNotApplicable() {
        #expect(ReaderStatusMac.hidLine(.success([]))
                == ReaderStatusLine(reader: .hidTemperature,
                                    status: .notApplicable(.empty(what: "HID temperature services (usage page 0xFF00, usage 0x0005)"))))
    }

    @Test func hidNoValidReadingIsFailed() {
        let readings = [ThermalSensors.Reading(name: "a", value: .nan), ThermalSensors.Reading(name: "b", value: -1.3)]
        #expect(ReaderStatusMac.hidLine(.success(readings))
                == ReaderStatusLine(reader: .hidTemperature,
                                    status: .failed(.implausible(what: "HID temperature readings", value: "2 read, 0 valid", accepted: "finite > 0"))))
    }

    @Test func hidOkReadingNamesTheSoCDie() {
        let readings = [ThermalSensors.Reading(name: "PMU tdie1", value: 41.25), ThermalSensors.Reading(name: "PMU tdie3", value: 44.5),
                        ThermalSensors.Reading(name: "NAND CH0 temp", value: 30), ThermalSensors.Reading(name: "dead", value: .nan)]
        #expect(ReaderStatusMac.hidLine(.success(readings))
                == ReaderStatusLine(reader: .hidTemperature, status: .ok, reading: "4 services, 3 valid, SoC die 44.5 °C"))
        let noDie = [ThermalSensors.Reading(name: "NAND CH0 temp", value: 30)]
        #expect(ReaderStatusMac.hidLine(.success(noDie))
                == ReaderStatusLine(reader: .hidTemperature, status: .ok, reading: "1 services, 1 valid"))
    }

    // MARK: CPU frequency

    private let both: Set<CoreGroupKey> = [.efficiency, .performance]

    @Test func frequencySetupFailure() {
        let reason = ReaderReason.symbolMissing(library: CPUFrequencyReader.libraryPath, symbol: "IOReportStateGetCount")
        #expect(ReaderStatusMac.frequencyLine(FrequencyProbe(setupFailure: reason), expected: both)
                == ReaderStatusLine(reader: .cpuFrequency, status: .failed(reason)))
    }

    @Test func frequencySampleFailure() {
        let reason = ReaderReason.nullResult(call: "IOReportCreateSamplesDelta")
        let ok = FrequencyProbe(readings: [.efficiency: .success(FrequencyReading(mhz: 1000, activeShare: 0.5))])
        var p = ok
        p.sampleFailure = reason
        #expect(ReaderStatusMac.frequencyLine(p, expected: both) == ReaderStatusLine(reader: .cpuFrequency, status: .failed(reason)))
    }

    @Test func frequencyIdleAndActiveParts() {
        let p = FrequencyProbe(readings: [.efficiency: .success(FrequencyReading(mhz: 1019.6, activeShare: 0.344)),
                                          .performance: .success(FrequencyReading(mhz: 0, activeShare: 0.01))])
        #expect(ReaderStatusMac.frequencyLine(p, expected: both)
                == ReaderStatusLine(reader: .cpuFrequency, status: .ok, reading: "E 1020 MHz 34% active, P idle"))
    }

    @Test func frequencySkippedPerformanceIsFailedWithTheEfficiencyReading() {
        let skipped = ReaderReason.registryPropertyAbsent(entry: "IODeviceTree:/arm-io/pmgr", property: "voltage-states5-sram")
        let p = FrequencyProbe(skipped: [.performance: skipped],
                               readings: [.efficiency: .success(FrequencyReading(mhz: 1020, activeShare: 0.5))])
        #expect(ReaderStatusMac.frequencyLine(p, expected: both)
                == ReaderStatusLine(reader: .cpuFrequency, status: .failed(skipped), reading: "E 1020 MHz 50% active"))
    }

    @Test func frequencyChannelAbsentAndReadingFailure() {
        let weighting = ReaderReason.validationFailed(what: "IOReport ECPU residencies", check: "D2 (e)/(f) weighting")
        let p = FrequencyProbe(readings: [.efficiency: .failure(weighting)])
        #expect(ReaderStatusMac.frequencyLine(p, expected: both)
                == ReaderStatusLine(reader: .cpuFrequency,
                                    status: .failed(.several([weighting, .ioReportChannelAbsent(group: "CPU Stats", subgroup: "CPU Complex Performance States", channel: "PCPU")]))))
    }

    @Test func frequencyOnlyExpectedTypesAreChecked() {
        let p = FrequencyProbe(readings: [.performance: .success(FrequencyReading(mhz: 3000, activeShare: 0.9))])
        #expect(ReaderStatusMac.frequencyLine(p, expected: [.performance])
                == ReaderStatusLine(reader: .cpuFrequency, status: .ok, reading: "P 3000 MHz 90% active"))
    }

    @Test func frequencyUnknownTopologyExpectsBothTypes() {
        #expect(ReaderStatusMac.expectedFrequencyKeys([]) == both)
        #expect(ReaderStatusMac.expectedFrequencyKeys([CoreGroup(name: "Super", count: 4, coreIndices: [0, 1, 2, 3])]) == both)
        #expect(ReaderStatusMac.expectedFrequencyKeys([CoreGroup(name: "Performance", count: 4, coreIndices: [0, 1, 2, 3])]) == [.performance])
        #expect(ReaderStatusMac.expectedFrequencyKeys([CoreGroup(name: "Performance", count: 2, coreIndices: [0, 1]),
                                                       CoreGroup(name: "Efficiency", count: 2, coreIndices: [2, 3])]) == both)
    }
}

// MARK: - S3 mappings (spec T1 rows 3, 9, 10, 12-14, 19, 21)

struct ReaderStatusMacS3Tests {
    private let reason = ReaderReason.nullResult(call: "x")

    @Test func cpuBrandTrimsAndRejectsBlank() {
        #expect(ReaderStatusMac.cpuBrandLine(.success("Apple M2\n"))
                == ReaderStatusLine(reader: .systemCPUBrand, status: .ok, reading: "Apple M2"))
        #expect(ReaderStatusMac.cpuBrandLine(.success(" \n "))
                == ReaderStatusLine(reader: .systemCPUBrand, status: .failed(.empty(what: "sysctl machdep.cpu.brand_string"))))
        #expect(ReaderStatusMac.cpuBrandLine(.failure(reason))
                == ReaderStatusLine(reader: .systemCPUBrand, status: .failed(reason)))
    }

    @Test func topologyReadingAndFailure() {
        let groups = [CoreGroup(name: "Performance", count: 8, coreIndices: Array(0..<8)),
                      CoreGroup(name: "Efficiency", count: 2, coreIndices: [8, 9])]
        #expect(ReaderStatusMac.topologyLine(.success(groups))
                == ReaderStatusLine(reader: .cpuTopology, status: .ok, reading: "Performance 8, Efficiency 2"))
        #expect(ReaderStatusMac.topologyLine(.success([CoreGroup(name: nil, count: 4, coreIndices: [0, 1, 2, 3])]))
                == ReaderStatusLine(reader: .cpuTopology, status: .ok, reading: "unknown 4"))
        #expect(ReaderStatusMac.topologyLine(.failure(reason)) == ReaderStatusLine(reader: .cpuTopology, status: .failed(reason)))
    }

    @Test func coreTicksAndGPULines() {
        let t = CoreTicks(user: 1, system: 2, idle: 3, nice: 4)
        #expect(ReaderStatusMac.coreTicksLine(.success([t, t, t]))
                == ReaderStatusLine(reader: .cpuCoreTicks, status: .ok, reading: "3 cores"))
        #expect(ReaderStatusMac.coreTicksLine(.failure(reason)) == ReaderStatusLine(reader: .cpuCoreTicks, status: .failed(reason)))
        #expect(ReaderStatusMac.gpuUtilizationLine(.success(37))
                == ReaderStatusLine(reader: .gpuUtilization, status: .ok, reading: "37%"))
        #expect(ReaderStatusMac.gpuUtilizationLine(.failure(reason)) == ReaderStatusLine(reader: .gpuUtilization, status: .failed(reason)))
        #expect(ReaderStatusMac.gpuCoreCountLine(.success(10))
                == ReaderStatusLine(reader: .gpuCoreCount, status: .ok, reading: "10 cores"))
        #expect(ReaderStatusMac.gpuCoreCountLine(.failure(reason)) == ReaderStatusLine(reader: .gpuCoreCount, status: .failed(reason)))
        let client = GPUClientSample(pid: 1, name16: "a", gpuTimeNs: 5)
        #expect(ReaderStatusMac.gpuClientsLine(.success([client, client]))
                == ReaderStatusLine(reader: .gpuClients, status: .ok, reading: "2 clients"))
        #expect(ReaderStatusMac.gpuClientsLine(.success([]))
                == ReaderStatusLine(reader: .gpuClients, status: .ok, reading: "0 clients"))
        #expect(ReaderStatusMac.gpuClientsLine(.failure(reason)) == ReaderStatusLine(reader: .gpuClients, status: .failed(reason)))
    }

    @Test func memoryPressureReading() {
        #expect(ReaderStatusMac.memoryPressureLine(.success(.normal))
                == ReaderStatusLine(reader: .systemMemoryPressure, status: .ok, reading: "normal"))
        #expect(ReaderStatusMac.memoryPressureLine(.success(.warn))
                == ReaderStatusLine(reader: .systemMemoryPressure, status: .ok, reading: "warn"))
        #expect(ReaderStatusMac.memoryPressureLine(.success(.critical))
                == ReaderStatusLine(reader: .systemMemoryPressure, status: .ok, reading: "critical"))
        let implausible = ReaderReason.implausible(what: "kern.memorystatus_vm_pressure_level", value: "3", accepted: "1, 2 or 4")
        #expect(ReaderStatusMac.memoryPressureLine(.failure(implausible))
                == ReaderStatusLine(reader: .systemMemoryPressure, status: .failed(implausible)))
    }

    @Test func simpleRowsKeepNoReading() {
        #expect(ReaderStatusMac.simpleLine(.systemLoadAverage, Result<[Double], ReaderReason>.success([1, 2, 3]))
                == ReaderStatusLine(reader: .systemLoadAverage, status: .ok))
        let rc = ReaderReason.callFailed(call: "getloadavg", code: -1)
        #expect(ReaderStatusMac.simpleLine(.systemLoadAverage, Result<[Double], ReaderReason>.failure(rc))
                == ReaderStatusLine(reader: .systemLoadAverage, status: .failed(rc)))
    }

    @Test func powerSources() {
        #expect(ReaderStatusMac.powerSourcesLine(.success(nil))
                == ReaderStatusLine(reader: .batteryPowerSources,
                                    status: .notApplicable(.empty(what: "IOPS source of type InternalBattery"))))
        let info = BatteryInfo(source: .battery, charge: 81, state: .discharging, cycles: nil, condition: nil, maxCapacity: nil)
        #expect(ReaderStatusMac.powerSourcesLine(.success(info))
                == ReaderStatusLine(reader: .batteryPowerSources, status: .ok, reading: "charge 81%"))
        var noCharge = info
        noCharge.charge = nil
        #expect(ReaderStatusMac.powerSourcesLine(.success(noCharge))
                == ReaderStatusLine(reader: .batteryPowerSources, status: .ok))
        let nullInfo = ReaderReason.nullResult(call: "IOPSCopyPowerSourcesInfo")
        #expect(ReaderStatusMac.powerSourcesLine(.failure(nullInfo))
                == ReaderStatusLine(reader: .batteryPowerSources, status: .failed(nullInfo)))
    }
}

/// READER-STATUS S4: the command-based mappings (spec T1 rows 1, 22-24, 26), built from literal outcomes.
struct ReaderStatusMacS4Tests {
    private let emptyPlistArray = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<array/>\n</plist>\n"
    private func lineOf(_ id: ReaderID, _ status: ReaderStatus, _ reading: String? = nil) -> ReaderStatusLine {
        ReaderStatusLine(reader: id, status: status, reading: reading)
    }

    @Test func systemVersionBranches() {
        let path = "/System/Library/CoreServices/SystemVersion.plist"
        #expect(ReaderStatusMac.systemVersionLine(dataRead: false, parsed: false)
                == lineOf(.systemVersion, .failed(.nullResult(call: "FileManager.contents(\(path))"))))
        #expect(ReaderStatusMac.systemVersionLine(dataRead: true, parsed: false)
                == lineOf(.systemVersion, .failed(.unparsed(tool: "SystemVersion.plist"))))
        #expect(ReaderStatusMac.systemVersionLine(dataRead: true, parsed: true) == lineOf(.systemVersion, .ok))
    }

    @Test func pmsetBranches() {
        let desktop = BatteryInfo(source: .ac, charge: nil, state: nil, cycles: nil, condition: nil, maxCapacity: nil)
        #expect(ReaderStatusMac.pmsetLine(termination: .exited(0), stdout: "Now drawing from 'AC Power'\n", info: desktop)
                == lineOf(.batteryPmset, .notApplicable(.empty(what: "InternalBattery line in pmset -g batt"))))
        #expect(ReaderStatusMac.pmsetLine(termination: .launchFailed(2), stdout: "", info: nil)
                == lineOf(.batteryPmset, .failed(.command(tool: "pmset -g batt", termination: .launchFailed(2)))))
        let laptop = BatteryInfo(source: .battery, charge: 64, state: .discharging, cycles: nil, condition: nil, maxCapacity: nil)
        #expect(ReaderStatusMac.pmsetLine(termination: .exited(0), stdout: "x\n", info: laptop)
                == lineOf(.batteryPmset, .ok, "charge 64%"))
    }

    @Test func spPowerBranches() {
        let tool = "system_profiler SPPowerDataType"
        #expect(ReaderStatusMac.spPowerLine(termination: .exited(0), stdout: "Power:\n", cycles: nil,
                                            profileHasBattery: false, pmsetCharge: nil)
                == lineOf(.batterySystemProfiler,
                          .notApplicable(.empty(what: "battery fields in system_profiler SPPowerDataType"))))
        #expect(ReaderStatusMac.spPowerLine(termination: .exited(0), stdout: "Power:\n", cycles: nil,
                                            profileHasBattery: false, pmsetCharge: 50)
                == lineOf(.batterySystemProfiler, .failed(.unparsed(tool: tool))))
        #expect(ReaderStatusMac.spPowerLine(termination: .exited(0), stdout: "Power:\n", cycles: 312,
                                            profileHasBattery: true, pmsetCharge: 50)
                == lineOf(.batterySystemProfiler, .ok, "312 cycles"))
        #expect(ReaderStatusMac.spPowerLine(termination: .timedOut, stdout: "", cycles: nil,
                                            profileHasBattery: false, pmsetCharge: nil)
                == lineOf(.batterySystemProfiler, .failed(.command(tool: tool, termination: .timedOut))))
    }

    @Test func ioregBranches() {
        let tool = "ioreg -r -c AppleSmartBattery -a -l"
        #expect(ReaderStatusMac.ioregBatteryLine(termination: .exited(0), stdout: emptyPlistArray, parsed: false)
                == lineOf(.batteryIoreg, .notApplicable(.serviceAbsent(className: "AppleSmartBattery"))))
        #expect(ReaderStatusMac.ioregBatteryLine(termination: .timedOut, stdout: "", parsed: false)
                == lineOf(.batteryIoreg, .failed(.command(tool: tool, termination: .timedOut))))
        #expect(ReaderStatusMac.ioregBatteryLine(termination: .exited(0), stdout: "garbage", parsed: false)
                == lineOf(.batteryIoreg, .failed(.unparsed(tool: tool))))
        #expect(ReaderStatusMac.ioregBatteryLine(termination: .exited(0), stdout: "<plist/>", parsed: true)
                == lineOf(.batteryIoreg, .ok))
    }

    @Test func internalSmartBranches() {
        let paths = ["/opt/homebrew/sbin/smartctl", "/opt/homebrew/bin/smartctl",
                     "/usr/local/sbin/smartctl", "/usr/local/bin/smartctl"]
        #expect(ReportCollector.smartctlPaths == paths)
        #expect(ReaderStatusMac.internalSmartLine(smartctl: nil, diskutilOK: true, tool: "smartctl -A -j disk0",
                                                  termination: nil, stdout: "", attrCount: 0)
                == lineOf(.diskInternalSmart, .notApplicable(.executableAbsent(name: "smartctl", searched: paths))))
        #expect(ReaderStatusMac.internalSmartLine(smartctl: "/opt/homebrew/sbin/smartctl", diskutilOK: false,
                                                  tool: "smartctl -A -j disk0", termination: nil, stdout: "", attrCount: 0)
                == lineOf(.diskInternalSmart, .failed(.prerequisiteFailed(reader: .diskInternalInfo))))
        #expect(ReaderStatusMac.internalSmartLine(smartctl: "/opt/homebrew/sbin/smartctl", diskutilOK: true,
                                                  tool: "sudo -n smartctl -A -j disk0", termination: .exited(4),
                                                  stdout: "{}", attrCount: 12)
                == lineOf(.diskInternalSmart, .ok, "12 attributes"))
    }

    @Test func isEmptyPlistArrayCases() {
        #expect(ReaderStatusMac.isEmptyPlistArray(emptyPlistArray))
        let full = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<array><string>a</string></array>\n</plist>\n"
        #expect(!ReaderStatusMac.isEmptyPlistArray(full))
        #expect(!ReaderStatusMac.isEmptyPlistArray("not a plist"))
    }
}
