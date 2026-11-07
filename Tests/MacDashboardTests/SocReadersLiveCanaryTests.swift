// Tests/MacDashboardTests/SocReadersLiveCanaryTests.swift
// SOC-DETAILS 1.7: opt-in live canaries for the six SoC readers, each checked against an independent source.
// Run: MACDASH_LIVE=1 swift test --filter liveCanary. Reads only; the frequency canary spins two threads for 2 s.
// Every line printed here starts with `liveCanary`.
import Foundation
import Testing
@testable import MacDashboard

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
            let w = try #require(SMCReader.readSystemPowerW(), "PSTR returned nil")
            let batt = await ioregBattery()
            let external = batt["ExternalConnected"] ?? "?", charging = batt["IsCharging"] ?? "?"
            let volts = Double(batt["Voltage"] ?? "")
            let amps = batt["InstantAmperage"].flatMap { UInt64($0) }.map { Double(Int64(bitPattern: $0)) }
            print(String(format: "liveCanary power PSTR %.2f W", w))
            print("liveCanary power battery ExternalConnected=\(external) IsCharging=\(charging) Voltage=\(batt["Voltage"] ?? "nil") mV InstantAmperage=\(amps.map { String(format: "%.0f", $0) } ?? "nil") mA")
            #expect(w > 0 && w <= 1000)
            if external == "No", let volts, let amps {
                let discharge = volts * abs(amps) / 1e6
                print(String(format: "liveCanary power battery V x |A| = %.2f W, difference %.2f W", discharge, abs(w - discharge)))
                #expect(abs(w - discharge) <= 1.5)
            } else {
                print("liveCanary power AC: no battery comparison")
            }
        }
    }
}
