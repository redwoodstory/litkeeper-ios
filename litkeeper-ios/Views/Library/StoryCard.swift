import SwiftUI

struct StoryCard: View {
    let story: Story
    let isDownloaded: Bool
    let coverURL: URL?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CoverImageView(url: coverURL, title: story.title, author: story.author)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

            // Badges
            VStack(alignment: .trailing, spacing: 4) {
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .background(Circle().fill(.white).padding(-2))
                        .font(.caption)
                }
                if let rating = story.rating, rating == 5 {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .background(Circle().fill(.white).padding(-2))
                        .font(.caption)
                }
                if story.inQueue {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(.blue)
                        .background(Circle().fill(.white).padding(-2))
                        .font(.caption)
                }
            }
            .padding(5)
        }
    }
}
