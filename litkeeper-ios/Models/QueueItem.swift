import Foundation

struct QueueItem: Identifiable, Codable, Equatable {
    let id: Int
    var url: String
    var status: QueueStatus
    var title: String?
    var author: String?
    var jobType: String?
    var totalPages: Int?
    var downloadedPages: Int?
    var errorMessage: String?
    var createdAt: String?
    var completedAt: String?

    enum QueueStatus: String, Codable, Equatable {
        case pending, processing, completed, failed
        case rateLimited = "rate_limited"
        case skipped
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            self = QueueStatus(rawValue: value) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, url, status, title, author
        case jobType = "job_type"
        case totalPages = "total_pages"
        case downloadedPages = "downloaded_pages"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    var progress: Double {
        guard let total = totalPages, total > 0, let downloaded = downloadedPages else { return 0 }
        return Double(downloaded) / Double(total)
    }
}

struct QueueStats: Codable {
    let pending: Int
    let processing: Int
    let completed: Int
    let failed: Int
}

struct QueueResponse: Codable {
    let items: [QueueItem]?
    // The endpoint returns grouped items; we parse them flat
}
