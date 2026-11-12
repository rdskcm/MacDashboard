// Views/HomeLayers.swift
// REDESIGN-HOME (stage B): Home's skeleton shimmer as a Core Animation layer. Drawn once, animated by the render
// server (rule gpu-per-frame): no SwiftUI state changes per frame. The «All good» dot is static (PULSE-COST).

import SwiftUI
import AppKit
import QuartzCore

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
