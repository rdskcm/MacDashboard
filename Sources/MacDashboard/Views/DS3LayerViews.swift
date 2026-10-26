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

/// RIM-GLOW-OPTICS: the 1.2 pt ring of a glass card, masked; inside it the static ambient layer and the pointer light
/// sprite, both composited `plusL` (spec §3.2, §3.3, D8). Per pointer event: one `position` set and one fixed-key animation.
final class DS3RimView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var cornerRadius: CGFloat {
        didSet {
            guard cornerRadius != oldValue else { return }
            appliedMaskKey = nil
            needsLayout = true
        }
    }
    private(set) var isStatic = false

    private let ring = CALayer()
    private let ringMask = CALayer()
    private let ambient = CALayer()
    private let spot = CALayer()
    private var shadeRing: CALayer?
    private var shadeMask: CALayer?
    /// RESIZE-FRAME-COST: the (corner radius, scale) the ring masks currently show; the nine-slice sprite is stretched by the
    /// render server, so a width step sets no mask content.
    private var appliedMaskKey: MaskKey?
    private struct MaskKey: Equatable { let cornerRadius: CGFloat; let scale: CGFloat }
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
        let keys = ["bounds", "position", "frame", "transform", "path", "contents", "contentsCenter", "contentsScale",
                    "hidden", "compositingFilter", "opacity", "backgroundColor"]
        for l in [ring, ringMask, ambient, spot] as [CALayer] {
            l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
        }
        ring.mask = ringMask
        ambient.contentsGravity = .resize
        spot.contentsGravity = .resize
        spot.opacity = 0
        spot.compositingFilter = "plusL"
        ring.compositingFilter = "plusL"
        ring.addSublayer(ambient)
        ring.addSublayer(spot)
        layer?.addSublayer(ring)
        RimSettingsObserver.shared.register(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ringMask.frame = ring.bounds
        if let shadeRing, let shadeMask {
            shadeRing.frame = bounds
            shadeMask.frame = shadeRing.bounds
        }
        ambient.frame = CGRect(x: 0, y: 0, width: bounds.width, height: cornerRadius)
        let r = CGFloat(RimLight.range(h: h))
        spot.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        applyMask()
        CATransaction.commit()
        renderIfNeeded()
    }

    /// Shows the shared nine-slice ring-mask sprite on the ring masks; a no-op until the corner radius or the scale changes.
    private func applyMask() {
        guard let window else { return }
        let scale = window.backingScaleFactor
        let maskKey = MaskKey(cornerRadius: cornerRadius, scale: scale)
        guard maskKey != appliedMaskKey else { return }
        guard let img = DS3SpriteCache.shared.ringMask(cornerRadius: cornerRadius, scale: scale) else {
            if !loggedRenderFailure { NSLog("[MacDashboard] rim mask render failed; retrying on the next pass") }
            loggedRenderFailure = true
            return
        }
        let center = DS3SliceGeometry.ringMask(cornerRadius: cornerRadius).contentsCenter(fixedWidth: false, fixedHeight: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for m in [ringMask, shadeMask].compactMap({ $0 }) {
            m.contents = img
            m.contentsScale = scale
            m.contentsCenter = center
        }
        CATransaction.commit()
        appliedMaskKey = maskKey
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyMask()
        renderIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyMask()
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
            ring.isHidden = true
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
            if !loggedRenderFailure { NSLog("[MacDashboard] rim bitmap render failed; keeping the previous contents, retrying on the next pass") }
            loggedRenderFailure = true
        } else {
            renderedKey = key
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.isHidden = false
        if shaded {
            if shadeRing == nil, let host = layer {
                let sr = CALayer()
                let sm = CALayer()
                let off = NSNull()
                let keys = ["bounds", "position", "frame", "path", "contents", "contentsCenter", "contentsScale", "hidden",
                            "backgroundColor"]
                for l in [sr, sm] as [CALayer] { l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) }) }
                sr.mask = sm
                host.insertSublayer(sr, below: ring)
                shadeRing = sr
                shadeMask = sm
                appliedMaskKey = nil
                applyMask()
                needsLayout = true
            }
            shadeRing?.isHidden = false
            shadeRing?.backgroundColor = ds3Resolve(DS3.rimShade, in: effectiveAppearance)
        } else {
            shadeRing?.isHidden = true
        }
        if let sprite { spot.contents = sprite }
        if let amb { ambient.contents = amb }
        spot.contentsScale = scale
        ambient.contentsScale = scale
        CATransaction.commit()
    }

    func setStatic(_ s: Bool) {
        guard s != isStatic else { return }
        isStatic = s
        if s {
            spot.removeAllAnimations()
            spotVisible = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spot.opacity = 0
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
            spot.position = local
            CATransaction.commit()
            spot.removeAnimation(forKey: "pos")
            fade(to: 1)
            return
        }
        let from = spot.presentation()?.position ?? spot.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spot.position = local
        CATransaction.commit()
        let a = CABasicAnimation(keyPath: "position")
        a.fromValue = NSValue(point: from)
        a.toValue = NSValue(point: local)
        a.duration = DS3Motion.rimFollow
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        spot.add(a, forKey: "pos")
    }

    private func fade(to value: Float) {
        let from = spot.presentation()?.opacity ?? spot.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spot.opacity = value
        CATransaction.commit()
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = value
        a.duration = DS3Motion.rimFade
        spot.add(a, forKey: "fade")
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
struct DS3OrbSpec {
    let color: Color
    let d: CGFloat
    let centre: (CGSize) -> CGPoint

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
            if !loggedRenderFailure { NSLog("[MacDashboard] orb bitmap render failed; keeping the previous contents, retrying on the next pass") }
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
