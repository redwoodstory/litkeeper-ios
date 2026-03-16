import Foundation
import Observation

@Observable
final class QueueViewModel {
    var items: [QueueItem] = []
    var stats: QueueStats? = nil
    var isLoading = false
    var errorMessage: String? = nil

    private var refreshTask: Task<Void, Never>? = nil

    func refresh(appState: AppState) async {
        guard appState.isConfigured else { return }
        isLoading = true
        let client = appState.makeAPIClient()
        async let itemsFetch = client.fetchQueueItems()
        async let statsFetch = client.fetchQueueStats()
        do {
            let (newItems, newStats) = try await (itemsFetch, statsFetch)
            items = newItems
            stats = newStats
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func startAutoRefresh(appState: AppState) {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled {
                    await refresh(appState: appState)
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
