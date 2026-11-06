// Views/SocReadoutChip.swift
// SOC-DETAILS 2.3 (design 7.3, 7.12): the page-bar readout chip (chip temperature | thermal state | whole-Mac
// power) and the chip family's two scales, the temperature gauge and the thermal rail. Home reuses the two scales
// in Stage 4. All values come from `SocReadout.make` (Engine/SocPageModel.swift); this file only draws them.
//
// Nothing here is measured: every width is a parameter, so no size feeds back into layout
// (`no-measured-size-feedback`). The only animations are the tint colour of a segment and the position of the
// gauge marker, both on views whose size does not depend on the animated value (`animation-value-size-coupling`).

import SwiftUI

extension CPUNoteTone {
    /// Fill colour of the tone: gauge zones, rail steps, tint.
    var fill: Color {
        switch self {
        case .green: return DS3.green
        case .neutral: return DS3.muted
        case .amber: return DS3.amber
        case .hot: return DS3.hot
        }
    }

    /// Text colour of the tone (`-ink` variants, `light-theme-ink-variants`). Calm tones read as plain text.
    var ink: Color {
        switch self {
        case .green: return DS3.ink
        case .neutral: return DS3.inkSoft
        case .amber: return DS3.amberInk
        case .hot: return DS3.hotInk
        }
    }

    /// Amber and hot mark something that needs a look; they alone get a tinted segment.
    var isAttention: Bool { self == .amber || self == .hot }
}

// MARK: - Chip

/// Internal: the visual fixture renders it.
@MainActor
struct SocReadoutChip: View {
    let model: AppModel
    /// Window width below 1000 pt (`breakpoints.narrow`).
    let narrow: Bool
    /// The page-bar state tag is showing (it is hidden in the OK state).
    let tagVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let r = SocReadout.make(socTempC: model.socTempC, thermal: model.thermal, powerW: model.socLive.powerW,
                                narrow: narrow, tagVisible: tagVisible)
        let tempTone: CPUNoteTone = r.temperature.map { $0.zone == 2 ? .hot : ($0.zone == 1 ? .amber : .green) } ?? .green
        HStack(spacing: 0) {
            temperature(r.temperature, tone: tempTone)
            if let th = r.thermal {
                divider
                thermal(th)
            }
            divider
            power(r.power)
        }
        .frame(height: 30)
        .background(Capsule().fill(DS3.field))
        .clipShape(Capsule())
        .ds3InsetRims(Capsule(), ring: DS3.line, ringWidth: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label(r))
        .accessibilityIdentifier("soc-readout-chip")
    }

    /// Lift of a lowercase word so its visual middle (x-height / 2) is level with the digits' middle
    /// (cap height / 2): `(capHeight - xHeight) / 2` of the font actually used. Home chips reuse it.
    static func wordLift(size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let f = NSFont.systemFont(ofSize: size, weight: weight)
        return (f.capHeight - f.xHeight) / 2
    }

    /// The chip's segment font is 13 / semibold (see `segmentText`).
    static let segmentWordLift = wordLift(size: 13, weight: .semibold)

    private var divider: some View {
        Rectangle().fill(DS3.lineStrong).frame(width: 1)
    }

    private var tintAnimation: Animation? { .easeOut(duration: reduceMotion ? 0.12 : 0.2) }

    /// Calm segments have no fill. An attention segment gets the status-tag tint (26 % to 11 %); only its colour
    /// is animated, on a background that cannot change the segment's size.
    private func tint(_ tone: CPUNoteTone) -> some View {
        Color.clear
            .ds3TintPanel(tone.fill, from: 0.26, to: 0.11, ring: nil, cornerRadius: 0)
            .opacity(tone.isAttention ? 1 : 0)
            .animation(tintAnimation, value: tone)
    }

    private func temperature(_ t: SocReadout.Temperature?, tone: CPUNoteTone) -> some View {
        HStack(spacing: 7) {
            if let t {
                SocTemperatureGauge(zone: t.zone, markerX: t.markerX, width: 30)
                // The word is raised so its x-height middle is level with the digits' middle.
                (Text(t.value) + (t.word.map { Text(" \($0)").baselineOffset(Self.segmentWordLift) } ?? Text("")))
                    .foregroundStyle(tone.ink)
            } else {
                Text("—").foregroundStyle(DS3.muted)
            }
        }
        .segmentText()
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background { tint(tone) }
        .hoverTip(t == nil ? L.socTemperatureUnavailable : L.socTemperatureHelp)
    }

    private func thermal(_ th: SocReadout.Thermal) -> some View {
        HStack(spacing: 7) {
            SocThermalRail(step: th.step, tone: th.tone.fill, stepWidth: 7)
            Text(th.text).baselineOffset(Self.segmentWordLift).foregroundStyle(th.tone.ink)
        }
        .segmentText()
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background { tint(th.tone) }
        .hoverTip(th.help)
    }

    private func power(_ p: SocReadout.Power) -> some View {
        HStack(spacing: 7) {
            if let prefix = p.prefix {
                Text(prefix).fontWeight(.medium).baselineOffset(Self.wordLift(size: 13, weight: .medium)).foregroundStyle(DS3.muted)
            }
            Text(p.value).foregroundStyle(p.available ? DS3.ink : DS3.muted)
        }
        .segmentText()
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .hoverTip(p.help)
    }

    /// One spoken sentence for the three segments, in reading order.
    private func label(_ r: SocReadout) -> String {
        var parts: [String] = []
        if let t = r.temperature {
            parts.append([L.socChipTemperature, t.value, t.word].compactMap { $0 }.joined(separator: " "))
        } else {
            parts.append(L.socTemperatureUnavailable)
        }
        if let th = r.thermal { parts.append(th.full) }
        parts.append(r.power.available ? "\(L.socPowerLabel) \(r.power.value)" : L.socPowerUnavailable)
        return parts.joined(separator: ", ")
    }
}

private extension View {
    /// Segment text: 13 / 650 (semibold is the nearest named weight), tabular digits, one line. The chip takes its
    /// ideal width through a `layoutPriority` at the call site, never through `.fixedSize()` (`fixed-size-in-header-row`).
    func segmentText() -> some View {
        font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
    }
}

// MARK: - Temperature gauge (design 7.12)

/// Three zones (green 30 to 85 °C, amber 85 to 95, hot 95 to 105: flex 55 / 10 / 10), gap 2, height 4. The zone
/// holding the value is at full opacity, the rest at 28 %. The marker is a fixed 2 x 10 shape moved by position only.
/// `width` is 30 in the page bar and 34 on Home.
struct SocTemperatureGauge: View {
    let zone: Int
    let markerX: Double
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let zoneColors: [Color] = [DS3.green, DS3.amber, DS3.hot]
    private static let flex: [CGFloat] = [55, 10, 10]

    var body: some View {
        let usable = max(0, width - 4)
        let total = Self.flex.reduce(0, +)
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.zoneColors[i])
                    .opacity(i == zone ? 1 : 0.28)
                    .frame(width: usable * Self.flex[i] / total, height: 4)
            }
        }
        .frame(width: width, height: 4, alignment: .leading)
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(DS3.ink)
                .frame(width: 2, height: 10)
                .background(RoundedRectangle(cornerRadius: 2.5).fill(DS3.glassStrong).frame(width: 5, height: 13))
                .offset(x: CGFloat(min(1, max(0, markerX))) * width - 1, y: -3)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: markerX)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Thermal rail (design 7.12)

/// Four steps (normal, elevated, high, critical), 4 pt tall, gap 2. Steps up to and including `step` take `tone`,
/// the rest `DS3.track`. `stepWidth` is 7 in the page bar and 9 on Home.
struct SocThermalRail: View {
    let step: Int
    let tone: Color
    let stepWidth: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i <= step ? tone : DS3.track)
                    .frame(width: stepWidth, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}
