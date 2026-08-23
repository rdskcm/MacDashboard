// Views/QuietStrip.swift
// Block V2-QUIET (Spec §5.2): collapses quiet Security/Updates&Crashes sections
// into a single disclosure-row "quiet strip" so an all-clear dashboard doesn't
// spend two full cards saying "nothing to see here" — and, on the flip side,
// promotes a loud (non-quiet) section to a full `LoudSectionCard` so it reads
// with the same weight as any other card that needs the user's attention.

import AppKit
import SwiftUI

// MARK: - Row model + localized row builders

struct SystemSectionRow: Identifiable {
    let id: String
    let name: String
    let mark: String
    let ok: Bool
}

func securityRows(_ sec: SecurityState) -> [SystemSectionRow] {
    func row(_ id: String, _ name: String, _ value: Bool?) -> SystemSectionRow {
        switch value {
        case .some(true): return SystemSectionRow(id: id, name: name, mark: "✓", ok: true)
        case .some(false): return SystemSectionRow(id: id, name: name, mark: L.quietMarkOff, ok: false)
        case .none: return SystemSectionRow(id: id, name: name, mark: L.quietMarkUnknown, ok: false)
        }
    }
    return [
        row("fileVault", L.securityFileVault, sec.fileVault),
        row("gatekeeper", L.securityGatekeeper, sec.gatekeeper),
        row("sip", L.securitySip, sec.sip),
        row("firewall", L.securityFirewall, sec.firewall),
    ]
}

func updatesRows(updates: [String], crashes: [CrashGroup]) -> [SystemSectionRow] {
    func row(_ id: String, _ name: String, count: Int, allClear: String) -> SystemSectionRow {
        count > 0
            ? SystemSectionRow(id: id, name: name, mark: L.quietCountItems(count), ok: false)
            : SystemSectionRow(id: id, name: name, mark: allClear, ok: true)
    }
    let crashReports = crashes.reduce(0) { $0 + $1.count }
    return [
        row("updates", L.maintenanceUpdatesSection, count: updates.count, allClear: L.maintenanceUpdatesAllUpdated),
        row("crashes", L.maintenanceCrashesSection, count: crashReports, allClear: L.maintenanceCrashesNone),
    ]
}

/// V2-FIX-SECURITY-ROWS: the explanation that used to live in the row label as a
/// parenthetical now lives in the row's hover tooltip. Unknown id → "" → .hoverTip
/// is a no-op (HoverTip.swift:417 guards on text.isEmpty).
func sectionRowTip(_ id: String) -> String {
    switch id {
    case "fileVault": return L.securityFileVaultTip
    case "sip": return L.securitySipTip
    case "firewall": return L.securityFirewallTip
    case "gatekeeper": return L.securityGatekeeperTip
    case "updates": return L.maintenanceUpdatesTip
    case "crashes": return L.maintenanceCrashesTip
    default: return ""
    }
}

// MARK: - QuietStrip

struct QuietSection: Identifiable {
    let id: String // "sec" / "maint"
    let title: String
    let status: String
    let rows: [SystemSectionRow]
}

struct QuietStrip: View {
    let sections: [QuietSection]

    @State private var open: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(sections: [QuietSection], initiallyOpen: Set<String> = []) {
        self.sections = sections
        _open = State(initialValue: initiallyOpen)
    }

    var body: some View {
        if sections.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sections) { section in
                    QuietStripRow(section: section, isOpen: open.contains(section.id), reduceMotion: reduceMotion) {
                        if open.contains(section.id) { open.remove(section.id) } else { open.insert(section.id) }
                    }
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 14).fill(DS.row))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.line, lineWidth: 1))
        }
    }
}

private struct QuietStripRow: View {
    let section: QuietSection
    let isOpen: Bool
    let reduceMotion: Bool
    let toggle: () -> Void

    @State private var hovering = false
    /// Single source of truth for the disclosure's progress, 0 = fully closed,
    /// 1 = fully open — ported from `EnergyCard.openAmount` (see its doc
    /// comment, EnergyCard.swift:88-99, and `AutoSectionRow.openAmount` in
    /// AutostartCard.swift for the full writeup) to replace this row's former
    /// implicit `if isOpen { }.transition(...)` mechanism with the same
    /// explicit, permanently-mounted pattern. Unlike EnergyCard (which always
    /// starts collapsed), this row's open/closed state is owned by the parent
    /// `QuietStrip` via `isOpen`/`open: Set<String>`, so the initial value is
    /// seeded from `isOpen` in `init` below rather than hardcoded to 0.
    @State private var openAmount: Double
    /// Natural (fully-expanded) height of the disclosed grid below, captured
    /// via `.onGeometryChange` — see `EnergyCard.measuredHeight` /
    /// `AutoSectionRow.measuredHeight` for the full root-cause writeup.
    @State private var measuredHeight: CGFloat?

    init(section: QuietSection, isOpen: Bool, reduceMotion: Bool, toggle: @escaping () -> Void) {
        self.section = section
        self.isOpen = isOpen
        self.reduceMotion = reduceMotion
        self.toggle = toggle
        _openAmount = State(initialValue: isOpen ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                DSDisclosureBars(expanded: isOpen)
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(section.status)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.muted)
                    .lineLimit(1)
                Text("✓")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(DS.greenInk)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill((isOpen || hovering) ? DS.glass3 : .clear)
                    // Duration matches DSMotion.cardHover (0.16) deliberately; the curve (easeInOut, not
                    // easeOut) does not, so this is not a drop-in token swap — left as a literal.
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isOpen || hovering)
            )
            .contentShape(Rectangle())
            .onTapGesture { toggle() }
            .onHover { hovering = $0 }
            .accessibilityLabel(section.title)
            .accessibilityAddTraits(.isButton)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                      alignment: .leading, spacing: 5) {
                ForEach(section.rows) { row in
                    HStack(spacing: 10) {
                        Text(row.name).font(.system(size: 13)).foregroundStyle(DS.muted).lineLimit(1)
                        Spacer(minLength: 10)
                        Text(row.mark).font(.system(size: 13, weight: .bold)).foregroundStyle(DS.greenInk)
                    }
                    .contentShape(Rectangle())
                    .hoverTip(sectionRowTip(row.id))
                }
            }
            .padding(EdgeInsets(top: 4, leading: 33, bottom: 10, trailing: 12))
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
                measuredHeight = newHeight
            }
            .frame(height: measuredHeight.map { $0 * openAmount } ?? (openAmount == 0 ? 0 : nil), alignment: .top)
            .clipShape(BleedRect(top: 20, leading: 20, trailing: 20))
            .opacity(openAmount)
            .offset(y: reduceMotion ? 0 : DSMotion.discloseRiseY * (1 - openAmount))
        }
        // Outer backstop clip — same rationale as `EnergyCard`'s (see its
        // comment above `.clipShape(BleedRect(leading: 20, trailing: 20))`,
        // EnergyCard.swift:146-159): the inner clip above is itself offset
        // upward by up to `DSMotion.discloseRiseY` while collapsing/collapsed,
        // so an already-clipped-to-zero-height box can still poke a sliver
        // above the header without this outer re-clip.
        .clipShape(BleedRect(leading: 20, trailing: 20))
        .onChange(of: isOpen) { _, newValue in
            let target: Double = newValue ? 1 : 0
            let curve: Animation = reduceMotion
                ? .easeInOut(duration: DSMotion.reduceMotionFallback)
                : DSMotion.expand
            withAnimation(curve) { openAmount = target }
        }
    }
}

// MARK: - LoudSectionCard

struct LoudSectionCard<Extra: View>: View {
    let title: String
    let dotColor: Color
    let failTone: Color
    let rows: [SystemSectionRow]
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            titleRow
            grid
            extra()
        }
        .cardBackground()
        .dsHoverLift()
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            Text(title).font(.system(size: 15, weight: .bold)).kerning(-0.15).lineLimit(1)
            Spacer(minLength: 8)
            Text(L.quietNeedsAttention).font(.system(size: 12.5)).foregroundStyle(DS.muted).lineLimit(1)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                  alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.name).font(.system(size: 13)).foregroundStyle(DS.inkSoft).lineLimit(1)
                    Spacer(minLength: 10)
                    Text(row.mark)
                        .font(.system(size: 13, weight: row.ok ? .regular : .semibold))
                        .foregroundStyle(row.ok ? DS.greenInk : failTone)
                }
                .contentShape(Rectangle())
                .hoverTip(sectionRowTip(row.id))
            }
        }
    }
}

// MARK: - UpdatesCrashesCard

struct UpdatesCrashesCard: View {
    let model: DashboardModel
    let state: QuietState

    var body: some View {
        switch state.updates {
        case .collecting:
            CardChrome(title: L.quietUpdatesTitle) {
                SectionStateView(done: (model.report.progress["updates"] ?? false) && (model.report.progress["crashes"] ?? false))
            }
        case .loud:
            let updates = model.report.updates ?? []
            let crashes = model.report.crashes ?? []
            LoudSectionCard(title: L.quietUpdatesTitle, dotColor: DS.amber, failTone: DS.amberInk,
                             rows: updatesRows(updates: updates, crashes: crashes)) {
                // The detail lists mirror `LoudSectionCard.grid`'s column spec so
                // each list sits under its own row — the crash filenames used to
                // render full-width and read as belonging to «macOS updates».
                // Both cells are emitted unconditionally (an empty cell is a
                // zero-height view) so crashes always land in column 2.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                          alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !updates.isEmpty {
                            ForEach(Array(updates.prefix(5).enumerated()), id: \.offset) { _, u in
                                Text(u).font(.system(size: 13)).foregroundStyle(DS.inkSoft)
                            }
                            if updates.count > 5 {
                                Text(L.maintenanceAndMore(updates.count - 5))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(DS.muted)
                            }
                            RainbowCapsuleButton(title: L.maintenanceOpenSoftwareUpdate, size: .card) {
                                AdviceActionRunner.openPane(AdvicePanes.softwareUpdate)
                            }
                            .accessibilityLabel(L.maintenanceOpenSoftwareUpdate)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        if !crashes.isEmpty {
                            ForEach(Array(crashes.prefix(5))) { g in
                                CrashRevealRow(group: g)
                            }
                            if crashes.count > 5 {
                                Text(L.maintenanceAndMore(crashes.count - 5))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(DS.muted)
                                    .padding(.horizontal, 9)     // align with the rows' text inset
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .quiet:
            EmptyView()
        }
    }
}

// MARK: - CrashRevealRow (V2-CRASH-REVEAL, item 2)

/// One crash group as a clickable *filled list row* — the same hover surface class
/// as `ProcessCards`' process row (resting `DS.row`, hover `DS.track`, 0.14 s), NOT
/// normalised to the flat-text or tinted-plate class. Clicking reveals the directory
/// THIS group's report actually came from (`CrashGroup.directory`), which is why the
/// affordance is per row and not one shared button under the list: two rows can point
/// at two different directories.
private struct CrashRevealRow: View {
    let group: CrashGroup

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            AdviceActionRunner.reveal(group.directory)
        } label: {
            Text(L.maintenanceCrashRow(group.process, group.count))
                .font(.system(size: 13))
                .foregroundStyle(DS.inkSoft)
                .lineLimit(1)
                .truncationMode(.middle)
                .hoverTip(group.directory)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                // Optical centring: SwiftUI centres the text's LINE BOX, whose
                // descender space is empty for these strings, so a mathematically
                // centred row reads 0.5 pt low. 1 pt of bottom padding inside the
                // centred block lifts the glyphs. Measured on a 2x render: without
                // it the glyphs sit 18 px below / 16 px above, with it 16 / 18 — the
                // grid snaps, so any value in (0, 1] lifts by exactly one device
                // pixel and 0.5 is the smallest honest one. The row's own height is
                // still the fixed 27, so nothing about the layout moves.
                .padding(.bottom, 0.5)
                .frame(height: 27)
                .background(
                    // Animate the FILL at the shape: the row's size does not depend
                    // on `hovering`, and nothing here lifts, so the hit test stays
                    // pinned to the resting frame.
                    RoundedRectangle(cornerRadius: 9)
                        .fill(hovering ? DS.track : DS.row)
                        .animation(.easeInOut(duration: reduceMotion ? DSMotion.reduceMotionFallback : 0.14),
                                   value: hovering)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .pointingHandOnHover(hovering: $hovering)
        .accessibilityLabel(L.maintenanceCrashRevealA11y(group.process))
    }
}
