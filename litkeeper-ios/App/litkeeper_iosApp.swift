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
        .modelContainer(for: LocalStory.self)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            ReadingQueueView()
                .tabItem { Label("Reading Queue", systemImage: "list.bullet") }

            QueueView()
                .tabItem { Label("History", systemImage: "clock") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { WebViewPrewarmer.shared.prewarm() }
        .fullScreenCover(isPresented: Binding(
            get: { appState.isLocked },
            set: { _ in }
        )) {
            LockView()
                .environment(appState)
        }
    }
}
