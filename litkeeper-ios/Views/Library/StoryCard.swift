import SwiftUI

struct StoryCard: View {
    let story: Story
    let isDownloaded: Bool
    let coverURL: URL?
    var token: String = ""
    var pangolinTokenId: String = ""
    var pangolinToken: String = ""
    var showCategory: Bool = false

    var body: some View {
        VStack(spacing: 4) {
        ZStack(alignment: .topTrailing) {
            CoverImageView(url: coverURL, title: story.title, author: story.author, token: token, pangolinTokenId: pangolinTokenId, pangolinToken: pangolinToken)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

            // Badges — horizontal row anchored to top-right, flowing left
            HStack(spacing: 4) {
                if isDownloaded {
                    badge("checkmark.circle.fill", color: .green)
                }
                if story.inQueue {
                    badge("bookmark.fill", color: .blue)
                }
                if let rating = story.rating, rating == 5 {
                    badge("heart.fill", color: .pink)
                }
            }
            .padding(5)
        }
        if showCategory, let category = story.category {
            Text(category)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        } // end VStack
    }

    private func badge(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(5)
            .background(Circle().fill(.white.opacity(0.92)))
    }
}
