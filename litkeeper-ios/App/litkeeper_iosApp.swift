import SwiftUI
import SwiftData

@main
struct LitKeeperApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
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

            DownloadsView()
                .tabItem { Label("Downloaded", systemImage: "arrow.down.circle") }

            QueueView()
                .tabItem { Label("Queue", systemImage: "clock") }
        }
        .fullScreenCover(isPresented: Binding(
            get: { appState.isLocked },
            set: { _ in }
        )) {
            LockView()
                .environment(appState)
        }
    }
}
