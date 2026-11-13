// Views/DS3LayerViews.swift
// IPHONE-SCROLL-LAG: Core Animation hosts for the DS3 pointer-light rim (RIM-GLOW-OPTICS) and orbs. Content is rendered once; motion is layer animation evaluated by the render server.

import SwiftUI
import AppKit
import QuartzCore
import IOSurface

/// Resolves an appearance-dynamic SwiftUI `Color` against `appearance`. Same technique as
/// `BarFillLayerView.resolvedColor`: `ImageRenderer` does not reliably resolve `NSColor(dynamicProvider:)` colours.
@MainActor
func ds3Resolve(_ color: Color, in appearance: NSAppearance) -> CGColor {
    var out = CGColor(gray: 0, alpha: 0)
    appearance.performAsCurrentDrawingAppearance {
        let base = NSColor(color)
        out = (base.usingColorSpace(.sRGB) ?? base).cgColor
    }
    return out
}

// MARK: - Rim

/// RIM-HOVER-COST: the eight disjoint rectangles (card-local points, y down) that hold every pixel the 1.2 pt ring
/// can touch: four corner patches and four edge strips. Inner edges lie on whole points; outer edges sit 1 pt outside
/// the card, so the ring mask's own bounds, not the band clip, stay the outer clip (spec D5-D7).
/// Order: top-left, top, top-right, left, right, bottom-left, bottom, bottom-right.
enum RimBands {
    /// Corner patch depth = ceil(cornerFactor * cornerRadius) + cornerPad: the continuous corner curve leaves the
    /// straight edge about 1.53 r from the corner; + 2 pt keeps the anti-aliased edge inside the patch.
    static let cornerFactor: CGFloat = 1.6
    static let cornerPad: CGFloat = 2
    /// Edge strip thickness: the straight ring occupies 0-1.2 pt from the edge, plus one pixel of anti-aliasing.
    static let strip: CGFloat = 3

    static func rects(size: CGSize, cornerRadius: CGFloat) -> [CGRect] {
        let w = max(size.width, 0), h = max(size.height, 0)
        let halfW = (w / 2).rounded(.down), halfH = (h / 2).rounded(.down)
        let k = max((cornerFactor * cornerRadius).rounded(.up) + cornerPad, strip)
        let kx = min(k, halfW), ky = min(k, halfH)
        let s = min(strip, halfW, halfH)
        let xR = (w - kx).rounded(.down), yB = (h - ky).rounded(.down)
        let xS = (w - s).rounded(.down), yS = (h - s).rounded(.down)
        func r(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
        }
        return [
            r(-1, -1, kx, ky), r(kx, -1, xR, s), r(xR, -1, w + 1, ky),
            r(-1, ky, s, yB), r(xS, ky, w + 1, yB),
            r(-1, yB, kx, h + 1), r(kx, yS, xR, h + 1), r(xR, yB, w + 1, h + 1),
        ]
    }

    /// Added to the sprite's range R: the sprite bitmap is exactly zero at r >= R (`OrbBitmap.render`), bilinear
    /// sampling spreads a texel by at most 1 pt, and the bitmap side is rounded to whole pixels (spec D13).
    static let reachPad: CGFloat = 2

    /// True when a light whose centre travels the segment `from`-`to` (card-local points) comes closer than `radius`
    /// to a non-empty band, i.e. can put light on a ring pixel. Empty bands hold no ring pixel (RimBandsTests).
    static func reaches(_ bands: [CGRect], from a: CGPoint, to b: CGPoint, radius: CGFloat) -> Bool {
        bands.contains { !$0.isEmpty && distance($0, a, b) < radius }
    }

    /// Shortest distance between segment ab and rect r; 0 when they meet.
    static func distance(_ r: CGRect, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        // Liang-Barsky: does the segment enter the rect?
        var t0: CGFloat = 0, t1: CGFloat = 1, meets = true
        for (p, q) in [(-dx, a.x - r.minX), (dx, r.maxX - a.x), (-dy, a.y - r.minY), (dy, r.maxY - a.y)] {
            if p == 0 {
                if q < 0 { meets = false; break }
            } else {
                let t = q / p
                if p < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                if t0 > t1 { meets = false; break }
            }
        }
        if meets { return 0 }
        func toRect(_ p: CGPoint) -> CGFloat {
            hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
        }
        func toSegment(_ c: CGPoint) -> CGFloat {
            let l2 = dx * dx + dy * dy
            let t = l2 > 0 ? min(max(((c.x - a.x) * dx + (c.y - a.y) * dy) / l2, 0), 1) : 0
            return hypot(a.x + t * dx - c.x, a.y + t * dy - c.y)
        }
        // Disjoint convex sets: the minimum is at an endpoint (to the rect) or at a rect corner (to the segment).
        return min(toRect(a), toRect(b),
                   toSegment(CGPoint(x: r.minX, y: r.minY)), toSegment(CGPoint(x: r.maxX, y: r.minY)),
                   toSegment(CGPoint(x: r.minX, y: r.maxY)), toSegment(CGPoint(x: r.maxX, y: r.maxY)))
    }
}

/// RIM-HOVER-COST: which layer set draws a card's pointer light (spec D20-D23). `ring`: the sprite inside the static
/// card-sized ring group (main's structure). `bands`: the eight band sprites. `none`: the light cannot reach the ring.
/// All nine sprites always hold the same values and animations, so switching carriers changes no pixel.
enum RimLightCarrier: Equatable {
    case none, ring, bands

    static func pick(reaches: Bool, inMotion: Bool, leaving: Bool) -> RimLightCarrier {
        guard reaches else { return .none }
        if inMotion && !leaving { return .bands }
        return .ring
    }
}

struct DS3RimLayer: NSViewRepresentable {
    let cornerRadius: CGFloat
    let model: DS3RimModel
    let isStatic: Bool

    func makeNSView(context: Context) -> DS3RimView {
        let v = DS3RimView(cornerRadius: cornerRadius)
        v.setStatic(isStatic)
        model.view = v
        v.setLeaving(model.leaving)
        return v
    }

    func updateNSView(_ nsView: DS3RimView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.setStatic(isStatic)
        nsView.configure(profileKey: RimSettingsObserver.shared.profileKey)
        model.view = nsView
        nsView.setLeaving(model.leaving)
    }

    /// Takes whatever the parent offers (same as `BarFillLayer.sizeThatFits`).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DS3RimView, context: Context) -> CGSize? {
        func finite(_ v: CGFloat?) -> CGFloat {
            guard let v, v.isFinite else { return 0 }
            return v
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }
}

/// RIM-GLOW-OPTICS look, RIM-HOVER-COST structure: the 1.2 pt ring of a glass card as main's card-sized ring group (ring mask, ambient light from above, pointer-light sprite, plusL) plus eight clipped bands (RimBands) that each hold a copy of the sprite (ring mask, plusL). The bands carry the light only while it moves on a card it can reach and that is not on a leaving Home; at rest the ring group carries it, so a resting or unreached card costs what main's ring costs (spec D10-D23). Per pointer event: one presentation read, one position set and one fixed-key animation per sprite, all in one transaction.
final class DS3RimView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var cornerRadius: CGFloat {
        didSet { if cornerRadius != oldValue { needsLayout = true } }
    }
    private(set) var isStatic = false

    /// One clipped copy of the sprite. `clip`: band rect, `masksToBounds`, ring mask, plusL. `shift`: plain, card-sized, so `spot` keeps card-local geometry in every band (spec D3).
    private struct Band {
        let clip = CALayer()
        let mask = CAShapeLayer()
        let shift = CALayer()
        let spot = CALayer()
    }
    private let bands: [Band] = (0..<8).map { _ in Band() }
    /// Main's card-sized ring group: ring mask + ambient light from above + the sprite `ringSpot` (plusL), group
    /// plusL. It carries the light at rest and on a leaving page; the bands carry it while it moves (spec D10, D20).
    private let ring = CALayer()
    private let ringMask = CAShapeLayer()
    private let ambient = CALayer()
    private let ringSpot = CALayer()
    /// Every sprite: the ring's and the eight bands'. All get the same model values and animations in the same
    /// transaction, so `ringSpot` stands for all of them when reading the presentation.
    private lazy var spots: [CALayer] = [ringSpot] + bands.map(\.spot)
    private var shadeRing: CALayer?
    private var shadeMask: CAShapeLayer?
    private var h: Double
    private var spotVisible = false
    /// The sprite is fading out after the pointer left the window (its 0.12 s fade has not completed).
    private var fadingOut = false
    /// Bumped by every fade and by `setStatic(true)`; a fade-out completion with an older token does nothing.
    private var fadeToken = 0
    /// Segment the sprite centre travels after the last committed aim (card-local): a superset of every position it
    /// is drawn at from that commit on (spec D15).
    private var lightPath = (from: CGPoint.zero, to: CGPoint.zero)
    /// Band rectangles from the last `layout()`; empty before the first layout (= nothing reaches).
    private var bandRects: [CGRect] = []
    /// Which layer set draws the light now (model value of `ringSpot`/band `isHidden`).
    private var carrier = RimLightCarrier.none
    /// A follow animation is in flight: from a follow aim until that animation's completion (spec D21).
    private var inMotion = false
    /// Bumped by every follow, first aim and `setStatic(true)`; a follow completion with an older token does nothing.
    private var motionToken = 0
    /// This card belongs to Home while Home is fading out under an opened page (spec D22): never `bands`.
    private var leaving = false
    /// Light appearance with `RimLight.lightMode == .none`: ring group and bands hidden (dead path today, kept correct).
    private var ringOff = false
    private var loggedRenderFailure = false

    private struct RenderKey: Equatable {
        let appearance: NSAppearance.Name
        let scale: CGFloat
        let h: Double
        let depthPx: Int
    }
    private var renderedKey: RenderKey?

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        self.h = RimSettingsObserver.height(for: RimSettingsObserver.shared.profileKey)
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let off = NSNull()
        let keys = ["bounds", "position", "frame", "transform", "path", "contents", "hidden",
                    "compositingFilter", "opacity", "backgroundColor"]
        for l in [ring, ringMask, ambient, ringSpot] as [CALayer] {
            l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
        }
        ringMask.fillColor = CGColor(gray: 0, alpha: 1)
        ring.mask = ringMask
        ambient.contentsGravity = .resize
        ringSpot.contentsGravity = .resize
        ringSpot.opacity = 0
        ringSpot.isHidden = true
        ringSpot.compositingFilter = "plusL"
        ring.compositingFilter = "plusL"
        ring.addSublayer(ambient)
        ring.addSublayer(ringSpot)
        layer?.addSublayer(ring)
        for b in bands {
            for l in [b.clip, b.mask, b.shift, b.spot] as [CALayer] {
                l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
            }
            b.mask.fillColor = CGColor(gray: 0, alpha: 1)
            b.clip.mask = b.mask
            b.clip.masksToBounds = true
            b.clip.isHidden = true
            b.spot.contentsGravity = .resize
            b.spot.opacity = 0
            b.spot.compositingFilter = "plusL"
            b.clip.compositingFilter = "plusL"
            b.shift.addSublayer(b.spot)
            b.clip.addSublayer(b.shift)
            layer?.addSublayer(b.clip)
        }
        RimSettingsObserver.shared.register(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = bounds.size
        let path = Self.ringPath(size, cornerRadius)
        let r = CGFloat(RimLight.range(h: h))
        ring.frame = bounds
        ringMask.frame = ring.bounds
        ringMask.path = path
        ambient.frame = CGRect(x: 0, y: 0, width: size.width, height: cornerRadius)
        ringSpot.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        let rects = RimBands.rects(size: size, cornerRadius: cornerRadius)
        for (b, rect) in zip(bands, rects) {
            let card = CGRect(x: -rect.minX, y: -rect.minY, width: size.width, height: size.height)
            b.clip.frame = rect
            b.mask.frame = card
            b.mask.path = path
            b.shift.frame = card
            b.spot.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        }
        if let shadeRing, let shadeMask {
            shadeRing.frame = bounds
            shadeMask.frame = shadeRing.bounds
            shadeMask.path = path
        }
        bandRects = rects
        syncCarrier()
        CATransaction.commit()
        renderIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderIfNeeded()
    }

    /// The 1.2 pt `strokeBorder` outline of the continuous rounded rectangle, as a fillable path.
    static func ringPath(_ size: CGSize, _ r: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .inset(by: 0.6)
            .path(in: CGRect(origin: .zero, size: size))
            .cgPath
            .copy(strokingWithWidth: 1.2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }

    /// Edge-light profile from the Settings row (`RimSettingsObserver`).
    func configure(profileKey: String) {
        let newH = RimSettingsObserver.height(for: profileKey)
        guard newH != h else { return }
        h = newH
        renderedKey = nil
        needsLayout = true
        renderIfNeeded()
    }

    /// Sprite and ambient bitmaps at the window's backing scale, for this appearance; shared through `RimSpriteCache`.
    /// Never per event. A failed render is not recorded, so the next pass retries.
    private func renderIfNeeded() {
        guard let window else { return }
        let scale = window.backingScaleFactor
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if !isDark && RimLight.lightMode == .none {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ringOff = true
            ring.isHidden = true
            for b in bands { b.clip.isHidden = true }
            shadeRing?.isHidden = true
            CATransaction.commit()
            renderedKey = nil
            return
        }
        let depthPx = Int((cornerRadius * scale).rounded(.up))
        let key = RenderKey(appearance: effectiveAppearance.name, scale: scale, h: h, depthPx: depthPx)
        guard key != renderedKey else { return }
        var ground = isDark ? DS3.rimGroundDark : DS3.rimGroundLight
        let shaded = !isDark && RimLight.lightMode == .shade
        if shaded {
            ground = RimLight.shadedGround(ground, shade: SIMD3<Double>(60, 40, 20) / 255, alpha: 0.12)
        }
        let sprite = RimSpriteCache.shared.sprite(h: h, scale: scale, ground: ground)
        let amb = depthPx > 0 ? RimSpriteCache.shared.ambient(depthPx: depthPx, ground: ground, alpha: isDark ? 0.2 : 0.5) : nil
        if sprite == nil || (depthPx > 0 && amb == nil) {
            if !loggedRenderFailure { NSLog("[Moonport] rim bitmap render failed; keeping the previous contents, retrying on the next pass") }
            loggedRenderFailure = true
        } else {
            renderedKey = key
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringOff = false
        ring.isHidden = false
        ringSpot.isHidden = carrier != .ring
        for b in bands { b.clip.isHidden = carrier != .bands }
        if shaded {
            if shadeRing == nil, let host = layer {
                let sr = CALayer()
                let sm = CAShapeLayer()
                let off = NSNull()
                let keys = ["bounds", "position", "frame", "path", "hidden", "backgroundColor"]
                for l in [sr, sm] as [CALayer] { l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) }) }
                sm.fillColor = CGColor(gray: 0, alpha: 1)
                sr.mask = sm
                host.insertSublayer(sr, below: ring)
                shadeRing = sr
                shadeMask = sm
                needsLayout = true
            }
            shadeRing?.isHidden = false
            shadeRing?.backgroundColor = ds3Resolve(DS3.rimShade, in: effectiveAppearance)
        } else {
            shadeRing?.isHidden = true
        }
        for s in spots { if let sprite { s.contents = sprite }; s.contentsScale = scale }
        if let amb { ambient.contents = amb }
        ambient.contentsScale = scale
        CATransaction.commit()
    }

    func setStatic(_ s: Bool) {
        guard s != isStatic else { return }
        isStatic = s
        if s {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for s in spots {
                s.removeAllAnimations()
                s.opacity = 0
            }
            spotVisible = false
            fadingOut = false
            fadeToken &+= 1
            inMotion = false
            motionToken &+= 1
            syncCarrier()
            CATransaction.commit()
        }
    }

    /// Home is fading out under an opened page (true) or shown again (false); from `DS3RimModel.setLeaving` (spec D22).
    func setLeaving(_ l: Bool) {
        guard l != leaving else { return }
        leaving = l
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncCarrier()
        CATransaction.commit()
    }

    /// Moves the light to the pointer's card-local point (nil = pointer outside the window: fade out).
    /// A fixed animation key replaces the previous one, so at most one live animation per card.
    /// Position, animations, opacity and band visibility change in one transaction (spec D16).
    func aim(to local: CGPoint?) {
        guard !isStatic, local != nil || spotVisible else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let local {
            if !spotVisible {
                // First aim: the sprite jumps to the pointer and rests there while it fades in.
                spotVisible = true
                fadingOut = false
                fadeToken &+= 1
                inMotion = false
                motionToken &+= 1
                for s in spots {
                    s.position = local
                    s.removeAnimation(forKey: "pos")
                }
                lightPath = (local, local)
                fade(to: 1)
            } else {
                // Follow: in motion until this follow's animations complete (a newer aim replaces them first).
                motionToken &+= 1
                let mt = motionToken
                CATransaction.setCompletionBlock { [weak self] in self?.motionEnded(mt) }
                inMotion = true
                let from = ringSpot.presentation()?.position ?? ringSpot.position
                for s in spots { s.position = local }
                let a = CABasicAnimation(keyPath: "position")
                a.fromValue = NSValue(point: from)
                a.toValue = NSValue(point: local)
                a.duration = DS3Motion.rimFollow
                a.timingFunction = CAMediaTimingFunction(name: .linear)
                for s in spots { s.add(a, forKey: "pos") }
                lightPath = (from, local)
            }
        } else {
            // Pointer left the window: the sprite finishes its current follow (inside `lightPath`) while it fades.
            spotVisible = false
            fadingOut = true
            fadeToken &+= 1
            let token = fadeToken
            CATransaction.setCompletionBlock { [weak self] in self?.fadeOutEnded(token) }
            fade(to: 0)
        }
        syncCarrier()
        CATransaction.commit()
    }

    /// Call inside an open transaction (aim). `add(_:forKey:)` copies, so one animation object serves all sprites.
    private func fade(to value: Float) {
        let from = ringSpot.presentation()?.opacity ?? ringSpot.opacity
        for s in spots { s.opacity = value }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = value
        a.duration = DS3Motion.rimFade
        for s in spots { s.add(a, forKey: "fade") }
    }

    /// The pointer-left fade has completed or was replaced. Only the newest fade-out may end the light.
    private func fadeOutEnded(_ token: Int) {
        guard token == fadeToken, fadingOut else { return }
        fadingOut = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncCarrier()
        CATransaction.commit()
    }

    /// The newest follow has arrived (no aim since): the light rests, so the ring group carries it (spec D21).
    private func motionEnded(_ token: Int) {
        guard token == motionToken, inMotion else { return }
        inMotion = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncCarrier()
        CATransaction.commit()
    }

    /// Picks the carrier (`RimLightCarrier.pick`) and shows exactly that layer set, both toggles in the caller's
    /// transaction. `reaches`: the sprite is visible or still fading out, and the segment it travels from this commit on
    /// comes within R + pad of a band (spec D11-D14). Any switch changes no pixel: all nine sprites are identical (D20).
    private func syncCarrier() {
        let radius = CGFloat(RimLight.range(h: h)) + RimBands.reachPad
        let reaches = (spotVisible || fadingOut)
            && RimBands.reaches(bandRects, from: lightPath.from, to: lightPath.to, radius: radius)
        let c = RimLightCarrier.pick(reaches: reaches, inMotion: inMotion, leaving: leaving)
        guard c != carrier else { return }
        carrier = c
        guard !ringOff else { return }
        ringSpot.isHidden = c != .ring
        for b in bands { b.clip.isHidden = c != .bands }
    }
}

/// One surface per key for every card on every page (R4). Entries are never evicted: a handful per process.
@MainActor
final class RimSpriteCache {
    static let shared = RimSpriteCache()
    private struct SpriteKey: Hashable { let h: Double; let scale: Double; let ground: [Int] }
    private struct AmbientKey: Hashable { let depthPx: Int; let alpha: Double; let ground: [Int] }
    private var sprites: [SpriteKey: IOSurfaceRef] = [:]
    private var ambients: [AmbientKey: IOSurfaceRef] = [:]

    private static func quantised(_ g: SIMD3<Double>) -> [Int] { (0..<3).map { Int((g[$0] * 255).rounded()) } }

    func sprite(h: Double, scale: CGFloat, ground: SIMD3<Double>) -> IOSurfaceRef? {
        let k = SpriteKey(h: h, scale: Double(scale), ground: Self.quantised(ground))
        if let s = sprites[k] { return s }
        guard let s = RimLight.render(h: h, scale: Double(scale), ground: ground)?.surface else { return nil }
        sprites[k] = s
        return s
    }

    func ambient(depthPx: Int, ground: SIMD3<Double>, alpha: Double) -> IOSurfaceRef? {
        let k = AmbientKey(depthPx: depthPx, alpha: alpha, ground: Self.quantised(ground))
        if let s = ambients[k] { return s }
        guard let s = RimAmbient.render(depthPx: depthPx, ground: ground, alpha: alpha)?.surface else { return nil }
        ambients[k] = s
        return s
    }
}

// MARK: - Shadow sprite

/// RESIZE-FRAME-COST: the `ds3Elevation` stack of a glass card / the header, rendered once into a nine-slice bitmap and
/// shown by one plain layer, so a width step costs the render server a stretch instead of an offscreen blur pass.
struct DS3ShadowSpriteLayer: NSViewRepresentable {
    let kind: DS3Shadow
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> DS3ShadowSpriteView {
        DS3ShadowSpriteView(kind: kind, cornerRadius: cornerRadius)
    }

    func updateNSView(_ nsView: DS3ShadowSpriteView, context: Context) {
        nsView.cornerRadius = cornerRadius
    }

    /// Takes whatever the parent offers (same as `DS3RimLayer.sizeThatFits`).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DS3ShadowSpriteView, context: Context) -> CGSize? {
        func finite(_ v: CGFloat?) -> CGFloat {
            guard let v, v.isFinite else { return 0 }
            return v
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }
}

final class DS3ShadowSpriteView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    let kind: DS3Shadow
    var cornerRadius: CGFloat {
        didSet {
            guard cornerRadius != oldValue else { return }
            nineSlice = Self.nineSlice(kind: kind, cornerRadius: cornerRadius)
            renderedKey = nil
            needsLayout = true
        }
    }

    /// Cached per corner radius (recomputed in `cornerRadius.didSet`), not per layout pass.
    private var nineSlice: DS3SliceGeometry.NineSlice
    private let keyKind: String
    private let sprite = CALayer()
    private var renderedKey: DS3SpriteKey?
    private var loggedRenderFailure = false

    init(kind: DS3Shadow, cornerRadius: CGFloat) {
        self.kind = kind
        self.cornerRadius = cornerRadius
        self.nineSlice = Self.nineSlice(kind: kind, cornerRadius: cornerRadius)
        self.keyKind = "shadow.\(kind)"
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let off = NSNull()
        let keys = ["bounds", "position", "frame", "contents", "contentsRect", "contentsCenter", "contentsScale",
                    "hidden", "transform"]
        sprite.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
        layer?.addSublayer(sprite)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func nineSlice(kind: DS3Shadow, cornerRadius: CGFloat) -> DS3SliceGeometry.NineSlice {
        let ls = kind.layers
        return DS3SliceGeometry.shadow(cornerRadius: cornerRadius,
                                       maxRadius: ls.map(\.radius).max() ?? 0,
                                       maxInset: ls.map(\.inset).max() ?? 0,
                                       maxY: ls.map(\.y).max() ?? 0)
    }

    override func layout() {
        super.layout()
        let n = nineSlice
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds.insetBy(dx: -n.bleed, dy: -n.bleed)
        CATransaction.commit()
        renderIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderIfNeeded()
    }

    private func renderIfNeeded() {
        // An empty view (first layout before SwiftUI sizes it) has nothing to show; skip the throwaway 0 x 0 render.
        guard let window, !bounds.isEmpty else { return }
        let scale = window.backingScaleFactor
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let n = nineSlice
        let fixedW = DS3SliceGeometry.fixedAxis(bounds.width, n, scale: scale)
        let fixedH = DS3SliceGeometry.fixedAxis(bounds.height, n, scale: scale)
        let key = DS3SpriteKey(kind: keyKind, shape: .rounded(cornerRadius), heightPx: fixedH ?? 0, widthPx: fixedW ?? 0,
                               scale: Double(scale), dark: dark, stops: [], extra: Double(cornerRadius))
        guard key != renderedKey else { return }
        guard let image = DS3SpriteCache.shared.image(for: key, render: { render(n, fixedW: fixedW, fixedH: fixedH, scale: scale) }) else {
            if !loggedRenderFailure {
                loggedRenderFailure = true
                NSLog("DS3ShadowSpriteView: shadow sprite render failed")
            }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = image
        sprite.contentsScale = scale
        sprite.contentsCenter = n.contentsCenter(fixedWidth: fixedW != nil, fixedHeight: fixedH != nil)
        CATransaction.commit()
        renderedKey = key
    }

    /// The existing `ds3Elevation` stack (blur, insets, offsets, `destinationOut` punch) on a view of the reference size,
    /// padded by the bleed so the blur tail lands inside the bitmap.
    private func render(_ n: DS3SliceGeometry.NineSlice, fixedW: Int?, fixedH: Int?, scale: CGFloat) -> CGImage? {
        let w0 = fixedW.map { CGFloat($0) / scale } ?? (2 * n.core + 2)
        let h0 = fixedH.map { CGFloat($0) / scale } ?? (2 * n.core + 2)
        let appearance = effectiveAppearance
        let view = Color.clear
            .frame(width: w0, height: h0)
            .ds3Elevation(kind, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                          resolve: { Color(cgColor: ds3Resolve($0, in: appearance)) })
            .padding(n.bleed)
        let size = CGSize(width: w0 + 2 * n.bleed, height: h0 + 2 * n.bleed)
        return DS3SpriteCache.render(view, scale: scale, size: size,
                                     pixelsWide: Int((size.width * scale).rounded()), pixelsHigh: Int((size.height * scale).rounded()))
    }
}

/// The edge-light profile: `rimProfile` ("1" | "2" | "3", default "2"; written by `AppSettings` from the Settings row)
/// in the app's own domain, switched live by KVO.
@MainActor
final class RimSettingsObserver {
    static let shared = RimSettingsObserver()
    private var observer: DefaultsKeyObserver?
    private let views = NSHashTable<DS3RimView>.weakObjects()

    private(set) var profileKey = RimLight.defaultProfileKey

    static func height(for key: String) -> Double {
        RimLight.heights[key] ?? RimLight.heights[RimLight.defaultProfileKey]!
    }

    private init() {
        read()
        // KVO reports changes made by other processes (`defaults write`); the callback may come on any thread.
        observer = DefaultsKeyObserver(keys: [AppSettings.rimProfileKey]) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.changed() } }
        }
    }

    func register(_ v: DS3RimView) { views.add(v) }

    private func read() {
        let k = UserDefaults.standard.string(forKey: AppSettings.rimProfileKey) ?? RimLight.defaultProfileKey
        profileKey = RimLight.heights[k] != nil ? k : RimLight.defaultProfileKey
    }

    private func changed() {
        read()
        for v in views.allObjects { v.configure(profileKey: profileKey) }
    }
}

// MARK: - Orbs

/// One soft colour glow: colour, diameter and a centre function of the layer size.
struct DS3OrbSpec: Sendable {
    let color: Color
    let d: CGFloat
    let centre: @Sendable (CGSize) -> CGPoint

    /// The main window's three v2 orbs (`This Mac Home v2.dc.html:33-35`): A back 780 `top -300 right -220`,
    /// B mid 580 `top 330 left -250`, C front 420 `bottom -190 right 20%`. REDESIGN-ORBS.
    static let window: [DS3OrbSpec] = [
        DS3OrbSpec(color: DS3.orbA, d: 780, centre: { OrbGeometry.centre(left: OrbGeometry.leftFromRight(-220, d: 780, width: $0.width), top: -300, d: 780) }),
        DS3OrbSpec(color: DS3.orbB, d: 580, centre: { _ in OrbGeometry.centre(left: -250, top: 330, d: 580) }),
        DS3OrbSpec(color: DS3.orbC, d: 420, centre: { OrbGeometry.centre(left: OrbGeometry.leftFromRight(0.2 * $0.width, d: 420, width: $0.width), top: OrbGeometry.topFromBottom(-190, d: 420, height: $0.height), d: 420) }),
    ]

    /// The Settings window's smaller set (`Settings.dc.html:28-30`); values unchanged by REDESIGN-ORBS
    /// (D1: colour, blend and H1 profile follow the window set).
    static let settings: [DS3OrbSpec] = [
        DS3OrbSpec(color: DS3.orbA, d: 520, centre: { _ in CGPoint(x: 80, y: 40) }),
        DS3OrbSpec(color: DS3.orbB, d: 460, centre: { CGPoint(x: $0.width - 70, y: $0.height + 10) }),
        DS3OrbSpec(color: DS3.orbC, d: 380, centre: { CGPoint(x: $0.width - 250, y: -70) }),
    ]
}

struct DS3OrbLayer: NSViewRepresentable {
    var orbs: [DS3OrbSpec] = DS3OrbSpec.window

    func makeNSView(context: Context) -> DS3OrbView { DS3OrbView(orbs: orbs) }

    func updateNSView(_ nsView: DS3OrbView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DS3OrbView, context: Context) -> CGSize? {
        func finite(_ v: CGFloat?) -> CGFloat {
            guard let v, v.isFinite else { return 0 }
            return v
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }
}

final class DS3OrbView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private let orbs: [DS3OrbSpec]
    private let container = CALayer()
    private let orbLayers: [CALayer]
    private var renderedAppearance: NSAppearance.Name?
    private var renderedScale: CGFloat?
    private var loggedRenderFailure = false

    init(orbs: [DS3OrbSpec]) {
        self.orbs = orbs
        self.orbLayers = orbs.map { _ in CALayer() }
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let off = NSNull()
        let keys = ["bounds", "position", "frame", "transform", "path", "contents", "hidden", "compositingFilter", "opacity"]
        for l in [container] + orbLayers {
            l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
        }
        for l in orbLayers { container.addSublayer(l) }
        layer?.addSublayer(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        for (l, o) in zip(orbLayers, orbs) {
            let side = OrbProfile.sideFactor * o.d        // 1.4·d (spec §3.3): the layer holds the whole H1 window W(u)
            l.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            l.position = o.centre(bounds.size)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderImagesIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderImagesIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderImagesIfNeeded()
    }

    /// H1 orb bitmaps (spec §3.3) at the window's backing scale, colours and ground resolved for this view's
    /// appearance. Runs once per appearance × scale on the main thread, before the first paint after attach; never
    /// per frame (D12). Dark bitmaps are deltas over `DS3.ground`, so a ground change re-renders with the appearance.
    private func renderImagesIfNeeded() {
        guard let window else { return }
        let scale = window.backingScaleFactor
        let name = effectiveAppearance.name
        guard name != renderedAppearance || scale != renderedScale else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let mode: OrbBitmap.Mode = isDark ? .dark(ground: Self.rgb(ds3Resolve(DS3.ground, in: effectiveAppearance))) : .light
        let images = orbs.enumerated().map { i, o in
            let c = ds3Resolve(o.color, in: effectiveAppearance)
            return OrbBitmap.render(d: o.d, scale: scale, colour: Self.rgb(c), alpha: Double(c.alpha), mode: mode,
                                    seed: OrbBitmap.seed(orb: i))?.surface   // the layer retains its surface
        }
        let failed = images.contains { $0 == nil }
        if failed {
            if !loggedRenderFailure { NSLog("[Moonport] orb bitmap render failed; keeping the previous contents, retrying on the next pass") }
            loggedRenderFailure = true
        } else {
            renderedAppearance = name        // a failed render is not recorded, so the next pass retries
            renderedScale = scale
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (l, img) in zip(orbLayers, images) {
            if let img { l.contents = img }
            l.contentsScale = scale
            l.compositingFilter = isDark ? "plusL" : nil
        }
        CATransaction.commit()
    }

    /// The r, g, b of a `ds3Resolve` colour (always sRGB with four components).
    private static func rgb(_ c: CGColor) -> SIMD3<Double> {
        guard let k = c.components, k.count >= 3 else { return SIMD3(repeating: 0) }
        return SIMD3(Double(k[0]), Double(k[1]), Double(k[2]))
    }
}
