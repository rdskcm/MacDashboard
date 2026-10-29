// Views/SharedUI.swift
// Shared chrome/primitives: chips, meter bar, KPI tile chrome, card background,
// status rows, tables, pills and the flow layout.

import SwiftUI
import AppKit

// MARK: - Chips (header)

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            // Load-average digits rewrite every fast tick; without monospaced digits the
            // chip's `.fixedSize` width changes with the digit shapes and jitters the
            // whole header row (V2-RELEASE re-review [N2]).
            .monospacedDigit()
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
/// (its only call site, the old `HeaderChipsView`, went with REDESIGN-HOME D; kept as the
/// `animation-value-size-coupling` reference).
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

    // Colour-only animation state: a `Color` in `@State` is not a layout input, and the
    // `withAnimation` transaction it fires in is separate from the one that commits a new
    // `label`, so the chip's geometry is never inside an animated transaction. Do not
    // replace this with `.animation(_:value:)` on the padded subtree — that reintroduces
    // the layout-jump bug the moment `tone` and `label` change together (they always do).
    @State private var animTone: Color? = nil
    private var shownTone: Color { animTone ?? tone }

    private var colorTransition: Animation {
        .easeInOut(duration: reduceMotion ? DSMotion.reduceMotionFallback : 0.18)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(shownTone)
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
        // Prototype gives this chip 6pt vertical pad; this app uses 8.5 on
        // purpose to match the header refresh button's height
        // height — user decision 2026-08-10 (V2-FIX-HEADER-CHROME). Do not
        // "fix" this back to 6 in a future optical audit.
        .padding(.vertical, 8.5)
        .background(Capsule().fill(shownTone.opacity(0.14)))
        .overlay(Capsule().strokeBorder(shownTone.opacity(0.32), lineWidth: 1))
        .onAppear { animTone = tone }
        .onChange(of: tone) { _, newTone in
            withAnimation(colorTransition) { animTone = newTone }
        }
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
    /// tiles' live bars — 0.45 s `cubic-bezier(0.22,0.61,0.36,1)` — while Disk
    /// and Battery must keep snapping instantly. Defaults to `false` so any
    /// call site that doesn't opt in keeps the (correct, already-audited)
    /// no-animation behavior.
    var animated: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let f = CGFloat(min(max(fraction, 0), 1))
        ZStack(alignment: .leading) {
            dsRecessedTrack(in: Capsule())
            // V2-RELAYOUT-COREANIM: the fill is a CALayer animated by CoreAnimation
            // (BarFillLayer.swift), not a SwiftUI-animated view. Do NOT attach
            // `.animation(_:value:)` here and do NOT put a GeometryReader back in
            // this subtree — either one re-creates the per-display-frame SwiftUI
            // ViewGraph cost this block removed (and the second also re-opens the
            // V2-FIX-BARFLY 0 -> real-width fly-in).
            BarFillLayer(spans: [BarSpan(key: "fill", fraction: f, color: color)],
                         layout: .single(minWidth: 2, cornerRadius: nil),
                         animated: animated && !reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 6)
    }
}

// MARK: - Severity -> v2 tone map

/// crit/serious -> DS.hot, warn/info -> DS.amber, good -> DS.green. Never the
/// legacy `Severity.color` (Theme.swift) — that palette belongs to the v1 UI.
/// Hoisted here (V2-TILES) from the former attention card, its original
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
/// 2. value (30pt + 5pt gap, one line, never wraps): tabular monospaced `value` +
///    `unit` (both keep their intrinsic width) + the shrinkable/ellipsizable
///    `outOf` ("из N");
/// 3. visual (41pt): whatever `visual` supplies — typically a `MeterBar`, or
///    for CPU the sparkline occupying the same zone;
/// 4. footer (31pt): `footer` text pinned to the band's bottom edge.
///
/// Generic over the two optional per-tile views (`EmptyView` when absent) —
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

    /// Measured width of `outOf`'s flexible slot (see `valueRow`'s comment).
    /// Starts at 0 — same "settle from zero" convention `MeterBar.trackWidth`
    /// already uses in this file — so a fresh mount never has a stale/wrong
    /// width to truncate against; it corrects within the same layout pass.
    @State private var outOfSlotWidth: CGFloat = 0

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

    private static var outOfLeadingPad: CGFloat { 5 }
    private static var outOfFontSize: CGFloat { 13 }

    /// `value`/`unit` keep their intrinsic width (`fixedSize`) so they never
    /// truncate; `outOf` is the one element allowed to shrink/ellipsize when
    /// the column is tight (the five-equal-column grid depends on this).
    ///
    /// `outOf` does NOT rely on `Text`'s own `lineLimit`/`truncationMode` —
    /// confirmed by measuring the actual proposed widths at the 900pt window
    /// minimum (V2-FIX-OPTICAL-2/C1): Disk's residual slot there was ~35pt
    /// and truncated to "of…" correctly, but Swap's was ~14pt (one digit
    /// wider `value` — "534.4" vs "91.4" — leaves less remainder) and
    /// `Text` painted the *un*truncated string past its own reported bounds
    /// instead of ellipsizing, with the overflow hard-clipped mid-glyph by
    /// the card's rounded-rect surface. So `Text`'s built-in truncation is
    /// only reliable above some width it doesn't document and this view
    /// can't predict — the fix truncates the STRING ourselves with real
    /// AppKit font metrics (`truncatedToFit`, using the *measured* slot
    /// width) before it ever reaches `Text`, then renders it with
    /// `fixedSize` so `Text` never needs to truncate at draw time: it either
    /// gets a string already provably narrower than the slot (real ellipsis
    /// if trimmed) or, when even a single trimmed character + "…" doesn't
    /// fit, an empty string (renders nothing — never a partial glyph).
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
                let budget = max(0, outOfSlotWidth - Self.outOfLeadingPad)
                // The fitted string is drawn as an OVERLAY on an empty, zero-ideal
                // slot, and never as a laid-out sibling. That separation is the
                // whole point: a `fixedSize` Text placed directly in this HStack
                // reports its fitted width as the slot's MINIMUM, so a tile whose
                // `outOf` currently fits refuses to compress while its neighbours
                // keep shrinking — the five columns stop being equal. And because
                // the fitted width is itself derived from the measured slot, that
                // version latched: widening the window and narrowing it again left
                // the tiles unevenly sized until relaunch. An overlay contributes
                // nothing to sizing, so the measurement stays a one-way read of
                // what the HStack proposed.
                //
                // `Text("")` is the slot: zero width, but it still carries the
                // 13pt font's baseline, which is what keeps `outOf` sitting on the
                // same baseline as `value` under the HStack's `.firstTextBaseline`.
                Text("")
                    .font(.system(size: Self.outOfFontSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                        Text(Self.truncatedToFit(outOf, maxWidth: budget, fontSize: Self.outOfFontSize))
                            .font(.system(size: Self.outOfFontSize))
                            .foregroundStyle(DS.muted)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.leading, Self.outOfLeadingPad)
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { w in
                        outOfSlotWidth = w
                    }
            }
        }
        .frame(height: 30, alignment: .leading)
        // The 27pt value sits 5pt lower than the prototype's band skeleton: with a
        // header capsule present the satellite-to-digits gap measured only 6pt
        // (11pt in the capsule-less tiles). Paid for by the visual band below, so
        // the tile's total height is unchanged (user decision, V2-KPI-POLISH).
        .padding(.top, 5)
    }

    /// Trims `text` to the longest prefix (+ "…") that measures at or under
    /// `maxWidth` at `fontSize` using real AppKit glyph metrics — never
    /// SwiftUI's own `Text` truncation, which this file's `valueRow` comment
    /// documents as unreliable at very small proposed widths. Returns ""
    /// (nothing drawn) if even one trimmed character + "…" doesn't fit.
    private static func truncatedToFit(_ text: String, maxWidth: CGFloat, fontSize: CGFloat) -> String {
        guard maxWidth > 0, !text.isEmpty else { return "" }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: attrs).width }
        if width(text) <= maxWidth { return text }
        var candidate = text
        while !candidate.isEmpty {
            candidate.removeLast()
            let trimmed = candidate + "…"
            if width(trimmed) <= maxWidth { return trimmed }
        }
        return ""
    }

    private var visualZone: some View {
        visual()
            .frame(maxWidth: .infinity)
            .frame(height: 41, alignment: .center)
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

/// Shared "surface" look (rounded rect + hairline border) reused by KPITileView, the QuietStrip cards and the
/// collapsed-by-default Energy card.
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

/// L.sharedUnavailable / spinner placeholder for report sections not yet collected.
struct SectionStateView: View {
    let done: Bool
    var body: some View {
        if done {
            Text(L.sharedUnavailable)
                .font(.callout)
                .foregroundStyle(DS.muted)
        } else {
            HStack(spacing: 8) {
                DS3Spinner(role: .track, size: 13)
                Text(L.sharedCollectingData)
                    .font(.callout)
                    .foregroundStyle(DS.muted)
            }
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

    /// Leading inset the column-0 HEADER needs to line up with swatched value cells:
    /// `swatchView`'s 10 pt swatch plus the value row's 8 pt `HStack` spacing.
    /// Column 0 only, and only when `swatches` is set (V2-POLISH B5).
    private static let swatchColumnInset: CGFloat = 18

    @State private var hoveredRow: Int? = nil

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: columnSpacing, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                    Text(h)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.muted)
                        .padding(.leading, i == 0 && swatches != nil ? Self.swatchColumnInset : 0)
                        .gridColumnAlignment(numericColumns.contains(i) ? .trailing : .leading)
                }
            }
            Rectangle().fill(DS.line).frame(height: 1)
            ForEach(rows.indices, id: \.self) { r in
                let row = rows[r]
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, cell in
                        let isNumeric = numericColumns.contains(c)
                        let cellFont: Font = isNumeric
                            ? .system(size: 12.5, weight: .regular, design: .monospaced)
                            : .system(size: 13, weight: .medium)
                        let cellColor: Color = isNumeric ? DS.ink : DS.inkSoft
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
                    // Hover fill is a pure visual state on every row; the table itself is
                    // read-only, so nothing here is clickable.
                    if hovering {
                        hoveredRow = r
                    } else {
                        if hoveredRow == r { hoveredRow = nil }
                    }
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
            let size = Self.measure(subview, maxWidth: maxWidth)
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

    /// Ideal size, re-measured at the row width when the ideal is wider than
    /// the row — so an over-wide subview truncates instead of overflowing.
    /// Subviews that fit are measured exactly as before (`.unspecified`).
    private static func measure(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, ideal.width > maxWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = Self.measure(subview, maxWidth: bounds.width)
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

/// Human-readable one-liner for the live `brew upgrade` progress state.
/// Views-layer helper (app-only) — reads `L` at call time so it follows
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

// MARK: - Shared pointing-hand hover cursor

/// Balances `NSCursor.pointingHand.push()`/`.pop()` for a hover affordance.
///
/// `pushed` is tracked explicitly rather than inferred from `hovering`, and it is
/// popped on THREE exits, not one:
///   * hover-exit — the ordinary case;
///   * `isEnabled` going false mid-hover (a button disabled under a stationary
///     cursor, a plate turning non-interactive after its action ran);
///   * `.onDisappear` — SwiftUI does not fire `onHover`'s exit callback for a view
///     removed from the hierarchy while the cursor is still over it (force-quit
///     removes a process row, a disk is unplugged, a card is rebuilt on refresh),
///     so without this the push leaks and the pointing-hand cursor sticks app-wide.
///
/// `hovering` is optional: sites that keep their own hover visual pass a binding,
/// sites that only need the cursor pass nothing. While `isEnabled` is false the
/// binding is left alone entirely, so a non-interactive element shows no hover
/// visual either — that gating is load-bearing for the former attention card's plates.
///
/// `.pointerStyle(.link)` (macOS 15+) is within the package's macOS 26 floor and
/// could replace this modifier; that replacement has not been made yet.
struct PointingHandOnHover: ViewModifier {
    var isEnabled: Bool = true
    var hovering: Binding<Bool>? = nil
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                guard isEnabled else { return }
                hovering?.wrappedValue = isHovering
                if isHovering {
                    if !pushed { NSCursor.pointingHand.push(); pushed = true }
                } else if pushed {
                    NSCursor.pop(); pushed = false
                }
            }
            .onChange(of: isEnabled) { _, nowEnabled in
                guard !nowEnabled else { return }
                hovering?.wrappedValue = false
                if pushed { NSCursor.pop(); pushed = false }
            }
            .onDisappear {
                if pushed { NSCursor.pop(); pushed = false }
            }
    }
}

extension View {
    /// Pointing-hand cursor on hover, balanced on hover-exit, on disable and on unmount.
    func pointingHandOnHover(isEnabled: Bool = true, hovering: Binding<Bool>? = nil) -> some View {
        modifier(PointingHandOnHover(isEnabled: isEnabled, hovering: hovering))
    }
}

// MARK: - "Ещё N" / "Свернуть" toggle (item grid overflow)

struct MoreLessToggle: View {
    let expanded: Bool
    let collapsedLabel: String
    let expandedLabel: String
    let action: () -> Void

    private var label: String { expanded ? expandedLabel : collapsedLabel }

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS.accentInk)
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityLabel(label)
    }
}
