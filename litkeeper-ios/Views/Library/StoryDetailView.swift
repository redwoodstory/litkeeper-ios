import SwiftUI
import SwiftData

struct StoryDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let story: Story

    @Query private var localStories: [LocalStory]
    @State private var downloadProgress: Double = 0
    @State private var downloadMessage: String = ""
    @State private var isDownloading = false
    @State private var downloadError: String? = nil
    @State private var currentRating: Int?
    @State private var showDeleteConfirm = false
    @State private var showEPUBReader = false
    @State private var showHTMLReader = false

    private var localStory: LocalStory? {
        localStories.first { $0.storyID == story.id }
    }

    private var isDownloaded: Bool { localStory != nil }
    private var canReadEPUB: Bool { story.hasEPUB }
    private var canReadHTML: Bool { story.hasHTML }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero cover
                    HStack(spacing: 16) {
                        CoverImageView(
                            url: coverURL,
                            title: story.title,
                            author: story.author,
                            token: appState.apiToken
                        )
                        .frame(width: 110, height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 6)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(story.title)
                                .font(.headline)
                                .lineLimit(3)
                            Text(story.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let cat = story.category {
                                Text(cat)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundStyle(Color.accentColor)
                            }
                            RatingView(rating: currentRating) { newRating in
                                currentRating = newRating == 0 ? nil : newRating
                                Task { try? await appState.makeAPIClient().updateRating(storyID: story.id, rating: newRating) }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    Divider()

                    // Stats
                    statsRow
                        .padding(.horizontal)

                    // Tags
                    if !story.tags.isEmpty {
                        tagsRow
                            .padding(.horizontal)
                    }

                    // Description
                    if let desc = story.description, !desc.isEmpty {
                        Text(desc)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    Divider()

                    // Download section
                    downloadSection
                        .padding(.horizontal)

                    Divider()

                    // Read buttons
                    readSection
                        .padding(.horizontal)

                    // Source link
                    if let urlString = story.sourceURL, let url = URL(string: urlString) {
                        Link("View on Literotica →", destination: url)
                            .font(.footnote)
                            .padding(.horizontal)
                    }

                    // Delete
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete from Library", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .padding(.top)
            }
            .navigationTitle("Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete Story?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await appState.makeAPIClient().deleteStory(storyID: story.id)
                        if let local = localStory {
                            try? DownloadManager.shared.deleteLocalFiles(for: local)
                            modelContext.delete(local)
                            try? modelContext.save()
                        }
                        dismiss()
                    }
                }
            } message: {
                Text("This removes the story from the server and device. This cannot be undone.")
            }
            .fullScreenCover(isPresented: $showEPUBReader) {
                EPUBReaderView(story: story, localStory: localStory, appState: appState)
            }
            .fullScreenCover(isPresented: $showHTMLReader) {
                HTMLReaderView(story: story, localStory: localStory, appState: appState)
            }
        }
        .onAppear { currentRating = story.rating }
    }

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 20) {
            if let words = story.wordCount {
                stat(label: "Words", value: formatWordCount(words))
            }
            if let chapters = story.chapterCount {
                stat(label: "Chapters", value: "\(chapters)")
            }
            ForEach(story.formats, id: \.self) { format in
                Text(format.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.secondary.opacity(0.15)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var tagsRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(story.tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.secondary.opacity(0.12)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device Storage")
                .font(.subheadline)
                .fontWeight(.semibold)

            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: downloadProgress)
                    Text(downloadMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if isDownloaded {
                Label("Downloaded to device", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
                Button("Remove from Device", role: .destructive) {
                    if let local = localStory {
                        try? DownloadManager.shared.deleteLocalFiles(for: local)
                        modelContext.delete(local)
                        try? modelContext.save()
                    }
                }
                .font(.footnote)
            } else {
                Button {
                    startDownload()
                } label: {
                    Label("Download to Device", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let err = downloadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var readSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Read")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack(spacing: 12) {
                Button {
                    showEPUBReader = true
                } label: {
                    Label("EPUB", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canReadEPUB)

                Button {
                    showHTMLReader = true
                } label: {
                    Label("HTML", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canReadHTML)
            }
            if !isDownloaded {
                Text("Download to device for offline reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var coverURL: URL? {
        guard !appState.serverURL.isEmpty else { return nil }
        let filename = story.cover ?? "\(story.filenameBase).jpg"
        let base = appState.serverURL.hasSuffix("/") ? String(appState.serverURL.dropLast()) : appState.serverURL
        return URL(string: "\(base)/api/cover/\(filename)")
    }

    private func startDownload() {
        isDownloading = true
        downloadError = nil
        Task {
            do {
                try await DownloadManager.shared.downloadStory(
                    story: story,
                    serverBaseURL: appState.serverURL,
                    token: appState.apiToken,
                    modelContext: modelContext
                ) { fraction, message in
                    downloadProgress = fraction
                    downloadMessage = message
                }
            } catch {
                downloadError = error.localizedDescription
            }
            isDownloading = false
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline).fontWeight(.semibold)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func formatWordCount(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)"
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.bounds
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.frames[index].minX + bounds.minX,
                                     y: result.frames[index].minY + bounds.minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var bounds = CGSize.zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    y += rowHeight + spacing
                    x = 0
                    rowHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            bounds = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}
