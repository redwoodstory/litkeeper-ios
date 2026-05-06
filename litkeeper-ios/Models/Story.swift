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
    var pageCount: Int?
    var size: Int?
    var rating: Int?
    var inQueue: Bool
    var queuedAt: String?
    var lastOpenedAt: String?
    var description: String?
    var dateAdded: String?
    var updatedAt: String?
    var autoUpdateEnabled: Bool
    var autoRefreshExcluded: Bool
    var autoRefreshExclusionReason: String?
    var autoRefreshExclusionType: String?

    enum CodingKeys: String, CodingKey {
        case id, title, author, category, tags, cover, formats, description, rating, size
        case authorURL = "author_url"
        case filenameBase = "filename_base"
        case sourceURL = "source_url"
        case wordCount = "word_count"
        case chapterCount = "chapter_count"
        case pageCount = "page_count"
        case inQueue = "in_queue"
        case queuedAt = "queued_at"
        case lastOpenedAt = "last_opened_at"
        case dateAdded = "date_added"
        case updatedAt = "updated_at"
        case autoUpdateEnabled = "auto_update_enabled"
        case autoRefreshExcluded = "auto_refresh_excluded"
        case autoRefreshExclusionReason = "auto_refresh_exclusion_reason"
        case autoRefreshExclusionType = "auto_refresh_exclusion_type"
    }

    init(id: Int, title: String, author: String, authorURL: String? = nil, category: String? = nil,
         tags: [String], cover: String? = nil, filenameBase: String, formats: [String],
         sourceURL: String? = nil, wordCount: Int? = nil, chapterCount: Int? = nil,
         pageCount: Int? = nil, size: Int? = nil, rating: Int? = nil, inQueue: Bool,
         queuedAt: String? = nil, lastOpenedAt: String? = nil, description: String? = nil,
         dateAdded: String? = nil, updatedAt: String? = nil,
         autoUpdateEnabled: Bool = true,
         autoRefreshExcluded: Bool = false,
         autoRefreshExclusionReason: String? = nil,
         autoRefreshExclusionType: String? = nil) {
        self.id           = id
        self.title        = title
        self.author       = author
        self.authorURL    = authorURL
        self.category     = category
        self.tags         = tags
        self.cover        = cover
        self.filenameBase = filenameBase
        self.formats      = formats
        self.sourceURL    = sourceURL
        self.wordCount    = wordCount
        self.chapterCount = chapterCount
        self.pageCount    = pageCount
        self.size         = size
        self.rating       = rating
        self.inQueue      = inQueue
        self.queuedAt     = queuedAt
        self.lastOpenedAt = lastOpenedAt
        self.description  = description
        self.dateAdded    = dateAdded
        self.updatedAt    = updatedAt
        self.autoUpdateEnabled = autoUpdateEnabled
        self.autoRefreshExcluded = autoRefreshExcluded
        self.autoRefreshExclusionReason = autoRefreshExclusionReason
        self.autoRefreshExclusionType = autoRefreshExclusionType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(Int.self,     forKey: .id)
        title        = try c.decode(String.self,  forKey: .title).decodingHTMLEntities()
        author       = try c.decode(String.self,  forKey: .author).decodingHTMLEntities()
        authorURL    = try c.decodeIfPresent(String.self,   forKey: .authorURL)
        category     = try c.decodeIfPresent(String.self,   forKey: .category)
        tags         = try c.decode([String].self,           forKey: .tags)
        cover        = try c.decodeIfPresent(String.self,   forKey: .cover)
        filenameBase = try c.decode(String.self,  forKey: .filenameBase)
        formats      = try c.decode([String].self,           forKey: .formats)
        sourceURL    = try c.decodeIfPresent(String.self,   forKey: .sourceURL)
        wordCount    = try c.decodeIfPresent(Int.self,      forKey: .wordCount)
        chapterCount = try c.decodeIfPresent(Int.self,      forKey: .chapterCount)
        pageCount    = try c.decodeIfPresent(Int.self,      forKey: .pageCount)
        size         = try c.decodeIfPresent(Int.self,      forKey: .size)
        rating       = try c.decodeIfPresent(Int.self,      forKey: .rating)
        inQueue      = try c.decode(Bool.self,    forKey: .inQueue)
        queuedAt     = try c.decodeIfPresent(String.self,   forKey: .queuedAt)
        lastOpenedAt = try c.decodeIfPresent(String.self,   forKey: .lastOpenedAt)
        description  = try c.decodeIfPresent(String.self,   forKey: .description)
        dateAdded    = try c.decodeIfPresent(String.self,   forKey: .dateAdded)
        updatedAt    = try c.decodeIfPresent(String.self,   forKey: .updatedAt)
        autoUpdateEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateEnabled) ?? true
        autoRefreshExcluded = try c.decodeIfPresent(Bool.self, forKey: .autoRefreshExcluded) ?? false
        autoRefreshExclusionReason = try c.decodeIfPresent(String.self, forKey: .autoRefreshExclusionReason)
        autoRefreshExclusionType = try c.decodeIfPresent(String.self, forKey: .autoRefreshExclusionType)
    }

    // Computed helpers
    var hasEPUB: Bool { formats.contains("epub") }
    // Server stores this format as "json" (the file is a JSON document rendered to HTML for reading)
    var hasHTML: Bool { formats.contains("html") || formats.contains("json") }
}

struct LibraryResponse: Codable {
    let stories: [Story]
}
