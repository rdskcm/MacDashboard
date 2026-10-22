// Views/SectionPageBlocks.swift
// REDESIGN-CPU: the shared §8 section-page blocks (00-shared §8) — page bar, hero, tile, note, wait,
// hero/tiles split layout and the deep-link focus pulse. The CPU page is the first consumer; pages 04–10
// use them too. All colours DS3; text roles use the `-ink` variants
// (`light-theme-ink-variants`).

import SwiftUI

// MARK: - Page bar

/// Pinned frosted bar (00 §4.2 / §8), the shape of `IPhoneDeviceView.header`: Back chip, icon, title,
/// sub line, tag, then a trailing slot (Refresh) after the spacer.
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
            tag()
                .layoutPriority(1)
            Spacer(minLength: 0)
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
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toneInk)
            Text(value)
                .font(.system(size: 40, weight: .bold))
                .tracking(-1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(dimmed ? DS3.muted : DS3.ink)
            Spacer(minLength: 0)
            DS3Bar(fraction: fraction, height: 8, fill: AnyShapeStyle(tone))
            Text(note)
                .font(.system(size: 12.5))
                .foregroundStyle(DS3.muted)
                .lineLimit(2)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS3.inkSoft)
                    .lineLimit(1)
                if let dot {
                    Circle().fill(dot)
                        .frame(width: 7, height: 7)
                        .background(Circle().fill(dot.opacity(0.22)).frame(width: 13, height: 13))
                }
            }
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(valueInk)
                .lineLimit(1)
            if let note {
                Text(note)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(noteInk)
                    .lineLimit(1)
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

/// Tinted note with an optional action button (the CPU failed state's «Try again»).
struct SectionNote: View {
    let tone: Color
    let text: String
    var button: (title: String, a11y: String, busy: Bool, action: () -> Void)? = nil
    var buttonIdentifier: String? = nil
    /// REDESIGN-SECURITY: «Install…» is a primary button; every older call site keeps the secondary one.
    var primary = false
    /// REDESIGN-BACKUPS: a disabled button («Back up now» with the disk unplugged) and its tooltip.
    var buttonDisabled = false
    var buttonHelp: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(tone).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(DS3.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let button {
                // Opacity ZStack: the label swaps for a spinner without changing the width (`swap-in-place`).
                Button(action: button.action) {
                    ZStack {
                        Text(button.title).opacity(button.busy ? 0 : 1)
                        ProgressView().controlSize(.small).opacity(button.busy ? 1 : 0)
                    }
                }
                .buttonStyle(DS3ButtonStyle(kind: primary ? .primary : .secondary, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(button.busy || buttonDisabled)
                .accessibilityLabel(button.a11y)
                .accessibilityIdentifier(buttonIdentifier ?? "")
            }
        }
        // A disabled macOS button shows no help tag, so the tooltip sits on the container.
        .help(buttonHelp ?? "")
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
            ProgressView().controlSize(.small)
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
