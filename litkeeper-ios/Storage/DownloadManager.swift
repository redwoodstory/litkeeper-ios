import Foundation
import SwiftData

final class DownloadManager {
    static let shared = DownloadManager()
    private init() { ensureDirectories() }

    // MARK: - Directories

    private var baseDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LitKeeper/stories")
    }

    var epubDirectory: URL { baseDirectory.appendingPathComponent("epubs") }
    var htmlDirectory: URL { baseDirectory.appendingPathComponent("html") }
    var coversDirectory: URL { baseDirectory.appendingPathComponent("covers") }

    private func ensureDirectories() {
        for dir in [epubDirectory, htmlDirectory, coversDirectory] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - URL helpers

    func localEPUBURL(filenameBase: String) -> URL {
        epubDirectory.appendingPathComponent("\(filenameBase).epub")
    }

    func localHTMLURL(filenameBase: String) -> URL {
        htmlDirectory.appendingPathComponent("\(filenameBase).json")
    }

    func localCoverURL(filename: String) -> URL {
        coversDirectory.appendingPathComponent(filename)
    }

    func epubExists(filenameBase: String) -> Bool {
        FileManager.default.fileExists(atPath: localEPUBURL(filenameBase: filenameBase).path)
    }

    func htmlExists(filenameBase: String) -> Bool {
        FileManager.default.fileExists(atPath: localHTMLURL(filenameBase: filenameBase).path)
    }

    // MARK: - Download

    /// Downloads a story's files to local storage and creates/updates a LocalStory record.
    /// - Parameters:
    ///   - story: The story to download.
    ///   - serverBaseURL: The configured server base URL string.
    ///   - token: The API bearer token.
    ///   - modelContext: SwiftData context (must be called from the main actor).
    ///   - onProgress: Reports (fraction 0–1, description).
    @MainActor
    func downloadStory(
        story: Story,
        serverBaseURL: String,
        token: String,
        pangolinTokenId: String? = nil,
        pangolinToken: String? = nil,
        modelContext: ModelContext,
        onProgress: @escaping (Double, String) -> Void
    ) async throws {
        let base = URL(string: serverBaseURL.hasSuffix("/") ? String(serverBaseURL.dropLast()) : serverBaseURL)
            ?? URL(string: "http://localhost:5017")!

        var epubPath: String? = nil
        var htmlPath: String? = nil
        var coverPath: String? = nil

        // 1. EPUB
        if story.hasEPUB {
            onProgress(0.0, "Downloading EPUB…")
            let url = base.appendingPathComponent("epub/file/\(story.id)")
            let dest = localEPUBURL(filenameBase: story.filenameBase)
            try await downloadFile(from: url, token: token, pangolinTokenId: pangolinTokenId, pangolinToken: pangolinToken, to: dest)
            epubPath = "\(story.filenameBase).epub"
            onProgress(0.5, "EPUB saved")
        }

        // 2. HTML
        if story.hasHTML {
            onProgress(story.hasEPUB ? 0.5 : 0.0, "Downloading HTML…")
            let url = base.appendingPathComponent("download/\(story.filenameBase).json")
            let dest = localHTMLURL(filenameBase: story.filenameBase)
            try await downloadFile(from: url, token: token, pangolinTokenId: pangolinTokenId, pangolinToken: pangolinToken, to: dest)
            htmlPath = "\(story.filenameBase).json"
            onProgress(0.85, "HTML saved")
        }

        // 3. Cover — use story.cover if set, fall back to filenameBase.jpg (same
        //    logic as coverURL and syncCovers so all three paths stay consistent).
        let coverFilename = story.cover ?? "\(story.filenameBase).jpg"
        onProgress(0.85, "Downloading cover…")
        let coverRemoteURL = base.appendingPathComponent("api/cover/\(coverFilename)")
        let coverDest = localCoverURL(filename: coverFilename)
        try? await downloadFile(from: coverRemoteURL, token: token, pangolinTokenId: pangolinTokenId, pangolinToken: pangolinToken, to: coverDest)
        coverPath = coverFilename

        // 4. Persist to SwiftData
        let storyID = story.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<LocalStory>(predicate: #Predicate { $0.storyID == storyID })
        ).first
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
        if existing == nil { modelContext.insert(record) }
        try? modelContext.save()

        onProgress(1.0, "Done")
    }

    private func downloadFile(from url: URL, token: String, pangolinTokenId: String? = nil, pangolinToken: String? = nil, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let id = pangolinTokenId { request.setValue(id, forHTTPHeaderField: "P-Access-Token-Id") }
        if let tok = pangolinToken { request.setValue(tok, forHTTPHeaderField: "P-Access-Token") }
        request.timeoutInterval = 120

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    // MARK: - Delete

    func deleteLocalFiles(for story: LocalStory) throws {
        if let path = story.epubLocalPath {
            try? FileManager.default.removeItem(at: epubDirectory.appendingPathComponent(path))
        }
        if let path = story.htmlLocalPath {
            try? FileManager.default.removeItem(at: htmlDirectory.appendingPathComponent(path))
        }
        if let path = story.coverLocalPath {
            try? FileManager.default.removeItem(at: coversDirectory.appendingPathComponent(path))
        }
    }

    // MARK: - Storage

    func totalStorageUsed() -> Int64 {
        var total: Int64 = 0
        for dir in [epubDirectory, htmlDirectory, coversDirectory] {
            guard let enumerator = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Integrity check

    func pruneStaleRecords(modelContext: ModelContext) {
        guard let records = try? modelContext.fetch(FetchDescriptor<LocalStory>()) else { return }
        for record in records {
            if let path = record.epubLocalPath,
               !FileManager.default.fileExists(atPath: epubDirectory.appendingPathComponent(path).path) {
                record.epubLocalPath = nil
            }
            if let path = record.htmlLocalPath,
               !FileManager.default.fileExists(atPath: htmlDirectory.appendingPathComponent(path).path) {
                record.htmlLocalPath = nil
            }
            if record.epubLocalPath == nil && record.htmlLocalPath == nil {
                modelContext.delete(record)
            }
        }
        try? modelContext.save()
    }
}
