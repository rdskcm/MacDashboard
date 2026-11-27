// Tests/MoonportTests/CoreLoadReaderTests.swift
// SOC-DETAILS 1.1: per-core usage math, the topology fallback rule and group ordering. Pure inputs only.
import Foundation
import Testing
@testable import Moonport

private func ticks(_ user: UInt64, _ system: UInt64, _ idle: UInt64, _ nice: UInt64 = 0) -> CoreTicks {
    CoreTicks(user: user, system: system, idle: idle, nice: nice)
}

struct CoreLoadReaderTests {
    // MARK: usage

    @Test func busyAndIdleCores() {
        let prev = [ticks(100, 50, 1000), ticks(100, 50, 1000)]
        let cur = [ticks(190, 60, 1000), ticks(100, 50, 1100)]   // core 0: all 100 new ticks busy; core 1: all idle
        #expect(CoreLoadReader.usage(prev: prev, cur: cur) == [100, 0])
    }

    @Test func niceCountsAsUser() {
        let prev = [ticks(0, 0, 0, 0)]
        let cur = [ticks(10, 10, 60, 20)]   // (10 + 10 + 20) / 100
        #expect(CoreLoadReader.usage(prev: prev, cur: cur) == [40])
    }

    @Test func roundsToWholePercent() {
        #expect(CoreLoadReader.usage(prev: [ticks(0, 0, 0)], cur: [ticks(1, 0, 2)]) == [33])    // 33.3
        #expect(CoreLoadReader.usage(prev: [ticks(0, 0, 0)], cur: [ticks(2, 0, 1)]) == [67])    // 66.7
        #expect(CoreLoadReader.usage(prev: [ticks(0, 0, 0)], cur: [ticks(1, 0, 199)]) == [1])   // 0.5 rounds up
    }

    @Test func zeroElapsedTicksIsNilForThatCoreOnly() {
        let prev = [ticks(5, 5, 5), ticks(5, 5, 5)]
        let cur = [ticks(5, 5, 5), ticks(5, 5, 15)]
        #expect(CoreLoadReader.usage(prev: prev, cur: cur) == [nil, 0])
    }

    @Test func mismatchedCountGivesAllNil() {
        let cur = [ticks(1, 1, 1), ticks(1, 1, 1), ticks(1, 1, 1)]
        #expect(CoreLoadReader.usage(prev: [ticks(0, 0, 0)], cur: cur) == [nil, nil, nil])
        #expect(CoreLoadReader.usage(prev: [], cur: []) == [])
    }

    @Test func kernelCounterWrapIsHandled() {
        // The kernel counters are 32-bit: 2^32 - 10 → 40 is 50 elapsed ticks.
        let prev = [ticks(0xFFFF_FFF6, 0, 0)]
        let cur = [ticks(40, 0, 50)]
        #expect(CoreLoadReader.usage(prev: prev, cur: cur) == [50])
    }

    // MARK: topology

    private let two = [PerfLevel(name: "Performance", count: 4), PerfLevel(name: "Efficiency", count: 4)]
    private let eeeePPPP: [Character] = ["E", "E", "E", "E", "P", "P", "P", "P"]

    @Test func matchingRegistryGivesNamedGroupsInPerflevelOrder() {
        let g = CoreTopology.resolve(levels: two, clusterLetters: eeeePPPP, ncpu: 8)
        #expect(g == [CoreGroup(name: "Performance", count: 4, coreIndices: [4, 5, 6, 7]),
                      CoreGroup(name: "Efficiency", count: 4, coreIndices: [0, 1, 2, 3])])
    }

    @Test func interleavedCoresKeepTheirIndices() {
        let letters: [Character] = ["P", "E", "P", "E", "P", "E", "P", "E"]
        let g = CoreTopology.resolve(levels: two, clusterLetters: letters, ncpu: 8)
        #expect(g.map(\.coreIndices) == [[0, 2, 4, 6], [1, 3, 5, 7]])
    }

    @Test func unfamiliarThirdTypeKeepsTheSystemsName() {
        let levels = [PerfLevel(name: "Super", count: 2), PerfLevel(name: "Performance", count: 4), PerfLevel(name: "Efficiency", count: 4)]
        let letters: [Character] = ["E", "E", "E", "E", "P", "P", "P", "P", "S", "S"]
        let g = CoreTopology.resolve(levels: levels, clusterLetters: letters, ncpu: 10)
        #expect(g.map(\.name) == ["Super", "Performance", "Efficiency"])
        #expect(g.map(\.count) == [2, 4, 4])
        #expect(g[0].coreIndices == [8, 9])
    }

    @Test func zeroCountTypeHasNoGroup() {
        let levels = [PerfLevel(name: "Performance", count: 4), PerfLevel(name: "Efficiency", count: 0)]
        let g = CoreTopology.resolve(levels: levels, clusterLetters: ["P", "P", "P", "P"], ncpu: 4)
        #expect(g.map(\.name) == ["Performance"])
    }

    private func unknown(_ n: Int) -> [CoreGroup] { [CoreGroup(name: nil, count: n, coreIndices: Array(0..<n))] }

    @Test func anyMismatchFallsBackToOneUnnamedGroup() {
        // Registry count differs from the active processor count.
        #expect(CoreTopology.resolve(levels: two, clusterLetters: Array(eeeePPPP.dropLast()), ncpu: 8) == unknown(8))
        // Perflevel sums differ from the active processor count.
        #expect(CoreTopology.resolve(levels: two, clusterLetters: eeeePPPP, ncpu: 10) == unknown(10))
        // The registry has 5 P and 3 E, the perflevels say 4 and 4.
        let skewed: [Character] = ["E", "E", "E", "P", "P", "P", "P", "P"]
        #expect(CoreTopology.resolve(levels: two, clusterLetters: skewed, ncpu: 8) == unknown(8))
        // A letter that no level claims.
        let odd: [Character] = ["E", "E", "E", "E", "P", "P", "P", "X"]
        #expect(CoreTopology.resolve(levels: two, clusterLetters: odd, ncpu: 8) == unknown(8))
        // Registry unreadable, no perflevels, an unnamed level.
        #expect(CoreTopology.resolve(levels: two, clusterLetters: nil, ncpu: 8) == unknown(8))
        #expect(CoreTopology.resolve(levels: [], clusterLetters: eeeePPPP, ncpu: 8) == unknown(8))
        #expect(CoreTopology.resolve(levels: [PerfLevel(name: nil, count: 4), PerfLevel(name: "Efficiency", count: 4)],
                                     clusterLetters: eeeePPPP, ncpu: 8) == unknown(8))
        // Two levels with the same initial are ambiguous.
        let same = [PerfLevel(name: "Performance", count: 4), PerfLevel(name: "Plus", count: 4)]
        #expect(CoreTopology.resolve(levels: same, clusterLetters: eeeePPPP, ncpu: 8) == unknown(8))
    }

    @Test func resolutionNamesTheFailedCheck() {
        func fail(_ check: String) -> Result<[CoreGroup], ReaderReason> {
            .failure(.validationFailed(what: "core topology", check: check))
        }
        func run(_ levels: [PerfLevel], _ letters: [Character], _ ncpu: Int) -> Result<[CoreGroup], ReaderReason> {
            CoreTopology.resolution(levels: .success(levels), clusterLetters: .success(letters), ncpu: ncpu)
        }
        #expect(run(two, eeeePPPP, 0) == fail("activeProcessorCount 0 > 0"))
        #expect(run([], eeeePPPP, 8) == fail("hw.perflevel0 present"))
        #expect(run(two, Array(eeeePPPP.dropLast()), 8) == fail("cluster-type count 7 == activeProcessorCount 8"))
        #expect(run(two, eeeePPPP, 10) == fail("cluster-type count 8 == activeProcessorCount 10"))
        let tenLetters = Array(eeeePPPP) + ["E", "E"]
        #expect(run(two, tenLetters, 10) == fail("perflevel core sum 8 == activeProcessorCount 10"))
        #expect(run([PerfLevel(name: nil, count: 4), PerfLevel(name: "Efficiency", count: 4)], eeeePPPP, 8)
                == fail("hw.perflevel0.name present"))
        let same = [PerfLevel(name: "Performance", count: 4), PerfLevel(name: "Plus", count: 4)]
        #expect(run(same, eeeePPPP, 8) == fail("perflevel name initials unique"))
        let skewed: [Character] = ["E", "E", "E", "P", "P", "P", "P", "P"]
        #expect(run(two, skewed, 8) == fail("Performance cores 5 == hw.perflevel0.physicalcpu 4"))
        let odd: [Character] = ["E", "E", "E", "E", "P", "P", "P", "X"]
        #expect(run(two, odd, 8) == fail("Performance cores 3 == hw.perflevel0.physicalcpu 4"))
        // The level counts sum to ncpu, but the registry letters do not match the second level.
        let zero = [PerfLevel(name: "Performance", count: 0), PerfLevel(name: "Efficiency", count: 8)]
        #expect(run(zero, eeeePPPP, 8) == fail("Efficiency cores 4 == hw.perflevel1.physicalcpu 8"))
        // A failed input returns its own reason, levels before letters.
        let levelsReason = ReaderReason.errno(call: "sysctlbyname(hw.perflevel0.physicalcpu)", code: 2)
        let lettersReason = ReaderReason.registryEntryAbsent(path: "IODeviceTree:/cpus")
        #expect(CoreTopology.resolution(levels: .failure(levelsReason), clusterLetters: .failure(lettersReason), ncpu: 8)
                == .failure(levelsReason))
        #expect(CoreTopology.resolution(levels: .success(two), clusterLetters: .failure(lettersReason), ncpu: 8)
                == .failure(lettersReason))
        // A matching input succeeds with the groups `resolve` returns.
        #expect(run(two, eeeePPPP, 8) == .success(CoreTopology.resolve(levels: two, clusterLetters: eeeePPPP, ncpu: 8)))
    }

    @Test func nodeNamesParse() {
        #expect(CoreTopology.coreIndex(fromNodeName: "cpu0") == 0)
        #expect(CoreTopology.coreIndex(fromNodeName: "cpu12") == 12)
        #expect(CoreTopology.coreIndex(fromNodeName: "cpus") == nil)
        #expect(CoreTopology.coreIndex(fromNodeName: "cpu") == nil)
        #expect(CoreTopology.coreIndex(fromNodeName: "arm-io") == nil)
    }

    // MARK: cluster letters (READER-STATUS T5)

    private func entry(_ i: Int, _ c: Character?) -> CoreTopology.ClusterTypeEntry {
        .init(index: i, clusterType: c.map { UInt8(ascii: $0.unicodeScalars.first!) })
    }

    @Test func clusterLettersSucceedInIndexOrder() throws {
        let raw: Result<[CoreTopology.ClusterTypeEntry]?, ReaderReason> =
            .success([entry(1, "P"), entry(0, "E"), entry(2, "P")])
        #expect(try CoreTopology.clusterLetters(from: raw).get() == ["E", "P", "P"])
    }

    @Test func clusterLettersEntryAbsent() {
        let r = CoreTopology.clusterLetters(from: .success(nil))
        guard case .failure(let reason) = r else { Issue.record("expected failure"); return }
        #expect(reason == .registryEntryAbsent(path: "IODeviceTree:/cpus"))
    }

    @Test func clusterLettersPropertyAbsentNamesTheChild() {
        let raw: Result<[CoreTopology.ClusterTypeEntry]?, ReaderReason> = .success([entry(0, "E"), entry(1, nil)])
        guard case .failure(let reason) = CoreTopology.clusterLetters(from: raw) else { Issue.record("expected failure"); return }
        #expect(reason == .registryPropertyAbsent(entry: "IODeviceTree:/cpus/cpu1", property: "cluster-type"))
    }

    @Test func clusterLettersIndexGapNamesTheIndices() {
        let raw: Result<[CoreTopology.ClusterTypeEntry]?, ReaderReason> = .success([entry(2, "P"), entry(0, "E")])
        guard case .failure(let reason) = CoreTopology.clusterLetters(from: raw) else { Issue.record("expected failure"); return }
        #expect(reason == .validationFailed(what: "IODeviceTree:/cpus children", check: "indices 0..<2, got [0, 2]"))
        let empty = CoreTopology.clusterLetters(from: .success([]))
        guard case .failure(let r2) = empty else { Issue.record("expected failure"); return }
        #expect(r2 == .validationFailed(what: "IODeviceTree:/cpus children", check: "indices 0..<0, got []"))
    }

    @Test func clusterLettersPassesIOKitFailureThrough() {
        let reason = ReaderReason.nullResult(call: "x")
        guard case .failure(let r) = CoreTopology.clusterLetters(from: .failure(reason)) else { Issue.record("expected failure"); return }
        #expect(r == reason)
    }
}
