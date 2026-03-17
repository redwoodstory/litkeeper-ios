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
    var downloadedAt: Date
    var serverUpdatedAt: Date?
    var lastReadAt: Date?
    var readingProgressCFI: String?
    var readingProgressLocator: String?
    var readingProgressPercentage: Double?
    var readingProgressScrollY: Double?

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
}
