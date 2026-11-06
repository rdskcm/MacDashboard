// Tests/MacDashboardTests/SocDisplayTests.swift
// SOC-DETAILS Stage 5a: equality at the precision the SoC page shows (`SocDisplay`).
import Foundation
import Testing
@testable import MacDashboard

// `fmtFixed` reads the process-wide UI language (decimal separator), so the suite is serialized (`tests-layout`).
extension SerialTests {
    struct SocDisplayTests {
        private func row(_ share: Double?, name: String = "Dock", pid: Int32 = 5, lifetime: UInt64 = 1) -> GPUProcessRow {
            GPUProcessRow(id: pid, name: name, sharePct: share, lifetimeNs: lifetime)
        }

        @Test func roundedAgreesWithFmtFixed() {
            let values: [Double] = [0, 0.04, 0.05, 0.15, 0.25, 0.35, 1.005, 2.675, 9.95, 99.95, 100.05, 3953.4]
            for v in values {
                for d in [1, 2] {
                    #expect(fmtFixed(SocDisplay.rounded(v, decimals: d), decimals: d) == fmtFixed(v, decimals: d), "v = \(v), d = \(d)")
                }
            }
            var mismatches = 0
            for i in 0...100_000 {
                let v = Double(i) / 1000
                let x = fmtFixed(SocDisplay.rounded(v, decimals: 1), decimals: 1), y = fmtFixed(v, decimals: 1)
                if x != y { mismatches += 1 }
            }
            #expect(mismatches == 0)
        }

        @Test func frequencyComparesAsGHzWithTwoDecimals() {
            #expect(SocDisplay.sameOnScreen(FrequencyState.mhz(3953), .mhz(3949)))
            #expect(!SocDisplay.sameOnScreen(FrequencyState.mhz(3953), .mhz(3966)))
            #expect(!SocDisplay.sameOnScreen(FrequencyState.idle, .mhz(800)))
            #expect(!SocDisplay.sameOnScreen(FrequencyState.notYet, .unavailable))
            #expect(SocDisplay.sameOnScreen(FrequencyState.idle, .idle))
        }

        @Test func powerComparesWithOneDecimalAndNilIsADash() {
            #expect(SocDisplay.sameOnScreen(6.84, 6.76, decimals: SocDisplay.powerDecimals))
            #expect(!SocDisplay.sameOnScreen(6.84, 6.86, decimals: SocDisplay.powerDecimals))
            #expect(SocDisplay.sameOnScreen(nil, nil, decimals: SocDisplay.powerDecimals))
            #expect(!SocDisplay.sameOnScreen(nil, 0.0, decimals: SocDisplay.powerDecimals))
        }

        @Test func gpuRowsCompareByPidNameAndShownShareInOrder() {
            #expect(SocDisplay.sameOnScreen(row(2.31), row(2.34)))
            #expect(!SocDisplay.sameOnScreen(row(2.34), row(2.36)))
            #expect(SocDisplay.sameOnScreen(row(2.3, lifetime: 1), row(2.3, lifetime: 999)), "lifetimeNs is not shown")
            #expect(!SocDisplay.sameOnScreen(row(2.3, name: "Dock"), row(2.3, name: "Safari")))
            #expect(SocDisplay.sameOnScreen(row(nil), row(nil)))
            #expect(!SocDisplay.sameOnScreen(row(nil), row(0.0)))
            let a = row(1, pid: 1), b = row(2, pid: 2)
            #expect(SocDisplay.sameOnScreen(GPURowsState.rows([a, b]), .rows([a, b])))
            #expect(!SocDisplay.sameOnScreen(GPURowsState.rows([a, b]), .rows([b, a])), "order swapped")
            #expect(!SocDisplay.sameOnScreen(GPURowsState.rows([a, b]), .rows([a])), "count differs")
            #expect(!SocDisplay.sameOnScreen(GPURowsState.rows([]), .empty))
            #expect(SocDisplay.sameOnScreen(GPURowsState.empty, .empty))
            #expect(!SocDisplay.sameOnScreen(GPURowsState.notYet, .unavailable))
        }

        @Test func coreGroupsCompareWholePercentLoadsAndShownFrequency() {
            let perf = CoreGroup(name: "Performance", count: 2, coreIndices: [2, 3])
            func groups(_ load: Int?, _ f: FrequencyState) -> [CoreGroupLoad]? {
                [CoreGroupLoad(group: perf, loads: [load, 50], frequency: f)]
            }
            #expect(!SocDisplay.sameOnScreen(groups(50, .mhz(3950)), groups(51, .mhz(3950))))
            #expect(SocDisplay.sameOnScreen(groups(50, .mhz(3950)), groups(50, .mhz(3951))))
            #expect(SocDisplay.sameOnScreen(nil as [CoreGroupLoad]?, nil))
            #expect(!SocDisplay.sameOnScreen(groups(50, .idle), nil))
        }
    }
}
