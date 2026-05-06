import SwiftUI

struct LinkStoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let story: Story
    let onLinked: (Story) -> Void

    @State private var searchState: SearchState = .loading
    @State private var manualURL = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    enum SearchState {
        case loading
        case results(APIClient.MetadataSearchResponse)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch searchState {
                case .loading:
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching Literotica…").foregroundStyle(.secondary)
                        }
                    }

                case .failed(let msg):
                    Section {
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }

                case .results(let resp):
                    if let results = resp.results, !results.isEmpty {
                        Section {
                            ForEach(results) { result in
                                ResultRow(
                                    result: result,
                                    isAutoMatch: result.url == resp.bestMatch?.url && (resp.autoMatch == true),
                                    isSubmitting: isSubmitting
                                ) {
                                    Task { await link(url: result.url, method: result.url == resp.bestMatch?.url ? "auto" : "manual") }
                                }
                            }
                        } header: {
                            Text("Search Results")
                        }
                    } else {
                        Section {
                            Label("No matches found on Literotica. Enter a URL below.", systemImage: "magnifyingglass")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    TextField("https://www.literotica.com/s/…", text: $manualURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Link with This URL") {
                        Task { await link(url: manualURL, method: "manual") }
                    }
                    .disabled(manualURL.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                } header: {
                    Text("Manual URL")
                } footer: {
                    Text("Paste the Literotica story URL to link it manually.")
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Link Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(isSubmitting)
            .task { await search() }
        }
    }

    private func search() async {
        searchState = .loading
        do {
            let resp = try await appState.makeAPIClient().searchStoryMetadata(storyID: story.id)
            searchState = .results(resp)
        } catch {
            searchState = .failed("Search failed. Enter a URL manually.")
        }
    }

    private func link(url: String, method: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("literotica.com") else {
            errorMessage = "Please enter a valid Literotica URL."
            return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            let updated = try await appState.makeAPIClient().refreshStoryMetadata(storyID: story.id, url: trimmed, method: method)
            await MainActor.run {
                HapticManager.shared.notify(.success)
                onLinked(updated)
                dismiss()
            }
        } catch {
            await MainActor.run {
                HapticManager.shared.notify(.error)
                errorMessage = "Failed to link story. Please try again."
                isSubmitting = false
            }
        }
    }
}

private struct ResultRow: View {
    let result: APIClient.MetadataSearchResult
    let isAutoMatch: Bool
    let isSubmitting: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.title)
                        .font(.body)
                        .lineLimit(1)
                    if isAutoMatch {
                        Text("Best Match")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    }
                }
                Text("by \(result.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(result.confidence * 100))% confidence")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Use This", action: onSelect)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSubmitting)
        }
        .padding(.vertical, 2)
    }
}
