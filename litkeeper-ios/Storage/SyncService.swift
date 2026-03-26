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
                record.updateMetadata(from: story)
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

    // MARK: - Queue Status Sync

    /// Syncs queue status and metadata for all stories from the server.
    /// Creates LocalStory records for queued stories that haven't been downloaded yet,
    /// and updates metadata on all existing records so rich data is available offline.
    func syncQueueStatus(for stories: [Story], modelContext: ModelContext) {
        guard let localStories = try? modelContext.fetch(FetchDescriptor<LocalStory>()) else { return }
        var localByID = Dictionary(uniqueKeysWithValues: localStories.map { ($0.storyID, $0) })

        // Don't overwrite inQueue for stories that have a pending local change
        let pendingQueueIDs: Set<Int> = {
            let ops = (try? modelContext.fetch(FetchDescriptor<PendingOperation>(
                predicate: #Predicate { $0.operationType == "queue" }
            ))) ?? []
            return Set(ops.map { $0.storyID })
        }()

        let pendingRatingIDs: Set<Int> = {
            let ops = (try? modelContext.fetch(FetchDescriptor<PendingOperation>(
                predicate: #Predicate { $0.operationType == "rating" }
            ))) ?? []
            return Set(ops.map { $0.storyID })
        }()

        for story in stories {
            if let local = localByID[story.id] {
                // Only update queue flag if there's no pending local change waiting to sync
                if !pendingQueueIDs.contains(story.id) {
                    local.inQueue = story.inQueue ?? false
                }
                // Preserve pending rating before updateMetadata overwrites it
                let savedRating = pendingRatingIDs.contains(story.id) ? local.rating : nil
                local.updateMetadata(from: story)
                if let saved = savedRating { local.rating = saved }
            } else if story.inQueue == true {
                // Create a metadata-only record for queued stories not yet downloaded
                let record = LocalStory(
                    storyID: story.id,
                    title: story.title,
                    author: story.author,
                    filenameBase: story.filenameBase,
                    coverFilename: story.cover
                )
                record.inQueue = true
                record.updateMetadata(from: story)
                modelContext.insert(record)
                localByID[story.id] = record
            }
        }

        // Clear queue flag for any local records whose story is no longer in queue
        let serverIDs = Set(stories.map { $0.id })
        for local in localStories where !serverIDs.contains(local.storyID) {
            local.inQueue = false
        }

        try? modelContext.save()
        print("[LK-Sync] ✓ Queue status sync: \(localStories.count) local stories updated")
    }

    // MARK: - Highlights Sync

    private(set) var isSyncingHighlights = false

    func syncHighlights(appState: AppState, modelContext: ModelContext) async {
        guard appState.isConfigured, !isSyncingHighlights else { return }
        isSyncingHighlights = true
        defer { isSyncingHighlights = false }

        let client = appState.makeAPIClient()
        guard let highlights = try? await client.fetchHighlights() else { return }

        let existing: [LocalHighlight]
        do {
            existing = try modelContext.fetch(FetchDescriptor<LocalHighlight>())
        } catch {
            print("[LK-Sync] ✗ syncHighlights: fetch failed: \(error)")
            return
        }

        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.highlightID, $0) })
        let serverIDs = Set(highlights.map { $0.id })

        // Upsert
        for h in highlights {
            if let local = existingByID[h.id] {
                local.storyTitle = h.storyTitle
                local.storyAuthor = h.storyAuthor
                local.filenameBase = h.filenameBase
                local.chapterIndex = h.chapterIndex
                local.paragraphIndex = h.paragraphIndex
                local.quoteText = h.quoteText
                local.note = h.note
            } else {
                let local = LocalHighlight(
                    highlightID: h.id,
                    storyID: h.storyId,
                    storyTitle: h.storyTitle,
                    storyAuthor: h.storyAuthor,
                    filenameBase: h.filenameBase,
                    chapterIndex: h.chapterIndex,
                    paragraphIndex: h.paragraphIndex,
                    quoteText: h.quoteText,
                    note: h.note,
                    createdAt: h.createdAt
                )
                modelContext.insert(local)
            }
        }

        // Delete highlights removed on the server
        for local in existing where !serverIDs.contains(local.highlightID) {
            modelContext.delete(local)
        }

        try? modelContext.save()
        print("[LK-Sync] ✓ Highlights sync: \(highlights.count) highlights synced")
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

    // MARK: - Pending Operations Flush

    /// Attempts to send all locally-queued operations to the server.
    /// Records are deleted on success and kept for retry on failure (e.g. still offline).
    func flushPendingOperations(appState: AppState, modelContext: ModelContext) async {
        guard appState.isConfigured else { return }
        let pending = (try? modelContext.fetch(FetchDescriptor<PendingOperation>())) ?? []
        guard !pending.isEmpty else { return }

        let client = appState.makeAPIClient()
        var didChange = false

        for op in pending {
            do {
                switch op.operationType {
                case "queue":
                    try await client.updateQueue(storyID: op.storyID, inQueue: op.inQueue ?? false)
                case "rating":
                    try await client.updateRating(storyID: op.storyID, rating: op.rating ?? 0)
                case "progress":
                    if let fraction = op.progressFraction {
                        let progress = ReadingProgress(
                            currentChapter: nil,
                            cfi: nil,
                            percentage: fraction,
                            isCompleted: fraction >= 0.99,
                            lastReadAt: nil
                        )
                        try await client.saveProgress(storyID: op.storyID, progress: progress)
                    }
                default:
                    break
                }
                modelContext.delete(op)
                didChange = true
                print("[LK-Sync] ✓ Flushed pending \(op.operationType) op for story \(op.storyID)")
            } catch {
                print("[LK-Sync] ✗ Pending \(op.operationType) op for story \(op.storyID) still offline — will retry")
            }
        }

        if didChange { try? modelContext.save() }
    }

    // MARK: - Metadata Sync

    func syncMetadata(appState: AppState, modelContext: ModelContext) async {
        guard appState.isConfigured, !isSyncingMetadata else { return }
        isSyncingMetadata = true
        defer { isSyncingMetadata = false }

        // Push any locally-queued changes before pulling server state
        await flushPendingOperations(appState: appState, modelContext: modelContext)

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
