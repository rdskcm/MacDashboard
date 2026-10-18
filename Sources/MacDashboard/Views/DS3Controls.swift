// Views/DS3Controls.swift
// IPHONE-DESIGN: DS v3 controls (buttons, tag, card, bar, phone glyph). Used by iPhone mode;
// APP-REDESIGN will reuse them later.

import SwiftUI

// MARK: - Buttons

struct DS3ButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger, text }

    var kind: Kind
    var height: CGFloat
    var hPad: CGFloat
    var fontSize: CGFloat = 13
    var glow = false
    var topRim: Double = 0.6
    var disabledOpacity: Double = 0.45

    func makeBody(configuration: Configuration) -> some View {
        DS3ButtonBody(configuration: configuration, style: self)
    }
}

private struct DS3ButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: DS3ButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        base
            .scaleEffect(configuration.isPressed && !reduceMotion ? DS3Motion.pressScale : 1)
            .animation(reduceMotion ? nil : DS3Motion.press, value: configuration.isPressed)
            .opacity(isEnabled ? 1 : style.disabledOpacity)
    }

    @ViewBuilder private var base: some View {
        switch style.kind {
        case .primary:
            if style.glow {
                primary.ds3Elevation(.primaryGlow, in: Capsule())
            } else {
                primary
            }
        case .secondary:
            label(DS3.ink)
                .background(Capsule().fill(DS3.chip))
                .ds3InsetRims(Capsule(), top: style.topRim > 0 ? DS3.rimMid : nil, ring: DS3.lineStrong)
                .contentShape(Capsule())
        case .danger:
            label(DS3.hotInk)
                .background(Capsule().fill(DS3.hot.opacity(0.14)))
                .ds3InsetRims(Capsule(), ring: DS3.hot.opacity(0.45))
                .contentShape(Capsule())
        case .text:
            label(DS3.accentInk)
                .background(Capsule().fill(hover ? DS3.chip : Color.clear))
                .contentShape(Capsule())
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
        }
    }

    private var primary: some View {
        label(.white)
            .background(
                Capsule().fill(
                    LinearGradient(
                        stops: [.init(color: DS3.primaryTop, location: 0), .init(color: DS3.accentSolid, location: 0.62)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .ds3InsetRims(Capsule(), top: .white.opacity(style.topRim))
            .contentShape(Capsule())
    }

    private func label(_ ink: Color) -> some View {
        configuration.label
            .font(.system(size: style.fontSize, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, style.hPad)
            .frame(height: style.height)
    }
}

struct DS3CircleButtonStyle: ButtonStyle {
    var diameter: CGFloat
    var disabledOpacity: Double = 0.45

    func makeBody(configuration: Configuration) -> some View {
        DS3CircleButtonBody(configuration: configuration, style: self)
    }
}

private struct DS3CircleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: DS3CircleButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .frame(width: style.diameter, height: style.diameter)
            .background(Circle().fill(DS3.chip))
            .ds3InsetRims(Circle(), ring: DS3.line)
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? DS3Motion.pressScale : 1)
            .animation(reduceMotion ? nil : DS3Motion.press, value: configuration.isPressed)
            .opacity(isEnabled ? 1 : style.disabledOpacity)
    }
}

/// Big device tile: lifts under the pointer, presses in on click. Hover probe stays on the resting frame
/// (`hover-offset-hit-test`): the outer wrapper owns `contentShape`/`onHover`, the inner content is offset.
struct DS3TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DS3TileButtonBody(configuration: configuration)
    }
}

private struct DS3TileButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        ZStack {
            configuration.label
                .geometryGroup()
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? DS3Motion.tilePressScale : (hover ? DS3Motion.tileHoverScale : 1)))
                .offset(y: (!reduceMotion && hover && !configuration.isPressed) ? DS3Motion.tileHoverLift : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : DS3Motion.tile, value: hover)
        .animation(reduceMotion ? nil : DS3Motion.tile, value: configuration.isPressed)
    }
}

// MARK: - Tag

struct DS3Tag: View {
    enum Tone { case accent, neutral, amber, hot, green }

    let tone: Tone
    let text: String
    var pulse = false
    var vPad: CGFloat = 4
    var hPad: CGFloat = 11

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Pulse {
        var scale: CGFloat = 1
        var opacity: Double = DS3Motion.pulseOpacityFrom
    }

    var body: some View {
        capsule(
            HStack(spacing: 7) {
                dot
                Text(text)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
            .padding(.vertical, vPad)
            .padding(.horizontal, hPad)
        )
    }

    private var ink: Color {
        switch tone {
        case .accent: return DS3.accentInk
        case .neutral: return DS3.inkSoft
        case .amber: return DS3.amberInk
        case .hot: return DS3.hotInk
        case .green: return DS3.greenInk
        }
    }

    private var dotColour: Color {
        switch tone {
        case .accent: return DS3.accent
        case .neutral: return DS3.muted
        case .amber: return DS3.amber
        case .hot: return DS3.hot
        case .green: return DS3.green
        }
    }

    @ViewBuilder private func capsule<C: View>(_ content: C) -> some View {
        switch tone {
        case .accent:
            content.ds3TintPanel(DS3.accent, from: 0.26, to: 0.11, ring: 0.45, cornerRadius: 999, top: .white.opacity(0.45))
        case .neutral:
            content
                .background(Capsule().fill(DS3.chip))
                .ds3InsetRims(Capsule(), top: DS3.rimMid, ring: DS3.lineStrong)
        case .amber:
            content.ds3TintPanel(DS3.amber, from: 0.26, to: 0.11, ring: 0.45, cornerRadius: 999, top: .white.opacity(0.40))
        case .hot:
            content.ds3TintPanel(DS3.hot, from: 0.26, to: 0.11, ring: 0.45, cornerRadius: 999, top: .white.opacity(0.40))
        case .green:
            content.ds3TintPanel(DS3.green, from: 0.26, to: 0.11, ring: 0.45, cornerRadius: 999, top: .white.opacity(0.40))
        }
    }

    private var dot: some View {
        Circle()
            .fill(dotColour)
            .frame(width: 7, height: 7)
            .background {
                if pulse && !reduceMotion && !DS3Motion.isFrozen {
                    KeyframeAnimator(initialValue: Pulse(), repeating: true) { v in
                        Circle().fill(DS3.accent).scaleEffect(v.scale).opacity(v.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(DS3Motion.pulseScale, duration: DS3Motion.pulseRise)
                            LinearKeyframe(DS3Motion.pulseScale, duration: DS3Motion.pulseHold)
                        }
                        KeyframeTrack(\.opacity) {
                            CubicKeyframe(0, duration: DS3Motion.pulseRise)
                            LinearKeyframe(0, duration: DS3Motion.pulseHold)
                        }
                    }
                }
            }
    }
}

// MARK: - Card

struct DS3Card<Trailing: View, Content: View>: View {
    let title: String
    var caption: String? = nil
    var spacing: CGFloat = 16
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.22)
                    .foregroundStyle(DS3.ink)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(DS3.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing().layoutPriority(1)
            }
            .frame(minHeight: 32)
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ds3GlassCard(cornerRadius: 30)
    }
}

extension DS3Card where Trailing == EmptyView {
    init(title: String, caption: String? = nil, spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, caption: caption, spacing: spacing, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Bar

/// Proportional bar. The fill is an `.overlay` with its own `GeometryReader`, so the bar never feeds
/// its measured size back into layout (`no-measured-size-feedback`).
struct DS3Bar: View {
    let fraction: Double
    var height: CGFloat = 5
    var fill: AnyShapeStyle
    var recessed = false

    var body: some View {
        Capsule().fill(DS3.track)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(fill).frame(width: g.size.width * min(max(fraction, 0), 1))
                }
            }
            .overlay {
                if recessed {
                    Capsule().stroke(Color.black.opacity(0.1), lineWidth: 2).blur(radius: 1).offset(y: 1).mask(Capsule())
                }
            }
    }
}

// MARK: - Phone glyph

/// The design's phone picture drawn from shapes; draws its own rounded box.
struct IPhoneGlyph: View {
    enum Size { case tile, header, notice }

    let size: Size
    let tint: Color
    var tinted: Bool

    private var box: CGFloat {
        switch size {
        case .tile: return 52
        case .header: return 44
        case .notice: return 72
        }
    }

    private var boxRadius: CGFloat {
        switch size {
        case .tile: return 18
        case .header: return 16
        case .notice: return 24
        }
    }

    private var outline: (w: CGFloat, h: CGFloat, radius: CGFloat, border: CGFloat) {
        switch size {
        case .tile: return (20, 32, 6, 2)
        case .header: return (17, 27, 5, 2)
        case .notice: return (28, 44, 8, 2.5)
        }
    }

    private var notch: (w: CGFloat, h: CGFloat, top: CGFloat) {
        switch size {
        case .tile: return (7, 2.5, 3)
        case .header: return (6, 2, 2.5)
        case .notice: return (9, 3, 4)
        }
    }

    private var boxFill: AnyShapeStyle {
        tinted
            ? AnyShapeStyle(LinearGradient(colors: [DS3.accent.opacity(0.22), DS3.accent.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(DS3.chip)
    }

    var body: some View {
        let o = outline
        let n = notch
        let shape = RoundedRectangle(cornerRadius: boxRadius, style: .continuous)
        ZStack {
            Color.clear
                .background(shape.fill(boxFill))
                .ds3InsetRims(shape, top: DS3.rimHi, ring: DS3.lineStrong)
            RoundedRectangle(cornerRadius: o.radius, style: .continuous)
                .strokeBorder(tint, lineWidth: o.border)
                .frame(width: o.w, height: o.h)
                .overlay(alignment: .top) {
                    Capsule().fill(tint).frame(width: n.w, height: n.h).padding(.top, n.top)
                }
        }
        .frame(width: box, height: box)
        .accessibilityHidden(true)
    }
}
