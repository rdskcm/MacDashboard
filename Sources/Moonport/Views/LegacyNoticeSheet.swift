// Views/LegacyNoticeSheet.swift
// MOONPORT-RENAME D7, amendment 3 (user's design, handoff 12-moonport-welcome.md): the one-time Moonport Welcome panel.
// The value `LegacyNotice` is built in Engine (`LegacyMigration.swift`); this file is the panel with its own surface.
// `LegacyNoticeOverlay` places and animates it (centred, veil behind) and is mounted only while a notice exists
// (`no-unseen-work`). The panel's own motion: staggered entrance parts (`\.noticeEntered`), the state pop, item fades.
// Only opacity, scale and offset animate (`gpu-per-frame`). Side effects come in as `WelcomeActions` (AppShell), the
// starting state as `WelcomeStart`, so snapshots render any state without awaiting anything.
import SwiftUI

/// Where the old-app action stands in the Settings › About row.
enum LegacyTrashState: Equatable {
    case idle, quitting, trashed
    case failed(String)
}

private struct NoticeEnteredKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    /// false until the overlay's entrance starts; true everywhere else (snapshots render the finished panel).
    var noticeEntered: Bool {
        get { self[NoticeEnteredKey.self] }
        set { self[NoticeEnteredKey.self] = newValue }
    }
}

/// One staggered entrance part (design §5). `.rise`: opacity 0 to 1 and offset y 6 to 0, 0.7 s `.timingCurve(0.22, 1, 0.36, 1)`
/// after `delay`. `.glow`: opacity only, 1.2 s, delay 0.3 s. Reduce Motion: no own motion (the panel fades as a whole).
private struct NoticePart: ViewModifier {
    enum Kind { case rise(delay: Double), glow }
    let kind: Kind
    @Environment(\.noticeEntered) private var entered
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            switch kind {
            case .rise(let delay):
                content
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 6)
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.7).delay(delay), value: entered)
            case .glow:
                content
                    .opacity(entered ? 1 : 0)
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.2).delay(0.3), value: entered)
            }
        }
    }
}

private extension View {
    func noticePart(_ kind: NoticePart.Kind) -> some View { modifier(NoticePart(kind: kind)) }
}

/// The panel's starting state. The defaults are the real launch (archive move running, nothing granted, nothing decided);
/// the snapshot states pass the others.
struct WelcomeStart: Equatable {
    enum OldApp: Equatable { case undecided, kept, trashed(URL) }
    /// nil = busy until the task answers.
    var archive: LegacyArchiveMove.Outcome? = nil
    /// true = step 1 starts granted.
    var fullDiskAccess = false
    var oldApp = OldApp.undecided
}

/// Every side effect of the panel. `.inert` (snapshots, `-fixtureLegacyNotice`) and `.live(notice:)` are in `AppShell.swift`:
/// views may not name `VisualFixture.` (EngineBoundaryTests `viewsReadNoFixtureHooks`).
@MainActor struct WelcomeActions {
    var quitOldApp: () async -> Bool
    /// Moves the old app to the Trash; returns where it landed.
    var trash: () throws -> URL
    var restore: (URL) throws -> Void
    var openFullDiskAccess: () -> Void
    var fullDiskAccess: () -> FullDiskAccessState
    var archiveTask: () -> Task<LegacyArchiveMove.Outcome, Never>?
    var retryArchives: () -> Task<LegacyArchiveMove.Outcome, Never>?
    /// Selects the URLs that exist in Finder, else opens the fallback folder.
    var reveal: ([URL], URL) -> Void
}

/// D-W10: the old-app step.
enum WelcomeOldAppState: Equatable {
    case undecided(error: String?)
    case kept
    case trashed(URL, undoError: String?)
}

@MainActor struct LegacyNoticeSheet: View {
    let notice: LegacyNotice
    let settings: AppSettings
    let onDone: () -> Void
    let actions: WelcomeActions
    /// The panel's largest height (window height − 48). nil = natural height, no scrolling (snapshots).
    var maxPanelHeight: CGFloat? = nil

    private enum PermState { case idle, checking, granted }

    @State private var archiveOutcome: LegacyArchiveMove.Outcome?
    @State private var archiveRetried = false
    @State private var perm: PermState
    @State private var oldApp: WelcomeOldAppState
    @State private var oldAppBusy = false
    @State private var oldAppRunning: Bool
    @State private var loginStatus: LoginItem.Status = LoginItem.status()
    @State private var loginError: String?
    @State private var activations = 0
    @State private var contentHeight: CGFloat?
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var scrollerGutter: CGFloat = 0
    @State private var topFade: CGFloat = 0
    @State private var moreBelow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let panelWidth: CGFloat = 560

    init(notice: LegacyNotice, settings: AppSettings, onDone: @escaping () -> Void, actions: WelcomeActions,
         start: WelcomeStart = WelcomeStart(), maxPanelHeight: CGFloat? = nil) {
        self.notice = notice
        self.settings = settings
        self.onDone = onDone
        self.actions = actions
        self.maxPanelHeight = maxPanelHeight
        _archiveOutcome = State(initialValue: start.archive ?? notice.archiveKnown)
        _perm = State(initialValue: start.fullDiskAccess ? .granted : .idle)
        _oldAppRunning = State(initialValue: notice.oldAppRunning)
        switch start.oldApp {
        case .undecided: _oldApp = State(initialValue: .undecided(error: nil))
        case .kept: _oldApp = State(initialValue: .kept)
        case .trashed(let url): _oldApp = State(initialValue: .trashed(url, undoError: nil))
        }
    }

    // MARK: Derived state

    private var oldAppDecided: Bool {
        if case .undecided = oldApp { return false }
        return true
    }

    private var remaining: Int {
        WelcomeProgress.remaining(fdaGranted: perm == .granted, hasOldApp: notice.oldApp != nil, oldAppDecided: oldAppDecided)
    }

    /// The one button that carries `.defaultAction`. Both buttons read this, so two can never hold it at once.
    private enum DefaultButton { case openSettings, done }
    private var defaultButton: DefaultButton? {
        if perm == .idle { return .openSettings }
        return remaining == 0 ? .done : nil
    }

    private var requiredDone: [Bool] { [perm == .granted] + (notice.oldApp != nil ? [oldAppDecided] : []) }

    private var archiveRow: WelcomeProgress.ArchiveRow { WelcomeProgress.archiveRow(archiveOutcome) }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
            scrollRegion
            footer
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { footerHeight = $0 }
        }
        .frame(width: Self.panelWidth)
        .fixedSize(horizontal: false, vertical: maxPanelHeight == nil)
        .modifier(WelcomePanelSurface())
        .background { cancelShortcut }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("legacy-notice-sheet")
        .task {
            if notice.archivesMoving, archiveOutcome == nil, let t = actions.archiveTask() {
                archiveOutcome = await t.value
                retryIfNeeded()
            }
        }
        // D-W4: one silent probe when the panel appears (the panel is still invisible), then on every app-became-active while
        // it is mounted. No timer, no polling.
        .onAppear {
            if perm != .granted, actions.fullDiskAccess() == .granted { perm = .granted }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = LoginItem.status()
            if perm != .granted { activations += 1 }
        }
        .task(id: activations) { if activations > 0 { await check() } }
    }

    /// D-W4/W3: the "Checking" state for 0.6 s, then the non-prompting probe. A newer activation cancels this one.
    private func check() async {
        guard perm != .granted else { return }
        perm = .checking
        try? await Task.sleep(for: .seconds(0.6))
        guard !Task.isCancelled else { return }
        perm = actions.fullDiskAccess() == .granted ? .granted : .idle
        retryIfNeeded()
    }

    /// W4/D-W5: once per panel, when Full Disk Access arrives after a denied launch move.
    private func retryIfNeeded() {
        guard WelcomeProgress.shouldRetryArchives(fdaGranted: perm == .granted, outcome: archiveOutcome, retried: archiveRetried) else { return }
        archiveRetried = true
        if let t = actions.retryArchives() {
            archiveOutcome = nil
            Task { archiveOutcome = await t.value }
        }
    }

    /// Esc: the same as «Later» / «Done». Never writes a setting (W8).
    private var cancelShortcut: some View {
        Button("") { close() }
            .keyboardShortcut(.cancelAction)
            .disabled(oldAppBusy)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private func close() { onDone() }

    // MARK: Header (design §3.1)

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
                .noticePart(.rise(delay: 0.30))
            VStack(alignment: .leading, spacing: 6) {
                titleText
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.57)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .noticePart(.rise(delay: 0.40))
                Text(L.legacySubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(DS3.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .noticePart(.rise(delay: 0.50))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 24, leading: 28, bottom: 16, trailing: 28))
    }

    /// The brand word in `moonText`, the rest in `ink` (the whole title in `ink` when the brand is not found).
    private var titleText: Text {
        let full = L.legacyNoticeTitle
        guard let r = full.range(of: AppInfo.name) else { return Text(verbatim: full).foregroundStyle(DS3.ink) }
        let pre = Text(verbatim: String(full[..<r.lowerBound])).foregroundStyle(DS3.ink)
        let brand = Text(verbatim: String(full[r])).foregroundStyle(DS3.moonText)
        let post = Text(verbatim: String(full[r.upperBound...])).foregroundStyle(DS3.ink)
        return Text("\(pre)\(brand)\(post)")
    }

    // MARK: Scroll region (design §3.2)

    @ViewBuilder private var scrollRegion: some View {
        let groups = VStack(spacing: 16) {
            doneGroup.noticePart(.rise(delay: 0.62))
            todoGroup.noticePart(.rise(delay: 0.76))
        }
        .padding(EdgeInsets(top: 4, leading: 28, bottom: 16, trailing: maxPanelHeight == nil ? 28 : max(0, 28 - scrollerGutter)))
        if let maxPanelHeight {
            let cap = max(120, maxPanelHeight - headerHeight - footerHeight)
            ScrollView(.vertical) {
                groups.onGeometryChange(for: CGSize.self, of: { $0.size }) {
                    contentHeight = $0.height
                    // A legacy (always visible) scroller takes layout width. The groups give that width back from their
                    // trailing padding, so they end where the pinned footer ends. An overlay scroller leaves 0.
                    scrollerGutter = max(0, Self.panelWidth - $0.width)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.vertical, 6, for: .scrollIndicators)
            .contentMargins(.trailing, 6, for: .scrollIndicators)
            .onScrollGeometryChange(for: CGFloat.self, of: { min(max($0.contentOffset.y + $0.contentInsets.top, 0), 32) }) { _, new in
                topFade = new
            }
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.containerSize.height < $0.contentSize.height - 1 }) { _, new in
                moreBelow = new
            }
            // Fade the content out under the header instead of a divider. At offset 0 the mask is solid (no line).
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: topFade)
                    Rectangle()
                }
            }
            .frame(height: min(contentHeight ?? cap, cap))
        } else {
            groups.fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Groups and rows

    private func group<Rows: View>(label: String, caption: String?, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS3.inkSoft)
                Spacer(minLength: 8)
                if let caption {
                    Text(caption).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(DS3.muted)
                }
            }
            .padding(.horizontal, 4)
            Group(subviews: rows()) { subviews in
                VStack(spacing: 0) {
                    ForEach(subviews.indices, id: \.self) { i in
                        if i > 0 { Rectangle().fill(DS3.line).frame(height: 1) }
                        subviews[i]
                    }
                }
            }
            .ds3RowPanel(cornerRadius: 22)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One row: circle 28, title and caption, trailing item. `step` rows are taller (design §3.2).
    private func row<Caption: View, Trailing: View>(
        _ circle: WelcomeStatusCircle.Kind, title: String, tag: String? = nil, titleColor: Color = DS3.ink, step: Bool = false,
        textButtonTrailing: Bool = false, @ViewBuilder caption: () -> Caption, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            WelcomeStatusCircle(kind: circle)
            VStack(alignment: .leading, spacing: step ? 2 : 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if let tag { Text(tag).font(.system(size: 12.5)).foregroundStyle(DS3.muted) }
                }
                caption()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(EdgeInsets(top: step ? 11 : 9, leading: 16, bottom: step ? 11 : 9, trailing: textButtonTrailing ? 10 : 16))
    }

    private func captionText(_ text: String, color: Color = DS3.muted) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func meta(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(DS3.muted).fixedSize()
    }

    private func textButton(_ title: String, id: String, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).dsSwapInPlace(busy) { DS3Spinner(role: .softRing, size: 13) }
        }
        .buttonStyle(DS3ButtonStyle(kind: .text, height: 30, hPad: 10))
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    // MARK: Done automatically (design §3.3)

    private var doneCaption: String {
        switch WelcomeProgress.doneCaption(dataShown: notice.moved > 0, archive: notice.archivesMoving ? archiveRow : nil, failed: notice.failed) {
        case .progress(let done, let total): L.legacyDoneProgress(done: done, total: total)
        case .allInPlace: L.legacyDoneAllInPlace
        case .withNotes: L.legacyDoneWithNotes
        }
    }

    private var doneGroup: some View {
        group(label: L.legacySectionDone, caption: doneCaption) {
            if notice.moved > 0 {
                row(.done, title: L.legacyDataMovedTitle, caption: { captionText(L.legacyDataMovedSub) },
                    trailing: { meta(L.legacyFilesTag(notice.moved)) })
            }
            if notice.archivesMoving { archivesRow }
            if notice.parked > 0 {
                row(.info, title: L.legacyParkedTitle(notice.parked), textButtonTrailing: true,
                    caption: { captionText(L.legacyParkedSub) },
                    trailing: { textButton(L.legacyShowButton, id: "legacy-parked-show") { revealParked() } })
            }
            if notice.failed > 0 {
                row(.error, title: L.legacyFailedTitle(notice.failed), titleColor: DS3.hotInk, textButtonTrailing: true,
                    caption: { captionText(L.legacyFailedSub) },
                    trailing: { textButton(L.legacyShowButton, id: "legacy-failed-show") { revealFailed() } })
                    .background(LinearGradient(stops: [.init(color: DS3.hot.opacity(0.09), location: 0), .init(color: .clear, location: 0.7)],
                                               startPoint: .leading, endPoint: .trailing))
            }
        }
    }

    private var archivePathLine: some View {
        Text("~/Documents/" + AppInfo.supportFolderName + "/iPhone")
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .tracking(0.125)
            .foregroundStyle(DS3.muted)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(IPhoneStore.defaultArchiveRoot().path)
    }

    /// D-W8: the archive row by state; the swap fades like an item (design §5).
    @ViewBuilder private var archivesRow: some View {
        Group {
            switch archiveRow {
            case .busy:
                row(.busy, title: L.legacyArchivesMovingTitle, caption: {
                    VStack(alignment: .leading, spacing: 7) {
                        archivePathLine
                        ProgressView().progressViewStyle(.linear).tint(DS3.accent).frame(height: 4)
                    }
                }, trailing: { meta(L.legacyArchivesMovingTag) })
            case .done:
                row(.done, title: L.legacyArchivesMovedTitle, caption: { archivePathLine },
                    trailing: { if notice.archiveCount > 0 { meta(L.legacyArchivesTag(notice.archiveCount)) } })
            case .left(let n):
                row(.warning, title: L.legacyArchivesMovedTitle, textButtonTrailing: true,
                    caption: { captionText(L.legacyArchivesLeftSub(n), color: DS3.amberInk) },
                    trailing: {
                        textButton(L.legacyShowButton, id: "legacy-archives-show") {
                            actions.reveal([], IPhoneStore.legacyDocumentsArchiveRoot())
                        }
                    })
            case .denied:
                row(.warning, title: L.legacyArchivesDeniedTitle,
                    caption: {
                        captionText(archiveRetried ? L.legacyArchivesDeniedAgainSub : L.legacyArchivesDeniedSub, color: DS3.amberInk)
                    }, trailing: { EmptyView() })
            }
        }
        .transition(.welcomeItem(reduceMotion))
        .animation(WelcomeMotion.item(reduceMotion), value: archiveRow)
    }

    // D-W7: Finder selections. Both versions of up to 5 parked files, else the park folder.
    private func revealParked() {
        guard let folder = notice.parkedFolder else { return }
        if notice.parked <= 5, !notice.parkedFiles.isEmpty {
            let urls = notice.parkedFiles.flatMap {
                [AppInfo.supportFolderURL.appendingPathComponent($0), folder.appendingPathComponent($0)]
            }
            actions.reveal(urls, folder)
        } else {
            actions.reveal([], folder)
        }
    }

    private func revealFailed() {
        let old = AppInfo.legacySupportFolderURL
        actions.reveal(notice.failedFiles.prefix(10).map { old.appendingPathComponent($0) }, old)
    }

    // MARK: For you to do (design §3.4)

    private var todoGroup: some View {
        group(label: L.legacySectionTodo, caption: nil) {
            permissionsRow
            if let app = notice.oldApp { oldAppRow(app) }
            loginRow
        }
    }

    private var permissionsRow: some View {
        row(perm == .granted ? .done : .step(1), title: L.legacyPermsTitle, step: true,
            caption: { captionText(L.legacyPermsSub) },
            trailing: {
                ZStack(alignment: .trailing) {
                    switch perm {
                    case .idle:
                        Button(L.legacyOpenButton) { actions.openFullDiskAccess() }
                            .buttonStyle(DS3ButtonStyle(kind: .primary, height: 32, hPad: 18))
                            .keyboardShortcut(defaultButton == .openSettings ? .defaultAction : nil)
                            .accessibilityLabel(L.legacyOpenButton)
                            .accessibilityIdentifier("legacy-open-fda")
                    case .checking:
                        Button {} label: {
                            HStack(spacing: 6) {
                                DS3Spinner(role: .softRing, size: 13)
                                Text(L.legacyCheckingLabel).foregroundStyle(DS3.inkSoft)
                            }
                        }
                        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14))
                        .disabled(true)
                        .accessibilityLabel(L.legacyCheckingLabel)
                    case .granted:
                        Text(L.legacyGrantedLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS3.greenInk)
                            .transition(.welcomePop(reduceMotion))
                    }
                }
                .frame(minWidth: 96, alignment: .trailing)
                .animation(WelcomeMotion.pop(reduceMotion), value: perm)
            })
    }

    private func oldAppRow(_ app: URL) -> some View {
        row(oldAppDecided ? .done : .step(2), title: L.legacyOldAppTitle, step: true, textButtonTrailing: oldAppDecided,
            caption: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.lastPathComponent)
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .tracking(0.125)
                            .foregroundStyle(DS3.inkSoft)
                            .lineLimit(1)
                        Text(L.legacyInApplications).font(.system(size: 12.5)).foregroundStyle(DS3.muted).lineLimit(1)
                    }
                    .help(app.path)
                    oldAppCaptionLine
                }
            },
            trailing: { oldAppTrailing })
    }

    @ViewBuilder private var oldAppCaptionLine: some View {
        switch oldApp {
        case .undecided(let error):
            if let error { captionText(error, color: DS3.hotInk) }
            else { captionText(oldAppRunning ? L.legacyNoticeOldAppRunning : L.legacyOldAppNoneSub) }
        case .kept:
            captionText(L.legacyOldAppKeptSub)
        case .trashed(_, let undoError):
            if let undoError { captionText(undoError, color: DS3.hotInk) } else { captionText(L.legacyOldAppTrashedSub) }
        }
    }

    @ViewBuilder private var oldAppTrailing: some View {
        switch oldApp {
        case .undecided:
            HStack(spacing: 6) {
                Button(L.legacyKeepButton) { keepOldApp() }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14))
                    .disabled(oldAppBusy)
                    .accessibilityLabel(L.legacyKeepButton)
                    .accessibilityIdentifier("legacy-keep")
                Button { Task { await trashOldApp() } } label: {
                    Text(L.legacyTrashButton).dsSwapInPlace(oldAppBusy) { DS3Spinner(role: .softRing, size: 13) }
                }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, dangerInk: true))
                .disabled(oldAppBusy)
                .accessibilityLabel(L.legacyTrashButton)
                .accessibilityIdentifier("legacy-trash")
            }
            .transition(.welcomeItem(reduceMotion))
        case .kept, .trashed:
            HStack(spacing: 6) {
                Text(isTrashed ? L.legacyInTrashLabel : L.legacyKeptLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS3.muted)
                if !hasUndoError {
                    Button { Task { await undoOldApp() } } label: {
                        Text(L.legacyUndoButton).dsSwapInPlace(oldAppBusy) { DS3Spinner(role: .softRing, size: 13) }
                    }
                    .buttonStyle(DS3ButtonStyle(kind: .text, height: 30, hPad: 10))
                    .disabled(oldAppBusy)
                    .accessibilityLabel(L.legacyUndoButton)
                    .accessibilityIdentifier("legacy-undo")
                }
            }
            .transition(.welcomeItem(reduceMotion))
        }
    }

    private var isTrashed: Bool {
        if case .trashed = oldApp { return true }
        return false
    }

    private var hasUndoError: Bool {
        if case .trashed(_, let e) = oldApp { return e != nil }
        return false
    }

    // D-W10: «Keep» / «Move to Trash» / «Undo». Esc, «Later» and «Done» never touch `legacyAppOfferDismissed`.
    private func keepOldApp() {
        settings.legacyAppOfferDismissed = true
        withAnimation(WelcomeMotion.item(reduceMotion)) { oldApp = .kept }
    }

    private func trashOldApp() async {
        oldAppBusy = true
        defer { oldAppBusy = false }
        if oldAppRunning {
            guard await actions.quitOldApp() else { oldApp = .undecided(error: L.legacyQuitRefused); return }
            oldAppRunning = false
        }
        do {
            let url = try actions.trash()
            withAnimation(WelcomeMotion.item(reduceMotion)) { oldApp = .trashed(url, undoError: nil) }
        } catch {
            oldApp = .undecided(error: L.legacyTrashFailed(reason: error.localizedDescription))
        }
    }

    private func undoOldApp() async {
        switch oldApp {
        case .kept:
            settings.legacyAppOfferDismissed = false
            withAnimation(WelcomeMotion.item(reduceMotion)) { oldApp = .undecided(error: nil) }
        case .trashed(let url, _):
            oldAppBusy = true
            defer { oldAppBusy = false }
            do {
                try actions.restore(url)
                withAnimation(WelcomeMotion.item(reduceMotion)) { oldApp = .undecided(error: nil) }
            } catch let e as LegacyApp.RestoreError {
                oldApp = .trashed(url, undoError: e == .originalOccupied ? L.legacyRestoreOccupied : L.legacyRestoreGone)
            } catch {
                oldApp = .trashed(url, undoError: L.legacyRestoreFailed)
            }
        case .undecided:
            break
        }
    }

    private var loginRow: some View {
        row(.optional, title: L.settingsLaunchAtLoginLabel, tag: L.legacyOptionalTag, step: true,
            caption: { captionText(loginError ?? L.legacyLoginSub, color: loginError != nil ? DS3.hotInk : DS3.muted) },
            trailing: {
                DS3Switch(isOn: loginBinding, label: L.settingsLaunchAtLoginLabel, metrics: .settings)
                    .frame(minWidth: 96, alignment: .trailing)
                    .accessibilityIdentifier("legacy-login-switch")
            })
    }

    /// The same source of truth as Settings › General: `LoginItem` (the switch shows the system's real status).
    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled },
            set: { on in
                do { try LoginItem.setEnabled(on); loginError = nil } catch { loginError = error.localizedDescription }
                loginStatus = LoginItem.status()
                if loginStatus == .requiresApproval { LoginItem.openLoginItemsSettings() }
            }
        )
    }

    // MARK: Footer (design §3.5)

    private var footer: some View {
        HStack(spacing: 12) {
            if remaining > 0 {
                HStack(spacing: 10) {
                    WelcomeProgressDots(steps: requiredDone)
                    Text(L.legacyStepsLeft(remaining)).font(.system(size: 13, weight: .medium)).foregroundStyle(DS3.inkSoft)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.legacyStepsLeft(remaining))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    Text(L.legacyAllDone).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DS3.greenInk)
                .transition(.welcomePop(reduceMotion))
            }
            Spacer(minLength: 0)
            if remaining > 0 {
                Button { close() } label: { Text(L.legacyLaterButton).frame(minWidth: 64) }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 20))
                    .disabled(oldAppBusy)
                    .accessibilityLabel(L.legacyLaterButton)
                    .accessibilityIdentifier("legacy-later")
            } else {
                Button { close() } label: { Text(L.legacyDoneButton).frame(minWidth: 64) }
                    .buttonStyle(DS3ButtonStyle(kind: .primary, height: 34, hPad: 20))
                    .keyboardShortcut(defaultButton == .done ? .defaultAction : nil)
                    .disabled(oldAppBusy)
                    .transition(.welcomePop(reduceMotion))
                    .accessibilityLabel(L.legacyDoneButton)
                    .accessibilityIdentifier("legacy-done")
            }
        }
        .animation(WelcomeMotion.pop(reduceMotion), value: remaining == 0)
        .padding(EdgeInsets(top: 14, leading: 32, bottom: 18, trailing: 22))
        .overlay(alignment: .top) { Rectangle().fill(DS3.line).frame(height: 1) }
        .overlay(alignment: .top) {
            if maxPanelHeight != nil {
                LinearGradient(colors: [.clear, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 12)
                    .offset(y: -12)
                    .opacity(moreBelow ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: moreBelow)
                    .allowsHitTesting(false)
            }
        }
        .noticePart(.rise(delay: 0.90))
    }
}

// MARK: - Surface (D-W12, D-W15, D-W17)

/// The panel's own surface: material and `panel` tint (opaque under Reduce Transparency), the top glow, the inset top rim,
/// the pointer rim and the pre-rendered `welcome` shadow. The overlay adds only veil, placement, motion and focus.
private struct WelcomePanelSurface: ViewModifier {
    @Environment(GlassSettings.self) private var glass: GlassSettings?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let usesMaterial = (glass?.fill ?? .standard).usesMaterial
        content
            .background {
                ZStack(alignment: .top) {
                    if usesMaterial { Rectangle().fill(.regularMaterial) }
                    Rectangle().fill(usesMaterial ? DS3.panel : DS3.overlaySolid)
                    topGlow
                }
                .clipShape(shape)
            }
            .ds3InsetRims(shape, top: DS3.rimMid)
            .overlay { DS3Rim(cornerRadius: 28) }
            .ds3ElevationSprite(.welcome, cornerRadius: 28)
            .contentShape(shape)
    }

    /// Radial ellipse 80 % × 120 % at (12 %, 0) of a 560 × 160 box, accent 14 % to clear at 62 %.
    private var topGlow: some View {
        EllipticalGradient(stops: [.init(color: DS3.accent.opacity(0.14), location: 0), .init(color: .clear, location: 0.62)])
            .frame(width: 896, height: 384)
            .offset(x: 67 - 448, y: -192)
            .frame(width: 560, height: 160, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(false)
            .noticePart(.glow)
    }
}
