// Views/DesignSystem.swift
// Block V2-FOUND: v2.0 design-system surfaces/controls/motion, all values inlined
// from the design handoff Spec §2–§4 so no later block re-derives layer geometry.
// Pure SwiftUI Views code (not Foundation-only) — deliberately NOT symlinked into
// Checks/ (see PLAN.md block spec: a symlink here would break the Foundation-only
// MacDashboardChecks target).
//
// Reduce Motion contract (project-wide, wired here as a deliverable of this block):
// keyframe-style/transform animations play once at ~0 ms (i.e. no animation) under
// `@Environment(\.accessibilityReduceMotion)`; only 0.12 s color/opacity/border/
// shadow transitions remain. Every control below reads the environment value and
// degrades accordingly.

import SwiftUI

// MARK: - Motion constants

/// Named animation curves shared across the v2.0 UI so no later block re-derives
/// timing. `rainbow` and `reduceMotionFallback` are plain durations (seconds) —
/// callers pick their own curve for those two; the rest are ready-to-use `Animation`s.
enum DSMotion {
    static let barRelayout = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let cardHover = Animation.easeOut(duration: 0.16)
    static let fillHover = Animation.easeOut(duration: 0.12)
    static let tooltip = Animation.easeInOut(duration: 0.15)
    /// Paired with `tooltip`: the tooltip rises by this many points while it fades in.
    static let tooltipRiseY: CGFloat = -7
    static let expand = Animation.easeInOut(duration: 0.18)
    /// Popover dismiss fade duration — a plain duration (not a curve); callers pick their own easing.
    static let popoverDismiss: Double = 0.16
    static let breathing = Animation.easeInOut(duration: 2).repeatCount(5, autoreverses: true)
    /// Rainbow ring rotation period, seconds/turn. Both prototypes and the shipping
    /// default agree on 6 s; Spec §4's "~1.4 s" row is not authoritative — flip
    /// here only, at acceptance, so it's a one-line edit (see SharedUI.swift Step 3a).
    static let rainbow: Double = 6
    /// Reduce Motion fallback duration for color/opacity/border/shadow transitions.
    static let reduceMotionFallback: Double = 0.12
    /// Hover transition for controls that ALSO carry a `.rainbowBorder()` glow
    /// (e.g. EnergyCard's Reset button). `RainbowBorder` fades its own ring with
    /// a hardcoded internal `.easeInOut(duration: 0.25)` (SharedUI.swift); a
    /// caller-side hover animation on a *different* curve/duration (e.g. the
    /// plain `cardHover` easeOut/0.16 s used by non-glow hover controls) settles
    /// before the ring's own fade does, so the color and the glow visibly move
    /// out of step — read as an abrupt, two-stage hover instead of one smooth
    /// motion. Same 0.25 s response as the ring's fade keeps them in lockstep;
    /// `dampingFraction: 0.86` reuses `barRelayout`'s established "smooth,
    /// no-overshoot" damping instead of inventing a new ratio.
    static let rainbowHover = Animation.spring(response: 0.25, dampingFraction: 0.86)
}

// MARK: - Shadow color helper

/// Navy-tinted black (rgba(20,30,50,·)) used for every light-appearance
/// elevation/inset shadow layer below — plain black reads flat/muddy against
/// the light ground, spec calls for this cool tint instead. Dark-appearance
/// shadow layers stay plain `Color.black`.
private func dsShadowNavy(_ opacity: Double) -> Color {
    Color(red: 20 / 255, green: 30 / 255, blue: 50 / 255, opacity: opacity)
}

// MARK: - Card surface

/// `.dsCardSurface()` — the load-bearing visual surface for every card in the
/// app (delegated to by `CardBackgroundModifier` in SharedUI.swift). Rounded
/// rect, native `.regularMaterial`, a 1 pt hairline border, a three-layer
/// elevation shadow stack, and a top-edge highlight (the only hard edge).
private enum DSCardSurfaceTokens {
    // Elevation shadows (color = black; radius values are already the
    // blur/2 SwiftUI translation — SwiftUI shadows have no CSS-style spread).
    static let contact = Color(light: dsShadowNavy(0.10), dark: Color.black.opacity(0.45))
    static let mid = Color(light: dsShadowNavy(0.13), dark: Color.black.opacity(0.50))
    static let ambient = Color(light: dsShadowNavy(0.24), dark: Color.black.opacity(0.72))
    // Top-edge highlight: bright in light appearance (white 85%), subtle in dark (white 10%).
    static let highlight = Color(light: Color.white.opacity(0.85), dark: Color.white.opacity(0.10))
}

struct DSCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DS.line, lineWidth: 1)
            )
            .overlay(
                // Top-edge-only highlight: a full-perimeter stroke whose gradient
                // fades from `highlight` to `.clear` over the first ~15% of the
                // shape's height, so only the top arc reads as a crisp edge.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: DSCardSurfaceTokens.highlight, location: 0),
                                .init(color: .clear, location: 0.15),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            // Flattens the card into a single composited layer before the shadow
            // stack below, so each of the three shadows rasterizes the already-
            // composited result once instead of the full material+content subtree
            // three times per frame. Confirmed empirically (not `.drawingGroup()`,
            // which would also flatten the `.regularMaterial` backdrop sample and
            // silently change the visual result — `.compositingGroup()` does not).
            .compositingGroup()
            .shadow(color: DSCardSurfaceTokens.contact, radius: 0.75, x: 0, y: 1)
            .shadow(color: DSCardSurfaceTokens.mid, radius: 5, x: 0, y: 4)
            .shadow(color: DSCardSurfaceTokens.ambient, radius: 17, x: 0, y: 16)
    }
}

extension View {
    func dsCardSurface() -> some View { modifier(DSCardSurface()) }
}

// MARK: - Hover lift

/// `.dsHoverLift()` — the shared card-hover affordance: a 2 pt upward offset
/// plus a border step up to `DS.lineStrong`, `DSMotion.cardHover` (0.16 s
/// ease-out). Under Reduce Motion the offset is dropped entirely and only the
/// border/color change remains, at the 0.12 s Reduce Motion fallback duration.
struct DSHoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .offset(y: (hovering && !reduceMotion) ? -2 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? DS.lineStrong : .clear, lineWidth: 1)
            )
            .animation(
                reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
                value: hovering
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func dsHoverLift() -> some View { modifier(DSHoverLift()) }
}

/// `.dsBorderHover()` — a border-only hover treatment: transitions the card
/// border from `DS.line` to `DS.lineStrong` on hover, with NO offset/lift
/// (unlike `dsHoverLift`). Same `DSMotion.cardHover` duration as `dsHoverLift`
/// normally; since this is purely a color/border transition (not a transform),
/// it keeps running under Reduce Motion per this file's Reduce Motion contract
/// — only the duration drops to `DSMotion.reduceMotionFallback`, mirroring how
/// `dsHoverLift` degrades its own border/color half.
struct DSBorderHover: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? DS.lineStrong : DS.line, lineWidth: 1)
            )
            .animation(
                reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
                value: hovering
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func dsBorderHover() -> some View { modifier(DSBorderHover()) }
}

// MARK: - Recessed track

/// `dsRecessedTrack(in:)` — the shared smooth-recess background reused by
/// `DSSlidingSegmented`'s track and by 6 pt progress bars. FORBIDDEN shape
/// (rejected in design review): a single short-blur inset + a hard 1 pt inner
/// ring — that reads as a visible banding ring. Instead this chains three
/// growing-radius inner shadows closed by a soft bottom "bounce" highlight, so
/// the result reads as one smooth recess, plus the ordinary 1 pt `DS.line`
/// border. Returns a ready-to-place `View` (fill + inner-shadow stack + border)
/// rather than a bare `ShapeStyle`, since the border can't be expressed as one.
private enum DSRecessedTrackTokens {
    // Three growing inner shadows (dark opacity > light — black has less
    // contrast against a dark ground, so it needs more alpha to read there).
    static let inner1 = Color(light: dsShadowNavy(0.09), dark: Color.black.opacity(0.30))
    static let inner2 = Color(light: dsShadowNavy(0.085), dark: Color.black.opacity(0.26))
    static let inner3 = Color(light: dsShadowNavy(0.07), dark: Color.black.opacity(0.20))
    // Bottom "bounce" highlight (white opposite skew — light needs more alpha
    // to read a white highlight against an already-light ground).
    static let bounce = Color(light: Color.white.opacity(0.55), dark: Color.white.opacity(0.06))
}

func dsRecessedTrack<S: InsettableShape>(in shape: S) -> some View {
    shape
        .fill(
            DS.track
                .shadow(.inner(color: DSRecessedTrackTokens.inner1, radius: 1, y: 1))
                .shadow(.inner(color: DSRecessedTrackTokens.inner2, radius: 3.5, y: 3))
                .shadow(.inner(color: DSRecessedTrackTokens.inner3, radius: 9, y: 9))
                .shadow(.inner(color: DSRecessedTrackTokens.bounce, radius: 4, y: -3))
        )
        .overlay(shape.strokeBorder(DS.line, lineWidth: 1))
}

// MARK: - Sliding segmented control

/// `DSSlidingSegmented<T: Hashable>` — a recessed-track segmented control with
/// an inverted sliding capsule thumb (never a per-button background). The
/// thumb is rendered BEHIND the labels (zIndex 0 vs 1); its motion is a
/// `.spring(response: 0.38, dampingFraction: 0.68)` slide plus a `scaleX(1.09)`
/// stretch anchored to the trailing edge that relaxes back to 1.0 over 0.19 s
/// ease-out. Labels cross-fade color over 0.18 s. Segments are equal-width
/// (divides the available width by option count).
private enum DSSlidingSegmentedTokens {
    // Thumb outward shadows (dark opacity > light, same reasoning as the track).
    static let shadow1 = Color(light: dsShadowNavy(0.10), dark: Color.black.opacity(0.26))
    static let shadow2 = Color(light: dsShadowNavy(0.13), dark: Color.black.opacity(0.34))
    static let shadow3 = Color(light: dsShadowNavy(0.16), dark: Color.black.opacity(0.40))
    // Top gleam (inner, white — light needs more alpha to read against the light ground).
    static let gleam = Color(light: Color.white.opacity(0.95), dark: Color.white.opacity(0.22))
}

struct DSSlidingSegmented<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stretch: CGFloat = 1.0
    /// Transform-origin for the stretch scale, direction-aware: anchored at
    /// the side the thumb moved FROM, so it visually stretches toward the new
    /// position. Updated in `select(_:)`, the sole mutator of `selection`.
    @State private var stretchAnchor: UnitPoint = .trailing
    /// Outer container inset (spec §2.3): track, thumb, and labels all sit
    /// inset 3 pt from the control's own bounds.
    private let containerPadding: CGFloat = 3

    init(options: [T], selection: Binding<T>, label: @escaping (T) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    private var selectedIndex: Int {
        options.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(options.count, 1)
            let segmentWidth = max(0, geo.size.width - containerPadding * 2) / CGFloat(count)

            ZStack(alignment: .leading) {
                dsRecessedTrack(in: Capsule())

                thumb
                    .frame(width: max(0, segmentWidth))
                    .offset(x: segmentWidth * CGFloat(selectedIndex))
                    .scaleEffect(x: stretch, y: 1, anchor: stretchAnchor)
                    .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.68), value: selection)
                    .zIndex(0)

                HStack(spacing: 2) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            select(option)
                        } label: {
                            Text(label(option))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(option == selection ? DS.ink : DS.muted)
                                .frame(width: segmentWidth)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(option))
                        .animation(
                            reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : .easeInOut(duration: 0.18),
                            value: selection
                        )
                    }
                }
                .zIndex(1)
            }
            .padding(containerPadding)
        }
        .frame(height: 28)
    }

    private var thumb: some View {
        Capsule()
            .fill(DS.glass3.shadow(.inner(color: DSSlidingSegmentedTokens.gleam, radius: 3, y: 3)))
            .padding(3)
            .shadow(color: DSSlidingSegmentedTokens.shadow1, radius: 1, x: 0, y: 1)
            .shadow(color: DSSlidingSegmentedTokens.shadow2, radius: 5, x: 0, y: 4)
            .shadow(color: DSSlidingSegmentedTokens.shadow3, radius: 10, x: 0, y: 10)
    }

    private func select(_ option: T) {
        guard option != selection else { return }
        let oldIndex = selectedIndex
        let newIndex = options.firstIndex(of: option) ?? oldIndex
        // Anchor at the side the thumb is leaving, so the stretch reads as
        // motion toward the new position.
        stretchAnchor = newIndex > oldIndex ? .leading : .trailing
        selection = option
        guard !reduceMotion else { return }
        stretch = 1.09
        withAnimation(.easeOut(duration: 0.19)) {
            stretch = 1.0
        }
    }
}

// MARK: - Disclosure chevron

/// `DSDisclosureBars(expanded:)` — the prototype's two-bar disclosure indicator
/// (`Overview Screen.dc.html`: 13×13 container, 13×2 track, two 7×1.7 pt bars).
/// Collapsed, the container is rotated −90° and the bars sit at ±45° around their
/// inner ends, reading as a right-pointing chevron. Expanded, everything returns
/// to 0° and the two bars — pinned to opposite edges of the 13 pt track, so they
/// overlap by 1 pt — merge into one seamless horizontal bar. The prototype's
/// `.22s cubic-bezier(0.34, 1.3, 0.64, 1)` maps to `.spring(response: 0.22,
/// dampingFraction: 0.62)`. Reduce Motion: the transforms jump, since this is a
/// transform rather than a color/opacity/border/shadow transition.
struct DSDisclosureBars: View {
    let expanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barSize = CGSize(width: 7, height: 1.7)
    private let boxSize: CGFloat = 13

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                bar.rotationEffect(.degrees(expanded ? 0 : 45), anchor: .trailing)
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                bar.rotationEffect(.degrees(expanded ? 0 : -45), anchor: .leading)
            }
        }
        .frame(width: boxSize, height: boxSize)
        .rotationEffect(.degrees(expanded ? 0 : -90))
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.62), value: expanded)
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: barSize.height / 2)
            .fill(DS.muted)
            .frame(width: barSize.width, height: barSize.height)
    }
}

// MARK: - Kicker text style

/// `.dsKicker()` — section-header eyebrow/kicker: a 22×2 pt `DS.accent` bar
/// followed by an uppercase label (spec §2.8, source OS:116-119). Label color
/// is `DS.accentInk` — deliberate, per §2.8's component-level table, not the
/// more ambiguous general token-role table.
extension Text {
    func dsKicker() -> some View {
        HStack(spacing: 9) {
            dsKickerBar
            dsKickerLabel
        }
        .padding(.top, 4)
    }

    /// `.dsKickerCentered()` — the СИСТЕМА section's variant: bar - label - bar,
    /// horizontally centered in its container, instead of the standard
    /// left-aligned single-bar-then-label layout every other kicker uses.
    /// Reuses the same bar/label styling as `.dsKicker()` — only the layout differs.
    func dsKickerCentered() -> some View {
        HStack(spacing: 9) {
            dsKickerBar
            dsKickerLabel
            dsKickerBar
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    private var dsKickerBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(DS.accent)
            .frame(width: 22, height: 2)
    }

    private var dsKickerLabel: some View {
        self
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(11.5 * 0.14) // 0.14em tracking
            .textCase(.uppercase)
            .foregroundStyle(DS.accentInk)
    }
}
