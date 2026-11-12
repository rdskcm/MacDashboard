// Tests/MoonportTests/GPUClientRankingTests.swift
// SOC-DETAILS 1.3: ranking of GPU clients between two samples (D10-D13) and the pure parts of the client reader.
import Foundation
import Testing
@testable import Moonport

private func c(_ pid: Int32, _ name: String, _ ns: UInt64) -> GPUClientSample {
    GPUClientSample(pid: pid, name16: name, gpuTimeNs: ns)
}
private let noNames: @Sendable (Int32) -> String? = { _ in nil }

struct GPUClientRankingTests {
    @Test func sharePerElapsedSecond() {
        // 0.2 s of GPU time in 2 s = 10 %.
        let rows = GPUClientRanking.rows(prev: [c(1, "A", 1_000)], cur: [c(1, "A", 1_000 + 200_000_000)], dtSeconds: 2, names: noNames)
        #expect(rows.count == 1)
        #expect(abs((rows[0].sharePct ?? 0) - 10) < 1e-9)
    }

    @Test func clientsOfOnePidAreSummed() {
        let prev = [c(7, "Safari", 100), c(7, "Safari", 200), c(8, "Dock", 0)]
        let cur = [c(7, "Safari", 100 + 100_000_000), c(7, "Safari", 200 + 300_000_000), c(8, "Dock", 0)]
        let rows = GPUClientRanking.rows(prev: prev, cur: cur, dtSeconds: 1, names: noNames)
        #expect(rows.map(\.id) == [7, 8])
        #expect(abs((rows[0].sharePct ?? 0) - 40) < 1e-9)
    }

    @Test func newPidGetsNoRowThisTick() {
        let rows = GPUClientRanking.rows(prev: [c(1, "A", 0)], cur: [c(1, "A", 10), c(2, "New", 999_999_999)], dtSeconds: 1, names: noNames)
        #expect(rows.map(\.id) == [1])
    }

    @Test func counterThatWentDownGetsNoRow() {
        let rows = GPUClientRanking.rows(prev: [c(1, "A", 5_000), c(2, "B", 10)], cur: [c(1, "A", 100), c(2, "B", 20)], dtSeconds: 1, names: noNames)
        #expect(rows.map(\.id) == [2])
    }

    @Test func aPidThatExitedLeavesTheList() {
        let rows = GPUClientRanking.rows(prev: [c(1, "A", 0), c(2, "B", 0)], cur: [c(2, "B", 0)], dtSeconds: 1, names: noNames)
        #expect(rows.map(\.id) == [2])
    }

    @Test func shareAbove101IsNil() {
        let rows = GPUClientRanking.rows(prev: [c(1, "A", 0), c(2, "B", 0)],
                                         cur: [c(1, "A", 1_010_000_000), c(2, "B", 1_011_000_000)], dtSeconds: 1, names: noNames)
        #expect(rows.first { $0.id == 1 }?.sharePct != nil)     // exactly 101 is still plausible
        #expect(rows.first { $0.id == 2 }?.sharePct == nil)
    }

    @Test func implausibleShareRanksLast() {
        let rows = GPUClientRanking.rows(prev: [c(1, "Real", 0), c(2, "Garbage", 0)],
                                         cur: [c(1, "Real", 100_000_000), c(2, "Garbage", 5_000_000_000)], dtSeconds: 1, names: noNames)
        #expect(rows.map(\.id) == [1, 2])
        #expect(rows[1].sharePct == nil)
    }

    @Test func rankedByShareThenLifetimeThenName() {
        let prev = [c(1, "Zed", 0), c(2, "Alpha", 0), c(3, "Mid", 0), c(4, "Busy", 0), c(5, "Beta", 0)]
        let cur = [c(1, "Zed", 500), c(2, "Alpha", 500), c(3, "Mid", 500), c(4, "Busy", 900_000_000), c(5, "Beta", 500)]
        let rows = GPUClientRanking.rows(prev: prev, cur: cur, dtSeconds: 1, names: noNames)
        #expect(rows.first?.id == 4)
        // The four tied at the same share and lifetime 500 rank by name.
        #expect(rows.dropFirst().map(\.name) == ["Alpha", "Beta", "Mid", "Zed"])
    }

    @Test func tiesAtZeroRankByLifetimeDescending() {
        let prev = [c(1, "A", 10), c(2, "B", 30), c(3, "C", 20)]
        let rows = GPUClientRanking.rows(prev: prev, cur: prev, dtSeconds: 2, names: noNames)
        #expect(rows.map(\.id) == [2, 3, 1])
        #expect(rows.allSatisfy { $0.sharePct == 0 })
    }

    @Test func exactlyTheFirstFive() {
        let prev = (1...9).map { c(Int32($0), "P\($0)", 0) }
        let cur = (1...9).map { c(Int32($0), "P\($0)", UInt64($0) * 1_000_000) }
        let rows = GPUClientRanking.rows(prev: prev, cur: cur, dtSeconds: 1, names: noNames)
        #expect(rows.count == 5)
        #expect(rows.map(\.id) == [9, 8, 7, 6, 5])
        // Fewer than 5 pids: no padding here, the view keeps the height.
        #expect(GPUClientRanking.rows(prev: prev.prefix(2).map { $0 }, cur: cur.prefix(2).map { $0 }, dtSeconds: 1, names: noNames).count == 2)
    }

    @Test func nameComesFromTheLookupElseTheSourceName() {
        let prev = [c(1, "ThemeWidgetContr", 0), c(2, "Dock", 0)]
        let cur = [c(1, "ThemeWidgetContr", 5), c(2, "Dock", 4)]
        let rows = GPUClientRanking.rows(prev: prev, cur: cur, dtSeconds: 1, names: { $0 == 1 ? "ThemeWidgetController" : nil })
        #expect(rows.first { $0.id == 1 }?.name == "ThemeWidgetController")
        #expect(rows.first { $0.id == 2 }?.name == "Dock")   // lookup failed: the 16-character name as read, no ellipsis
    }

    @Test func nonPositiveIntervalGivesNoRows() {
        #expect(GPUClientRanking.rows(prev: [c(1, "A", 0)], cur: [c(1, "A", 1)], dtSeconds: 0, names: noNames).isEmpty)
        #expect(GPUClientRanking.rows(prev: [c(1, "A", 0)], cur: [c(1, "A", 1)], dtSeconds: -1, names: noNames).isEmpty)
    }

    // MARK: pure parts of the client reader

    @Test func creatorStringParses() {
        let p = GPUStats.parseClientCreator("pid 123, WindowServer")
        #expect(p?.pid == 123 && p?.name16 == "WindowServer")
        #expect(GPUStats.parseClientCreator("pid 7, Name, with comma")?.name16 == "Name, with comma")
        #expect(GPUStats.parseClientCreator("pid 123") == nil)
        #expect(GPUStats.parseClientCreator("pid abc, X") == nil)
        #expect(GPUStats.parseClientCreator("pid 0, kernel") == nil)
        #expect(GPUStats.parseClientCreator("kernel_task") == nil)
    }

    @Test func appUsageSumsAccumulatedTime() {
        let usage: [[String: Any]] = [["accumulatedGPUTime": NSNumber(value: 100)], ["accumulatedGPUTime": NSNumber(value: 250)], ["other": 1]]
        #expect(GPUStats.accumulatedGPUTimeNs(appUsage: usage) == 350)
        #expect(GPUStats.accumulatedGPUTimeNs(appUsage: []) == nil)
        #expect(GPUStats.accumulatedGPUTimeNs(appUsage: [["other": 1]]) == nil)
    }
}
