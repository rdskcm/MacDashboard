// Views/SectionPageBlocks.swift
// REDESIGN-CPU: the shared §8 section-page blocks (00-shared §8) — page bar, hero, tile, note, wait,
// hero/tiles split layout and the deep-link focus pulse. The CPU page is the first consumer; pages 04–10
// use them too. All colours DS3; text roles use the `-ink` variants
// (`light-theme-ink-variants`).

import SwiftUI
import AppKit

// MARK: - Page bar

/// Pinned frosted bar (00 §4.2 / §8), the shape of `IPhoneDeviceView.header`: Back chip, icon, title,
/// sub line, then after the spacer the tag and the trailing slot (Refresh).
@MainActor
struct SectionPageBar<Tag: View, Trailing: View>: View {
    let symbol: String
    let title: String
    let sub: String?
    var subIsFailure = false
    let onBack: () -> Void
    @ViewBuilder var tag: () -> Tag
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            back
            HomeIconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.4)
                    .lineLimit(1)
                if let sub {
                    Text(sub)
                        .font(.system(size: 13))
                        .foregroundStyle(subIsFailure ? DS3.hotInk : DS3.muted)
                        .lineLimit(1)
                        .help(sub)
                }
            }
            Spacer(minLength: 0)
            tag()
                .layoutPriority(1)
            trailing()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background { DS3GlassBar() }
        .overlay(alignment: .bottom) { Rectangle().fill(DS3.line).frame(height: 1) }
    }

    private var back: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                Text(L.commonThisMac)
            }
            .padding(.leading, -4)
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 13, topRim: 1))
        .accessibilityLabel(L.homeBackA11y)
        .accessibilityIdentifier("page-back")
        .layoutPriority(1)
    }
}

// MARK: - Hero

/// Big figure with a bar and a note, on a tinted panel.
struct SectionHero: View {
    let label: String
    let value: String
    let fraction: Double
    let note: String
    let tone: Color
    let toneInk: Color
    /// Bar colour when it differs from the panel tint (the GPU hero: blue panel, lime bar).
    var barTone: Color? = nil
    var dimmed = false

    var body: some View {
        // Gaps of 10 pt are explicit paddings, so the Spacer adds one gap (min 10) between value and bar, not two
        // (147 pt with a one-line note, CPU:77-81).
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toneInk)
                .frame(height: 19)
            Text(value)
                .font(.system(size: 40, weight: .bold))
                .tracking(-1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(dimmed ? DS3.muted : DS3.ink)
                .frame(height: 40)
                .padding(.top, 10)
            Spacer(minLength: 10)
            DS3Bar(fraction: fraction, height: 8, fill: AnyShapeStyle(barTone ?? tone))
            Text(note)
                .font(.system(size: 12.5))
                .foregroundStyle(DS3.muted)
                .lineLimit(2)
                .frame(minHeight: 18)
                .padding(.top, 10)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ds3TintPanel(tone, from: 0.16, to: 0.06, ring: 0.40, cornerRadius: 20, top: DS3.rimMid)
    }
}

// MARK: - Tile

/// Small stat tile: label (with an optional status dot), value, optional note.
struct SectionTile: View {
    let label: String
    let value: String
    var note: String? = nil
    var noteInk: Color = DS3.greenInk
    var dot: Color? = nil
    var valueInk: Color = DS3.ink
    /// SERIAL-MASK-LAST4: optional control in the label row, right-aligned (the Battery serial tile's Show / Hide and
    /// copy). nil everywhere else, so every other tile renders exactly as before. It is laid out in the label's
    /// 19 pt and offset, so it adds no height; its trailing edge sits 5 pt in from the tile's right edge (the 30 pt
    /// circle is concentric with the 20 pt corner) and its centre 20 pt below the top edge.
    var labelAccessory: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                if let dot {
                    Circle().fill(dot)
                        .frame(width: 7, height: 7)
                        .background(Circle().fill(dot.opacity(0.22)).frame(width: 13, height: 13))
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS3.inkSoft)
                    .lineLimit(1)
                    .frame(height: 19)
                    // Pushes the accessory right. A Spacer here would add a second 7 pt of row spacing.
                    .frame(maxWidth: labelAccessory == nil ? nil : .infinity, alignment: .leading)
                if let labelAccessory {
                    // 11 = 16 tile padding - 5 inset; 3.5 = 23.5 label line centre - 20 corner centre.
                    labelAccessory.frame(height: 19).padding(.trailing, -11).offset(y: -3.5).layoutPriority(1)
                }
            }
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(valueInk)
                .lineLimit(1)
                .frame(height: 25)
            if let note {
                Text(note)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(noteInk)
                    .lineLimit(1)
                    .frame(height: 18)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), top: DS3.rimLo, ring: DS3.line)
    }
}

// MARK: - Note

/// Tinted note with an optional action button (e.g. the folder-count failure's «Try again» on Storage).
struct SectionNote: View {
    let tone: Color
    let text: String
    var button: (title: String, a11y: String, busy: Bool, action: () -> Void)? = nil
    var buttonIdentifier: String? = nil
    /// REDESIGN-SECURITY: «Install…» is a primary button; every older call site keeps the secondary one.
    var primary = false

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(tone).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(DS3.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let button {
                // The label swaps for a spinner without changing the width (`swap-in-place`).
                Button(action: button.action) {
                    Text(button.title).dsSwapInPlace(button.busy) {
                        DS3Spinner(role: primary ? .onSolid : .softRing, size: 12)
                    }
                }
                .buttonStyle(DS3ButtonStyle(kind: primary ? .primary : .secondary, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(button.busy)
                .accessibilityLabel(button.a11y)
                .ds3BusyValue(button.busy)
                .accessibilityIdentifier(buttonIdentifier ?? "")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .ds3TintPanel(tone, from: 0.16, to: 0.06, ring: 0.42, cornerRadius: 20)
    }
}

// MARK: - Wait

/// «Collecting data…» block for a card whose data has not arrived yet.
struct SectionWait: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            DS3Spinner(role: .track, size: 14)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(DS3.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: - Hero / tiles split

/// Two subviews: hero (left) and tiles (right). Widths come from the proposed width only
/// (`CPUPageModel.heroWidths`), never from a measurement of the subviews (`no-measured-size-feedback`,
/// `equal-split-columns`, `hstack-frame-priority-trap`).
struct HeroSplitLayout: Layout {
    private func widths(_ proposal: ProposedViewSize) -> (hero: CGFloat, tiles: CGFloat) {
        let total: CGFloat
        if let w = proposal.width, w.isFinite { total = w } else { total = 600 }
        return CPUPageModel.heroWidths(total: total)
    }

    private func height(_ subviews: Subviews, _ w: (hero: CGFloat, tiles: CGFloat)) -> CGFloat {
        guard subviews.count == 2 else { return 0 }
        return max(
            subviews[0].sizeThatFits(ProposedViewSize(width: w.hero, height: nil)).height,
            subviews[1].sizeThatFits(ProposedViewSize(width: w.tiles, height: nil)).height
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = widths(proposal)
        return CGSize(width: w.hero + 8 + w.tiles, height: height(subviews, w))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let w = CPUPageModel.heroWidths(total: bounds.width)
        let h = height(subviews, w)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: w.hero, height: h))
        subviews[1].place(at: CGPoint(x: bounds.minX + w.hero + 8, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: w.tiles, height: h))
    }
}

// MARK: - Focus pulse

extension View {
    /// SECURITY-IDLE-COST F5: keeps a deep link's focus scroll on its card while the page's content is still taking its
    /// size. Measured on the first visit after launch (Battery, fixture): the page's one `proxy.scrollTo` leaves the page at
    /// offset 0, while a repeat visit scrolls (270 pt). While `focus` (the page's pulse, a scroll-needing card, not `top`) is
    /// set, every content-height change repeats the `scrollTo`; the user scrolling, clicking or pressing a key ends it for
    /// that focus.
    func ds3KeepFocusScroll(_ focus: CardID?, top: CardID, proxy: ScrollViewProxy, router: NavigationRouter) -> some View {
        modifier(KeepFocusScroll(focus: focus == top ? nil : focus, proxy: proxy, router: router))
    }
}

private struct KeepFocusScroll: ViewModifier {
    let focus: CardID?
    let proxy: ScrollViewProxy
    let router: NavigationRouter
    @State private var userActed = false
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height }) { _, _ in
                guard let focus, !userActed, !router.isInlineConfirmOpen else { return }
                proxy.scrollTo(focus, anchor: .top)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating { userActed = true }
            }
            .onChange(of: focus) { _, new in
                userActed = false
                removeMonitor()
                guard new != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { e in
                    userActed = true
                    return e
                }
            }
            .onDisappear { removeMonitor() }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    /// Deep-link focus ring: a 3 pt accent ring on the card; `active` flips true when the page was opened
    /// with this card as `focus`. Opacity only, no geometry depends on it (`animation-value-size-coupling`).
    func sectionFocusPulse(_ active: Bool, cornerRadius: CGFloat = 30) -> some View {
        modifier(SectionFocusPulse(active: active, cornerRadius: cornerRadius))
    }
}

private struct SectionFocusPulse: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat
    @State private var ring = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS3.accent, lineWidth: 3)
                    .opacity(ring)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .task(id: active) {
                guard active, !DS3Motion.isFrozen else { ring = 0; return }
                if reduceMotion {
                    ring = 1
                    try? await Task.sleep(for: .seconds(1.5))
                    ring = 0
                } else {
                    try? await Task.sleep(for: .seconds(0.45))
                    ring = 1
                    try? await Task.sleep(for: .seconds(1.3))
                    withAnimation(.easeOut(duration: 0.9)) { ring = 0 }
                }
            }
    }
}
