// DS3EntranceHostTests.swift
// APPEAR-CA-ENTRANCE R5, R7, R8: the nested hosting view forwards the environment, reports its ideal height to the
// outer layout, and adds no animation under Reduce Motion / the frozen fixture.

import Testing
import SwiftUI
import AppKit
@testable import MacDashboard

@MainActor
private final class EHost {
    let tracker = DS3PointerTracker()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
    init<V: View>(_ view: V) {
        _ = NSApplication.shared
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.frame(width: 600, height: 700, alignment: .topLeading).ds3PointerTracking(tracker))
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
        window.contentView = hosting
        settle()
    }
    func settle(_ s: TimeInterval = 0.3) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: s))
        window.contentView?.layoutSubtreeIfNeeded()
    }
    func find<T: NSView>(_ type: T.Type) -> T? {
        func walk(_ v: NSView) -> T? {
            if let t = v as? T { return t }
            for s in v.subviews { if let t = walk(s) { return t } }
            return nil
        }
        return window.contentView.flatMap(walk)
    }
    func findHost() -> NSView? { findHostView(in: window.contentView) }
    func close() { window.contentView = nil; window.close(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
}

@MainActor private func findHostView(in root: NSView?) -> NSView? {
    guard let root else { return nil }
    if root.identifier == DS3EntranceHostTestHooks.viewID { return root }
    for s in root.subviews { if let v = findHostView(in: s) { return v } }
    return nil
}

/// Amendment 2: the window's content view is an `NSHostingController`'s view, so a test can probe the outer layout at
/// any width with `sizeThatFits(in:)` (as the window's min-size probe does) while the window places the page at its
/// real width. `sizingOptions = []`: the outer view installs no size constraints, the window keeps the set size.
@MainActor
private final class MHost {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
    let outer: NSHostingController<AnyView>
    init<V: View>(_ view: V) {
        _ = NSApplication.shared
        window.isReleasedWhenClosed = false
        outer = NSHostingController(rootView: AnyView(VStack(alignment: .leading, spacing: 0) { view }))
        outer.sizingOptions = []
        window.contentView = outer.view
        window.setContentSize(NSSize(width: 600, height: 700))
        settle()
    }
    func settle(_ s: TimeInterval = 0.3) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: s))
        window.contentView?.layoutSubtreeIfNeeded()
    }
    func findHost() -> NSView? { findHostView(in: window.contentView) }
    func close() { window.contentView = nil; window.close(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
}

@MainActor private enum Placements { static var widths: [CGFloat] = [] }

/// Passes sizes through; records every width the hosted content is PLACED at (a measurement does not place).
private struct PlacementRecorder: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        MainActor.assumeIsolated { Placements.widths.append(bounds.width) }
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private let wrapText = String(repeating: "Wrapping words in a hosted card ", count: 24)

/// A card whose height depends on its width (≈ 8 lines at 600 pt, ≈ 10 at 500 pt).
private struct WrapProbe: View {
    var body: some View { PlacementRecorder { Self.text } }
    static var text: some View {
        Text(wrapText).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
    }
    /// The same content measured alone at width `w` (no host): what the host must answer.
    @MainActor static func referenceHeight(_ w: CGFloat) -> CGFloat {
        NSHostingController(rootView: text.fixedSize(horizontal: false, vertical: true))
            .sizeThatFits(in: CGSize(width: w, height: 10_000)).height
    }
}

@MainActor private enum Seen {
    static var glass: GlassSettings?
    static var tracker: DS3PointerTracker?
}

private struct EnvProbe: View {
    @Environment(GlassSettings.self) private var glass
    @Environment(\.ds3PointerTracker) private var tracker
    var body: some View {
        Color.clear.frame(width: 50, height: 50).onAppear { Seen.glass = glass; Seen.tracker = tracker }
    }
}

@MainActor @Observable private final class Flag { var tall = false }

private struct FrameProbe: View {
    let record: (CGRect) -> Void
    var body: some View {
        GeometryReader { g in Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in record(f) } }
    }
}

@MainActor private enum Recorded { static var siblingMinY: CGFloat = 0 }

extension SerialTests {
    @Suite struct DS3EntranceHostTests {
        @MainActor @Test func environmentReachesTheHostedContent() {
            Seen.glass = nil; Seen.tracker = nil
            let h = EHost(DS3EntranceHost(delay: 0, offsetY: 14, scale: 0.98, slideX: 28) { EnvProbe() }
                .environment(GlassSettings(fixture: true)))
            h.settle()
            #expect(Seen.glass != nil, "GlassSettings reaches the nested host")
            #expect(Seen.tracker === h.tracker, "the pointer tracker reaches the nested host")
            h.close()
        }

        @MainActor @Test func heightChangeInsideTheHostMovesTheSibling() {
            let flag = Flag()
            struct Page: View {
                let flag: Flag
                var body: some View {
                    VStack(spacing: 0) {
                        DS3EntranceHost(delay: 0, offsetY: 0, scale: 1, slideX: 0) {
                            Rectangle().frame(height: flag.tall ? 200 : 100)
                        }
                        Rectangle().frame(height: 50).background(FrameProbe { Recorded.siblingMinY = $0.minY })
                    }
                }
            }
            let h = EHost(Page(flag: flag))
            let before = Recorded.siblingMinY
            flag.tall = true
            h.settle()
            #expect(abs((Recorded.siblingMinY - before) - 100) < 0.5, "sibling moved by the card's growth (was \(before), now \(Recorded.siblingMinY))")
            h.close()
        }

        @MainActor @Test func reduceMotionOrFrozenAddsNoAnimation() {
            let card = DS3EntranceHost(delay: 0, offsetY: 14, scale: 0.98, slideX: 28) { Color.blue.frame(height: 80) }

            VisualFixture.forced = true
            let n0 = DS3Appear.entranceStarts
            let frozen = EHost(card)
            frozen.settle()
            let fv = frozen.findHost()
            #expect(fv != nil)
            #expect(fv?.layer?.animationKeys() == nil)
            #expect(fv?.layer?.opacity == 1)
            #expect(DS3Appear.entranceStarts == n0 + 1, "frozen branch still counts the start")
            frozen.close()

            VisualFixture.forced = false
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                print("skipped live half: Reduce Motion is on")
                return
            }
            let n1 = DS3Appear.entranceStarts
            let live = EHost(card)
            live.settle(0.1)
            let keys = live.findHost()?.layer?.animationKeys() ?? []
            #expect(keys.contains("ds3.opacity") && keys.contains("ds3.enter"), "entrance animations on the layer: \(keys)")
            #expect(DS3Appear.entranceStarts == n1 + 1)
            live.close()
        }

        @MainActor @Test func alternatingProposalsNeitherRebuildNorRelayTheHostedRoot() {
            VisualFixture.forced = true
            defer { VisualFixture.forced = false }
            Placements.widths = []
            let h = MHost(DS3EntranceHost(delay: 0, offsetY: 0, scale: 1, slideX: 0) { WrapProbe() })
            let mounted = DS3EntranceHostTestHooks.rootAssignments
            let placed = Placements.widths.count
            #expect(Placements.widths.last == 600, "hosted content laid out at the placed width: \(Placements.widths)")
            var answers: [CGFloat: Set<CGFloat>] = [:]
            for _ in 0..<10 {
                for w: CGFloat in [600, 500] {   // the real width and a min-size-style probe, alternating like 927 / 827
                    let s = h.outer.sizeThatFits(in: CGSize(width: w, height: 10_000))
                    answers[w, default: []].insert((s.height * 2).rounded() / 2)
                }
            }
            h.settle()
            #expect(DS3EntranceHostTestHooks.rootAssignments == mounted, "20 probes assigned no hosted root (R14)")
            let after = Array(Placements.widths.dropFirst(placed))
            #expect(after.allSatisfy { $0 == 600 }, "no probe re-laid the hosted content out at the probe width: \(after)")
            let ref600 = WrapProbe.referenceHeight(600), ref500 = WrapProbe.referenceHeight(500)
            #expect(ref500 > ref600 + 10, "precondition: the probe text wraps differently at 600 and 500 (\(ref600), \(ref500))")
            #expect(answers[600]?.count == 1 && answers[500]?.count == 1, "one stable answer per width: \(answers)")
            #expect(abs((answers[600]?.first ?? 0) - ref600) < 0.5, "height at 600 = the content's own (R15): \(answers[600] ?? []) vs \(ref600)")
            #expect(abs((answers[500]?.first ?? 0) - ref500) < 0.5, "height at 500 = the content's own (R15): \(answers[500] ?? []) vs \(ref500)")
            #expect(abs((h.findHost()?.frame.height ?? 0) - ref600) < 0.5, "the placed host is as tall as the content at 600")
            h.close()
        }

        @MainActor @Test func realWidthChangeReflowsTheHostedContentInTheSamePass() {
            VisualFixture.forced = true
            defer { VisualFixture.forced = false }
            Placements.widths = []
            let h = MHost(DS3EntranceHost(delay: 0, offsetY: 0, scale: 1, slideX: 0) { WrapProbe() })
            for w: CGFloat in [450, 750, 600] {
                h.window.setContentSize(NSSize(width: w, height: 700))
                h.window.contentView?.layoutSubtreeIfNeeded()          // one layout pass, no run-loop turn
                let host = h.findHost()
                #expect(host?.frame.width == w, "host placed at \(w) in the same pass: \(String(describing: host?.frame))")
                #expect(Placements.widths.last == w, "hosted content laid out at \(w) in the same pass: \(Placements.widths.suffix(3))")
                #expect(abs((host?.frame.height ?? 0) - WrapProbe.referenceHeight(w)) < 0.5, "host height = content height at \(w)")
                h.settle()
            }
            let n = Placements.widths.count
            h.settle(0.5)
            #expect(Placements.widths.count == n, "no layout churn once the resize settled (no feedback loop): \(Placements.widths.suffix(4))")
            h.close()
        }
    }
}
