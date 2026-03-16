import Foundation

actor APIClient {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    init(baseURLString: String, token: String) {
        // Normalize: strip trailing slash
        let cleaned = baseURLString.hasSuffix("/")
            ? String(baseURLString.dropLast())
            : baseURLString
        self.baseURL = URL(string: cleaned) ?? URL(string: "http://localhost:5017")!
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
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
        return all
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

    func updateQueue(storyID: Int, inQueue: Bool) async throws {
        _ = try await post("/api/story/\(storyID)/queue", body: ["in_queue": inQueue])
    }

    func deleteStory(storyID: Int) async throws {
        _ = try await delete("/api/story/delete/\(storyID)")
    }

    func updateMetadata(storyID: Int, title: String, author: String, category: String?, description: String?) async throws {
        var body: [String: Any] = ["title": title, "author": author]
        if let cat = category { body["category"] = cat }
        if let desc = description { body["description"] = desc }
        _ = try await put("/api/story/\(storyID)/metadata", body: body)
    }

    // MARK: - Reading Progress

    func fetchProgress(storyID: Int) async throws -> ReadingProgress {
        let data = try await get("/epub/api/progress/\(storyID)")
        return try decode(ReadingProgress.self, from: data)
    }

    func saveProgress(storyID: Int, progress: ReadingProgress) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = try encoder.encode(progress)
        _ = try await postData("/epub/api/progress/\(storyID)", body: body, contentType: "application/json")
    }

    // MARK: - Cover Image URL

    func coverURL(filename: String) -> URL {
        baseURL.appendingPathComponent("api/cover/\(filename)")
    }

    // MARK: - Download URLs (for DownloadManager)

    func epubDownloadURL(storyID: Int) -> URL {
        baseURL.appendingPathComponent("epub/file/\(storyID)")
    }

    func htmlDownloadURL(filename: String) -> URL {
        baseURL.appendingPathComponent("download/html/\(filename)")
    }

    func coverDownloadURL(filename: String) -> URL {
        baseURL.appendingPathComponent("api/cover/\(filename)")
    }

    // MARK: - Connection Test

    func testConnection() async throws {
        _ = try await get("/api/library")
    }

    // MARK: - Private HTTP helpers

    private func request(for path: String, method: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(String(path.dropFirst()))  // drop leading /
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
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
        let path = request.url?.path ?? "?"
        let start = Date()
        print("[LK-API] → \(method) \(path)")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
            switch http.statusCode {
            case 200...299:
                print("[LK-API] ← \(http.statusCode) \(path) (\(elapsed), \(data.count)B)")
                return data
            case 401:
                print("[LK-API] ✗ 401 Unauthorized \(path)")
                throw APIError.unauthorized
            case 404:
                print("[LK-API] ✗ 404 Not Found \(path)")
                throw APIError.notFound
            default:
                print("[LK-API] ✗ \(http.statusCode) Server Error \(path)")
                throw APIError.serverError(http.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch {
            print("[LK-API] ✗ Network error on \(path): \(error.localizedDescription)")
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
