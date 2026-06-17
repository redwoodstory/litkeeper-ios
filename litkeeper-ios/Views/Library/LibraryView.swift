import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var localStories: [LocalStory]

    @AppStorage("showCategoryLabel") private var showCategoryLabel = false

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
                    VStack(spacing: 16) {
                        EmptyStateView(
                            icon: viewModel.errorMessage != nil ? "wifi.slash" : "books.vertical",
                            title: viewModel.errorMessage != nil ? "Server Unreachable" : (viewModel.stories.isEmpty ? "Library Empty" : "No Results"),
                            message: viewModel.errorMessage != nil
                                ? "Could not connect to your server. Check your connection or settings."
                                : (viewModel.stories.isEmpty
                                    ? "Submit a Literotica URL to download your first story."
                                    : "Try adjusting your search or filters.")
                        )
                        if viewModel.errorMessage != nil || viewModel.stories.isEmpty {
                            Button {
                                Task { await viewModel.refresh(appState: appState) }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    ScrollView {
                        if viewModel.isShowingCachedData {
                            Label("Showing last synced library — server unreachable", systemImage: "wifi.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
                                        localRating: localStories.first(where: { $0.storyID == story.id })?.rating,
                                        coverURL: coverURL(for: story),
                                        fallbackURL: DownloadManager.shared.remoteCoverURL(storyID: story.id, serverURL: appState.serverURL),
                                        token: appState.apiToken,
                                        proxyTokenId: appState.proxyTokenId,
                                        proxyToken: appState.proxyToken,
                                        showCategory: showCategoryLabel
                                    )
                                }
                                .buttonStyle(PressScaleButtonStyle())
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 12)
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.8)
                                        .delay(Double(min(index, 8)) * 0.03),
                                    value: cardsAppeared
                                )
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.refresh(appState: appState)
                        HapticManager.shared.notify(.success)
                        await syncService.syncQueueStatus(for: viewModel.stories, modelContext: modelContext)
                        cardsAppeared = false
                        Task { await syncService.syncCovers(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, proxyTokenId: appState.proxyTokenId,
                                        proxyToken: appState.proxyToken, modelContext: modelContext) }
                        Task { await syncService.syncContent(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, proxyTokenId: appState.proxyTokenId,
                                        proxyToken: appState.proxyToken, modelContext: modelContext, localStories: localStories) }
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
                    showCategoryLabel: $showCategoryLabel,
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
            viewModel.loadLocalData(localStories: localStories)
            await viewModel.refresh(appState: appState, silent: true)
            // Queue status runs async so the UI is never blocked
            Task { await syncService.syncQueueStatus(for: viewModel.stories, modelContext: modelContext) }
            Task { await syncService.syncMetadata(appState: appState, modelContext: modelContext) }
            Task { await syncService.syncHighlights(appState: appState, modelContext: modelContext) }
            // Delay heavier syncs so the grid can render before background I/O starts
            Task {
                try? await Task.sleep(for: .seconds(1))
                await syncService.syncCovers(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, proxyTokenId: appState.proxyTokenId,
                                    proxyToken: appState.proxyToken, modelContext: modelContext)
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                await syncService.syncContent(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, proxyTokenId: appState.proxyTokenId,
                                    proxyToken: appState.proxyToken, modelContext: modelContext, localStories: localStories)
            }
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
            }
            // Do not clear stories when isConfigured becomes false — it may be a transient
            // flicker during ServerSettingsView initialization and would wipe the visible library.
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refresh(appState: appState, silent: true) }
            }
        }
        .onChange(of: localStories) { _, new in
            viewModel.updateDownloadedIDs(from: new)
        }
    }

    private func coverURL(for story: Story) -> URL? {
        let local = localStories.first { $0.storyID == story.id }
        if let url = DownloadManager.shared.resolveCoverURL(for: story, localStory: local) { return url }
        guard !appState.serverURL.isEmpty else { return nil }
        let base = appState.serverURL.hasSuffix("/") ? String(appState.serverURL.dropLast()) : appState.serverURL
        return URL(string: "\(base)/api/story/\(story.id)/cover")
    }
}
