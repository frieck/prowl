import AppKit
import Foundation

enum BartenderError: LocalizedError {
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .syncFailed:
            return "Could not update Bartender preferences."
        }
    }
}

/// Best-effort integration with Bartender (no public API — uses documented defaults keys).
enum BartenderIntegration {
    private static let bartenderDomain = "com.surteesstudios.Bartender" as CFString
    private static let ignoreKey = "IgnoreAppsWithBundleIdentifiers" as CFString
    private static let profileKey = "ProfileSettings"

    static var appBundleID: String {
        Bundle.main.bundleIdentifier ?? "br.com.farsystems.prowl"
    }

    /// Bartender indexes status items as `{bundleID}-Item-0` in many setups.
    static var menuBarItemID: String {
        "\(appBundleID)-Item-0"
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.surteesstudios.Bartender") != nil
    }

    /// When true, Bartender should not move/hide PRowl's icon at all.
    static var isExcludedFromManagement: Bool {
        ignoredBundleIDs().contains(appBundleID)
    }

    static func ignoredBundleIDs() -> [String] {
        CFPreferencesCopyAppValue(ignoreKey, bartenderDomain) as? [String] ?? []
    }

    static func setExcludedFromManagement(_ excluded: Bool) throws {
        var ids = ignoredBundleIDs()
        if excluded {
            guard !ids.contains(appBundleID) else {
                try pinToShownItems()
                return
            }
            ids.append(appBundleID)
        } else {
            ids.removeAll { $0 == appBundleID }
        }

        CFPreferencesSetAppValue(ignoreKey, ids as CFPropertyList, bartenderDomain)
        guard CFPreferencesAppSynchronize(bartenderDomain) else {
            throw BartenderError.syncFailed
        }

        if excluded {
            try pinToShownItems()
        }
    }

    /// Moves PRowl from Hide/AlwaysHide into Show in Bartender's active profile.
    private static func pinToShownItems() throws {
        guard var profileSettings = readProfileSettings(),
              var activeProfile = profileSettings["activeProfile"] as? [String: Any] else {
            return
        }

        let itemID = menuBarItemID
        var show = activeProfile["Show"] as? [String] ?? []
        var hide = activeProfile["Hide"] as? [String] ?? []
        var alwaysHide = activeProfile["AlwaysHide"] as? [String] ?? []

        hide.removeAll { $0 == itemID || $0.hasPrefix(appBundleID) }
        alwaysHide.removeAll { $0 == itemID || $0.hasPrefix(appBundleID) }
        if !show.contains(itemID) {
            show.append(itemID)
        }

        activeProfile["Show"] = show
        activeProfile["Hide"] = hide
        activeProfile["AlwaysHide"] = alwaysHide
        profileSettings["activeProfile"] = activeProfile

        CFPreferencesSetAppValue(profileKey as CFString, profileSettings as CFPropertyList, bartenderDomain)
        guard CFPreferencesAppSynchronize(bartenderDomain) else {
            throw BartenderError.syncFailed
        }
    }

    private static func readProfileSettings() -> [String: Any]? {
        CFPreferencesCopyAppValue(profileKey as CFString, bartenderDomain) as? [String: Any]
    }

    static func openBartender() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.surteesstudios.Bartender") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
