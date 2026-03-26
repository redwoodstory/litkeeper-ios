import Foundation
import SwiftData

@Model
final class LocalHighlight {
    var highlightID: Int
    var storyID: Int
    var storyTitle: String
    var storyAuthor: String
    var filenameBase: String
    var chapterIndex: Int
    var paragraphIndex: Int
    var quoteText: String
    var note: String?
    var createdAt: String?

    init(
        highlightID: Int,
        storyID: Int,
        storyTitle: String,
        storyAuthor: String,
        filenameBase: String,
        chapterIndex: Int,
        paragraphIndex: Int,
        quoteText: String,
        note: String? = nil,
        createdAt: String? = nil
    ) {
        self.highlightID = highlightID
        self.storyID = storyID
        self.storyTitle = storyTitle
        self.storyAuthor = storyAuthor
        self.filenameBase = filenameBase
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.quoteText = quoteText
        self.note = note
        self.createdAt = createdAt
    }
}
