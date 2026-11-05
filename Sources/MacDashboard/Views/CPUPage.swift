// Views/CPUPage.swift
// REDESIGN-CPU: the CPU section page (handoff 03-cpu) on the shared §8 blocks (SectionPageBlocks.swift):
// page bar (Back, icon, title, sub line, state tag) and the restyled Processes card. GPU-UTILIZATION: it is
// now the SoC page: CPU card, GPU card, chip-temperature block (SoCCards) and the Processes card.
// All texts and states come from the pure `CPUPageModel`; this file only draws them.

import SwiftUI

@MainActor
struct CPUPage: View {
    let model: AppModel
    let router: NavigationRouter

    @State private var pulse: CardID? = nil

    /// Reads no live model field (only `router.navigationSerial` / `destination`): `CPUPageBar` and
    /// `SoCCards` do the reading, so a 2 s tick never re-evaluates the page itself (same rule as `HomeNowCard`).
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SoCCards(model: model)
                        .id(CardID.cpu)
                        .sectionFocusPulse(pulse == .cpu)
                        .ds3Appear(delay: 0.08)
                    ProcessListCard(model: model, initialMetric: .cpu, onConfirmShown: { router.isInlineConfirmOpen = $0 })
                        .id(CardID.procs)
                        .sectionFocusPulse(pulse == .procs)
                        .ds3Appear(delay: 0.14)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.top, 16, for: .scrollContent)
            .ds3KeepFocusScroll(pulse, top: .cpu, proxy: proxy, router: router)
            .safeAreaInset(edge: .top, spacing: 0) { CPUPageBar(model: model, onBack: { _ = router.back() }) }
            .task(id: router.navigationSerial) {
                // Deep link: scroll the focused card under the bar (the CPU card is already on top) and pulse it.
                let d = router.destination
                guard d.page == .cpu, let f = d.focus else { return }
                if f == .procs { proxy.scrollTo(CardID.procs, anchor: .top) }
                pulse = f
                try? await Task.sleep(for: .seconds(3))
                pulse = nil
            }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
        .onDisappear { router.isInlineConfirmOpen = false }
    }
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it
/// (Tests/MacDashboardTests/ContentSnapshotTests.swift).
@MainActor
struct CPUPageBar: View {
    let model: AppModel
    let onBack: () -> Void

    var body: some View {
        let m = CPUPageModel.make(cpuPageInput(model))
        SectionPageBar(symbol: Page.cpu.symbol, title: Page.cpu.title, sub: m.sub, subIsFailure: m.subIsFailure,
                       onBack: onBack) {
            DS3Tag(tone: tone(m.tag), text: m.tagText).help(m.tagText)
        } trailing: {
            EmptyView()
        }
    }

    private func tone(_ t: CPUTagKind) -> DS3Tag.Tone {
        switch t {
        case .ok: return .green
        case .high: return .amber
        case .loading: return .neutral
        case .failed: return .hot
        }
    }
}

// MARK: - SoC cards

/// Internal: the visual fixture renders it. CPU card, GPU card (equal height) and the chip-temperature block.
@MainActor
struct SoCCards: View {
    let model: AppModel

    var body: some View {
        let m = CPUPageModel.make(cpuPageInput(model))
        VStack(alignment: .leading, spacing: 16) {
            EqualColumnsLayout(columns: 2, spacing: 16, fillsHeight: true) {
                DS3Card(title: L.commonCPU, caption: m.caption, fillsHeight: true) {
                    if m.showsWait {
                        SectionWait(text: L.commonCollectingData)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            if let note = m.failureNote { SectionNote(tone: DS3.hot, text: note) }
                            SectionHero(label: L.cpuUsage, value: m.hero.value, fraction: m.hero.fraction, note: m.hero.note,
                                        tone: m.hero.high ? DS3.amber : DS3.accent,
                                        toneInk: m.hero.high ? DS3.amberInk : DS3.accentInk,
                                        dimmed: m.hero.dimmed)
                                .fixedSize(horizontal: false, vertical: true)
                            EqualColumnsLayout(columns: 2, spacing: 8, fillsHeight: true) {
                                ForEach(m.tiles.indices, id: \.self) { tile(m.tiles[$0]) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                DS3Card(title: L.commonGPU, fillsHeight: true) {
                    if m.showsWait {
                        SectionWait(text: L.commonCollectingData)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHero(label: L.cpuUsage, value: m.gpu.value, fraction: m.gpu.fraction, note: m.gpu.note,
                                        tone: DS3.accent, toneInk: DS3.accentInk, dimmed: m.gpu.dimmed)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            DS3Card(title: L.socChipTemperature) {
                if m.showsWait {
                    SectionWait(text: L.commonCollectingData)
                } else {
                    tile(m.temperature)
                }
            }
        }
    }

    /// State colour from the dot (CPULoad.socLevel via CPUPageModel): hot → hot, warm → amber, else green note / plain value.
    /// The note ink comes from the thermal tone when present (THERMAL-STATE); the tooltip is attached only when present.
    @ViewBuilder
    private func tile(_ t: CPUTileModel) -> some View {
        let ink: Color = t.dot == .hot ? DS3.hotInk : (t.dot == .amber ? DS3.amberInk : DS3.greenInk)
        let noteInk: Color = t.noteTone.map { tone -> Color in
            switch tone {
            case .green: return DS3.greenInk
            case .neutral: return DS3.inkSoft
            case .amber: return DS3.amberInk
            case .hot: return DS3.hotInk
            }
        } ?? ink
        let base = SectionTile(label: t.label, value: t.value, note: t.note,
                               noteInk: noteInk,
                               dot: t.dot.map { $0 == .hot ? DS3.hot : ($0 == .amber ? DS3.amber : DS3.green) },
                               valueInk: t.dimmed ? DS3.muted : ((t.dot == .hot || t.dot == .amber) ? ink : DS3.ink))
        if let h = t.help { base.help(h) } else { base }
    }
}

@MainActor
private func cpuPageInput(_ model: AppModel) -> CPUPageModel.Input {
    CPUPageModel.Input(cpu: model.cpu, load: model.load, ncpu: model.ncpu, chip: model.headerSystem?.chip,
                       socTempC: model.socTempC, block: model.cpuBlock.phase, highSince: model.cpuHighSince,
                       now: model.lastSampleAt, intervalSeconds: model.settings.fastIntervalSeconds,
                       thermal: model.thermal, gpuUtil: model.gpuUtil)
}
