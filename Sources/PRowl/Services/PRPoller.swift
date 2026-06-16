import Foundation
import Combine

/// Core engine: holds settings, polls GitHub on a timer, publishes the PR list
/// for the UI, diffs successive snapshots and fires notifications on changes.
@MainActor
final class PRPoller: ObservableObject {
    @Published private(set) var pullRequests: [PullRequest] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastWarning: String?
    @Published private(set) var lastUpdated: Date?
    @Published var hasToken: Bool = GitHubAuth.isConfigured

    /// How GitHub credentials are obtained. Persisted.
    @Published var authMethod: AuthMethod {
        didSet {
            GitHubAuth.method = authMethod
            syncCredentialState()
            resetSnapshot()
            Task { await refresh() }
        }
    }

    /// Poll interval in seconds. Persisted.
    @Published var pollInterval: Double {
        didSet {
            UserDefaults.standard.set(pollInterval, forKey: Keys.pollInterval)
            if timer != nil { restartTimer() }
        }
    }

    /// Which PR sets to watch. Persisted.
    @Published var watchSets: Set<WatchSet> {
        didSet {
            let raw = watchSets.map { $0.rawValue }
            UserDefaults.standard.set(raw, forKey: Keys.watchSets)
        }
    }

    /// Which event types should fire a notification. Persisted.
    @Published var enabledEvents: Set<NotificationEvent> {
        didSet {
            let raw = enabledEvents.map { $0.rawValue }
            UserDefaults.standard.set(raw, forKey: Keys.enabledEvents)
        }
    }

    /// GraphQL API endpoint (override for GitHub Enterprise). Persisted.
    @Published var apiURL: String {
        didSet {
            UserDefaults.standard.set(apiURL, forKey: Keys.apiURL)
        }
    }

    private var timer: Timer?
    private var previousStatuses: [String: PRStatus] = [:]
    private var didSeed = false

    private enum Keys {
        static let pollInterval = "pollInterval"
        static let watchSets = "watchSets"
        static let enabledEvents = "enabledEvents"
        static let apiURL = "apiURL"
    }

    init() {
        let storedInterval = UserDefaults.standard.double(forKey: Keys.pollInterval)
        self.pollInterval = storedInterval > 0 ? storedInterval : 60
        self.authMethod = GitHubAuth.method

        if let raw = UserDefaults.standard.array(forKey: Keys.watchSets) as? [String] {
            let sets = raw.compactMap { WatchSet(rawValue: $0) }
            self.watchSets = sets.isEmpty ? [.authored] : Set(sets)
        } else {
            self.watchSets = [.authored]
        }

        if let raw = UserDefaults.standard.array(forKey: Keys.enabledEvents) as? [String] {
            self.enabledEvents = Set(raw.compactMap { NotificationEvent(rawValue: $0) })
        } else {
            self.enabledEvents = NotificationEvent.defaultEnabled
        }

        let storedURL = UserDefaults.standard.string(forKey: Keys.apiURL)
        self.apiURL = (storedURL?.isEmpty == false ? storedURL! : GitHubClient.defaultEndpoint)
    }

    // MARK: - Lifecycle

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        hasToken = GitHubAuth.isConfigured
        NotificationManager.shared.ensureAuthorized { _ in }
        Task { await refresh() }
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = max(15, pollInterval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func syncCredentialState() {
        hasToken = GitHubAuth.isConfigured
    }

    func refreshGitHubCLIStatus() {
        syncCredentialState()
    }

    // MARK: - Token management

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(token: trimmed)
        syncCredentialState()
        resetSnapshot()
        Task { await refresh() }
        restartTimer()
    }

    func clearToken() {
        KeychainStore.delete()
        syncCredentialState()
        pullRequests = []
        resetSnapshot()
        lastError = nil
        NotificationManager.shared.promptIfMissingTokenAfterTokenRemoved()
    }

    private func resetSnapshot() {
        previousStatuses = [:]
        didSeed = false
    }

    // MARK: - Polling

    func refresh() async {
        guard GitHubAuth.isConfigured else {
            syncCredentialState()
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let sets = Array(watchSets)
            let client = GitHubClient(apiURL: apiURL)
            let result = try await client.fetchOpenPullRequests(sets: sets)
            detectChanges(newPRs: result.pullRequests)
            pullRequests = result.pullRequests
            lastUpdated = Date()
            lastError = nil
            lastWarning = result.warnings.isEmpty
                ? nil
                : GitHubClient.formatGraphQLMessages(result.warnings)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastWarning = nil
        }
    }

    // MARK: - Diffing & notifications

    private func detectChanges(newPRs: [PullRequest]) {
        let newStatuses = Dictionary(uniqueKeysWithValues: newPRs.map { ($0.id, $0.status) })

        // First successful fetch seeds the snapshot silently to avoid alert spam.
        guard didSeed else {
            previousStatuses = newStatuses
            didSeed = true
            return
        }

        for pr in newPRs {
            guard let old = previousStatuses[pr.id] else { continue } // newly-seen PR: no alert
            let new = pr.status
            guard old != new else { continue }

            for event in transitions(old: old, new: new) where enabledEvents.contains(event) {
                NotificationManager.shared.notify(
                    title: "\(pr.repository) #\(pr.number)",
                    body: "\(event.label)\n\(pr.title)",
                    prURL: pr.url
                )
            }
        }

        previousStatuses = newStatuses
    }

    /// Determines which notification events a status transition represents.
    private func transitions(old: PRStatus, new: PRStatus) -> [NotificationEvent] {
        var events: [NotificationEvent] = []

        if old.lifecycle != new.lifecycle {
            switch new.lifecycle {
            case .merged: return [.merged]
            case .closed: return [.closed]
            case .open: break
            }
        }

        if new.commentCount > old.commentCount {
            events.append(.newComment)
        }

        if old.reviewDecision != new.reviewDecision {
            switch new.reviewDecision {
            case .approved: events.append(.approved)
            case .changesRequested: events.append(.changesRequested)
            case .reviewRequired: events.append(.reviewRequired)
            case .none: break
            }
        }

        if !old.hasConflict && new.hasConflict {
            events.append(.conflict)
        }

        if old.checks != new.checks {
            switch new.checks {
            case .failure, .error: events.append(.ciFailed)
            case .success where old.checks == .pending || old.checks == .expected:
                events.append(.ciPassed)
            default: break
            }
        }

        if !old.isReadyToMerge && new.isReadyToMerge {
            events.append(.readyToMerge)
        }

        if old.isDraft && !new.isDraft {
            events.append(.readyForReview)
        }

        return events
    }
}
