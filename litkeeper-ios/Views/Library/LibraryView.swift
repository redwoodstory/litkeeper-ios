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
    @State private var cardsAppeared = false

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)
    ]

    // Derived directly from @Query so they update immediately, even while a sheet is open.
    private var localQueuedIDs: Set<Int> {
        Set(localStories.filter { $0.inQueue }.map { $0.storyID })
    }
    private var localFavoritedIDs: Set<Int> {
        Set(localStories.filter { ($0.rating ?? 0) >= 5 }.map { $0.storyID })
    }

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
                            ForEach(Array(viewModel.filteredStories.enumerated()), id: \.element.id) { index, story in
                                Button {
                                    selectedStory = story
                                } label: {
                                    StoryCard(
                                        story: story,
                                        isDownloaded: viewModel.isDownloaded(story),
                                        isInQueue: story.inQueue || localQueuedIDs.contains(story.id),
                                        isFavorited: story.rating == 5 || localFavoritedIDs.contains(story.id),
                                        coverURL: coverURL(for: story),
                                        token: appState.apiToken,
                                        pangolinTokenId: appState.pangolinTokenId,
                                        pangolinToken: appState.pangolinToken,
                                        showCategory: viewModel.showCategoryLabel
                                    )
                                }
                                .buttonStyle(PressScaleButtonStyle())
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 12)
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.8)
                                        .delay(Double(min(index, 20)) * 0.03),
                                    value: cardsAppeared
                                )
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.refresh(appState: appState)
                        HapticManager.shared.notify(.success)
                        syncService.syncQueueStatus(for: viewModel.stories, modelContext: modelContext)
                        cardsAppeared = false
                        Task { await syncService.syncCovers(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, pangolinTokenId: appState.pangolinTokenId, pangolinToken: appState.pangolinToken) }
                        Task { await syncService.syncContent(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, pangolinTokenId: appState.pangolinTokenId, pangolinToken: appState.pangolinToken, modelContext: modelContext, localStories: localStories) }
                        Task { await syncService.syncHighlights(appState: appState, modelContext: modelContext) }
                        try? await Task.sleep(for: .milliseconds(50))
                        cardsAppeared = true
                    }
                    .onAppear {
                        guard !cardsAppeared else { return }
                        cardsAppeared = true
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
                        Task { await viewModel.refresh(appState: appState, silent: true) }
                    }
            }
            .sheet(isPresented: $showFilterSort) {
                FilterSortView(
                    selectedCategory: $viewModel.selectedCategory,
                    sortBy: $viewModel.sortBy,
                    sortAscending: $viewModel.sortAscending,
                    showQueueOnly: $viewModel.showQueueOnly,
                    showCategoryLabel: $viewModel.showCategoryLabel,
                    categories: viewModel.availableCategories
                )
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
            viewModel.updateDownloadedIDs(from: localStories)
            await viewModel.refresh(appState: appState, silent: true)
            syncService.syncQueueStatus(for: viewModel.stories, modelContext: modelContext)
            Task { await syncService.syncMetadata(appState: appState, modelContext: modelContext) }
            Task { await syncService.syncCovers(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, pangolinTokenId: appState.pangolinTokenId, pangolinToken: appState.pangolinToken) }
            Task { await syncService.syncContent(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, pangolinTokenId: appState.pangolinTokenId, pangolinToken: appState.pangolinToken, modelContext: modelContext, localStories: localStories) }
            Task { await syncService.syncHighlights(appState: appState, modelContext: modelContext) }
        }
        .task {
            // Periodic library + metadata sync — fires every 5 minutes while the view is active
            repeat {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await viewModel.refresh(appState: appState, silent: true)
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
        let localURL = DownloadManager.shared.localCoverURL(filename: filename)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        guard !appState.serverURL.isEmpty else { return nil }
        let base = appState.serverURL.hasSuffix("/") ? String(appState.serverURL.dropLast()) : appState.serverURL
        return URL(string: "\(base)/api/cover/\(filename)")
    }
}
