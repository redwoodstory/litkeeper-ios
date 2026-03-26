import Foundation
import SwiftData
import Observation

@Observable
final class ReadingQueueViewModel {
    var stories: [Story] = []
    var isLoading = false
    var errorMessage: String? = nil
    var downloadedStoryIDs: Set<Int> = []
    // Server progress keyed by story ID, 0-1 scale
    var progressByStoryID: [Int: Double] = [:]
    private var hasAttemptedLoad = false

    var queuedStories: [Story] {
        stories
            .filter { $0.inQueue }
            .sorted { a, b in
                (a.dateAdded ?? "") > (b.dateAdded ?? "")
            }
    }

    func isDownloaded(_ story: Story) -> Bool {
        downloadedStoryIDs.contains(story.id)
    }

    func updateDownloadedIDs(from localStories: [LocalStory]) {
        downloadedStoryIDs = Set(localStories.map { $0.storyID })
    }

    func removeFromQueue(story: Story, appState: AppState) async {
        if let idx = stories.firstIndex(where: { $0.id == story.id }) {
            stories[idx].inQueue = false
        }
        do {
            try await appState.makeAPIClient().updateQueue(storyID: story.id, inQueue: false)
        } catch {
            if let idx = stories.firstIndex(where: { $0.id == story.id }) {
                stories[idx].inQueue = true
            }
            errorMessage = error.localizedDescription
        }
    }

    func refresh(appState: AppState, silent: Bool = false) async {
        guard appState.isConfigured else {
            stories = []
            return
        }
        if !silent || (!hasAttemptedLoad && stories.isEmpty) { isLoading = true }
        errorMessage = nil
        let client = appState.makeAPIClient()
        do {
            stories = try await client.fetchLibrary()
            await fetchProgressForQueue(client: client)
        } catch let error as APIError {
            if case .networkError = error { /* transient — never alert */ }
            else if !silent { errorMessage = error.localizedDescription }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
        isLoading = false
        hasAttemptedLoad = true
    }

    private func fetchProgressForQueue(client: APIClient) async {
        let ids = queuedStories.map { $0.id }
        let result = await client.fetchAllProgress(storyIDs: ids)
        for (id, progress) in result {
            if let pct = progress.percentage {
                progressByStoryID[id] = pct
            }
        }
    }
}
