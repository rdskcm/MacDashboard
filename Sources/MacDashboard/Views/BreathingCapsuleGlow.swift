// Views/BreathingCapsuleGlow.swift
// GPU-RENDER-AUDIT C1: the amber "breathing" ring + glow, drawn once and pulsed by a Core Animation
// opacity animation the render server runs — no SwiftUI state changes per frame (rule gpu-per-frame).

import SwiftUI
import AppKit
import QuartzCore

/// Amber capsule outline + glow at the BRIGHT state (outline 1.0, glow 0.6), drawn once; the breath is
/// layer opacity 0.5 ↔ 1.0, 2 s per leg, 5 legs (= `DSMotion.breathing`), ending bright; the constants
/// reproduce the old `easeInOut(2).repeatCount(5, autoreverses: true)`.
/// `paused == true` settles to the dim state (0.5) in 0.2 s; `false` again restarts the breath.
struct BreathingCapsuleGlow: NSViewRepresentable {
    let lineWidth: CGFloat
    let paused: Bool

    func makeNSView(context: Context) -> BreathingCapsuleGlowView {
        let v = BreathingCapsuleGlowView(lineWidth: lineWidth)
        v.setPaused(paused)
        return v
    }

    func updateNSView(_ nsView: BreathingCapsuleGlowView, context: Context) {
        nsView.lineWidth = lineWidth
        nsView.setPaused(paused)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BreathingCapsuleGlowView, context: Context) -> CGSize? {
        func finite(_ v: CGFloat?) -> CGFloat {
            guard let v, v.isFinite else { return 0 }
            return v
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }
}

final class BreathingCapsuleGlowView: NSView {
    /// Room for the 6 pt SwiftUI shadow on every side (3 × radius).
    private static let pad: CGFloat = 18
    private static let dim: Float = 0.5

    var lineWidth: CGFloat {
        didSet { if lineWidth != oldValue { needsLayout = true } }
    }
    private let glow = CALayer()
    private var renderedKey = ""
    private var paused = false

    init(lineWidth: CGFloat) {
        self.lineWidth = lineWidth
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false
        let off = NSNull()
        glow.actions = ["bounds": off, "position": off, "frame": off, "contents": off, "opacity": off]
        glow.opacity = Self.dim
        layer?.addSublayer(glow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        let key = "\(bounds.size.width)x\(bounds.size.height)|\(lineWidth)|\(effectiveAppearance.name.rawValue)|\(scale)"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = bounds.insetBy(dx: -Self.pad, dy: -Self.pad)
        if key != renderedKey, bounds.width > 0, bounds.height > 0 {
            renderedKey = key
            glow.contents = render(scale: scale)
            glow.contentsScale = scale
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    /// Mirrors SwiftUI `.onAppear`: (re)attaching to a window starts a breath unless paused.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, !paused { startBreath() }
    }

    func setPaused(_ p: Bool) {
        guard p != paused else { return }
        paused = p
        if p { settleDim() } else if window != nil { startBreath() }
    }

    private func render(scale: CGFloat) -> CGImage? {
        let amber = Color(cgColor: ds3Resolve(DS.amber, in: effectiveAppearance))
        let renderer = ImageRenderer(content:
            Capsule()
                .strokeBorder(amber, lineWidth: lineWidth)
                .shadow(color: amber.opacity(0.6), radius: 6)
                .frame(width: bounds.width, height: bounds.height)
                .padding(Self.pad))
        renderer.scale = scale
        return renderer.cgImage
    }

    private func startBreath() {
        glow.removeAnimation(forKey: "settle")
        glow.opacity = 1   // model = final bright state
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = Self.dim
        a.toValue = 1.0
        a.duration = 2
        a.autoreverses = true
        a.repeatCount = 2.5
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(a, forKey: "breath")
    }

    private func settleDim() {
        let from = glow.presentation()?.opacity ?? glow.opacity
        glow.removeAnimation(forKey: "breath")
        glow.opacity = Self.dim
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = Self.dim
        a.duration = 0.2
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(a, forKey: "settle")
    }
}
