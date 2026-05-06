import SwiftUI

struct StoryAutoUpdateView: View {
    @Environment(AppState.self) private var appState

    @State private var stories: [Story] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var togglingIDs: Set<Int> = []
    @State private var linkingStory: Story?

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                }
            } else if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } else if stories.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "tray").foregroundStyle(.secondary)
                        Text("No stories in library yet.").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ForEach($stories) { $story in
                        StoryAutoUpdateRow(
                            story: $story,
                            isToggling: togglingIDs.contains(story.id),
                            onToggle: { Task { await toggle(story: story) } },
                            onLink: { linkingStory = story }
                        )
                    }
                }
            }
        }
        .navigationTitle("Manage Stories")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $linkingStory) { story in
            LinkStoryView(story: story) { updated in
                if let idx = stories.firstIndex(where: { $0.id == updated.id }) {
                    stories[idx] = updated
                }
            }
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let fetched = try await appState.makeAPIClient().fetchLibrary()
            await MainActor.run {
                stories = fetched
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func toggle(story: Story) async {
        await MainActor.run { togglingIDs.insert(story.id) }
        do {
            let newValue = try await appState.makeAPIClient().toggleStoryAutoUpdate(storyID: story.id)
            await MainActor.run {
                if let idx = stories.firstIndex(where: { $0.id == story.id }) {
                    stories[idx].autoUpdateEnabled = newValue
                }
                togglingIDs.remove(story.id)
                HapticManager.shared.notify(.success)
            }
        } catch {
            await MainActor.run {
                togglingIDs.remove(story.id)
                HapticManager.shared.notify(.error)
            }
        }
    }
}

private struct StoryAutoUpdateRow: View {
    @Binding var story: Story
    let isToggling: Bool
    let onToggle: () -> Void
    let onLink: () -> Void

    private var canLink: Bool {
        story.autoRefreshExcluded &&
        story.autoRefreshExclusionType != "duplicate" &&
        story.autoRefreshExclusionType != "combined"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(story.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("by \(story.author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let chapters = story.chapterCount, chapters > 1 {
                        Text("· \(chapters) parts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if story.autoRefreshExcluded {
                    Text(canLink ? "Source URL required" : (story.autoRefreshExclusionReason ?? "Excluded"))
                        .font(.caption2)
                        .foregroundStyle(canLink ? Color.secondary : Color.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if canLink {
                Button("Link", action: onLink)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if isToggling {
                ProgressView().scaleEffect(0.8)
            } else {
                Toggle("", isOn: Binding(
                    get: { story.autoUpdateEnabled && !story.autoRefreshExcluded },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                .disabled(story.autoRefreshExcluded)
            }
        }
        .padding(.vertical, 2)
        .opacity(story.autoRefreshExcluded && !canLink ? 0.55 : 1)
    }
}
