import Foundation

struct BrowseStory: Codable, Identifiable {
    var id: String { url }
    let url: String
    let title: String
    let score: String?
    let voteCount: String?
    let readCount: String?
    let dateApprove: String?
    let description: String?
    let authorName: String?
    let authorURL: String?
    let category: String?
    let isSeries: Bool?
    let chapterCount: Int?
    let inLibrary: Bool
    let isQueued: Bool

    enum CodingKeys: String, CodingKey {
        case url, title, score, description, category
        case voteCount = "vote_count"
        case readCount = "read_count"
        case dateApprove = "date_approve"
        case authorName = "author_name"
        case authorURL = "author_url"
        case isSeries = "is_series"
        case chapterCount = "chapter_count"
        case inLibrary = "in_library"
        case isQueued = "is_queued"
    }
}

struct BrowseResult: Codable {
    let success: Bool
    let stories: [BrowseStory]
    let page: Int?
    let totalPages: Int?
    let totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case success, stories, page
        case totalPages = "total_pages"
        case totalCount = "total_count"
    }
}

struct BrowseCategory: Codable, Identifiable {
    var id: String { slug }
    let slug: String
    let label: String
}
