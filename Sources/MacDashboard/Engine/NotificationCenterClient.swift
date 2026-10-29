// Engine/NotificationCenterClient.swift
// REDESIGN-NOTIFY: the app's one UNUserNotificationCenter client (authorization, posting, delegate). Everything that decides
// WHAT to post is pure and lives in NotificationEngine.swift; this file only talks to the system. Never touched under
// -visualFixture or in `swift test`: UNUserNotificationCenter.current() traps in a process without a bundle.
import Foundation
import UserNotifications

/// App-side view of the system status (pure enum so views and the fixture can hold it without the framework).
enum NotificationAuthorization: Equatable { case notDetermined, authorized, denied }

@MainActor
final class NotificationCenterClient: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterClient()
    /// Snapshot tests / -visualFixture: when non-nil, `status` answers this without touching the system. Unset under
    /// fixture means `.authorized` (ARCH-ENGINE-GUARD: the branch left SettingsView; ContentSnapshotTests sets
    /// `.denied` for one state and nil to restore).
    static var fixtureStatus: NotificationAuthorization? {
        get { fixtureStatusOverride ?? (VisualFixture.isRequested ? .authorized : nil) }
        set { fixtureStatusOverride = newValue }
    }
    private static var fixtureStatusOverride: NotificationAuthorization?

    /// Set by AppModel.start(): banner allowed iff the app is "paused" (not frontmost with a visible window).
    var shouldPresentBanner: () -> Bool = { true }
    /// Set by AppModel.start(): a click on a notification carrying `page` lands here (Stage 2).
    var onOpen: (Page) -> Void = { _ in }

    private var installed = false
    func install() {
        guard !installed else { return }
        installed = true
        UNUserNotificationCenter.current().delegate = self
    }

    func status(_ completion: @escaping @MainActor (NotificationAuthorization) -> Void) {
        if let fixed = Self.fixtureStatus { completion(fixed); return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let mapped: NotificationAuthorization
            switch s.authorizationStatus {
            case .authorized, .provisional: mapped = .authorized
            case .denied: mapped = .denied
            default: mapped = .notDetermined
            }
            Task { @MainActor in completion(mapped) }
        }
    }

    func requestAuthorization(_ completion: @escaping @MainActor (Bool) -> Void) {
        if Self.fixtureStatus != nil { completion(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("notify: requestAuthorization error: %@", error.localizedDescription) }
            Task { @MainActor in completion(granted) }
        }
    }

    /// Posts one notification now. `identifier` repeats replace the delivered one (no pile-up in Notification Center).
    func deliver(identifier: String, title: String, body: String, page: Page?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let page { content.userInfo = ["page": page.rawValue] }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("notify: add(%@) error: %@", identifier, error.localizedDescription) }
        }
    }

    // MARK: UNUserNotificationCenterDelegate (called on an arbitrary queue; hop to the main actor)

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { shouldPresentBanner() ? [.banner, .list, .sound] : [] }
    }

    /// macOS has already activated the app when this runs; only the page remains to be opened.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["page"] as? String
        await MainActor.run { if let raw, let page = Page(rawValue: raw) { onOpen(page) } }
    }

    // MARK: -notifyProbe (Stage 1 gate and the on-demand eye check; prints every value it reads)

    /// Installs the delegate, prints the current status, requests authorization, and 5 s later posts one notification
    /// (switch to another app within those 5 s to see the banner). Posts the Low-disk-space category's title with a
    /// fixed debug body; the click opens Storage.
    func runProbe() {
        install()
        print("notifyProbe: bundle=\(Bundle.main.bundleIdentifier ?? "nil") path=\(Bundle.main.bundlePath)")
        status { before in
            print("notifyProbe: status before request = \(before)")
            self.requestAuthorization { granted in
                print("notifyProbe: granted = \(granted)")
                self.status { after in
                    print("notifyProbe: status after request = \(after)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.deliver(identifier: "probe", title: L.settingsNotifyLabel(.disk),
                                     body: "Probe: a Low disk space notification looks like this.", page: NotifyCategory.disk.page)
                        print("notifyProbe: posted identifier=probe at \(Date())")
                    }
                }
            }
        }
    }
}
