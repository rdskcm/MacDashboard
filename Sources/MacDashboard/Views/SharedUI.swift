// Views/SharedUI.swift
// Shared chrome/primitives: chips, meter bar, KPI tile chrome, card chrome,
// ChartOrTableCard, status rows, tables, pills and the flow layout.

import SwiftUI
import AppKit

// MARK: - Chips (header)

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
    }
}

struct SeverityChip: View {
    let sev: Severity
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(sev.icon)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(sev.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(sev.color.opacity(0.14)))
    }
}

// MARK: - Meter bar (6px, severity/series tinted)

struct MeterBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule().fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - KPI tile chrome

struct KPITileView<Extra: View>: View {
    let label: String
    let value: String
    let unit: String
    var sub: String? = nil
    var meterFraction: Double? = nil
    var meterColor: Color = SeriesPalette.s1
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 25, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            extra()
            if let meterFraction {
                MeterBar(fraction: meterFraction, color: meterColor)
            }
            if let sub {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

extension KPITileView where Extra == EmptyView {
    init(label: String, value: String, unit: String, sub: String? = nil,
         meterFraction: Double? = nil, meterColor: Color = SeriesPalette.s1) {
        self.init(label: label, value: value, unit: unit, sub: sub,
                   meterFraction: meterFraction, meterColor: meterColor, extra: { EmptyView() })
    }
}

// MARK: - Card chrome

/// Shared "surface" look (rounded rect + hairline border) reused by CardChrome,
/// KPITileView and the collapsed-by-default Energy card (which uses a native
/// DisclosureGroup instead of CardChrome so its own header stays the toggle).
struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCardSurface()
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}

struct CardChrome<Content: View, Trailing: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.headline)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
        .cardBackground()
    }
}

extension CardChrome where Trailing == EmptyView {
    init(title: String, caption: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, caption: caption, trailing: { EmptyView() }, content: content)
    }
}

/// The central component (SPEC §8 pt.4): a card with an L.sharedToggleToTable/L.sharedToggleToChart toggle
/// where BOTH the chart and table closures read the same observable model data
/// passed in by the caller, so whichever is visible keeps ticking live. This is
/// the regression-test target for the old dashboard's "table view goes stale" bug.
struct ChartOrTableCard<ChartContent: View, TableContent: View>: View {
    let title: String
    var caption: String? = nil
    /// Optional always-visible "ⓘ" affordance in the header (nil by default,
    /// so most callers are unaffected). Sits in CardChrome's trailing area, so
    /// it stays visible in both chart and table sub-views.
    var infoHelp: String? = nil
    @State private var showTable = false
    @State private var showInfo = false
    @ViewBuilder var chart: () -> ChartContent
    @ViewBuilder var table: () -> TableContent

    var body: some View {
        CardChrome(title: title, caption: caption, trailing: {
            HStack(spacing: 10) {
                if infoHelp != nil {
                    Button {
                        showInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(showInfo ? L.sharedInfoHide : L.sharedInfoShow)
                }
                Button(showTable ? L.sharedToggleToChart : L.sharedToggleToTable) {
                    showTable.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(showTable ? L.sharedToggleShowChart : L.sharedToggleShowTable)
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                if showInfo, let infoHelp {
                    Text(infoHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showTable {
                    table()
                } else {
                    chart()
                }
            }
        }
    }
}

// MARK: - Status rows (severity dot + text)

struct SeverityDot: View {
    let sev: Severity
    var body: some View {
        Circle()
            .fill(sev.color)
            .frame(width: 8, height: 8)
    }
}

struct StatusRow: View {
    let sev: Severity
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SeverityDot(sev: sev).padding(.top, 5)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// L.sharedUnavailable / spinner placeholder for report sections not yet collected.
struct SectionStateView: View {
    let done: Bool
    var body: some View {
        if done {
            Text(L.sharedUnavailable)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L.sharedCollectingData)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Label/value row (Time Machine, Homebrew, …)

struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Simple table (Grid-based; lighter than SwiftUI Table for our read-only case)

struct SimpleTable: View {
    let headers: [String]
    let rows: [[String]]
    var numericColumns: Set<Int> = []
    /// Optional (row, col) -> tooltip lookup. Nil by default so existing call
    /// sites are unaffected; when a cell has no tooltip the closure returns nil
    /// and no `.help()` is applied (avoids a stray empty hover bubble on cells
    /// that don't need one).
    var cellTooltip: ((Int, Int) -> String?)? = nil
    /// Optional per-row action (row index into `rows`). Nil by default, so
    /// existing call sites render exactly as before; when set the whole row
    /// becomes clickable with a pointing-hand cursor + subtle hover highlight.
    var rowAction: ((Int) -> Void)? = nil
    /// Column indices that support click-to-sort. Empty by default, so
    /// existing call sites render exactly as before (no header interaction,
    /// no sort indicator).
    var sortableColumns: Set<Int> = []
    /// Raw numeric sort keys aligned with `rows`/columns, required for any
    /// column listed in `sortableColumns` so sorting compares values rather
    /// than formatted display strings (e.g. "1.2 GB" vs "890 MB").
    var sortValues: [[Double]]? = nil

    @State private var hoveredRow: Int? = nil
    @State private var sortColumn: Int? = nil
    @State private var sortAscending: Bool = true

    /// Row indices into `rows`/`sortValues`, in current display order. When
    /// no sort is active (default) this is simply 0..<rows.count, so
    /// non-opted-in call sites see unchanged row order.
    private var displayOrder: [Int] {
        guard let col = sortColumn, let values = sortValues, sortableColumns.contains(col) else {
            return Array(rows.indices)
        }
        return rows.indices.sorted { a, b in
            let va = values[a][col]
            let vb = values[b][col]
            return sortAscending ? va < vb : va > vb
        }
    }

    var body: some View {
        let order = displayOrder
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                    let sortable = sortableColumns.contains(i) && sortValues != nil
                    HStack(spacing: 2) {
                        Text(h)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if sortable {
                            if sortColumn == i {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .opacity(0.4)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard sortable else { return }
                        if sortColumn == i {
                            sortAscending.toggle()
                        } else {
                            sortColumn = i
                            sortAscending = true
                        }
                    }
                    .gridColumnAlignment(numericColumns.contains(i) ? .trailing : .leading)
                }
            }
            Divider()
            ForEach(order, id: \.self) { r in
                let row = rows[r]
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, cell in
                        let text = Text(cell)
                            .font(.callout)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if let tip = cellTooltip?(r, c) {
                            text.hoverTip(tip)
                        } else {
                            text
                        }
                    }
                }
                .background((rowAction != nil && hoveredRow == r) ? Color.primary.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard rowAction != nil else { return }
                    if hovering {
                        hoveredRow = r
                        NSCursor.pointingHand.push()
                    } else {
                        if hoveredRow == r { hoveredRow = nil }
                        NSCursor.pop()
                    }
                }
                .onTapGesture {
                    rowAction?(r)
                }
            }
        }
    }
}

// MARK: - Pill flow (Login Items / agents / daemons)

struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().strokeBorder(Color.primary.opacity(0.18)))
    }
}

struct PillFlow: View {
    let items: [String]
    var body: some View {
        if items.isEmpty {
            Text(L.sharedEmpty).font(.caption).foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Pill(text: item)
                }
            }
        }
    }
}

/// Minimal flow/wrap layout (macOS 13+ Layout protocol) — legacy CSS used
/// `.pills{display:flex;flex-wrap:wrap}`; SwiftUI has no built-in equivalent.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Legend item (memory stack, etc.)

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Rainbow border (shimmering, "AI mode" chip style)

/// Full-perimeter shimmering rainbow stroke, reusable on any capsule-shaped control.
/// A slow, continuous rotation of an `AngularGradient` around the shape's perimeter —
/// the gradient's first and last stops share the same color so the 360°→0° wrap is
/// seamless. Shimmer shows only while `isActive`: both the stroke opacity and the phase
/// rotation animation are gated on it, so the `repeatForever` animation only runs
/// while an active/hover state is true — it does not keep driving CoreAnimation
/// in the background when inactive. The glow effect uses layered centered strokes
/// with increasing blur for a soft fading outer edge.
/// One shadow/glow layer of a rainbow ring, out→in: how far it sits outside the
/// shape's edge (`inset`, negative = outward), its stroke `thickness`, its
/// gaussian `blur` radius, and its `opacity`.
struct RainbowRingLayer {
    let inset: CGFloat
    let thickness: CGFloat
    let blur: CGFloat
    let opacity: Double
}

/// The two named ring recipes (SPEC §4 / design handoff, ground truth verified
/// at planning against the prototypes' 9 hover-ring button sites). Deliberately
/// kept as two explicit presets rather than one recipe with a flag, so layer
/// count and per-layer values stay reviewable at a glance — do not collapse.
enum RainbowRingRecipe {
    /// 4 layers (glow14/glow7/glow3/sharp) — the Overview-tab recipe.
    case overview
    /// 3 layers (glow14/glow7/sharp, no glow3) — the Settings-tab recipe;
    /// brighter glows are intentional (0.85/0.7/0.9 vs Overview's 0.12/0.25/0.45/1.0).
    case settings

    var layers: [RainbowRingLayer] {
        switch self {
        case .overview:
            return [
                RainbowRingLayer(inset: -5, thickness: 10, blur: 14, opacity: 0.12),
                RainbowRingLayer(inset: -3, thickness: 6, blur: 7, opacity: 0.25),
                RainbowRingLayer(inset: -1.5, thickness: 3, blur: 3, opacity: 0.45),
                RainbowRingLayer(inset: -0.75, thickness: 1.5, blur: 0, opacity: 1.0),
            ]
        case .settings:
            return [
                RainbowRingLayer(inset: -5, thickness: 10, blur: 14, opacity: 0.85),
                RainbowRingLayer(inset: -3, thickness: 6, blur: 7, opacity: 0.7),
                RainbowRingLayer(inset: -0.75, thickness: 1.5, blur: 0, opacity: 0.9),
            ]
        }
    }
}

struct RainbowBorder: ViewModifier {
    /// Full 360° revolution period. Slow enough to read as a gentle shimmer rather
    /// than a spinner.
    var period: Double = DSMotion.rainbow
    var isActive: Bool = true
    var recipe: RainbowRingRecipe = .overview

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    private var colors: [Color] {
        [
            Color(hex: 0xff3b30), Color(hex: 0xff9500), Color(hex: 0xffcc00),
            Color(hex: 0x34c759), Color(hex: 0x0a84ff), Color(hex: 0xaf52de),
            Color(hex: 0xff3b30),
        ]
    }

    /// Reduce Motion still allows the opacity fade — it's a color/opacity
    /// transition per the project-wide Reduce Motion contract — just at the
    /// shortened 0.12 s fallback duration instead of the normal 0.25 s.
    private var fadeDuration: Double {
        reduceMotion ? DSMotion.reduceMotionFallback : 0.25
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    ForEach(Array(recipe.layers.enumerated()), id: \.offset) { _, layer in
                        Capsule()
                            .strokeBorder(
                                AngularGradient(gradient: Gradient(colors: colors), center: .center, angle: .zero),
                                lineWidth: layer.thickness
                            )
                            .padding(layer.inset)
                            .blur(radius: layer.blur)
                            .hueRotation(.degrees(phase))
                            .opacity(layer.opacity)
                    }
                }
                .opacity(isActive ? 1 : 0)
                .animation(.easeInOut(duration: fadeDuration), value: isActive)
            }
            .onChange(of: isActive, initial: true) { _, newValue in
                guard !reduceMotion else {
                    // Reduce Motion: ring appears static (no spin), fade only.
                    var stillTransaction = Transaction()
                    stillTransaction.disablesAnimations = true
                    withTransaction(stillTransaction) { phase = 0 }
                    return
                }
                if newValue {
                    var resetTransaction = Transaction()
                    resetTransaction.disablesAnimations = true
                    withTransaction(resetTransaction) {
                        phase = 0
                    }
                    withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                        phase = 360
                    }
                } else {
                    var stopTransaction = Transaction()
                    stopTransaction.disablesAnimations = true
                    withTransaction(stopTransaction) {
                        phase = 0
                    }
                }
            }
    }
}

extension View {
    func rainbowBorder(period: Double = DSMotion.rainbow, isActive: Bool = true, recipe: RainbowRingRecipe = .overview) -> some View {
        modifier(RainbowBorder(period: period, isActive: isActive, recipe: recipe))
    }
}

/// Small capsule button with the shimmering rainbow hover border — the shared look for card-header actions (SMART «Обновить», battery «Детали»).
/// `recipe` defaults to `.overview` — today's shipped look on every existing call
/// site, including the Settings «Перезапустить сейчас» button, which keeps the
/// Overview recipe until block V2-SET-GEN explicitly passes `recipe: .settings`.
struct RainbowCapsuleButton: View {
    let title: String
    var busy: Bool = false
    var recipe: RainbowRingRecipe = .overview
    let action: () -> Void

    @State private var hovering = false
    @State private var cursorPushed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small)
                }
                Text(title).font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay { Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1) }
            .rainbowBorder(isActive: hovering, recipe: recipe)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { isHovering in
            self.hovering = isHovering
            if isHovering && !busy {
                NSCursor.pointingHand.push()
                cursorPushed = true
            } else if !isHovering && cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
    }
}

/// Human-readable one-liner for the live `brew upgrade` progress state.
/// Views-layer helper (not in Checks) — reads `L` at call time so it follows
/// instant language switching.
func brewProgressText(_ p: BrewProgress) -> String {
    switch p.phase {
    case .downloading:
        return L.maintenanceBrewProgressDownloading(p.downloadsDone)
    case .upgrading:
        guard let name = p.formula else { return L.maintenanceBrewUpgrading }
        if p.total == 0 {
            return L.maintenanceBrewProgressUpgradingBare(name)
        }
        let k = min(p.completed, p.total)
        let n = p.total
        let pct = min(100, Int((Double(p.completed) / Double(p.total) * 100).rounded()))
        return L.maintenanceBrewProgressUpgrading(name, k, n, pct)
    }
}
