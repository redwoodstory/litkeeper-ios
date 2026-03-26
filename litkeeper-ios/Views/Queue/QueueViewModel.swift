import Foundation
import Observation

@Observable
final class QueueViewModel {
    var items: [QueueItem] = []
    var stats: QueueStats? = nil
    var isLoading = false
    var errorMessage: String? = nil

    private var refreshTask: Task<Void, Never>? = nil
    private var hasAttemptedLoad = false

    func refresh(appState: AppState, silent: Bool = false) async {
        guard appState.isConfigured else { return }
        if !silent || (!hasAttemptedLoad && items.isEmpty) { isLoading = true }
        let client = appState.makeAPIClient()
        async let itemsFetch = client.fetchQueueItems()
        async let statsFetch = client.fetchQueueStats()
        do {
            let (newItems, newStats) = try await (itemsFetch, statsFetch)
            items = newItems
            stats = newStats
        } catch let error as APIError {
            if case .networkError = error { /* transient — never alert */ }
            else if !silent { errorMessage = error.localizedDescription }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
        isLoading = false
        hasAttemptedLoad = true
    }

    func startAutoRefresh(appState: AppState) {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if !Task.isCancelled {
                    await refresh(appState: appState, silent: true)
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
