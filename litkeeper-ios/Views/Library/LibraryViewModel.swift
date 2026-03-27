import Foundation
import SwiftData
import Observation

@Observable
final class LibraryViewModel {
    var stories: [Story] = []
    var isLoading = false
    var errorMessage: String? = nil
    var isShowingCachedData = false
    private var hasAttemptedLoad = false

    private static let cacheKey = "cachedLibraryStories"

    // Filter/sort state
    var searchText = ""
    var selectedCategory: String? = nil
    var sortBy: SortOption = .dateAdded
    var sortAscending = false
    var showQueueOnly = false
    var showCategoryLabel = false

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

    var filteredStories: [Story] {
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
            result = result.filter { $0.inQueue }
        }

        result.sort { a, b in
            let ascending = sortAscending
            switch sortBy {
            case .dateAdded:
                return ascending
                    ? (a.dateAdded ?? "") < (b.dateAdded ?? "")
                    : (a.dateAdded ?? "") > (b.dateAdded ?? "")
            case .lastOpened:
                // Stories never opened (nil) should appear last when descending (most recent first)
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

        return result
    }

    var availableCategories: [String] {
        Array(Set(stories.compactMap { $0.category })).sorted()
    }

    func isDownloaded(_ story: Story) -> Bool {
        downloadedStoryIDs.contains(story.id)
    }

    func refresh(appState: AppState, silent: Bool = false) async {
        guard appState.isConfigured else {
            stories = []
            isShowingCachedData = false
            return
        }
        if !silent || (!hasAttemptedLoad && stories.isEmpty) { isLoading = true }
        errorMessage = nil
        let client = appState.makeAPIClient()
        do {
            let fetched = try await client.fetchLibrary()
            stories = fetched
            isShowingCachedData = false
            saveLibraryCache(fetched)
        } catch let error as APIError {
            if case .networkError = error {
                // Transient network failure — load cache if we have nothing to show
                if stories.isEmpty {
                    let cached = loadLibraryCache()
                    if !cached.isEmpty {
                        stories = cached
                        isShowingCachedData = true
                    }
                }
            } else if !silent {
                errorMessage = error.localizedDescription
            }
        } catch {
            if stories.isEmpty {
                let cached = loadLibraryCache()
                if !cached.isEmpty {
                    stories = cached
                    isShowingCachedData = true
                }
            }
            if !silent { errorMessage = error.localizedDescription }
        }
        isLoading = false
        hasAttemptedLoad = true
    }

    private func saveLibraryCache(_ stories: [Story]) {
        guard let data = try? JSONEncoder().encode(stories) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func loadLibraryCache() -> [Story] {
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
