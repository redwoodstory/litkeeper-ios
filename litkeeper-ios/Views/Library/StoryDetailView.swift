import SwiftUI
import SwiftData

struct StoryDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let story: Story

    @Query private var localStories: [LocalStory]
    @State private var downloadError: String? = nil
    @State private var currentRating: Int?
    @State private var showDeleteConfirm = false
    @State private var showResetProgressConfirm = false
    @State private var showEPUBReader = false
    @State private var showHTMLReader = false
    @State private var isSyncing = false
    @State private var isInQueue = false
    @State private var editableTitle: String = ""
    @State private var editableAuthor: String = ""
    @State private var editableCategory: String = ""
    @State private var editableDescription: String = ""
    @State private var editableTags: [String] = []
    @State private var showEditStory = false

    private var localStory: LocalStory? {
        localStories.first { $0.storyID == story.id }
    }

    private var isDownloaded: Bool { localStory != nil }
    private var canReadEPUB: Bool { localStory?.hasEPUB == true }
    private var canReadHTML: Bool { story.hasHTML }

    var body: some View {
        NavigationStack {
            List {
                // Header — cover + title info, no section background
                headerSection
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                // Read buttons
                readSection

                // Reading progress
                if let local = localStory, let pct = local.readingProgressPercentage, pct > 0 {
                    progressSection(local: local, percentage: pct)
                }

                // Stats row
                statsSection

                // Description
                if !editableDescription.isEmpty {
                    descriptionSection
                }

                // Tags
                if !editableTags.isEmpty {
                    tagsSection
                }

                // Utility: offline + delete
                utilitySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showEditStory = true } label: {
                        Image(systemName: "pencil")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Reset Progress?", isPresented: $showResetProgressConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    Task { await resetProgress() }
                }
            } message: {
                Text("This will reset your reading position to the beginning.")
            }
            .alert("Delete Story?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
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
                Text("This permanently removes the story from the server and device.")
            }
            .fullScreenCover(isPresented: $showEPUBReader) {
                EPUBReaderView(story: story, localStory: localStory, appState: appState)
            }
            .fullScreenCover(isPresented: $showHTMLReader) {
                HTMLReaderView(story: story, localStory: localStory, appState: appState)
            }
            .sheet(isPresented: $showEditStory) {
                EditStoryForm(
                    title: $editableTitle,
                    author: $editableAuthor,
                    category: $editableCategory,
                    description: $editableDescription,
                    tags: $editableTags,
                    onSave: {
                        let coverRegenerated = (try? await appState.makeAPIClient().updateMetadata(
                            storyID: story.id,
                            title: editableTitle,
                            author: editableAuthor,
                            category: editableCategory.isEmpty ? nil : editableCategory,
                            description: editableDescription.isEmpty ? nil : editableDescription,
                            tags: editableTags
                        )) ?? false
                        if coverRegenerated {
                            let filename = story.cover ?? "\(story.filenameBase).jpg"
                            await syncService.resyncCover(
                                coverFilename: filename,
                                serverURL: appState.serverURL,
                                token: appState.apiToken
                            )
                        }
                    }
                )
            }
        }
        .onAppear {
            currentRating = story.rating
            isInQueue = story.inQueue
            editableTitle = story.title
            editableAuthor = story.author
            editableCategory = story.category ?? ""
            editableDescription = story.description ?? ""
            editableTags = story.tags
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImageView(url: coverURL, title: editableTitle, author: editableAuthor, token: appState.apiToken)
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                // Title + source link
                HStack(alignment: .top, spacing: 6) {
                    Text(editableTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let urlString = story.sourceURL, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }

                // Author
                if let authorURL = story.authorURL, let url = URL(string: authorURL) {
                    Link(destination: url) {
                        Text(editableAuthor)
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Text(editableAuthor)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Category
                if !editableCategory.isEmpty {
                    Text(editableCategory)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                // Offline + queue icons
                HStack(spacing: 4) {
                    Button {
                        if isDownloaded {
                            if let local = localStory {
                                try? DownloadManager.shared.deleteLocalFiles(for: local)
                                modelContext.delete(local)
                                try? modelContext.save()
                            }
                        } else {
                            isSyncing = true
                            startDownload()
                        }
                    } label: {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.85)
                                .frame(width: 44, height: 44)
                        } else {
                            Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.title)
                                .foregroundStyle(isDownloaded ? Color.green : Color.secondary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncing)

                    Button {
                        isInQueue.toggle()
                        let newValue = isInQueue
                        Task { try? await appState.makeAPIClient().updateQueue(storyID: story.id, inQueue: newValue) }
                    } label: {
                        Image(systemName: isInQueue ? "list.bullet.circle.fill" : "list.bullet.circle")
                            .font(.title)
                            .foregroundStyle(isInQueue ? Color.accentColor : Color.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)

                Spacer(minLength: 0)

                // Rating
                RatingView(rating: currentRating) { newRating in
                    currentRating = newRating == 0 ? nil : newRating
                    Task { try? await appState.makeAPIClient().updateRating(storyID: story.id, rating: newRating) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    // MARK: - Read section

    @ViewBuilder
    private var readSection: some View {
        Section {
            HStack(spacing: 10) {
                Button {
                    showEPUBReader = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                        Text("Read EPUB")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .disabled(!canReadEPUB)

                Button {
                    showHTMLReader = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                        Text("Read HTML")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .disabled(!canReadHTML)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            if let err = downloadError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Stats section

    @ViewBuilder
    private var statsSection: some View {
        Section {
            HStack(spacing: 0) {
                statCell(value: story.wordCount.map { formatWordCount($0) } ?? "—", label: "Words")
                Divider().frame(height: 36)
                statCell(value: story.pageCount.map { "\($0)" } ?? "—", label: "Pages")
                Divider().frame(height: 36)
                statCell(value: story.size.map { formatSize($0) } ?? "—", label: "Size")
                Divider().frame(height: 36)
                statCell(value: story.dateAdded.map { formatDateShort($0) } ?? "—", label: "Added")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Description section

    @ViewBuilder
    private var descriptionSection: some View {
        Section("About") {
            Text(editableDescription)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Tags section

    @ViewBuilder
    private var tagsSection: some View {
        Section("Tags") {
            FlowLayout(spacing: 8) {
                ForEach(editableTags, id: \.self) { tag in
                    Text(tag)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemGray5)))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        }
    }

    // MARK: - Progress section

    @ViewBuilder
    private func progressSection(local: LocalStory, percentage: Double) -> some View {
        Section("Reading Progress") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Int(percentage))% complete")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Reset") {
                        showResetProgressConfirm = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
                ProgressView(value: percentage / 100)
                    .tint(.accentColor)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Utility section

    @ViewBuilder
    private var utilitySection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                    Text("Delete from Library")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var coverURL: URL? {
        let filename = story.cover ?? "\(story.filenameBase).jpg"
        if syncService.localCoverFilenames.contains(filename) {
            return DownloadManager.shared.localCoverURL(filename: filename)
        }
        guard !appState.serverURL.isEmpty else { return nil }
        let base = appState.serverURL.hasSuffix("/") ? String(appState.serverURL.dropLast()) : appState.serverURL
        return URL(string: "\(base)/api/cover/\(filename)")
    }

    private func resetProgress() async {
        guard let local = localStory else { return }
        local.readingProgressPercentage = nil
        local.readingProgressCFI = nil
        local.readingProgressLocator = nil
        local.readingProgressScrollY = nil
        try? modelContext.save()
        let zeroed = ReadingProgress(currentChapter: nil, cfi: nil, percentage: 0, isCompleted: false, lastReadAt: nil)
        try? await appState.makeAPIClient().saveProgress(storyID: story.id, progress: zeroed)
    }

    private func startDownload() {
        downloadError = nil
        Task {
            do {
                try await DownloadManager.shared.downloadStory(
                    story: story,
                    serverBaseURL: appState.serverURL,
                    token: appState.apiToken,
                    modelContext: modelContext
                ) { _, _ in }
            } catch {
                downloadError = error.localizedDescription
            }
            isSyncing = false
        }
    }

    private func formatWordCount(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)"
    }

    private func formatDateShort(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: dateString) {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, yyyy"
            return fmt.string(from: date)
        }
        return dateString
    }

    private func formatSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%d KB", max(1, bytes / 1024))
    }
}

// MARK: - Flow layout for tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).bounds
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: result.frames[index].minX + bounds.minX,
                            y: result.frames[index].minY + bounds.minY),
                proposal: .unspecified
            )
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (bounds: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
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
        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

// MARK: - Edit Story Form

private struct EditStoryForm: View {
    @Binding var title: String
    @Binding var author: String
    @Binding var category: String
    @Binding var description: String
    @Binding var tags: [String]
    let onSave: () async -> Void

    @State private var newTag = ""
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Title") {
                        TextField("Required", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Author") {
                        TextField("Required", text: $author)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Category") {
                        TextField("Optional", text: $category)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }

                Section("Tags") {
                    ForEach(tags.indices, id: \.self) { index in
                        Text(tags[index])
                    }
                    .onDelete { offsets in
                        tags.remove(atOffsets: offsets)
                    }
                    HStack {
                        TextField("Add tag", text: $newTag)
                            .onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Edit Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            isSaving = true
                            Task {
                                await onSave()
                                isSaving = false
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  author.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tags.append(trimmed)
        newTag = ""
    }
}
