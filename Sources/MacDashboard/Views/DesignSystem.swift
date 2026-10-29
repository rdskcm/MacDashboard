// Views/DesignSystem.swift
// Block V2-FOUND: v2.0 design-system surfaces/controls/motion, all values inlined
// from the design handoff Spec §2–§4 so no later block re-derives layer geometry.
// Pure SwiftUI Views code (not Foundation-only) — deliberately app-only, not
// covered by Tests/MacDashboardTests (see PLAN.md block spec: the tested Engine code stays Foundation-only).
//
// Reduce Motion contract (project-wide, wired here as a deliverable of this block):
// keyframe-style/transform animations play once at ~0 ms (i.e. no animation) under
// `@Environment(\.accessibilityReduceMotion)`; only 0.12 s color/opacity/border/
// shadow transitions remain. Every control below reads the environment value and
// degrades accordingly.

import SwiftUI

// MARK: - Motion constants

/// Named animation curves shared across the v2.0 UI so no later block re-derives
/// timing. `reduceMotionFallback` is a plain duration (seconds) — callers pick
/// their own curve for it; the rest are ready-to-use `Animation`s.
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
    /// Reduce Motion fallback duration for color/opacity/border/shadow transitions.
    static let reduceMotionFallback: Double = 0.12
}

// MARK: - Disclosure transition

/// Fade + slight rise, shared by every collapse/expand disclosure in the v2.0 UI
/// (QuietStrip rows, the process-row panels, SectionRows) so appearing/disappearing content reads as one
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
/// Under Reduce Transparency the fill is the solid card colour, not the material (CARD-GLASS-LEFTOVERS).
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
    /// CARD-GLASS-LEFTOVERS: nil in offscreen renders (no injection) → material, the reference look. Only the
    /// Reduce Transparency branch is read (`usesMaterial`), so the Liquid Glass slider never re-runs this body.
    @Environment(GlassSettings.self) private var glass: GlassSettings?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return content
            .background {
                // Under Reduce Transparency the material becomes the OS grey stand-in; draw the app's solid card
                // colour instead (the same one the DS3 glass cards use, D5).
                if glass?.usesMaterial ?? true { shape.fill(.regularMaterial) } else { shape.fill(DS3.glassTint(.solid)) }
            }
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
            .dsCardElevation()
    }
}

extension View {
    func dsCardSurface() -> some View { modifier(DSCardSurface()) }

    /// The card elevation alone: the three appearance-adaptive shadow layers of
    /// `DSCardSurfaceTokens`. Used by `DSCardSurface` and by Settings'
    /// `SolidCardSurface`, which needs the same elevation without the material
    /// fill. Apply it after `.compositingGroup()`, as `DSCardSurface` does.
    func dsCardElevation() -> some View {
        self
            .shadow(color: DSCardSurfaceTokens.contact, radius: 0.75, x: 0, y: 1)
            .shadow(color: DSCardSurfaceTokens.mid, radius: 5, x: 0, y: 4)
            .shadow(color: DSCardSurfaceTokens.ambient, radius: 17, x: 0, y: 16)
    }
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
                // Resolve the lifted subtree's geometry as one unit BEFORE the
                // animated offset (HOVER-TEXT-JITTER). Without it, a Text whose
                // own paint animates in the same transaction as the lift (a hover
                // colour fade on a capsule label, the Memory legend emphasis) is
                // re-rendered and positioned independently of its siblings: it
                // reaches the lifted position on the first frame, overshoots on
                // exit and snaps back. Must stay BEFORE `.offset` — placed after
                // it the group has no effect (measured). Not a rasterisation: no
                // offscreen pass, glyph rendering unchanged. Do not replace with
                // `.drawingGroup()` (1 px lag, re-rasterises text, flattens the
                // card material) or `.compositingGroup()` (no effect here).
                .geometryGroup()
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
/// a capsule button (since removed) and a −48 pt swing on the attention chip
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

/// `DSSlidingSegmented<T: Hashable>` — a flat-track segmented control (MOCKUP-DEVIATIONS-REVIEW) with
/// a sliding capsule thumb (never a per-button background). The
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
    /// The shared window header's «This Mac | iPhone» switch (capsule table S5, 01-window-chrome.md):
    /// 13 / 600, segment padding 8 × 16.
    case header
    /// In-card controls (metric pickers, folder tabs): the default, tighter fit.
    case card
    /// Settings row segment (REDESIGN-SETTINGS, `Settings.dc.html:87-90`): 12.5 / 600, segment height 24 (padding 4.5 × 12), gap 2.
    case settingsRow
    /// Section page card trailing control (REDESIGN-CPU, 00-shared §8): 12.5 / 600, segment padding 6 × 12.
    case section

    var font: Font {
        switch self {
        case .tabs: return .system(size: 12.5, weight: .semibold)
        case .header: return .system(size: 13, weight: .semibold)
        case .card: return .system(size: 11, weight: .semibold)
        case .settingsRow: return .system(size: 12.5, weight: .semibold)
        case .section: return .system(size: 12.5, weight: .semibold)
        }
    }
    var hPad: CGFloat {
        switch self {
        case .tabs: return 16
        case .header: return 16
        case .card: return 11
        case .settingsRow: return 12
        case .section: return 12
        }
    }
    var vPad: CGFloat {
        switch self {
        case .tabs: return 6
        case .header: return 8
        case .card: return 5
        case .settingsRow: return 4.5
        case .section: return 6
        }
    }
    /// Gap between segments, matching the prototype track's `gap` (2px for
    /// tabs/card/settings row).
    var gap: CGFloat {
        switch self {
        case .tabs: return 2
        case .header: return 2
        case .card: return 2
        case .settingsRow: return 2
        case .section: return 2
        }
    }
}

/// Applies `.accessibilityIdentifier` only when `id` is non-nil, so a `nil`
/// identifier leaves a segment exactly as it was before (no empty-string
/// identifier set).
private struct DSOptionalAXIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

/// Makes the control one AX container labelled `label` (the group name
/// VoiceOver announces on entry) while each segment keeps its own label.
/// Without `.contain`, a label applied to the control from outside is passed
/// down to every segment and replaces its name (A11Y-SEGMENTS). `nil` leaves
/// the control exactly as before (no container element). The branch depends
/// only on whether the call site passed a label, never on runtime state, so it
/// does not break the control's identity (rule control-identity-branch).
private struct DSOptionalAXGroupLabel: ViewModifier {
    let label: String?
    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
        } else {
            content
        }
    }
}

struct DSSlidingSegmented<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    let size: DSSegmentedSize
    /// Group name for the whole control (e.g. «Период графика истории»), set on
    /// an `.accessibilityElement(children: .contain)` container. Pass it here,
    /// never as `.accessibilityLabel` on the control from outside: that label
    /// would replace every segment's own name. `nil` = no container element.
    let groupLabel: String?
    /// Optional stable AX identifier per segment (VISUAL-COVERAGE Amendment 1):
    /// `.accessibilityLabel` below lands in AXAttributedDescription, which
    /// System Events (osascript UI automation) cannot read — `AXIdentifier` is
    /// the language-independent, script-readable handle. `nil` for every
    /// existing call site (no identifier set, unchanged from before).
    let identifier: (T) -> String?
    /// REDESIGN-HISTORY: segments that cannot be chosen (History ranges longer than the data). Default: none.
    let disabled: (T) -> Bool
    /// `.help` shown on every disabled segment (one reason for all of them), nil = no tooltip.
    let disabledHelp: String?

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
    /// Called when the already-selected segment is clicked again (selection does not change).
    private let onReselect: ((T) -> Void)?

    init(options: [T], selection: Binding<T>, size: DSSegmentedSize = .card,
         groupLabel: String? = nil,
         identifier: @escaping (T) -> String? = { _ in nil },
         disabled: @escaping (T) -> Bool = { _ in false }, disabledHelp: String? = nil,
         onReselect: ((T) -> Void)? = nil, label: @escaping (T) -> String) {
        self.options = options
        self._selection = selection
        self.size = size
        self.groupLabel = groupLabel
        self.identifier = identifier
        self.disabled = disabled
        self.disabledHelp = disabledHelp
        self.onReselect = onReselect
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
                        .foregroundStyle(option == selection ? DS3.ink : DS3.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, size.hPad)
                        .padding(.vertical, size.vPad)
                        .contentShape(Rectangle())
                        // macOS shows no help tag on a disabled button, so the tooltip sits on the label
                        // view, which stays hit-testable (History.dc.html:82 `title` on a wrapper).
                        .help(disabled(option) ? (disabledHelp ?? "") : "")
                }
                .buttonStyle(.plain)
                .disabled(disabled(option))
                .opacity(disabled(option) ? 0.45 : 1)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(option == selection ? .isSelected : [])
                .modifier(DSOptionalAXIdentifier(id: identifier(option)))
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
        .modifier(DSOptionalAXGroupLabel(label: groupLabel))
    }

    /// Mockup track (S:87, CPU:67, I:197): flat `--field` fill with a 1 pt inset `--line` ring. The card/header
    /// tracks' `inset 0 1px 3px rgba(0,0,0,.08)` is not drawn (MOCKUP-DEVIATIONS-REVIEW D2).
    private var track: some View {
        // `.circular`: the default (continuous) capsule stroke leaves square nubs at both ends (see `DS3Switch`).
        Capsule(style: .circular).fill(DS3.field)
            .ds3InsetRims(Capsule(style: .circular), ring: DS3.line, ringWidth: 1)
    }

    /// Mockup lens (S:88, H:124): `--lens` fill, `inset 0 1px 0 rim-hi`, `inset 0 0 0 .5px rim-mid`, `--lens-sh`
    /// (= `DS3Shadow.lens`). Same recipe as the Settings sidebar pill (`SettingsView.navRow`).
    private var thumb: some View {
        Capsule(style: .circular).fill(DS3.lens)
            .ds3InsetRims(Capsule(style: .circular), top: DS3.rimHi, ring: DS3.rimMid)
            .ds3Elevation(.lens, in: Capsule(style: .circular))
    }

    private func select(_ option: T) {
        guard !disabled(option) else { return }
        guard option != selection else {
            onReselect?(option)
            return
        }
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
/// an outer glow or shadow survive on the edges left at their default 0.
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
