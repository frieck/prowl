import Foundation

/// Shared launch wiring so AppDelegate and SwiftUI views can reach the poller.
@MainActor
enum AppCoordinator {
    static var poller: PRPoller?

    static var openSettings: (@MainActor () -> Void)? {
        return { StatusBarController.shared.openSettingsInPopover() }
    }
}
