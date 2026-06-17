import SwiftUI

struct BrowseView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = BrowseViewModel()
    @State private var showFilters = false

    var body: some View {
        NavigationStack {
            List {
                modePicker
                categoryRow
                storyRows
            }
            .listStyle(.plain)
            .navigationTitle("Browse")
            .toolbar {
                sortToolbarItem
                filterToolbarItem
            }
            .refreshable {
                await viewModel.load(apiClient: appState.makeAPIClient())
            }
            .sheet(isPresented: $showFilters, onDismiss: { triggerLoad() }) {
                BrowseFilterView(
                    minScore: $viewModel.minScore,
                    minViews: $viewModel.minViews,
                    minFaves: $viewModel.minFaves,
                    seriesFilter: $viewModel.seriesFilter,
                    dateRange: $viewModel.dateRange
                )
            }
            .task {
                guard appState.isConfigured else { return }
                await viewModel.initialize(apiClient: appState.makeAPIClient())
            }
            .overlay {
                if !appState.isConfigured {
                    EmptyStateView(
                        icon: "gearshape",
                        title: "Not Configured",
                        message: "Configure your server in Settings to start browsing."
                    )
                } else if viewModel.isLoading && viewModel.stories.isEmpty {
                    ProgressView()
                } else if let error = viewModel.errorMessage, viewModel.stories.isEmpty {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Unable to Load",
                        message: error,
                        action: triggerLoad,
                        actionLabel: "Retry"
                    )
                } else if !viewModel.isLoading && viewModel.stories.isEmpty {
                    EmptyStateView(
                        icon: "books.vertical",
                        title: "No Stories",
                        message: "No stories match the current filters."
                    )
                }
            }
        }
    }

    // MARK: - List Rows

    private var modePicker: some View {
        let modes: [BrowseViewModel.BrowseMode] = viewModel.customListAvailable
            ? [.byCategory, .global, .customList]
            : [.byCategory, .global]
        return Picker("Source", selection: $viewModel.mode) {
            ForEach(modes, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .onChange(of: viewModel.mode) { triggerLoad() }
    }

    // Only shown for By Category and Custom List — global mode has no sub-row.
    @ViewBuilder
    private var categoryRow: some View {
        switch viewModel.mode {
        case .byCategory:
            Picker("Category", selection: $viewModel.selectedCategorySlug) {
                ForEach(viewModel.litCategories) { cat in
                    Text(cat.label).tag(cat.slug)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.selectedCategorySlug) { triggerLoad() }
        case .global:
            EmptyView()
        case .customList:
            Picker("Category", selection: $viewModel.customCategory) {
                Text("All Categories").tag("")
                ForEach(viewModel.customCategories, id: \.self) { cat in
                    Text(cat.replacingOccurrences(of: "-", with: " ").capitalized).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.customCategory) { triggerLoad() }
        }
    }

    @ViewBuilder
    private var storyRows: some View {
        let showCategory = viewModel.mode == .global
            || (viewModel.mode == .customList && viewModel.customCategory.isEmpty)
        ForEach(viewModel.stories) { story in
            BrowseStoryRow(
                story: story,
                isInLibrary: story.inLibrary,
                isQueued: story.isQueued || viewModel.queuedURLs.contains(story.url),
                showCategory: showCategory,
                onAdd: {
                    await viewModel.queueStory(
                        url: story.url,
                        apiClient: appState.makeAPIClient()
                    )
                }
            )
            .onAppear {
                if story.id == viewModel.stories.last?.id {
                    Task { await viewModel.loadNextPage(apiClient: appState.makeAPIClient()) }
                }
            }
        }
        if viewModel.isLoadingMore {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Toolbar

    // Sort options differ by mode; for .global they drive the top-list tab rather than a sort order.
    @ToolbarContentBuilder
    private var sortToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                switch viewModel.mode {
                case .byCategory:
                    Picker("Sort", selection: $viewModel.litSort) {
                        Text("All Time").tag("top_all")
                        Text("12 Months").tag("top_12mo")
                        Text("30 Days").tag("top_30d")
                        Text("Newest").tag("newest")
                    }
                    .onChange(of: viewModel.litSort) { triggerLoad() }
                case .global:
                    Picker("List", selection: $viewModel.globalTab) {
                        Text("Top Rated").tag("top_rated")
                        Text("Most Read").tag("most_read")
                        Text("Newest").tag("newest")
                    }
                    .onChange(of: viewModel.globalTab) { triggerLoad() }
                case .customList:
                    Picker("Sort", selection: $viewModel.customSort) {
                        Text("Top Rated").tag("score_desc")
                        Text("Most Viewed").tag("views_desc")
                        Text("Most Favorited").tag("favorites_desc")
                        Text("Newest").tag("date_desc")
                        Text("Oldest").tag("date_asc")
                    }
                    .onChange(of: viewModel.customSort) { triggerLoad() }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
    }

    @ToolbarContentBuilder
    private var filterToolbarItem: some ToolbarContent {
        if viewModel.mode == .customList {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilters = true
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    // MARK: - Helpers

    private func triggerLoad() {
        Task { await viewModel.load(apiClient: appState.makeAPIClient()) }
    }
}
