// HomeAdviceDispatchTests.swift
// HIDDEN-CONTENT-WORK (R4, R9): Home's attention-card dispatch is owned by DashboardModel, so its state outlives
// the card; dismissing confirmations keeps done state and errors. No GUI.

import Foundation
import Testing
@testable import MacDashboard

@MainActor private func tempModel() throws -> (DashboardModel, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-dispatch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (DashboardModel(dataDirectory: dir), dir)
}

@MainActor
struct HomeAdviceDispatchTests {
    // Intent: the dispatch is model-owned; no `@State` path is left. This proves the ownership, not SwiftUI behaviour.
    @Test func dispatchSurvivesCardRemount() throws {
        let (m, dir) = try tempModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = HomeAttentionCard(model: m, router: NavigationRouter(), width: LiveWindowWidth(1150))
        a.dispatch.completedAdviceIDs.insert("Корзина")
        a.dispatch.trashError = "x"
        let b = HomeAttentionCard(model: m, router: NavigationRouter(), width: LiveWindowWidth(1150))   // what a remount does
        #expect(a.dispatch === b.dispatch)
        #expect(b.dispatch.done("Корзина|1,4 ГБ"))
        #expect(b.dispatch.trashError == "x")
        #expect(m.homeAdviceDispatch === b.dispatch)
    }

    @Test func dismissConfirmationsKeepsDoneAndErrors() throws {
        let (m, dir) = try tempModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let d = m.homeAdviceDispatch
        d.showTrashConfirm = true
        d.showFirewallConfirm = true
        d.showBrewConfirm = true
        d.completedAdviceIDs.insert("Корзина")
        d.trashError = "x"
        d.dismissConfirmations()
        #expect(!d.showTrashConfirm)
        #expect(!d.showFirewallConfirm)
        #expect(!d.showBrewConfirm)
        #expect(d.done("Корзина|1,4 ГБ"))
        #expect(d.trashError == "x")
    }
}
