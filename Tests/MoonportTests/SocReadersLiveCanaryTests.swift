// Tests/MoonportTests/SocReadersLiveCanaryTests.swift
// SOC-DETAILS 1.7 and TEMP-SENSORS-DETAIL: opt-in live canaries for the six SoC readers, each checked against an independent source.
// Run: MACDASH_LIVE=1 swift test --filter liveCanary. Reads only; the frequency canary spins two threads for 2 s.
// Every line printed here starts with `liveCanary`.
import Foundation
import Testing
@testable import Moonport

private let liveEnabled = ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"

private func hostCPUTicks() -> (user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)? {
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    var info = host_cpu_load_info_data_t()
    let kr = withUnsafeMutablePointer(to: &info) { p in
        p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
    }
    guard kr == KERN_SUCCESS else { return nil }
    return (UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3))
}

/// Busy loops on `threads` background threads for `seconds`.
private func spin(threads: Int, seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    let group = DispatchGroup()
    for _ in 0..<threads {
        group.enter()
        Thread.detachNewThread {
            var x: UInt64 = 1
            while Date() < end { for _ in 0..<10_000 { x = x &* 6364136223846793005 &+ 1442695040888963407 } }
            if x == 42 { print("") }   // keep the loop from being optimised away
            group.leave()
        }
    }
    group.wait()
}

private func ioregBattery() async -> [String: String] {
    let text = await CommandRunner.run("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"], timeout: 10).text ?? ""
    var out: [String: String] = [:]
    for line in text.split(separator: "\n") {
        guard let eq = line.range(of: " = ") else { continue }
        let key = line[..<eq.lowerBound].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"|+- "))
        if out[key] == nil { out[key] = String(line[eq.upperBound...]).trimmingCharacters(in: .whitespaces) }
    }
    return out
}

/// Battery discharge power (V x |A|, watts) from one `ioreg` read; nil unless the Mac is on battery with both values.
private func batteryDischargeW(_ batt: [String: String]) -> Double? {
    guard batt["ExternalConnected"] == "No", let volts = Double(batt["Voltage"] ?? ""),
          let amps = batt["InstantAmperage"].flatMap({ UInt64($0) }).map({ Double(Int64(bitPattern: $0)) }) else { return nil }
    return volts * abs(amps) / 1e6
}

/// The battery gauge publishes a new Voltage/InstantAmperage only every 30-60 s (measured), and between publications
/// it keeps showing the load of the last one, so a PSTR comparison against a stale gauge can agree or disagree by
/// accident (a run after the spin canary read PSTR 7.0 W against a stale 13.2 W). The comparison is therefore made only
/// at the instant the gauge publishes a fresh sample: record the gauge's Voltage and InstantAmperage, poll once per
/// second until either changes, require PSTR within `agreement` W of V x |A| right then, and do it for two
/// consecutive refreshes. Both must agree. The total cap is `cap` s (two refreshes take up to about 120 s).
/// `failure` is nil on a pass (and on AC or without a battery reading, where there is nothing to compare);
/// otherwise it names the reason. `checks` lists each refresh's readings.
private func gaugeRefreshPower(agreement: Double = 1.5, cap: Int = 150)
    async -> (pstr: Double?, discharge: Double?, batt: [String: String], failure: String?, checks: [String]) {
    func gauge(_ b: [String: String]) -> String { "\(b["Voltage"] ?? "nil")/\(b["InstantAmperage"] ?? "nil")" }
    var batt = await ioregBattery()
    var pstr = SMCReader.readSystemPowerW()
    var discharge = batteryDischargeW(batt)
    // On AC (or without a battery reading) there is nothing to compare, so nothing to wait for.
    guard discharge != nil else { return (pstr, nil, batt, nil, []) }
    var baseline = gauge(batt)
    var checks: [String] = []
    var elapsed = 0
    while checks.count < 2 {
        var refreshed = false
        while elapsed < cap {
            try? await Task.sleep(for: .seconds(1))
            elapsed += 1
            let b = await ioregBattery()
            pstr = SMCReader.readSystemPowerW()
            discharge = batteryDischargeW(b)
            batt = b
            if gauge(b) != baseline { refreshed = true; break }
        }
        let n = checks.count + 1
        let fmt: (Double?) -> String = { $0.map { String(format: "%.2f", $0) } ?? "nil" }
        guard refreshed else {
            return (pstr, discharge, batt, "gauge never refreshed (refresh \(n) of 2 not seen within \(cap) s; Voltage/InstantAmperage stayed \(baseline)). Last readings: PSTR \(fmt(pstr)) W, V x |A| \(fmt(discharge)) W. Earlier checks: \(checks)", checks)
        }
        guard let w = pstr, let d = discharge else {
            return (pstr, discharge, batt, "reading missing at gauge refresh \(n) of 2: PSTR \(fmt(pstr)) W, V x |A| \(fmt(discharge)) W (battery \(gauge(batt)))", checks)
        }
        checks.append(String(format: "refresh %d at %d s: PSTR %.2f W, V x |A| %.2f W, difference %.2f W", n, elapsed, w, d, abs(w - d)))
        if abs(w - d) > agreement {
            return (pstr, discharge, batt, "mismatch at gauge refresh \(n) of 2: PSTR \(fmt(w)) W vs V x |A| \(fmt(d)) W, difference \(String(format: "%.2f", abs(w - d))) W exceeds \(agreement) W. Checks: \(checks)", checks)
        }
        baseline = gauge(batt)
    }
    return (pstr, discharge, batt, nil, checks)
}

extension SerialTests {
    @MainActor struct SocReadersLiveCanaryTests {
        // MARK: core load and topology

        @Test(.enabled(if: liveEnabled))
        func liveCanaryCoreLoad() async throws {
            let groups = CoreTopology.read()
            for g in groups { print("liveCanary topology group=\(g.name ?? "unknown") count=\(g.count) indices=\(g.coreIndices)") }
            let ncpu = ProcessInfo.processInfo.activeProcessorCount
            #expect(groups.reduce(0) { $0 + $1.count } == ncpu)
            #expect(Set(groups.flatMap(\.coreIndices)) == Set(0..<ncpu))
            if groups.count == 1, groups[0].name == nil { print("liveCanary topology type unknown (fallback)") }
            else {
                for (i, g) in groups.enumerated() {
                    let cli = await CommandRunner.run("/usr/sbin/sysctl", ["-n", "hw.perflevel\(i).name"], timeout: 5).text?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    print("liveCanary topology sysctl hw.perflevel\(i).name=\(cli ?? "nil")")
                    #expect(g.name == cli)
                }
            }

            let a = try #require(CoreLoadReader.readTicks()), h0 = try #require(hostCPUTicks())
            try await Task.sleep(for: .seconds(1))
            let b = try #require(CoreLoadReader.readTicks()), h1 = try #require(hostCPUTicks())
            #expect(a.count == ncpu && b.count == ncpu)
            let usage = CoreLoadReader.usage(prev: a, cur: b)
            print("liveCanary perCore % by index: \(usage.map { $0.map(String.init) ?? "-" })")
            for g in groups {
                print("liveCanary perCore group=\(g.name ?? "unknown") % \(g.coreIndices.map { usage[$0].map(String.init) ?? "-" })")
            }
            for u in usage { if let u { #expect((0...100).contains(u)) } }
            let values = usage.compactMap { $0 }.map(Double.init)
            let mean = values.reduce(0, +) / Double(max(1, values.count))
            let (du, ds, di, dn) = (h1.user &- h0.user, h1.sys &- h0.sys, h1.idle &- h0.idle, h1.nice &- h0.nice)
            let hostBusy = Double(du + ds + dn) / Double(max(1, du + ds + di + dn)) * 100
            print(String(format: "liveCanary perCore mean %.1f%% host_statistics %.1f%% diff %.1f pp", mean, hostBusy, abs(mean - hostBusy)))
            #expect(abs(mean - hostBusy) <= 15)
        }

        // MARK: frequency

        @Test(.enabled(if: liveEnabled))
        func liveCanaryCPUFrequency() async throws {
            let setup = try #require(CPUFrequencyReader.shared, "D2 (a)-(d) failed on this Mac: the Mac or macOS changed, not the code")
            for key in [CoreGroupKey.efficiency, .performance] {
                guard let t = setup.tables[key] else { print("liveCanary freq table \(key): absent (setup check failed)"); continue }
                let states = t.mhz.count + 1
                print("liveCanary freq table \(key) entries=\(t.mhz.count) states=\(states) MHz=\(t.mhz.map { String(format: "%.0f", $0) })")
                #expect(CPUFrequencyReader.validate(table: t.mhz, stateCount: states))
            }
            #expect(!setup.tables.isEmpty)

            func window(_ during: () async throws -> Void) async throws -> [CoreGroupKey: FrequencyReading?] {
                _ = CPUFrequencyReader.sample(setup)             // baseline
                try await during()
                return try #require(CPUFrequencyReader.sample(setup))
            }
            let rest = try await window { try await Task.sleep(for: .seconds(1)) }
            for key in [CoreGroupKey.efficiency, .performance] {
                guard let entry = rest[key] else { print("liveCanary freq rest \(key): no channel"); continue }
                if let r = entry { print(String(format: "liveCanary freq rest %@ %.0f MHz active %.1f%%", "\(key)", r.mhz, r.activeShare * 100)) }
                else { print("liveCanary freq rest \(key): reading failed D2 (e)/(f)") }
            }
            if let p = rest[.performance] ?? nil {
                if p.activeShare < CPUFrequency.idleShare { print(String(format: "liveCanary idle-threshold-check: P active %.1f %% < 5 %% (shows idle)", p.activeShare * 100)) }
                else { print(String(format: "liveCanary idle-threshold-check: P active %.1f %% ≥ 5 %%", p.activeShare * 100)) }
            }

            let load = try await window { spin(threads: 2, seconds: 2) }
            let p = try #require(load[.performance] ?? nil, "no P reading under load")
            print(String(format: "liveCanary freq load P %.0f MHz active %.1f%%", p.mhz, p.activeShare * 100))
            if let e = load[.efficiency] ?? nil { print(String(format: "liveCanary freq load E %.0f MHz active %.1f%%", e.mhz, e.activeShare * 100)) }
            let pMax = try #require(setup.tables[.performance]?.mhz.last)
            #expect(p.mhz >= 0.5 * pMax)
            #expect(p.activeShare >= 0.5)
        }

        // MARK: GPU clients

        @Test(.enabled(if: liveEnabled))
        func liveCanaryGPUClients() async throws {
            let a = try #require(GPUStats.readClients())
            let t0 = Date()
            try await Task.sleep(for: .seconds(1))
            let b = try #require(GPUStats.readClients())
            let dt = Date().timeIntervalSince(t0)
            print("liveCanary gpuClients samples a=\(a.count) b=\(b.count) dt=\(String(format: "%.2f", dt)) s")
            let rows = GPUClientRanking.rows(prev: a, cur: b, dtSeconds: dt, names: { GPUClientRanking.executableName(pid: $0) })
            for r in rows { print("liveCanary gpuRow pid=\(r.id) name=\(r.name) share=\(r.sharePct.map { String(format: "%.1f%%", $0) } ?? "— (above 101)")") }
            #expect(rows.count >= 1)
            for r in rows {
                #expect(r.id > 0)
                #expect(r.sharePct != nil, "pid \(r.id) read above 101 %")
                if let s = r.sharePct { #expect((0...101).contains(s)) }
            }
            if let top = rows.first {
                let ps = await CommandRunner.run("/bin/ps", ["-o", "comm=", "-p", "\(top.id)"], timeout: 5).text?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print("liveCanary gpuRow top ps comm=\(ps ?? "nil") resolved name=\(top.name)")
                if let ps, !ps.isEmpty {
                    #expect(ps.hasSuffix(top.name) || GPUClientRanking.executableName(pid: top.id) == nil)
                }
            }
        }

        @Test(.enabled(if: liveEnabled))
        func liveCanaryGPUCoreCount() async throws {
            let n = try #require(GPUStats.readCoreCount())
            let json = await CommandRunner.run("/usr/sbin/system_profiler", ["SPDisplaysDataType", "-json"], timeout: 30).text ?? ""
            let root = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            let displays = try #require(root["SPDisplaysDataType"] as? [[String: Any]])
            let cores = displays.compactMap { $0["sppci_cores"] }.compactMap { v -> Int? in (v as? String).flatMap(Int.init) ?? (v as? Int) }.first
            print("liveCanary gpuCoreCount registry=\(n) system_profiler sppci_cores=\(cores.map(String.init) ?? "nil")")
            #expect(n == cores)
        }

        // MARK: power

        @Test(.enabled(if: liveEnabled))
        func liveCanaryPower() async throws {
            // Independent of test order: after the CPU spin canary the battery gauge is stale for 30-60 s (6-9 W
            // apart seen), so compare only at two fresh gauge samples.
            let r = await gaugeRefreshPower()
            let w = try #require(r.pstr, "PSTR returned nil")
            let batt = r.batt
            let external = batt["ExternalConnected"] ?? "?", charging = batt["IsCharging"] ?? "?"
            let amps = batt["InstantAmperage"].flatMap { UInt64($0) }.map { Double(Int64(bitPattern: $0)) }
            print(String(format: "liveCanary power PSTR %.2f W", w))
            print("liveCanary power battery ExternalConnected=\(external) IsCharging=\(charging) Voltage=\(batt["Voltage"] ?? "nil") mV InstantAmperage=\(amps.map { String(format: "%.0f", $0) } ?? "nil") mA")
            #expect(w > 0 && w <= 1000)
            if let discharge = r.discharge {
                print(String(format: "liveCanary power battery V x |A| = %.2f W, difference %.2f W", discharge, abs(w - discharge)))
                for c in r.checks { print("liveCanary power \(c)") }
                if let failure = r.failure { Issue.record("PSTR vs battery V x |A|: \(failure)") }
            } else {
                print("liveCanary power AC: no battery comparison")
            }
        }

        // MARK: temperatures (TEMP-SENSORS-DETAIL R14)

        @Test(.enabled(if: liveEnabled))
        func liveCanaryTemperatures() throws {
            let t0 = Date()
            let raw = try #require(SMCReader.readSensorTemperatures(), "SMC could not be opened or its key list could not be read")
            let first = Date().timeIntervalSince(t0)
            let t1 = Date()
            _ = SMCReader.readSensorTemperatures()
            let second = Date().timeIntervalSince(t1)
            print(String(format: "liveCanary temps first call (with enumeration) %.1f ms, second call %.1f ms, %d keys",
                         first * 1000, second * 1000, raw.count))
            for key in raw.keys.sorted() { print(String(format: "liveCanary temps smc %@ %.3f", key, raw[key] ?? .nan)) }
            let rows = TemperatureSensors.readings(from: raw)
            for r in rows { print("liveCanary temps row \(r.kind) \(r.celsius.map(String.init) ?? "nil") °C") }
            let chipRaw = try #require(SMCReader.readTemperatures(keys: TemperatureSensors.chipKeys))
            let hid = ThermalHIDReader.readTemperatureSensors()
            let tdieMax = ThermalSensors.socTemperature(from: hid)
            let chip = TemperatureSensors.chipTemperature(chipRaw) { tdieMax }
            func f(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }
            print("liveCanary temps TCMz=\(f(chipRaw["TCMz"])) TCMb=\(f(chipRaw["TCMb"])) tdieMax=\(f(tdieMax)) chip=\(f(chip))")
            #expect(!rows.isEmpty)
            #expect(rows.allSatisfy { $0.celsius.map { $0 > 10 && $0 <= 150 } ?? true })
            #expect(!raw.keys.contains { $0.hasPrefix("TG") }, "battery gas-gauge keys are never rows")
            let chipValue = try #require(chip)
            #expect(TemperatureSensors.isValid(chipValue))
            if let z = chipRaw["TCMz"], TemperatureSensors.isValid(z) {
                #expect(chipValue == z, "TCMz is first in the source order")
                // Reference Mac: TCMz idles about 9 °C above max(PMU tdie) and rises more under load (findings rows 18, 20).
                if let t = tdieMax { #expect(z >= t - 1) }
            }
            // Independent readings of the same parts (findings row 20): TB0T equals a HID "gas gauge battery" value,
            // TH0x is about "NAND CH0 temp". The HID NAND value is whole degrees (38.00, 39.00 seen), so up to 1 °C of
            // quantisation plus sampling drift separates the two: tolerance 2.0.
            let gas = hid.filter { $0.name == "gas gauge battery" && ThermalSensors.isValidReading($0.value) }.map(\.value)
            print("liveCanary temps HID gas gauge \(gas.map { f($0) }) NAND \(f(hid.first { $0.name == "NAND CH0 temp" }?.value))")
            if let b = raw["TB0T"], !gas.isEmpty { #expect(gas.contains { abs($0 - b) <= 1.0 }) }
            if let s = raw["TH0x"], let nand = hid.first(where: { $0.name == "NAND CH0 temp" })?.value {
                #expect(abs(s - nand) <= 2.0)
            }
        }
    }
}
