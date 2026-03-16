import Foundation

struct ReadingProgress: Codable {
    var currentChapter: Int?
    var cfi: String?
    var percentage: Double?
    var isCompleted: Bool
    var lastReadAt: String?

    enum CodingKeys: String, CodingKey {
        case cfi, percentage
        case currentChapter = "current_chapter"
        case isCompleted = "is_completed"
        case lastReadAt = "last_read_at"
    }
}
