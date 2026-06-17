import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var localStories: [LocalStory]

    @State private var showClearConfirm = false
    @State private var storageUsed: String = ""
    @State private var autoUpdateEnabled = false
    @State private var autoWatchEnabled = false
    @State private var hasLoadedServerSettings = false

    enum ConnectionStatus { case unknown, checking, reachable, unreachable }

    @State private var connectionStatus: ConnectionStatus = .unknown

    var body: some View {
        @Bindable var appStateBindable = appState
        NavigationStack {
            Form {
                Section("Server") {
                    NavigationLink("Server & Token") {
                        ServerSettingsView()
                    }
                    LabeledContent("Status") {
                        statusLabel
                    }
                }

                if appState.isConfigured {
                    Section {
                        Toggle("Enable Auto-Update", isOn: $autoUpdateEnabled)
                            .onChange(of: autoUpdateEnabled) { _, newValue in
                                guard hasLoadedServerSettings else { return }
                                saveAutoUpdate(newValue)
                            }
                        NavigationLink("Manage Stories") {
                            StoryAutoUpdateView()
                        }
                        .disabled(!autoUpdateEnabled)
                    } header: {
                        Text("Auto-Update Stories")
                    } footer: {
                        Text("Stories are checked for new chapters when the automation runs. Settings are stored on your server.")
                            .font(.caption)
                    }

                    Section {
                        Toggle("Auto-Download New Stories", isOn: $autoWatchEnabled)
                            .onChange(of: autoWatchEnabled) { _, newValue in
                                guard hasLoadedServerSettings else { return }
                                saveAutoWatch(newValue)
                            }
                        NavigationLink("Manage Authors") {
                            AuthorsView()
                        }
                        .disabled(!autoWatchEnabled)
                    } header: {
                        Text("Watched Authors")
                    } footer: {
                        Text("Watched authors are checked for new stories on the same schedule.")
                            .font(.caption)
                    }
                }

                Section {
                    Toggle("Biometric Lock", isOn: Bindable(appState).biometricLockEnabled)
                } header: {
                    Text("Security")
                } footer: {
                    Text("Lock the app when it goes to the background.")
                        .font(.caption)
                }

                Section {
                    LabeledContent("Downloaded Stories", value: "\(localStories.count)")
                    LabeledContent("Storage Used", value: storageUsed)
                    Button("Clear All Downloads", role: .destructive) {
                        showClearConfirm = true
                    }
                } header: {
                    Text("Local Storage")
                }

                Section("History") {
                    NavigationLink("Download History") {
                        QueueView()
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                refreshStorageUsed()
                checkConnection()
                loadServerSettings()
            }
            .onChange(of: appState.isConfigured) { _, isConfigured in
                checkConnection()
                if isConfigured {
                    hasLoadedServerSettings = false
                    loadServerSettings()
                } else {
                    hasLoadedServerSettings = false
                }
            }
            .confirmationDialog(
                "Clear all downloaded stories?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Downloads", role: .destructive) {
                    clearAllDownloads()
                }
            } message: {
                Text("Story files will be removed from this device. Your library on the server is unaffected.")
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch connectionStatus {
        case .unknown, .checking:
            if appState.isConfigured {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Checking…").foregroundStyle(.secondary)
                }
            } else {
                Text("Not configured").foregroundStyle(.secondary)
            }
        case .reachable:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Reachable").foregroundStyle(.green)
            }
        case .unreachable:
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text("Unreachable").foregroundStyle(.red)
            }
        }
    }

    private func checkConnection() {
        guard appState.isConfigured else {
            connectionStatus = .unknown
            return
        }
        connectionStatus = .checking
        let client = appState.makeAPIClient()
        Task {
            do {
                try await client.testConnection()
                connectionStatus = .reachable
            } catch {
                connectionStatus = .unreachable
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func refreshStorageUsed() {
        let bytes = DownloadManager.shared.totalStorageUsed()
        if bytes < 1024 * 1024 {
            storageUsed = "\(bytes / 1024) KB"
        } else {
            storageUsed = String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    private func loadServerSettings() {
        guard appState.isConfigured else { return }
        let client = appState.makeAPIClient()
        Task {
            async let autoUpdate = try? client.fetchAutoUpdateEnabled()
            async let autoWatch = try? client.fetchAutoWatchEnabled()
            let (update, watch) = await (autoUpdate, autoWatch)
            await MainActor.run {
                if let update { autoUpdateEnabled = update }
                if let watch { autoWatchEnabled = watch }
                hasLoadedServerSettings = true
            }
        }
    }

    private func saveAutoUpdate(_ enabled: Bool) {
        let client = appState.makeAPIClient()
        Task { try? await client.setAutoUpdateEnabled(enabled) }
    }

    private func saveAutoWatch(_ enabled: Bool) {
        let client = appState.makeAPIClient()
        Task { try? await client.setAutoWatchEnabled(enabled) }
    }

    private func clearAllDownloads() {
        for story in localStories {
            try? DownloadManager.shared.deleteLocalFiles(for: story)
            modelContext.delete(story)
        }
        try? modelContext.save()
        refreshStorageUsed()
    }
}
