// Tests/MacDashboardTests/AppModelHistoryTests.swift
// SOC-DETAILS D5/D6: the fast task's history append (a nil GPU sample is kept as a gap) and the 61-sample trim.
import Foundation
import Testing
@testable import MacDashboard

struct AppModelHistoryTests {
    @Test func gpuAppendKeepsNilSamples() {
        var h: [(Date, Int?)] = []
        AppModel.appendTrimmed(&h, (Date(timeIntervalSince1970: 0), 40))
        AppModel.appendTrimmed(&h, (Date(timeIntervalSince1970: 2), nil))
        #expect(h.count == 2 && h[0].1 == 40 && h[1].1 == nil)
    }

    @Test func historiesTrimToTheLast61() {
        var cpu: [(Date, Double)] = []
        var gpu: [(Date, Int?)] = []
        for i in 0..<70 {
            let t = Date(timeIntervalSince1970: Double(i))
            AppModel.appendTrimmed(&cpu, (t, Double(i)))
            AppModel.appendTrimmed(&gpu, (t, i % 2 == 0 ? nil : i))
        }
        #expect(cpu.count == 61 && gpu.count == 61)
        #expect(cpu.first?.1 == 9 && cpu.last?.1 == 69)
        #expect(gpu.first?.0 == Date(timeIntervalSince1970: 9) && gpu.last?.1 == 69)
    }
}
