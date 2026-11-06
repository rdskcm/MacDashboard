// Views/CPUPage.swift
// REDESIGN-CPU: the CPU section page (handoff 03-cpu) on the shared §8 blocks (SectionPageBlocks.swift):
// page bar (Back, icon, title, sub line, state tag) and the restyled Processes card. GPU-UTILIZATION: it is
// now the SoC page. SOC-DETAILS Stage 2 (mockups/SoC.dc.html): the page bar carries the readout chip (chip
// temperature, thermal state, whole-Mac power); the page is CPU / GPU pair (SoCCards), CPU cores card
// (SocCoresCard), the 2-minute chart card (SocChartCard) and the Processes card, with the CPU read-failure
// note above the pair only in that state.
// All texts and states come from the pure `CPUPageModel` / `SocPageModel`; this file only draws them.

import SwiftUI

@MainActor
struct CPUPage: View {
    let model: AppModel
    let router: NavigationRouter
    /// Window below 1000 pt (`breakpoints.narrow`): the sub line and the readout chip shorten (design 7.3). The
    /// default keeps callers that have no breakpoint (the HiddenContent test) compiling.
    var narrow = false

    @State private var pulse: CardID? = nil

    /// Reads no live model field (only `router.navigationSerial` / `destination`): `CPUPageBar`, `SoCCards` and the
    /// other cards do the reading, so a 2 s tick never re-evaluates the page itself (same rule as `HomeNowCard`).
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SocFailureNote(model: model)
                    SoCCards(model: model)
                        .id(CardID.cpu)
                        .sectionFocusPulse(pulse == .cpu)
                    SocCoresCard(model: model)
                        .ds3Appear(delay: 0.24)
                    SocChartCard(model: model)
                        .ds3Appear(delay: 0.30)
                    ProcessListCard(model: model, initialMetric: .cpu, onConfirmShown: { router.isInlineConfirmOpen = $0 })
                        .id(CardID.procs)
                        .sectionFocusPulse(pulse == .procs)
                        .ds3Appear(delay: 0.36)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.top, 16, for: .scrollContent)
            .ds3KeepFocusScroll(pulse, top: .cpu, proxy: proxy, router: router)
            .safeAreaInset(edge: .top, spacing: 0) { CPUPageBar(model: model, narrow: narrow, onBack: { _ = router.back() }) }
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
        // SOC-DETAILS D22: the page tick lives exactly as long as this page (SwiftUI cancels the task on unmount), so
        // nothing is read while another page is shown, the app is in the background or the window is hidden.
        .task { await model.socLive.run() }
    }
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it
/// (Tests/MacDashboardTests/ContentSnapshotTests.swift).
@MainActor
struct CPUPageBar: View {
    let model: AppModel
    /// Window below 1000 pt (`breakpoints.narrow`).
    let narrow: Bool
    let onBack: () -> Void

    var body: some View {
        let m = CPUPageModel.make(cpuPageInput(model, compactSub: narrow))
        // §7.3: the state tag is hidden in the OK state (it only repeated the calm green of the readout chip).
        let tagVisible = m.tag != .ok
        SectionPageBar(symbol: Page.cpu.symbol, title: Page.cpu.title, sub: m.sub, subIsFailure: m.subIsFailure,
                       onBack: onBack) {
            if tagVisible { DS3Tag(tone: tone(m.tag), text: m.tagText).help(m.tagText) }
        } trailing: {
            SocReadoutChip(model: model, narrow: narrow, tagVisible: tagVisible)
                .layoutPriority(1)
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

/// Internal: the visual fixture renders it. CPU card and GPU card, equal height by construction: both are
/// header 32 · 16 · hero 147 · 16 · detail 218 = 473 pt, so neither can have a hole (design 7.4).
@MainActor
struct SoCCards: View {
    let model: AppModel

    var body: some View {
        let m = CPUPageModel.make(cpuPageInput(model))
        let loadAverage = SocLoadAverage.make(load: model.load)
        EqualColumnsLayout(columns: 2, spacing: 16, fillsHeight: true) {
            DS3Card(title: L.commonCPU, caption: m.caption, fillsHeight: true) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHero(label: L.cpuUsage, value: m.hero.value, fraction: m.hero.fraction, note: m.hero.note,
                                tone: m.hero.high ? DS3.amber : DS3.accent,
                                toneInk: m.hero.high ? DS3.amberInk : DS3.accentInk,
                                barTone: m.hero.high ? nil : DS3.s1,
                                dimmed: m.hero.dimmed)
                        .frame(height: 147)
                    VStack(spacing: 8) {
                        SocSplitPanel(split: m.split).equatable()
                        SocLoadAverageTile(load: loadAverage).equatable()
                    }
                    .frame(height: 218)
                }
            }
            .ds3Appear(delay: 0.12)
            DS3Card(title: L.commonGPU, caption: SocGPUListModel.caption(coreCount: model.socLive.gpuCoreCount),
                    fillsHeight: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // §7.4 bar colour rule: a bar that shows one series takes its colour (the GPU series is lime).
                    // The panel and label follow the mockup (blue accent); only the bar is lime.
                    SectionHero(label: L.cpuUsage, value: m.gpu.value, fraction: m.gpu.fraction, note: m.gpu.note,
                                tone: DS3.accent, toneInk: DS3.accentInk, barTone: DS3.s6, dimmed: m.gpu.dimmed)
                        .frame(height: 147)
                    SocGPUList(model: model)
                }
            }
            .ds3Appear(delay: 0.18)
        }
    }
}

/// Internal: `SocFailureNote` and the snapshot tests build the same input. `compactSub`: window below 1000 pt.
@MainActor
func cpuPageInput(_ model: AppModel, compactSub: Bool = false) -> CPUPageModel.Input {
    CPUPageModel.Input(cpu: model.cpu, ncpu: model.ncpu, chip: model.headerSystem?.chip,
                       block: model.cpuBlock.phase, highSince: model.cpuHighSince,
                       now: model.lastSampleAt, intervalSeconds: model.settings.fastIntervalSeconds,
                       gpuUtil: model.gpuUtil, compactSub: compactSub)
}
