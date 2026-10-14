// Tests/MacDashboardTests/SmokeTests.swift
// Port of Checks/main.swift lines 927-1014 (CHECKS-SWIFT-TESTING). Real-machine smoke checks (LiveCollector, process limit, ReportCollector).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct SmokeTests {
        @Test func liveCollectorSmoke() async {
            // =====================================================================
            // MARK: - SMOKE (real machine)
            // =====================================================================

            do {
                let collector = LiveCollector()
                _ = await collector.collect(limit: 10)
                Thread.sleep(forTimeInterval: 1.3)
                let snap2 = await collector.collect(limit: 10)
                #expect(snap2.cpu != nil, "smoke LiveCollector: 2nd sample cpu != nil")
                #expect((snap2.mem?.total ?? 0) > 4 * GIB, "smoke LiveCollector: mem.total > 4 GiB")
                #expect((snap2.disk?.size ?? 0) > 0, "smoke LiveCollector: disk.size > 0")
                #expect(snap2.disk?.purgeable.map { $0 > 0 } ?? true, "smoke LiveCollector: purgeable, when known, is > 0")
                #expect(snap2.disk.map { d in (d.purgeable ?? 0) < d.size } ?? false, "smoke LiveCollector: purgeable < volume size")
                #expect(snap2.load != nil, "smoke LiveCollector: load != nil")
                #expect(snap2.ncpu >= 1, "smoke LiveCollector: ncpu >= 1 (got \(snap2.ncpu))")
                // Exercises the REAL `/bin/ps -axww -o pid=,rss=,time=,comm=` output on this
                // machine end-to-end through the ProcessSampler ps-snapshot path (a synthetic
                // fixture only proves the parser handles an assumed format, not that the real
                // `ps` columns actually match it).
                #expect(!snap2.topCPU.isEmpty, "smoke LiveCollector: topCPU non-empty (real ps snapshot parse)")
                #expect(snap2.topCPU.first?.pid != nil, "smoke LiveCollector: live pid parsed through ps snapshot path")
                #expect(!snap2.topMem.isEmpty, "smoke LiveCollector: topMem non-empty")
                // sample() may legitimately return fewer rows than the limit, so <= not ==.
                #expect(snap2.topCPU.count <= 10,
                      "smoke LiveCollector: topCPU.count <= processListLimit")
                #expect(snap2.topMem.count <= 10,
                      "smoke LiveCollector: topMem.count <= processListLimit")
                #expect(snap2.topCPU.allSatisfy { $0.cpu != nil },
                      "smoke LiveCollector: every topCPU row has a cpu value (sampler primed itself)")
            }
        }

        @Test func processLimitResolution() async {
            do {
                #expect(AppSettings.allowedProcessLimits.allSatisfy { AppSettings.resolveProcessLimit(raw: $0) == $0 },
                      "AppSettings: every offered process limit resolves to itself")
                #expect(AppSettings.allowedProcessLimits.contains(AppSettings.resolveProcessLimit(raw: 0)),
                      "AppSettings: the fallback process limit is one of the offered values")
                #expect(AppSettings.resolveProcessLimit(raw: 12) == 10, "AppSettings: the retired hard-coded 12 migrates to 10")
                // Re-check of the resolution formula via the real product function (AppSettings.init()
                // calls the same one — see AppSettings.resolveProcessLimit).
                #expect(AppSettings.resolveProcessLimit(raw: 0) == 10, "AppSettings: fresh default (unset) resolves to 10")
                #expect(AppSettings.resolveProcessLimit(raw: 999) == 10, "AppSettings: out-of-range stored value resolves to 10")
            }
        }

        @Test func reportCollectorSmoke() async {
            do {
                let result: FullReport? = await ReportCollector().collect(skipSlow: true) { _ in }
                #expect(result?.system != nil, "smoke ReportCollector: system != nil")
                #expect(result?.security != nil, "smoke ReportCollector: security != nil")
                #expect((result?.smart?.isEmpty == false), "smoke ReportCollector: smart non-empty")
                #expect(result?.autostart != nil, "smoke ReportCollector: autostart != nil")
                #expect(result?.snapshots != nil,
                      "smoke ReportCollector: snapshots != nil — an empty local-snapshot list is an ANSWER, not 'not checked' (V21-HONEST-EXITS)")
                #expect(!hasBattery || result?.battery != nil,
                      "smoke ReportCollector: battery != nil (or no battery on this machine)")
                #expect(result?.energy != nil, "smoke ReportCollector: energy != nil")
                #expect(result?.crashes != nil,
                      "smoke ReportCollector: crashes != nil (the section answers even if a directory is unreadable)")
                // Block N7 smoke — on a real developer machine with smartctl + the NOPASSWD
                // sudo rule, the disk reporting itself as "internal" should carry parsed SMART
                // attrs. Hosted CI runners (GitHub Actions sets CI=true) have unpredictable disk
                // topology — the boot/data volume isn't guaranteed to be tagged "internal" by
                // our detection heuristic at all, let alone carry parseable attrs — so this
                // assertion only runs outside CI; `smart non-empty` two lines above already
                // covers that the smartctl parsing pipeline works at all in every environment.
                let isCI = ProcessInfo.processInfo.environment["CI"] != nil
                #expect(result?.system?.osVersion != nil, "smoke ReportCollector: system osVersion != nil (SystemVersion.plist)")
                #expect(result?.system?.osBuild != nil, "smoke ReportCollector: system osBuild != nil")
                #expect(result?.system?.chip != nil, "smoke ReportCollector: system chip != nil")
                #expect(isCI || (result?.system?.modelName != nil && result?.system?.cores != nil && result?.system?.memBytes != nil),
                      "smoke ReportCollector: system_profiler -json model/cores/memory (skipped under CI)")
                let internalDisk = result?.smart?.first { $0.device == "internal" }
                #expect(isCI || internalDisk?.attrs.isEmpty == false,
                      "smoke ReportCollector: internal disk has parsed SMART attrs (smartctl -A disk0; skipped under CI)")
                #expect(isCI || result?.parseFailures.isEmpty == true,
                      "smoke ReportCollector: no parse failures recorded (skipped under CI) — got \(result?.parseFailures.map(\.commandLine) ?? [])")
            }
        }
    }
}
