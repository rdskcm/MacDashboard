// Engine/ReaderStatusMac.swift
// READER-STATUS: Mac reader identifiers, their report order and the pure status mappings.
// The device-neutral types live in ReaderStatus.swift.
import Foundation

extension ReaderID {
    static let systemVersion = ReaderID("system.version")
    static let systemHardwareProfile = ReaderID("system.hardwareProfile")
    static let systemCPUBrand = ReaderID("system.cpuBrand")
    static let smcConnection = ReaderID("smc.connection")
    static let smcChipTemperature = ReaderID("smc.chipTemperature")
    static let smcPower = ReaderID("smc.power")
    static let smcSensors = ReaderID("smc.sensors")
    static let hidTemperature = ReaderID("hid.temperature")
    static let cpuTopology = ReaderID("cpu.topology")
    static let cpuCoreTicks = ReaderID("cpu.coreTicks")
    static let cpuFrequency = ReaderID("cpu.frequency")
    static let gpuUtilization = ReaderID("gpu.utilization")
    static let gpuCoreCount = ReaderID("gpu.coreCount")
    static let gpuClients = ReaderID("gpu.clients")
    static let systemCPULoad = ReaderID("system.cpuLoad")
    static let systemLoadAverage = ReaderID("system.loadAverage")
    static let systemMemory = ReaderID("system.memory")
    static let systemSwap = ReaderID("system.swap")
    static let systemMemoryPressure = ReaderID("system.memoryPressure")
    static let systemVolume = ReaderID("system.volume")
    static let batteryPowerSources = ReaderID("battery.powerSources")
    static let batteryPmset = ReaderID("battery.pmset")
    static let batterySystemProfiler = ReaderID("battery.systemProfiler")
    static let batteryIoreg = ReaderID("battery.ioreg")
    static let diskInternalInfo = ReaderID("disk.internalInfo")
    static let diskInternalSmart = ReaderID("disk.internalSmart")
    static let diskExternalList = ReaderID("disk.externalList")

    /// Report order of the Mac readers (spec T1 rows 1-27).
    static let macOrder: [ReaderID] = [
        .systemVersion, .systemHardwareProfile, .systemCPUBrand,
        .smcConnection, .smcChipTemperature, .smcPower,
        .smcSensors, .hidTemperature, .cpuTopology,
        .cpuCoreTicks, .cpuFrequency, .gpuUtilization,
        .gpuCoreCount, .gpuClients, .systemCPULoad,
        .systemLoadAverage, .systemMemory, .systemSwap,
        .systemMemoryPressure, .systemVolume, .batteryPowerSources,
        .batteryPmset, .batterySystemProfiler, .batteryIoreg,
        .diskInternalInfo, .diskInternalSmart, .diskExternalList,
    ]
}

enum ReaderStatusMac {
    /// Pure. The generic command rule (spec T3).
    static func commandStatus(tool: String, termination: CommandOutcome.Termination, stdout: String, parsed: Bool) -> ReaderStatus {
        let blank = stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch termination {
        case .launchFailed, .timedOut, .cancelled:
            return .failed(.command(tool: tool, termination: termination))
        case .signaled:
            if blank { return .failed(.command(tool: tool, termination: termination)) }
        case .exited(let code):
            if blank { return code == 0 ? .failed(.emptyOutput(tool: tool)) : .failed(.command(tool: tool, termination: termination)) }
        }
        return parsed ? .ok : .failed(.unparsed(tool: tool))
    }

    /// Pure. `reading` is kept only when the status is `.ok`.
    static func commandLine(_ id: ReaderID, tool: String, termination: CommandOutcome.Termination, stdout: String,
                            parsed: Bool, reading: String? = nil) -> ReaderStatusLine {
        let status = commandStatus(tool: tool, termination: termination, stdout: stdout, parsed: parsed)
        return ReaderStatusLine(reader: id, status: status, reading: status == .ok ? reading : nil)
    }

    /// Pure. Success is `.ok` with `reading(value)`; failure is `.failed(reason)`.
    static func simpleLine<T>(_ id: ReaderID, _ result: Result<T, ReaderReason>,
                              reading: (T) -> String? = { _ in nil }) -> ReaderStatusLine {
        switch result {
        case .success(let value): return ReaderStatusLine(reader: id, status: .ok, reading: reading(value))
        case .failure(let reason): return ReaderStatusLine(reader: id, status: .failed(reason))
        }
    }
}

// MARK: - S2 mappings: SMC, HID, CPU frequency (spec T1 rows 4-8 and 11)

extension ReaderStatusMac {
    /// The accepted temperature range as text, from the same bounds `TemperatureSensors.isValid` uses.
    static let celsiusRange = "(\(Int(TemperatureSensors.minValid)), \(Int(TemperatureSensors.maxValid))] °C"

    /// Pure. Four lines in order connection, chipTemperature, power, sensors (T1 rows 4-7).
    static func smcLines(_ p: SMCProbe) -> [ReaderStatusLine] {
        if let failure = p.openFailure {
            let notRun = ReaderStatus.failed(.prerequisiteFailed(reader: .smcConnection))
            return [ReaderStatusLine(reader: .smcConnection, status: .failed(failure)),
                    ReaderStatusLine(reader: .smcChipTemperature, status: notRun),
                    ReaderStatusLine(reader: .smcPower, status: notRun),
                    ReaderStatusLine(reader: .smcSensors, status: notRun)]
        }
        return [ReaderStatusLine(reader: .smcConnection, status: .ok),
                smcChipLine(p.chip),
                smcPowerLine(p.power),
                smcSensorsLine(p)]
    }

    /// Pure. The decoded value of one outcome that read a value, or why it has none.
    private static func smcTemperature(_ outcome: SMCKeyOutcome) -> Result<Double, ReaderReason> {
        switch outcome.read {
        case .value(let type, let bytes):
            guard let v = SMCReader.decodeTemperature(bytes: bytes, type: type) else {
                return .failure(.smcKeyUnsupported(key: outcome.key, type: type, size: bytes.count))
            }
            guard TemperatureSensors.isValid(v) else {
                return .failure(.implausible(what: outcome.key, value: String(format: "%.1f °C", v), accepted: celsiusRange))
            }
            return .success(v)
        default:
            return .failure(SMCReader.failure(key: outcome.key, read: outcome.read)!)   // safe: not a value
        }
    }

    private static func smcChipLine(_ outcomes: [SMCKeyOutcome]) -> ReaderStatusLine {
        var reasons: [ReaderReason] = []
        for outcome in outcomes {
            switch smcTemperature(outcome) {
            case .success(let v):
                return ReaderStatusLine(reader: .smcChipTemperature, status: .ok, reading: "\(outcome.key) " + String(format: "%.1f °C", v))
            case .failure(let r): reasons.append(r)
            }
        }
        guard !reasons.isEmpty else {
            return ReaderStatusLine(reader: .smcChipTemperature, status: .failed(.empty(what: "SMC chip temperature keys")))
        }
        let allAbsent = reasons.allSatisfy { if case .smcKeyAbsent = $0 { return true } else { return false } }
        let reason = ReaderReason.joined(reasons)
        return ReaderStatusLine(reader: .smcChipTemperature, status: allAbsent ? .notApplicable(reason) : .failed(reason))
    }

    private static func smcPowerLine(_ outcome: SMCKeyOutcome?) -> ReaderStatusLine {
        func line(_ status: ReaderStatus, _ reading: String? = nil) -> ReaderStatusLine {
            ReaderStatusLine(reader: .smcPower, status: status, reading: reading)
        }
        guard let outcome else { return line(.failed(.empty(what: "SMC key \(SMCReader.systemPowerKey) read"))) }
        switch outcome.read {
        case .missing:
            return line(.notApplicable(SMCReader.failure(key: outcome.key, read: outcome.read)!))   // safe: not a value
        case .unsupported, .callFailed:
            return line(.failed(SMCReader.failure(key: outcome.key, read: outcome.read)!))
        case .value(let type, let bytes):
            guard let raw = SMCReader.decodeFloat(bytes: bytes, type: type) else {
                return line(.failed(.smcKeyUnsupported(key: SMCReader.systemPowerKey, type: type, size: bytes.count)))
            }
            guard let watts = SMCReader.plausibleWatts(raw) else {
                return line(.failed(.implausible(what: SMCReader.systemPowerKey, value: String(format: "%.2f W", raw),
                                                 accepted: "(0, \(Int(SMCReader.maxPlausibleWatts))] W")))
            }
            return line(.ok, "\(SMCReader.systemPowerKey) " + String(format: "%.2f W", watts))
        }
    }

    private static func smcSensorsLine(_ p: SMCProbe) -> ReaderStatusLine {
        func line(_ status: ReaderStatus, _ reading: String? = nil) -> ReaderStatusLine {
            ReaderStatusLine(reader: .smcSensors, status: status, reading: reading)
        }
        switch p.sensorKeys {
        case nil:
            return line(.failed(.empty(what: "SMC sensor key list read")))
        case .failure(let r)?:
            return line(.failed(r))
        case .success(let keys)?:
            if keys.isEmpty {
                return line(.notApplicable(.empty(what: "SMC sensor keys Te*, Tp*, Tg*, TB0T, TW0P, TH0x, TCHP")))
            }
            let valid = p.sensors.filter { if case .success = smcTemperature($0) { return true } else { return false } }.count
            if valid == 0 {
                return line(.failed(.implausible(what: "SMC sensor keys", value: "\(keys.count) read, 0 valid", accepted: celsiusRange)))
            }
            return line(.ok, "\(keys.count) keys, \(valid) valid")
        }
    }

    /// Pure. T1 row 8.
    static func hidLine(_ r: Result<[ThermalSensors.Reading], ReaderReason>) -> ReaderStatusLine {
        func line(_ status: ReaderStatus, _ reading: String? = nil) -> ReaderStatusLine {
            ReaderStatusLine(reader: .hidTemperature, status: status, reading: reading)
        }
        switch r {
        case .failure(let reason):
            return line(.failed(reason))
        case .success(let readings):
            if readings.isEmpty {
                return line(.notApplicable(.empty(what: "HID temperature services (usage page 0xFF00, usage 0x0005)")))
            }
            let valid = readings.filter { ThermalSensors.isValidReading($0.value) }.count
            if valid == 0 {
                return line(.failed(.implausible(what: "HID temperature readings", value: "\(readings.count) read, 0 valid", accepted: "finite > 0")))
            }
            let soc = ThermalSensors.socTemperature(from: readings).map { String(format: ", SoC die %.1f °C", $0) } ?? ""
            return line(.ok, "\(readings.count) services, \(valid) valid" + soc)
        }
    }

    /// Pure. The core types the frequency check expects: those the topology names, or both when it names none.
    static func expectedFrequencyKeys(_ groups: [CoreGroup]) -> Set<CoreGroupKey> {
        let keys = Set(groups.compactMap { CoreGroupKey(groupName: $0.name) })
        return keys.isEmpty ? [.efficiency, .performance] : keys
    }

    /// Pure. T1 row 11.
    static func frequencyLine(_ p: FrequencyProbe, expected: Set<CoreGroupKey>) -> ReaderStatusLine {
        if let r = p.setupFailure { return ReaderStatusLine(reader: .cpuFrequency, status: .failed(r)) }
        if let r = p.sampleFailure { return ReaderStatusLine(reader: .cpuFrequency, status: .failed(r)) }
        var parts: [String] = []
        var reasons: [ReaderReason] = []
        for (key, label) in [(CoreGroupKey.efficiency, "E"), (.performance, "P")] where expected.contains(key) {
            if let skipped = p.skipped[key] { reasons.append(skipped); continue }
            switch p.readings[key] {
            case .success(let reading)?:
                parts.append(reading.activeShare < CPUFrequency.idleShare
                             ? "\(label) idle"
                             : "\(label) \(Int(reading.mhz.rounded())) MHz \(Int((reading.activeShare * 100).rounded()))% active")
            case .failure(let r)?:
                reasons.append(r)
            case nil:
                reasons.append(.ioReportChannelAbsent(group: CPUFrequencyReader.groupName, subgroup: CPUFrequencyReader.subgroupName,
                                                      channel: label + "CPU"))
            }
        }
        let reading = parts.isEmpty ? nil : parts.joined(separator: ", ")
        return ReaderStatusLine(reader: .cpuFrequency, status: reasons.isEmpty ? .ok : .failed(.joined(reasons)), reading: reading)
    }
}

// MARK: - S3 mappings: CPU brand, topology, core ticks, GPU, LiveCollector readers (spec T1 rows 3, 9, 10, 12-14, 19, 21)

extension ReaderStatusMac {
    /// Pure. T1 row 3; the brand string is trimmed, blank is failed.
    static func cpuBrandLine(_ r: Result<String, ReaderReason>) -> ReaderStatusLine {
        switch r {
        case .failure(let reason):
            return ReaderStatusLine(reader: .systemCPUBrand, status: .failed(reason))
        case .success(let raw):
            let brand = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if brand.isEmpty {
                return ReaderStatusLine(reader: .systemCPUBrand, status: .failed(.empty(what: "sysctl machdep.cpu.brand_string")))
            }
            return ReaderStatusLine(reader: .systemCPUBrand, status: .ok, reading: brand)
        }
    }

    /// Pure. T1 row 9.
    static func topologyLine(_ r: Result<[CoreGroup], ReaderReason>) -> ReaderStatusLine {
        simpleLine(.cpuTopology, r) { groups in groups.map { "\($0.name ?? "unknown") \($0.count)" }.joined(separator: ", ") }
    }

    /// Pure. T1 row 10.
    static func coreTicksLine(_ r: Result<[CoreTicks], ReaderReason>) -> ReaderStatusLine {
        simpleLine(.cpuCoreTicks, r) { "\($0.count) cores" }
    }

    /// Pure. T1 row 12.
    static func gpuUtilizationLine(_ r: Result<Int, ReaderReason>) -> ReaderStatusLine {
        simpleLine(.gpuUtilization, r) { "\($0)%" }
    }

    /// Pure. T1 row 13.
    static func gpuCoreCountLine(_ r: Result<Int, ReaderReason>) -> ReaderStatusLine {
        simpleLine(.gpuCoreCount, r) { "\($0) cores" }
    }

    /// Pure. T1 row 14.
    static func gpuClientsLine(_ r: Result<[GPUClientSample], ReaderReason>) -> ReaderStatusLine {
        simpleLine(.gpuClients, r) { "\($0.count) clients" }
    }

    /// Pure. T1 row 19; the reading is `normal`, `warn` or `critical`.
    static func memoryPressureLine(_ r: Result<MemoryPressureLevel, ReaderReason>) -> ReaderStatusLine {
        simpleLine(.systemMemoryPressure, r) { "\($0)" }
    }

    /// Pure. T1 row 21; no InternalBattery source is not applicable.
    static func powerSourcesLine(_ r: Result<BatteryInfo?, ReaderReason>) -> ReaderStatusLine {
        switch r {
        case .failure(let reason):
            return ReaderStatusLine(reader: .batteryPowerSources, status: .failed(reason))
        case .success(nil):
            return ReaderStatusLine(reader: .batteryPowerSources,
                                    status: .notApplicable(.empty(what: "IOPS source of type InternalBattery")))
        case .success(let info?):
            return ReaderStatusLine(reader: .batteryPowerSources, status: .ok, reading: info.charge.map { "charge \($0)%" })
        }
    }
}

// MARK: - S4 mappings: command-based rows (spec T1 rows 1, 22-24, 26)

extension ReaderStatusMac {
    /// Pure. T1 row 1; `dataRead` is whether `FileManager.contents(atPath:)` returned data.
    static func systemVersionLine(dataRead: Bool, parsed: Bool) -> ReaderStatusLine {
        let path = "/System/Library/CoreServices/SystemVersion.plist"
        guard dataRead else {
            return ReaderStatusLine(reader: .systemVersion, status: .failed(.nullResult(call: "FileManager.contents(\(path))")))
        }
        guard parsed else {
            return ReaderStatusLine(reader: .systemVersion, status: .failed(.unparsed(tool: "SystemVersion.plist")))
        }
        return ReaderStatusLine(reader: .systemVersion, status: .ok)
    }

    /// Pure. T1 row 22; a parsed output without a charge (desktop) is not applicable.
    static func pmsetLine(termination: CommandOutcome.Termination, stdout: String, info: BatteryInfo?) -> ReaderStatusLine {
        let status = commandStatus(tool: "pmset -g batt", termination: termination, stdout: stdout, parsed: info != nil)
        guard status == .ok else { return ReaderStatusLine(reader: .batteryPmset, status: status) }
        guard let charge = info?.charge else {
            return ReaderStatusLine(reader: .batteryPmset,
                                    status: .notApplicable(.empty(what: "InternalBattery line in pmset -g batt")))
        }
        return ReaderStatusLine(reader: .batteryPmset, status: .ok, reading: "charge \(charge)%")
    }

    /// Pure. T1 row 23; unparsed without a pmset charge is a desktop, so not applicable.
    static func spPowerLine(termination: CommandOutcome.Termination, stdout: String, cycles: Int?,
                            profileHasBattery: Bool, pmsetCharge: Int?) -> ReaderStatusLine {
        let tool = "system_profiler SPPowerDataType"
        var status = commandStatus(tool: tool, termination: termination, stdout: stdout, parsed: profileHasBattery)
        if status == .failed(.unparsed(tool: tool)), pmsetCharge == nil {
            status = .notApplicable(.empty(what: "battery fields in system_profiler SPPowerDataType"))
        }
        return ReaderStatusLine(reader: .batterySystemProfiler, status: status,
                                reading: status == .ok ? cycles.map { "\($0) cycles" } : nil)
    }

    /// Pure. True when `stdout` is a property list whose top level is an empty array.
    static func isEmptyPlistArray(_ stdout: String) -> Bool {
        guard let array = (try? PropertyListSerialization.propertyList(from: Data(stdout.utf8), format: nil)) as? [Any] else {
            return false
        }
        return array.isEmpty
    }

    /// Pure. T1 row 24; an empty plist array means no AppleSmartBattery service (a desktop).
    static func ioregBatteryLine(termination: CommandOutcome.Termination, stdout: String, parsed: Bool) -> ReaderStatusLine {
        let tool = "ioreg -r -c AppleSmartBattery -a -l"
        var status = commandStatus(tool: tool, termination: termination, stdout: stdout, parsed: parsed)
        if status == .failed(.unparsed(tool: tool)), isEmptyPlistArray(stdout) {
            status = .notApplicable(.serviceAbsent(className: "AppleSmartBattery"))
        }
        return ReaderStatusLine(reader: .batteryIoreg, status: status)
    }

    /// Pure. T1 row 26, checks in this order: no smartctl, failed diskutil step, then the command rule.
    static func internalSmartLine(smartctl: String?, diskutilOK: Bool, tool: String,
                                  termination: CommandOutcome.Termination?, stdout: String,
                                  attrCount: Int) -> ReaderStatusLine {
        guard smartctl != nil else {
            return ReaderStatusLine(reader: .diskInternalSmart,
                                    status: .notApplicable(.executableAbsent(name: "smartctl", searched: ReportCollector.smartctlPaths)))
        }
        guard diskutilOK, let termination else {
            return ReaderStatusLine(reader: .diskInternalSmart, status: .failed(.prerequisiteFailed(reader: .diskInternalInfo)))
        }
        return commandLine(.diskInternalSmart, tool: tool, termination: termination, stdout: stdout,
                           parsed: attrCount > 0, reading: "\(attrCount) attributes")
    }
}
