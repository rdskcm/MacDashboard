// Tests/MacDashboardTests/SliceSpriteTests.swift
// RESIZE-FRAME-COST Stage 1: nine-slice / three-slice geometry oracles (hand-computed from the spec formulas).
import CoreGraphics
import SwiftUI
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
        func size(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
        let a = G.measure(.rounded(20), size: size(300, 203.33), scale: 2)
        #expect(a.heightPx == 407)
        #expect(a.narrow == false)
        #expect(G.measure(.rounded(20), size: size(60, 200), scale: 2).narrow)
        #expect(G.measure(.rect, size: size(10, 0), scale: 2).narrow)
        // APPEAR-COST D1: the layout height alone decides the sprite height; position never enters.
        #expect(G.measure(.rect, size: size(300, 53.3), scale: 2).heightPx == 107)
        #expect(G.measure(.rect, size: size(300, 53.3), scale: 1).heightPx == 53)
        // Capsule corners are continuous: the cap holds 1.6 r like a rounded rectangle with r = h / 2.
        #expect(G.measure(.capsule, size: size(62, 36), scale: 2).narrow)
        #expect(!G.measure(.capsule, size: size(63, 36), scale: 2).narrow)
    }

    @MainActor @Test func resolvedStopsAreCachedPerAppearance() {
        let stops = [Gradient.Stop(color: .white.opacity(0.5), location: 0), Gradient.Stop(color: .white.opacity(0), location: 0.18)]
        let c = DS3SpriteCache.shared
        let before = c.resolveMisses
        let light1 = ds3ResolvedStops(stops, dark: false)
        let light2 = ds3ResolvedStops(stops, dark: false)
        #expect(light1 == light2)
        #expect(c.resolveMisses == before + 1, "second call for the same stops and appearance is a hit")
        _ = ds3ResolvedStops(stops, dark: true)
        #expect(c.resolveMisses == before + 2, "a different appearance resolves once more")
        _ = ds3ResolvedStops(stops, dark: true)
        #expect(c.resolveMisses == before + 2)
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
