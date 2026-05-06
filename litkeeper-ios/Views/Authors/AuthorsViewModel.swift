import Foundation
import Observation

@Observable
final class AuthorsViewModel {
    var authors: [Author] = []
    var isLoading = false
    var errorMessage: String? = nil

    func refresh(appState: AppState) async {
        guard appState.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        let client = appState.makeAPIClient()
        do {
            authors = try await client.fetchAuthors()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleWatch(author: Author, appState: AppState) async {
        let client = appState.makeAPIClient()
        do {
            let newValue = try await client.toggleAuthorWatch(authorID: author.id)
            if let idx = authors.firstIndex(where: { $0.id == author.id }) {
                authors[idx].watchEnabled = newValue
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rescan(author: Author, appState: AppState) async {
        let client = appState.makeAPIClient()
        do {
            try await client.rescanAuthor(authorID: author.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addAuthor(url: String, appState: AppState) async throws -> QueueItem {
        let client = appState.makeAPIClient()
        let item = try await client.queueAuthorDownload(authorURL: url)
        await refresh(appState: appState)
        return item
    }
}
