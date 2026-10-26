// Tests/MacDashboardTests/SliceSpriteTests.swift
// RESIZE-FRAME-COST Stage 1: nine-slice / three-slice geometry oracles (hand-computed from the spec formulas).
import CoreGraphics
import Testing
@testable import MacDashboard

struct SliceSpriteTests {
    typealias G = DS3SliceGeometry

    @Test func caps() {
        #expect(G.cap(.rect, height: 50) == 2)
        #expect(G.cap(.rounded(20), height: 200) == 34)
        #expect(G.cap(.rounded(999), height: 24) == 22)
        #expect(G.cap(.capsule, height: 36) == 31)
        #expect(G.cap(.capsule, height: 37) == 32)
    }

    @Test func reference() {
        #expect(G.referenceWidth(cap: 34) == 69)
    }

    @Test func measure() {
        func frame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        let a = G.measure(.rounded(20), frame: frame(0, 0, 300, 203.33), scale: 2)
        #expect(a.heightPx == 407)
        #expect(a.narrow == false)
        #expect(G.measure(.rounded(20), frame: frame(0, 0, 60, 200), scale: 2).narrow)
        #expect(G.measure(.rect, frame: frame(0, 0, 10, 0), scale: 2).narrow)
        // Top and bottom edges snap to the pixel grid separately: 106.6 px at a pixel-aligned origin covers 107 rows,
        // at a half-pixel origin (20.5 -> 21, 127.1 -> 127) only 106.
        #expect(G.measure(.rect, frame: frame(10, 10, 300, 53.3), scale: 2).heightPx == 107)
        #expect(G.measure(.rect, frame: frame(10, 10.25, 300, 53.3), scale: 2).heightPx == 106)
        #expect(G.measure(.rect, frame: frame(10, 10.25, 300, 53.3), scale: 1).heightPx == 54)
        // Capsule corners are continuous: the cap holds 1.6 r like a rounded rectangle with r = h / 2.
        #expect(G.measure(.capsule, frame: frame(0, 0, 62, 36), scale: 2).narrow)
        #expect(!G.measure(.capsule, frame: frame(0, 0, 63, 36), scale: 2).narrow)
    }

    @Test func shadowSlices() {
        let card = G.shadow(cornerRadius: 30, maxRadius: 18, maxInset: 18, maxY: 18)
        #expect(card.core == 102)
        #expect(card.bleed == 72)
        #expect(card.side == 350)
        let c = card.contentsCenter(fixedWidth: false, fixedHeight: false)
        #expect(c == CGRect(x: 174.0 / 350, y: 174.0 / 350, width: 2.0 / 350, height: 2.0 / 350))
        let h = card.contentsCenter(fixedWidth: false, fixedHeight: true)
        #expect(h.origin.y == 0)
        #expect(h.size.height == 1)
        let header = G.shadow(cornerRadius: 0, maxRadius: 12, maxInset: 18, maxY: 10)
        #expect(header.core == 54)
        #expect(header.bleed == 46)
        #expect(header.side == 202)
    }

    @Test func fixedAxes() {
        let card = G.shadow(cornerRadius: 30, maxRadius: 18, maxInset: 18, maxY: 18)
        #expect(G.fixedAxis(188, card, scale: 2) == 376)
        #expect(G.fixedAxis(300, card, scale: 2) == nil)
    }

    @Test func ringMaskSlice() {
        let m = G.ringMask(cornerRadius: 30)
        #expect(m.core == 50)
        #expect(m.side == 102)
        #expect(m.contentsCenter(fixedWidth: false, fixedHeight: false)
            == CGRect(x: 50.0 / 102, y: 50.0 / 102, width: 2.0 / 102, height: 2.0 / 102))
    }
}
