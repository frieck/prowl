import Foundation

/// The sets of PRs the user can choose to watch. Each maps to a GitHub search
/// qualifier. They are run as separate aliased searches and merged by id.
enum WatchSet: String, CaseIterable, Identifiable, Codable {
    case authored
    case reviewRequested
    case assigned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .authored: return "Authored by me"
        case .reviewRequested: return "Review requested"
        case .assigned: return "Assigned to me"
        }
    }

    var qualifier: String {
        switch self {
        case .authored: return "author:@me"
        case .reviewRequested: return "review-requested:@me"
        case .assigned: return "assignee:@me"
        }
    }
}

enum GitHubError: LocalizedError {
    case noToken
    case githubCLI(String)
    case http(Int, String)
    case graphQL(String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            switch GitHubAuth.method {
            case .personalToken:
                return "No GitHub token configured. Add one in Settings."
            case .githubCLI:
                return GitHubCLIError.notLoggedIn.errorDescription
            }
        case .githubCLI(let message):
            return message
        case .http(let code, let body):
            if code == 401 { return "Authentication failed (401). Check your token." }
            return "GitHub returned HTTP \(code). \(body)"
        case .graphQL(let message):
            return "GitHub API error: \(message)"
        case .decoding(let message):
            return "Could not read GitHub response: \(message)"
        case .transport(let message):
            return "Network error: \(message)"
        }
    }
}

/// Minimal GitHub GraphQL client that fetches open PRs and their status fields.
struct GitHubClient {
    static let defaultEndpoint = "https://api.github.com/graphql"

    private let endpoint: URL
    private let session: URLSession

    init(apiURL: String = GitHubClient.defaultEndpoint, session: URLSession = .shared) {
        let trimmed = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = URL(string: trimmed.isEmpty ? GitHubClient.defaultEndpoint : trimmed)
            ?? URL(string: GitHubClient.defaultEndpoint)!
        self.session = session
    }

    /// Fetches and merges open PRs for the enabled watch sets.
    func fetchOpenPullRequests(sets: [WatchSet]) async throws -> GitHubFetchResult {
        let token: String
        do {
            token = try GitHubAuth.resolveToken()
        } catch let error as GitHubCLIError {
            throw GitHubError.githubCLI(error.errorDescription ?? "GitHub CLI error.")
        } catch {
            throw GitHubError.noToken
        }
        let enabled = sets.isEmpty ? [.authored] : sets
        let query = buildQuery(sets: enabled)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // merge-info preview enables `mergeStateStatus`.
        request.setValue("application/vnd.github.merge-info-preview+json", forHTTPHeaderField: "Accept")
        request.setValue("PRowl", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.http(http.statusCode, body)
        }

        return try parse(data: data, sets: enabled)
    }

    // MARK: - Query construction

    private func buildQuery(sets: [WatchSet]) -> String {
        let searches = sets.enumerated().map { index, set -> String in
            let q = "is:pr is:open archived:false \(set.qualifier)"
            return """
            s\(index): search(query: \"\(q)\", type: ISSUE, first: 50) {
              nodes { ...prFields }
            }
            """
        }.joined(separator: "\n")

        return """
        query {
        \(searches)
        }
        fragment prFields on PullRequest {
          id
          number
          title
          url
          isDraft
          state
          updatedAt
          repository { nameWithOwner }
          author { login }
          reviewDecision
          mergeable
          mergeStateStatus
          comments { totalCount }
          reviews { totalCount }
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup { state }
              }
            }
          }
        }
        """
    }

    // MARK: - Parsing

    private func parse(data: Data, sets: [WatchSet]) throws -> GitHubFetchResult {
        let decoded: GraphQLResponse
        do {
            decoded = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        } catch let error as DecodingError {
            throw GitHubError.decoding(describeDecodingError(error))
        } catch {
            throw GitHubError.decoding(error.localizedDescription)
        }

        let warnings = Self.uniqueGraphQLMessages(decoded.errors)

        guard let dataDict = decoded.data else {
            if warnings.isEmpty {
                throw GitHubError.decoding("Missing data in response.")
            }
            throw GitHubError.graphQL(Self.formatGraphQLMessages(warnings))
        }

        var byId: [String: PullRequest] = [:]
        for index in sets.indices {
            guard let search = dataDict["s\(index)"], let search else { continue }
            for node in search.nodes {
                guard let pr = node?.toPullRequest() else { continue }
                byId[pr.id] = pr
            }
        }

        let pullRequests = byId.values.sorted { $0.updatedAt > $1.updatedAt }
        if pullRequests.isEmpty, !warnings.isEmpty {
            throw GitHubError.graphQL(Self.formatGraphQLMessages(warnings))
        }

        return GitHubFetchResult(
            pullRequests: pullRequests,
            warnings: warnings
        )
    }

    private static func uniqueGraphQLMessages(_ errors: [GraphQLError]?) -> [String] {
        guard let errors else { return [] }
        var seen = Set<String>()
        return errors.compactMap { error in
            let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty, seen.insert(message).inserted else { return nil }
            return message
        }
    }

    static func formatGraphQLMessages(_ messages: [String]) -> String {
        let body = messages.joined(separator: "\n\n")
        if body.contains("forbids access via a personal access token (classic)") {
            return """
            \(body)

            That organization blocks classic PATs. Create a fine-grained token at github.com/settings/tokens?type=beta with read access to pull requests for the org’s repositories, then replace your token in Settings.
            """
        }
        return body
    }

    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing field '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))."
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))."
        case .typeMismatch(let type, let context):
            return "Unexpected type for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))."
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}

struct GitHubFetchResult {
    let pullRequests: [PullRequest]
    let warnings: [String]
}

// MARK: - Decoding types

private struct GraphQLResponse: Decodable {
    let data: [String: SearchResult?]?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private struct SearchResult: Decodable {
    let nodes: [PRNode?]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decodeIfPresent([PRNode?].self, forKey: .nodes) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case nodes
    }
}

private struct PRNode: Decodable {
    let id: String?
    let number: Int?
    let title: String?
    let url: String?
    let isDraft: Bool?
    let state: String?
    let updatedAt: String?
    let repository: Repository?
    let author: Author?
    let reviewDecision: String?
    let mergeable: String?
    let mergeStateStatus: String?
    let comments: CountContainer?
    let reviews: CountContainer?
    let commits: Commits?

    struct Repository: Decodable { let nameWithOwner: String? }
    struct Author: Decodable { let login: String? }
    struct CountContainer: Decodable { let totalCount: Int? }
    struct Commits: Decodable {
        let nodes: [CommitNode]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nodes = try container.decodeIfPresent([CommitNode].self, forKey: .nodes) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case nodes
        }

        struct CommitNode: Decodable {
            let commit: Commit?
            struct Commit: Decodable {
                let statusCheckRollup: Rollup?
                struct Rollup: Decodable { let state: String? }
            }
        }
    }

    func toPullRequest() -> PullRequest? {
        guard let id, let number, let title,
              let urlString = url, let url = URL(string: urlString) else {
            return nil
        }

        let checks = CheckState(
            rawValueOrUnknown: commits?.nodes.first?.commit?.statusCheckRollup?.state
        )
        let commentCount = (comments?.totalCount ?? 0) + (reviews?.totalCount ?? 0)
        let status = PRStatus(
            lifecycle: PRLifecycle(rawValueOrOpen: state),
            isDraft: isDraft ?? false,
            reviewDecision: ReviewDecision(rawValueOrNone: reviewDecision),
            mergeState: MergeStateStatus(rawValueOrUnknown: mergeStateStatus),
            mergeable: Mergeable(rawValueOrUnknown: mergeable),
            checks: checks,
            commentCount: commentCount
        )

        return PullRequest(
            id: id,
            number: number,
            title: title,
            url: url,
            repository: repository?.nameWithOwner ?? "",
            author: author?.login ?? "",
            updatedAt: PRNode.dateFormatter.date(from: updatedAt ?? "") ?? Date.distantPast,
            status: status
        )
    }

    static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
