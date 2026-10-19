// Views/DS3Surfaces.swift
// IPHONE-DESIGN: DS v3 surfaces (hand-drawn shadows, inset rims, glass card, pointer-following rim,
// static orbs, entrance motion). Used by iPhone mode; APP-REDESIGN will reuse them later.

import SwiftUI
import AppKit

// MARK: - Pointer tracker

/// The pointer position in `DS3.windowSpace`, written by one `.onContinuousHover` on the window root
/// (`ds3PointerTracking`). It is deliberately not observable (D6): rims register with it and are re-aimed
/// imperatively, so no SwiftUI body reads the pointer. Re-aims are gated while any scroll event stream is
/// active and happen once, 0.15 s after the last scroll event.
@MainActor
final class DS3PointerTracker {
    /// Window-space pointer location, nil outside the window.
    private(set) var location: CGPoint?

    private var rims: [ObjectIdentifier: DS3RimModel] = [:]
    private var isScrolling = false
    private var scrollEnd: DispatchWorkItem?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            self?.scrolled()
            return e
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        scrollEnd?.cancel()
    }

    func register(_ m: DS3RimModel) { rims[ObjectIdentifier(m)] = m }
    func unregister(_ m: DS3RimModel) { rims[ObjectIdentifier(m)] = nil }

    /// Reports the pointer; re-aims only when the location actually changed (D7) and no scroll is in flight.
    func pointer(_ p: CGPoint?) {
        guard p != location else { return }
        location = p
        guard !isScrolling else { return }
        aimAll()
    }

    private func scrolled() {
        isScrolling = true
        scrollEnd?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scrollEnded() }
        scrollEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DS3Motion.rimScrollSettle, execute: work)
    }

    private func scrollEnded() {
        isScrolling = false
        scrollEnd = nil
        aimAll()
    }

    private func aimAll() {
        for m in rims.values { m.aim(at: location) }
    }
}

/// One rim's window-space frame and its layer view; the tracker calls `aim(at:)` directly.
@MainActor
final class DS3RimModel {
    var rect = CGRect.zero
    weak var view: DS3RimView?

    func aim(at p: CGPoint?) {
        guard let view else { return }
        let target = p.map { RimAngle.target(pointer: $0, center: CGPoint(x: rect.midX, y: rect.midY)) } ?? RimAngle.resting
        view.aim(to: target)
    }
}

private struct DS3PointerTrackerKey: EnvironmentKey {
    static let defaultValue: DS3PointerTracker? = nil
}

extension EnvironmentValues {
    var ds3PointerTracker: DS3PointerTracker? {
        get { self[DS3PointerTrackerKey.self] }
        set { self[DS3PointerTrackerKey.self] = newValue }
    }
}

// MARK: - View modifiers

extension View {
    /// Hand-drawn layered shadow (D5): each layer is a blurred copy of `shape` inset by the CSS spread,
    /// and the shape itself is punched out so nothing shows through a translucent fill.
    func ds3Elevation<S: InsettableShape>(_ s: DS3Shadow, in shape: S) -> some View {
        let layers = s.layers
        return background {
            ZStack {
                ForEach(Array(layers.enumerated()), id: \.offset) { _, l in
                    shape.inset(by: l.inset).fill(l.color).blur(radius: l.radius).offset(y: l.y)
                }
                shape.fill(Color.black).blendMode(.destinationOut)
            }
            .compositingGroup()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// CSS `inset 0 1px 0 X` is `top: X`; `inset 0 0 0 .5px X` is `ring: X`; `inset 0 0 0 1px X` is `ring: X, ringWidth: 1`.
    func ds3InsetRims<S: InsettableShape>(_ shape: S, top: Color? = nil, ring: Color? = nil, ringWidth: CGFloat = 0.5) -> some View {
        overlay {
            if let ring {
                shape.strokeBorder(ring, lineWidth: ringWidth).allowsHitTesting(false)
            }
        }
        .overlay {
            if let top {
                // Top-edge-only highlight, same technique as `DSCardSurface`.
                shape.strokeBorder(
                    LinearGradient(
                        stops: [.init(color: top, location: 0), .init(color: .clear, location: 0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
        }
    }

    /// Quiet inner panel: `DS3.row` fill with a 1 pt `DS3.line` ring.
    func ds3RowPanel(cornerRadius r: CGFloat) -> some View {
        background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(DS3.row))
            .ds3InsetRims(RoundedRectangle(cornerRadius: r, style: .continuous), ring: DS3.line, ringWidth: 1)
    }

    /// Tinted panel: vertical `tone` gradient a -> b, optional 0.5 pt ring in `tone` and top highlight.
    /// For capsules pass `cornerRadius: 999`.
    func ds3TintPanel(_ tone: Color, from a: Double, to b: Double, ring: Double?, cornerRadius r: CGFloat, top: Color? = nil) -> some View {
        background(
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(
                LinearGradient(colors: [tone.opacity(a), tone.opacity(b)], startPoint: .top, endPoint: .bottom)
            )
        )
        .ds3InsetRims(RoundedRectangle(cornerRadius: r, style: .continuous), top: top, ring: ring.map { tone.opacity($0) })
    }

    /// Glass card: material + `glassStrong` tint, pointer rim, card shadow (D4). No `.clipped()` on ancestors:
    /// the shadow bleeds 36 pt below and about 18 pt sideways.
    /// The fill follows the system Liquid Glass slider and Reduce Transparency through GlassSettings (CARD-GLASS-BACKDROP).
    func ds3GlassCard(cornerRadius r: CGFloat) -> some View {
        modifier(DS3GlassCard(cornerRadius: r))
    }

    /// One `.onContinuousHover` on the window root feeds the tracker; rims reach it through the environment.
    /// The tracker also owns the app-local scroll monitor, started and stopped with this view.
    func ds3PointerTracking(_ t: DS3PointerTracker) -> some View {
        coordinateSpace(.named(DS3.windowSpace))
            .onContinuousHover(coordinateSpace: .named(DS3.windowSpace)) { phase in
                switch phase {
                case .active(let p): t.pointer(p)
                case .ended: t.pointer(nil)
                }
            }
            .environment(\.ds3PointerTracker, t)
            .onAppear { t.start() }
            .onDisappear { t.stop() }
    }

    /// State-driven entrance (D23): a transition would not fire for content present at first render.
    func ds3Appear(
        delay: Double = 0,
        offset: CGSize = CGSize(width: 0, height: DS3Motion.appearOffsetY),
        scale: CGFloat = DS3Motion.appearScale,
        animation: Animation = DS3Motion.appear
    ) -> some View {
        modifier(DS3Appear(delay: delay, offset: offset, scale: scale, animation: animation))
    }
}

private struct DS3Appear: ViewModifier {
    let delay: Double
    let offset: CGSize
    let scale: CGFloat
    let animation: Animation
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : scale)
            .offset(shown ? .zero : offset)
            .onAppear {
                if reduceMotion || DS3Motion.isFrozen {
                    shown = true
                } else {
                    withAnimation(animation.delay(delay)) { shown = true }
                }
            }
    }
}

/// CARD-GLASS-BACKDROP: `ds3GlassCard`'s surface. Reads the one injected `GlassSettings` (nil in offscreen harness
/// renders → the default look). Under Reduce Transparency there is no material and the tint is opaque. Shadow and rim
/// are unchanged; no `.drawingGroup()` here (it would flatten the material's backdrop sample, findings R2-C4).
private struct DS3GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(GlassSettings.self) private var glass: GlassSettings?

    func body(content: Content) -> some View {
        let fill = glass?.fill ?? .standard
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background {
                ZStack {
                    if fill.usesMaterial { shape.fill(.regularMaterial) }
                    shape.fill(DS3.glassTint(fill))
                }
            }
            .overlay(DS3Rim(cornerRadius: cornerRadius))
            .ds3Elevation(.card, in: shape)
    }
}

// MARK: - Rim

/// Pointer-following edge highlight, dark appearance only. The gradient is a pre-rendered image rotated by a
/// Core Animation transform (`DS3RimLayer`); the tracker re-aims it imperatively, only when the pointer location
/// changes (D7) and once after a scroll ends. No body here reads the pointer (D6). Without a tracker (offscreen
/// harness renders) it is the static stroke at the resting angle.
@MainActor
struct DS3Rim: View {
    let cornerRadius: CGFloat

    @Environment(\.ds3PointerTracker) private var tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var model = DS3RimModel()

    var body: some View {
        // Light appearance draws no pointer rim (the white highlight is invisible on the light glass).
        if colorScheme == .dark {
            Group {
                if let tracker {
                    DS3RimLayer(cornerRadius: cornerRadius, model: model, isStatic: reduceMotion || DS3Motion.isFrozen)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(DS3.windowSpace)) }) { model.rect = $0 }
                        .onAppear { tracker.register(model) }
                        .onDisappear { tracker.unregister(model) }
                } else {
                    DS3RimStroke(angle: RimAngle.resting, cornerRadius: cornerRadius)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct DS3RimStroke: View {
    let angle: Double
    let cornerRadius: CGFloat

    var body: some View {
        // CSS conic 0 deg = up; SwiftUI 0 deg = trailing.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(
            AngularGradient(
                stops: DS3.rimStops(hi: DS3.rimHi, mid: DS3.rimMid, lo: DS3.rimLo),
                center: .center,
                startAngle: .degrees(angle - 90),
                endAngle: .degrees(angle + 270)
            ),
            lineWidth: 1.2
        )
    }
}

extension DS3 {
    /// One stop list for the SwiftUI stroke and `DS3RimImage`. CSS conic 0 deg = up.
    static func rimStops(hi: Color, mid: Color, lo: Color) -> [Gradient.Stop] {
        [
            .init(color: hi, location: 0),
            .init(color: lo, location: 0.22),
            .init(color: mid, location: 0.5),
            .init(color: lo, location: 0.78),
            .init(color: hi, location: 1),
        ]
    }
}

// MARK: - Orbs

/// Three soft static colour glows (`DS3OrbLayer`). Static by decision in HOME-D: the 12 Hz drift kept
/// WindowServer at ~10% CPU at idle (static: ~2.7%); motion returns only with the v2 orbs and their own perf A/B.
struct DS3OrbField: View {
    var body: some View {
        DS3OrbLayer()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
