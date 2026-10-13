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

struct DS3OrbLayer: NSViewRepresentable {
    let animated: Bool

    func makeNSView(context: Context) -> DS3OrbView {
        let v = DS3OrbView()
        v.setAnimated(animated)
        return v
    }

    func updateNSView(_ nsView: DS3OrbView, context: Context) {
        nsView.setAnimated(animated)
    }

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

    private struct Orb {
        let color: Color
        let d: CGFloat
        let dx: CGFloat
        let dy: CGFloat
        let s: CGFloat
        let period: Double
        let centre: (CGSize) -> CGPoint
    }

    private static let orbs: [Orb] = [
        Orb(color: DS3.orbA, d: 640, dx: -60, dy: 50, s: 1.08, period: 26, centre: { CGPoint(x: $0.width - 180, y: 100) }),
        Orb(color: DS3.orbB, d: 560, dx: 70, dy: -40, s: 0.94, period: 34, centre: { _ in CGPoint(x: 40, y: 640) }),
        Orb(color: DS3.orbC, d: 520, dx: -40, dy: 60, s: 1.10, period: 42, centre: { CGPoint(x: $0.width * 0.82 - 260, y: $0.height) }),
    ]

    private let container = CALayer()
    private let orbLayers: [CALayer] = (0..<3).map { _ in CALayer() }
    private var animated = false
    private var renderedAppearance: NSAppearance.Name?
    private var renderedScale: CGFloat?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let off = NSNull()
        let keys = ["bounds", "position", "frame", "transform", "path", "contents", "hidden"]
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
        for (l, o) in zip(orbLayers, Self.orbs) {
            l.bounds = CGRect(x: 0, y: 0, width: o.d, height: o.d)
            l.position = o.centre(bounds.size)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderImagesIfNeeded()
        updateAnimations()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderImagesIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderImagesIfNeeded()
    }

    /// Radial images at the window's backing scale, with colours resolved for this view's appearance.
    private func renderImagesIfNeeded() {
        guard let window else { return }
        let scale = window.backingScaleFactor
        let name = effectiveAppearance.name
        guard name != renderedAppearance || scale != renderedScale else { return }
        renderedAppearance = name
        renderedScale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (l, o) in zip(orbLayers, Self.orbs) {
            let c = Color(cgColor: ds3Resolve(o.color, in: effectiveAppearance))
            let renderer = ImageRenderer(
                content: Circle()
                    .fill(RadialGradient(colors: [c, c.opacity(0)], center: .center, startRadius: 0, endRadius: 0.495 * o.d))
                    .frame(width: o.d, height: o.d)
            )
            renderer.scale = scale
            l.contents = renderer.cgImage
            l.contentsScale = scale
        }
        CATransaction.commit()
    }

    func setAnimated(_ a: Bool) {
        animated = a
        updateAnimations()
    }

    private func updateAnimations() {
        for (l, o) in zip(orbLayers, Self.orbs) {
            if animated && window != nil {
                if l.animation(forKey: "drift") == nil { l.add(drift(o), forKey: "drift") }
            } else {
                l.removeAnimation(forKey: "drift")
            }
        }
    }

    /// Today's cosine easing, k = (1 - cos(2 pi t / P)) / 2, sampled at 121 points per period.
    private func drift(_ o: Orb) -> CAKeyframeAnimation {
        let n = 120
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = (0...n).map { i -> NSValue in
            let k = (1 - cos(2 * Double.pi * Double(i) / Double(n))) / 2
            let sc = 1 + (o.s - 1) * CGFloat(k)
            let t = CATransform3DConcat(
                CATransform3DMakeScale(sc, sc, 1),
                CATransform3DMakeTranslation(o.dx * CGFloat(k), o.dy * CGFloat(k), 0))
            return NSValue(caTransform3D: t)
        }
        a.calculationMode = .linear
        a.duration = o.period
        a.repeatCount = .infinity
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: Float(1 / DS3Motion.orbTick))
        return a
    }
}
