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
        #expect(G.cap(.capsule, height: 36) == 20)
        #expect(G.cap(.capsule, height: 37) == 21)
    }

    @Test func reference() {
        #expect(G.referenceWidth(cap: 34) == 69)
    }

    @Test func measure() {
        let a = G.measure(.rounded(20), size: CGSize(width: 300, height: 203.33), scale: 2)
        #expect(a.heightPx == 407)
        #expect(a.narrow == false)
        #expect(G.measure(.rounded(20), size: CGSize(width: 60, height: 200), scale: 2).narrow)
        #expect(G.measure(.rect, size: CGSize(width: 10, height: 0), scale: 2).narrow)
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
