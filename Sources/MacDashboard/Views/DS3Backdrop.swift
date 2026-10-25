// Views/DS3Backdrop.swift
// REDESIGN-ORBS: the single window backdrop (ground + orbs behind the content, grain above it) for the main window
// in both modes and for the Settings window. 01-window-chrome.md: the background belongs to the window, not to a
// mode; nothing here depends on the mode, so a mode switch never re-renders or re-animates it.
import SwiftUI

struct DS3Backdrop: ViewModifier {
    let orbs: [DS3OrbSpec]
    let grain: Bool
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    DS3.ground
                    DS3OrbField(orbs: orbs)
                }
            }
            // Stage 2 adds: .overlay { if grain { DS3GrainLayer() } }
    }
}

extension View {
    /// Ground + orbs under `self`, grain over it. `grain` is wired in Stage 2 and ignored until then.
    func ds3Backdrop(orbs: [DS3OrbSpec], grain: Bool = true) -> some View { modifier(DS3Backdrop(orbs: orbs, grain: grain)) }
}
