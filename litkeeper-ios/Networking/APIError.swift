import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case notFound
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Server not configured. Go to Settings to add your server URL and token."
        case .unauthorized:
            return "Invalid API token. Check your token in Settings."
        case .notFound:
            return "Not found."
        case .serverError(let code):
            return "Server error (\(code))."
        case .networkError:
            return "Can't reach the server. Check your connection and try again."
        case .decodingError(let error):
            return "Data error: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid server URL."
        }
    }
}
