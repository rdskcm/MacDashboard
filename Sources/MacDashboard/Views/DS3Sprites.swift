// Sources/MacDashboard/Views/DS3Sprites.swift
// RESIZE-FRAME-COST: bitmap sprites rendered once and stretched by the render server (rule gpu-per-frame).
// Geometry lives in Engine/SliceSprite.swift.
import AppKit
import SwiftUI

protocol DS3SliceableShape { var ds3Slice: DS3SliceShape { get } }
extension RoundedRectangle: DS3SliceableShape { var ds3Slice: DS3SliceShape { .rounded(cornerSize.width) } }
extension Capsule: DS3SliceableShape { var ds3Slice: DS3SliceShape { .capsule } }
extension Rectangle: DS3SliceableShape { var ds3Slice: DS3SliceShape { .rect } }

/// A gradient stop with its colour resolved to sRGB for a given appearance (components x 65535, location x 10000).
struct DS3ResolvedStop: Hashable {
    let r, g, b, a: UInt16
    let location: Int
}

@MainActor
func ds3ResolvedStops(_ stops: [Gradient.Stop], dark: Bool) -> [DS3ResolvedStop] {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    return stops.map { stop in
        let c = ds3Resolve(stop.color, in: appearance).components ?? [0, 0, 0, 0]
        func q(_ v: CGFloat) -> UInt16 { UInt16((min(max(v, 0), 1) * 65535).rounded()) }
        let comps = c.count >= 4 ? c : (c.count == 2 ? [c[0], c[0], c[0], c[1]] : [0, 0, 0, 0])
        return DS3ResolvedStop(r: q(comps[0]), g: q(comps[1]), b: q(comps[2]), a: q(comps[3]),
                               location: Int((stop.location * 10000).rounded()))
    }
}

enum DS3SpriteContent {
    case topRim(stops: [Gradient.Stop], lineWidth: CGFloat)
}

struct DS3SpriteKey: Hashable {
    let kind: String   // "rim" | "shadow" | "mask"
    let shape: DS3SliceShape
    let heightPx: Int
    let widthPx: Int   // 0 = stretched
    let scale: Double
    let dark: Bool
    let stops: [DS3ResolvedStop]
    let extra: Double  // line width (rim), corner radius (shadow, mask)
}

@MainActor
final class DS3SpriteCache {
    static let shared = DS3SpriteCache()
    private var images: [DS3SpriteKey: CGImage] = [:]

    func image(for key: DS3SpriteKey, render: () -> CGImage?) -> CGImage? {
        if let hit = images[key] { return hit }
        if images.count >= 64 { images.removeAll() }
        guard let img = render() else { return nil }
        images[key] = img
        return img
    }

    /// RESIZE-FRAME-COST: the 1.2 pt ring mask of `DS3RimView` as an alpha-only nine-slice bitmap, drawn once per
    /// (corner radius, scale) from `DS3RimView.ringPath` and stretched by the render server. Vertically symmetric, so the
    /// bottom-left origin of the bitmap does not matter.
    func ringMask(cornerRadius: CGFloat, scale: CGFloat) -> CGImage? {
        let key = DS3SpriteKey(kind: "mask", shape: .rounded(cornerRadius), heightPx: 0, widthPx: 0, scale: Double(scale),
                               dark: false, stops: [], extra: Double(cornerRadius))
        return image(for: key) {
            let side = DS3SliceGeometry.ringMask(cornerRadius: cornerRadius).side
            let px = Int((side * scale).rounded())
            guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return nil }
            ctx.scaleBy(x: scale, y: scale)
            ctx.addPath(DS3RimView.ringPath(CGSize(width: side, height: side), cornerRadius))
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fillPath()
            return ctx.makeImage()
        }
    }

    /// Renders `v` (laid out at `size` points) into a 16-bit-per-component premultiplied sRGB bitmap of `pixelsWide` x
    /// `pixelsHigh`, content at the top-left. `ImageRenderer.cgImage` is 8-bit, and its premultiplied rounding loses the faint
    /// alpha tail of a gradient edge; 16 bits keep the single 8-bit rounding for the compositing of the final frame.
    static func render<V: View>(_ v: V, scale: CGFloat, size: CGSize, pixelsWide: Int, pixelsHigh: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 16, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        else { return nil }
        let r = ImageRenderer(content: v)
        r.scale = scale
        r.proposedSize = ProposedViewSize(size)
        var drawn = false
        r.render { _, draw in
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: 0, y: CGFloat(pixelsHigh) / scale - size.height)
            draw(ctx)
            drawn = true
        }
        return drawn ? ctx.makeImage() : nil
    }
}

/// Top rim drawn once at the reference width and stretched horizontally (three-slice).
/// Non-sliceable shapes, narrow views and the frames before the first measurement draw the live stroke.
struct DS3StretchSprite<S: InsettableShape>: View {
    let shape: S
    let content: DS3SpriteContent

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var measure: DS3SliceGeometry.Measure?
    /// The bitmap is stored with the key it was rendered for, so a changed height or appearance never shows the old one.
    @State private var sprite: (key: DS3SpriteKey, image: CGImage)?

    private var scale: CGFloat { displayScale }
    private var slice: DS3SliceShape? { (shape as? any DS3SliceableShape)?.ds3Slice }

    private var stops: [Gradient.Stop] {
        switch content {
        case .topRim(let s, _): return s
        }
    }

    private var kind: String {
        switch content {
        case .topRim: return "rim"
        }
    }

    private var lineWidth: CGFloat {
        if case .topRim(_, let w) = content { return w }
        return 0
    }

    private var key: DS3SpriteKey? {
        guard let slice, let measure, !measure.narrow else { return nil }
        return DS3SpriteKey(kind: kind, shape: slice, heightPx: measure.heightPx, widthPx: 0, scale: Double(scale),
                            dark: colorScheme == .dark, stops: ds3ResolvedStops(stops, dark: colorScheme == .dark),
                            extra: Double(lineWidth))
    }

    @ViewBuilder
    private func gradientView(_ stops: [Gradient.Stop]) -> some View {
        switch content {
        case .topRim(_, let w):
            shape.strokeBorder(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom), lineWidth: w)
        }
    }

    private var live: some View { gradientView(stops) }

    var body: some View {
        Color.clear
            .onGeometryChange(for: DS3SliceGeometry.Measure?.self,
                              of: { g in slice.map { DS3SliceGeometry.measure($0, frame: g.frame(in: .global), scale: scale) } }) { measure = $0 }
            .overlay(alignment: .top) {
                if let key, let sprite, sprite.key == key, let slice {
                    let cap = DS3SliceGeometry.cap(slice, height: CGFloat(key.heightPx) / scale)
                    Image(decorative: sprite.image, scale: scale)
                        .resizable(capInsets: EdgeInsets(top: 0, leading: cap, bottom: 0, trailing: cap), resizingMode: .stretch)
                        .frame(height: CGFloat(key.heightPx) / scale)
                } else {
                    live
                }
            }
            .task(id: key) {
                sprite = key.flatMap { k in DS3SpriteCache.shared.image(for: k) { renderSprite(k) }.map { (k, $0) } }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func renderSprite(_ k: DS3SpriteKey) -> CGImage? {
        let h0 = CGFloat(k.heightPx) / scale
        let w0 = DS3SliceGeometry.referenceWidth(cap: DS3SliceGeometry.cap(k.shape, height: h0))
        let resolved: [Gradient.Stop] = k.stops.map { s in
            let color = Color(.sRGB, red: Double(s.r) / 65535, green: Double(s.g) / 65535, blue: Double(s.b) / 65535,
                              opacity: Double(s.a) / 65535)
            return Gradient.Stop(color: color, location: CGFloat(s.location) / 10000)
        }
        let view = gradientView(resolved).frame(width: w0, height: h0)
        return DS3SpriteCache.render(view, scale: scale, size: CGSize(width: w0, height: h0),
                                     pixelsWide: Int((w0 * scale).rounded()), pixelsHigh: k.heightPx)
    }

}
