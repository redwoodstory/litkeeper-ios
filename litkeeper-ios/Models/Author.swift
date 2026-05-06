import Foundation

struct Author: Identifiable, Codable {
    let id: Int
    let name: String
    let literoticaURL: String?
    var watchEnabled: Bool
    let storyCount: Int
    let knownStoryCount: Int
    let lastWatchCheckAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case literoticaURL = "literotica_url"
        case watchEnabled = "watch_enabled"
        case storyCount = "story_count"
        case knownStoryCount = "known_story_count"
        case lastWatchCheckAt = "last_watch_check_at"
    }
}

struct AuthorsResponse: Codable {
    let success: Bool?
    let authors: [Author]
}
