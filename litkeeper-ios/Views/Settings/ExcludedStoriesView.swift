import SwiftUI

struct ExcludedStoriesView: View {
    @Environment(AppState.self) private var appState

    @State private var stories: [Story] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showResetConfirm = false
    @State private var resetCount = 0

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…")
                            .foregroundStyle(.secondary)
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
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All stories are eligible for auto-refresh")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Exclusions")
                                .fontWeight(.medium)
                        }
                    }
                } footer: {
                    Text("This will clear all exclusion flags and allow the automation to re-check these stories during the next cycle.")
                        .font(.caption)
                }

                Section("Excluded Stories") {
                    ForEach(stories) { story in
                        NavigationLink {
                            StoryDetailView(story: story)
                        } label: {
                            ExcludedStoryRow(story: story)
                        }
                    }
                }
            }
        }
        .navigationTitle("Excluded Stories")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Reset all exclusions?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { performReset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all exclusion flags and allow the automation to re-check these stories during the next cycle.")
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let client = appState.makeAPIClient()
            let fetched = try await client.fetchExcludedStories()
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

    private func performReset() {
        Task {
            do {
                let client = appState.makeAPIClient()
                let count = try await client.resetAllExclusions()
                await MainActor.run {
                    HapticManager.shared.notify(.success)
                    stories = []
                    resetCount = count
                }
            } catch {
                await MainActor.run {
                    HapticManager.shared.notify(.error)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ExcludedStoryRow: View {
    let story: Story

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(story.title)
                .font(.body)
                .lineLimit(1)

            Text("by \(story.author)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let reason = story.autoRefreshExclusionReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if let type = story.autoRefreshExclusionType {
                Text(typeLabel(type))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor(type), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "no_match": return "No Match"
        case "low_confidence": return "Low Confidence"
        case "duplicate": return "Duplicate"
        default: return type.capitalized
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "no_match": return .gray
        case "low_confidence": return .orange
        case "duplicate": return .red
        default: return .secondary
        }
    }
}
