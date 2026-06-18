import Foundation
import SwiftData
import Observation

@Observable
final class LibraryViewModel {
    var stories: [Story] = [] { didSet { _recomputeFiltered() } }
    var isLoading = false
    var errorMessage: String? = nil
    var isShowingCachedData = false
    private var hasAttemptedLoad = false

    private static let cacheKey = "cachedLibraryStories"

    // Filter/sort state — each setter triggers a filteredStories recompute
    var searchText = "" { didSet { _recomputeFiltered() } }
    var selectedCategory: String? = nil { didSet { _recomputeFiltered() } }
    var sortBy: SortOption = .dateAdded { didSet { _recomputeFiltered() } }
    var sortAscending = false { didSet { _recomputeFiltered() } }
    var showQueueOnly = false { didSet { _recomputeFiltered() } }

    enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded = "Date Added"
        case lastOpened = "Date Last Opened"
        case title = "Title"
        case author = "Author"
        case wordCount = "Length"
        case rating = "Rating"
        var id: String { rawValue }
    }

    // Set of downloaded story IDs — merged from SwiftData
    var downloadedStoryIDs: Set<Int> = []

    // Cached result — recomputed only when stories or filter/sort state changes
    private(set) var filteredStories: [Story] = []

    func _recomputeFiltered() {
        var result = stories

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q)
            }
        }
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if showQueueOnly {
            result = result.filter { $0.inQueue == true }
        }

        result.sort { a, b in
            let ascending = sortAscending
            switch sortBy {
            case .dateAdded:
                return ascending
                    ? (a.dateAdded ?? "") < (b.dateAdded ?? "")
                    : (a.dateAdded ?? "") > (b.dateAdded ?? "")
            case .lastOpened:
                let aDate = a.lastOpenedAt ?? ""
                let bDate = b.lastOpenedAt ?? ""
                if aDate.isEmpty && bDate.isEmpty { return false }
                if aDate.isEmpty { return ascending }
                if bDate.isEmpty { return !ascending }
                return ascending ? aDate < bDate : aDate > bDate
            case .title:
                return ascending ? a.title < b.title : a.title > b.title
            case .author:
                return ascending ? a.author < b.author : a.author > b.author
            case .wordCount:
                return ascending
                    ? (a.wordCount ?? 0) < (b.wordCount ?? 0)
                    : (a.wordCount ?? 0) > (b.wordCount ?? 0)
            case .rating:
                return ascending
                    ? (a.rating ?? 0) < (b.rating ?? 0)
                    : (a.rating ?? 0) > (b.rating ?? 0)
            }
        }

        filteredStories = result
    }

    var availableCategories: [String] {
        Array(Set(stories.compactMap { $0.category })).sorted()
    }

    func isDownloaded(_ story: Story) -> Bool {
        downloadedStoryIDs.contains(story.id)
    }

    /// Call before the first server sync to surface local data immediately.
    /// Falls back from UserDefaults cache → SwiftData local stories → empty.
    func loadLocalData(localStories: [LocalStory] = []) {
        guard stories.isEmpty else { return }
        let cached = readCache()
        if !cached.isEmpty {
            stories = cached
            isShowingCachedData = true
        } else if !localStories.isEmpty {
            stories = localStories.map { $0.asStory }
            isShowingCachedData = true
        }
    }

    func refresh(appState: AppState, silent: Bool = false) async {
        guard appState.isConfigured else {
            isShowingCachedData = false
            return
        }
        if !silent || (!hasAttemptedLoad && stories.isEmpty) { isLoading = true }
        errorMessage = nil
        let client = appState.makeAPIClient()
        do {
            let fetched = try await client.fetchLibrary()
            if fetched != stories { stories = fetched }
            isShowingCachedData = false
            Task.detached(priority: .background) { [weak self] in
                self?.saveCache(fetched)
            }
        } catch let error as APIError {
            switch error {
            case .unauthorized, .notConfigured:
                if !silent { errorMessage = error.localizedDescription }
            default:
                break
            }
            isShowingCachedData = !stories.isEmpty
        } catch {
            isShowingCachedData = !stories.isEmpty
        }
        isLoading = false
        hasAttemptedLoad = true
    }

    private func saveCache(_ stories: [Story]) {
        guard let data = try? JSONEncoder().encode(stories) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func readCache() -> [Story] {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let stories = try? JSONDecoder().decode([Story].self, from: data)
        else { return [] }
        return stories
    }

    func updateDownloadedIDs(from localStories: [LocalStory]) {
        downloadedStoryIDs = Set(localStories.map { $0.storyID })
    }

    func deleteStory(_ story: Story, appState: AppState) async {
        let client = appState.makeAPIClient()
        do {
            try await client.deleteStory(storyID: story.id)
            stories.removeAll { $0.id == story.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
