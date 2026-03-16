import Foundation
import SwiftData
import Observation

@Observable
final class LibraryViewModel {
    var stories: [Story] = []
    var isLoading = false
    var errorMessage: String? = nil

    // Filter/sort state
    var searchText = ""
    var selectedCategory: String? = nil
    var sortBy: SortOption = .dateAdded
    var sortAscending = false
    var showQueueOnly = false

    enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded = "Date Added"
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

    func refresh(appState: AppState) async {
        guard appState.isConfigured else {
            errorMessage = "Configure your server in Settings."
            return
        }
        isLoading = true
        errorMessage = nil
        let client = appState.makeAPIClient()
        do {
            stories = try await client.fetchLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
