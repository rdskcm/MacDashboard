// Views/IdentifierRevealControls.swift
// SERIAL-MASK-LAST4: the Show / Hide toggle and the copy button for one masked identifier (IdentifierMask), as one
// view: toggle and copy circle side by side (HStack, spacing 4). Used by the iPhone identity card's serial rows and,
// as the label accessory of SectionTile, by the Mac Battery Passport serial tile. The caller owns the shown flag
// and the toggle action; the full value reaches the pasteboard only on the copy click (R13, D10). Strings are the
// identity card's, whose text is device-neutral.

import AppKit
import SwiftUI

/// The Show ↔ Hide text button and the copy circle side by side. The caller flips its own shown state (and may
/// animate around it); the copy circle owns its ✓ state (1.5 s).
struct IdentifierRevealControls: View {
    /// The row's label, used in the accessibility labels («Show value: Serial number»).
    let label: String
    /// The raw value: copied as is.
    let fullValue: String
    let shown: Bool
    let toggle: () -> Void
    @State private var copied: Bool
    @State private var copiedTask: Task<Void, Never>? = nil

    /// `initiallyCopied` exists for the harness render; the app always passes false.
    init(label: String, fullValue: String, shown: Bool, initiallyCopied: Bool = false, toggle: @escaping () -> Void) {
        self.label = label
        self.fullValue = fullValue
        self.shown = shown
        self.toggle = toggle
        _copied = State(initialValue: initiallyCopied)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                // Both words laid out, one visible, ending at the circle: the button keeps the wider word's width.
                ZStack(alignment: .trailing) {
                    Text(L.iphoneIdentityShow).hidden()
                    Text(L.iphoneIdentityHide).hidden()
                    Text(shown ? L.iphoneIdentityHide : L.iphoneIdentityShow)
                }
            }
            .buttonStyle(DS3ButtonStyle(kind: .text, height: 30, hPad: 11, fontSize: 12.5))
            .accessibilityLabel(shown ? L.iphoneHideA11y(label) : L.iphoneRevealA11y(label))
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(copied ? DS3.accentInk : DS3.ink)
            }
            .buttonStyle(DS3CircleButtonStyle(diameter: 30))
            .help(copied ? L.iphoneIdentityCopied : L.iphoneIdentityCopy)
            .accessibilityLabel(L.iphoneCopyA11y(label))
        }
        .onDisappear {
            copiedTask?.cancel()
            copied = false
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullValue, forType: .string)
        copied = true
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled { copied = false }
        }
    }
}
