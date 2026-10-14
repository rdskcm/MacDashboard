// Tests/MacDashboardTests/InFlightReadsTests.swift
// Port of Checks/InFlightReadsChecks.swift (CHECKS-SWIFT-TESTING).
// IPHONE-LOGS-REATTACH: the pure in-flight bookkeeping (InFlightReads.swift, symlinked) for
// the crash-log listing and identity read, with the S-scenarios from the block spec.
// Pure value type only; no transport, no model.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct InFlightReadsTests {
        @Test func inFlightReads() async {
            let k = "k", j = "j"

            // --- S1/S2: late completion of the old connection lands after re-attach with a new handle ---
            do {
                var r = InFlightReads<Int>()
                let a = r.begin(k, handle: 1)
                #expect(a != nil, "iPhone in-flight: S1/S2 late success or failure, new handle: A begins")
                r.detach(1)
                #expect(!r.contains(k), "iPhone in-flight: S1/S2 late success or failure, new handle: detach clears A")
                let b = r.begin(k, handle: 2)
                #expect(b != nil, "iPhone in-flight: S1/S2 late success or failure, new handle: B begins over h2")
                #expect(r.finish(k, id: a ?? -1) == false, "iPhone in-flight: S1/S2 late success or failure, new handle: late A is dropped")
                #expect(r.contains(k), "iPhone in-flight: S1/S2 late success or failure, new handle: B marker kept")
                #expect(r.finish(k, id: b ?? -1) == true, "iPhone in-flight: S1/S2 late success or failure, new handle: B is applied")
                #expect(!r.contains(k), "iPhone in-flight: S1/S2 late success or failure, new handle: no marker after B")
            }

            // --- S6: same sequence without an isConnected flip (detach+attach between renders) ---
            do {
                var r = InFlightReads<Int>()
                let a = r.begin(k, handle: 1)
                r.detach(1)
                let b = r.begin(k, handle: 2)
                #expect(a != nil && b != nil, "iPhone in-flight: S6 no isConnected flip: A and B both begin")
                #expect(r.finish(k, id: a ?? -1) == false, "iPhone in-flight: S6 no isConnected flip: late A is dropped")
                #expect(r.contains(k), "iPhone in-flight: S6 no isConnected flip: B marker kept")
                #expect(r.finish(k, id: b ?? -1) == true, "iPhone in-flight: S6 no isConnected flip: B is applied")
                #expect(!r.contains(k), "iPhone in-flight: S6 no isConnected flip: no marker after B")
            }

            // --- S7: identity behaves as logs; the two markers are independent ---
            do {
                var logs = InFlightReads<Int>()
                var ident = InFlightReads<Int>()
                let la = logs.begin(k, handle: 1)
                let ia = ident.begin(k, handle: 1)
                #expect(la != nil && ia != nil, "iPhone in-flight: S7 identity: logs and identity both begin over h1")
                ident.detach(1)
                let ib = ident.begin(k, handle: 2)
                #expect(ib != nil, "iPhone in-flight: S7 identity: identity B begins over h2")
                #expect(ident.finish(k, id: ia ?? -1) == false, "iPhone in-flight: S7 identity: late identity A is dropped")
                #expect(ident.finish(k, id: ib ?? -1) == true, "iPhone in-flight: S7 identity: identity B is applied")
                #expect(logs.contains(k), "iPhone in-flight: S7 identity: logs marker unaffected by identity events")
                logs.detach(1)
                #expect(!logs.contains(k), "iPhone in-flight: S7 identity: logs marker clears only on its own detach")
            }

            // --- S3 control: same handle value reused after re-attach ---
            do {
                var r = InFlightReads<Int>()
                let a = r.begin(k, handle: 1)
                r.detach(1)
                let b = r.begin(k, handle: 1)
                #expect(b != nil && b != a, "iPhone in-flight: S3 same handle reused: B begins with a new id")
                #expect(r.finish(k, id: a ?? -1) == false, "iPhone in-flight: S3 same handle reused: late A is dropped")
                #expect(r.contains(k), "iPhone in-flight: S3 same handle reused: B marker kept")
                #expect(r.finish(k, id: b ?? -1) == true, "iPhone in-flight: S3 same handle reused: B is applied")
            }

            // --- S4 control: A lands before detach ---
            do {
                var r = InFlightReads<Int>()
                let a = r.begin(k, handle: 1)
                #expect(r.finish(k, id: a ?? -1) == true, "iPhone in-flight: S4 A lands before detach: A is applied")
                r.detach(1)
                let b = r.begin(k, handle: 2)
                #expect(b != nil, "iPhone in-flight: S4 A lands before detach: B begins over h2")
                #expect(r.finish(k, id: b ?? -1) == true, "iPhone in-flight: S4 A lands before detach: B is applied")
            }

            // --- S5 control: A lands while detached ---
            do {
                var r = InFlightReads<Int>()
                let a = r.begin(k, handle: 1)
                r.detach(1)
                #expect(r.finish(k, id: a ?? -1) == false, "iPhone in-flight: S5 A lands while detached: A is dropped")
                #expect(!r.contains(k), "iPhone in-flight: S5 A lands while detached: no marker")
                #expect(r.begin(k, handle: 2) != nil, "iPhone in-flight: S5 A lands while detached: re-attach begins")
            }

            // --- Dedupe: a second begin over the same handle is a no-op ---
            do {
                var r = InFlightReads<Int>()
                let a = r.begin(k, handle: 1)
                #expect(a != nil, "iPhone in-flight: dedupe: first begin is accepted")
                #expect(r.begin(k, handle: 1) == nil, "iPhone in-flight: dedupe: second begin over the same handle is nil")
                #expect(r.contains(k), "iPhone in-flight: dedupe: marker kept")
                #expect(r.finish(k, id: a ?? -1) == true, "iPhone in-flight: dedupe: A is applied")
            }

            // --- Attach before detach: h2 is processed before h1 detaches ---
            do {
                var r = InFlightReads<Int>()
                let a = r.begin(k, handle: 1)
                let b = r.begin(k, handle: 2)
                #expect(b != nil, "iPhone in-flight: attach before detach: B begins over h2 while A is in flight")
                #expect(r.finish(k, id: a ?? -1) == false, "iPhone in-flight: attach before detach: A is dropped as superseded")
                #expect(r.contains(k), "iPhone in-flight: attach before detach: B marker kept")
                #expect(r.finish(k, id: b ?? -1) == true, "iPhone in-flight: attach before detach: B is applied")
            }

            // --- Detach without re-attach ---
            do {
                var r = InFlightReads<Int>()
                let a = r.begin(k, handle: 1)
                r.detach(1)
                #expect(r.finish(k, id: a ?? -1) == false, "iPhone in-flight: detach without re-attach: late A is dropped")
                #expect(!r.contains(k), "iPhone in-flight: detach without re-attach: no marker")
            }

            // --- Other handle untouched by a detach ---
            do {
                var r = InFlightReads<Int>()
                _ = r.begin(k, handle: 1)
                _ = r.begin(j, handle: 2)
                r.detach(1)
                #expect(!r.contains(k) && r.contains(j), "iPhone in-flight: other handle untouched: detach(1) clears k, keeps j")
            }
        }
    }
}
