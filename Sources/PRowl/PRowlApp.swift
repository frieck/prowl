import SwiftUI

@main
struct PRowlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu-bar only app; the status item is managed by StatusBarController.
        Settings {
            EmptyView()
        }
    }
}
