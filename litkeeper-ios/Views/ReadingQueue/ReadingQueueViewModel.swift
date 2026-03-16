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

    func refresh(appState: AppState) async {
        guard appState.isConfigured else { return }
        isLoading = true
        errorMessage = nil
        let client = appState.makeAPIClient()
        do {
            stories = try await client.fetchLibrary()
            await fetchProgressForQueue(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchProgressForQueue(client: APIClient) async {
        let ids = queuedStories.map { $0.id }
        await withTaskGroup(of: (Int, Double?).self) { group in
            for id in ids {
                group.addTask {
                    let p = try? await client.fetchProgress(storyID: id)
                    return (id, p?.percentage)
                }
            }
            for await (id, pct) in group {
                if let pct {
                    progressByStoryID[id] = pct
                }
            }
        }
    }
}
