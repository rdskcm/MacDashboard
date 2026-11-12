// Views/IPhoneTileMenu.swift
// IPHONE-UNLINK: the device tile's «⋯» button and the mockup's menu panel — Open, Unlink device…, and the inline
// confirm (mockup §3.2, iPhone Module v3 :103, :138-153). The list page places the panel (IPhoneModeView, B4).
import SwiftUI

enum IPhoneTileMenuMetrics {
    static let panelTop: CGFloat = 58        // mockup `top:58px` inside the tile
    static let panelTrailing: CGFloat = 16   // mockup `right:16px`
    static let radius: CGFloat = 22
    static let padding: CGFloat = 6
    static let menuMinContent: CGFloat = 168 // 180 − 2 × 6
    static let contentMax: CGFloat = 268     // 280 − 2 × 6
    static let button: CGFloat = 34

    /// Top-trailing corner of the panel in the list's coordinates for a tile whose resting frame is `tile`.
    /// `lifted` (the tile is pinned in its hover pose, Reduce Motion off): the corner moves with the tile's
    /// `scaleEffect(tileHoverScale)` about its centre and `offset(y: tileHoverLift)`, as the mockup's panel does as a
    /// child of the lifted tile.
    static func panelAnchor(tile r: CGRect, lifted: Bool) -> CGPoint {
        let p = CGPoint(x: r.maxX - panelTrailing, y: r.minY + panelTop)
        guard lifted else { return p }
        let s = DS3Motion.tileHoverScale
        return CGPoint(x: r.midX + s * (p.x - r.midX), y: r.midY + s * (p.y - r.midY) + DS3Motion.tileHoverLift)
    }
}

/// The three dots, centred by their rendered ink in the 34-pt circle (not by a text baseline).
struct IPhoneTileMenuGlyph: View {
    /// SF Symbol point size giving an 18 × 4 pt ink box (mockup: three 4-pt dots, gap 3). Measured by
    /// `IPhoneTileMenuGlyphSnapshotTests`; start value 15.
    static let fontSize: CGFloat = 18.5
    /// Correction so the ink's centre is the circle's centre; measured by the same test (dx -0.25, dy 0.5 at the 18.5-pt size).
    static let opticalOffset = CGSize(width: 0.25, height: -0.5)
    var ink: Color

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: Self.fontSize, weight: .bold))
            .foregroundStyle(ink)
            .offset(Self.opticalOffset)
            .frame(width: IPhoneTileMenuMetrics.button, height: IPhoneTileMenuMetrics.button, alignment: .center)
            .accessibilityHidden(true)
    }
}

struct IPhoneTileMenuButton: View {
    let name: String
    let open: Bool
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        Button(action: onTap) { IPhoneTileMenuGlyph(ink: hover ? DS3.ink : DS3.inkSoft) }
            .buttonStyle(DS3CircleButtonStyle(diameter: IPhoneTileMenuMetrics.button, ring: DS3.line,
                                              fill: open ? DS3.chip : .clear))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.25), value: hover)
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.2), value: open)
            .accessibilityLabel(L.iphoneTileActionsA11y(name))
            .help(L.iphoneTileActionsA11y(name))
    }
}

/// Menu or inline confirm on the mockup's panel surface. Internal so the snapshot suite renders it standalone.
struct IPhoneTileMenuPanel: View {
    let name: String
    let keptArchives: Int
    let unlinkAllowed: Bool
    @Binding var asking: Bool
    let onOpen: () -> Void
    let onUnlink: () -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var voFirst: Bool

    var body: some View {
        Group {
            if asking { confirm } else { menu }
        }
        .padding(IPhoneTileMenuMetrics.padding)
        .ds3PopPanel(cornerRadius: IPhoneTileMenuMetrics.radius)
        .background {
            // Esc, the `SectionConfirmPanel` recipe.
            Button("") { onClose() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onExitCommand { onClose() }
        .onAppear { focused = true; voFirst = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.iphoneTileActionsA11y(name))
        .accessibilityAddTraits(.isModal)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(L.iphoneTileOpen) { onOpen() }
                .buttonStyle(IPhoneTileMenuRowStyle(ink: DS3.ink, hoverFill: DS3.row))
                .accessibilityLabel(L.iphoneTileOpen)
                .accessibilityFocused($voFirst)
            unlinkRow
        }
        .frame(minWidth: IPhoneTileMenuMetrics.menuMinContent, maxWidth: IPhoneTileMenuMetrics.contentMax,
               alignment: .leading)
    }

    @ViewBuilder private var unlinkRow: some View {
        let row = Button(L.iphoneUnlinkDevice) { asking = true }
            .buttonStyle(IPhoneTileMenuRowStyle(ink: DS3.hotInk, hoverFill: DS3.hot.opacity(0.12)))
            .disabled(!unlinkAllowed)
            .opacity(unlinkAllowed ? 1 : 0.45)
            .accessibilityLabel(L.iphoneUnlinkDevice)
        if unlinkAllowed {
            row
        } else {
            // The tooltip sits on a wrapper: a disabled AppKit control may not show its own.
            HStack(spacing: 0) { row }
                .contentShape(Rectangle())
                .help(L.iphoneUnlinkBusyHelp)
        }
    }

    private var confirm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.iphoneUnlinkTitle(name))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(DS3.ink)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($voFirst)
                Text(keptArchives > 0 ? L.iphoneUnlinkBody + " " + L.iphoneUnlinkArchives(keptArchives) : L.iphoneUnlinkBody)
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L.iphoneUnlinkCancel) { onClose() }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, topRim: 0))
                    .accessibilityLabel(L.iphoneUnlinkCancel)
                // No keyboard shortcut (Decision 5): Return does nothing.
                Button(L.iphoneUnlinkConfirm) { onClose(); onUnlink() }
                    .buttonStyle(DS3ButtonStyle(kind: .dangerSolid, height: 32, hPad: 14, topRim: 0))
                    .accessibilityLabel(L.iphoneUnlinkConfirmA11y(name))
            }
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 6, trailing: 10))
        .frame(width: IPhoneTileMenuMetrics.contentMax, alignment: .leading)
    }
}

/// Menu row: 14 / 600, full width, radius 16, hover fill, press scale (mockup :149-150).
struct IPhoneTileMenuRowStyle: ButtonStyle {
    let ink: Color
    let hoverFill: Color

    func makeBody(configuration: Configuration) -> some View {
        IPhoneTileMenuRowBody(configuration: configuration, ink: ink, hoverFill: hoverFill)
    }
}

private struct IPhoneTileMenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    let ink: Color
    let hoverFill: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(shape.fill(hover && isEnabled ? hoverFill : .clear))
            .contentShape(shape)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.2), value: hover)
            .scaleEffect(configuration.isPressed && !reduceMotion ? DS3Motion.pressScale : 1)
            .animation(reduceMotion ? nil : DS3Motion.press, value: configuration.isPressed)
    }
}
