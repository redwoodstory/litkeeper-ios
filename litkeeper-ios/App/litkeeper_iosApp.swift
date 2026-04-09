import SwiftUI
import SwiftData

@main
struct LitKeeperApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()
    @State private var syncService = SyncService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(syncService)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        appState.lockIfEnabled()
                    case .active:
                        if appState.isLocked {
                            Task { await appState.unlock() }
                        }
                    default:
                        break
                    }
                }
        }
        .modelContainer(for: [LocalStory.self, LocalHighlight.self, PendingOperation.self])
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(0)

            ReadingQueueView()
                .tabItem { Label("Queue", systemImage: "list.bullet") }
                .tag(1)

            QueueView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(2)

            HighlightsView()
                .tabItem { Label("Quotes", systemImage: "quote.bubble") }
                .tag(3)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(4)
        }
        .onChange(of: selectedTab) {
            HapticManager.shared.selectionChanged()
        }
        .fullScreenCover(isPresented: Binding(
            get: { appState.isLocked },
            set: { _ in }
        )) {
            LockView()
                .environment(appState)
        }
        .task {
            DownloadManager.shared.migrateToIDPrefixedFiles(modelContext: modelContext)
        }
    }
}
