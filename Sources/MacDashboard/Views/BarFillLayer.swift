// Views/BarFillLayer.swift
// V2-RELAYOUT-COREANIM: the app's three tick-driven bar fills (KPI meter bars,
// process-row gauges, memory segment bar) drawn by CoreAnimation instead of by
// SwiftUI's animation engine.
//
// WHY: each of those bars re-values every ~2 s and glides over 0.45 s. Driven by
// `.animation(_:value:)`, SwiftUI re-runs its ViewGraph/AttributeGraph update for
// every display frame of that 0.45 s window — a ~40% duty cycle that measured at
// ~20-27% of Main Thread samples and up to ~47% of one core (V2-UI-RELAYOUT-COST).
// Moving the animated quantity from `.frame(width:)` to `Shape.animatableData`
// did NOT help; the cost is the per-frame SwiftUI update itself. Here the main
// thread does one commit per tick and CoreAnimation interpolates the rest.
//
// NEVER attach `.animation(_:value:)` to a `BarFillLayer` — that would put the
// SwiftUI animation engine back on top of the CA animation and re-create the bug.

import AppKit
import SwiftUI

// MARK: - Value types

/// One animated span of a bar fill.
struct BarSpan: Equatable {
    /// Stable identity across ticks — one `CALayer` per key, so a span keeps its
    /// in-flight animation when its value changes.
    var key: String

    /// Share of the bar's available width. `.single` clamps it to 0...1;
    /// `.segments` does not (a segment clamped up to `minWidth` pushes its
    /// successors right and the row may overflow, exactly as the old HStack did).
    var fraction: CGFloat

    /// Multiplied into the fill colour's own alpha — this is SwiftUI's
    /// `.opacity()` on a `Color` (the process gauge's 0.22 / 0.18). Animates on
    /// the BAR curve, together with the colour it belongs to.
    var alpha: Double = 1

    /// Base fill colour. May be appearance-dynamic (`Color(light:dark:)` in
    /// Theme.swift); it is resolved against the view's effective appearance and
    /// re-resolved when that appearance changes.
    var color: Color

    /// Layer opacity — the memory card's hover dimming (1 or 0.45). Animates on
    /// the DIM curve, not the bar curve.
    var dim: Double = 1
}

enum BarFillLayout: Equatable {
    /// One leading-anchored span. `minWidth` is a point floor applied once the bar
    /// has any width; `cornerRadius == nil` ⇒ capsule (height / 2).
    case single(minWidth: CGFloat, cornerRadius: CGFloat?)
    /// N spans left to right, `gap` pt apart, each at least `minWidth` pt wide.
    case segments(gap: CGFloat, minWidth: CGFloat, cornerRadius: CGFloat)
}

/// Rects, in points, for `spans` inside a bar `width` pt wide. Single source of
/// truth for bar geometry: `BarFillLayerView` draws these, and `MemoryCard` builds
/// its per-segment hover hit regions from the same call, so drawn and hit-tested
/// rects cannot drift apart AT REST. During a transition they can — the CALayers
/// interpolate towards these rects over `barDuration` (0.45 s) while the hit regions
/// jump to them on the tick the values change, so the hover boundaries lead the drawn
/// ones by a few points until the animation lands (V2-RELEASE re-review [N6],
/// accepted: segment boundaries move only a few pt per tick).
func barSpanRects(_ spans: [BarSpan], layout: BarFillLayout, width: CGFloat) -> [(x: CGFloat, width: CGFloat)] {
    guard width > 0, !spans.isEmpty else { return spans.map { _ in (x: 0, width: 0) } }
    switch layout {
    case let .single(minWidth, _):
        return spans.map { span in
            (x: 0, width: max(minWidth, width * max(0, min(span.fraction, 1))))
        }
    case let .segments(gap, minWidth, _):
        let avail = max(0, width - gap * CGFloat(spans.count - 1))
        var out: [(x: CGFloat, width: CGFloat)] = []
        var x: CGFloat = 0
        for span in spans {
            let w = max(minWidth, avail * span.fraction)
            out.append((x: x, width: w))
            x += w + gap
        }
        return out
    }
}

private func barCornerRadius(_ layout: BarFillLayout, width: CGFloat, height: CGFloat) -> CGFloat {
    let requested: CGFloat
    switch layout {
    case let .single(_, r): requested = r ?? height / 2
    case let .segments(_, _, r): requested = r
    }
    return max(0, min(requested, min(width, height) / 2))
}

// MARK: - SwiftUI face

struct BarFillLayer: NSViewRepresentable {
    var spans: [BarSpan]
    var layout: BarFillLayout
    /// `false` ⇒ every change applies instantly (Reduce Motion, or a `MeterBar`
    /// call site that never opted into the animation).
    var animated: Bool

    func makeNSView(context: Context) -> BarFillLayerView {
        let view = BarFillLayerView()
        view.apply(spans: spans, layout: layout, animated: false)
        return view
    }

    func updateNSView(_ nsView: BarFillLayerView, context: Context) {
        nsView.apply(spans: spans, layout: layout, animated: animated)
    }

    /// The fill has no intrinsic size — it takes whatever the parent offers, like
    /// the `Shape` it replaces. Every call site wraps it in
    /// `.frame(maxWidth: .infinity, maxHeight: .infinity)`, so the proposal is
    /// always concrete here; the guard only keeps an ideal-size probe sane.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BarFillLayerView, context: Context) -> CGSize? {
        func finite(_ v: CGFloat?) -> CGFloat {
            guard let v, v.isFinite else { return 0 }
            return v
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }
}

// MARK: - The CALayer host

final class BarFillLayerView: NSView {
    /// The app-wide bar curve, `cubic-bezier(0.22, 0.61, 0.36, 1)`, shortened to
    /// 0.45 s (V2-RELAYOUT-RESIDUAL, CPU cost is ~linear in duration) — kept in
    /// sync with `processRowMotion` in `ProcessCards.swift`.
    private static let barCurve = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
    private static let barDuration: CFTimeInterval = 0.45
    /// The memory card's hover dim, matching `.easeOut(duration: 0.12)`.
    private static let dimCurve = CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)
    private static let dimDuration: CFTimeInterval = 0.12

    /// Last values pushed to each layer, for diffing. Deliberately stores the
    /// INPUTS (SwiftUI `Color` + alpha + appearance name) rather than the resolved
    /// `CGColor`, so no `CGColor` equality is needed anywhere.
    private struct Applied {
        var rect: CGRect
        var radius: CGFloat
        var color: Color
        var alpha: Double
        var appearance: NSAppearance.Name
        var dim: Float
    }

    private var spans: [BarSpan] = []
    // Named `barLayout`, not `layout`: a stored property named `layout` collides
    // with NSView's own `override func layout()` at the Objective-C selector
    // level and fails to compile ("invalid redeclaration of 'layout()'").
    private var barLayout: BarFillLayout = .single(minWidth: 0, cornerRadius: nil)
    private var sublayers: [String: CALayer] = [:]
    private var applied: [String: Applied] = [:]
    private var hasApplied = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false   // the memory bar may overflow, as it does today
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The fill is decoration. It must never take a click from the process row's
    /// tap gesture, nor a hover from the memory card's SwiftUI hit-region overlay —
    /// AppKit hit-tests real subviews before SwiftUI sees the event.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        // A bounds change (window resize) re-places the fill INSTANTLY — the old
        // Shape behaved the same way, because its draw rect was never animatable
        // data. The per-property diff below no-ops if nothing actually moved, so a
        // spurious layout pass cannot cancel an in-flight animation.
        applyNow(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyNow(animated: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        for sub in sublayers.values { sub.contentsScale = scale }
    }

    func apply(spans newSpans: [BarSpan], layout newLayout: BarFillLayout, animated: Bool) {
        spans = newSpans
        barLayout = newLayout
        // The very first application is never animated: a fresh mount / ForEach
        // reorder must not glide 0 -> real width (V2-FIX-BARFLY).
        applyNow(animated: animated && hasApplied)
    }

    private func applyNow(animated: Bool) {
        guard let host = layer else { return }
        let height = max(0, bounds.height)
        let rects = barSpanRects(spans, layout: barLayout, width: bounds.width)
        let appearanceName = effectiveAppearance.name
        var live = Set<String>()

        for (i, span) in spans.enumerated() {
            live.insert(span.key)
            let sub = sublayer(for: span.key, in: host)
            let w = max(0, rects[i].width)
            let target = Applied(
                rect: CGRect(x: rects[i].x, y: 0, width: w, height: height),
                radius: barCornerRadius(barLayout, width: w, height: height),
                color: span.color,
                alpha: span.alpha,
                appearance: appearanceName,
                dim: Float(span.dim)
            )
            let prev = applied[span.key]
            applied[span.key] = target

            if prev?.rect != target.rect {
                let fromBounds = sub.presentation()?.bounds ?? sub.bounds
                let fromPosition = sub.presentation()?.position ?? sub.position
                sub.bounds = CGRect(origin: .zero, size: target.rect.size)
                sub.position = CGPoint(x: target.rect.minX, y: target.rect.minY)
                animate(sub, "bounds", from: NSValue(rect: fromBounds),
                        to: NSValue(rect: sub.bounds), curve: Self.barCurve,
                        duration: Self.barDuration, animated: animated)
                animate(sub, "position", from: NSValue(point: fromPosition),
                        to: NSValue(point: sub.position), curve: Self.barCurve,
                        duration: Self.barDuration, animated: animated)
            }
            if prev?.radius != target.radius {
                let from = sub.presentation()?.cornerRadius ?? sub.cornerRadius
                sub.cornerRadius = target.radius
                animate(sub, "cornerRadius", from: from, to: target.radius,
                        curve: Self.barCurve, duration: Self.barDuration, animated: animated)
            }
            if prev?.color != target.color || prev?.alpha != target.alpha || prev?.appearance != target.appearance {
                let from = sub.presentation()?.backgroundColor ?? sub.backgroundColor
                sub.backgroundColor = resolvedColor(span.color, alpha: span.alpha)
                animate(sub, "backgroundColor", from: from, to: sub.backgroundColor,
                        curve: Self.barCurve, duration: Self.barDuration, animated: animated)
            }
            if prev?.dim != target.dim {
                let from = sub.presentation()?.opacity ?? sub.opacity
                sub.opacity = target.dim
                animate(sub, "opacity", from: from, to: target.dim,
                        curve: Self.dimCurve, duration: Self.dimDuration, animated: animated)
            }
        }

        for (key, sub) in sublayers where !live.contains(key) {
            sub.removeFromSuperlayer()
            sublayers[key] = nil
            applied[key] = nil
        }

        // z-order = span order, matching the old ZStack (later segments on top).
        // Only reassigned when it actually differs, so running animations survive.
        let ordered = spans.compactMap { sublayers[$0.key] }
        if (host.sublayers ?? []).map(ObjectIdentifier.init) != ordered.map(ObjectIdentifier.init) {
            host.sublayers = ordered
        }

        hasApplied = true
    }

    private func sublayer(for key: String, in host: CALayer) -> CALayer {
        if let existing = sublayers[key] { return existing }
        let sub = CALayer()
        sub.anchorPoint = .zero
        sub.contentsScale = window?.backingScaleFactor ?? 2
        // No implicit animations, ever. Every transition in this view is an
        // explicit CABasicAnimation with the app's own curve; CA's default 0.25 s
        // implicit action would be visibly wrong.
        sub.actions = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull(),
                       "backgroundColor": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
                       "contents": NSNull(), "sublayers": NSNull()]
        host.addSublayer(sub)
        sublayers[key] = sub
        return sub
    }

    private func animate(_ layer: CALayer, _ keyPath: String, from: Any?, to: Any?,
                         curve: CAMediaTimingFunction, duration: CFTimeInterval, animated: Bool) {
        guard animated else {
            layer.removeAnimation(forKey: keyPath)
            return
        }
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.timingFunction = curve
        layer.add(a, forKey: keyPath)
    }

    /// Resolves an appearance-dynamic SwiftUI `Color` (see `Color(light:dark:)` in
    /// Theme.swift, which wraps an `NSColor(name:dynamicProvider:)`) against THIS
    /// view's effective appearance, then multiplies in `alpha` the way SwiftUI's
    /// `.opacity()` does.
    private func resolvedColor(_ color: Color, alpha: Double) -> CGColor {
        var out = CGColor(gray: 0, alpha: 0)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = NSColor(color)
            let srgb = base.usingColorSpace(.sRGB) ?? base
            out = srgb.withAlphaComponent(srgb.alphaComponent * CGFloat(alpha)).cgColor
        }
        return out
    }
}

// Vertical orientation needs no `isFlipped` handling: every span spans the full bar
// height, so with `anchorPoint = .zero`, `position.y = 0` and `bounds.height = view
// height` the layer covers the same pixels in either coordinate convention.
