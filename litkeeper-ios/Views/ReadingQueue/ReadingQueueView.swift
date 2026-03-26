import SwiftUI
import SwiftData

struct ReadingQueueView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncService.self) private var syncService
    @Query private var localStories: [LocalStory]

    @State private var viewModel = ReadingQueueViewModel()
    @State private var selectedStory: Story?

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isConfigured {
                    EmptyStateView(
                        icon: "server.rack",
                        title: "Server Not Configured",
                        message: "Add your server URL and API token in Settings to get started."
                    )
                } else if viewModel.isLoading && viewModel.stories.isEmpty {
                    ReadingQueueSkeletonView()
                } else if viewModel.queuedStories.isEmpty && offlineQueue.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet",
                        title: "Reading Queue Empty",
                        message: "Open a story and add it to your reading queue."
                    )
                } else {
                    let stories = viewModel.queuedStories.isEmpty ? offlineQueue.map { $0.asStory } : viewModel.queuedStories
                    List {
                        ForEach(stories) { story in
                            Button {
                                selectedStory = story
                            } label: {
                                ReadingQueueRow(
                                    story: story,
                                    readingProgress: viewModel.progressByStoryID[story.id],
                                    coverURL: coverURL(for: story),
                                    token: appState.apiToken,
                                    pangolinTokenId: appState.pangolinTokenId,
                                    pangolinToken: appState.pangolinToken
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    HapticManager.shared.notify(.warning)
                                    Task { await viewModel.removeFromQueue(story: story, appState: appState) }
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.refresh(appState: appState)
                    }
                }
            }
            .navigationTitle("Reading Queue")
            .toolbar {
                if viewModel.isLoading {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProgressView()
                    }
                }
            }
            .sheet(item: $selectedStory) { story in
                StoryDetailView(story: story)
                    .environment(appState)
                    .onDisappear {
                        Task { await viewModel.refresh(appState: appState, silent: true) }
                    }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            await viewModel.refresh(appState: appState, silent: true)
        }
        .onChange(of: appState.isConfigured) { wasConfigured, isConfigured in
            if isConfigured && !wasConfigured {
                Task { await viewModel.refresh(appState: appState, silent: true) }
            } else if !isConfigured {
                viewModel.stories = []
            }
        }
    }

    private var offlineQueue: [LocalStory] {
        localStories.filter { $0.inQueue }
    }

    private func coverURL(for story: Story) -> URL? {
        let filename = story.cover ?? "\(story.filenameBase).jpg"
        let localURL = DownloadManager.shared.localCoverURL(filename: filename)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        guard !appState.serverURL.isEmpty else { return nil }
        let base = appState.serverURL.hasSuffix("/") ? String(appState.serverURL.dropLast()) : appState.serverURL
        return URL(string: "\(base)/api/cover/\(filename)")
    }
}
