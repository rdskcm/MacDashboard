// Tests/MoonportTests/RimBandsTests.swift
// RIM-HOVER-COST: the eight edge bands are disjoint, have whole-point seams, and hold every pixel the ring path touches.
import CoreGraphics
import Testing
@testable import Moonport

@MainActor
struct RimBandsTests {
    static let sizes: [CGSize] = [
        CGSize(width: 942, height: 300), CGSize(width: 942.5, height: 177.5), CGSize(width: 412, height: 177),
        CGSize(width: 254, height: 158), CGSize(width: 120, height: 60), CGSize(width: 60, height: 60),
        CGSize(width: 300, height: 40), CGSize(width: 40, height: 300), CGSize(width: 61, height: 7),
        CGSize(width: 5, height: 5),
    ]

    @Test(arguments: [CGFloat(30), 34])
    func bandsAreDisjointWithWholePointSeams(r: CGFloat) {
        for size in Self.sizes {
            let b = RimBands.rects(size: size, cornerRadius: r)
            #expect(b.count == 8)
            for i in 0..<b.count {
                for j in (i + 1)..<b.count {
                    let x = b[i].intersection(b[j])
                    #expect(x.isNull || x.width == 0 || x.height == 0, "\(size) r \(r): bands \(i) and \(j) overlap")
                }
                for e in [b[i].minX, b[i].maxX] where e != size.width + 1 { #expect(e == e.rounded(), "\(size) \(b[i])") }
                for e in [b[i].minY, b[i].maxY] where e != size.height + 1 { #expect(e == e.rounded(), "\(size) \(b[i])") }
            }
        }
    }

    @Test(arguments: [CGFloat(30), 34])
    func everyRingPixelLiesInExactlyOneBand(r: CGFloat) throws {
        for size in Self.sizes {
            for scale in [CGFloat(1), 2] {
                let bands = RimBands.rects(size: size, cornerRadius: r)
                let wp = Int(((size.width + 2) * scale).rounded(.up)), hp = Int(((size.height + 2) * scale).rounded(.up))
                let ctx = try #require(CGContext(data: nil, width: wp, height: hp, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
                // Card-local points, y down, origin 1 pt inside the bitmap's top-left corner.
                ctx.translateBy(x: 0, y: CGFloat(hp))
                ctx.scaleBy(x: scale, y: -scale)
                ctx.translateBy(x: 1, y: 1)
                ctx.addPath(DS3RimView.ringPath(size, r))
                ctx.setFillColor(gray: 1, alpha: 1)
                ctx.fillPath()
                let px = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
                var lit = 0, misplaced = 0
                for m in 0..<hp {
                    for n in 0..<wp where px[m * ctx.bytesPerRow + n] > 0 {
                        lit += 1
                        let c = CGPoint(x: (CGFloat(n) + 0.5) / scale - 1, y: (CGFloat(m) + 0.5) / scale - 1)
                        if bands.filter({ $0.contains(c) }).count != 1 { misplaced += 1 }
                    }
                }
                #expect(lit > 0, "\(size) r \(r) @\(scale)x: nothing rasterised")
                #expect(misplaced == 0, "\(size) r \(r) @\(scale)x: \(misplaced) ring pixels outside exactly one band")
            }
        }
    }

    /// RIM-HOVER-COST fix: the reach threshold is exact at the band edge (just outside: not lit, just inside: lit).
    @Test func reachThresholdAtTheBandEdge() {
        let bands = RimBands.rects(size: CGSize(width: 412, height: 177), cornerRadius: 30)
        let rho: CGFloat = 202                       // R 200 (h 40) + reachPad
        let edge: CGFloat = 413                      // right bands end at w + 1
        #expect(!RimBands.reaches(bands, from: CGPoint(x: edge + rho, y: 88), to: CGPoint(x: edge + rho, y: 88), radius: rho))
        #expect(RimBands.reaches(bands, from: CGPoint(x: edge + rho - 0.5, y: 88), to: CGPoint(x: edge + rho - 0.5, y: 88), radius: rho))
        #expect(!RimBands.reaches(bands, from: CGPoint(x: 88, y: -1 - rho), to: CGPoint(x: 88, y: -1 - rho), radius: rho))
        #expect(RimBands.reaches(bands, from: CGPoint(x: 88, y: -1 - rho + 0.5), to: CGPoint(x: 88, y: -1 - rho + 0.5), radius: rho))
    }

    /// A light in the middle of a large card reaches no band when R is small, and does when R is large.
    @Test func lightInsideALargeCard() {
        let bands = RimBands.rects(size: CGSize(width: 942, height: 600), cornerRadius: 30)
        let c = CGPoint(x: 471, y: 300)              // 297 pt from the top and bottom strips (y 3 and 597)
        #expect(!RimBands.reaches(bands, from: c, to: c, radius: 202))
        #expect(RimBands.reaches(bands, from: c, to: c, radius: 352))
    }

    /// A follow segment whose endpoints are both out of reach still lights the card when its middle passes close.
    @Test func segmentSweepingPastACard() {
        let bands = RimBands.rects(size: CGSize(width: 412, height: 177), cornerRadius: 30)
        let a = CGPoint(x: -500, y: 88), b = CGPoint(x: 900, y: 88)   // straight through the card
        #expect(!RimBands.reaches(bands, from: a, to: a, radius: 202))
        #expect(!RimBands.reaches(bands, from: b, to: b, radius: 202))
        #expect(RimBands.reaches(bands, from: a, to: b, radius: 202))
        // Diagonal past the top-left corner: line x + y = -200 is 198 / sqrt(2) = 140 pt from the corner (-1, -1).
        let c = CGPoint(x: -400, y: 200), d = CGPoint(x: 200, y: -400)
        #expect(RimBands.reaches(bands, from: c, to: d, radius: 202))
        #expect(!RimBands.reaches(bands, from: c, to: d, radius: 130))
    }

    @Test func distanceBasics() {
        let r = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(RimBands.distance(r, CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)) == 0)
        #expect(RimBands.distance(r, CGPoint(x: 13, y: 14), CGPoint(x: 13, y: 14)) == 5)
        #expect(RimBands.distance(r, CGPoint(x: -5, y: 20), CGPoint(x: 15, y: 20)) == 10)
        #expect(RimBands.distance(r, CGPoint(x: -5, y: 5), CGPoint(x: 15, y: 5)) == 0)
        #expect(!RimBands.reaches([CGRect(x: 0, y: 0, width: 0, height: 10)], from: .zero, to: .zero, radius: 5))
    }

    /// Bands only for a moving light on a page that is not leaving; a resting or leaving light uses the ring group.
    @Test func carrierTable() {
        #expect(RimLightCarrier.pick(reaches: false, inMotion: true, leaving: false) == .none)
        #expect(RimLightCarrier.pick(reaches: false, inMotion: false, leaving: true) == .none)
        #expect(RimLightCarrier.pick(reaches: true, inMotion: true, leaving: false) == .bands)
        #expect(RimLightCarrier.pick(reaches: true, inMotion: false, leaving: false) == .ring)
        #expect(RimLightCarrier.pick(reaches: true, inMotion: true, leaving: true) == .ring)
        #expect(RimLightCarrier.pick(reaches: true, inMotion: false, leaving: true) == .ring)
    }

    /// Only Home's rims become leaving when Home stops being the destination, whatever the registration order.
    @Test func homeRimsLeaveWhileHomeIsNotShown() {
        let t = DS3PointerTracker()
        let home = DS3RimModel(), page = DS3RimModel()
        home.onHome = true
        t.register(home)
        t.register(page)
        t.setHomeShown(false)
        #expect(home.leaving)
        #expect(!page.leaving)
        let late = DS3RimModel()                     // a Home rim registering after the switch
        late.onHome = true
        t.register(late)
        #expect(late.leaving)
        t.setHomeShown(true)
        #expect(!home.leaving && !late.leaving && !page.leaving)
    }
}
