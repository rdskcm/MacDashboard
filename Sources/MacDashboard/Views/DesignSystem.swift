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
    /// Paired with `.dsDisclosure(reduceMotion:)`: the disclosed content rises by
    /// this many points while it fades in/out.
    static let discloseRiseY: CGFloat = -7
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

// MARK: - Disclosure transition

/// Fade + slight rise, shared by every collapse/expand disclosure in the v2.0 UI
/// (AutostartCard, EnergyCard) so appearing/disappearing content reads as one
/// consistent motion instead of each call site inventing its own combination.
private struct DSFadeSlide: ViewModifier {
    let progress: Double            // 1 = hidden, 0 = shown
    func body(content: Content) -> some View {
        content.opacity(1 - progress).offset(y: DSMotion.discloseRiseY * progress)
    }
}
extension AnyTransition {
    static func dsDisclosure(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity
                     : .modifier(active: DSFadeSlide(progress: 1), identity: DSFadeSlide(progress: 0))
    }
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

    private var lift: CGFloat { (hovering && !reduceMotion) ? -2 : 0 }

    func body(content: Content) -> some View {
        // Hover/tap hit-testing is attached to this OUTER wrapper, not to a
        // same-level sibling probe (both prior attempts — `.overlay` probe,
        // then `.background` probe — failed in live testing: `.overlay` won
        // front-to-back tap resolution over buttons in `content`; `.background`
        // was itself occluded by `content`'s own opaque surface and never saw
        // hover events at all). `.offset()` is a render-time transform applied
        // after layout — it does not change what size/frame `content` reports
        // to its parent — so this ZStack's own layout frame, and therefore its
        // own `.contentShape`/`.onHover` hit region, stays pinned at the card's
        // RESTING position even while the inner content visually shifts by
        // `lift`. That keeps the hit area stable (no bottom-edge oscillation).
        // `content` (with the real buttons) remains a distinct child node with
        // its own hit-testing at its actual rendered position, so a plain
        // `.onHover` + `.contentShape` on the parent — with no `.onTapGesture`
        // attached here — never intercepts the child Buttons' own gesture
        // recognizers; clicks still resolve normally on the controls.
        ZStack {
            content
                .offset(y: lift)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(hovering ? DS.lineStrong : .clear, lineWidth: 1)
                        .offset(y: lift)
                )
        }
        .animation(
            reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
            value: hovering
        )
        .contentShape(Rectangle())
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

// MARK: - In-place state swap

/// Draws `replacement` in place of the receiver WITHOUT letting the container
/// resize: the receiver stays the layout's size determinant (hidden, never
/// removed) and the replacement is drawn centred on top of it.
///
/// Use wherever a spinner or a ✓ takes a label's place mid-action. Mounting
/// them as `HStack` siblings instead measured a +22 pt width jump on
/// `RainbowCapsuleButton` and a −48 pt swing on the attention chip
/// (V2-FIX-OPTICAL, 2026-08-09) — enough to reflow the whole row around the
/// control while a single action runs.
struct DSSwapInPlace<Replacement: View>: ViewModifier {
    let isActive: Bool
    @ViewBuilder let replacement: () -> Replacement

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0 : 1)
            .overlay { if isActive { replacement() } }
    }
}

extension View {
    func dsSwapInPlace<R: View>(_ isActive: Bool, @ViewBuilder replacement: @escaping () -> R) -> some View {
        modifier(DSSwapInPlace(isActive: isActive, replacement: replacement))
    }
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
/// ease-out. Labels cross-fade color over 0.18 s. Each segment is sized from
/// its own label + padding (`DSSegmentedSize`) — the control never fixes its
/// own width; callers must not pin one via `.frame`.
enum DSSegmentedSize {
    /// Toolbar-level tabs (e.g. the Overview/Report switch): larger type, more
    /// breathing room.
    case tabs
    /// In-card controls (metric pickers, folder tabs): the default, tighter fit.
    case card
    /// Settings ▸ Monitoring interval switch (spec §2.3/§7.3, SW:92): monospaced
    /// tabular digits, since the segments are all-numeric.
    case settingsInterval

    var font: Font {
        switch self {
        case .tabs: return .system(size: 12.5, weight: .semibold)
        case .card: return .system(size: 11, weight: .semibold)
        case .settingsInterval: return .system(size: 12, weight: .semibold, design: .monospaced)
        }
    }
    var hPad: CGFloat {
        switch self {
        case .tabs: return 16
        case .card: return 11
        case .settingsInterval: return 11
        }
    }
    var vPad: CGFloat {
        switch self {
        case .tabs: return 6
        case .card: return 5
        case .settingsInterval: return 6
        }
    }
    /// Gap between segments, matching the prototype track's `gap` (2px for
    /// tabs/card, 3px for the monospaced Settings interval switch).
    var gap: CGFloat {
        switch self {
        case .tabs: return 2
        case .card: return 2
        case .settingsInterval: return 3
        }
    }
}

private enum DSSlidingSegmentedTokens {
    // Thumb outward shadows (dark opacity > light, same reasoning as the track).
    // Exact `--thumb-shadow` alphas per Desktop/Segmented Control Spec.md (2026-08-11).
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
    let size: DSSegmentedSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stretch: CGFloat = 1.0
    /// Transform-origin for the stretch scale, direction-aware: anchored at the
    /// side the thumb is moving TO, so the stretch smears back toward the side it
    /// came from. Updated in `select(_:)`, the sole mutator of `selection`.
    @State private var stretchAnchor: UnitPoint = .trailing
    /// Outer container inset (spec §2.3): track, thumb, and labels all sit
    /// inset 3 pt from the control's own bounds.
    private let containerPadding: CGFloat = 3
    /// Thumb inset beyond `containerPadding` — 0 per Desktop/Segmented Control Spec.md
    /// §2 ("top: 3px; bottom: 3px — insets equal the capsule padding", nothing extra).
    private let thumbInset: CGFloat = 0
    /// Each segment's rendered width, keyed by index — read from the label's
    /// own laid-out geometry (`.onGeometryChange`, not a `GeometryReader`
    /// inside the animated subtree: that previously collapsed the row to
    /// ~6 pt mid-transition). Drives both the thumb's width and its offset.
    @State private var widths: [Int: CGFloat] = [:]
    /// Label row height, measured the same way as `widths`. The `.background`
    /// this control's thumb sits in is proposed the FULL padded frame (labels
    /// + `containerPadding` on every side), so without an explicit height the
    /// thumb — constrained only in width — stretches to fill that full height
    /// instead of matching the label row. Uniform across segments (same font/
    /// `vPad` per size variant), so the last write wins.
    @State private var rowHeight: CGFloat = 0

    init(options: [T], selection: Binding<T>, size: DSSegmentedSize = .card, label: @escaping (T) -> String) {
        self.options = options
        self._selection = selection
        self.size = size
        self.label = label
    }

    private var selectedIndex: Int {
        options.firstIndex(of: selection) ?? 0
    }

    private var thumbWidth: CGFloat {
        widths[selectedIndex] ?? 0
    }

    private var thumbOffset: CGFloat {
        let precedingWidths = (0..<selectedIndex).reduce(CGFloat(0)) { $0 + (widths[$1] ?? 0) }
        return precedingWidths + size.gap * CGFloat(selectedIndex)
    }

    var body: some View {
        HStack(spacing: size.gap) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                Button {
                    select(option)
                } label: {
                    Text(label(option))
                        .font(size.font)
                        .foregroundStyle(option == selection ? DS.ink : DS.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, size.hPad)
                        .padding(.vertical, size.vPad)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .animation(
                    reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : .easeInOut(duration: 0.18),
                    value: selection
                )
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
                    widths[index] = newSize.width
                    rowHeight = newSize.height
                }
            }
        }
        .padding(containerPadding)
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                track

                thumb
                    .frame(width: max(0, thumbWidth - 2 * thumbInset), height: max(0, rowHeight - 2 * thumbInset))
                    .offset(x: containerPadding + thumbInset + thumbOffset, y: containerPadding + thumbInset)
                    .scaleEffect(x: stretch, y: 1, anchor: stretchAnchor)
                    .animation(nil, value: widths)
                    .animation(nil, value: rowHeight)
                    .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.68), value: selection)
            }
        }
    }

    // Local reimplementation of `dsRecessedTrack` (never edit that shared helper —
    // `SharedUI.swift:90` reuses it for 6 pt progress bars) using the same
    // opaque-layer technique as the thumb below: native `ShapeStyle.shadow(.inner(...))`
    // on a translucent fill (`DS.track`, ~0.10 alpha) reads flat — confirmed live, twice,
    // for both this and the GlassSegmented.swift reference port. Hand-rolled here as
    // blurred, offset, opaque Capsules masked back to the track's own shape (so they
    // stay INSET rather than haloing outward like the thumb's).
    private var track: some View {
        ZStack {
            Capsule().fill(DS.track)
            // A masked, shifted-then-blurred opaque copy reveals MORE of itself on the
            // side it's shifted TOWARD, not away from — the inverse of a normal offset
            // shadow's intuition. To darken the top inner edge (matching CSS positive-Y
            // inset shadows) the copy must shift UP (negative y); the bottom "bounce"
            // highlight (CSS y:-3) mirrors that and shifts DOWN (positive y).
            // Full magnitudes per Desktop/Segmented Control Spec.md §1 (radius = blur / 2,
            // same as `dsRecessedTrack`'s own untouched numbers: 18px blur → 9, 7px → 3.5,
            // 2px → 1, 8px bounce → 4).
            ZStack {
                Capsule().fill(DSRecessedTrackTokens.inner3).blur(radius: 9).offset(y: -9)
                Capsule().fill(DSRecessedTrackTokens.inner2).blur(radius: 3.5).offset(y: -3)
                Capsule().fill(DSRecessedTrackTokens.inner1).blur(radius: 1).offset(y: -1)
                Capsule().fill(DSRecessedTrackTokens.bounce).blur(radius: 4).offset(y: 3)
            }
            .compositingGroup()
            .mask(Capsule())
        }
        .overlay(Capsule().strokeBorder(DS.line, lineWidth: 1))
    }

    // Radii use the app-wide CSS-blur→SwiftUI-radius convention (radius = blur / 2,
    // spread not modeled) — the same one `dsRecessedTrack` uses for its own
    // negative-spread shadows (`--thumb-shadow`: `0 4px 10px -3px` → radius 5 y 4,
    // `inset 0 3px 6px -4px` → radius 3 y 3).
    //
    // These are hand-rolled as blurred, offset, opaque-filled Capsules BEHIND the
    // visible thumb rather than `.shadow()` view modifiers — confirmed by an A/B
    // test (solid white fill vs `DS.glass3`) that `.shadow()`'s effective strength
    // is multiplied by the shadowed content's OWN alpha, and `DS.glass3` is ~0.11
    // alpha, which crushed every one of these shadows to invisible. Filling a shape
    // directly with a color that already carries its own alpha has no such dilution.
    //
    // The blurred core of each shadow is punched out exactly where it sits under the
    // thumb's own footprint (`.blendMode(.destinationOut)` inside a `.compositingGroup()`)
    // so only the halo bleeding past the visible edge shows — a `.padding`-based shrink
    // alone still left enough full-alpha core under the translucent glass fill to
    // darken the whole pill toward black instead of just haloing its edge (found live).
    private var thumb: some View {
        ZStack {
            ZStack {
                Capsule().fill(DSSlidingSegmentedTokens.shadow3).blur(radius: 10).offset(y: 10)
                Capsule().fill(DSSlidingSegmentedTokens.shadow2).blur(radius: 5).offset(y: 4)
                Capsule().fill(DSSlidingSegmentedTokens.shadow1).blur(radius: 1).offset(y: 1)
                Capsule().fill(Color.black).blendMode(.destinationOut)
            }
            .compositingGroup()

            Capsule()
                .fill(DS.glass3.shadow(.inner(color: DSSlidingSegmentedTokens.gleam, radius: 3, y: 3)))
        }
    }

    private func select(_ option: T) {
        guard option != selection else { return }
        let oldIndex = selectedIndex
        let newIndex = options.firstIndex(of: option) ?? oldIndex
        // Anchor at the side the thumb is moving TO, so it visually smears
        // back toward where it came from (prototype: transform-origin follows
        // movement direction, not the departure side).
        stretchAnchor = newIndex > oldIndex ? .trailing : .leading
        selection = option
        guard !reduceMotion else { return }
        // Two sequential eased legs (1 -> 1.09 -> 1), each 0.19s, mirroring the
        // prototype's `transform .19s ease-out` transition being retriggered
        // twice: once when the stretch is applied, once 190ms later when it's
        // cleared.
        withAnimation(.easeOut(duration: 0.19)) {
            stretch = 1.09
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { [self] in
            withAnimation(.easeOut(duration: 0.19)) {
                stretch = 1.0
            }
        }
    }
}

// MARK: - Bleed-rect clip shape

/// A clip shape that crops the edges an animation needs cropped while letting
/// a rainbow ring's outer glow survive (19 pt bleed, see SharedUI.swift:825
/// `RainbowRingLayer`'s `.overview` layer) on the edges left at their default 0.
struct BleedRect: Shape {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
    var bottom: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX - leading,
            y: rect.minY - top,
            width: rect.width + leading + trailing,
            height: rect.height + top + bottom
        ))
    }
}

// MARK: - Disclosure chevron

/// `DSDisclosureBars(expanded:)` — the prototype's two-bar disclosure indicator
/// (`Overview Screen.dc.html`: 13×13 container, 13×2 track, two 7×1.7 pt bars).
/// Collapsed, the container is rotated −90° and the bars sit at ±45° around their
/// inner ends, reading as a right-pointing chevron. Expanded, everything returns
/// to 0° and the two bars — pinned to opposite edges of the 13 pt track, so they
/// overlap by 1 pt — merge into one seamless horizontal bar. Uses `DSMotion.expand`,
/// the same curve as the disclosed content's own fade/slide, so the chevron and
/// the section body move on one shared timing instead of two out-of-step curves.
/// Reduce Motion: the transforms jump, since this is a transform rather than a
/// color/opacity/border/shadow transition.
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
        .animation(reduceMotion ? nil : DSMotion.expand, value: expanded)
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
