import SwiftUI
import SwiftData

struct HighlightsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext
    @Query private var highlights: [LocalHighlight]
    @State private var selectedHighlight: LocalHighlight?

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    EmptyStateView(
                        icon: "quote.bubble",
                        title: "No Saved Quotes",
                        message: "Long-press any paragraph while reading to save a memorable passage."
                    )
                } else {
                    List {
                        ForEach(highlights) { h in
                            HighlightRow(highlight: h.asHighlight)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedHighlight = h }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        HapticManager.shared.notify(.warning)
                                        Task { await remove(h) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await syncHighlights() }
                }
            }
            .navigationTitle("Saved Quotes")
            .fullScreenCover(item: $selectedHighlight) { h in
                OfflineHighlightReaderLauncher(highlight: h)
                    .environment(appState)
            }
        }
    }

    private func syncHighlights() async {
        await syncService.syncHighlights(appState: appState, modelContext: modelContext)
    }

    private func remove(_ h: LocalHighlight) async {
        try? await appState.makeAPIClient().deleteHighlight(id: h.highlightID)
    }
}

// MARK: - LocalHighlight helpers

extension LocalHighlight {
    var asHighlight: Highlight {
        Highlight(
            id: highlightID,
            storyId: storyID,
            storyTitle: storyTitle,
            storyAuthor: storyAuthor,
            filenameBase: filenameBase,
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            quoteText: quoteText,
            note: note,
            createdAt: createdAt
        )
    }
}

// MARK: - Offline-aware reader launcher

struct OfflineHighlightReaderLauncher: View {
    let highlight: LocalHighlight
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var story: Story?
    @State private var localStory: LocalStory?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let story, let local = localStory, local.hasHTML {
                HTMLReaderView(
                    story: story,
                    localStory: local,
                    appState: appState,
                    targetChapterIndex: highlight.chapterIndex,
                    targetParagraphIndex: highlight.paragraphIndex,
                    targetQuoteText: highlight.quoteText
                )
            } else if let story {
                // Story found on server but not downloaded locally
                ContentUnavailableView {
                    Label("Story Not Downloaded", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download \"\(story.title)\" to read this quote offline.")
                } actions: {
                    Button("Dismiss") { dismiss() }
                }
            } else {
                ContentUnavailableView {
                    Label("Story Not Found", systemImage: "book.closed")
                } description: {
                    Text("This story is no longer available.")
                } actions: {
                    Button("Dismiss") { dismiss() }
                }
            }
        }
        .task {
            await resolveStory()
            isLoading = false
        }
    }

    private func resolveStory() async {
        // Check local SwiftData first — works fully offline
        let id = highlight.storyID
        if let local = (try? modelContext.fetch(
            FetchDescriptor<LocalStory>(predicate: #Predicate { $0.storyID == id })
        ))?.first {
            localStory = local
            story = local.asStory
            return
        }

        // Fall back to server if we're online
        guard appState.isConfigured else { return }
        let stories = (try? await appState.makeAPIClient().fetchLibrary()) ?? []
        story = stories.first { $0.id == highlight.storyID }
    }
}
