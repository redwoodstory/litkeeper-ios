import SwiftUI

struct BrowseStoryRow: View {
    let story: BrowseStory
    let isInLibrary: Bool
    let isQueued: Bool
    let showCategory: Bool
    let onAdd: () async -> Void

    @State private var isAdding = false
    @State private var safariURL: URL?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // Tappable title — opens story in in-app browser
                Button {
                    if let url = URL(string: story.url) { safariURL = url }
                } label: {
                    Text(story.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)

                // Stats: ★ rating · ♥ faves · views · series
                Text(primaryMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Context: date · author + optional category badge
                if !secondaryMetadata.isEmpty || (showCategory && story.category != nil) {
                    HStack(alignment: .center, spacing: 4) {
                        if !secondaryMetadata.isEmpty {
                            Text(secondaryMetadata)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if showCategory, let cat = story.category {
                            categoryBadge(cat)
                        }
                    }
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
        .sheet(item: $safariURL) { SafariView(url: $0) }
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

    @ViewBuilder
    private func categoryBadge(_ slug: String) -> some View {
        Text(formatCategory(slug))
            .font(.system(size: 10, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(.systemFill)))
    }

    // ★ rating · ♥ faves · views · series
    private var primaryMetadata: String {
        var parts: [String] = []
        if let score = story.score { parts.append("★ \(score)") }
        if let faves = story.voteCount, let n = Int(faves), n > 0 { parts.append("♥ \(formatCount(n))") }
        if let count = story.readCount, let n = Int(count) { parts.append(formatCount(n) + " views") }
        if let chapters = story.chapterCount, chapters > 0 { parts.append("\(chapters) parts") }
        else if story.isSeries == true { parts.append("Series") }
        return parts.joined(separator: " · ")
    }

    // date · author
    private var secondaryMetadata: String {
        var parts: [String] = []
        if let date = story.dateApprove { parts.append(formatDate(date)) }
        if let author = story.authorName { parts.append(author) }
        return parts.joined(separator: " · ")
    }

    private func formatCategory(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
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
