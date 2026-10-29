// Views/HomeNowCard.swift
// REDESIGN-HOME (stage C): the Now card of Home — live CPU / Memory / Storage / Battery cells
// (02-home.md §2, 00-shared §4.6/§4.7). The cells come from `HomeModel.nowCells`; this file only draws them.
// Cells sit in a non-lazy `EqualColumnsLayout` so a column change keeps their identity and animates their frames
// (RESIZE-MOTION); `live-list-identity` still holds (non-lazy, live sparkline).

import SwiftUI

struct HomeNowCard: View {
    let model: AppModel
    let router: NavigationRouter
    let tier: WidthTier
    /// `false` only in the offscreen visual harness (see `homeEntrance`).
    var animatesEntrance = true

    var body: some View {
        let input = HomeInput.make(model)
        let hasBattery = input.hasBattery
        let short = hasBattery && tier.isMid
        let narrow = tier.isNarrow
        let columns = hasBattery ? (narrow ? 2 : 4) : 3
        let tasks = HomeModel.tasks(input.assessment, report: input.report, disk: input.disk, battery: model.battery)
        let cells = HomeModel.nowCells(input, tasks: tasks, memPressure: model.memPressure, socTempC: model.socTempC,
                                       cpu: model.cpu, short: short, narrow: narrow)
        let spark = HomeModel.sparkline(model.cpuHistory)
        DS3Card(title: L.commonNow, caption: L.homeEverySeconds(model.settings.fastIntervalSeconds)) {
            EqualColumnsLayout(columns: columns, spacing: 8) {
                ForEach(cells) { cell in
                    HomeNowCellView(cell: cell, sparkline: spark) { router.navigate(to: cell.destination) }
                }
            }
        }
        .homeEntrance(delay: 0.12, enabled: animatesEntrance)
    }
}

struct HomeNowCellView: View {
    let cell: HomeNowCell
    let sparkline: [Double]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                labelRow
                valueRow
                visual.frame(height: 40)
                Text(cell.foot)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS3.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(cell.foot)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HomeNowTint(tone: cell.tone, kind: cell.kind))
        }
        .buttonStyle(DS3TileButtonStyle())
        .accessibilityLabel("\(cell.label), \(cell.big) \(cell.of)")
        .accessibilityIdentifier("home-now-\(cell.kind.rawValue)")
    }

    private var labelColor: Color {
        if cell.kind == .cpu { return DS3.accentInk }
        switch cell.tone {
        case .amber: return DS3.amberInk
        case .hot: return DS3.hotInk
        default: return DS3.inkSoft
        }
    }

    private var labelRow: some View {
        HStack(spacing: 8) {
            Text(cell.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .help(cell.label)
            Spacer(minLength: 4)
            if let text = cell.chipText, let tone = cell.chipTone {
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tone.ink)
                    .lineLimit(1)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 9)
                    .ds3TintPanel(tone.base, from: 0.16, to: 0.16, ring: 0.45, cornerRadius: 999)
                    .help(text)
            }
        }
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(cell.big)
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.78)
                .monospacedDigit()
                .foregroundStyle(cell.loading ? DS3.muted : DS3.ink)
                .lineLimit(1)
            Text(cell.of)
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
                .lineLimit(1)
                .help(cell.of)
        }
    }

    @ViewBuilder
    private var visual: some View {
        if cell.kind == .cpu {
            HomeSparkline(values: sparkline)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Spacer(minLength: 0)
                HomeStackBar(segments: cell.segments, mark: cell.mark)
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(Array(cell.legend.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.isRule ? DS3.inkSoft : homeSeriesColor(item.series))
                        .frame(width: item.isRule ? 2 : 7, height: 7)
                    Text(item.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS3.muted)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Cell surface by tone (00 §1.1): neutral row fill with inset rims, amber / hot tint panels.
private struct HomeNowTint: ViewModifier {
    let tone: HomeTone
    let kind: HomeNowKind

    func body(content: Content) -> some View {
        if kind == .cpu {
            content.ds3TintPanel(DS3.accent, from: 0.16, to: 0.06, ring: 0.40, cornerRadius: 20, top: DS3.rimMid)
        } else {
            toneBody(content)
        }
    }

    @ViewBuilder
    private func toneBody(_ content: Content) -> some View {
        switch tone {
        case .amber:
            content.ds3TintPanel(DS3.amber, from: 0.13, to: 0.04, ring: 0.34, cornerRadius: 20, top: DS3.rimMid)
        case .hot:
            content.ds3TintPanel(DS3.hot, from: 0.14, to: 0.05, ring: 0.45, cornerRadius: 20, top: DS3.rimMid)
        default:
            content
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
                .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), top: DS3.rimLo, ring: DS3.line)
        }
    }
}

func homeSeriesColor(_ s: HomeSeries) -> Color {
    switch s {
    case .s1: return DS3.s1
    case .s2: return DS3.s2
    case .s3: return DS3.s3
    case .s4: return DS3.s4
    case .sfree: return DS3.sfree
    case .track: return DS3.track
    case .green: return DS3.green
    case .amber: return DS3.amber
    case .hot: return DS3.hot
    }
}

/// 24-point CPU line with a flat 22 % area (00 §4.7; prototype `This Mac Home v2.dc.html:219-222`).
struct HomeSparkline: View {
    let values: [Double]

    var body: some View {
        if values.count >= 2 {
            ZStack {
                HomeSparklinePath(values: values, closed: true)
                    .fill(DS3.accent.opacity(0.22))
                HomeSparklinePath(values: values, closed: false)
                    .stroke(DS3.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}

private struct HomeSparklinePath: Shape {
    let values: [Double]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = values.count
        guard n >= 2 else { return p }
        func pt(_ i: Int) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(i) / CGFloat(n - 1) * rect.width,
                    y: rect.minY + rect.height - CGFloat(values[i] / 100) * (rect.height - 2) - 1)
        }
        p.move(to: pt(0))
        for i in 1..<n {
            let a = pt(i - 1), b = pt(i)
            let mx = (a.x + b.x) / 2
            p.addCurve(to: b, control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
        }
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

/// Proportional segmented bar (00 §4.6). Widths are drawn inside a non-sizing overlay
/// (`no-measured-size-feedback`); no animation on segment widths.
struct HomeStackBar: View {
    let segments: [HomeNowSegment]
    let mark: Double?

    var body: some View {
        Color.clear.frame(height: 10)
            .overlay {
                GeometryReader { g in
                    let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
                    let gaps = 2 * CGFloat(max(0, segments.count - 1))
                    HStack(spacing: 2) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(homeSeriesColor(seg.series))
                                .frame(width: max(2, (g.size.width - gaps) * seg.value / total))
                        }
                    }
                }
            }
            .overlay {
                if let mark {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(DS3.ink.opacity(0.55))
                            .frame(width: 2, height: 18)
                            .position(x: g.size.width * mark, y: 5)
                            .help(L.homeWearThresholdHelp)
                    }
                }
            }
    }
}
