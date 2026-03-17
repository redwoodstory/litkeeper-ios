import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext
    @Query private var localStories: [LocalStory]

    @State private var viewModel = LibraryViewModel()
    @State private var selectedStory: Story? = nil
    @State private var showAddStory = false
    @State private var showFilterSort = false

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.stories.isEmpty {
                    LibrarySkeletonView()
                } else if !appState.isConfigured {
                    EmptyStateView(
                        icon: "server.rack",
                        title: "Server Not Configured",
                        message: "Add your server URL and API token in Settings to get started."
                    )
                } else if viewModel.filteredStories.isEmpty {
                    EmptyStateView(
                        icon: "books.vertical",
                        title: viewModel.stories.isEmpty ? "Library Empty" : "No Results",
                        message: viewModel.stories.isEmpty
                            ? "Submit a Literotica URL to download your first story."
                            : "Try adjusting your search or filters."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.filteredStories) { story in
                                Button {
                                    selectedStory = story
                                } label: {
                                    StoryCard(
                                        story: story,
                                        isDownloaded: viewModel.isDownloaded(story),
                                        coverURL: coverURL(for: story),
                                        token: appState.apiToken
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.refresh(appState: appState)
                        Task { await syncService.syncCovers(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken) }
                        Task { await syncService.syncContent(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, modelContext: modelContext, localStories: localStories) }
                    }
                }
            }
            .navigationTitle("LitKeeper")
            .searchable(text: $viewModel.searchText, prompt: "Search title or author")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showAddStory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        showFilterSort = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddStory) {
                AddStoryView()
                    .environment(appState)
                    .onDisappear {
                        Task { await viewModel.refresh(appState: appState) }
                    }
            }
            .sheet(isPresented: $showFilterSort) {
                FilterSortView(
                    selectedCategory: $viewModel.selectedCategory,
                    sortBy: $viewModel.sortBy,
                    sortAscending: $viewModel.sortAscending,
                    showQueueOnly: $viewModel.showQueueOnly,
                    categories: viewModel.availableCategories
                )
            }
            .sheet(item: $selectedStory) { story in
                StoryDetailView(story: story)
                    .environment(appState)
                    .onDisappear {
                        Task { await viewModel.refresh(appState: appState) }
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
            viewModel.updateDownloadedIDs(from: localStories)
            await viewModel.refresh(appState: appState)
            Task { await syncService.syncMetadata(appState: appState, modelContext: modelContext) }
            Task { await syncService.syncCovers(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken) }
            Task { await syncService.syncContent(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, modelContext: modelContext, localStories: localStories) }
        }
        .task {
            // Periodic library + metadata sync — fires every 5 minutes while the view is active
            repeat {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await viewModel.refresh(appState: appState)
                await syncService.syncMetadata(appState: appState, modelContext: modelContext)
            } while !Task.isCancelled
        }
        .onChange(of: appState.isConfigured) { wasConfigured, isConfigured in
            if isConfigured && !wasConfigured {
                Task { await viewModel.refresh(appState: appState) }
            } else if !isConfigured {
                viewModel.stories = []
            }
        }
        .onChange(of: localStories) { _, new in
            viewModel.updateDownloadedIDs(from: new)
        }
    }

    private func coverURL(for story: Story) -> URL? {
        let filename = story.cover ?? "\(story.filenameBase).jpg"
        if syncService.localCoverFilenames.contains(filename) {
            return DownloadManager.shared.localCoverURL(filename: filename)
        }
        guard !appState.serverURL.isEmpty else { return nil }
        let base = appState.serverURL.hasSuffix("/") ? String(appState.serverURL.dropLast()) : appState.serverURL
        return URL(string: "\(base)/api/cover/\(filename)")
    }
}
