// Tests/MacDashboardTests/ProcEntryOrderingTests.swift
// CI-SWIFT-TESTING: swift-testing port of the ProcEntry id / ordering checks
// (Checks/main.swift). Runs via `swift test` locally and in CI; the primary gate is still `swift run MacDashboardChecks`.
import Testing
@testable import MacDashboard

@Test func procEntryIDPrefersPid() {
    #expect(ProcEntry(rank: 3, name: "X", pid: 27120).id == "p27120")
    #expect(ProcEntry(rank: 3, name: "X").id == "3-X")
}

@Test func stableOrderedKeepsFrozenOrder() {
    let a = ProcEntry(rank: 0, name: "A", cpu: 10, pid: 1)
    let b = ProcEntry(rank: 1, name: "B", cpu: 20, pid: 2)
    let c = ProcEntry(rank: 2, name: "C", cpu: 5, pid: 3)
    #expect([a, b, c].stableOrdered(matching: []).map(\.pid) == [1, 2, 3] as [Int32?])
    #expect([b, a, c].stableOrdered(matching: [1, 2, 3]).map(\.pid) == [1, 2, 3] as [Int32?])
    #expect([a, c].stableOrdered(matching: [1, 2, 3]).map(\.pid) == [1, 3] as [Int32?])
    let d = ProcEntry(rank: 3, name: "D", cpu: 1, pid: 4)
    #expect([d, b, a].stableOrdered(matching: [1, 2]).map(\.pid) == [1, 2, 4] as [Int32?])
    let e = ProcEntry(rank: 4, name: "E", cpu: 1)
    #expect([e, b, a].stableOrdered(matching: [1, 2]).map(\.pid) == [1, 2, nil] as [Int32?])
    let aFresh = ProcEntry(rank: 5, name: "A", cpu: 99, pid: 1)
    let fresh = [aFresh, b].stableOrdered(matching: [1, 2])
    #expect(fresh.first?.cpu == 99)
    #expect(fresh.first?.id == aFresh.id)
}

@Test func rankedByCPUIgnoresSubDisplayDifferences() {
    let hi = ProcEntry(rank: 0, name: "hi", cpu: 0.24, pid: 900)
    let lo = ProcEntry(rank: 0, name: "lo", cpu: 0.16, pid: 400)
    #expect([hi, lo].rankedByCPU().map(\.pid) == [400, 900] as [Int32?])
    #expect([lo, hi].rankedByCPU().map(\.pid) == [400, 900] as [Int32?])
    let big = ProcEntry(rank: 0, name: "big", cpu: 0.9, pid: 999)
    #expect([lo, big].rankedByCPU().map(\.pid) == [999, 400] as [Int32?])
    let none = ProcEntry(rank: 0, name: "none", cpu: nil, pid: 100)
    #expect([none, lo].rankedByCPU().map(\.pid) == [400, 100] as [Int32?])
}

@Test func rankedByMemBreaksTiesByPid() {
    let m1 = ProcEntry(rank: 0, name: "m1", cpu: 0, memBytes: 5 << 20, pid: 700)
    let m2 = ProcEntry(rank: 0, name: "m2", cpu: 0, memBytes: 5 << 20, pid: 300)
    #expect([m1, m2].rankedByMem().map(\.pid) == [300, 700] as [Int32?])
    #expect([m2, m1].rankedByMem().map(\.pid) == [300, 700] as [Int32?])
    let m3 = ProcEntry(rank: 0, name: "m3", cpu: 0, memBytes: 9 << 20, pid: 800)
    #expect([m2, m3].rankedByMem().map(\.pid) == [800, 300] as [Int32?])
}
