// Views/ReportSheet.swift
// REDESIGN-REPORT: the Report as a system sheet over the window (02-home §4, 00-shared §4.13 [SYS]).
// `ReportSheetContent` is pure (takes a `ReportSheetState`), so snapshots can render every state;
// `ReportSheet` is the thin wrapper that reads the model.

import SwiftUI
import AppKit

/// What the sheet shows, as values (snapshot tests build these directly).
struct ReportSheetState: Equatable {
    enum Phase: Equatable { case ready, generating, failed(BlockFailure) }
    var phase: Phase
    var text: String?        // nil = no report yet (placeholder)
    var updatedAt: Date?     // time of `text`; nil when text is nil
    var now: Date            // for reportUpdatedTimeString

    @MainActor static func make(_ model: AppModel) -> ReportSheetState {
        let phase: Phase
        if model.isCollectingReport { phase = .generating }
        else if case .failed(let f, _) = HomeModel.scan(model.blockState(.scan)) { phase = .failed(f) }
        else { phase = .ready }
        return ReportSheetState(phase: phase, text: model.reportText, updatedAt: model.reportUpdatedAt,
                                now: model.now())
    }
}

/// Thin wrapper: reads the model, hands values to the content view.
@MainActor struct ReportSheet: View {
    let model: AppModel
    let onDone: () -> Void
    var body: some View {
        ReportSheetContent(state: .make(model), reportURL: model.reportURL,
                           onRetry: { model.refreshReport(trigger: .button) }, onDone: onDone)
    }
}

@MainActor struct ReportSheetContent: View {
    let state: ReportSheetState
    let reportURL: URL
    let onRetry: () -> Void
    let onDone: () -> Void
    @State private var copied = false
    @State private var copiedTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var generating: Bool { state.phase == .generating }

    /// Caption text and colour for the ready / failed phases; nil = no caption line.
    private var caption: (text: String, color: Color)? {
        if case .failed = state.phase {
            let t = state.updatedAt.map { L.reportNotUpdatedShowing(reportUpdatedTimeString($0, now: state.now)) }
                ?? L.reportNotUpdated
            return (t, DS3.hotInk)
        }
        guard state.text != nil, let at = state.updatedAt else { return nil }
        return (L.reportFileUpdatedCaption(reportUpdatedTimeString(at, now: state.now)), DS3.muted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if case .failed(let f) = state.phase { banner(f) }
            bodyBox
        }
        .padding(22)
        .frame(width: 680)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report-sheet")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.commonReport)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.22)
                    .foregroundStyle(DS3.ink)
                if let c = caption {
                    Text(c.text)
                        .font(.system(size: 13))
                        .foregroundStyle(c.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(c.text)
                        .dsSwapInPlace(generating) { generatingCaption }
                } else if generating {
                    generatingCaption
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(L.reportShowInFinder) { AdviceActionRunner.reveal(reportURL.path) }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, disabledOpacity: 0.5))
                .disabled(generating || state.text == nil)
                .accessibilityLabel(L.reportShowInFinder)
                .accessibilityIdentifier("report-show-in-finder")

            Button { copy() } label: {
                Text(copied ? L.reportCopied : L.reportCopy)
                    .foregroundStyle(copied ? DS3.greenInk : DS3.ink)
                    .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.25), value: copied)
                    .frame(width: 124 - 28)   // D11: 124 is the whole button; 14 pt padding each side
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, disabledOpacity: 0.5))
            .disabled(generating || state.text == nil)
            .accessibilityLabel(copied ? L.reportCopied : L.reportCopy)
            .accessibilityIdentifier("report-copy")

            Button(L.commonDone, action: onDone)
                .buttonStyle(DS3ButtonStyle(kind: .primary, height: 32, hPad: 16))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L.commonDone)
                .accessibilityIdentifier("report-done")
        }
        .frame(minHeight: 32)
        .onDisappear { copiedTask?.cancel() }
    }

    private var generatingCaption: some View {
        HStack(spacing: 7) {
            DS3Spinner(role: .accentRing, size: 13)
            Text(L.reportCollecting)
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
        }
        // `dsSwapInPlace` overlays the replacement centred over the hidden caption; filling its width and
        // anchoring leading puts the spinner on the title's left edge.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func banner(_ f: BlockFailure) -> some View {
        HStack(spacing: 12) {
            Text(f == .timedOut ? L.reportFailedTimedOut : L.reportFailedNoReading)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS3.hotInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
            Button(L.commonTryAgain, action: onRetry)
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 14))
                .accessibilityLabel(L.commonTryAgain)
                .accessibilityIdentifier("report-try-again")
                .layoutPriority(1)
        }
        .padding(EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 7))
        .ds3TintPanel(DS3.hot, from: 0.12, to: 0.12, ring: 0.40, cornerRadius: 999)
    }

    private var bodyBox: some View {
        // The report ends with one "\n" (file format); a Text would draw it as an empty last line.
        let shown = state.text.map { $0.hasSuffix("\n") ? String($0.dropLast()) : $0 }
        let content = Text(shown ?? L.reportPlaceholder)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .lineSpacing(4)
            .tracking(0.28)
            .foregroundStyle(state.text == nil ? DS3.muted : DS3.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
        // Sized to the content up to 400 pt; longer text scrolls inside the box. The hidden copy of the
        // content is only measured (a layout needs its height before the ScrollView can be capped).
        return CappedHeightLayout(maxHeight: 400) {
            content.hidden().accessibilityHidden(true)
            ScrollView { content }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), ring: DS3.line)
        .opacity(generating ? 0.45 : 1)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.2), value: generating)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(state.text ?? "", forType: .string)
        copied = true
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copied = false }
        }
    }
}

/// Two subviews: [0] measures the natural height, [1] is shown at `min(natural, maxHeight)`.
private struct CappedHeightLayout: Layout {
    let maxHeight: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? subviews[0].sizeThatFits(.unspecified).width
        let h = subviews[0].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
        return CGSize(width: w, height: min(h, maxHeight))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for v in subviews {
            v.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
