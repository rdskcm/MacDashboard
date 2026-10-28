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
}
