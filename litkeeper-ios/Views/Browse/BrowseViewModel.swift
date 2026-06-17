import Foundation
import Observation

@Observable
final class BrowseViewModel {
    enum BrowseMode: String, CaseIterable {
        case byCategory = "By Category"
        case global = "Top Lists"
        case customList = "Custom List"
    }

    // Navigation
    var mode: BrowseMode = .byCategory
    var customListAvailable = false

    // By Category
    var litCategories: [BrowseCategory] = []
    var selectedCategorySlug: String = ""
    var litSort = "top_all"

    // Top Lists
    var globalTab = "top_rated"

    // Custom List
    var customCategories: [String] = []
    var customCategory = ""
    var customSort = "score_desc"
    var minScore: Double = 4.5
    var minViews: Int = 100
    var seriesFilter = "all"
    var dateRange = "all"

    // Content
    var stories: [BrowseStory] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var page = 1
    var totalPages = 1

    // Optimistic queuing — tracks URLs queued this session
    var queuedURLs: Set<String> = []

    var selectedCategoryLabel: String {
        litCategories.first { $0.slug == selectedCategorySlug }?.label ?? "Category"
    }

    func initialize(apiClient: APIClient) async {
        guard litCategories.isEmpty else {
            if stories.isEmpty { await load(apiClient: apiClient) }
            return
        }
        async let catsResult = try? apiClient.fetchBrowseCategories()
        async let customCatsResult = try? apiClient.fetchCustomListCategories()
        let (cats, customCats) = await (catsResult, customCatsResult)
        if let cats, !cats.isEmpty {
            litCategories = cats
            selectedCategorySlug = cats.first?.slug ?? ""
        }
        if let customCats, !customCats.isEmpty {
            customCategories = customCats
            customCategory = customCats.first ?? ""
            customListAvailable = true
        }
        await load(apiClient: apiClient)
    }

    func load(apiClient: APIClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await fetchPage(1, apiClient: apiClient)
            stories = result.stories
            page = result.page ?? 1
            totalPages = result.totalPages ?? 1
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadNextPage(apiClient: APIClient) async {
        guard !isLoadingMore, page < totalPages else { return }
        isLoadingMore = true
        do {
            let result = try await fetchPage(page + 1, apiClient: apiClient)
            stories += result.stories
            page = result.page ?? (page + 1)
        } catch {
            // Pagination failures are silent; user can pull-to-refresh
        }
        isLoadingMore = false
    }

    func queueStory(url: String, apiClient: APIClient) async {
        queuedURLs.insert(url)
        do {
            try await apiClient.queueBrowseStories(urls: [url])
        } catch {
            queuedURLs.remove(url)
        }
    }

    private func fetchPage(_ p: Int, apiClient: APIClient) async throws -> BrowseResult {
        switch mode {
        case .byCategory:
            let cat = selectedCategorySlug.isEmpty
                ? (litCategories.first?.slug ?? "erotic-couplings")
                : selectedCategorySlug
            return try await apiClient.browseByCategory(category: cat, sort: litSort, page: p)
        case .global:
            return try await apiClient.browseGlobal(mode: globalTab, page: p)
        case .customList:
            return try await apiClient.browseCustomList(
                category: customCategory,
                sort: customSort,
                page: p,
                minScore: minScore,
                minViews: minViews,
                series: seriesFilter,
                dateRange: dateRange
            )
        }
    }
}
