import Foundation
import SwiftData

@Model
final class LocalStory {
    var storyID: Int
    var title: String
    var author: String
    var filenameBase: String
    var coverFilename: String?
    var epubLocalPath: String?    // relative to Documents/LitKeeper/stories/epubs/
    var htmlLocalPath: String?    // relative to Documents/LitKeeper/stories/html/
    var coverLocalPath: String?   // relative to Documents/LitKeeper/stories/covers/
    var inQueue: Bool = false
    var downloadedAt: Date
    var serverUpdatedAt: Date?
    var lastReadAt: Date?
    var readingProgressCFI: String?
    var readingProgressLocator: String?
    var readingProgressPercentage: Double?
    var readingProgressScrollY: Double?
    var readingProgressParagraphID: String?

    // Cached server metadata — populated on sync so these are available offline
    var authorURL: String?
    var category: String?
    var tags: [String] = []
    var sourceURL: String?
    var wordCount: Int?
    var chapterCount: Int?
    var pageCount: Int?
    var size: Int?
    var rating: Int?
    var storyDescription: String?

    init(
        storyID: Int,
        title: String,
        author: String,
        filenameBase: String,
        coverFilename: String? = nil
    ) {
        self.storyID = storyID
        self.title = title
        self.author = author
        self.filenameBase = filenameBase
        self.coverFilename = coverFilename
        self.downloadedAt = Date()
    }

    var hasEPUB: Bool { epubLocalPath != nil }
    var hasHTML: Bool { htmlLocalPath != nil }

    /// Updates all server-sourced metadata fields from a Story value.
    func updateMetadata(from story: Story) {
        title = story.title
        author = story.author
        filenameBase = story.filenameBase
        coverFilename = story.cover
        authorURL = story.authorURL
        category = story.category
        tags = story.tags
        sourceURL = story.sourceURL
        wordCount = story.wordCount
        chapterCount = story.chapterCount
        pageCount = story.pageCount
        size = story.size
        rating = story.rating
        storyDescription = story.description
    }

    /// Constructs a Story value with all available cached metadata.
    var asStory: Story {
        Story(
            id: storyID,
            title: title,
            author: author,
            authorURL: authorURL,
            category: category,
            tags: tags,
            cover: coverFilename,
            filenameBase: filenameBase,
            formats: hasHTML ? ["json"] : (hasEPUB ? ["epub"] : []),
            sourceURL: sourceURL,
            wordCount: wordCount,
            chapterCount: chapterCount,
            pageCount: pageCount,
            size: size,
            rating: rating,
            inQueue: inQueue,
            description: storyDescription,
            dateAdded: nil,
            updatedAt: nil
        )
    }
}
