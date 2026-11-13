// Tests/MoonportTests/IPhoneBenchTransportTests.swift
// GATE-TABLE-PROBE: only the installed app's bundle id starts the live iPhone transport.
import Foundation
import Testing
@testable import Moonport

struct IPhoneBenchTransportTests {
    @Test func onlyTheInstalledAppStartsTheLiveTransport() {
        #expect(IPhoneModel.startsLiveTransport(bundleID: AppInfo.bundleID))
        #expect(!IPhoneModel.startsLiveTransport(bundleID: "app.moonport.bench"))
        #expect(!IPhoneModel.startsLiveTransport(bundleID: AppInfo.legacyBundleID))
        #expect(!IPhoneModel.startsLiveTransport(bundleID: nil))
        #expect(!IPhoneModel.startsLiveTransport(), "this test process is refused")
    }
}
