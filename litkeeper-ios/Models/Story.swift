import Foundation

struct Story: Identifiable, Codable, Hashable {
    let id: Int
    var title: String
    var author: String
    var authorURL: String?
    var category: String?
    var tags: [String]
    var cover: String?
    var filenameBase: String
    var formats: [String]
    var sourceURL: String?
    var wordCount: Int?
    var chapterCount: Int?
    var rating: Int?
    var inQueue: Bool
    var description: String?
    var dateAdded: String?

    enum CodingKeys: String, CodingKey {
        case id, title, author, category, tags, cover, formats, description, rating
        case authorURL = "author_url"
        case filenameBase = "filename_base"
        case sourceURL = "source_url"
        case wordCount = "word_count"
        case chapterCount = "chapter_count"
        case inQueue = "in_queue"
        case dateAdded = "date_added"
    }

    // Computed helpers
    var hasEPUB: Bool { formats.contains("epub") }
    // Server stores this format as "json" (the file is a JSON document rendered to HTML for reading)
    var hasHTML: Bool { formats.contains("html") || formats.contains("json") }
}

struct LibraryResponse: Codable {
    let stories: [Story]
}
