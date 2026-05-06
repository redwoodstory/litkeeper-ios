import SwiftUI

struct AuthorsView: View {
    @Environment(AppState.self) private var appState

    @State private var viewModel = AuthorsViewModel()
    @State private var urlText = ""
    @State private var isSubmitting = false
    @State private var submitMessage: String? = nil
    @State private var submitIsError = false
    @State private var authorToRescan: Author? = nil

    var body: some View {
        Form {
            Section {
                TextField("https://www.literotica.com/authors/username", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if let msg = submitMessage {
                    Label(msg, systemImage: submitIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(submitIsError ? .red : .green)
                        .font(.callout)
                }

                Button(action: submitAuthor) {
                    HStack(spacing: 6) {
                        if isSubmitting { ProgressView().scaleEffect(0.8) }
                        Text(isSubmitting ? "Adding…" : "Scan & Watch Author")
                    }
                }
                .disabled(urlText.isEmpty || isSubmitting || !appState.isConfigured)
            } header: {
                Text("Watch an Author")
            } footer: {
                Text("Paste a Literotica author profile URL to queue a full scan and watch for new stories.")
                    .font(.caption)
            }

            if viewModel.isLoading && viewModel.authors.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                }
            } else if !viewModel.authors.isEmpty {
                Section("Watched Authors") {
                    ForEach(viewModel.authors) { author in
                        AuthorRow(author: author) {
                            Task { await viewModel.toggleWatch(author: author, appState: appState) }
                        } onRescan: {
                            authorToRescan = author
                        }
                    }
                }
            } else if !viewModel.isLoading {
                Section {
                    Text("No watched authors yet. Add one above.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            if let errorMsg = viewModel.errorMessage {
                Section {
                    Label(errorMsg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Watched Authors")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refresh(appState: appState) }
        .refreshable { await viewModel.refresh(appState: appState) }
        .alert("Re-queue Author Scan", isPresented: Binding(
            get: { authorToRescan != nil },
            set: { if !$0 { authorToRescan = nil } }
        )) {
            Button("Confirm") {
                guard let author = authorToRescan else { return }
                Task { await viewModel.rescan(author: author, appState: appState) }
                authorToRescan = nil
            }
            Button("Cancel", role: .cancel) { authorToRescan = nil }
        } message: {
            if let author = authorToRescan {
                Text("Re-check \(author.name)'s profile for new stories?")
            }
        }
    }

    private func submitAuthor() {
        isSubmitting = true
        submitMessage = nil
        let url = urlText
        Task {
            do {
                _ = try await viewModel.addAuthor(url: url, appState: appState)
                await MainActor.run {
                    HapticManager.shared.notify(.success)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        submitMessage = "Author scan queued"
                        submitIsError = false
                    }
                    urlText = ""
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    HapticManager.shared.notify(.error)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        submitMessage = error.localizedDescription
                        submitIsError = true
                    }
                    isSubmitting = false
                }
            }
        }
    }
}

private struct AuthorRow: View {
    let author: Author
    let onToggleWatch: () -> Void
    let onRescan: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(author.name)
                    .font(.body)
                Text("\(author.storyCount) \(author.storyCount == 1 ? "story" : "stories") in library")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let checked = author.lastWatchCheckAt {
                    Text("Last checked \(relativeDate(checked))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onRescan) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(
                get: { author.watchEnabled },
                set: { _ in onToggleWatch() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate,
                                   .withColonSeparatorInTime, .withTimeZone]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate,
                                       .withColonSeparatorInTime]
            date = formatter.date(from: iso)
        }
        guard let date else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
