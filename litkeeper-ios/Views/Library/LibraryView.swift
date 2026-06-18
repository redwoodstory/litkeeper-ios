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

    // Derived from @Query — recomputed only when localStories changes, not on every cell render.
    @State private var localByID: [Int: LocalStory] = [:]
    @State private var localQueuedIDs: Set<Int> = []
    @State private var localFavoritedIDs: Set<Int> = []

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            libraryContent
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
            let taskStart = Date()
            print("[LK-STARTUP] LibraryView.task start")
            updateLocalDerivedData(from: localStories)
            viewModel.updateDownloadedIDs(from: localStories)
            viewModel.loadLocalData(localStories: localStories)
            print("[LK-STARTUP] loadLocalData done: \(String(format: "%.1f", Date().timeIntervalSince(taskStart)*1000))ms (stories: \(viewModel.stories.count))")
            await viewModel.refresh(appState: appState, silent: true)
            print("[LK-STARTUP] refresh done: \(String(format: "%.1f", Date().timeIntervalSince(taskStart)*1000))ms")
            let container = modelContext.container
            let serverURL = appState.serverURL
            let token = appState.apiToken
            let proxyTokenId = appState.proxyTokenId
            let proxyToken = appState.proxyToken
            let stories = viewModel.stories
            let serverReachable = !viewModel.isShowingCachedData
            Task {
                try? await Task.sleep(for: .seconds(5))
                await syncService.syncQueueStatus(for: stories, modelContainer: container)
            }
            guard serverReachable else { return }
            Task {
                try? await Task.sleep(for: .seconds(5))
                await syncService.syncMetadata(serverURL: serverURL, token: token,
                    proxyTokenId: proxyTokenId, proxyToken: proxyToken, modelContainer: container)
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                await syncService.syncHighlights(serverURL: serverURL, token: token,
                    proxyTokenId: proxyTokenId, proxyToken: proxyToken, modelContainer: container)
            }
            Task {
                try? await Task.sleep(for: .seconds(6))
                await syncService.syncCovers(for: stories, serverURL: serverURL, token: token,
                    proxyTokenId: proxyTokenId, proxyToken: proxyToken, modelContainer: container)
            }
            Task {
                try? await Task.sleep(for: .seconds(7))
                await syncService.syncContent(for: stories, serverURL: serverURL, token: token,
                    proxyTokenId: proxyTokenId, proxyToken: proxyToken, modelContainer: container)
            }
        }
        .task {
            // Periodic library + metadata sync — fires every 5 minutes while the view is active
            repeat {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await viewModel.refresh(appState: appState, silent: true)
                let container = modelContext.container
                let serverURL = appState.serverURL
                let token = appState.apiToken
                let proxyTokenId = appState.proxyTokenId
                let proxyToken = appState.proxyToken
                await syncService.syncMetadata(serverURL: serverURL, token: token,
                    proxyTokenId: proxyTokenId, proxyToken: proxyToken, modelContainer: container)
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
            updateLocalDerivedData(from: new)
            viewModel.updateDownloadedIDs(from: new)
        }
    }

    private func updateLocalDerivedData(from stories: [LocalStory]) {
        localByID = Dictionary(uniqueKeysWithValues: stories.map { ($0.storyID, $0) })
        localQueuedIDs = Set(stories.filter { $0.inQueue }.map { $0.storyID })
        localFavoritedIDs = Set(stories.filter { ($0.rating ?? 0) >= 5 }.map { $0.storyID })
    }

    @ViewBuilder
    private var libraryContent: some View {
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
                emptyStateContent
            } else {
                libraryGrid
            }
        }
        .navigationTitle("LitKeeper")
    }

    @ViewBuilder
    private var emptyStateContent: some View {
        let hasError = viewModel.errorMessage != nil
        let isEmpty = viewModel.stories.isEmpty
        VStack(spacing: 16) {
            EmptyStateView(
                icon: hasError ? "wifi.slash" : "books.vertical",
                title: hasError ? "Server Unreachable" : (isEmpty ? "Library Empty" : "No Results"),
                message: hasError
                    ? "Could not connect to your server. Check your connection or settings."
                    : (isEmpty ? "Submit a Literotica URL to download your first story." : "Try adjusting your search or filters.")
            )
            if hasError || isEmpty {
                Button {
                    Task { await viewModel.refresh(appState: appState) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var libraryGrid: some View {
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
                    storyButton(story: story, index: index)
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.refresh(appState: appState)
            HapticManager.shared.notify(.success)
            await syncService.syncQueueStatus(for: viewModel.stories, modelContainer: modelContext.container)
            cardsAppeared = false
            Task { await syncService.syncCovers(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, proxyTokenId: appState.proxyTokenId, proxyToken: appState.proxyToken, modelContainer: modelContext.container) }
            Task { await syncService.syncContent(for: viewModel.stories, serverURL: appState.serverURL, token: appState.apiToken, proxyTokenId: appState.proxyTokenId, proxyToken: appState.proxyToken, modelContainer: modelContext.container) }
            Task { await syncService.syncHighlights(serverURL: appState.serverURL, token: appState.apiToken, proxyTokenId: appState.proxyTokenId, proxyToken: appState.proxyToken, modelContainer: modelContext.container) }
            try? await Task.sleep(for: .milliseconds(50))
            cardsAppeared = true
        }
        .onAppear {
            guard !cardsAppeared else { return }
            cardsAppeared = true
        }
    }

    private func storyButton(story: Story, index: Int) -> some View {
        Button { selectedStory = story } label: {
            StoryCard(
                story: story,
                isDownloaded: viewModel.isDownloaded(story),
                isInQueue: story.inQueue || localQueuedIDs.contains(story.id),
                isFavorited: story.rating == 5 || localFavoritedIDs.contains(story.id),
                localRating: localByID[story.id]?.rating,
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
            .spring(response: 0.4, dampingFraction: 0.8).delay(Double(min(index, 8)) * 0.03),
            value: cardsAppeared
        )
    }

    private func coverURL(for story: Story) -> URL? {
        let local = localByID[story.id]
        if let url = DownloadManager.shared.resolveCoverURL(for: story, localStory: local) { return url }
        guard !appState.serverURL.isEmpty else { return nil }
        let base = appState.serverURL.hasSuffix("/") ? String(appState.serverURL.dropLast()) : appState.serverURL
        return URL(string: "\(base)/api/story/\(story.id)/cover")
    }
}
