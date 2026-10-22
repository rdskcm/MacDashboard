// Views/CPUPage.swift
// REDESIGN-CPU: the CPU section page (handoff 03-cpu) on the shared §8 blocks (SectionPageBlocks.swift):
// page bar (Back, icon, title, sub line, state tag), «CPU · live snapshot» card (hero + three
// tiles, loading / failed states) and the restyled Processes card. All texts and states come from the
// pure `CPUPageModel`; this file only draws them.

import SwiftUI

@MainActor
struct CPUPage: View {
    let model: DashboardModel
    let router: NavigationRouter
    let onBack: () -> Void

    @State private var pulse: CardID? = nil

    /// Reads no live model field (only `router.navigationSerial` / `destination`): `CPUPageBar` and
    /// `CPUUsageCard` do the reading, so a 2 s tick never re-evaluates the page itself (same rule as `HomeNowCard`).
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CPUUsageCard(model: model)
                        .id(CardID.cpu)
                        .sectionFocusPulse(pulse == .cpu)
                        .ds3Appear(delay: 0.08)
                    ProcessListCard(model: model, initialMetric: .cpu, onConfirmShown: { router.isInlineConfirmOpen = $0 })
                        .id(CardID.procs)
                        .sectionFocusPulse(pulse == .procs)
                        .ds3Appear(delay: 0.14)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) { CPUPageBar(model: model, onBack: onBack) }
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

/// Internal (not private): the visual fixture renders it (tools/visual/content_states.swift).
@MainActor
struct CPUPageBar: View {
    let model: DashboardModel
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

// MARK: - CPU card

/// Internal: the visual fixture renders it.
@MainActor
struct CPUUsageCard: View {
    let model: DashboardModel

    var body: some View {
        let m = CPUPageModel.make(cpuPageInput(model))
        DS3Card(title: L.commonCPU, caption: m.caption) {
            if m.showsWait {
                SectionWait(text: L.commonCollectingData)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if let note = m.failureNote {
                        SectionNote(tone: DS3.hot, text: note,
                                    button: (L.commonTryAgain, L.cpuTryAgainA11y, model.cpuRefreshing, { model.refreshCPUNow() }))
                    }
                    HeroSplitLayout {
                        SectionHero(label: L.cpuUsage, value: m.hero.value, fraction: m.hero.fraction, note: m.hero.note,
                                    tone: m.hero.high ? DS3.amber : DS3.accent,
                                    toneInk: m.hero.high ? DS3.amberInk : DS3.accentInk,
                                    dimmed: m.hero.dimmed)
                        EqualColumnsLayout(columns: 3, spacing: 8) {
                            ForEach(m.tiles.indices, id: \.self) { tile(m.tiles[$0]) }
                        }
                    }
                }
            }
        }
    }

    /// State colour from the dot (CPULoad.socLevel via CPUPageModel): hot → hot, warm → amber, else green note / plain value.
    private func tile(_ t: CPUTileModel) -> some View {
        let ink: Color = t.dot == .hot ? DS3.hotInk : (t.dot == .amber ? DS3.amberInk : DS3.greenInk)
        return SectionTile(label: t.label, value: t.value, note: t.note,
                           noteInk: ink,
                           dot: t.dot.map { $0 == .hot ? DS3.hot : ($0 == .amber ? DS3.amber : DS3.green) },
                           valueInk: t.dimmed ? DS3.muted : ((t.dot == .hot || t.dot == .amber) ? ink : DS3.ink))
    }
}

@MainActor
private func cpuPageInput(_ model: DashboardModel) -> CPUPageModel.Input {
    CPUPageModel.Input(cpu: model.cpu, load: model.load, ncpu: model.ncpu, chip: model.headerSystem?.chip,
                       socTempC: model.socTempC, block: model.cpuBlock.phase, highSince: model.cpuHighSince,
                       now: model.lastSampleAt, intervalSeconds: AppSettings.shared.fastIntervalSeconds)
}
