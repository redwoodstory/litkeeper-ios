import Foundation
import SwiftData

@Observable
@MainActor
final class SyncService {
    private(set) var localCoverFilenames: Set<String> = []
    private(set) var isSyncingCovers = false
    private(set) var isSyncingContent = false
    private(set) var isSyncingMetadata = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init() {
        populateLocalCoversFromDisk()
    }

    // MARK: - Cover Sync

    func syncCovers(for stories: [Story], serverURL: String, token: String, pangolinTokenId: String? = nil, pangolinToken: String? = nil) async {
        guard !serverURL.isEmpty, !token.isEmpty, !isSyncingCovers else { return }
        isSyncingCovers = true
        defer { isSyncingCovers = false }

        let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL

        var pending: [(filename: String, remoteURL: URL)] = []
        for story in stories {
            let filename = story.cover ?? "\(story.filenameBase).jpg"
            let localURL = DownloadManager.shared.localCoverURL(filename: filename)

            if FileManager.default.fileExists(atPath: localURL.path) {
                if let updatedAtStr = story.updatedAt,
                   let serverDate = Self.isoFormatter.date(from: updatedAtStr),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
                   let fileDate = attrs[.modificationDate] as? Date,
                   fileDate >= serverDate {
                    localCoverFilenames.insert(filename)
                    continue
                }
            }

            guard let remoteURL = URL(string: "\(base)/api/cover/\(filename)") else { continue }
            pending.append((filename, remoteURL))
        }

        let batches = stride(from: 0, to: pending.count, by: 5).map {
            Array(pending[$0..<min($0 + 5, pending.count)])
        }
        for (index, batch) in batches.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms between batches
            }
            await withTaskGroup(of: (String, Data)?.self) { group in
                for item in batch {
                    let capturedFilename = item.filename
                    let capturedURL = item.remoteURL
                    let capturedToken = token
                    let capturedPangolinId = pangolinTokenId
                    let capturedPangolinToken = pangolinToken
                    group.addTask {
                        var request = URLRequest(url: capturedURL)
                        request.setValue("Bearer \(capturedToken)", forHTTPHeaderField: "Authorization")
                        if let id = capturedPangolinId { request.setValue(id, forHTTPHeaderField: "P-Access-Token-Id") }
                        if let tok = capturedPangolinToken { request.setValue(tok, forHTTPHeaderField: "P-Access-Token") }
                        guard let (data, response) = try? await URLSession.shared.data(for: request),
                              let http = response as? HTTPURLResponse,
                              http.statusCode == 200 else { return nil }
                        return (capturedFilename, data)
                    }
                }
                for await result in group {
                    guard let (filename, data) = result else { continue }
                    let localURL = DownloadManager.shared.localCoverURL(filename: filename)
                    try? data.write(to: localURL)
                    localCoverFilenames.insert(filename)
                }
            }
        }
    }

    // MARK: - Content Sync

    func syncContent(
        for stories: [Story],
        serverURL: String,
        token: String,
        pangolinTokenId: String? = nil,
        pangolinToken: String? = nil,
        modelContext: ModelContext,
        localStories: [LocalStory]
    ) async {
        guard !serverURL.isEmpty, !token.isEmpty, !isSyncingContent else { return }
        isSyncingContent = true
        defer { isSyncingContent = false }

        let localByID = Dictionary(uniqueKeysWithValues: localStories.map { ($0.storyID, $0) })

        for story in stories {
            let local = localByID[story.id]

            var needsSync = false
            if local == nil {
                needsSync = true
            } else if let updatedAtStr = story.updatedAt,
                      let serverDate = Self.isoFormatter.date(from: updatedAtStr) {
                needsSync = local?.serverUpdatedAt.map { serverDate > $0 } ?? true
            }

            guard needsSync else { continue }

            do {
                try await DownloadManager.shared.downloadStory(
                    story: story,
                    serverBaseURL: serverURL,
                    token: token,
                    pangolinTokenId: pangolinTokenId,
                    pangolinToken: pangolinToken,
                    modelContext: modelContext,
                    onProgress: { _, _ in }
                )
                if let updatedAtStr = story.updatedAt,
                   let serverDate = Self.isoFormatter.date(from: updatedAtStr) {
                    let storyID = story.id
                    if let record = (try? modelContext.fetch(
                        FetchDescriptor<LocalStory>(predicate: #Predicate { $0.storyID == storyID })
                    ))?.first {
                        record.serverUpdatedAt = serverDate
                        try? modelContext.save()
                    }
                }
            } catch {
                print("[LK-Sync] ✗ Failed to sync story \(story.id): \(error)")
            }
        }
    }

    // MARK: - Cover Resync (after metadata change)

    func resyncCover(coverFilename: String, serverURL: String, token: String) async {
        guard !serverURL.isEmpty, !token.isEmpty else { return }

        let localURL = DownloadManager.shared.localCoverURL(filename: coverFilename)
        try? FileManager.default.removeItem(at: localURL)
        localCoverFilenames.remove(coverFilename)

        let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        guard let remoteURL = URL(string: "\(base)/api/cover/\(coverFilename)") else { return }

        var request = URLRequest(url: remoteURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return }

        try? data.write(to: localURL)
        localCoverFilenames.insert(coverFilename)
        print("[LK-Sync] ✓ Cover resynced: \(coverFilename)")
    }

    // MARK: - Metadata Sync

    func syncMetadata(appState: AppState, modelContext: ModelContext) async {
        guard appState.isConfigured, !isSyncingMetadata else { return }
        isSyncingMetadata = true
        defer { isSyncingMetadata = false }

        let localStories: [LocalStory]
        do {
            localStories = try modelContext.fetch(FetchDescriptor<LocalStory>())
        } catch {
            print("[LK-Sync] ✗ syncMetadata: failed to fetch LocalStory records: \(error)")
            return
        }
        guard !localStories.isEmpty else { return }

        let client = appState.makeAPIClient()
        let ids = localStories.map { $0.storyID }
        let progressMap = await client.fetchAllProgress(storyIDs: ids)
        guard !progressMap.isEmpty else { return }

        for story in localStories {
            if let p = progressMap[story.storyID], let pct = p.percentage {
                story.readingProgressScrollY = pct
                story.readingProgressPercentage = pct * 100
            }
        }
        try? modelContext.save()
        print("[LK-Sync] ✓ Metadata sync complete — progress updated for \(progressMap.count) stories")
    }

    // MARK: - Private

    private func populateLocalCoversFromDisk() {
        let dir = DownloadManager.shared.coversDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        localCoverFilenames = Set(contents)
    }
}
