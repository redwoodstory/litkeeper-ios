import SwiftUI

struct ReadingQueueRow: View {
    let story: Story
    let readingProgress: Double?  // 0-1 scale from server
    let coverURL: URL?
    var fallbackURL: URL? = nil
    let token: String
    var proxyTokenId: String = ""
    var proxyToken: String = ""

    private var relativeQueueDate: String? {
        guard let raw = story.queuedAt, let date = Self.parseDate(raw) else { return nil }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { let m = Int(seconds / 60); return "\(m) minute\(m == 1 ? "" : "s") ago" }
        if seconds < 86400 { let h = Int(seconds / 3600); return "\(h) hour\(h == 1 ? "" : "s") ago" }
        if seconds < 604800 { let d = Int(seconds / 86400); return "\(d) day\(d == 1 ? "" : "s") ago" }
        return Self.displayFormatter.string(from: date)
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let microsecondFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return f
    }()

    private static let secondFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static func parseDate(_ raw: String) -> Date? {
        iso8601WithFractional.date(from: raw)
            ?? iso8601Plain.date(from: raw)
            ?? microsecondFormatter.date(from: raw)
            ?? secondFormatter.date(from: raw)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImageView(url: coverURL, fallbackURL: fallbackURL, title: story.title, author: story.author, token: token, proxyTokenId: proxyTokenId, proxyToken: proxyToken)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(story.title)
                    .font(.headline)
                    .lineLimit(2)

                // Author + page count on the same line
                HStack(spacing: 0) {
                    Text(story.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let pages = story.pageCount {
                        Text("  |  \(pages) pages")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let added = relativeQueueDate {
                    Text("Added \(added)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let progress = readingProgress, progress > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: progress)
                            .tint(.blue)
                        Text("\(Int(progress * 100))% read")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .padding(.top, 2)
                }

                if let rating = story.rating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(i <= rating ? Color.orange : Color.secondary.opacity(0.4))
                        }
                    }
                    .padding(.top, 1)
                }

                if let desc = story.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 1)
                }

                if !story.tags.isEmpty {
                    Text(story.tags.prefix(4).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
