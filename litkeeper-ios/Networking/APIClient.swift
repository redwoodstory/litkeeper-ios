import Foundation

actor APIClient {
    private let baseURL: URL
    private let token: String
    private let proxyTokenId: String?
    private let proxyToken: String?
    private let session: URLSession

    init(baseURLString: String, token: String, proxyTokenId: String? = nil, proxyToken: String? = nil) {
        // Normalize: strip trailing slash
        let cleaned = baseURLString.hasSuffix("/")
            ? String(baseURLString.dropLast())
            : baseURLString
        // Prepend https:// when no scheme is provided (e.g. user typed "myserver.local:5017")
        let schemed: String
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
            schemed = cleaned
        } else if cleaned.isEmpty {
            schemed = cleaned
        } else {
            schemed = "https://" + cleaned
        }
        self.baseURL = URL(string: schemed) ?? URL(string: "https://localhost:5017")!
        self.token = token
        self.proxyTokenId = proxyTokenId
        self.proxyToken = proxyToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        self.session = URLSession(configuration: config)
    }

    // MARK: - Library

    func fetchLibrary() async throws -> [Story] {
        let data = try await get("/api/library")
        let response = try decode(LibraryResponse.self, from: data)
        for story in response.stories {
            print("[LK-iOS] Story '\(story.title)' (id=\(story.id)) tags=\(story.tags)")
        }
        return response.stories
    }

    // MARK: - Queue

    func queueDownload(url storyURL: String) async throws -> QueueItem {
        var body: [String: Any] = ["url": storyURL]
        let data = try await post("/api/queue", body: body)
        // Response wraps queue_item
        struct QueueResponse: Codable {
            let queueItem: QueueItem?
            let success: Bool?
            let message: String?
            enum CodingKeys: String, CodingKey {
                case queueItem = "queue_item"
                case success, message
            }
        }
        let response = try decode(QueueResponse.self, from: data)
        guard let item = response.queueItem else {
            throw APIError.serverError(0)
        }
        return item
    }

    func fetchQueueItems() async throws -> [QueueItem] {
        let data = try await get("/queue/api/items")
        // Returns {pending: [...], processing: [...], completed: [...], failed: [...]}
        struct GroupedQueue: Codable {
            let pending: [QueueItem]?
            let processing: [QueueItem]?
            let completed: [QueueItem]?
            let failed: [QueueItem]?
        }
        let grouped = try decode(GroupedQueue.self, from: data)
        var all: [QueueItem] = []
        if let items = grouped.processing { all += items }
        if let items = grouped.pending { all += items }
        if let items = grouped.completed { all += Array(items.prefix(20)) }
        if let items = grouped.failed { all += items }
        return all.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    func fetchQueueStats() async throws -> QueueStats {
        let data = try await get("/queue/api/stats")
        return try decode(QueueStats.self, from: data)
    }

    func cancelQueueItem(id: Int) async throws {
        _ = try await delete("/api/queue/\(id)")
    }

    // MARK: - Story

    func updateRating(storyID: Int, rating: Int) async throws {
        _ = try await post("/api/story/\(storyID)/rating", body: ["rating": rating])
    }

    func updateQueue(storyID: Int, inQueue: Bool, queuedAt: Date? = nil) async throws {
        var body: [String: Any] = ["in_queue": inQueue]
        if let queuedAt = queuedAt {
            let isoFormatter = ISO8601DateFormatter()
            body["queued_at"] = isoFormatter.string(from: queuedAt)
        }
        _ = try await post("/api/story/\(storyID)/queue", body: body)
    }

    func deleteStory(storyID: Int) async throws {
        _ = try await delete("/api/story/delete/\(storyID)")
    }
    
    func updateLastOpened(storyID: Int, timestamp: Date) async throws {
        let isoFormatter = ISO8601DateFormatter()
        _ = try await post("/api/story/\(storyID)/last_opened", body: ["last_opened_at": isoFormatter.string(from: timestamp)])
    }

    func updateMetadata(storyID: Int, title: String, author: String, category: String?, description: String?, tags: [String]) async throws -> Bool {
        var body: [String: Any] = ["title": title, "author": author, "tags": tags]
        if let cat = category { body["category"] = cat }
        if let desc = description { body["description"] = desc }
        let data = try await put("/api/story/\(storyID)/metadata", body: body)
        struct Response: Decodable {
            let coverRegenerated: Bool
            enum CodingKeys: String, CodingKey { case coverRegenerated = "cover_regenerated" }
        }
        return (try? decode(Response.self, from: data))?.coverRegenerated ?? false
    }

    // MARK: - Reading Progress

    func fetchProgress(storyID: Int) async throws -> ReadingProgress {
        let data = try await get("/epub/api/progress/\(storyID)")
        return try decode(ReadingProgress.self, from: data)
    }

    func fetchAllProgress(storyIDs: [Int]) async -> [Int: ReadingProgress] {
        guard !storyIDs.isEmpty else { return [:] }
        let ids = storyIDs.map(String.init).joined(separator: ",")
        guard let data = try? await get("/epub/api/progress/bulk?ids=\(ids)") else { return [:] }
        struct BulkResponse: Codable {
            let progress: [String: ReadingProgress]
        }
        guard let response = try? decode(BulkResponse.self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: response.progress.compactMap { key, value in
            guard let id = Int(key) else { return nil }
            return (id, value)
        })
    }

    func fetchBulkContent(storyIDs: [Int]) async -> BulkContentResponse? {
        guard !storyIDs.isEmpty else { return nil }
        let ids = storyIDs.map(String.init).joined(separator: ",")
        guard let data = try? await get("/api/download/bulk?ids=\(ids)") else { return nil }
        return try? decode(BulkContentResponse.self, from: data)
    }

    func saveProgress(storyID: Int, progress: ReadingProgress) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = try encoder.encode(progress)
        _ = try await postData("/epub/api/progress/\(storyID)", body: body, contentType: "application/json")
    }

    // MARK: - Cover Image URL

    func coverURL(storyID: Int) -> URL {
        baseURL.appendingPathComponent("api/story/\(storyID)/cover")
    }

    // MARK: - Download URLs (for DownloadManager)

    func epubDownloadURL(storyID: Int) -> URL {
        baseURL.appendingPathComponent("epub/file/\(storyID)")
    }

    func htmlDownloadURL(filename: String) -> URL {
        baseURL.appendingPathComponent("download/html/\(filename)")
    }

    func coverDownloadURL(storyID: Int) -> URL {
        baseURL.appendingPathComponent("api/story/\(storyID)/cover")
    }

    // MARK: - Highlights

    func fetchHighlights() async throws -> [Highlight] {
        let data = try await get("/api/highlights")
        return try decode(HighlightsResponse.self, from: data).highlights
    }

    func saveHighlight(storyID: Int, chapterIndex: Int, paragraphIndex: Int, quoteText: String) async throws {
        let body: [String: Any] = [
            "story_id": storyID,
            "chapter_index": chapterIndex,
            "paragraph_index": paragraphIndex,
            "quote_text": quoteText
        ]
        _ = try await post("/api/highlights", body: body)
    }

    func deleteHighlight(id: Int) async throws {
        _ = try await delete("/api/highlights/\(id)")
    }

    // MARK: - Authors

    func fetchAuthors() async throws -> [Author] {
        let data = try await get("/api/authors")
        return try decode(AuthorsResponse.self, from: data).authors
    }

    func queueAuthorDownload(authorURL: String) async throws -> QueueItem {
        let data = try await post("/api/queue/author", body: ["author_url": authorURL])
        struct Resp: Codable {
            let queueItem: QueueItem?
            let success: Bool?
            let message: String?
            enum CodingKeys: String, CodingKey {
                case queueItem = "queue_item"
                case success, message
            }
        }
        let resp = try decode(Resp.self, from: data)
        guard let item = resp.queueItem else { throw APIError.serverError(0) }
        return item
    }

    func toggleAuthorWatch(authorID: Int) async throws -> Bool {
        let data = try await post("/api/authors/\(authorID)/toggle-watch", body: [:])
        struct Resp: Codable {
            let watchEnabled: Bool
            enum CodingKeys: String, CodingKey { case watchEnabled = "watch_enabled" }
        }
        return try decode(Resp.self, from: data).watchEnabled
    }

    func rescanAuthor(authorID: Int) async throws {
        _ = try await post("/api/authors/\(authorID)/rescan", body: [:])
    }

    // MARK: - Server Settings

    func fetchAutoUpdateEnabled() async throws -> Bool {
        let data = try await get("/api/settings/auto-update-enabled")
        struct Resp: Codable { let enabled: Bool }
        return try decode(Resp.self, from: data).enabled
    }

    func setAutoUpdateEnabled(_ enabled: Bool) async throws -> Bool {
        let data = try await post("/api/settings/toggle-auto-update", body: ["enabled": enabled])
        struct Resp: Codable { let enabled: Bool }
        return try decode(Resp.self, from: data).enabled
    }

    func fetchAutoWatchEnabled() async throws -> Bool {
        let data = try await get("/api/settings/auto-watch-enabled")
        struct Resp: Codable { let enabled: Bool }
        return try decode(Resp.self, from: data).enabled
    }

    func setAutoWatchEnabled(_ enabled: Bool) async throws -> Bool {
        let data = try await post("/api/settings/toggle-auto-watch", body: ["enabled": enabled])
        struct Resp: Codable { let enabled: Bool }
        return try decode(Resp.self, from: data).enabled
    }

    func toggleStoryAutoUpdate(storyID: Int) async throws -> Bool {
        let data = try await post("/api/story/\(storyID)/toggle-auto-update", body: [:])
        struct Resp: Codable {
            let autoUpdateEnabled: Bool
            enum CodingKeys: String, CodingKey { case autoUpdateEnabled = "auto_update_enabled" }
        }
        return try decode(Resp.self, from: data).autoUpdateEnabled
    }

    // MARK: - Metadata / Link Story

    struct MetadataSearchResult: Codable, Identifiable {
        var id: String { url }
        let title: String
        let author: String
        let url: String
        let confidence: Double
        let category: String?
    }

    struct MetadataSearchResponse: Codable {
        let success: Bool
        let results: [MetadataSearchResult]?
        let bestMatch: MetadataSearchResult?
        let autoMatch: Bool?
        let message: String?
        enum CodingKeys: String, CodingKey {
            case success, results, message
            case bestMatch = "best_match"
            case autoMatch = "auto_match"
        }
    }

    func searchStoryMetadata(storyID: Int) async throws -> MetadataSearchResponse {
        let data = try await post("/api/metadata/search/\(storyID)", body: [:])
        return try decode(MetadataSearchResponse.self, from: data)
    }

    func refreshStoryMetadata(storyID: Int, url: String, method: String) async throws -> Story {
        let data = try await post("/api/metadata/refresh/\(storyID)", body: ["url": url, "method": method])
        struct Resp: Codable {
            let success: Bool
            let story: Story
            let message: String?
        }
        let resp = try decode(Resp.self, from: data)
        guard resp.success else {
            throw APIError.serverError(0)
        }
        return resp.story
    }

    // MARK: - Excluded Stories

    func fetchExcludedStories() async throws -> [Story] {
        let data = try await get("/api/stories/excluded")
        struct Response: Codable {
            let success: Bool
            let stories: [Story]
        }
        let response = try decode(Response.self, from: data)
        return response.stories
    }

    func resetAllExclusions() async throws -> Int {
        let data = try await post("/api/stories/excluded/reset", body: [:])
        struct Response: Codable {
            let success: Bool
            let count: Int
        }
        let response = try decode(Response.self, from: data)
        return response.count
    }

    func toggleStoryExclusion(storyID: Int, excluded: Bool) async throws -> Story {
        let data = try await post("/api/story/\(storyID)/toggle-exclusion", body: ["excluded": excluded])
        struct Response: Codable {
            let success: Bool
            let story: Story
        }
        let response = try decode(Response.self, from: data)
        return response.story
    }

    // MARK: - Browse

    func fetchBrowseCategories() async throws -> [BrowseCategory] {
        let data = try await get("/api/browse/categories")
        struct Response: Codable {
            let success: Bool
            let categories: [BrowseCategory]
        }
        return try decode(Response.self, from: data).categories
    }

    func browseByCategory(category: String, sort: String, page: Int) async throws -> BrowseResult {
        let path = queryPath("/api/browse/category", params: [
            ("category", category), ("sort", sort), ("page", "\(page)")
        ])
        return try decode(BrowseResult.self, from: try await get(path))
    }

    func browseGlobal(mode: String, page: Int) async throws -> BrowseResult {
        let path = queryPath("/api/browse/global", params: [
            ("mode", mode), ("page", "\(page)")
        ])
        return try decode(BrowseResult.self, from: try await get(path))
    }

    func fetchCustomListCategories() async throws -> [String] {
        let data = try await get("/api/browse/custom_list/categories")
        struct Response: Codable {
            let success: Bool
            let categories: [String]
        }
        return try decode(Response.self, from: data).categories
    }

    func browseCustomList(
        category: String, sort: String, page: Int,
        minScore: Double, minViews: Int, minFaves: Int, series: String, dateRange: String
    ) async throws -> BrowseResult {
        let path = queryPath("/api/browse/custom_list", params: [
            ("category", category),
            ("sort", sort),
            ("page", "\(page)"),
            ("min_score", String(format: "%.1f", minScore)),
            ("min_views", "\(minViews)"),
            ("min_faves", "\(minFaves)"),
            ("series", series),
            ("date_range", dateRange)
        ])
        print("[browseCustomList] URL: \(path)")
        let data = try await get(path)
        let result = try decode(BrowseResult.self, from: data)
        let lowFaves = result.stories.filter { s in
            if let v = s.voteCount, let n = Int(v) { return n < minFaves }
            return minFaves > 0
        }
        if !lowFaves.isEmpty {
            print("[browseCustomList] WARNING: \(lowFaves.count) stories returned with faves below min_faves=\(minFaves):")
            for s in lowFaves.prefix(5) {
                print("  - \"\(s.title)\" voteCount=\(s.voteCount ?? "nil")")
            }
        } else {
            print("[browseCustomList] OK: all \(result.stories.count) stories have faves >= \(minFaves)")
        }
        return result
    }

    func queueBrowseStories(urls: [String]) async throws {
        _ = try await post("/api/browse/queue-stories", body: ["story_urls": urls])
    }

    // MARK: - Connection Test

    func testConnection() async throws {
        let data = try await get("/api/library")
        // Reject HTML responses — proxy auth pages return 200 HTML when the proxy token is missing/wrong
        if let first = data.first, first == UInt8(ascii: "<") {
            print("[LK-API] ✗ testConnection: got HTML response, not JSON — proxy auth page?")
            throw APIError.proxyAuthRequired
        }
    }

    // MARK: - Private HTTP helpers

    private func request(for path: String, method: String) -> URLRequest {
        let url = URL(string: baseURL.absoluteString + path) ?? baseURL
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(token, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let tokenId = proxyTokenId, let tok = proxyToken {
            req.setValue(tokenId, forHTTPHeaderField: "P-Access-Token-Id")
            req.setValue(tok, forHTTPHeaderField: "P-Access-Token")
        }
        return req
    }

    private func queryPath(_ base: String, params: [(String, String)]) -> String {
        guard !params.isEmpty else { return base }
        let query = params.map { k, v in
            let enc = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(k)=\(enc)"
        }.joined(separator: "&")
        return "\(base)?\(query)"
    }

    private func get(_ path: String) async throws -> Data {
        let req = request(for: path, method: "GET")
        return try await perform(req)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var req = request(for: path, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(req)
    }

    private func postData(_ path: String, body: Data, contentType: String) async throws -> Data {
        var req = request(for: path, method: "POST")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return try await perform(req)
    }

    private func put(_ path: String, body: [String: Any]) async throws -> Data {
        var req = request(for: path, method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(req)
    }

    private func delete(_ path: String) async throws -> Data {
        let req = request(for: path, method: "DELETE")
        return try await perform(req)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let fullURL = request.url?.absoluteString ?? "?"
        let start = Date()

        print("[LK-API] → \(method) \(fullURL)")
        if let tokenId = proxyTokenId, let tok = proxyToken {
            print("[LK-API]   P-Access-Token-Id: \(tokenId) / P-Access-Token: …\(tok.suffix(4)) (\(tok.count) chars)")
        } else {
            print("[LK-API]   P-Access-Token: (not configured)")
        }

        // Preserve auth headers across redirects — URLSession strips custom headers by default,
        // which causes a 403 on any HTTP redirect through a proxy.
        var authHeaders: [String: String] = [
            "X-Api-Key": token,
            "Accept": "application/json"
        ]
        if let tokenId = proxyTokenId, let tok = proxyToken {
            authHeaders["P-Access-Token-Id"] = tokenId
            authHeaders["P-Access-Token"] = tok
        }
        let redirectDelegate = HeaderPreservingDelegate(headers: authHeaders)

        do {
            let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
            switch http.statusCode {
            case 200...299:
                let responseURL = http.url?.absoluteString ?? fullURL
                if responseURL != fullURL {
                    print("[LK-API] ← \(http.statusCode) \(responseURL) [redirected from \(fullURL)] (\(elapsed), \(data.count)B)")
                } else {
                    print("[LK-API] ← \(http.statusCode) \(fullURL) (\(elapsed), \(data.count)B)")
                }
                return data
            case 401:
                print("[LK-API] ✗ 401 \(http.url?.absoluteString ?? fullURL)")
                if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                    print("[LK-API]   Response body: \(body.prefix(500))")
                }
                throw APIError.unauthorized
            case 404:
                print("[LK-API] ✗ 404 \(http.url?.absoluteString ?? fullURL)")
                throw APIError.notFound
            default:
                print("[LK-API] ✗ \(http.statusCode) \(http.url?.absoluteString ?? fullURL) (\(elapsed))")
                if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                    print("[LK-API]   Response body: \(body.prefix(500))")
                }
                throw APIError.serverError(http.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch {
            print("[LK-API] ✗ Network error on \(fullURL): \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            print("[LK-API] ✗ Decode error for \(T.self): \(error)")
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Bulk Content Response

struct BulkContentStory: Codable {
    let epub: String?
    let epubFilename: String?
    let html: String?
    let htmlFilename: String?
    let cover: String?
    let coverFilename: String?

    enum CodingKeys: String, CodingKey {
        case epub
        case epubFilename = "epub_filename"
        case html
        case htmlFilename = "html_filename"
        case cover
        case coverFilename = "cover_filename"
    }
}

struct BulkContentResponse: Codable {
    let stories: [String: BulkContentStory]
}

// Preserves custom auth headers when URLSession follows HTTP redirects.
// URLSession strips non-standard headers on redirect by default, which causes a 403
// when a reverse proxy re-checks auth on the redirected request.
private final class HeaderPreservingDelegate: NSObject, URLSessionTaskDelegate {
    private let headers: [String: String]

    init(headers: [String: String]) {
        self.headers = headers
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var newReq = request
        for (key, value) in headers {
            newReq.setValue(value, forHTTPHeaderField: key)
        }
        print("[LK-API] ↪ Redirect \(response.statusCode) → \(request.url?.absoluteString ?? "?") (re-adding \(headers.count) headers)")
        completionHandler(newReq)
    }
}
