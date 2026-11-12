// Tests/MoonportTests/IPhoneTileMenuSnapshotTests.swift
// IPHONE-UNLINK Stage B: panel anchor geometry (plain) and the «⋯» glyph's rendered ink centre (needs a window
// server, runs with the snapshot suite: tools/visual/snapshots.sh filters on `SnapshotTests`).
import AppKit
import SwiftUI
import Testing
@testable import Moonport

@Suite struct IPhoneTileMenuLayoutTests {
    @Test func panelAnchorAtRest() {
        let p = IPhoneTileMenuMetrics.panelAnchor(tile: CGRect(x: 0, y: 0, width: 300, height: 300), lifted: false)
        #expect(p == CGPoint(x: 284, y: 58))
    }

    @Test func panelAnchorLiftedFollowsTilePose() {
        let p = IPhoneTileMenuMetrics.panelAnchor(tile: CGRect(x: 0, y: 0, width: 300, height: 300), lifted: true)
        #expect(abs(p.x - 285.34) < 0.01)
        #expect(abs(p.y - 54.08) < 0.01)
    }
}

@Suite(.enabled(if: SnapshotEnv.outDir != nil, "set MACDASH_SNAPSHOTS: run tools/visual/snapshots.sh")) @MainActor
struct IPhoneTileMenuGlyphSnapshotTests {
    @Test func inkIsCentredAndSized() throws {
        let side: CGFloat = 34
        let hosting = NSHostingView(rootView: IPhoneTileMenuGlyph(ink: .black).frame(width: side, height: side))
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: .zero)
        window.contentView?.addSubview(hosting)
        hosting.frame = NSRect(x: 0, y: 0, width: side, height: side)
        window.setContentSize(hosting.frame.size)
        hosting.layoutSubtreeIfNeeded()
        let px = 136
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: side, height: side)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        var minX = px, minY = px, maxX = -1, maxY = -1
        for y in 0..<px { for x in 0..<px where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        try #require(maxX >= 0, "no ink rendered")
        let w = CGFloat(maxX - minX + 1), h = CGFloat(maxY - minY + 1)
        let cx = CGFloat(minX + maxX + 1) / 2, cy = CGFloat(minY + maxY + 1) / 2
        let dx = (cx - 68) / 4, dy = (cy - 68) / 4
        let note = "dx \(dx) pt, dy \(dy) pt, ink \(w / 4) x \(h / 4) pt"
        #expect(abs(cx - 68) <= 1 && abs(cy - 68) <= 1, "centre off: \(note)")
        #expect(abs(w - 72) <= 8, "width off: \(note)")
        #expect(abs(h - 16) <= 4, "height off: \(note)")
    }
}
