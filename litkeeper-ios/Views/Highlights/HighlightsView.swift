import SwiftUI

struct HighlightsView: View {
    @Environment(AppState.self) private var appState
    @State private var highlights: [Highlight] = []
    @State private var isLoading = false
    @State private var selectedHighlight: Highlight?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && highlights.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if highlights.isEmpty {
                    EmptyStateView(
                        icon: "quote.bubble",
                        title: "No Saved Quotes",
                        message: "Long-press any paragraph while reading to save a memorable passage."
                    )
                } else {
                    List {
                        ForEach(highlights) { h in
                            HighlightRow(highlight: h)
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
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Saved Quotes")
            .task { await load() }
            .fullScreenCover(item: $selectedHighlight) { h in
                HighlightReaderLauncher(highlight: h)
                    .environment(appState)
            }
        }
    }

    private func load() async {
        guard appState.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        highlights = (try? await appState.makeAPIClient().fetchHighlights()) ?? []
    }

    private func remove(_ h: Highlight) async {
        try? await appState.makeAPIClient().deleteHighlight(id: h.id)
        highlights.removeAll { $0.id == h.id }
    }
}

// MARK: - Highlight Reader Launcher

struct HighlightReaderLauncher: View {
    let highlight: Highlight
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var story: Story?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let story {
                HTMLReaderView(
                    story: story,
                    localStory: nil,
                    appState: appState,
                    targetChapterIndex: highlight.chapterIndex,
                    targetParagraphIndex: highlight.paragraphIndex,
                    targetQuoteText: highlight.quoteText
                )
            } else {
                ContentUnavailableView("Story Not Found", systemImage: "book.closed")
            }
        }
        .task {
            let stories = (try? await appState.makeAPIClient().fetchLibrary()) ?? []
            story = stories.first { $0.id == highlight.storyId }
            isLoading = false
        }
    }
}
