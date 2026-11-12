// Views/WelcomeParts.swift
// MOONPORT-RENAME amendment 3: the small pieces of the Moonport Welcome panel (status circle, progress dots, motion values).
// Only opacity, scale and offset animate (`gpu-per-frame`). Design: handoff 12-moonport-welcome.md §3.2, §3.5, §5.
import SwiftUI

/// Animation values of the panel's state changes. Reduce Motion: opacity only, 0.12 s (design §5).
enum WelcomeMotion {
    /// A finished step, the "Granted" label, "All set", "Done": a springy pop.
    static func pop(_ reduce: Bool) -> Animation { reduce ? .easeOut(duration: 0.12) : .spring(response: 0.45, dampingFraction: 0.6) }
    /// A result item entering (old-app result, archive row swap).
    static func item(_ reduce: Bool) -> Animation { reduce ? .easeOut(duration: 0.12) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.4) }
}

extension AnyTransition {
    static func welcomePop(_ reduce: Bool) -> AnyTransition {
        reduce ? .opacity : .asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity), removal: .opacity)
    }
    static func welcomeItem(_ reduce: Bool) -> AnyTransition {
        reduce ? .opacity : .opacity.combined(with: .offset(y: 6))
    }
}

/// The 28 pt circle in a row's leading column (design §3.2).
struct WelcomeStatusCircle: View {
    enum Kind: Equatable { case done, busy, warning, error, info, step(Int), optional }
    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack { circle.transition(.welcomePop(reduceMotion)) }
            .frame(width: 28, height: 28)
            .animation(WelcomeMotion.pop(reduceMotion), value: kind)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var circle: some View {
        switch kind {
        case .done:
            tint(DS3.green, from: 0.32, to: 0.12, ring: 0.5, top: DS3.rimMid) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(DS3.greenInk)
            }
        case .busy:
            tint(DS3.accent, from: 0.32, to: 0.12, ring: 0.5, top: DS3.rimMid) {
                DS3Spinner(role: .accentInkRing, size: 12)
            }
        case .warning:
            tint(DS3.amber, from: 0.32, to: 0.12, ring: 0.5, top: DS3.rimMid) { bang(DS3.amberInk) }
        case .error:
            tint(DS3.hot, from: 0.28, to: 0.10, ring: 0.45, top: nil) { bang(DS3.hotInk) }
        case .info:
            Circle().fill(DS3.lens)
                .ds3InsetRims(Circle(), top: DS3.rimHi, ring: DS3.rimMid)
                .ds3Elevation(.lens, in: Circle())
                .overlay {
                    Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(DS3.inkSoft)
                }
        case .step(let n):
            ring.overlay {
                Text("\(n)").font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(DS3.muted)
            }
        case .optional:
            ring
        }
    }

    private var ring: some View { Circle().strokeBorder(DS3.lineStrong, lineWidth: 1.5) }

    private func bang(_ ink: Color) -> some View {
        Text("!").font(.system(size: 14, weight: .heavy)).foregroundStyle(ink)
    }

    private func tint<G: View>(_ tone: Color, from a: Double, to b: Double, ring: Double, top: Color?,
                               @ViewBuilder glyph: () -> G) -> some View {
        Color.clear
            .ds3TintPanel(tone, from: a, to: b, ring: ring, cornerRadius: 14, top: top)
            .overlay { glyph() }
    }
}

/// One 18 × 5 capsule per required step, green when done (design §3.5).
struct WelcomeProgressDots: View {
    let steps: [Bool]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, done in
                Capsule().fill(done ? DS3.green : DS3.track).frame(width: 18, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: steps)
        .accessibilityHidden(true)
    }
}
