// Views/SocGPUList.swift
// SOC-DETAILS 2.1 (design 7.4): the GPU card's detail area, the top processes by GPU. A container of fixed height
// 218 (6 + 5 x 38 + 4 x 4 + 6), five rows in the non-opening process-row form (no chevron, no click, no actions).
// States keep the 218: wait line, "No process is using the GPU.", "Not available on this Mac". Fewer than five rows
// leave empty slots, so the card never has a hole.
//
// Rows are identified by pid (`live-list-identity`). A re-sort moves rows with one explicit `withAnimation` on the
// shown list, with the same curve as the gauge. The gauge itself is a `BarFillLayer` with no SwiftUI animation on it.

import SwiftUI

/// The bar curve shared by the gauge and the row re-sort (same curve as the former `processRowMotion` of ProcessCards.swift, removed in IDLE-WORK-TRIM).
private let socGPURowMotion = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.45)

/// Internal: the visual fixture renders it through `SoCCards`.
@MainActor
struct SocGPUList: View {
    let model: AppModel

    /// The pids on screen, in order. Committed from `.onChange` so that a re-sort can ride one explicit
    /// `withAnimation`. Stage 5a: only the order lives here; each row's values are read by its own `SocGPUSlotRow`.
    @State private var shown: [Int32]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel) {
        self.model = model
        _shown = State(initialValue: model.socLive.gpuShape.pids)
    }

    var body: some View {
        // The container reads only the shape (state and pid order); the row slots are looked up untracked.
        let shape = model.socLive.gpuShape
        container {
            switch shape {
            // Clients exist but none has a previous sample yet (first tick after they appear): still collecting.
            case .notYet, .rows([]):
                SectionWait(text: L.commonCollectingData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                message(L.socGPUListEmpty)
            case .unavailable:
                message(L.gpuNotAvailable)
            case .rows(let pids):
                VStack(spacing: 4) {
                    ForEach(shown.isEmpty ? pids : shown, id: \.self) { pid in
                        if let slot = model.socLive.gpuRowSlots[pid] { SocGPUSlotRow(slot: slot) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        // Fires only when the pid order changed, so a value change never passes through this container.
        .onChange(of: shape.pids) { _, new in
            if !reduceMotion {
                withAnimation(socGPURowMotion) { shown = new }
            } else {
                shown = new
            }
        }
    }

    private func container<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 218, maxHeight: 218, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
            .ds3InsetRims(RoundedRectangle(cornerRadius: 22, style: .continuous), ring: DS3.line)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(DS3.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The only reader of `slot.row`: a share or name change re-evaluates this row and nothing above it.
private struct SocGPUSlotRow: View {
    let slot: SocGPURowSlot

    var body: some View {
        SocGPURowView(row: SocGPUListModel.row(slot.row))
    }
}

/// One row: name (14, tail truncation, full name on hover), value (SF Mono 13 / 600, at least 64 pt, trailing) and a
/// gauge behind the content in the lime series colour at 24 %, width = share on the absolute 0 to 100 scale.
struct SocGPURowView: View {
    let row: SocGPUListModel.Row

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Text(row.name)
                .font(.system(size: 14))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(row.name)
            Spacer(minLength: 8)
            Text(row.valueText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(row.muted ? DS3.muted : DS3.ink)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
        // The gauge lives in a `.background`: it sizes to its parent and cannot feed anything back (V2-FIX-RATCHET).
        .background(alignment: .leading) {
            BarFillLayer(spans: [BarSpan(key: "gauge", fraction: CGFloat(row.fraction), alpha: 0.24, color: DS3.s6)],
                         layout: .single(minWidth: 0, cornerRadius: 0),
                         animated: !reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.valueText)")
        .accessibilityAddTraits(.isStaticText)
    }
}
