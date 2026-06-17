import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var poller: PRPoller
    @ObservedObject var uiState: PopoverUIState

    var body: some View {
        panelContent
            .prowlGlassPanel()
            .frame(width: 420)
            .background(TransparentWindowConfigurator())
            .onAppear {
                NotificationManager.shared.prepareOnUserInteraction()
            }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            if uiState.showingSettings {
                SettingsView(poller: poller, isPresented: $uiState.showingSettings)
            } else {
                if let warning = poller.lastWarning {
                    warningBanner(warning)
                        .padding(.bottom, 10)
                }
                content
                footer
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(uiState.showingSettings ? "Configuration" : "PRowl")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    .linearGradient(colors: [.primary, .teal],
                                    startPoint: .leading, endPoint: .trailing)
                )
            Spacer()
            if poller.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !poller.hasToken {
            emptyState(
                symbol: poller.authMethod == .githubCLI ? "terminal" : "key.fill",
                title: poller.authMethod == .githubCLI ? "Sign in with GitHub CLI" : "Add a GitHub token",
                subtitle: missingCredentialSubtitle,
                actionTitle: "Open Settings",
                action: { uiState.showingSettings = true }
            )
        } else if let error = poller.lastError, poller.pullRequests.isEmpty {
            emptyState(
                symbol: "exclamationmark.triangle",
                title: "Couldn't load PRs",
                subtitle: error
            )
        } else if poller.pullRequests.isEmpty {
            emptyState(
                symbol: "checkmark.circle",
                title: "No open PRs",
                subtitle: poller.isLoading ? "Loading..." : "You're all caught up."
            )
        } else {
            ProwlScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(poller.pullRequests) { pr in
                        PRRow(pr: pr)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 400)
        }
    }

    private var missingCredentialSubtitle: String {
        if poller.authMethod == .githubCLI {
            return GitHubAuth.configurationHint
        }
        if NotificationManager.shared.isDenied || NotificationManager.shared.alertsDisabled {
            return "Open Settings to paste a token. Also enable notifications for PRowl in System Settings → Notifications."
        }
        return "Open Settings to paste a Personal Access Token and start watching your PRs."
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(10)
        .prowlGlassRow(cornerRadius: 10)
    }

    private func emptyState(
        symbol: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.teal)
                .frame(width: 68, height: 68)
                .prowlGlassCapsule()
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .prowlGlassProminentButton()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let updated = poller.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { Task { await poller.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .prowlGlassButton()
                    .help("Refresh now")
                    .disabled(!poller.hasToken)

                    Button { uiState.showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .prowlGlassButton()
                    .help("Settings")

                    Button { NSApplication.shared.terminate(nil) } label: {
                        Image(systemName: "power")
                    }
                    .prowlGlassButton()
                    .help("Quit PRowl")
                }
            }
        }
    }
}

// MARK: - PR Row

private struct PRRow: View {
    let pr: PullRequest

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: pr.statusSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 30, height: 30)
                    .prowlGlassCapsule()
                VStack(alignment: .leading, spacing: 4) {
                    Text(pr.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(pr.repository) #\(pr.number)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(pr.statusLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(iconColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .prowlGlassCapsule()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .prowlGlassRow(cornerRadius: 12)
    }

    private var iconColor: Color {
        switch pr.status.lifecycle {
        case .merged: return .purple
        case .closed: return .red
        case .open: break
        }
        if pr.status.isDraft { return .secondary }
        if pr.status.hasConflict { return .red }
        if pr.status.checks == .failure || pr.status.checks == .error { return .red }
        if pr.status.checks == .pending || pr.status.checks == .expected { return .orange }
        switch pr.status.reviewDecision {
        case .changesRequested: return .red
        case .approved: return pr.status.isReadyToMerge ? .green : .blue
        default: return pr.status.isReadyToMerge ? .green : .secondary
        }
    }
}
