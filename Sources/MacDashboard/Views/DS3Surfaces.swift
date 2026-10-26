// Views/DS3Surfaces.swift
// IPHONE-DESIGN: DS v3 surfaces (hand-drawn shadows, inset rims, glass card, pointer-light rim sprite,
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

    func register(_ m: DS3RimModel) {
        rims[ObjectIdentifier(m)] = m
        if !isScrolling { m.aim(at: location) }
    }
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
        view.aim(to: p.map { RimLight.localPoint($0, in: rect) })
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
    /// HISTORY-HOVER-COST: `resolve` maps each shadow colour before use (ImageRenderer needs appearance-resolved colours, D5).
    func ds3Elevation<S: InsettableShape>(_ s: DS3Shadow, in shape: S, resolve: ((Color) -> Color)? = nil) -> some View {
        let layers = s.layers
        return background {
            ZStack {
                ForEach(Array(layers.enumerated()), id: \.offset) { _, l in
                    shape.inset(by: l.inset).fill(resolve?(l.color) ?? l.color).blur(radius: l.radius).offset(y: l.y)
                }
                shape.fill(Color.black).blendMode(.destinationOut)
            }
            .compositingGroup()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// CSS `inset 0 1px 0 X` is `top: X`; `inset 0 0 0 .5px X` is `ring: X`; `inset 0 0 0 1px X` is `ring: X, ringWidth: 1`.
    /// The `top:` highlight is a stretched sprite (`DS3StretchSprite`, RESIZE-FRAME-COST).
    func ds3InsetRims<S: InsettableShape>(_ shape: S, top: Color? = nil, ring: Color? = nil, ringWidth: CGFloat = 0.5) -> some View {
        overlay {
            if let ring {
                shape.strokeBorder(ring, lineWidth: ringWidth).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if let top {
                // Top-edge-only highlight: a stretched sprite (`DS3StretchSprite`, RESIZE-FRAME-COST).
                DS3StretchSprite(
                    shape: shape,
                    content: .topRim(
                        stops: RimAmbient.ramp(alpha: 0.55, ground: DS3.rimGroundDark)
                            .map { Gradient.Stop(color: top.opacity($0.multiplier), location: 0.18 * $0.location) },
                        lineWidth: 1
                    )
                )
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
            DS3StretchSprite(
                shape: RoundedRectangle(cornerRadius: r, style: .continuous),
                content: .fill(stops: [.init(color: tone.opacity(a), location: 0), .init(color: tone.opacity(b), location: 1)])
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

    /// Settings group (`Settings.dc.html:74`): `DS3GlassCard`'s fill with an inset 1 pt `DS3.line` border and no rim or shadow.
    func ds3GlassGroup(cornerRadius r: CGFloat) -> some View {
        modifier(DS3GlassGroup(cornerRadius: r))
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

/// REDESIGN-SETTINGS: the Settings window's grouped-rows surface. Same fill as `DS3GlassCard` (material + tint through
/// `GlassSettings`), 1 pt inset `DS3.line` border, no rim and no shadow.
private struct DS3GlassGroup: ViewModifier {
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
            .overlay(shape.strokeBorder(DS3.line, lineWidth: 1))
    }
}

/// CARD-GLASS-LEFTOVERS: the frosted bar surface (main header, `SectionPageBar`, `IPhoneDeviceView.header`): material
/// plus `DS3.bar`, following the Liquid Glass slider and Reduce Transparency through the same `GlassSettings` as
/// `DS3GlassCard` (bar stops `GlassTint.barDark` / `barLight`). Under Reduce Transparency: no material, opaque bar
/// colour. A View, not a modifier: the header stacks its own rim, line and shadow on it, and those stay at the call sites.
struct DS3GlassBar: View {
    @Environment(GlassSettings.self) private var glass: GlassSettings?

    var body: some View {
        let fill = glass?.fill ?? .standard
        ZStack {
            if fill.usesMaterial { Rectangle().fill(.regularMaterial) }
            Rectangle().fill(DS3.barTint(fill))
        }
    }
}

// MARK: - Rim

/// Pointer light on the card edge (RIM-GLOW-OPTICS): a point light at height h over the glass. One pre-rendered
/// sprite layer per card (`DS3RimLayer`) is moved by the tracker imperatively, only when the pointer location
/// changes (D7) and once after a scroll ends; a static sublayer holds the ambient light from above. No body here
/// reads the pointer (D6). Without a tracker (offscreen harness renders) it is the static ambient stroke.
@MainActor
struct DS3Rim: View {
    let cornerRadius: CGFloat

    @Environment(\.ds3PointerTracker) private var tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var model = DS3RimModel()

    var body: some View {
        Group {
            if let tracker {
                DS3RimLayer(cornerRadius: cornerRadius, model: model, isStatic: reduceMotion || DS3Motion.isFrozen)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(DS3.windowSpace)) }) { model.rect = $0 }
                    .onAppear { tracker.register(model) }
                    .onDisappear { tracker.unregister(model) }
            } else if colorScheme == .dark || RimLight.lightMode != .none {
                DS3RimStroke(cornerRadius: cornerRadius)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The static ambient-only stroke: top light fading over the corner radius (spec §3.3, D7).
struct DS3RimStroke: View {
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(
                LinearGradient(
                    stops: RimAmbient.ramp(alpha: 0.2 /* rimMid dark */, ground: DS3.rimGroundDark)
                        .map { .init(color: DS3.rimMid.opacity($0.multiplier), location: $0.location) },
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: min(1, cornerRadius / max(1, g.size.height)))
                ),
                lineWidth: 1.2
            )
        }
    }
}

// MARK: - Orbs

/// Three soft static colour glows (`DS3OrbLayer`). Static since HOME-D; REDESIGN-ORBS kept them static
/// after its drift A/B (WindowServer 2.3 → 10.8 %; a cheaper drift is ORB-DRIFT-CHEAP).
/// Hidden when Settings › Background orbs is off or Reduce Motion is on (REDESIGN-SETTINGS).
struct DS3OrbField: View {
    var orbs: [DS3OrbSpec] = DS3OrbSpec.window
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if AppSettings.shared.orbsEnabled && !reduceMotion {
            DS3OrbLayer(orbs: orbs)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
