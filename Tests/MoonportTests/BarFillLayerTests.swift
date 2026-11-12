// Tests/MoonportTests/BarFillLayerTests.swift
// FIX-LEFTOVERS (GPU-RENDER-AUDIT m1): a segment bar makes ONE snap/glide decision per update, so neighbouring
// segments never take different paths. Reads the layers' animation dictionaries; no window, no run-loop spin.
import AppKit
import SwiftUI
import Testing
@testable import Moonport

extension SerialTests {
    /// In `SerialTests` because it touches `NSApplication.shared` (process-wide), as `SocLiveSamplerTests` does.
    @MainActor struct BarFillLayerTests {
        /// The SoC CPU split bar's layout. 206 pt wide, gap 2: 202 pt for three segments.
        private static let layout = BarFillLayout.segments(gap: 2, minWidth: 0, cornerRadius: 4)

        private func spans(_ f: [CGFloat]) -> [BarSpan] {
            zip(["a", "b", "c"], f).map { BarSpan(key: $0, fraction: $1, color: .blue) }
        }

        /// a 101, b 50.5 at x 103, c 50.5 at x 155.5. The first apply is never animated.
        private func makeView() -> BarFillLayerView {
            _ = NSApplication.shared
            let v = BarFillLayerView(frame: NSRect(x: 0, y: 0, width: 206, height: 8))
            v.apply(spans: spans([0.5, 0.25, 0.25]), layout: Self.layout, animated: true)
            return v
        }

        /// Per segment layer, in span order: does it carry a bounds AND a position glide?
        private func gliding(_ v: BarFillLayerView) -> [Bool] {
            (v.layer?.sublayers ?? []).map { $0.animation(forKey: "bounds") != nil && $0.animation(forKey: "position") != nil }
        }

        @Test func firstApplyNeverGlides() {
            #expect(gliding(makeView()) == [false, false, false])
        }

        /// a shrinks 1.2 pt, b moves 1.2 pt, c moves and grows 0.6 pt: decided per segment, c alone snapped and its gap
        /// to b changed during the glide; one decision makes all three glide.
        @Test func mixedMoveGlidesEverySegment() {
            let v = makeView()
            v.apply(spans: spans([0.494, 0.253, 0.253]), layout: Self.layout, animated: true)
            #expect(gliding(v) == [true, true, true])
        }

        /// Every segment moves 0.6 pt: the whole bar snaps (GPU-RENDER-AUDIT C6).
        @Test func subPointMoveSnapsEverySegment() {
            let v = makeView()
            v.apply(spans: spans([0.497, 0.25, 0.253]), layout: Self.layout, animated: true)
            #expect(gliding(v) == [false, false, false])
        }

        /// Reduce Motion (`animated: false`): nothing glides, even for a large move.
        @Test func unanimatedApplyNeverGlides() {
            let v = makeView()
            v.apply(spans: spans([0.3, 0.4, 0.3]), layout: Self.layout, animated: false)
            #expect(gliding(v) == [false, false, false])
        }
    }
}
