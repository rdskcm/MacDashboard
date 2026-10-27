// Views/HomeSectionTiles.swift
// REDESIGN-HOME (stage B): the "Sections" header and the grid of section tiles (CPU … History).
// Every label, tag and figure comes from `HomeModel.tiles` (`shared-vocabulary`).

import SwiftUI

@MainActor
struct HomeSectionsHeader: View {
    let model: DashboardModel

    var body: some View {
        // Seven tiles on a Mac without a battery, eight otherwise (`HomeModel.tiles`).
        let count = (model.battery ?? model.homeReport.battery) != nil ? 8 : 7
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L.homeSections).font(.system(size: 18, weight: .bold)).tracking(-0.22)
            Text(L.homeSectionCount(count)).font(.system(size: 13)).foregroundStyle(DS3.muted)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
struct HomeSectionsGrid: View {
    let model: DashboardModel
    let router: NavigationRouter
    let tier: WidthTier
    /// `false` only in the offscreen visual harness (see `homeEntrance`).
    var animatesEntrance = true

    var body: some View {
        let tiles = HomeInput.tiles(model)
        // Equal columns (`equal-split-columns`) from a non-lazy layout: eight static tiles gain nothing from
        // laziness, and a lazy grid leaves the tiles below the fold out of the accessibility tree (the visual
        // and perf harnesses press `home-tile-*` by AX identifier without scrolling).
        EqualColumnsLayout(columns: tier.isNarrow ? 2 : 4, spacing: 16) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { i, tile in
                HomeSectionTile(tile: tile) { router.navigate(to: tile.destination) }
                    .homeEntrance(delay: 0.18 + 0.05 * Double(i), enabled: animatesEntrance)
            }
        }
    }
}

struct HomeSectionTile: View {
    let tile: HomeTile
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                top
                if tile.skeleton {
                    HomeShimmerCapsule()
                } else {
                    DS3Tag(tone: tile.tagTone.ds3Tag, text: tile.tagText).help(tile.tagText)
                }
                Spacer(minLength: 0)
                kvGrid
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 188)
            .ds3GlassCard(cornerRadius: 30)
            .homeHotRing(tile.hotRing)
        }
        .buttonStyle(DS3TileButtonStyle())
        .accessibilityLabel(tile.skeleton ? tile.name : "\(tile.name), \(tile.tagText)")
        .accessibilityIdentifier("home-tile-\(tile.page.rawValue)")
    }

    private var top: some View {
        HStack(spacing: 12) {
            HomeIconTile(symbol: tile.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .help(tile.name)
                Text(tile.sub)
                    .font(.system(size: 12.5))
                    .foregroundStyle(tile.subIsFailure ? DS3.hotInk : DS3.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .help(tile.sub)
            }
        }
    }

    private var kvGrid: some View {
        EqualColumnsLayout(columns: 2, spacing: 8) {
            ForEach(Array(tile.kvs.enumerated()), id: \.offset) { _, kv in
                HomeMiniKV(kv: kv)
            }
        }
    }
}

/// Equal-width columns, row height = tallest cell. The column width comes from the proposed width only, never
/// from a measurement of the cells, so nothing feeds back (`no-measured-size-feedback`).
/// `fillsHeight`: inside `HeroSplitLayout` the rows stretch equally to the proposed height (CSS auto rows under
/// `align-content: normal`, CPU.dc.html:76-83; MOCKUP-DEVIATIONS-REVIEW D5).
struct EqualColumnsLayout: Layout {
    var columns: Int
    var spacing: CGFloat
    var fillsHeight = false

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rowHeights(_ subviews: Subviews, columnWidth w: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        } else {
            // nil or infinite proposal: the cells' ideal width (never infinite, so the result is always finite).
            let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.filter { $0.isFinite }.max() ?? 0
            width = widest * CGFloat(columns) + spacing * CGFloat(columns - 1)
        }
        let heights = rowHeights(subviews, columnWidth: columnWidth(width))
        let content = CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
        if fillsHeight, let h = proposal.height, h.isFinite, h > content.height {
            return CGSize(width: width, height: h)
        }
        return content
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = columnWidth(bounds.width)
        let heights = rowHeights(subviews, columnWidth: w)
        let content = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        let extra = fillsHeight && bounds.height > content && !heights.isEmpty
            ? (bounds.height - content) / CGFloat(heights.count) : 0
        var y = bounds.minY
        for (row, rowHeight) in heights.enumerated() {
            let h = rowHeight + extra
            for col in 0..<columns {
                let i = row * columns + col
                guard i < subviews.count else { break }
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(col) * (w + spacing), y: y),
                                  anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
            }
            y += h + spacing
        }
    }
}

/// 44 × 44 rounded icon (00 §4.3).
struct HomeIconTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 21))
            .foregroundStyle(DS3.accentInk)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS3.chip))
            .ds3InsetRims(RoundedRectangle(cornerRadius: 16, style: .continuous), top: DS3.rimHi, ring: DS3.lineStrong)
            .accessibilityHidden(true)
    }
}

/// Mini key/value cell of a tile (00 §4.5).
struct HomeMiniKV: View {
    let kv: HomeKV

    private var valueColor: Color {
        switch kv.tone {
        case nil: return DS3.ink
        case .hot?: return DS3.hotInk
        case .amber?: return DS3.amberInk
        case .neutral?: return DS3.muted
        case .green?: return DS3.greenInk
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(kv.label).font(.system(size: 12)).foregroundStyle(DS3.muted).lineLimit(1).help(kv.label)
            Text(kv.value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(valueColor).lineLimit(1).help(kv.value)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ds3RowPanel(cornerRadius: 16)
    }
}
