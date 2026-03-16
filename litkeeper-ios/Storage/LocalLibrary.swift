import Foundation
import SwiftData

/// Query helpers for the local SwiftData store.
enum LocalLibrary {
    static func localStory(for storyID: Int, in context: ModelContext) -> LocalStory? {
        let descriptor = FetchDescriptor<LocalStory>(
            predicate: #Predicate { $0.storyID == storyID }
        )
        return try? context.fetch(descriptor).first
    }

    static func allStories(in context: ModelContext) -> [LocalStory] {
        (try? context.fetch(FetchDescriptor<LocalStory>())) ?? []
    }

    static func downloadedStoryIDs(in context: ModelContext) -> Set<Int> {
        Set(allStories(in: context).map { $0.storyID })
    }
}
