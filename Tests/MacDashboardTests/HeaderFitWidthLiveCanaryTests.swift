// Tests/MacDashboardTests/HeaderFitWidthLiveCanaryTests.swift
// RESIZE-MOTION C2 opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanary
// Hosts the real header rows and the mode switch through the production probes and prints the window width below
// which each row falls back to its compact form; compared with the bench widths measured 2026-10-26 (SDK 27).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct HeaderFitWidthLiveCanaryTests {
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        @MainActor func liveCanaryHeaderFitWidths() {
            // (language, This Mac bench, iPhone bench) — findings C3/C5, formula values; the bench brackets them ±4.
            let bench: [(AppLanguage, CGFloat, CGFloat)] = [(.en, 994, 905), (.ru, 1083, 1099)]
            for (lang, macBench, iphoneBench) in bench {
                L10nStore.shared.language = lang
                let mac = MainDashboardView.fitWindowWidth(rowWidth: MacHeaderActions.fullRowIdealWidth())
                let iphone = MainDashboardView.fitWindowWidth(rowWidth: IPhoneHeaderActions.fullRowIdealWidth())
                print("liveCanary header fit widths \(lang): thisMac=\(mac) (bench \(macBench)) iphone=\(iphone) (bench \(iphoneBench))")
                #expect(abs(mac - macBench) <= 6, "This Mac fit width \(lang): \(mac) vs bench \(macBench)")
                #expect(abs(iphone - iphoneBench) <= 6, "iPhone fit width \(lang): \(iphone) vs bench \(iphoneBench)")
            }
        }
    }
}
