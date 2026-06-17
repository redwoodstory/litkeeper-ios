import SwiftUI

struct BrowseStoryRow: View {
    let story: BrowseStory
    let isInLibrary: Bool
    let isQueued: Bool
    let onAdd: () async -> Void

    @State private var isAdding = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(story.title)
                    .font(.headline)
                    .lineLimit(2)

                if let author = story.authorName {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(primaryMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !secondaryMetadata.isEmpty {
                    Text(secondaryMetadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let desc = story.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: 12)

            actionButton
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isInLibrary {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
        } else if isQueued {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
                .imageScale(.large)
        } else if isAdding {
            ProgressView()
                .frame(width: 28, height: 28)
        } else {
            Button {
                isAdding = true
                Task {
                    await onAdd()
                    isAdding = false
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
    }

    // Line 1: ratings and engagement numbers
    private var primaryMetadata: String {
        var parts: [String] = []
        if let score = story.score { parts.append("★ \(score)") }
        if let count = story.readCount, let n = Int(count) { parts.append(formatCount(n) + " views") }
        if let faves = story.voteCount, let n = Int(faves), n > 0 { parts.append(formatCount(n) + " faves") }
        return parts.joined(separator: " · ")
    }

    // Line 2: context — date, category, series info
    private var secondaryMetadata: String {
        var parts: [String] = []
        if let date = story.dateApprove { parts.append(formatDate(date)) }
        if let cat = story.category { parts.append(cat.capitalized) }
        if let chapters = story.chapterCount, chapters > 0 { parts.append("\(chapters) parts") }
        else if story.isSeries == true { parts.append("Series") }
        return parts.joined(separator: " · ")
    }

    private func formatCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return "\(n / 1_000)K"
        default: return "\(n)"
        }
    }

    private func formatDate(_ str: String) -> String {
        let parts = str.split(separator: "/")
        guard parts.count == 3, let year = parts.last else { return str }
        let months = ["Jan","Feb","Mar","Apr","May","Jun",
                      "Jul","Aug","Sep","Oct","Nov","Dec"]
        let monthIdx = (Int(parts[0]) ?? 1) - 1
        guard months.indices.contains(monthIdx) else { return String(year) }
        return "\(months[monthIdx]) \(year)"
    }
}
