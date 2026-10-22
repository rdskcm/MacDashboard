// Views/HomeLayers.swift
// REDESIGN-HOME (stage B): the two ambient animations of Home — the pulsing "All good" dot and the
// skeleton shimmer — as Core Animation layers. Drawn once, animated by the render server
// (rule gpu-per-frame, same layer-based approach for every ambient animation): no SwiftUI state changes per frame.

import SwiftUI
import AppKit
import QuartzCore

// MARK: - Pulse dot

/// Dot with a static halo and, behind it, a pulse ring (scale 1 → 2.6, opacity 0.55 → 0 over 1.68 s,
/// then held invisible for 1.12 s). No layer and no animation under Reduce Motion or in a frozen run.
struct HomePulseDot: View {
    let color: Color
    let size: CGFloat
    let haloWidth: CGFloat
    let haloOpacity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(haloOpacity)).frame(width: size + 2 * haloWidth, height: size + 2 * haloWidth))
            .background {
                if !(reduceMotion || DS3Motion.isFrozen) {
                    HomePulseLayer(color: color, size: size)
                        .frame(width: size, height: size)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct HomePulseLayer: NSViewRepresentable {
    let color: Color
    let size: CGFloat

    func makeNSView(context: Context) -> HomePulseLayerView {
        HomePulseLayerView(color: color, size: size)
    }

    func updateNSView(_ nsView: HomePulseLayerView, context: Context) {
        nsView.update(color: color, size: size)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HomePulseLayerView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class HomePulseLayerView: NSView {
    private let ring = CAShapeLayer()
    private var color: Color
    private var size: CGFloat

    init(color: Color, size: CGFloat) {
        self.color = color
        self.size = size
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false
        // Model state = the invisible hold phase; the animation only draws the rise.
        ring.opacity = 0
        let off = NSNull()
        ring.actions = ["bounds": off, "position": off, "frame": off, "path": off, "fillColor": off]
        layer?.addSublayer(ring)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(color: Color, size: CGFloat) {
        self.color = color
        self.size = size
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = CGRect(x: 0, y: 0, width: size, height: size)
        ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        ring.fillColor = ds3Resolve(color, in: effectiveAppearance)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startPulse() } else { ring.removeAllAnimations() }
    }

    private func startPulse() {
        ring.removeAnimation(forKey: "pulse")
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.3, 1)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = DS3Motion.pulseScale
        scale.duration = DS3Motion.pulseRise
        scale.timingFunction = timing
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = DS3Motion.pulseOpacityFrom
        fade.toValue = 0
        fade.duration = DS3Motion.pulseRise
        fade.timingFunction = timing
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = DS3Motion.pulseRise + DS3Motion.pulseHold
        group.repeatCount = .infinity
        ring.add(group, forKey: "pulse")
    }
}

// MARK: - Skeleton shimmer

/// 96 × 24 placeholder capsule with a highlight sweeping across it (replaces a tile's tag while the
/// first scan runs). Static (no highlight) under Reduce Motion or in a frozen run.
struct HomeShimmerCapsule: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule().fill(DS3.track)
            .frame(width: 96, height: 24)
            .overlay {
                if !(reduceMotion || DS3Motion.isFrozen) {
                    HomeShimmerLayer()
                        .clipShape(Capsule())
                        .allowsHitTesting(false)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct HomeShimmerLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> HomeShimmerLayerView { HomeShimmerLayerView() }
    func updateNSView(_ nsView: HomeShimmerLayerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HomeShimmerLayerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 96,
               height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 24)
    }
}

final class HomeShimmerLayerView: NSView {
    private let sweep = CAGradientLayer()
    private var laidOutWidth: CGFloat = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = true
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        let off = NSNull()
        sweep.actions = ["bounds": off, "position": off, "frame": off, "colors": off]
        layer?.addSublayer(sweep)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = bounds.width
        let highlight = ds3Resolve(DS3.rimMid, in: effectiveAppearance)
        sweep.colors = [highlight.copy(alpha: 0) ?? highlight, highlight, highlight.copy(alpha: 0) ?? highlight]
        sweep.bounds = CGRect(x: 0, y: 0, width: w * 0.4, height: bounds.height)
        sweep.position = CGPoint(x: -w * 0.2, y: bounds.height / 2)
        CATransaction.commit()
        if w != laidOutWidth, w > 0 {
            laidOutWidth = w
            if window != nil { startSweep() }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startSweep() } else { sweep.removeAllAnimations() }
    }

    /// The highlight's left edge travels from −40 % to 100 % of the capsule width (fully off to fully off).
    private func startSweep() {
        let w = bounds.width
        guard w > 0 else { return }
        sweep.removeAnimation(forKey: "sweep")
        let a = CABasicAnimation(keyPath: "position.x")
        a.fromValue = -w * 0.2
        a.toValue = w * 1.2
        a.duration = 1.2
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        a.repeatCount = .infinity
        sweep.add(a, forKey: "sweep")
    }
}
