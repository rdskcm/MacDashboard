// Views/LanguageDropdown.swift
// Block V2-SETTINGS. Custom language selector for the Settings General pane
// (Spec §7.2), replacing the native `.menu` Picker: a capsule trigger plus a
// floating frosted menu panel.
//
// The menu is rendered as a floating NSPanel — same idiom as HoverTip.swift's
// tooltip bubble — rather than an in-tree SwiftUI overlay, for two reasons:
// (1) it must visually float above the rest of the 420 pt-tall Settings window
// without being clipped by the detail column's ScrollView; (2) Trap 2 (project
// README §6.6): a `.regularMaterial` menu needs an unblurred layer *behind* the
// trigger to actually frost — putting the menu in its own NSPanel compositing
// layer guarantees that regardless of what the General card's own container
// does (the card itself must also carry no material of its own, see SettingsView).
//
// Unlike the tooltip, this panel must be interactive (clickable rows) and must
// light-dismiss on an outside pointer-down, so it can't reuse `ignoresMouseEvents`
// or `TipPanelController` verbatim — `InteractivePanel` overrides `canBecomeKey`
// so SwiftUI's `Button`s inside the hosted content receive clicks normally, and
// `LanguageMenuController` installs its own local+global mouse-down monitors for
// the light-dismiss behavior (SW:159-166's `onDocDown`).

import SwiftUI
import AppKit

/// Tiny invisible NSView giving us a stable AppKit anchor for the trigger's
/// on-screen frame — mirrors `AnchorFinder` in HoverTip.swift; duplicated
/// (rather than shared) so this file stays self-contained and that file's
/// tooltip path stays byte-identical.
private struct LanguageDropdownAnchor: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView) }
    }
}

/// Transparent margin around the menu's visible rounded-rect so its own
/// `.shadow()` (drawn outside the view's reported size) has room instead of
/// being hard-clipped at the panel edge — same technique as HoverTip's
/// `tipBubbleMargin`.
private let menuPanelMargin: CGFloat = 20
private let menuMinWidth: CGFloat = 186
private let menuRowHeight: CGFloat = 30
private let menuGap: CGFloat = 6

/// One selectable row inside the floating menu (SW:53-60).
private struct LanguageMenuRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DS.accentInk)
                    }
                }
                .frame(width: 12)
                Text(label)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.accentInk : DS.inkSoft)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: menuRowHeight)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? DS.accent.opacity(0.14) : (hovering ? DS.glass3 : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The floating menu's content (SW:51-62): frosted panel, 0.14 s fade + 7 pt
/// rise from its top-right anchor. Reduce Motion drops the rise, keeping only
/// a 0.12 s fade — the project-wide Reduce Motion contract (see DesignSystem.swift).
private struct LanguageMenuPanel: View {
    let languages: [(AppLanguage, String)]
    let selection: AppLanguage
    let onSelect: (AppLanguage) -> Void
    let reduceMotion: Bool

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 1) {
            ForEach(languages, id: \.0) { lang, label in
                LanguageMenuRow(label: label, selected: lang == selection) { onSelect(lang) }
            }
        }
        .padding(5)
        .frame(minWidth: menuMinWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.lineStrong, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(stops: [.init(color: DS.sheenLine, location: 0), .init(color: .clear, location: 0.15)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.32), radius: 16, x: 0, y: 10)
        .padding(menuPanelMargin) // transparent — see comment on menuPanelMargin
        .opacity(appeared ? 1 : 0)
        .offset(y: (appeared || reduceMotion) ? 0 : DSMotion.discloseRiseY)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? DSMotion.reduceMotionFallback : 0.14)) {
                appeared = true
            }
        }
    }
}

/// Subclassed only so the panel `canBecomeKey` despite the `.nonactivatingPanel`
/// style mask — without this, clicks on the SwiftUI `Button`s hosted inside
/// never reach them, since AppKit routes mouseDown through key-window-only
/// machinery for ordinary controls. `.nonactivatingPanel` itself only means
/// "becoming key doesn't bring the *application* forward", which is a no-op
/// here since our app is already frontmost — this is the standard pattern for
/// custom in-app popovers/menus.
private final class InteractivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the floating NSPanel, its light-dismiss monitors, and its lifecycle —
/// mirrors `TipPanelController` in HoverTip.swift (create-once, reposition-and-
/// reshow), but interactive and dismissible instead of `ignoresMouseEvents`.
private final class LanguageMenuController: NSObject {
    private var panel: InteractivePanel?
    private weak var anchorView: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?

    func setAnchor(_ view: NSView) {
        anchorView = view
    }

    func show(languages: [(AppLanguage, String)], selection: AppLanguage, onSelect: @escaping (AppLanguage) -> Void, onDismiss: @escaping () -> Void) {
        guard let anchor = anchorView, let window = anchor.window else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let content = LanguageMenuPanel(languages: languages, selection: selection, onSelect: onSelect, reduceMotion: reduceMotion)
        let hosting = NSHostingView(rootView: content)
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fitting)

        let panel: InteractivePanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = InteractivePanel(contentRect: NSRect(origin: .zero, size: fitting),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false // the panel draws its own soft shadow via SwiftUI
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            self.panel = panel
        }

        panel.appearance = anchor.effectiveAppearance
        panel.contentView = hosting
        panel.setContentSize(fitting)
        position(panel, near: anchor, in: window)

        if panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors(onDismiss: onDismiss)
    }

    func hide() {
        removeDismissMonitors()
        guard let panel else { return }
        let parent = panel.parent
        let wasKey = panel.isKeyWindow
        if let parent { parent.removeChildWindow(panel) }
        panel.orderOut(nil)
        // Escape/light-dismiss must hand keyboard focus back to Settings, not leave
        // it on a panel that is no longer on screen.
        if wasKey { parent?.makeKey() }
    }

    func teardown() {
        hide()
        panel?.close()
        panel = nil
        anchorView = nil
    }

    /// Anchored to the trigger's RIGHT edge, `menuGap` below it (SW:51's
    /// `top: 100% + 6; right: 0`). `panel.frame.size` includes `menuPanelMargin`
    /// of transparent shadow room on every side, so the offsets below subtract
    /// it back out — same idea as `TipPanelController.position(_:near:in:)`.
    private func position(_ panel: NSPanel, near anchor: NSView, in window: NSWindow) {
        let anchorFrameInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorScreenRect = window.convertToScreen(anchorFrameInWindow)
        let menuSize = panel.frame.size
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = anchorScreenRect.maxX + menuPanelMargin - menuSize.width
        x = max(visible.minX, min(x, visible.maxX - menuSize.width))

        var y = anchorScreenRect.minY - menuGap + menuPanelMargin - menuSize.height
        if y < visible.minY {
            // Flip above the trigger if there isn't room below (mirrors the
            // tooltip's own overflow flip, even though SW's prototype only
            // ever shows this menu with room below at 680×420).
            y = anchorScreenRect.maxY + menuGap - menuPanelMargin
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Light dismiss on any pointer-down outside the menu (SW:159-166's
    /// `onDocDown`), except: (a) clicks inside the menu itself (its own
    /// `Button`s handle those), and (b) clicks on the trigger button itself —
    /// that tap is handled by the trigger's own toggle action, so dismissing it
    /// here too would race the toggle and immediately reopen or double-close.
    private func installDismissMonitors(onDismiss: @escaping () -> Void) {
        removeDismissMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.shouldDismiss(for: event) {
                DispatchQueue.main.async { onDismiss() }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard self != nil else { return }
            DispatchQueue.main.async { onDismiss() }
        }
        // Escape is the keyboard-only / VoiceOver way out of this menu: the panel is
        // key (`InteractivePanel.canBecomeKey`), so without this the only dismissal
        // path is a mouse-down. LOCAL monitor only — a global .keyDown monitor would
        // demand Input Monitoring/Accessibility approval. Returning nil swallows the
        // key so it cannot also reach the Settings window behind the menu.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self != nil else { return event }
            guard event.keyCode == 53 else { return event }   // 53 = Escape
            DispatchQueue.main.async { onDismiss() }
            return nil
        }
    }

    private func shouldDismiss(for event: NSEvent) -> Bool {
        if event.window === panel { return false }
        if let anchor = anchorView, let anchorWindow = anchor.window, event.window === anchorWindow {
            let pointInWindow = event.locationInWindow
            let pointInAnchor = anchor.convert(pointInWindow, from: nil)
            if anchor.bounds.contains(pointInAnchor) { return false }
        }
        return true
    }

    private func removeDismissMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        localMonitor = nil
        globalMonitor = nil
        keyMonitor = nil
    }
}

/// The capsule trigger + floating menu (SW:43-64), replacing the `.menu`
/// Picker at the old SettingsView.swift:216-220. `selection` is bound directly
/// to `L10nStore.shared.language`; `onChange` runs after every commit (the
/// caller wires it to `syncAppleLanguages()`, unchanged behavior).
struct LanguageDropdown: View {
    @Binding var selection: AppLanguage
    var onChange: () -> Void = {}

    @State private var open = false
    @State private var hovering = false
    @State private var anchorView: NSView?
    @State private var controller = LanguageMenuController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Native-form language names — always shown in their own language
    /// regardless of the app's current UI language, matching the previous
    /// `Text(verbatim: …)` Picker rows this replaces. Exactly `.ru`/`.en`
    /// (Spec §7.2: "the list mirrors what StringsXX.swift provides").
    private let options: [(AppLanguage, String)] = [(.ru, "Русский"), (.en, "English")]

    private var currentLabel: String {
        options.first(where: { $0.0 == selection })?.1 ?? options[0].1
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                Text(currentLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.muted)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.62), value: open)
            }
            .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 7)
            .background(Capsule().fill(hovering ? DS.glass2 : DS.glass3))
            .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: 1))
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(stops: [.init(color: DS.sheenLine, location: 0), .init(color: .clear, location: 0.5)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(DSMotion.cardHover, value: hovering)
        .background(LanguageDropdownAnchor { view in
            if anchorView !== view {
                anchorView = view
                controller.setAnchor(view)
            }
        })
        .onHover { hovering = $0 }
        .onDisappear { controller.teardown() }
        .accessibilityLabel(L.settingsLanguageLabel)
        .accessibilityValue(currentLabel)
    }

    private func toggle() {
        open.toggle()
        if open {
            controller.show(languages: options, selection: selection, onSelect: pick, onDismiss: dismiss)
        } else {
            controller.hide()
        }
    }

    private func pick(_ language: AppLanguage) {
        selection = language
        onChange()
        controller.hide()
        open = false
    }

    private func dismiss() {
        guard open else { return }
        controller.hide()
        open = false
    }
}
