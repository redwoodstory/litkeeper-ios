import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var localStories: [LocalStory]

    @State private var showClearConfirm = false
    @State private var storageUsed: String = ""

    var body: some View {
        @Bindable var appStateBindable = appState
        NavigationStack {
            Form {
                Section("Server") {
                    NavigationLink("Server & Token") {
                        ServerSettingsView()
                    }
                    LabeledContent("Status") {
                        Text(appState.isConfigured ? "Connected" : "Not configured")
                            .foregroundStyle(appState.isConfigured ? .green : .secondary)
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

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .onAppear { refreshStorageUsed() }
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

    private func clearAllDownloads() {
        for story in localStories {
            try? DownloadManager.shared.deleteLocalFiles(for: story)
            modelContext.delete(story)
        }
        try? modelContext.save()
        refreshStorageUsed()
    }
}
