import SwiftUI

struct StoryCard: View {
    let story: Story
    let isDownloaded: Bool
    var isInQueue: Bool = false
    var isFavorited: Bool = false
    let coverURL: URL?
    var fallbackURL: URL? = nil
    var token: String = ""
    var proxyTokenId: String = ""
    var proxyToken: String = ""
    var showCategory: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            CoverImageView(url: coverURL, fallbackURL: fallbackURL, title: story.title, author: story.author, token: token, proxyTokenId: proxyTokenId, proxyToken: proxyToken)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

            if showCategory, let category = story.category {
                Text(category)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 2) {
                let rating = story.rating ?? 0
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(i <= rating ? .orange : .secondary.opacity(0.15))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

}
