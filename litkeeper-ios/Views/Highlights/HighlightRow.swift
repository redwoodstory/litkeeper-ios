import SwiftUI

struct HighlightRow: View {
    let highlight: Highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Text(highlight.quoteText)
                    .font(.body)
                    .italic()
                    .lineLimit(4)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.storyTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("by \(highlight.storyAuthor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 24)
        }
        .padding(.vertical, 4)
    }
}
