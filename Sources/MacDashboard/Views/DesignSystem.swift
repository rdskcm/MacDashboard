// Views/DesignSystem.swift
// Block V2-FOUND: v2.0 design-system motion constants, disclosure transition, in-place swap and bleed clip.
// Pure SwiftUI Views code (not Foundation-only) — deliberately app-only, not
// covered by Tests/MacDashboardTests (see PLAN.md block spec: the tested Engine code stays Foundation-only).
//
// Reduce Motion contract (project-wide, wired here as a deliverable of this block):
// keyframe-style/transform animations play once at ~0 ms (i.e. no animation) under
// `@Environment(\.accessibilityReduceMotion)`; only 0.12 s color/opacity/border/
// shadow transitions remain. Every modifier below reads the environment value
// where it matters and degrades accordingly.

import SwiftUI

// MARK: - Motion constants

/// Named animation curves shared across the v2.0 UI so no later block re-derives
/// timing. `reduceMotionFallback` is a plain duration (seconds) — callers pick
/// their own curve for it; the rest are ready-to-use `Animation`s.
enum DSMotion {
    static let expand = Animation.easeInOut(duration: 0.18)
    /// Paired with `.dsDisclosure(reduceMotion:)`: the disclosed content rises by
    /// this many points while it fades in/out.
    static let discloseRiseY: CGFloat = -7
    /// Reduce Motion fallback duration for color/opacity/border/shadow transitions.
    static let reduceMotionFallback: Double = 0.12
}

// MARK: - Disclosure transition

/// Fade + slight rise, shared by every collapse/expand disclosure in the v2.0 UI
/// (the process-row panels, SectionRows) so appearing/disappearing content reads as one
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
