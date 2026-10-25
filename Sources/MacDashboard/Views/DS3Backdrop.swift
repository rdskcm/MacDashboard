// Views/DS3Backdrop.swift
// REDESIGN-ORBS: the single window backdrop (ground + orbs behind the content) for the main window
// in both modes and for the Settings window. 01-window-chrome.md: the background belongs to the window, not to a
// mode; nothing here depends on the mode, so a mode switch never re-renders or re-animates it.
import SwiftUI

struct DS3Backdrop: ViewModifier {
    let orbs: [DS3OrbSpec]
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    DS3.ground
                    DS3OrbField(orbs: orbs)
                }
            }
    }
}

extension View {
    /// Ground + H1 orbs under `self` (spec §3.3).
    func ds3Backdrop(orbs: [DS3OrbSpec]) -> some View { modifier(DS3Backdrop(orbs: orbs)) }
}
