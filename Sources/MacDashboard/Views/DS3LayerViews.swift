// Views/DS3LayerViews.swift
// IPHONE-SCROLL-LAG: Core Animation hosts for the DS3 pointer rim and orbs. Content is rendered once; motion is layer animation evaluated by the render server.

import SwiftUI
import AppKit
import QuartzCore

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

/// The rim gradient, rendered once per process for the dark appearance: `hi` at the top (resting direction 0).
/// A conic gradient's colour depends only on the angle from the centre, so one square image serves every card
/// at any size, and rotating it about the card centre equals moving the gradient's start angle.
@MainActor
enum DS3RimImage {
    static let side: CGFloat = 1024

    static let conic: CGImage? = {
        let dark = NSAppearance(named: .darkAqua)!
        let hi = ds3Resolve(DS3.rimHi, in: dark)
        let mid = ds3Resolve(DS3.rimMid, in: dark)
        let lo = ds3Resolve(DS3.rimLo, in: dark)
        let renderer = ImageRenderer(
            content: Rectangle()
                .fill(AngularGradient(
                    stops: DS3.rimStops(hi: Color(cgColor: hi), mid: Color(cgColor: mid), lo: Color(cgColor: lo)),
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)))
                .frame(width: side, height: side)
        )
        renderer.scale = 1
        return renderer.cgImage
    }()
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

final class DS3RimView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var cornerRadius: CGFloat {
        didSet { if cornerRadius != oldValue { needsLayout = true } }
    }
    private(set) var isStatic = false
    /// Model angle in CSS degrees, unbounded; advanced only by `RimAngle.continuing`.
    private var angle = RimAngle.resting

    private let ring = CALayer()
    private let ringMask = CAShapeLayer()
    private let conic = CALayer()

    /// In flipped geometry a positive z rotation is clockwise on screen (orientation table in the spec).
    private static let rotationSign: Double = 1

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let off = NSNull()
        let keys = ["bounds", "position", "frame", "transform", "path", "contents", "hidden"]
        for l in [ring, ringMask, conic] as [CALayer] {
            l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
        }
        ringMask.fillColor = CGColor(gray: 0, alpha: 1)
        ring.mask = ringMask
        conic.contents = DS3RimImage.conic
        conic.contentsGravity = .resize
        ring.addSublayer(conic)
        layer?.addSublayer(ring)
        setRotation(angle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ringMask.frame = ring.bounds
        ringMask.path = Self.ringPath(bounds.size, cornerRadius)
        let d = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot().rounded(.up) + 2
        conic.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        conic.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? 2
        ring.contentsScale = s
        ringMask.contentsScale = s
    }

    /// The 1.2 pt `strokeBorder` outline of the continuous rounded rectangle, as a fillable path.
    static func ringPath(_ size: CGSize, _ r: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .inset(by: 0.6)
            .path(in: CGRect(origin: .zero, size: size))
            .cgPath
            .copy(strokingWithWidth: 1.2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }

    func setStatic(_ s: Bool) {
        guard s != isStatic else { return }
        isStatic = s
        if s {
            conic.removeAllAnimations()
            angle = RimAngle.resting
            setRotation(angle)
        }
    }

    /// Retargets with an additive spring from `-delta` to 0, so position and velocity stay continuous.
    func aim(to target: Double) {
        guard !isStatic else { return }
        let next = RimAngle.continuing(from: angle, to: target)
        let delta = next - angle
        guard abs(delta) >= 0.25 else { return }
        angle = next
        setRotation(next)
        let spring = DS3Motion.rimSpring
        let a = CASpringAnimation(keyPath: "transform.rotation.z")
        a.isAdditive = true
        a.fromValue = -delta * .pi / 180 * Self.rotationSign
        a.toValue = 0.0
        a.mass = CGFloat(spring.mass)
        a.stiffness = CGFloat(spring.stiffness)
        a.damping = CGFloat(spring.damping)
        a.duration = a.settlingDuration
        conic.add(a, forKey: nil)
    }

    private func setRotation(_ deg: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        conic.setValue(deg * .pi / 180 * Self.rotationSign, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
    }
}

// MARK: - Orbs

/// One soft colour glow: colour, diameter and a centre function of the layer size.
struct DS3OrbSpec {
    let color: Color
    let d: CGFloat
    let centre: (CGSize) -> CGPoint
    var drift: OrbDrift.Params? = nil

    /// The main window's three v2 orbs (`This Mac Home v2.dc.html:33-35`): A back 780 `top -300 right -220`,
    /// B mid 580 `top 330 left -250`, C front 420 `bottom -190 right 20%`. REDESIGN-ORBS.
    static let window: [DS3OrbSpec] = [
        DS3OrbSpec(color: DS3.orbA, d: 780, centre: { OrbGeometry.centre(left: OrbGeometry.leftFromRight(-220, d: 780, width: $0.width), top: -300, d: 780) }, drift: OrbDrift.a),
        DS3OrbSpec(color: DS3.orbB, d: 580, centre: { _ in OrbGeometry.centre(left: -250, top: 330, d: 580) }, drift: OrbDrift.b),
        DS3OrbSpec(color: DS3.orbC, d: 420, centre: { OrbGeometry.centre(left: OrbGeometry.leftFromRight(0.2 * $0.width, d: 420, width: $0.width), top: OrbGeometry.topFromBottom(-190, d: 420, height: $0.height), d: 420) }, drift: OrbDrift.c),
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
    var drifting = false

    func makeNSView(context: Context) -> DS3OrbView {
        let v = DS3OrbView(orbs: orbs)
        v.setDrifting(drifting)
        return v
    }

    func updateNSView(_ nsView: DS3OrbView, context: Context) { nsView.setDrifting(drifting) }

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
    private(set) var isDrifting = false
    private var occlusionObserver: NSObjectProtocol?

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

    deinit {
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderImagesIfNeeded()
        if isDrifting { removeDriftAnimations(); addDriftAnimations() }    // re-binds the occlusion observer to the new window
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderImagesIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderImagesIfNeeded()
    }

    func setDrifting(_ on: Bool) {
        guard on != isDrifting else { return }
        isDrifting = on
        on ? addDriftAnimations() : removeDriftAnimations()
    }

    /// One additive keyframe animation per term, all started in one transaction at the same begin time so the
    /// three orbs keep the mockup's relative phases. The render server evaluates them; the app commits nothing per frame.
    private func addDriftAnimations() {
        let t0 = container.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (l, o) in zip(orbLayers, orbs) {
            guard let p = o.drift else { continue }
            for (i, term) in OrbDrift.terms(p).enumerated() {
                let a = CAKeyframeAnimation(keyPath: term.keyPath)
                a.values = OrbDrift.samples(term)
                a.calculationMode = .linear
                a.duration = term.period
                a.isAdditive = true
                a.repeatCount = .greatestFiniteMagnitude
                a.isRemovedOnCompletion = false
                a.beginTime = t0
                a.preferredFrameRateRange = CAFrameRateRange(minimum: OrbDrift.frameRate.minimum, maximum: OrbDrift.frameRate.maximum, preferred: OrbDrift.frameRate.preferred)
                l.add(a, forKey: "drift.\(i)")
            }
        }
        CATransaction.commit()
        if occlusionObserver == nil, let window {
            occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncPause() }
            }
        }
        syncPause()
    }

    private func removeDriftAnimations() {
        for l in orbLayers { for k in l.animationKeys() ?? [] where k.hasPrefix("drift.") { l.removeAnimation(forKey: k) } }
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o); occlusionObserver = nil }
        container.speed = 1; container.timeOffset = 0; container.beginTime = 0
    }

    /// Occluded or hidden window: freeze the layer clock so the render server stops producing frames (the orbs
    /// keep their last position; resume continues from it, no jump).
    private func syncPause() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        if visible, container.speed == 0 {
            let paused = container.timeOffset
            container.speed = 1; container.timeOffset = 0; container.beginTime = 0
            container.beginTime = container.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else if !visible, container.speed != 0 {
            container.timeOffset = container.convertTime(CACurrentMediaTime(), from: nil)
            container.speed = 0
        }
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
