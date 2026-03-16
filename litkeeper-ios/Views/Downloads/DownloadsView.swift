import SwiftUI
import SwiftData

struct DownloadsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalStory.downloadedAt, order: .reverse) private var localStories: [LocalStory]

    @State private var selectedLocalStory: LocalStory? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if localStories.isEmpty {
                    EmptyStateView(
                        icon: "arrow.down.circle",
                        title: "Nothing Downloaded",
                        message: "Open a story from the Library and tap \"Download to Device\" to read offline."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(localStories) { local in
                                Button {
                                    selectedLocalStory = local
                                } label: {
                                    OfflineStoryCard(localStory: local)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteLocalStory(local)
                                    } label: {
                                        Label("Remove Download", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Downloaded")
            .sheet(item: $selectedLocalStory) { local in
                OfflineStoryDetailView(localStory: local)
                    .environment(appState)
            }
        }
    }

    private func deleteLocalStory(_ local: LocalStory) {
        try? DownloadManager.shared.deleteLocalFiles(for: local)
        modelContext.delete(local)
        try? modelContext.save()
    }
}

struct OfflineStoryCard: View {
    let localStory: LocalStory

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CoverImageView(
                url: localStory.coverLocalPath.map {
                    DownloadManager.shared.coversDirectory.appendingPathComponent($0)
                },
                title: localStory.title,
                author: localStory.author
            )
            .aspectRatio(2/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .background(Circle().fill(.white).padding(-2))
                .font(.caption)
                .padding(5)
        }
    }
}

struct OfflineStoryDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let localStory: LocalStory

    @State private var showEPUBReader = false
    @State private var showHTMLReader = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                CoverImageView(
                    url: localStory.coverLocalPath.map {
                        DownloadManager.shared.coversDirectory.appendingPathComponent($0)
                    },
                    title: localStory.title,
                    author: localStory.author
                )
                .frame(width: 130, height: 195)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 8)

                VStack(spacing: 4) {
                    Text(localStory.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(localStory.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let pct = localStory.readingProgressPercentage, pct > 0 {
                    VStack(spacing: 4) {
                        ProgressView(value: pct / 100)
                        Text("\(Int(pct))% read")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 40)
                }

                HStack(spacing: 16) {
                    if localStory.hasEPUB {
                        Button {
                            showEPUBReader = true
                        } label: {
                            Label("Read EPUB", systemImage: "book")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if localStory.hasHTML {
                        Button {
                            showHTMLReader = true
                        } label: {
                            Label("Read HTML", systemImage: "doc.text")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showEPUBReader) {
                EPUBReaderView(localStory: localStory, appState: appState)
            }
            .fullScreenCover(isPresented: $showHTMLReader) {
                HTMLReaderView(localStory: localStory, appState: appState)
            }
        }
    }
}
