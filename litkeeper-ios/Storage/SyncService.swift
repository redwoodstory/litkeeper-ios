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

        // Collect stories that need syncing
        let storiesToSync = stories.filter { story in
            let local = localByID[story.id]
            guard local != nil else { return true }
            guard let updatedAtStr = story.updatedAt,
                  let serverDate = Self.isoFormatter.date(from: updatedAtStr) else { return false }
            return local?.serverUpdatedAt.map { serverDate > $0 } ?? true
        }

        guard !storiesToSync.isEmpty else { return }

        let ptId = pangolinTokenId.flatMap { $0.isEmpty ? nil : $0 }
        let ptTok = pangolinToken.flatMap { $0.isEmpty ? nil : $0 }
        let client = APIClient(baseURLString: serverURL, token: token, pangolinTokenId: ptId, pangolinToken: ptTok)

        // Process in batches of 5 — keeps each request small and avoids CrowdSec triggers
        let batches = stride(from: 0, to: storiesToSync.count, by: 5).map {
            Array(storiesToSync[$0..<min($0 + 5, storiesToSync.count)])
        }

        for (index, batch) in batches.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s between batches
            }

            let ids = batch.map { $0.id }
            guard let response = await client.fetchBulkContent(storyIDs: ids) else {
                print("[LK-Sync] ✗ Bulk content fetch failed for batch \(index + 1)/\(batches.count)")
                continue
            }

            let dm = DownloadManager.shared
            for story in batch {
                guard let content = response.stories[String(story.id)] else { continue }

                var epubPath: String? = nil
                var htmlPath: String? = nil
                var coverPath: String? = nil

                if let b64 = content.epub, let filename = content.epubFilename,
                   let data = Data(base64Encoded: b64) {
                    try? data.write(to: dm.localEPUBURL(filenameBase: story.filenameBase))
                    epubPath = filename
                }

                if let b64 = content.html, let filename = content.htmlFilename,
                   let data = Data(base64Encoded: b64) {
                    try? data.write(to: dm.localHTMLURL(filenameBase: story.filenameBase))
                    htmlPath = filename
                }

                if let b64 = content.cover, let filename = content.coverFilename,
                   let data = Data(base64Encoded: b64) {
                    try? data.write(to: dm.localCoverURL(filename: filename))
                    coverPath = filename
                    localCoverFilenames.insert(filename)
                }

                let storyID = story.id
                let existing = (try? modelContext.fetch(
                    FetchDescriptor<LocalStory>(predicate: #Predicate { $0.storyID == storyID })
                ))?.first
                let record = existing ?? LocalStory(
                    storyID: story.id,
                    title: story.title,
                    author: story.author,
                    filenameBase: story.filenameBase,
                    coverFilename: story.cover
                )
                record.epubLocalPath = epubPath
                record.htmlLocalPath = htmlPath
                record.coverLocalPath = coverPath
                record.downloadedAt = Date()
                if let updatedAtStr = story.updatedAt,
                   let serverDate = Self.isoFormatter.date(from: updatedAtStr) {
                    record.serverUpdatedAt = serverDate
                }
                if existing == nil { modelContext.insert(record) }
            }
            try? modelContext.save()
            print("[LK-Sync] ✓ Bulk content sync: batch \(index + 1)/\(batches.count) complete (\(batch.count) stories)")
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

        let isoFormatter = ISO8601DateFormatter()
        for story in localStories {
            guard let p = progressMap[story.storyID] else { continue }

            // Determine if server progress is newer than what's stored locally
            let serverDate = p.lastReadAt.flatMap { isoFormatter.date(from: $0) }
            let localDate = story.lastReadAt
            let serverIsNewer = serverDate != nil && (localDate == nil || serverDate! > localDate!)

            if let pct = p.percentage {
                // Only overwrite local fraction if server is newer (avoids regressing progress)
                if serverIsNewer || story.readingProgressScrollY == nil {
                    story.readingProgressScrollY = pct
                    story.readingProgressPercentage = pct * 100
                }
            }

            // Restore precise paragraph position when server has newer data
            if serverIsNewer, let pid = p.paragraphID {
                story.readingProgressParagraphID = pid
                story.lastReadAt = serverDate
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
