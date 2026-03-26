import Foundation
import SwiftData

/// Persists a user action that needs to be synced to the server.
/// Each record represents the *latest* desired state for a given (storyID, operationType) pair.
/// Records are deleted on successful sync and retried on the next flush cycle.
@Model
final class PendingOperation {
    var storyID: Int
    /// One of: "queue", "rating", "progress", "last_opened"
    var operationType: String
    var inQueue: Bool?
    var queuedAt: Date?
    var rating: Int?
    var progressFraction: Double?
    var progressParagraphID: String?
    var lastOpenedAt: Date?
    var createdAt: Date

    init(storyID: Int, operationType: String) {
        self.storyID = storyID
        self.operationType = operationType
        self.createdAt = Date()
    }
}
