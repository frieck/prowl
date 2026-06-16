import AppKit
import UserNotifications

/// Handles app-launch hooks that must run before the menu-bar popover opens.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NotificationManager.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.bindDelegate()

        Task { @MainActor in
            let poller = PRPoller()
            AppCoordinator.poller = poller
            StatusBarController.shared.setup(poller: poller)
        }

        NotificationManager.shared.onOpenSettings = {
            Task { @MainActor in
                AppCoordinator.openSettings?()
            }
        }

        NotificationManager.shared.refreshAuthorizationStatus()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NotificationManager.shared.bindDelegate()
        NotificationManager.shared.refreshAuthorizationStatus()
    }
}
