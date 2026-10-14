// Tests/MacDashboardTests/ProcEntryOrderingTests.swift
// Port of Checks/main.swift lines 74-150 (CHECKS-SWIFT-TESTING). ProcEntry.id and the stable / ranked ordering helpers.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct ProcEntryOrderingTests {
        @Test func procEntryID() async {
            // ProcEntry.id: "p<pid>" when pid present, old rank-based form when pid is nil.
            #expect(ProcEntry(rank: 3, name: "X", pid: 27120).id == "p27120", "ProcEntry.id: \"p<pid>\" when pid present")
            #expect(ProcEntry(rank: 3, name: "X").id == "3-X", "ProcEntry.id: old rank-based form when pid is nil")
        }

        @Test func stableOrdered() async {
            // =====================================================================
            // MARK: - Array<ProcEntry>.stableOrdered(matching:) (V2-FIX-ROWID Step 2)
            // =====================================================================

            do {
                let a = ProcEntry(rank: 0, name: "A", cpu: 10, pid: 1)
                let b = ProcEntry(rank: 1, name: "B", cpu: 20, pid: 2)
                let c = ProcEntry(rank: 2, name: "C", cpu: 5, pid: 3)

                let empty = [a, b, c].stableOrdered(matching: [])
                #expect(empty.map(\.pid) == [1, 2, 3], "stableOrdered: empty frozen ⇒ receiver unchanged")

                // Input re-sorted (b now leads); frozen order should still win.
                let resorted = [b, a, c].stableOrdered(matching: [1, 2, 3])
                #expect(resorted.map(\.pid) == [1, 2, 3], "stableOrdered: frozen order honoured against differently-sorted input")

                // A frozen pid missing from the input (process died / fell out of top-N) is skipped.
                let missing = [a, c].stableOrdered(matching: [1, 2, 3])
                #expect(missing.map(\.pid) == [1, 3], "stableOrdered: frozen pid absent from input is skipped")

                // A new pid not in frozen lands after the frozen ones, in the receiver's own order.
                let d = ProcEntry(rank: 3, name: "D", cpu: 1, pid: 4)
                let withNew = [d, b, a].stableOrdered(matching: [1, 2])
                #expect(withNew.map(\.pid) == [1, 2, 4], "stableOrdered: new pid not in frozen lands after frozen ones")

                // nil-pid rows land in the trailing group.
                let nilPidRow = ProcEntry(rank: 4, name: "E", cpu: 1)
                let withNilPid = [nilPidRow, b, a].stableOrdered(matching: [1, 2])
                #expect(withNilPid.map(\.pid) == [1, 2, nil], "stableOrdered: nil-pid row lands in trailing group")

                // Returned elements carry the INPUT's (fresh) values/ids, not the frozen snapshot's.
                let aFresh = ProcEntry(rank: 5, name: "A", cpu: 99, pid: 1)
                let fresh = [aFresh, b].stableOrdered(matching: [1, 2])
                #expect(fresh.first?.cpu == 99 && fresh.first?.id == aFresh.id,
                      "stableOrdered: returned elements are the input's fresh values/ids, not the frozen snapshot's")
            }
        }

        @Test func rankedByCPUAndMem() async {
            // =====================================================================
            // MARK: - Array<ProcEntry>.rankedByCPU()/rankedByMem() (V2-RELAYOUT-RESIDUAL)
            // =====================================================================

            do {
                // Both render as "0,2%": a difference below display precision must NOT reorder,
                // and the result must not depend on the input order (Array.sorted is unstable).
                let hi = ProcEntry(rank: 0, name: "hi", cpu: 0.24, pid: 900)
                let lo = ProcEntry(rank: 0, name: "lo", cpu: 0.16, pid: 400)
                #expect([hi, lo].rankedByCPU().map(\.pid) == [400, 900],
                      "rankedByCPU: sub-display-precision difference does not reorder (pid decides)")
                #expect([lo, hi].rankedByCPU().map(\.pid) == [400, 900],
                      "rankedByCPU: same result from the opposite input order")

                // A difference the display DOES show still ranks by value.
                let big = ProcEntry(rank: 0, name: "big", cpu: 0.9, pid: 999)
                #expect([lo, big].rankedByCPU().map(\.pid) == [999, 400],
                      "rankedByCPU: a visible CPU difference still ranks by value")

                // nil cpu ranks as 0 and lands last, as it did before.
                let none = ProcEntry(rank: 0, name: "none", cpu: nil, pid: 100)
                #expect([none, lo].rankedByCPU().map(\.pid) == [400, 100],
                      "rankedByCPU: nil cpu ranks as 0")

                // Mem list: equal footprints break by pid, not by input order.
                let m1 = ProcEntry(rank: 0, name: "m1", cpu: 0, memBytes: 5 * MIB, pid: 700)
                let m2 = ProcEntry(rank: 0, name: "m2", cpu: 0, memBytes: 5 * MIB, pid: 300)
                #expect([m1, m2].rankedByMem().map(\.pid) == [300, 700],
                      "rankedByMem: equal memBytes break by pid")
                #expect([m2, m1].rankedByMem().map(\.pid) == [300, 700],
                      "rankedByMem: same result from the opposite input order")
                // A real difference still wins over the tie-break.
                let m3 = ProcEntry(rank: 0, name: "m3", cpu: 0, memBytes: 9 * MIB, pid: 800)
                #expect([m2, m3].rankedByMem().map(\.pid) == [800, 300],
                      "rankedByMem: a larger footprint outranks a lower pid")
            }
        }
    }
}
