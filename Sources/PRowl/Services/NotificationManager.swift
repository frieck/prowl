import Foundation
import AppKit
import UserNotifications

/// Wraps UNUserNotificationCenter for requesting authorization, posting local
/// notifications when a PR's status changes, and handling taps on them.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private static let urlKey = "url"
    private static let openSettingsKey = "openSettings"
    private static let missingTokenID = "prowl.missing-token"
    private static let registrationID = "prowl.register"

    /// Invoked when the user taps a notification that has no PR URL (e.g. the
    /// "missing token" nudge). Set by the app to open the Settings window.
    var onOpenSettings: (@MainActor () -> Void)?

    /// True when the user has denied notification permission in System Settings.
    private(set) var isDenied = false

    /// Latest authorization status for UI diagnostics.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// True when authorized but banner alerts are disabled in System Settings.
    private(set) var alertsDisabled = false

    /// Human-readable status for Settings UI.
    var statusSummary: String {
        switch authorizationStatus {
        case .authorized:
            return alertsDisabled ? "Allowed, but banners are off" : "Allowed"
        case .denied:
            return "Denied in System Settings"
        case .notDetermined:
            return "Not enabled yet — click Enable Notifications"
        case .provisional:
            return "Provisional"
        @unknown default:
            return "Unknown"
        }
    }

    var needsUserAuthorization: Bool {
        authorizationStatus == .notDetermined
    }

    /// Opens System Settings → Notifications.
    func openSystemNotificationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private override init() {
        super.init()
        bindDelegate()
    }

    /// SwiftUI can clobber the delegate after launch; re-attach on lifecycle hooks.
    func bindDelegate() {
        if Thread.isMainThread {
            center.delegate = self
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.center.delegate = self
            }
        }
    }

    private func activateForPermissionPrompt() {
        if Thread.isMainThread {
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Reads current notification settings without prompting.
    func refreshAuthorizationStatus(completion: ((Bool) -> Void)? = nil) {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(settings)
                let canDeliver = self.canDeliverAlerts(from: settings)
                NSLog("PRowl: notification status auth=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) canDeliver=\(canDeliver)")
                completion?(canDeliver)
            }
        }
    }

    /// Must be called from an explicit user action (button click). macOS 26 rejects
    /// or errors on permission prompts that are not tied to user interaction.
    func requestAuthorizationFromUser(completion: ((Bool) -> Void)? = nil) {
        bindDelegate()
        activateForPermissionPrompt()

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    NSLog("PRowl: notification authorization error: \(error.localizedDescription)")
                }
                self.refreshAuthorizationStatus { granted in
                    if granted {
                        self.registerWithNotificationCenter()
                        self.promptIfMissingToken()
                    }
                    completion?(granted)
                }
            }
        }
    }

    /// Ensures we have permission before posting; does not prompt unless already authorized.
    func ensureAuthorized(completion: @escaping (Bool) -> Void) {
        refreshAuthorizationStatus(completion: completion)
    }

    /// Called when the user opens the menu-bar panel or settings window.
    func prepareOnUserInteraction() {
        bindDelegate()
        refreshAuthorizationStatus { [weak self] granted in
            guard granted else { return }
            self?.promptIfMissingToken()
        }
    }

    func promptIfMissingToken() {
        guard !GitHubAuth.isConfigured else { return }

        refreshAuthorizationStatus { [weak self] granted in
            guard granted else { return }
            self?.deliverMissingTokenNotification()
        }
    }

    func promptIfMissingTokenAfterTokenRemoved() {
        promptIfMissingToken()
    }

    private func apply(_ settings: UNNotificationSettings) {
        authorizationStatus = settings.authorizationStatus
        isDenied = settings.authorizationStatus == .denied
        alertsDisabled = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            && settings.alertSetting == .disabled
    }

    private func canDeliverAlerts(from settings: UNNotificationSettings) -> Bool {
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return settings.alertSetting != .disabled
        default:
            return false
        }
    }

    /// macOS 26 may omit apps from Notification settings until one notification is delivered.
    private func registerWithNotificationCenter() {
        refreshAuthorizationStatus { [weak self] granted in
            guard granted, let self else { return }

            self.center.removePendingNotificationRequests(withIdentifiers: [Self.registrationID])
            self.center.removeDeliveredNotifications(withIdentifiers: [Self.registrationID])

            let content = UNMutableNotificationContent()
            content.title = "PRowl"
            content.body = "Notifications enabled"
            content.sound = nil
            self.enqueue(content: content, identifier: Self.registrationID, completion: nil)
        }
    }

    private func deliverMissingTokenNotification() {
        guard !GitHubAuth.isConfigured else { return }

        center.removePendingNotificationRequests(withIdentifiers: [Self.missingTokenID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.missingTokenID])

        let content = UNMutableNotificationContent()
        content.title = "PRowl is flying blind"
        content.body = "No GitHub token yet, so this owl can't spot your pull requests. Click here to give it eyes."
        content.sound = .default
        content.userInfo = [Self.openSettingsKey: true]

        enqueue(content: content, identifier: Self.missingTokenID)
    }

    func notify(title: String, body: String, prURL: URL?, opensSettings: Bool = false) {
        post(title: title, body: body, prURL: prURL, opensSettings: opensSettings)
    }

    func sendTestNotification(completion: ((Bool) -> Void)? = nil) {
        bindDelegate()
        activateForPermissionPrompt()

        refreshAuthorizationStatus { [weak self] granted in
            guard granted, let self else {
                completion?(false)
                return
            }
            self.post(
                title: "PRowl test",
                body: "If you see this, notifications are working.",
                prURL: nil,
                opensSettings: false,
                completion: completion
            )
        }
    }

    private func post(
        title: String,
        body: String,
        prURL: URL?,
        opensSettings: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        bindDelegate()
        refreshAuthorizationStatus { [weak self] granted in
            guard granted, let self else {
                completion?(false)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .active
            }
            var info: [String: Any] = [:]
            if let prURL {
                info[Self.urlKey] = prURL.absoluteString
            }
            if opensSettings {
                info[Self.openSettingsKey] = true
            }
            content.userInfo = info

            self.enqueue(content: content, identifier: UUID().uuidString, completion: completion)
        }
    }

    private func enqueue(
        content: UNMutableNotificationContent,
        identifier: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.25, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            DispatchQueue.main.async {
                if let error {
                    NSLog("PRowl: failed to deliver notification: \(error.localizedDescription)")
                    completion?(false)
                } else {
                    NSLog("PRowl: scheduled notification '\(content.title)'")
                    completion?(true)
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 12.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo

        if let urlString = info[Self.urlKey] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else if info[Self.openSettingsKey] as? Bool == true {
            Task { @MainActor [weak self] in
                NSApplication.shared.activate(ignoringOtherApps: true)
                self?.onOpenSettings?()
            }
        }
        completionHandler()
    }
}
