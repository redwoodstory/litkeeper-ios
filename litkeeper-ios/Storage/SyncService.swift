import Foundation
import SwiftData
import UIKit

@Observable
@MainActor
final class SyncService {
    private(set) var localCoverFilenames: Set<String> = []
    private(set) var isSyncingCovers = false
    private(set) var isSyncingContent = false
    private(set) var isSyncingMetadata = false
    private(set) var isSyncingHighlights = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init() {
        let t = Date()
        print("[LK-STARTUP] SyncService.init start")
        populateLocalCoversFromDisk()
        print("[LK-STARTUP] SyncService.init done: \(String(format: "%.1f", Date().timeIntervalSince(t)*1000))ms")
    }

    // MARK: - Cover Sync

    nonisolated func syncCovers(
        for stories: [Story],
        serverURL: String,
        token: String,
        proxyTokenId: String,
        proxyToken: String,
        modelContainer: ModelContainer
    ) async {
        guard !serverURL.isEmpty, !token.isEmpty else { return }
        let alreadySyncing = await MainActor.run { self.isSyncingCovers }
        guard !alreadySyncing else { return }
        await MainActor.run { self.isSyncingCovers = true }
        defer { Task { @MainActor [self] in self.isSyncingCovers = false } }

        let context = ModelContext(modelContainer)
        let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        let isoFormatter = Self.isoFormatter

        var pending: [(storyID: Int, filename: String, remoteURL: URL)] = []
        var alreadyLocalFilenames: Set<String> = []

        for story in stories {
            let filename = story.cover ?? "\(story.id)_\(story.filenameBase).jpg"
            let localURL = DownloadManager.shared.localCoverURL(filename: filename)

            if FileManager.default.fileExists(atPath: localURL.path) {
                if let updatedAtStr = story.updatedAt,
                   let serverDate = isoFormatter.date(from: updatedAtStr),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
                   let fileDate = attrs[.modificationDate] as? Date,
                   fileDate >= serverDate {
                    alreadyLocalFilenames.insert(filename)
                    continue
                }
            }

            guard let remoteURL = URL(string: "\(base)/api/story/\(story.id)/cover") else { continue }
            pending.append((story.id, filename, remoteURL))
        }

        await MainActor.run { self.localCoverFilenames.formUnion(alreadyLocalFilenames) }

        let batches = stride(from: 0, to: pending.count, by: 5).map {
            Array(pending[$0..<min($0 + 5, pending.count)])
        }

        var newlyDownloadedFilenames: Set<String> = []

        for (index, batch) in batches.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            await withTaskGroup(of: (Int, String, Data)?.self) { group in
                for item in batch {
                    let capturedStoryID = item.storyID
                    let capturedFilename = item.filename
                    let capturedURL = item.remoteURL
                    let capturedToken = token
                    let capturedProxyTokenId = proxyTokenId.isEmpty ? nil : proxyTokenId
                    let capturedProxyToken = proxyToken.isEmpty ? nil : proxyToken
                    group.addTask {
                        var request = URLRequest(url: capturedURL, timeoutInterval: 8)
                        request.setValue(capturedToken, forHTTPHeaderField: "X-Api-Key")
                        if let tokenId = capturedProxyTokenId { request.setValue(tokenId, forHTTPHeaderField: "P-Access-Token-Id") }
                        if let tok = capturedProxyToken { request.setValue(tok, forHTTPHeaderField: "P-Access-Token") }
                        guard let (data, response) = try? await URLSession.shared.data(for: request),
                              let http = response as? HTTPURLResponse,
                              http.statusCode == 200,
                              UIImage(data: data) != nil else { return nil }
                        return (capturedStoryID, capturedFilename, data)
                    }
                }
                for await result in group {
                    guard let (storyID, filename, data) = result else { continue }
                    let localURL = DownloadManager.shared.localCoverURL(filename: filename)
                    try? data.write(to: localURL, options: .atomic)
                    newlyDownloadedFilenames.insert(filename)
                    let sid = storyID
                    if let record = (try? context.fetch(
                        FetchDescriptor<LocalStory>(predicate: #Predicate { $0.storyID == sid })
                    ))?.first {
                        record.coverLocalPath = filename
                        try? context.save()
                    }
                }
            }
        }

        await MainActor.run { self.localCoverFilenames.formUnion(newlyDownloadedFilenames) }
    }

    // MARK: - Content Sync

    nonisolated func syncContent(
        for stories: [Story],
        serverURL: String,
        token: String,
        proxyTokenId: String,
        proxyToken: String,
        modelContainer: ModelContainer
    ) async {
        guard !serverURL.isEmpty, !token.isEmpty else { return }
        let alreadySyncing = await MainActor.run { self.isSyncingContent }
        guard !alreadySyncing else { return }
        await MainActor.run { self.isSyncingContent = true }
        defer { Task { @MainActor [self] in self.isSyncingContent = false } }

        let context = ModelContext(modelContainer)
        let isoFormatter = Self.isoFormatter

        let localStories = (try? context.fetch(FetchDescriptor<LocalStory>())) ?? []
        let localByID = Dictionary(uniqueKeysWithValues: localStories.map { ($0.storyID, $0) })

        let storiesToSync = stories.filter { story in
            let local = localByID[story.id]
            guard local != nil else { return true }
            guard let updatedAtStr = story.updatedAt,
                  let serverDate = isoFormatter.date(from: updatedAtStr) else { return false }
            return local?.serverUpdatedAt.map { serverDate > $0 } ?? true
        }

        guard !storiesToSync.isEmpty else { return }

        let ptId = proxyTokenId.isEmpty ? nil : proxyTokenId
        let ptTok = proxyToken.isEmpty ? nil : proxyToken
        let client = APIClient(baseURLString: serverURL, token: token, proxyTokenId: ptId, proxyToken: ptTok)

        let batches = stride(from: 0, to: storiesToSync.count, by: 5).map {
            Array(storiesToSync[$0..<min($0 + 5, storiesToSync.count)])
        }

        var newCoverFilenames: Set<String> = []

        for (index, batch) in batches.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
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
                    try? data.write(to: dm.localEPUBURL(storyID: story.id, filenameBase: story.filenameBase), options: .atomic)
                    epubPath = filename
                }

                if let b64 = content.html, let filename = content.htmlFilename,
                   let data = Data(base64Encoded: b64) {
                    try? data.write(to: dm.localHTMLURL(storyID: story.id, filenameBase: story.filenameBase), options: .atomic)
                    htmlPath = filename
                }

                if let b64 = content.cover, let filename = content.coverFilename,
                   let data = Data(base64Encoded: b64) {
                    try? data.write(to: dm.localCoverURL(filename: filename), options: .atomic)
                    coverPath = filename
                    newCoverFilenames.insert(filename)
                }

                let storyID = story.id
                let existing = (try? context.fetch(
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
                   let serverDate = isoFormatter.date(from: updatedAtStr) {
                    record.serverUpdatedAt = serverDate
                }
                if existing == nil { context.insert(record) }
            }
            try? context.save()
            print("[LK-Sync] ✓ Bulk content sync: batch \(index + 1)/\(batches.count) complete (\(batch.count) stories)")
        }

        await MainActor.run { self.localCoverFilenames.formUnion(newCoverFilenames) }
    }

    // MARK: - Queue Status Sync

    nonisolated func syncQueueStatus(for stories: [Story], modelContainer: ModelContainer) async {
        let context = ModelContext(modelContainer)

        guard let localStories = try? context.fetch(FetchDescriptor<LocalStory>()) else { return }
        var localByID = Dictionary(uniqueKeysWithValues: localStories.map { ($0.storyID, $0) })

        let pendingQueueIDs: Set<Int> = {
            let ops = (try? context.fetch(FetchDescriptor<PendingOperation>(
                predicate: #Predicate { $0.operationType == "queue" }
            ))) ?? []
            return Set(ops.map { $0.storyID })
        }()

        let pendingRatingIDs: Set<Int> = {
            let ops = (try? context.fetch(FetchDescriptor<PendingOperation>(
                predicate: #Predicate { $0.operationType == "rating" }
            ))) ?? []
            return Set(ops.map { $0.storyID })
        }()

        let isoFormatter = Self.isoFormatter

        var didChange = false

        for (i, story) in stories.enumerated() {
            if i > 0 && i.isMultiple(of: 50) { await Task.yield() }
            if let local = localByID[story.id] {
                if !pendingQueueIDs.contains(story.id) {
                    let newInQueue = story.inQueue ?? false
                    if local.inQueue != newInQueue { local.inQueue = newInQueue; didChange = true }
                    let newQueuedAt = story.queuedAt.flatMap { isoFormatter.date(from: $0) }
                    if local.queuedAt != newQueuedAt { local.queuedAt = newQueuedAt; didChange = true }
                }
                let savedRating = pendingRatingIDs.contains(story.id) ? local.rating : nil
                if local.updateMetadata(from: story) { didChange = true }
                if let saved = savedRating { local.rating = saved }
            } else if story.inQueue == true {
                let record = LocalStory(
                    storyID: story.id,
                    title: story.title,
                    author: story.author,
                    filenameBase: story.filenameBase,
                    coverFilename: story.cover
                )
                record.inQueue = true
                record.updateMetadata(from: story)
                context.insert(record)
                localByID[story.id] = record
                didChange = true
            }
        }

        let serverIDs = Set(stories.map { $0.id })
        for local in localStories where !serverIDs.contains(local.storyID) {
            if local.inQueue { local.inQueue = false; didChange = true }
        }

        if didChange {
            try? context.save()
            print("[LK-Sync] ✓ Queue status sync: changes saved")
        } else {
            print("[LK-Sync] ✓ Queue status sync: no changes")
        }
    }

    // MARK: - Highlights Sync

    nonisolated func syncHighlights(
        serverURL: String,
        token: String,
        proxyTokenId: String,
        proxyToken: String,
        modelContainer: ModelContainer
    ) async {
        guard !serverURL.isEmpty, !token.isEmpty else { return }
        let alreadySyncing = await MainActor.run { self.isSyncingHighlights }
        guard !alreadySyncing else { return }
        await MainActor.run { self.isSyncingHighlights = true }
        defer { Task { @MainActor [self] in self.isSyncingHighlights = false } }

        let ptId = proxyTokenId.isEmpty ? nil : proxyTokenId
        let ptTok = proxyToken.isEmpty ? nil : proxyToken
        let client = APIClient(baseURLString: serverURL, token: token, proxyTokenId: ptId, proxyToken: ptTok)
        let context = ModelContext(modelContainer)

        guard let highlights = try? await client.fetchHighlights() else { return }

        let existing: [LocalHighlight]
        do {
            existing = try context.fetch(FetchDescriptor<LocalHighlight>())
        } catch {
            print("[LK-Sync] ✗ syncHighlights: fetch failed: \(error)")
            return
        }

        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.highlightID, $0) })
        let serverIDs = Set(highlights.map { $0.id })

        for (i, h) in highlights.enumerated() {
            if i > 0 && i.isMultiple(of: 50) { await Task.yield() }
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
                context.insert(local)
            }
        }

        for local in existing where !serverIDs.contains(local.highlightID) {
            context.delete(local)
        }

        try? context.save()
        print("[LK-Sync] ✓ Highlights sync: \(highlights.count) highlights synced")
    }

    // MARK: - Cover Resync (after metadata change)

    nonisolated func resyncCover(storyID: Int, filenameBase: String, serverURL: String, token: String) async {
        guard !serverURL.isEmpty, !token.isEmpty else { return }

        let coverFilename = "\(storyID)_\(filenameBase).jpg"
        let localURL = DownloadManager.shared.localCoverURL(filename: coverFilename)
        try? FileManager.default.removeItem(at: localURL)
        await MainActor.run { self.localCoverFilenames.remove(coverFilename) }

        let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        guard let remoteURL = URL(string: "\(base)/api/story/\(storyID)/cover") else { return }

        var request = URLRequest(url: remoteURL)
        request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return }

        try? data.write(to: localURL, options: .atomic)
        await MainActor.run { self.localCoverFilenames.insert(coverFilename) }
        print("[LK-Sync] ✓ Cover resynced: \(coverFilename)")
    }

    // MARK: - Pending Operations Flush

    nonisolated func flushPendingOperations(
        serverURL: String,
        token: String,
        proxyTokenId: String,
        proxyToken: String,
        modelContainer: ModelContainer
    ) async {
        guard !serverURL.isEmpty, !token.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let pending = (try? context.fetch(FetchDescriptor<PendingOperation>())) ?? []
        guard !pending.isEmpty else { return }

        let ptId = proxyTokenId.isEmpty ? nil : proxyTokenId
        let ptTok = proxyToken.isEmpty ? nil : proxyToken
        let client = APIClient(baseURLString: serverURL, token: token, proxyTokenId: ptId, proxyToken: ptTok)
        var didChange = false

        for op in pending {
            do {
                switch op.operationType {
                case "queue":
                    try await client.updateQueue(storyID: op.storyID, inQueue: op.inQueue ?? false, queuedAt: op.queuedAt)
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
                case "last_opened":
                    if let timestamp = op.lastOpenedAt {
                        try await client.updateLastOpened(storyID: op.storyID, timestamp: timestamp)
                    }
                case "highlight":
                    if let chapter = op.highlightChapterIndex,
                       let paragraph = op.highlightParagraphIndex,
                       let text = op.highlightText {
                        try await client.saveHighlight(
                            storyID: op.storyID,
                            chapterIndex: chapter,
                            paragraphIndex: paragraph,
                            quoteText: text
                        )
                    }
                default:
                    break
                }
                context.delete(op)
                didChange = true
                print("[LK-Sync] ✓ Flushed pending \(op.operationType) op for story \(op.storyID)")
            } catch {
                print("[LK-Sync] ✗ Pending \(op.operationType) op for story \(op.storyID) still offline — will retry")
            }
        }

        if didChange { try? context.save() }
    }

    // MARK: - Metadata Sync

    nonisolated func syncMetadata(
        serverURL: String,
        token: String,
        proxyTokenId: String,
        proxyToken: String,
        modelContainer: ModelContainer
    ) async {
        guard !serverURL.isEmpty, !token.isEmpty else { return }
        let alreadySyncing = await MainActor.run { self.isSyncingMetadata }
        guard !alreadySyncing else { return }
        await MainActor.run { self.isSyncingMetadata = true }
        defer { Task { @MainActor [self] in self.isSyncingMetadata = false } }

        await flushPendingOperations(
            serverURL: serverURL,
            token: token,
            proxyTokenId: proxyTokenId,
            proxyToken: proxyToken,
            modelContainer: modelContainer
        )

        let context = ModelContext(modelContainer)
        let localStories: [LocalStory]
        do {
            localStories = try context.fetch(FetchDescriptor<LocalStory>())
        } catch {
            print("[LK-Sync] ✗ syncMetadata: failed to fetch LocalStory records: \(error)")
            return
        }
        guard !localStories.isEmpty else { return }

        let ptId = proxyTokenId.isEmpty ? nil : proxyTokenId
        let ptTok = proxyToken.isEmpty ? nil : proxyToken
        let client = APIClient(baseURLString: serverURL, token: token, proxyTokenId: ptId, proxyToken: ptTok)
        let ids = localStories.map { $0.storyID }
        let progressMap = await client.fetchAllProgress(storyIDs: ids)
        guard !progressMap.isEmpty else { return }

        let isoFormatter = ISO8601DateFormatter()
        for (i, story) in localStories.enumerated() {
            if i > 0 && i.isMultiple(of: 50) { await Task.yield() }
            guard let p = progressMap[story.storyID] else { continue }

            let serverDate = p.lastReadAt.flatMap { isoFormatter.date(from: $0) }
            let localDate = story.lastReadAt
            let serverIsNewer = serverDate != nil && (localDate == nil || serverDate! > localDate!)

            if let pct = p.percentage {
                if serverIsNewer || story.readingProgressScrollY == nil {
                    story.readingProgressScrollY = pct
                    story.readingProgressPercentage = pct * 100
                }
            }

            if serverIsNewer, let pid = p.paragraphID {
                story.readingProgressParagraphID = pid
                story.lastReadAt = serverDate
            }
        }
        try? context.save()
        print("[LK-Sync] ✓ Metadata sync complete — progress updated for \(progressMap.count) stories")
    }

    // MARK: - Private

    private func populateLocalCoversFromDisk() {
        let t0 = Date()
        let dir = DownloadManager.shared.coversDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        localCoverFilenames = Set(contents)
        print("[LK-STARTUP] populateLocalCoversFromDisk: \(contents.count) files in \(String(format: "%.1f", Date().timeIntervalSince(t0)*1000))ms")
    }
}
