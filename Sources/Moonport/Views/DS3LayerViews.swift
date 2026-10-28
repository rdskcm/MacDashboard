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
}

struct DS3RimLayer: NSViewRepresentable {
    let cornerRadius: CGFloat
    let model: DS3RimModel
    let isStatic: Bool

    func makeNSView(context: Context) -> DS3RimView {
        let v = DS3RimView(cornerRadius: cornerRadius)
        v.setStatic(isStatic)
        model.view = v
        return v
    }

    func updateNSView(_ nsView: DS3RimView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.setStatic(isStatic)
        nsView.configure(profileKey: RimSettingsObserver.shared.profileKey)
        model.view = nsView
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

/// RIM-GLOW-OPTICS look, RIM-HOVER-COST structure: the 1.2 pt ring of a glass card as eight clipped bands (RimBands), each a full copy of the ring group (ring mask, static ambient layer, pointer-light sprite, all composited plusL as in spec §3.2, §3.3, D8), so a moving light repaints only the bands. Per pointer event: one presentation read, one position set and one fixed-key animation per band, in one transaction.
final class DS3RimView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var cornerRadius: CGFloat {
        didSet { if cornerRadius != oldValue { needsLayout = true } }
    }
    private(set) var isStatic = false

    /// One clipped copy of the old card-sized ring group. `clip`: band rect, `masksToBounds`, ring mask, plusL.
    /// `shift`: plain, card-sized, so `ambient` and `spot` keep card-local geometry in every band (spec D3).
    private struct Band {
        let clip = CALayer()
        let mask = CAShapeLayer()
        let shift = CALayer()
        let ambient = CALayer()
        let spot = CALayer()
    }
    /// Invariant: every sprite gets the same model values and the same animations in the same transaction, so
    /// `bands[0].spot` stands for all of them when reading the presentation.
    private let bands: [Band] = (0..<8).map { _ in Band() }
    private var shadeRing: CALayer?
    private var shadeMask: CAShapeLayer?
    private var h: Double
    private var spotVisible = false
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
        for b in bands {
            for l in [b.clip, b.mask, b.shift, b.ambient, b.spot] as [CALayer] {
                l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
            }
            b.mask.fillColor = CGColor(gray: 0, alpha: 1)
            b.clip.mask = b.mask
            b.clip.masksToBounds = true
            b.ambient.contentsGravity = .resize
            b.spot.contentsGravity = .resize
            b.spot.opacity = 0
            b.spot.compositingFilter = "plusL"
            b.clip.compositingFilter = "plusL"
            b.shift.addSublayer(b.ambient)
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
        for (b, rect) in zip(bands, RimBands.rects(size: size, cornerRadius: cornerRadius)) {
            let card = CGRect(x: -rect.minX, y: -rect.minY, width: size.width, height: size.height)
            b.clip.frame = rect
            b.mask.frame = card
            b.mask.path = path
            b.shift.frame = card
            b.ambient.frame = CGRect(x: 0, y: 0, width: size.width, height: cornerRadius)
            b.spot.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        }
        if let shadeRing, let shadeMask {
            shadeRing.frame = bounds
            shadeMask.frame = shadeRing.bounds
            shadeMask.path = path
        }
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
        for b in bands { b.clip.isHidden = false }
        if shaded {
            if shadeRing == nil, let host = layer {
                let sr = CALayer()
                let sm = CAShapeLayer()
                let off = NSNull()
                let keys = ["bounds", "position", "frame", "path", "hidden", "backgroundColor"]
                for l in [sr, sm] as [CALayer] { l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) }) }
                sm.fillColor = CGColor(gray: 0, alpha: 1)
                sr.mask = sm
                host.insertSublayer(sr, below: bands[0].clip)
                shadeRing = sr
                shadeMask = sm
                needsLayout = true
            }
            shadeRing?.isHidden = false
            shadeRing?.backgroundColor = ds3Resolve(DS3.rimShade, in: effectiveAppearance)
        } else {
            shadeRing?.isHidden = true
        }
        for b in bands {
            if let sprite { b.spot.contents = sprite }
            if let amb { b.ambient.contents = amb }
            b.spot.contentsScale = scale
            b.ambient.contentsScale = scale
        }
        CATransaction.commit()
    }

    func setStatic(_ s: Bool) {
        guard s != isStatic else { return }
        isStatic = s
        if s {
            for b in bands { b.spot.removeAllAnimations() }
            spotVisible = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for b in bands { b.spot.opacity = 0 }
            CATransaction.commit()
        }
    }

    /// Moves the light to the pointer's card-local point (nil = pointer outside the window: fade out).
    /// A fixed animation key replaces the previous one, so at most one live animation per card.
    func aim(to local: CGPoint?) {
        guard !isStatic else { return }
        guard let local else {
            if spotVisible { spotVisible = false; fade(to: 0) }
            return
        }
        if !spotVisible {
            spotVisible = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for b in bands { b.spot.position = local }
            CATransaction.commit()
            for b in bands { b.spot.removeAnimation(forKey: "pos") }
            fade(to: 1)
            return
        }
        let lead = bands[0].spot
        let from = lead.presentation()?.position ?? lead.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for b in bands { b.spot.position = local }
        CATransaction.commit()
        let a = CABasicAnimation(keyPath: "position")
        a.fromValue = NSValue(point: from)
        a.toValue = NSValue(point: local)
        a.duration = DS3Motion.rimFollow
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        for b in bands { b.spot.add(a, forKey: "pos") }
    }

    private func fade(to value: Float) {
        let lead = bands[0].spot
        let from = lead.presentation()?.opacity ?? lead.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for b in bands { b.spot.opacity = value }
        CATransaction.commit()
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = value
        a.duration = DS3Motion.rimFade
        for b in bands { b.spot.add(a, forKey: "fade") }
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
