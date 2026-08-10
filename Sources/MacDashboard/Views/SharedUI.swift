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
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(DS.muted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(DS.glass))
            .overlay(Capsule().strokeBorder(DS.line, lineWidth: 1))
    }
}

/// Header status chip — bound to the live assessment, never a static label
/// (see `HeaderChipsView` in MainDashboardView.swift, its one call site).
/// `tone` drives the dot + 14%/32% fill/stroke; `isGood` only swaps the label's
/// ink (green-ink text on the all-clear state, plain `DS.ink` otherwise — the
/// "otherwise" tones (`DS.hot`/`DS.amber`) are containers/dot colors only, per
/// the light-theme ink-role rule: `DS.hot` has no light-mode text role).
struct SeverityChip: View {
    let isGood: Bool
    let tone: Color
    let label: String
    var hasCrit: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colorTransition: Animation {
        .easeInOut(duration: reduceMotion ? DSMotion.reduceMotionFallback : 0.18)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                // DS.hot has no -ink light-mode text variant, so the critical case
                // falls back to neutral DS.ink; the amber case has DS.amberInk and must use it.
                .foregroundStyle(isGood ? DS.greenInk : (hasCrit ? DS.ink : DS.amberInk))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(tone.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tone.opacity(0.32), lineWidth: 1))
        .animation(colorTransition, value: tone)
        .animation(colorTransition, value: label)
    }
}

// MARK: - Meter bar (6px, severity/series tinted, recessed track)

/// V2-TILES: the track is `dsRecessedTrack` (DesignSystem.swift) rather than a
/// flat translucent capsule — same 6pt height, now matching the KPI tile
/// Visual band's recessed look. The fill capsule on top is unchanged.
struct MeterBar: View {
    var fraction: Double
    var color: Color
    /// FIX-1 audit (V2-TILES follow-up): no call site carried a width-change
    /// animation before this pass. Spec requires it ONLY on the Memory/Swap
    /// tiles' live bars — .8 s `cubic-bezier(0.22,0.61,0.36,1)` — while Disk
    /// and Battery must keep snapping instantly. Defaults to `false` so any
    /// call site that doesn't opt in keeps the (correct, already-audited)
    /// no-animation behavior.
    var animated: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trackWidth: CGFloat = 0

    var body: some View {
        let f = CGFloat(min(max(fraction, 0), 1))
        ZStack(alignment: .leading) {
            dsRecessedTrack(in: Capsule())
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { newWidth in
                    trackWidth = newWidth
                }
            Capsule().fill(color)
                // Width comes from @State, never from a GeometryReader inside this
                // animated subtree (V2-FIX-BARFLY): the 0 -> real-width settling of
                // a fresh mount must NOT be swept into the fraction animation, or
                // the bar "flies in" every time LazyVGrid remounts the tile on
                // scroll. Same isolation as MemoryCard / BatteryDetailPopover.
                .frame(width: trackWidth > 0 ? max(2, trackWidth * f) : 0)
                .animation((animated && !reduceMotion) ? .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.8) : nil, value: f)
        }
        .frame(height: 6)
    }
}

// MARK: - Severity -> v2 tone map

/// crit/serious -> DS.hot, warn/info -> DS.amber, good -> DS.green. Never the
/// legacy `Severity.color` (Theme.swift) — that palette belongs to the v1 UI.
/// Hoisted here (V2-TILES) from `AttentionSummaryCard.swift`, its original
/// (private) home, since KPITiles.swift now needs the same mapping for the
/// swap/disk/battery meter-bar tints — single source of truth, no second copy.
func tone(for sev: Severity) -> Color {
    switch sev {
    case .crit, .serious: return DS.hot
    case .warn, .info: return DS.amber
    case .good: return DS.green
    }
}

// MARK: - KPI temperature capsule (header-band satellite, CPU/disk)

/// Small pill shown in a KPI tile's header band (CPU SOC temp, disk NVMe
/// temp): value 12pt monospaced + unit 9.5pt, tinted by how close `celsius`
/// is to `warn`/`crit`. "Cool" is more than 12°C below `warn` — everything
/// between cool and warn reads as "normal".
struct KPITempBadge: View {
    let celsius: Int
    let warn: Int
    let crit: Int

    private enum Band { case cool, normal, high, critical }

    private var band: Band {
        if celsius >= crit { return .critical }
        if celsius >= warn { return .high }
        if celsius < warn - 12 { return .cool }
        return .normal
    }

    /// Fill/border/dot color (non-ink; appearance-aware on its own via
    /// `Color(light:dark:)`, never the -ink variant — see the light-theme rule).
    private var tone: Color {
        switch band {
        case .cool: return DS.accent
        case .normal: return DS.green
        case .high: return DS.amber
        case .critical: return DS.hot
        }
    }

    /// Text color: the -ink variant in every non-critical band (light-theme
    /// contrast rule), plain white on the solid critical fill.
    private var textTone: Color {
        switch band {
        case .cool: return DS.accentInk
        case .normal: return DS.greenInk
        case .high: return DS.amberInk
        case .critical: return .white
        }
    }

    private var unitTone: Color {
        band == .critical ? Color.white.opacity(0.72) : textTone
    }

    private var fillOpacity: Double {
        switch band {
        case .cool, .normal: return 0.11
        case .high: return 0.15
        case .critical: return 1.0
        }
    }

    private var borderOpacity: Double {
        switch band {
        case .cool, .normal: return 0.34
        case .high: return 0.48
        case .critical: return 1.0
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(celsius)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
            Text("°C")
                .font(.system(size: 9.5))
                .foregroundStyle(unitTone)
        }
        .foregroundStyle(textTone)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 22)
        .background(Capsule().fill(tone.opacity(fillOpacity)))
        .overlay(Capsule().strokeBorder(tone.opacity(borderOpacity), lineWidth: 1))
    }
}

// MARK: - KPI tile chrome

/// One state chip in a KPI tile's header band: a 6pt severity dot + a short
/// word (`DS.inkSoft`). Distinct from `SeverityChip` (the header-level capsule
/// chip) — this one is bare (no capsule background), sized for the tile header.
struct KPITileStateChip {
    let color: Color
    let word: String
}

/// `KPITileView.unit` rendering: `.satellite` (default) is the small muted
/// unit sitting beside the value; `.prominent` matches the value's own 27pt
/// semibold monospaced style with only a 3pt gap — for tiles where a plain
/// space between value and unit reads too wide in a monospaced face (see
/// block V2-FIX-UNITS).
enum KPIUnitStyle {
    case satellite
    case prominent
}

/// KPI tile chrome (Spec §5.3): a four fixed-height-band card —
/// 1. header (22pt): nowrap+ellipsis label taking the slack, at most one
///    `satellite` view (temperature capsule / battery "Детали" pill), then an
///    optional state chip;
/// 2. value (30pt, one line, never wraps): tabular monospaced `value` +
///    `unit` (both keep their intrinsic width) + the shrinkable/ellipsizable
///    `outOf` ("из N");
/// 3. visual (46pt): whatever `visual` supplies — typically a `MeterBar`, or
///    for CPU the sparkline occupying the same zone;
/// 4. footer (31pt): `footer` text pinned to the band's bottom edge.
///
/// Generic over the two optional per-tile views, following the same
/// `Extra`/`EmptyView` convention as `CardChrome`/`ChartOrTableCard` above —
/// callers that need neither/either/both closures get a matching convenience
/// initializer instead of writing `{ EmptyView() }` by hand.
struct KPITileView<Satellite: View, Visual: View>: View {
    let label: String
    var chip: KPITileStateChip? = nil
    let value: String
    var unit: String? = nil
    var unitStyle: KPIUnitStyle = .satellite
    var outOf: String? = nil
    var footer: String? = nil
    @ViewBuilder var satellite: () -> Satellite
    @ViewBuilder var visual: () -> Visual

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            valueRow
            visualZone
            footerZone
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface()
        .dsHoverLift()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(DS.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            satellite()
            if let chip {
                HStack(spacing: 4) {
                    Circle().fill(chip.color).frame(width: 6, height: 6)
                    Text(chip.word)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DS.inkSoft)
                }
            }
        }
        .frame(height: 22)
    }

    /// `value`/`unit` keep their intrinsic width (`fixedSize`) so they never
    /// truncate; `outOf` is the one element allowed to shrink/ellipsize when
    /// the column is tight (the five-equal-column grid depends on this).
    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(value)
                .font(.system(size: 27, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let unit {
                switch unitStyle {
                case .satellite:
                    Text(unit)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.muted)
                        .padding(.leading, 2)
                        .fixedSize(horizontal: true, vertical: false)
                case .prominent:
                    Text(unit)
                        .font(.system(size: 27, weight: .semibold))
                        .padding(.leading, 3)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            if let outOf {
                Text(outOf)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 5)
                    // Without an explicit width frame, this Text has no
                    // well-defined layout width to truncate against inside
                    // an HStack whose other siblings are `fixedSize` — it
                    // renders at its intrinsic size and gets hard-clipped
                    // by the surrounding layout with no ellipsis (e.g. the
                    // Swap tile showing a stray "и" instead of "из 1,9…").
                    // `.frame(maxWidth: .infinity, ...)` gives it the same
                    // "take remaining space, then truncate" treatment the
                    // header label already uses.
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 30, alignment: .leading)
    }

    private var visualZone: some View {
        visual()
            .frame(maxWidth: .infinity)
            .frame(height: 46, alignment: .center)
    }

    /// Pinned to the bottom of the band (not vertically centered) so a
    /// short one-line footer sits flush with the card's bottom edge.
    private var footerZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .lineSpacing(4.4)   // 11pt * 1.4 line-height, minus the 11pt itself
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(DS.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(height: 31, alignment: .bottom)
    }
}

extension KPITileView where Satellite == EmptyView, Visual == EmptyView {
    init(label: String, chip: KPITileStateChip? = nil, value: String, unit: String? = nil,
         outOf: String? = nil, footer: String? = nil) {
        self.init(label: label, chip: chip, value: value, unit: unit, outOf: outOf, footer: footer,
                   satellite: { EmptyView() }, visual: { EmptyView() })
    }
}

extension KPITileView where Satellite == EmptyView {
    init(label: String, chip: KPITileStateChip? = nil, value: String, unit: String? = nil,
         unitStyle: KPIUnitStyle = .satellite, outOf: String? = nil, footer: String? = nil,
         @ViewBuilder visual: @escaping () -> Visual) {
        self.init(label: label, chip: chip, value: value, unit: unit, unitStyle: unitStyle,
                   outOf: outOf, footer: footer, satellite: { EmptyView() }, visual: visual)
    }
}

extension KPITileView where Visual == EmptyView {
    init(label: String, chip: KPITileStateChip? = nil, value: String, unit: String? = nil,
         outOf: String? = nil, footer: String? = nil, @ViewBuilder satellite: @escaping () -> Satellite) {
        self.init(label: label, chip: chip, value: value, unit: unit, outOf: outOf, footer: footer,
                   satellite: satellite, visual: { EmptyView() })
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
                Text(title).font(.headline).lineLimit(1).truncationMode(.tail)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                trailing().layoutPriority(1)
            }
            content()
        }
        .cardBackground()
        .dsHoverLift()
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
struct ChartOrTableCard<ChartContent: View, TableContent: View, HeaderAccessory: View>: View {
    let title: String
    var caption: String? = nil
    /// Optional always-visible "ⓘ" affordance in the header (nil by default,
    /// so most callers are unaffected). Sits in CardChrome's trailing area, so
    /// it stays visible in both chart and table sub-views.
    var infoHelp: String? = nil
    /// Extra header content (e.g. a metric picker) rendered in the trailing
    /// header row, BEFORE the ⓘ and the chart/table toggle. Lives here — not
    /// inside `chart`/`table` — so a stateful control bound to it keeps its
    /// identity across the chart/table switch instead of remounting. Defaults
    /// to `EmptyView` via the extension below, so most callers are unaffected.
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    @State private var showTable = false
    @State private var showInfo = false
    @State private var hovering = false
    @State private var infoHovering = false
    @State private var cursorPushed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var chart: () -> ChartContent
    @ViewBuilder var table: () -> TableContent

    var body: some View {
        CardChrome(title: title, caption: caption, trailing: {
            HStack(spacing: 10) {
                headerAccessory()
                if infoHelp != nil {
                    Button {
                        showInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(infoHovering ? DS.ink : DS.muted)
                    }
                    .buttonStyle(.plain)
                    .onHover { infoHovering = $0 }
                    .animation(
                        reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
                        value: infoHovering
                    )
                    .accessibilityLabel(showInfo ? L.sharedInfoHide : L.sharedInfoShow)
                }
                Button {
                    showTable.toggle()
                } label: {
                    Text(showTable ? L.sharedToggleToChart : L.sharedToggleToTable)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.inkSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(DS.glass3))
                        .overlay { Capsule().strokeBorder(DS.lineStrong, lineWidth: 1) }
                        .rainbowBorder(isActive: hovering, recipe: .overview)
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hovering = isHovering
                    if isHovering {
                        NSCursor.pointingHand.push()
                        cursorPushed = true
                    } else if cursorPushed {
                        NSCursor.pop()
                        cursorPushed = false
                    }
                }
                .accessibilityLabel(showTable ? L.sharedToggleShowChart : L.sharedToggleShowTable)
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                if showInfo, let infoHelp {
                    Text(infoHelp)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.muted)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
                if showTable {
                    table()
                } else {
                    chart()
                }
            }
            .animation(
                reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
                value: showInfo
            )
        }
    }
}

extension ChartOrTableCard where HeaderAccessory == EmptyView {
    init(
        title: String,
        caption: String? = nil,
        infoHelp: String? = nil,
        @ViewBuilder chart: @escaping () -> ChartContent,
        @ViewBuilder table: @escaping () -> TableContent
    ) {
        self.init(title: title, caption: caption, infoHelp: infoHelp, headerAccessory: { EmptyView() }, chart: chart, table: table)
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

/// Leading-column swatch kind for `SimpleTable` rows (MEMORY-ONLY today):
/// `.filled` draws a solid color chip, `.outline` draws a hollow outline chip
/// for rows that don't map to an actual chart color (e.g. reference-only rows
/// that overlap other buckets) while still reserving the same swatch slot.
enum TableSwatch: Equatable {
    case filled(Color)
    case outline
}

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
    /// Optional per-row leading swatch, one entry per `rows` index. Nil by
    /// default (no swatch affordance at all), so existing call sites render
    /// exactly as before. When set, must have the same count as `rows`; the
    /// swatch is inlined into column 0 (name column), not a separate Grid
    /// column, so header alignment matches the data columns 1:1.
    var swatches: [TableSwatch]? = nil
    /// Grid column spacing. Defaults to 16 (the historical value), so
    /// existing call sites are unaffected; MEMORY-ONLY call sites may pass a
    /// tighter value to compensate for the inlined swatch's extra width.
    var columnSpacing: CGFloat = 16
    /// V2-FIX-UNITS follow-up: column indices whose cell text is a formatted
    /// "value unit" pair (e.g. "1.9 GB") that should render as two `Text`s
    /// with a tight `.padding(.leading, 1.5)` gap instead of one `Text` with
    /// a literal space — this column is monospaced (see `cellFont` below), so
    /// a plain space is a full glyph advance and a thin-space substitution
    /// (verified empirically) doesn't narrow it in this font. Empty by
    /// default, so existing call sites render exactly as before; splits on
    /// the LAST regular space in the cell string, falling back to a single
    /// `Text` unchanged if no space is found.
    var unitSplitColumns: Set<Int> = []

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
        Grid(alignment: .leading, horizontalSpacing: columnSpacing, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                    let sortable = sortableColumns.contains(i) && sortValues != nil
                    HStack(spacing: 2) {
                        Text(h)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.muted)
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
            Rectangle().fill(DS.line).frame(height: 1)
            ForEach(order, id: \.self) { r in
                let row = rows[r]
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, cell in
                        let isNumeric = numericColumns.contains(c)
                        let cellFont: Font = isNumeric
                            ? .system(size: 12.5, weight: .regular, design: .monospaced)
                            : .system(size: 13, weight: .medium)
                        let cellColor: Color = isNumeric ? .primary : DS.inkSoft
                        let text = Group {
                            if unitSplitColumns.contains(c), let range = cell.range(of: " ", options: .backwards) {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text(cell[..<range.lowerBound])
                                    Text(cell[range.upperBound...])
                                        .padding(.leading, 1.5)
                                }
                            } else {
                                Text(cell)
                            }
                        }
                            .font(cellFont)
                            .monospacedDigit()
                            .foregroundStyle(cellColor)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if c == 0, swatches != nil {
                            let content = HStack(spacing: 8) { swatchView(row: r); text }
                            if let tip = cellTooltip?(r, c) {
                                content.hoverTip(tip)
                            } else {
                                content
                            }
                        } else if let tip = cellTooltip?(r, c) {
                            text.hoverTip(tip)
                        } else {
                            text
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 5).fill(hoveredRow == r ? DS.row : Color.clear))
                .contentShape(Rectangle())
                .onHover { hovering in
                    // Hover fill is a pure visual state on every row; the
                    // pointing-hand cursor stays gated on an actual `rowAction`
                    // so only genuinely clickable rows imply clickability.
                    if hovering {
                        hoveredRow = r
                        if rowAction != nil { NSCursor.pointingHand.push() }
                    } else {
                        if hoveredRow == r { hoveredRow = nil }
                        if rowAction != nil { NSCursor.pop() }
                    }
                }
                .onTapGesture {
                    rowAction?(r)
                }
            }
        }
    }

    @ViewBuilder
    private func swatchView(row: Int) -> some View {
        let swatch = swatches.flatMap { row < $0.count ? $0[row] : nil }
        RoundedRectangle(cornerRadius: 3)
            .fill(fillColor(for: swatch))
            .overlay {
                if case .outline = swatch {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(DS.line, lineWidth: 1)
                }
            }
            .frame(width: 10, height: 10)
    }

    private func fillColor(for swatch: TableSwatch?) -> Color {
        switch swatch {
        case .filled(let c): return c
        case .outline: return .clear
        case nil: return .clear
        }
    }
}

// MARK: - Pill flow (Login Items / agents / daemons)

struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(DS.inkSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().strokeBorder(DS.lineStrong, lineWidth: 1))
    }
}

struct PillFlow: View {
    let items: [String]
    var body: some View {
        if items.isEmpty {
            Text(L.sharedEmpty).font(.system(size: 11.5)).foregroundStyle(DS.muted)
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

/// Reciprocal hover emphasis between a legend row and its matching bar
/// segment (V2-FIX-MEM). `.neutral` is today's appearance verbatim.
enum LegendEmphasis {
    case neutral, active, dimmed
}

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String
    /// V2-FIX-UNITS follow-up: optional pre-split unit, mirroring `KPITileView`/
    /// `TMRow` — a literal space between `value` and `unit` in one `Text` reads
    /// as a wider gap than intended, so splitting into two `Text`s lets a tight
    /// `.padding(.leading, 1.5)` close the gap instead. (V2-FIX-MONO-FONT: this
    /// row is system-face, not mono, so `.padding(.leading, 1.5)` was originally
    /// sized for a mono glyph and is deliberately held as-is — re-tuning a gap
    /// is a size change and out of that block's scope.)
    var unit: String? = nil
    /// V2-FIX-MEM: when another legend row / bar segment is hovered, the
    /// uninvolved rows dim and keep the muted label; the involved row goes to
    /// full opacity with `DS.ink`. Default `.neutral` = today's appearance.
    var emphasis: LegendEmphasis = .neutral
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(emphasis == .active ? DS.ink : DS.muted)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .padding(.leading, 1.5)
                }
            }
        }
        .contentShape(Rectangle())
        .opacity(emphasis == .dimmed ? 0.45 : 1)
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

/// 11×11pt circular loading spinner (spec §2.7) — a `DS.lineStrong` base ring
/// with a `DS.accent`-colored quarter-turn arc at the top, continuously
/// rotating (360°/0.8 s, linear). Reduce Motion: mirrors `RainbowBorder`'s
/// continuous-rotation contract (see above) — the ring stays static, no spin.
struct DSSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(DS.lineStrong, lineWidth: 1.6)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(DS.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 11, height: 11)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

/// Size variants for `RainbowCapsuleButton`, matching the prototype's four
/// capsule sizes (C1/C4/C5/C6): `(font, horizontal padding, vertical padding)`.
enum DSCapsuleSize {
    case primary
    case card
    case toolbar
    case compact

    var font: Font {
        switch self {
        case .primary: return .system(size: 12, weight: .semibold)
        case .card: return .system(size: 11, weight: .semibold)
        case .toolbar: return .system(size: 11, weight: .semibold)
        case .compact: return .system(size: 10.5, weight: .semibold)
        }
    }

    var hPad: CGFloat {
        switch self {
        case .primary: return 14
        case .card: return 12
        case .toolbar: return 13
        case .compact: return 10
        }
    }

    var vPad: CGFloat {
        switch self {
        case .primary: return 8
        case .card: return 6
        case .toolbar: return 7
        case .compact: return 5
        }
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
    var size: DSCapsuleSize = .card
    let action: () -> Void

    @State private var hovering = false
    @State private var cursorPushed = false

    var body: some View {
        Button(action: action) {
            Text(title).font(size.font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .dsSwapInPlace(busy) { ProgressView().controlSize(.small) }
                .padding(.horizontal, size.hPad)
                .padding(.vertical, size.vPad)
                .background(Capsule().fill(DS.glass3))
                .overlay { Capsule().strokeBorder(DS.lineStrong, lineWidth: 1) }
                .rainbowBorder(isActive: hovering, recipe: recipe)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(title)
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
