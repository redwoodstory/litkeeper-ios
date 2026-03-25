import Foundation

struct Highlight: Identifiable, Codable {
    let id: Int
    let storyId: Int
    let storyTitle: String
    let storyAuthor: String
    let filenameBase: String
    let chapterIndex: Int
    let paragraphIndex: Int
    let quoteText: String
    let note: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, note
        case storyId = "story_id"
        case storyTitle = "story_title"
        case storyAuthor = "story_author"
        case filenameBase = "filename_base"
        case chapterIndex = "chapter_index"
        case paragraphIndex = "paragraph_index"
        case quoteText = "quote_text"
        case createdAt = "created_at"
    }
}

struct HighlightsResponse: Codable {
    let highlights: [Highlight]
}
