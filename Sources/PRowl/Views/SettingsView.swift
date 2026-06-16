import SwiftUI

struct SettingsView: View {
    @ObservedObject var poller: PRPoller
    @Binding var isPresented: Bool

    @State private var tokenInput: String = ""
    @State private var apiURLInput: String = ""
    @State private var savedConfirmation = false
    @State private var notificationsDenied = false
    @State private var alertsDisabled = false
    @State private var testNotificationResult: String?
    @State private var launchAtLogin = false
    @State private var launchAtLoginMessage: String?
    @State private var excludeFromBartender = false
    @State private var bartenderMessage: String?

    private let intervalOptions: [(label: String, seconds: Double)] = [
        ("30 seconds", 30),
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300),
        ("10 minutes", 600)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProwlScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    connectionSection
                        .prowlSectionSeparator()
                    watchSection
                        .prowlSectionSeparator()
                    eventsSection
                        .prowlSectionSeparator()
                    intervalSection
                        .prowlSectionSeparator()
                    generalSection
                }
                .padding(.bottom, 8)
            }
            .frame(minHeight: 400, maxHeight: 480)

            HStack {
                Spacer()
                Button("Done") {
                    applyConnection()
                    isPresented = false
                }
                .prowlGlassProminentButton()
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .onAppear {
            apiURLInput = poller.apiURL
            refreshNotificationStatus()
            refreshLaunchAtLoginState()
            refreshBartenderState()
        }
    }

    // MARK: - Connection / API

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("API & authentication", systemImage: "network")
                .font(.headline)

            Text("GraphQL API endpoint")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(GitHubClient.defaultEndpoint, text: $apiURLInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            Text("Leave as-is for github.com. For GitHub Enterprise use https://<host>/api/graphql.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Credentials")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Picker("Credentials", selection: $poller.authMethod) {
                ForEach(AuthMethod.allCases) { method in
                    Text(method.label).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if poller.authMethod == .githubCLI {
                githubCLISection
            } else {
                tokenSection
            }
        }
    }

    private var githubCLISection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: poller.hasToken ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(poller.hasToken ? .green : .orange)
                Text(GitHubCLIAuth.statusSummary())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Refresh CLI status") {
                poller.refreshGitHubCLIStatus()
                Task { await poller.refresh() }
            }
            .controlSize(.small)
            Text("Uses your existing `gh auth login` session (OAuth). Good for orgs that block classic PATs. Install from cli.github.com if needed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if poller.hasToken {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Token saved in Keychain")
                        .font(.caption)
                    Spacer()
                    Button("Remove") {
                        poller.clearToken()
                        tokenInput = ""
                    }
                    .controlSize(.small)
                }
            }

            SecureField("Paste Personal Access Token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(poller.hasToken ? "Replace Token" : "Save Token") {
                    poller.saveToken(tokenInput)
                    tokenInput = ""
                    flashSaved()
                }
                .prowlGlassProminentButton()
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if savedConfirmation {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text("Use a fine-grained token (recommended) or a classic token with `repo` and `read:org`. Some organizations block classic PATs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func applyConnection() {
        let trimmed = apiURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = trimmed.isEmpty ? GitHubClient.defaultEndpoint : trimmed
        if newValue != poller.apiURL {
            poller.apiURL = newValue
            Task { await poller.refresh() }
        }
    }

    private func flashSaved() {
        savedConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            savedConfirmation = false
        }
    }

    private func refreshNotificationStatus() {
        NotificationManager.shared.refreshAuthorizationStatus { _ in
            notificationsDenied = NotificationManager.shared.isDenied
            alertsDisabled = NotificationManager.shared.alertsDisabled
        }
    }

    // MARK: - Watch sets

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Which PRs to watch", systemImage: "eye")
                .font(.headline)
            ForEach(WatchSet.allCases) { set in
                Toggle(set.label, isOn: watchBinding(for: set))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private func watchBinding(for set: WatchSet) -> Binding<Bool> {
        Binding(
            get: { poller.watchSets.contains(set) },
            set: { isOn in
                var sets = poller.watchSets
                if isOn {
                    sets.insert(set)
                } else {
                    sets.remove(set)
                    if sets.isEmpty { sets.insert(.authored) }
                }
                poller.watchSets = sets
                Task { await poller.refresh() }
            }
        )
    }

    // MARK: - Notification events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Notify me about", systemImage: "bell.badge")
                    .font(.headline)
                Spacer()
                Button(allEventsEnabled ? "None" : "All") {
                    poller.enabledEvents = allEventsEnabled ? [] : Set(NotificationEvent.allCases)
                }
                .controlSize(.small)
            }
            ForEach(NotificationEvent.allCases) { event in
                Toggle(isOn: eventBinding(for: event)) {
                    Label(event.label, systemImage: event.systemImage)
                }
                .toggleStyle(.checkbox)
            }

            Text("Status: \(NotificationManager.shared.statusSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if NotificationManager.shared.needsUserAuthorization {
                Button("Enable Notifications") {
                    testNotificationResult = nil
                    NotificationManager.shared.requestAuthorizationFromUser { granted in
                        refreshNotificationStatus()
                        testNotificationResult = granted
                            ? "Permission granted. Try Send test notification."
                            : "Permission not granted. Use Open Notification Settings."
                    }
                }
                .prowlGlassProminentButton()
                .controlSize(.small)
            }

            if notificationsDenied || alertsDisabled {
                Button("Open Notification Settings") {
                    NotificationManager.shared.openSystemNotificationSettings()
                }
                .controlSize(.small)
            }

            if notificationsDenied {
                Text("Notifications are off for PRowl. Enable them in System Settings → Notifications → PRowl.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if alertsDisabled {
                Text("PRowl is allowed to notify, but banners are off. Turn on Alerts in System Settings → Notifications → PRowl.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Send test notification") {
                testNotificationResult = nil
                if NotificationManager.shared.needsUserAuthorization {
                    NotificationManager.shared.requestAuthorizationFromUser { granted in
                        refreshNotificationStatus()
                        guard granted else {
                            testNotificationResult = "Enable notifications first."
                            return
                        }
                        NotificationManager.shared.sendTestNotification { ok in
                            let status = NotificationManager.shared.statusSummary
                            testNotificationResult = ok
                                ? "Sent (\(status)). Check the top-right of your screen."
                                : "Blocked (\(status)). Use Open Notification Settings below."
                            refreshNotificationStatus()
                        }
                    }
                } else {
                    NotificationManager.shared.sendTestNotification { ok in
                        let status = NotificationManager.shared.statusSummary
                        testNotificationResult = ok
                            ? "Sent (\(status)). Check the top-right of your screen."
                            : "Blocked (\(status)). Use Open Notification Settings below."
                        refreshNotificationStatus()
                    }
                }
            }
            .controlSize(.small)
            .padding(.top, 4)

            if let testNotificationResult {
                Text(testNotificationResult)
                    .font(.caption2)
                    .foregroundStyle(testNotificationResult.contains("Sent") ? .green : .orange)
            }
        }
    }

    private var allEventsEnabled: Bool {
        poller.enabledEvents.count == NotificationEvent.allCases.count
    }

    private func eventBinding(for event: NotificationEvent) -> Binding<Bool> {
        Binding(
            get: { poller.enabledEvents.contains(event) },
            set: { isOn in
                var events = poller.enabledEvents
                if isOn { events.insert(event) } else { events.remove(event) }
                poller.enabledEvents = events
            }
        )
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("General", systemImage: "slider.horizontal.3")
                .font(.headline)

            Toggle("Open PRowl at login", isOn: launchAtLoginBinding)

            if let launchAtLoginMessage {
                Text(launchAtLoginMessage)
                    .font(.caption)
                    .foregroundStyle(launchAtLoginMessage.contains("Approve") ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if LaunchAtLoginManager.status == .requiresApproval {
                Button("Open Login Items Settings") {
                    LaunchAtLoginManager.openSystemSettings()
                }
                .controlSize(.small)
            }

            if BartenderIntegration.isInstalled {
                Divider().opacity(0.25).padding(.vertical, 4)

                Toggle("Keep icon visible in menu bar (Bartender)", isOn: excludeFromBartenderBinding)

                Text("Tells Bartender not to hide PRowl. You may need to quit and reopen Bartender once.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let bartenderMessage {
                    Text(bartenderMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Open Bartender") {
                    BartenderIntegration.openBartender()
                }
                .controlSize(.small)
            }
        }
    }

    private var excludeFromBartenderBinding: Binding<Bool> {
        Binding(
            get: { excludeFromBartender },
            set: { newValue in
                do {
                    try BartenderIntegration.setExcludedFromManagement(newValue)
                    refreshBartenderState()
                    bartenderMessage = newValue
                        ? "PRowl excluded from Bartender. Quit and reopen Bartender if the icon is still hidden."
                        : "PRowl will be managed by Bartender again."
                } catch {
                    refreshBartenderState()
                    bartenderMessage = error.localizedDescription
                }
            }
        )
    }

    private func refreshBartenderState() {
        excludeFromBartender = BartenderIntegration.isExcludedFromManagement
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLoginManager.setEnabled(newValue)
                    refreshLaunchAtLoginState()
                } catch {
                    refreshLaunchAtLoginState()
                    launchAtLoginMessage = error.localizedDescription
                }
            }
        )
    }

    private func refreshLaunchAtLoginState() {
        launchAtLogin = LaunchAtLoginManager.isEnabled
        launchAtLoginMessage = LaunchAtLoginManager.statusMessage
    }

    // MARK: - Interval

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Check every", systemImage: "clock")
                .font(.headline)
            Picker("Check every", selection: $poller.pollInterval) {
                ForEach(intervalOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}
