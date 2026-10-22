// Views/SectionListBlocks.swift
// REDESIGN-SYSTEM: the shared list blocks of the section pages (00-shared §8) — the list container and row moved
// out of SecurityPage.swift (`SectionList`, `SectionListRow`) plus the three new blocks of the System page:
// Rows (`SectionRows`/`SectionRowsRow`), the collapsible Pills group (`SectionCollapsibleGroup` + `SectionPill`)
// and the inline Confirm (`SectionConfirmPanel`). All colours DS3; text roles use the `-ink` variants
// (`light-theme-ink-variants`); every curve branches on Reduce Motion (`reduce-motion`).

import SwiftUI

// MARK: - Motion helpers

/// Row insert/remove curve (00-shared §8 Rows): 0.25 s ease-out, 0.12 s under Reduce Motion.
func sectionRowAnimation(reduceMotion: Bool) -> Animation {
    .easeOut(duration: reduceMotion ? 0.12 : 0.25)
}

/// Row insert/remove transition: fade + slide from the top; opacity only under Reduce Motion.
func sectionRowTransition(reduceMotion: Bool) -> AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
}

// MARK: - List container and row (moved from SecurityPage.swift)

/// The `BatteryHistoryCard.list` container: padding 6, radius 22, `DS3.row`, rows spaced 4.
/// `ring` adds the mockup's .5 pt `line` inner stroke; the System page sets it, Security keeps its existing look.
struct SectionList<Content: View>: View {
    var ring = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 4) { content() }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
            .ds3InsetRims(RoundedRectangle(cornerRadius: 22, style: .continuous), ring: ring ? DS3.line : nil)
    }
}

struct SectionListRow: View {
    let dot: Color
    let name: String
    let sub: String
    let value: String
    /// The mockup's row: the name takes the free width and the secondary text sits right of it, before the value
    /// column. Default false keeps the Security rows (secondary text right after the name).
    var subTrailing = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .help(name)
            if subTrailing { Spacer(minLength: 8) }
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
            }
            if !subTrailing { Spacer(minLength: 8) }
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }
}

// MARK: - Rows

/// Rows container: the same surface as `SectionList`.
struct SectionRows<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        SectionList(ring: true, content: content)
    }
}

/// One row of a Rows block: optional icon, a name over a wrapping sub line (two lines, as in the mockup), trailing
/// control.
/// No hover — the rows are not buttons.
struct SectionRowsRow<Trailing: View>: View {
    var icon: String? = nil
    var tint: Color = DS3.amber
    let name: String
    var nameMono = false
    var sub: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(nameMono ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 14))
                    .foregroundStyle(DS3.ink)
                    .lineLimit(1)
                    .help(name)
                if let sub, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS3.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing().fixedSize()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Collapsible group

/// A collapsible group header + body (Pills group, Hidden group). The header is a button; the body keeps the
/// `openAmount` disclosure recipe of the retired `AutoSectionRow`: ONE `openAmount` drives the body's
/// `.frame(height:)`, opacity and rise, committed by a SINGLE explicit `withAnimation` in `.onChange(of: isOpen)`,
/// with no `.animation(value:)` and no `.transition` anywhere on the collapsing subtree (`shared-vocabulary`).
/// Two constraints on what may go inside the body: it must have no height-flexible children (no bare `Spacer`,
/// nothing that consumes `proposal.height`), because the measured natural height is read under the clamped frame;
/// and an async result must not be written while a disclosure transaction is open (`async-disclosure-settled`).
struct SectionCollapsibleGroup<Content: View>: View {
    let title: String
    let count: Int?
    var warn: String?
    @Binding var isOpen: Bool
    var enabled: Bool
    var bodyInset: CGFloat
    /// Pills: right 10 / bottom 8; Hidden rows: right 0 / bottom 4 (mockup `0 10px 8px 30px` / `0 0 4px 20px`).
    var bodyTrailing: CGFloat
    var bodyBottom: CGFloat
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openAmount: Double
    /// Natural (fully-open) height of the body, captured by `.onGeometryChange`. `nil` until the first callback:
    /// an already-open group imposes no height constraint for that frame, a closed one gets a hard 0.
    @State private var measuredHeight: CGFloat?

    init(title: String, count: Int?, warn: String? = nil, isOpen: Binding<Bool>, enabled: Bool = true,
         bodyInset: CGFloat = 20, bodyTrailing: CGFloat = 10, bodyBottom: CGFloat = 8,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.warn = warn
        self._isOpen = isOpen
        self.enabled = enabled
        self.bodyInset = bodyInset
        self.bodyTrailing = bodyTrailing
        self.bodyBottom = bodyBottom
        self.content = content
        // Seed from the CURRENT binding so a group that starts open renders fully open on the first frame.
        self._openAmount = State(initialValue: isOpen.wrappedValue ? 1 : 0)
    }

    private var curve: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .easeOut(duration: 0.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content()
                .padding(.top, 8)
                .padding(.leading, bodyInset)
                .padding(.trailing, bodyTrailing)
                .padding(.bottom, bodyBottom)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
                    // Settled and open: track the body's own size changes (a row leaving) with the same curve.
                    if openAmount == 1 {
                        withAnimation(curve) { measuredHeight = newHeight }
                    } else {
                        measuredHeight = newHeight
                    }
                }
                .frame(height: measuredHeight.map { $0 * openAmount } ?? (openAmount == 0 ? 0 : nil), alignment: .top)
                .clipped()
                .opacity(openAmount)
                .offset(y: reduceMotion ? 0 : -6 * (1 - openAmount))
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS3.lens).opacity(openAmount)
        )
        // Backstop for the rise offset: re-clip to the animated frame so no sliver pokes above the header.
        .clipped()
        .onChange(of: isOpen) { _, newValue in
            withAnimation(curve) { openAmount = newValue ? 1 : 0 }
        }
    }

    private var header: some View {
        Button {
            if enabled { isOpen.toggle() }
        } label: {
            HStack(spacing: 9) {
                GroupChevron()
                    .stroke(DS3.muted, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(90 * openAmount))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(enabled ? DS3.ink : DS3.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let warn {
                    Text(warn)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS3.amberInk)
                        .lineLimit(1)
                }
                if let count {
                    Text("(\(count))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS3.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(isOpen ? L.sysGroupExpandedA11y : L.sysGroupCollapsedA11y)
        .accessibilityAddTraits(enabled ? .isButton : [])
    }
}

/// The mockup's 11 x 11 group chevron (`M3.5 2l3.5 3.5L3.5 9`, stroke 1.6) — thinner than the SF Symbol.
private struct GroupChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 11
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 3.5 * k, y: rect.minY + 2 * k))
        p.addLine(to: CGPoint(x: rect.minX + 7 * k, y: rect.minY + 5.5 * k))
        p.addLine(to: CGPoint(x: rect.minX + 3.5 * k, y: rect.minY + 9 * k))
        return p
    }
}

// MARK: - Pill

/// Name pill of a Pills group; a stale one carries the amber ⚠ treatment. `.help` shows the details.
struct SectionPill: View {
    let text: String
    var stale = false
    var help = ""

    var body: some View {
        HStack(spacing: 5) {
            if stale {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12.5))
                .lineLimit(1)
        }
        .foregroundStyle(stale ? DS3.amberInk : DS3.inkSoft)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(stale ? DS3.amber.opacity(0.12) : DS3.chip))
        .ds3InsetRims(Capsule(), ring: stale ? DS3.amber.opacity(0.50) : DS3.lineStrong)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityHint(help)
    }
}

// MARK: - Confirm panel

/// Inline confirm (the `StoragePage.confirmPanel` recipe): title, one paragraph per kind, optional note, Cancel
/// (default action, focused on appear, Esc cancels) and a confirm button that swaps for a spinner while `busy`.
/// The caller wraps the appearance in `withAnimation(DS3Motion.popIn)` (Reduce Motion: `.easeOut(0.12)`) and sets
/// `router.isInlineConfirmOpen` while it is shown.
struct SectionConfirmPanel: View {
    let title: String
    let paragraphs: [String]
    var note: String? = nil
    let cancelTitle: String
    let confirmTitle: String
    var confirmKind: DS3ButtonStyle.Kind = .dangerSolid
    var busy = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var cancelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS3.ink)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(DS3.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let note {
                Text(note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS3.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(cancelTitle) { onCancel() }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                    .keyboardShortcut(.defaultAction)
                    .focused($cancelFocused)
                    .accessibilityLabel(cancelTitle)
                    .background {
                        Button("") { onCancel() }
                            .keyboardShortcut(.cancelAction)
                            .accessibilityLabel(cancelTitle)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                Button(action: onConfirm) {
                    Text(confirmTitle).dsSwapInPlace(busy) { ProgressView().controlSize(.small).tint(.white) }
                }
                .buttonStyle(DS3ButtonStyle(kind: confirmKind, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(busy)
                .accessibilityLabel(confirmTitle)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.overlay))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), top: DS3.rimMid, ring: DS3.lineStrong)
        .onExitCommand { onCancel() }
        .onAppear { cancelFocused = true }
    }
}
