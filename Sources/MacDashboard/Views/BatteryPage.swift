// Views/BatteryPage.swift
// REDESIGN-BATTERY: the Battery section page (handoff 06-battery) on the shared §8 blocks; replaces the battery popover. All texts and states come from the pure BatteryPageModel; this file only draws them and runs the 3 s read loop.

import SwiftUI

@MainActor
struct BatteryPage: View {
    let model: DashboardModel
    let router: NavigationRouter
    let narrow: Bool

    @State private var pulse: CardID? = nil


    /// Reads no live model field (only `router.navigationSerial` / `destination`): the bar and the cards do the
    /// reading (same rule as `MemoryPage`).
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BatteryNowCard(model: model, narrow: narrow)
                        .id(CardID.batnow)
                        .sectionFocusPulse(pulse == .batnow)
                        .ds3Appear(delay: 0.08)
                    BatteryHealthCard(model: model, narrow: narrow)
                        .id(CardID.bathero)
                        .sectionFocusPulse(pulse == .bathero)
                        .ds3Appear(delay: 0.14)
                    BatteryChargingCard(model: model)
                        .id(CardID.batchg)
                        .sectionFocusPulse(pulse == .batchg)
                        .ds3Appear(delay: 0.20)
                    BatteryLifetimeCard(model: model)
                        .id(CardID.batlife)
                        .sectionFocusPulse(pulse == .batlife)
                        .ds3Appear(delay: 0.26)
                    BatteryPassportCard(model: model)
                        .id(CardID.batid)
                        .sectionFocusPulse(pulse == .batid)
                        .ds3Appear(delay: 0.32)
                    BatteryHistoryCard(model: model, router: router)
                        .id(CardID.bathist)
                        .sectionFocusPulse(pulse == .bathist)
                        .ds3Appear(delay: 0.38)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) { BatteryPageBar(model: model, onBack: { _ = router.back() }) }
            .task(id: router.navigationSerial) {
                // Deep link: scroll the focused card under the bar (Now is already on top) and pulse it.
                let d = router.destination
                guard d.page == .battery, let f = d.focus else { return }
                if f != .batnow { proxy.scrollTo(f, anchor: .top) }
                pulse = f
                try? await Task.sleep(for: .seconds(3))
                pulse = nil
            }
            .task {
                // The 3 s ioreg loop lives with the page: cancelled by SwiftUI when the page unmounts. Never under the
                // visual fixture (it would overwrite the fixture detail with live data).
                guard !VisualFixture.isRequested else { return }
                while !Task.isCancelled {
                    await model.readBatteryNow()
                    try? await Task.sleep(for: .seconds(BatteryPageModel.refreshSeconds))
                }
            }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
    }
}

// MARK: - Input and mapping helpers

@MainActor
private func batteryPageInput(_ model: DashboardModel) -> BatteryPageModel.Input {
    .init(detail: model.batteryDetail, condition: model.report.battery?.condition ?? model.battery?.condition,
          block: model.batteryBlock.phase, history: model.history.mac_history)
}

private func panelTone(_ t: BatteryTone) -> (Color, Color) {
    switch t {
    case .green: return (DS3.green, DS3.greenInk)
    case .amber: return (DS3.amber, DS3.amberInk)
    case .hot: return (DS3.hot, DS3.hotInk)
    case .neutral: return (DS3.muted, DS3.inkSoft)
    }
}

private func valueInk(_ t: BatteryTone?) -> Color {
    switch t {
    case nil: return DS3.ink
    case .neutral?: return DS3.muted
    case .green?: return DS3.greenInk
    case .amber?: return DS3.amberInk
    case .hot?: return DS3.hotInk
    }
}

private func dotColor(_ t: BatteryTone?) -> Color? {
    switch t {
    case .green?: return DS3.green
    case .amber?: return DS3.amber
    case .hot?: return DS3.hot
    default: return nil
    }
}

private func noteTone(_ t: BatteryTone) -> Color {
    switch t {
    case .amber: return DS3.amber
    case .hot: return DS3.hot
    case .green: return DS3.green
    case .neutral: return DS3.muted
    }
}

private func tagTone(_ k: BatteryTagKind) -> DS3Tag.Tone {
    switch k {
    case .healthy: return .green
    case .worn: return .amber
    case .service: return .hot
    case .reading: return .neutral
    case .failed: return .hot
    }
}

@MainActor
private func tile(_ t: BatteryTileModel) -> some View {
    SectionTile(label: t.label, value: t.value, note: t.note, noteInk: DS3.muted,
                dot: dotColor(t.dot), valueInk: valueInk(t.valueTone))
}

@MainActor
private func hero(_ h: BatteryHeroModel) -> some View {
    SectionHero(label: h.label, value: h.value, fraction: h.fraction, note: h.note,
                tone: panelTone(h.tone).0, toneInk: panelTone(h.tone).1, dimmed: h.dimmed)
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it. No Refresh: readings update every 3 s.
@MainActor
struct BatteryPageBar: View {
    let model: DashboardModel
    let onBack: () -> Void

    var body: some View {
        let m = BatteryPageModel.make(batteryPageInput(model))
        SectionPageBar(symbol: m.symbol, title: Page.battery.title, sub: m.sub, subIsFailure: m.subIsFailure,
                       onBack: onBack) {
            DS3Tag(tone: tagTone(m.tag), text: m.tagText).help(m.tagText)
        } trailing: {
            EmptyView()
        }
    }
}

// MARK: - Now card

@MainActor
struct BatteryNowCard: View {
    let model: DashboardModel
    let narrow: Bool

    var body: some View {
        let m = BatteryPageModel.make(batteryPageInput(model))
        DS3Card(title: L.batterySectionNow, caption: m.nowCaption) {
            if m.showsWait {
                SectionWait(text: L.batteryLoadingText)
            } else if let note = m.failureNote {
                VStack(alignment: .leading, spacing: 16) {
                    SectionNote(tone: DS3.hot, text: note)
                    EqualColumnsLayout(columns: narrow ? 2 : m.nowColumns, spacing: 8) {
                        ForEach(m.nowTiles.indices, id: \.self) { tile(m.nowTiles[$0]) }
                    }
                }
            } else if let h = m.nowHero {
                HeroSplitLayout {
                    hero(h)
                    EqualColumnsLayout(columns: 2, spacing: 8, fillsHeight: true) {
                        ForEach(m.nowTiles.indices, id: \.self) { tile(m.nowTiles[$0]) }
                    }
                }
            }
        }
    }
}

// MARK: - Capacity and health

@MainActor
struct BatteryHealthCard: View {
    let model: DashboardModel
    let narrow: Bool

    var body: some View {
        let m = BatteryPageModel.make(batteryPageInput(model))
        if m.showsDetailCards {
            DS3Card(title: L.batterySectionCapacity) {
                VStack(alignment: .leading, spacing: 16) {
                    HeroSplitLayout {
                        hero(m.healthHero)
                        EqualColumnsLayout(columns: narrow ? 2 : 3, spacing: 8, fillsHeight: true) {
                            ForEach(m.healthTiles.indices, id: \.self) { tile(m.healthTiles[$0]) }
                        }
                    }
                    if let n = m.healthNote {
                        SectionNote(tone: noteTone(n.tone), text: n.text,
                                    button: (L.batBatterySettings, L.batBatterySettingsA11y, false,
                                             { AdviceActionRunner.openPane(AdvicePanes.battery) }),
                                    buttonIdentifier: "battery-settings")
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Charging

@MainActor
struct BatteryChargingCard: View {
    let model: DashboardModel

    var body: some View {
        let m = BatteryPageModel.make(batteryPageInput(model))
        if m.showsDetailCards && m.showsCharging {
            DS3Card(title: L.batterySectionCharging, caption: L.batChargingCaption) {
                EqualColumnsLayout(columns: 3, spacing: 8) {
                    ForEach(m.chargingTiles.indices, id: \.self) { tile(m.chargingTiles[$0]) }
                }
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Lifetime

@MainActor
struct BatteryLifetimeCard: View {
    let model: DashboardModel

    var body: some View {
        let m = BatteryPageModel.make(batteryPageInput(model))
        if m.showsDetailCards && !m.lifetimeTiles.isEmpty {
            DS3Card(title: L.batterySectionLifetime, caption: L.batLifetimeCaption) {
                EqualColumnsLayout(columns: 3, spacing: 8) {
                    ForEach(m.lifetimeTiles.indices, id: \.self) { tile(m.lifetimeTiles[$0]) }
                }
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Passport

@MainActor
struct BatteryPassportCard: View {
    let model: DashboardModel

    var body: some View {
        let m = BatteryPageModel.make(batteryPageInput(model))
        if m.showsDetailCards && !m.passportTiles.isEmpty {
            DS3Card(title: L.batteryDetailPassportSection) {
                EqualColumnsLayout(columns: 3, spacing: 8) {
                    ForEach(m.passportTiles.indices, id: \.self) { tile(m.passportTiles[$0]) }
                }
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Capacity history

@MainActor
struct BatteryHistoryCard: View {
    let model: DashboardModel
    let router: NavigationRouter

    var body: some View {
        let m = BatteryPageModel.make(batteryPageInput(model))
        if m.showsDetailCards && !m.historyRows.isEmpty {
            DS3Card(title: L.batHistoryTitle, caption: m.historyCaption) {
                VStack(alignment: .leading, spacing: 8) {
                    list(m.historyRows)
                    foot
                }
            }
        } else {
            EmptyView()
        }
    }

    private func list(_ rows: [BatteryHistoryRow]) -> some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.id) { r in
                HStack(spacing: 10) {
                    Text(r.label).font(.system(size: 14)).foregroundStyle(DS3.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(r.value)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit().foregroundStyle(DS3.ink).lineLimit(1)
                        .frame(minWidth: 64, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
    }

    private var foot: some View {
        Button(L.batHistoryFoot) {
            router.navigate(to: Destination(.history, focus: .hist, historyMetric: .battery))
        }
        .buttonStyle(DS3ButtonStyle(kind: .text, height: 30, hPad: 11, fontSize: 12.5))
        .accessibilityLabel(L.batHistoryFootA11y)
        .accessibilityIdentifier("battery-history-link")
        .padding(.leading, 6)
    }
}
