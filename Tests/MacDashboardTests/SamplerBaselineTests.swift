// Tests/MacDashboardTests/SamplerBaselineTests.swift
// SAMPLER-OCCLUSION-GATE Stage A: the delta-baseline resets (D6a) re-prime the CPU and process samplers.
// Real system reads and timing, so it sits in SerialTests (rule tests-layout).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct SamplerBaselineTests {
        @Test func collectorResetPrimesCPUAgain() async throws {
            let c = LiveCollector()
            #expect(c.collectFast().cpu == nil)
            try await Task.sleep(for: .milliseconds(300))
            #expect(c.collectFast().cpu != nil)
            c.resetDeltaBaselines()
            #expect(c.collectFast().cpu == nil)
            // Fourth host_statistics read in under a second: macOS then returns the previous value.
            try await Task.sleep(for: .milliseconds(1200))
            #expect(c.collectFast().cpu != nil)
        }

        @Test func collectFastWithoutCPULeavesTheBaselineAlone() async throws {
            let c = LiveCollector()
            #expect(c.collectFast().cpu == nil)   // primes
            try await Task.sleep(for: .milliseconds(1200))
            #expect(c.collectFast(readsCPU: false).cpu == nil)
            #expect(c.collectFast().cpu != nil)   // the delta still spans the priming read
        }

        @Test func processSamplerResetPrimesAgain() async {
            let s = ProcessSampler()
            _ = await s.sample()
            s.resetBaseline()
            let clock = ContinuousClock()
            let start = clock.now
            _ = await s.sample()
            #expect(clock.now - start >= .milliseconds(500))
        }
    }
}
