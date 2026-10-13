// Views/DS3Surfaces.swift
// IPHONE-DESIGN: DS v3 surfaces (hand-drawn shadows, inset rims, glass card, pointer-following rim,
// drifting orbs, entrance motion). Used by iPhone mode; APP-REDESIGN will reuse them later.

import SwiftUI

// MARK: - Pointer tracker

/// The pointer position in `DS3.windowSpace`, written by one `.onContinuousHover` on the window root
/// (`ds3PointerTracking`) and read by every `DS3Rim`.
@MainActor @Observable
final class DS3PointerTracker {
    var location: CGPoint?
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
    func ds3GlassCard(cornerRadius r: CGFloat) -> some View {
        background {
            ZStack {
                RoundedRectangle(cornerRadius: r, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: r, style: .continuous).fill(DS3.glassStrong)
            }
        }
        .overlay(DS3Rim(cornerRadius: r))
        .ds3Elevation(.card, in: RoundedRectangle(cornerRadius: r, style: .continuous))
    }

    /// One `.onContinuousHover` on the window root feeds the tracker; rims read it from the environment.
    func ds3PointerTracking(_ t: DS3PointerTracker) -> some View {
        coordinateSpace(.named(DS3.windowSpace))
            .onContinuousHover(coordinateSpace: .named(DS3.windowSpace)) { phase in
                switch phase {
                case .active(let p): t.location = p
                case .ended: t.location = nil
                }
            }
            .environment(t)
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

// MARK: - Rim

/// Pointer-following edge highlight. The rim keeps its window-space frame in a non-observed box (D6) and
/// only re-aims on pointer movement (D7).
struct DS3Rim: View {
    let cornerRadius: CGFloat

    @Environment(DS3PointerTracker.self) private var tracker: DS3PointerTracker?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var angle = RimAngle.resting
    @State private var box = FrameBox()

    private final class FrameBox { var rect = CGRect.zero }

    var body: some View {
        // Light appearance draws no pointer rim (the white highlight is invisible on the light glass). The
        // stroke and its geometry/pointer observers exist only in dark, so light pays nothing per pointer move.
        if colorScheme == .dark {
            DS3RimStroke(angle: angle, cornerRadius: cornerRadius)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(DS3.windowSpace)) }) { box.rect = $0 }
                .onChange(of: tracker?.location) { _, p in update(p) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func update(_ p: CGPoint?) {
        guard !reduceMotion, !DS3Motion.isFrozen else { return }
        let target = p.map { RimAngle.target(pointer: $0, center: CGPoint(x: box.rect.midX, y: box.rect.midY)) } ?? RimAngle.resting
        withAnimation(DS3Motion.rim) { angle = RimAngle.continuing(from: angle, to: target) }
    }
}

struct DS3RimStroke: View, Animatable {
    var angle: Double
    let cornerRadius: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        // CSS conic 0 deg = up; SwiftUI 0 deg = trailing.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(
            AngularGradient(
                stops: [
                    .init(color: DS3.rimHi, location: 0),
                    .init(color: DS3.rimLo, location: 0.22),
                    .init(color: DS3.rimMid, location: 0.5),
                    .init(color: DS3.rimLo, location: 0.78),
                    .init(color: DS3.rimHi, location: 1),
                ],
                center: .center,
                startAngle: .degrees(angle - 90),
                endAngle: .degrees(angle + 270)
            ),
            lineWidth: 1.2
        )
    }
}

// MARK: - Orbs

/// Three large soft colour glows that drift very slowly (D3). Static under Reduce Motion and in
/// `-visualFixture` runs.
struct DS3OrbField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let periods: [Double] = [26, 34, 42]

    var body: some View {
        if reduceMotion || DS3Motion.isFrozen {
            orbs(k: [0, 0, 0])
        } else {
            TimelineView(.periodic(from: .now, by: DS3Motion.orbTick)) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                orbs(k: Self.periods.map { (1 - cos(2 * .pi * t / $0)) / 2 })
            }
        }
    }

    private func orbs(k: [Double]) -> some View {
        GeometryReader { g in
            ZStack {
                orb(DS3.orbA, d: 640, centre: CGPoint(x: g.size.width - 180, y: 100), dx: -60, dy: 50, s: 1.08, k: k[0])
                orb(DS3.orbB, d: 560, centre: CGPoint(x: 40, y: 640), dx: 70, dy: -40, s: 0.94, k: k[1])
                orb(DS3.orbC, d: 520, centre: CGPoint(x: g.size.width * 0.82 - 260, y: g.size.height), dx: -40, dy: 60, s: 1.10, k: k[2])
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func orb(_ c: Color, d: CGFloat, centre: CGPoint, dx: CGFloat, dy: CGFloat, s: CGFloat, k: Double) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c, c.opacity(0)], center: .center, startRadius: 0, endRadius: 0.495 * d))
            .frame(width: d, height: d)
            .scaleEffect(1 + (s - 1) * k)
            .offset(x: dx * k, y: dy * k)
            .position(centre)
    }
}
