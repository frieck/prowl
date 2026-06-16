import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var statusMessage: String? {
        switch status {
        case .requiresApproval:
            return "Approve PRowl in System Settings → General → Login Items & Extensions."
        case .notFound:
            return "Install PRowl in Applications, then enable this option again."
        default:
            return nil
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        if #available(macOS 14.0, *) {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
