// Tests/MacDashboardTests/CPUFrequencyReaderTests.swift
// SOC-DETAILS 1.2: the D2 setup checks, the residency-weighted average, the table parser and the idle threshold (D3).
import Foundation
import Testing
@testable import MacDashboard

/// Measured on the reference Mac: E table 744-2748 MHz (7 steps), P table 816-4056 MHz (20 steps).
private let eTable: [Double] = [744, 1032, 1272, 1668, 2064, 2400, 2748]
private let pTable: [Double] = (0..<20).map { 816 + Double($0) * (4056 - 816) / 19 }

struct CPUFrequencyReaderTests {
    // MARK: validate (D2 a-d)

    @Test func measuredTablesPass() {
        #expect(CPUFrequencyReader.validate(table: eTable, stateCount: 8))      // 7 + 1 idle
        #expect(CPUFrequencyReader.validate(table: pTable, stateCount: 21))     // 20 + 1 idle
    }

    @Test func tooShortTableFailsA() {
        #expect(!CPUFrequencyReader.validate(table: [], stateCount: 1))
        #expect(!CPUFrequencyReader.validate(table: [1000], stateCount: 2))
    }

    @Test func notStrictlyAscendingFailsB() {
        // The shape of the GPU table in the same source (…1056, 1053…).
        #expect(!CPUFrequencyReader.validate(table: [338, 618, 796, 924, 1056, 1053], stateCount: 7))
        #expect(!CPUFrequencyReader.validate(table: [1000, 1000, 2000], stateCount: 4))   // equal neighbours
    }

    @Test func boundsFailC() {
        #expect(!CPUFrequencyReader.validate(table: [99, 2000], stateCount: 3))          // 99 MHz < 100
        #expect(CPUFrequencyReader.validate(table: [100, 2000], stateCount: 3))
        #expect(!CPUFrequencyReader.validate(table: [1000, 10_001], stateCount: 3))      // above 10 000
        #expect(CPUFrequencyReader.validate(table: [1000, 10_000], stateCount: 3))
        #expect(!CPUFrequencyReader.validate(table: [0.8, 4.0], stateCount: 3))          // GHz instead of MHz
    }

    @Test func stateCountMismatchFailsD() {
        // The GPU has 14 table entries and 16 states: not entries + 1.
        let gpu: [Double] = (0..<14).map { 338 + Double($0) * 50 }
        #expect(!CPUFrequencyReader.validate(table: gpu, stateCount: 16))
        #expect(!CPUFrequencyReader.validate(table: eTable, stateCount: 7))
        #expect(!CPUFrequencyReader.validate(table: eTable, stateCount: 9))
    }

    // MARK: weightedMHz

    private func names(_ active: Int) -> [String] { ["IDLE"] + (0..<active).map { "V\($0)P\(0)" } }

    @Test func allIdleHasNoActiveShare() {
        let r = CPUFrequencyReader.weightedMHz(residencies: [500, 0, 0, 0, 0, 0, 0, 0], stateNames: names(7), table: eTable)
        #expect(r?.active == 0)
        #expect(r?.mhz == 0)
    }

    @Test func oneStateGivesThatFrequency() {
        // All active time in state index 2 (1272 MHz), half the sample idle.
        var res = [Double](repeating: 0, count: 8)
        res[0] = 100; res[3] = 100   // IDLE, then active index 2 (names[3])
        let r = CPUFrequencyReader.weightedMHz(residencies: res, stateNames: names(7), table: eTable)
        #expect(r != nil)
        #expect(abs((r?.mhz ?? 0) - 1272) < 1e-9)
        #expect(abs((r?.active ?? 0) - 0.5) < 1e-9)
    }

    @Test func mixedStatesAverageByResidency() {
        var res = [Double](repeating: 0, count: 8)
        res[1] = 100   // 744
        res[7] = 300   // 2748
        let r = CPUFrequencyReader.weightedMHz(residencies: res, stateNames: names(7), table: eTable)
        #expect(abs((r?.mhz ?? 0) - (744 * 0.25 + 2748 * 0.75)) < 1e-9)
        #expect(r?.active == 1)
    }

    @Test func idleLikeNamesAreExcludedFromTheAverage() {
        let n = ["IDLE", "DOWN", "OFF", "V0", "V1"]
        let r = CPUFrequencyReader.weightedMHz(residencies: [10, 10, 10, 50, 50], stateNames: n, table: [1000, 2000])
        #expect(abs((r?.mhz ?? 0) - 1500) < 1e-9)
        #expect(abs((r?.active ?? 0) - 100.0 / 130.0) < 1e-9)
    }

    @Test func outOfTableMappingIsNil() {
        // Eight active states against a 7-entry table.
        #expect(CPUFrequencyReader.weightedMHz(residencies: [1, 1, 1, 1, 1, 1, 1, 1, 1], stateNames: names(8), table: eTable) == nil)
        // Fewer active states than the table.
        #expect(CPUFrequencyReader.weightedMHz(residencies: [1, 1, 1], stateNames: names(2), table: eTable) == nil)
        // Lengths differ.
        #expect(CPUFrequencyReader.weightedMHz(residencies: [1, 1], stateNames: names(7), table: eTable) == nil)
    }

    @Test func negativeOrEmptySamplesAreNil() {
        var res = [Double](repeating: 1, count: 8); res[3] = -1
        #expect(CPUFrequencyReader.weightedMHz(residencies: res, stateNames: names(7), table: eTable) == nil)   // D2 (e)
        #expect(CPUFrequencyReader.weightedMHz(residencies: [Double](repeating: 0, count: 8), stateNames: names(7), table: eTable) == nil)
        #expect(CPUFrequencyReader.weightedMHz(residencies: [.nan, 1, 1, 1, 1, 1, 1, 1], stateNames: names(7), table: eTable) == nil)
    }

    @Test func averageIsWithinTheTableBounds() {
        // A true average of table values cannot leave the table, so a plain mix always passes D2 (f).
        let res: [Double] = [0, 3, 0, 5, 0, 7, 0, 11]
        let r = CPUFrequencyReader.weightedMHz(residencies: res, stateNames: names(7), table: eTable)
        #expect(r != nil)
        #expect((r?.mhz ?? 0) >= eTable.first! && (r?.mhz ?? 0) <= eTable.last!)
    }

    // MARK: table parser

    @Test func tableParsesPairsOfLittleEndianUInt32() {
        // 744 MHz = 744_000_000 Hz = 0x2C588A00, then a voltage word.
        func word(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }
        let data = Data(word(744_000_000) + word(790) + word(1_032_000_000) + word(800))
        #expect(CPUFrequencyReader.parseTable(data) == [744, 1032])
        #expect(CPUFrequencyReader.parseTable(Data([0x00, 0x8a, 0x58, 0x2c, 0x16, 0x03, 0x00, 0x00])) == [744])   // bytes as in the registry
        #expect(CPUFrequencyReader.parseTable(Data()) == nil)
        #expect(CPUFrequencyReader.parseTable(Data([1, 2, 3, 4, 5])) == nil)
    }

    // MARK: idle threshold (D3) and group mapping

    @Test func idleThresholdIsFivePercent() {
        #expect(CPUFrequency.idleShare == 0.05)
        #expect(CPUFrequency.state(from: nil) == .unavailable)
        #expect(CPUFrequency.state(from: FrequencyReading(mhz: 1419, activeShare: 0.009)) == .idle)      // P at rest, 0.9 %
        #expect(CPUFrequency.state(from: FrequencyReading(mhz: 1270, activeShare: 0.31)) == .mhz(1270))  // E at rest, 31 %
        #expect(CPUFrequency.state(from: FrequencyReading(mhz: 3000, activeShare: 0.05)) == .mhz(3000))  // exactly 5 % is a number
        #expect(CPUFrequency.state(from: FrequencyReading(mhz: 3000, activeShare: 0.0499)) == .idle)
    }

    @Test func groupNamesMapToChannels() {
        #expect(CoreGroupKey(groupName: "Efficiency") == .efficiency)
        #expect(CoreGroupKey(groupName: "Performance") == .performance)
        #expect(CoreGroupKey(groupName: "Super") == nil)
        #expect(CoreGroupKey(groupName: nil) == nil)
    }
}
