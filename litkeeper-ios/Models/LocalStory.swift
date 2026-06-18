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
    var queuedAt: Date?
    var lastOpenedAt: Date?
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

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Updates server-sourced metadata fields, writing only values that have changed.
    @discardableResult
    func updateMetadata(from story: Story) -> Bool {
        var changed = false
        func set<T: Equatable>(_ kp: ReferenceWritableKeyPath<LocalStory, T>, _ value: T) {
            if self[keyPath: kp] != value { self[keyPath: kp] = value; changed = true }
        }
        func setOpt<T: Equatable>(_ kp: ReferenceWritableKeyPath<LocalStory, T?>, _ value: T?) {
            if self[keyPath: kp] != value { self[keyPath: kp] = value; changed = true }
        }
        set(\.title, story.title)
        set(\.author, story.author)
        set(\.filenameBase, story.filenameBase)
        setOpt(\.coverFilename, story.cover)
        setOpt(\.authorURL, story.authorURL)
        setOpt(\.category, story.category)
        set(\.tags, story.tags)
        setOpt(\.sourceURL, story.sourceURL)
        setOpt(\.wordCount, story.wordCount)
        setOpt(\.chapterCount, story.chapterCount)
        setOpt(\.pageCount, story.pageCount)
        setOpt(\.size, story.size)
        setOpt(\.rating, story.rating)
        setOpt(\.storyDescription, story.description)

        let fmt = Self.isoFormatter
        let newQueuedAt = story.queuedAt.flatMap { fmt.date(from: $0) }
        let newLastOpenedAt = story.lastOpenedAt.flatMap { fmt.date(from: $0) }
        setOpt(\.queuedAt, newQueuedAt)
        setOpt(\.lastOpenedAt, newLastOpenedAt)
        return changed
    }

    /// Constructs a Story value with all available cached metadata.
    var asStory: Story {
        let fmt = Self.isoFormatter
        return Story(
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
            queuedAt: queuedAt.map { fmt.string(from: $0) },
            lastOpenedAt: lastOpenedAt.map { fmt.string(from: $0) },
            description: storyDescription,
            dateAdded: fmt.string(from: downloadedAt),
            updatedAt: nil
        )
    }
}
