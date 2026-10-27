// Views/DS3Spinner.swift
// DS3-SPINNER: the redesign mockups' spinner (`@keyframes tmspin`, 0.8 s linear) on Core Animation. The ring is two
// CAShapeLayer arcs set once per size; the motion is a `transform.rotation.z` animation the render server runs
// (`gpu-per-frame`). Mount it only while busy (`dsSwapInPlace` overlay or an `if busy`), never at opacity 0.

import SwiftUI
import AppKit
import QuartzCore

/// Colour roles transcribed from the mockups (spec table, DS3-SPINNER §2.1). `rest` is the 270° arc, `head` the 90° arc
/// centred on 12 o'clock at rotation 0; `head == nil` is the gap ring (CSS `border-top-color: transparent`).
enum DS3SpinnerRole: Equatable {
    case onSolid, onSolidRing, track, tinted, accentRing, accentInkRing, softRing, mutedRing

    var rest: Color {
        switch self {
        case .onSolid: return Color.white.opacity(0.35)
        case .onSolidRing: return .white
        case .track: return DS3.lineStrong
        case .tinted: return DS3.accent.opacity(0.30)
        case .accentRing: return DS3.accent
        case .accentInkRing: return DS3.accentInk
        case .softRing: return DS3.inkSoft
        case .mutedRing: return DS3.muted
        }
    }

    var head: Color? {
        switch self {
        case .onSolid: return .white
        case .track, .tinted: return DS3.accent
        case .onSolidRing, .accentRing, .accentInkRing, .softRing, .mutedRing: return nil
        }
    }
}

/// The app's one activity spinner. Fixed `size × size` frame, so swapping it in never changes a layout.
struct DS3Spinner: View {
    let role: DS3SpinnerRole
    let size: CGFloat
    /// VoiceOver label; nil reads `L.commonInProgress`.
    var accessibilityLabel: String? = nil

    /// D1 (provisional, DS3-SPINNER): the mockups keep spinners turning under Reduce Motion.
    static let stopsUnderReduceMotion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DS3SpinnerLayer(role: role, size: size,
                        spins: !DS3Motion.isFrozen && !(reduceMotion && Self.stopsUnderReduceMotion),
                        label: accessibilityLabel ?? L.commonInProgress)
            .frame(width: size, height: size)
    }
}

extension View {
    /// Busy state for VoiceOver on a button whose label swaps for a `DS3Spinner`.
    func ds3BusyValue(_ busy: Bool) -> some View {
        accessibilityValue(busy ? L.commonInProgress : "")
    }
}

struct DS3SpinnerLayer: NSViewRepresentable {
    let role: DS3SpinnerRole
    let size: CGFloat
    let spins: Bool
    let label: String

    func makeNSView(context: Context) -> DS3SpinnerView {
        let v = DS3SpinnerView()
        v.configure(role: role, size: size, spins: spins, label: label)
        return v
    }

    func updateNSView(_ nsView: DS3SpinnerView, context: Context) {
        nsView.configure(role: role, size: size, spins: spins, label: label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DS3SpinnerView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class DS3SpinnerView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private let rotor = CALayer()
    private let rest = CAShapeLayer()
    private let head = CAShapeLayer()
    private var role: DS3SpinnerRole = .track
    private var size: CGFloat = 13
    private var spins = false
    private var label = ""
    private var pathSize: CGFloat?

    /// In flipped geometry a positive z rotation is clockwise on screen (unverified until the live check L3); CSS
    /// `rotate(360deg)` is clockwise.
    private static let rotationSign: Double = 1
    static let period: Double = 0.8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let off = NSNull()
        let keys = ["bounds", "position", "frame", "transform", "path", "strokeColor", "hidden", "contentsScale"]
        for l in [rotor, rest, head] as [CALayer] {
            l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
        }
        for s in [rest, head] {
            s.fillColor = nil
            s.lineWidth = 2
            s.lineCap = .butt
            rotor.addSublayer(s)
        }
        layer?.addSublayer(rotor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(role: DS3SpinnerRole, size: CGFloat, spins: Bool, label: String) {
        self.label = label
        if self.role != role { self.role = role; resolveColors() }
        if self.size != size { self.size = size; needsLayout = true }
        if self.spins != spins { self.spins = spins; updateSpin() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rotor.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        rotor.position = CGPoint(x: bounds.midX, y: bounds.midY)
        rest.frame = rotor.bounds
        head.frame = rotor.bounds
        if pathSize != size {
            pathSize = size
            let c = CGPoint(x: size / 2, y: size / 2), r = size / 2 - 1
            // y-down: −π/2 is 12 o'clock. Head 10:30 → 1:30, rest 1:30 → 10:30 through 6 o'clock.
            let h = CGMutablePath()
            h.addArc(center: c, radius: r, startAngle: -.pi * 3 / 4, endAngle: -.pi / 4, clockwise: false)
            let t = CGMutablePath()
            t.addArc(center: c, radius: r, startAngle: -.pi / 4, endAngle: .pi * 5 / 4, clockwise: false)
            head.path = h
            rest.path = t
        }
        CATransaction.commit()
        resolveColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColors()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? 2   // offscreen snapshots have no window and render at 2x
        for l in [rotor, rest, head] as [CALayer] { l.contentsScale = s }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewDidChangeBackingProperties()
        updateSpin()
    }

    /// Resolves the role's colours for this view's appearance (offscreen too: no window guard).
    private func resolveColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rest.strokeColor = ds3Resolve(role.rest, in: effectiveAppearance)
        if let h = role.head {
            head.strokeColor = ds3Resolve(h, in: effectiveAppearance)
            head.isHidden = false
        } else {
            head.isHidden = true
        }
        CATransaction.commit()
    }

    /// Spins only while `spins` and in a window; re-run on every change of either.
    private func updateSpin() {
        rotor.removeAnimation(forKey: "spin")
        guard spins, window != nil else { return }
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = 2 * Double.pi * Self.rotationSign
        a.duration = Self.period
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        // 7.5° per frame at 60 Hz is smooth for a 12–20 pt ring; the cap halves WindowServer work on 120 Hz panels.
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        rotor.add(a, forKey: "spin")
    }

    // VoiceOver: a busy indicator, as the system `ProgressView` was.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .busyIndicator }
    override func accessibilityLabel() -> String? { label }
}
