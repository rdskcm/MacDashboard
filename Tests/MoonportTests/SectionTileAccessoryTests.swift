// Tests/MoonportTests/SectionTileAccessoryTests.swift
// SERIAL-MASK-LAST4, Decision 5: the label-row controls (toggle and copy circle) do not change the tile's height.
import AppKit
import SwiftUI
import Testing
@testable import Moonport

extension SerialTests {
    @Suite struct SectionTileAccessoryTests {
        /// 261 pt is one Passport tile at the minimum window.
        @MainActor private func height(_ tile: SectionTile) -> CGFloat {
            NSHostingView(rootView: tile.frame(width: 261)).fittingSize.height
        }

        @MainActor @Test func labelRowControlsKeepTheTileHeight() {
            _ = NSApplication.shared
            let controls = AnyView(IdentifierRevealControls(label: "Serial number", fullValue: "SYN0000001",
                                                            shown: false) {})
            let plain = height(SectionTile(label: "Serial number", value: "•••• 0001", noteInk: DS3.muted))
            let withControls = height(SectionTile(label: "Serial number", value: "•••• 0001", noteInk: DS3.muted,
                                                  labelAccessory: controls))
            let dated = height(SectionTile(label: "Manufacture date", value: "Mar 2024", note: "code 2410", noteInk: DS3.muted))
            #expect(plain == 77, "14 + 19 + 5 + 25 + 14")
            #expect(withControls == plain, "the 30 pt controls add no height")
            #expect(dated == 100, "14 + 19 + 5 + 25 + 5 + 18 + 14")
        }
    }
}
