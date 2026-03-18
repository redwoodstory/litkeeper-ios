import SwiftUI

struct ReadingQueueRow: View {
    let story: Story
    let readingProgress: Double?  // 0-1 scale from server
    let coverURL: URL?
    let token: String
    var pangolinTokenId: String = ""
    var pangolinToken: String = ""

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
                    HStack(spacing: 4) {
                        ForEach(story.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundStyle(.secondary)
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
