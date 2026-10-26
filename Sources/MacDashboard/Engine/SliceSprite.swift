// Sources/MacDashboard/Engine/SliceSprite.swift
// RESIZE-FRAME-COST: pure geometry for width-invariant sprites (rims, fills, shadows, ring masks) that are drawn once
// at the smallest width holding both corner caps and stretched by the render server. No AppKit/SwiftUI here.
import CoreGraphics

enum DS3SliceShape: Hashable {
    case rect
    case rounded(CGFloat)
    case capsule
}

enum DS3SliceGeometry {
    /// Corner cap width in points. 1.6 covers the continuous-corner extent (~1.53 r); the `min` handles `cornerRadius: 999`.
    static func cap(_ s: DS3SliceShape, height: CGFloat) -> CGFloat {
        switch s {
        case .rect: return 2
        case .rounded(let r): return ceil(1.6 * min(r, height / 2)) + 2
        case .capsule: return ceil(height / 2) + 2
        }
    }

    /// Two caps plus a 1 pt stretch column.
    static func referenceWidth(cap: CGFloat) -> CGFloat { 2 * cap + 1 }

    struct Measure: Hashable {
        let heightPx: Int
        let narrow: Bool
    }

    static func measure(_ s: DS3SliceShape, size: CGSize, scale: CGFloat) -> Measure {
        Measure(
            heightPx: Int((size.height * scale).rounded()),
            narrow: size.height <= 0 || size.width < referenceWidth(cap: cap(s, height: size.height))
        )
    }

    struct NineSlice: Hashable {
        let core: CGFloat
        let bleed: CGFloat
        var side: CGFloat { 2 * (bleed + core) + 2 }

        /// Unit-space centre rect: the stretched axis is the 2 px middle band, a fixed axis uses the whole image.
        func contentsCenter(fixedWidth: Bool, fixedHeight: Bool) -> CGRect {
            let o = (bleed + core) / side
            let e = 2 / side
            return CGRect(x: fixedWidth ? 0 : o, y: fixedHeight ? 0 : o,
                          width: fixedWidth ? 1 : e, height: fixedHeight ? 1 : e)
        }
    }

    static func shadow(cornerRadius: CGFloat, maxRadius: CGFloat, maxInset: CGFloat, maxY: CGFloat) -> NineSlice {
        NineSlice(core: max(ceil(1.6 * cornerRadius), maxInset) + 3 * maxRadius,
                  bleed: ceil(maxY + 3 * maxRadius))
    }

    /// `nil` when the axis is long enough to stretch; else the exact pixel size the axis is rendered at.
    static func fixedAxis(_ extent: CGFloat, _ n: NineSlice, scale: CGFloat) -> Int? {
        extent >= 2 * n.core + 2 ? nil : Int((extent * scale).rounded())
    }

    static func ringMask(cornerRadius: CGFloat) -> NineSlice {
        NineSlice(core: ceil(1.6 * cornerRadius) + 2, bleed: 0)
    }
}
