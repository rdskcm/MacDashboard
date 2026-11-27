// Tests/MoonportTests/ReaderProbeTests.swift
// READER-STATUS S2: the off-main runner with its deadline, and the timed-out rows. Timing, so it lives in SerialTests.
import Foundation
import Testing
@testable import Moonport

extension SerialTests {
    struct ReaderProbeTests {
        @Test func runOffMainReturnsTheValue() async {
            #expect(await ReaderProbe.runOffMain(timeout: 5) { 42 } == 42)
        }

        @Test func runOffMainGivesNilAfterTheDeadline() async {
            let clock = ContinuousClock()
            let t0 = clock.now
            let value: Int? = await ReaderProbe.runOffMain(timeout: 0.05) { Thread.sleep(forTimeInterval: 0.5); return 7 }
            #expect(value == nil)
            #expect(clock.now - t0 < .milliseconds(400))
        }

        @Test func timedOutLinesMarkEveryRow() {
            let lines = ReaderProbe.timedOutLines(ReaderProbe.hardwareIDs, seconds: 10)
            #expect(lines.map(\.reader) == ReaderProbe.hardwareIDs)
            #expect(lines.allSatisfy { $0.status == .failed(.timedOut(seconds: 10)) })
        }
    }
}
