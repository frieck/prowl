import Foundation

/// How PRowl obtains GitHub API credentials.
enum AuthMethod: String, CaseIterable, Identifiable, Codable {
    case personalToken
    case githubCLI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .personalToken: return "Personal access token"
        case .githubCLI: return "GitHub CLI (gh)"
        }
    }
}

enum GitHubAuth {
    private static let methodKey = "authMethod"

    static var method: AuthMethod {
        get {
            guard let raw = UserDefaults.standard.string(forKey: methodKey),
                  let method = AuthMethod(rawValue: raw) else {
                return .personalToken
            }
            return method
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: methodKey)
        }
    }

    static var isConfigured: Bool {
        switch method {
        case .personalToken:
            return KeychainStore.hasToken
        case .githubCLI:
            return GitHubCLIAuth.isLoggedIn
        }
    }

    static var configurationHint: String {
        switch method {
        case .personalToken:
            return "Paste a fine-grained or classic token in Settings."
        case .githubCLI:
            return GitHubCLIAuth.statusSummary()
        }
    }

    static func resolveToken() throws -> String {
        switch method {
        case .personalToken:
            guard let token = KeychainStore.loadToken() else {
                throw GitHubError.noToken
            }
            return token
        case .githubCLI:
            return try GitHubCLIAuth.token()
        }
    }
}
