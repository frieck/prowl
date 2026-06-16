import Foundation

enum GitHubCLIError: LocalizedError {
    case notInstalled
    case notLoggedIn
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "GitHub CLI (`gh`) is not installed. Install it from https://cli.github.com and run `gh auth login`."
        case .notLoggedIn:
            return "GitHub CLI is not logged in. Run `gh auth login` in Terminal."
        case .commandFailed(let detail):
            return detail
        }
    }
}

/// Reads credentials from the user's installed `gh` binary (same API access as `gh api`).
enum GitHubCLIAuth {
    private static let candidatePaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "\(NSHomeDirectory())/.local/bin/gh"
    ]

    static var isInstalled: Bool {
        resolveExecutable() != nil
    }

    static var isLoggedIn: Bool {
        guard isInstalled else { return false }
        return (try? token()) != nil
    }

    static func token() throws -> String {
        let output = try run(arguments: ["auth", "token"])
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GitHubCLIError.notLoggedIn }
        return token
    }

    static func statusSummary() -> String {
        guard isInstalled else {
            return "Install `gh` from cli.github.com, then run `gh auth login`."
        }
        do {
            let status = try run(arguments: ["auth", "status"])
            let firstLine = status.split(separator: "\n").first.map(String.init) ?? status
            return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func resolveExecutable() -> String? {
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return findViaWhich()
    }

    private static func findViaWhich() -> String? {
        let output = try? runViaEnv(arguments: ["which", "gh"])
        guard let path = output?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }

    private static func run(arguments: [String]) throws -> String {
        if let executable = resolveExecutable() {
            return try runProcess(executableURL: URL(fileURLWithPath: executable), arguments: arguments)
        }
        return try runViaEnv(arguments: ["gh"] + arguments)
    }

    private static func runViaEnv(arguments: [String]) throws -> String {
        try runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/env"), arguments: arguments)
    }

    private static func runProcess(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = shellEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GitHubCLIError.notInstalled
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            if process.terminationReason == .exit && process.terminationStatus == 127 {
                throw GitHubCLIError.notInstalled
            }
            if arguments.contains("token") {
                throw GitHubCLIError.notLoggedIn
            }
            let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitHubCLIError.commandFailed(detail.isEmpty ? "gh exited with code \(process.terminationStatus)" : detail)
        }

        return out
    }

    private static func shellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let prefix = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ].joined(separator: ":")
        env["PATH"] = prefix + ":" + (env["PATH"] ?? "")
        return env
    }
}
