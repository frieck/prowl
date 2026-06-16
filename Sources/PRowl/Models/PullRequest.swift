import Foundation

/// CI check rollup state for the latest commit of a PR.
enum CheckState: String, Codable, Equatable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case pending = "PENDING"
    case error = "ERROR"
    case expected = "EXPECTED"
    case unknown = "UNKNOWN"

    init(rawValueOrUnknown raw: String?) {
        guard let raw, let value = CheckState(rawValue: raw) else {
            self = .unknown
            return
        }
        self = value
    }
}

/// Review decision for a PR.
enum ReviewDecision: String, Codable, Equatable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
    case none = "NONE"

    init(rawValueOrNone raw: String?) {
        guard let raw, let value = ReviewDecision(rawValue: raw) else {
            self = .none
            return
        }
        self = value
    }
}

/// High-level lifecycle state of the PR.
enum PRLifecycle: String, Codable, Equatable {
    case open = "OPEN"
    case merged = "MERGED"
    case closed = "CLOSED"

    init(rawValueOrOpen raw: String?) {
        guard let raw, let value = PRLifecycle(rawValue: raw) else {
            self = .open
            return
        }
        self = value
    }
}

/// Whether the PR can be merged without conflicts.
enum Mergeable: String, Codable, Equatable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"

    init(rawValueOrUnknown raw: String?) {
        guard let raw, let value = Mergeable(rawValue: raw) else {
            self = .unknown
            return
        }
        self = value
    }
}

/// Mergeability "merge state" from GitHub (requires merge-info preview).
/// CLEAN means ready to merge; BLOCKED/BEHIND/DIRTY/UNSTABLE indicate problems.
enum MergeStateStatus: String, Codable, Equatable {
    case clean = "CLEAN"
    case blocked = "BLOCKED"
    case behind = "BEHIND"
    case dirty = "DIRTY"
    case unstable = "UNSTABLE"
    case hasHooks = "HAS_HOOKS"
    case draft = "DRAFT"
    case unknown = "UNKNOWN"

    init(rawValueOrUnknown raw: String?) {
        guard let raw, let value = MergeStateStatus(rawValue: raw) else {
            self = .unknown
            return
        }
        self = value
    }
}

/// A composite, comparable snapshot of a PR's status. Used both to render an
/// icon in the menu and to diff between polls to detect meaningful changes.
struct PRStatus: Equatable, Codable {
    var lifecycle: PRLifecycle
    var isDraft: Bool
    var reviewDecision: ReviewDecision
    var mergeState: MergeStateStatus
    var mergeable: Mergeable
    var checks: CheckState
    /// Total of conversation comments + reviews; used to detect new comments.
    var commentCount: Int

    /// True when the PR is open, not draft and in a clean mergeable state.
    var isReadyToMerge: Bool {
        lifecycle == .open && !isDraft && mergeState == .clean
    }

    var hasConflict: Bool {
        lifecycle == .open && (mergeable == .conflicting || mergeState == .dirty)
    }
}

struct PullRequest: Identifiable, Equatable {
    /// GraphQL node id, stable across polls.
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let author: String
    let updatedAt: Date
    let status: PRStatus

    /// SF Symbol name + human label describing the most important status.
    var statusSymbol: String {
        switch status.lifecycle {
        case .merged: return "checkmark.seal.fill"
        case .closed: return "xmark.circle.fill"
        case .open: break
        }
        if status.isDraft { return "pencil.circle" }
        if status.hasConflict { return "exclamationmark.triangle.fill" }
        switch status.checks {
        case .failure, .error: return "exclamationmark.octagon.fill"
        case .pending, .expected: return "clock.fill"
        default: break
        }
        switch status.reviewDecision {
        case .changesRequested: return "arrow.uturn.left.circle.fill"
        case .approved:
            return status.isReadyToMerge ? "arrow.triangle.merge" : "checkmark.circle.fill"
        case .reviewRequired, .none:
            return status.isReadyToMerge ? "arrow.triangle.merge" : "circle"
        }
    }

    var statusLabel: String {
        switch status.lifecycle {
        case .merged: return "Merged"
        case .closed: return "Closed"
        case .open: break
        }
        if status.isDraft { return "Draft" }
        var parts: [String] = []
        if status.hasConflict { parts.append("Merge conflict") }
        switch status.reviewDecision {
        case .approved: parts.append("Approved")
        case .changesRequested: parts.append("Changes requested")
        case .reviewRequired: parts.append("Review required")
        case .none: break
        }
        switch status.checks {
        case .failure, .error: parts.append("CI failed")
        case .pending, .expected: parts.append("CI running")
        case .success: parts.append("CI passed")
        case .unknown: break
        }
        if status.isReadyToMerge { parts.append("Ready to merge") }
        return parts.isEmpty ? "Open" : parts.joined(separator: " | ")
    }
}

/// The notification event types a user can opt in/out of in the configuration
/// screen. `defaultEnabled` defines the out-of-the-box selection.
enum NotificationEvent: String, CaseIterable, Identifiable, Codable {
    case newComment
    case approved
    case changesRequested
    case reviewRequired
    case conflict
    case ciFailed
    case ciPassed
    case readyToMerge
    case readyForReview
    case merged
    case closed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newComment: return "New comment"
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        case .reviewRequired: return "Review required"
        case .conflict: return "Merge conflict"
        case .ciFailed: return "CI failed"
        case .ciPassed: return "CI passed"
        case .readyToMerge: return "Ready to merge"
        case .readyForReview: return "Marked ready for review"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }

    var systemImage: String {
        switch self {
        case .newComment: return "bubble.left"
        case .approved: return "checkmark.circle"
        case .changesRequested: return "arrow.uturn.left.circle"
        case .reviewRequired: return "eye.circle"
        case .conflict: return "exclamationmark.triangle"
        case .ciFailed: return "xmark.octagon"
        case .ciPassed: return "checkmark.seal"
        case .readyToMerge: return "arrow.triangle.merge"
        case .readyForReview: return "pencil.circle"
        case .merged: return "checkmark.seal.fill"
        case .closed: return "xmark.circle"
        }
    }

    static var defaultEnabled: Set<NotificationEvent> {
        Set(allCases)
    }
}
