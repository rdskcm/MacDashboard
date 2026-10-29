// Views/HomeView.swift
// REDESIGN-HOME (stage B): the Home page of This Mac — scan banner, attention slot, Now slot,
// Sections grid. Each slot is its own struct that reads only what it renders (the observation
// split the old KPI row used), so a live tick re-runs the slot it affects and not the whole page.

import SwiftUI

extension HomeTone {
    var ds3Tag: DS3Tag.Tone {
        switch self {
        case .green: return .green
        case .neutral: return .neutral
        case .amber: return .amber
        case .hot: return .hot
        }
    }

    /// Text colour in the tone (the `-ink` variants: `light-theme-ink-variants`).
    var ink: Color {
        switch self {
        case .green: return DS3.greenInk
        case .neutral: return DS3.muted
        case .amber: return DS3.amberInk
        case .hot: return DS3.hotInk
        }
    }

    /// Dot / fill colour in the tone.
    var base: Color {
        switch self {
        case .green: return DS3.green
        case .neutral: return DS3.muted
        case .amber: return DS3.amber
        case .hot: return DS3.hot
        }
    }
}

extension HomeInput {
    /// Everything the tiles and the page bars derive from. Reads the live fields, so only the views
    /// that render tiles may call it.
    @MainActor
    static func make(_ model: AppModel) -> HomeInput {
        let report = model.homeReport
        let battery = model.battery ?? report.battery
        return HomeInput(assessment: model.assessment, report: report, scan: model.blockState(.scan),
                         load: model.load, ncpu: model.ncpu, processCount: model.processCount,
                         mem: model.mem, swap: model.swap, disk: model.disk,
                         hasBattery: battery != nil, battery: model.battery,
                         system: model.headerSystem, claudeBackup: model.claudeBackup,
                         backupStaleHours: model.settings.backupStaleHours,
                         history: [], now: model.now(),
                         historyDigest: model.history.homeDigest)
    }

    /// What the attention slot needs (tasks and chips): the assessment, the report, the scan state and
    /// the two live values the task wording uses. The Now/tile-only live fields (`load`, `mem`, `swap`,
    /// `processCount`) are left empty so a 2 s tick does not re-run the attention card.
    @MainActor
    static func attention(_ model: AppModel) -> HomeInput {
        let report = model.homeReport
        return HomeInput(assessment: model.assessment, report: report, scan: model.blockState(.scan),
                         load: nil, ncpu: model.ncpu, processCount: nil, mem: nil, swap: nil, disk: model.disk,
                         hasBattery: false, battery: model.battery, system: nil, claudeBackup: nil,
                         backupStaleHours: model.settings.backupStaleHours,
                         history: [], now: model.now())
    }

    /// The eight section tiles (seven without a battery) for the current model state.
    @MainActor
    static func tiles(_ model: AppModel) -> [HomeTile] {
        let input = make(model)
        let scan = HomeModel.scan(input.scan)
        let tasks = HomeModel.tasks(input.assessment, report: input.report, disk: input.disk, battery: model.battery)
        return HomeModel.tiles(input, tasks: tasks, scan: scan)
    }
}

extension View {
    /// Home's staggered entrance. The offscreen visual harness has no window, so `onAppear` never fires there
    /// and an animated entrance would stay at opacity 0: it renders its states with `enabled: false`.
    @ViewBuilder
    func homeEntrance(delay: Double, enabled: Bool) -> some View {
        if enabled { ds3Appear(delay: delay) } else { self }
    }
}

@MainActor
struct HomeView: View {
    let model: AppModel
    let router: NavigationRouter
    let width: LiveWindowWidth
    let tier: WidthTier

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HomeScanBannerSlot(model: model)
                HomeAttentionSlot(model: model, router: router, width: width)
                nowSlot
                HomeSectionsHeader(model: model)
                HomeSectionsGrid(model: model, router: router, tier: tier)
            }
            .padding(.top, 26)
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nowSlot: some View {
        HomeNowCard(model: model, router: router, tier: tier)
    }
}
