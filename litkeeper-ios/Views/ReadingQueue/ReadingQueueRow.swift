import SwiftUI

struct ReadingQueueRow: View {
    let story: Story
    let readingProgress: Double?  // 0-1 scale from server
    let coverURL: URL?
    let token: String
    var pangolinTokenId: String = ""
    var pangolinToken: String = ""

    private var relativeQueueDate: String? {
        guard let raw = story.queuedAt else { return nil }
        let date = Self.parseDate(raw)
        guard let date else { return nil }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { let m = Int(seconds / 60); return "\(m) minute\(m == 1 ? "" : "s") ago" }
        if seconds < 86400 { let h = Int(seconds / 3600); return "\(h) hour\(h == 1 ? "" : "s") ago" }
        if seconds < 604800 { let d = Int(seconds / 86400); return "\(d) day\(d == 1 ? "" : "s") ago" }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: raw) { return d }
        let f3 = DateFormatter()
        f3.locale = Locale(identifier: "en_US_POSIX")
        f3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = f3.date(from: raw) { return d }
        let f4 = DateFormatter()
        f4.locale = Locale(identifier: "en_US_POSIX")
        f4.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f4.date(from: raw)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImageView(url: coverURL, title: story.title, author: story.author, token: token, pangolinTokenId: pangolinTokenId, pangolinToken: pangolinToken)
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(story.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
