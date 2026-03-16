import SwiftUI

struct QueueView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = QueueViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isConfigured {
                    EmptyStateView(
                        icon: "server.rack",
                        title: "Server Not Configured",
                        message: "Add your server URL and API token in Settings."
                    )
                } else if viewModel.items.isEmpty && !viewModel.isLoading {
                    EmptyStateView(
                        icon: "clock",
                        title: "Queue Empty",
                        message: "Stories you add will appear here while downloading."
                    )
                } else {
                    List {
                        // Stats row
                        if let stats = viewModel.stats {
                            Section {
                                HStack(spacing: 0) {
                                    statCell(label: "Queued", value: stats.pending, color: .orange)
                                    Divider()
                                    statCell(label: "Active", value: stats.processing, color: .blue)
                                    Divider()
                                    statCell(label: "Done", value: stats.completed, color: .green)
                                    Divider()
                                    statCell(label: "Failed", value: stats.failed, color: .red)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }

                        // Processing
                        let processing = viewModel.items.filter { $0.status == .processing }
                        if !processing.isEmpty {
                            Section("Downloading") {
                                ForEach(processing) { item in QueueItemRow(item: item) }
                            }
                        }

                        // Pending
                        let pending = viewModel.items.filter { $0.status == .pending }
                        if !pending.isEmpty {
                            Section("Queued") {
                                ForEach(pending) { item in QueueItemRow(item: item) }
                            }
                        }

                        // Failed
                        let failed = viewModel.items.filter { $0.status == .failed }
                        if !failed.isEmpty {
                            Section("Failed") {
                                ForEach(failed) { item in QueueItemRow(item: item) }
                            }
                        }

                        // Completed (last 20)
                        let completed = viewModel.items.filter { $0.status == .completed }
                        if !completed.isEmpty {
                            Section("Completed") {
                                ForEach(completed) { item in QueueItemRow(item: item) }
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.refresh(appState: appState)
                    }
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                if viewModel.isLoading {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProgressView()
                    }
                }
            }
        }
        .task {
            await viewModel.refresh(appState: appState)
        }
        .onAppear { viewModel.startAutoRefresh(appState: appState) }
        .onDisappear { viewModel.stopAutoRefresh() }
    }

    private func statCell(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(value > 0 ? color : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct QueueItemRow: View {
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title ?? item.url)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                statusBadge
            }

            if item.status == .processing {
                ProgressView(value: item.progress)
                    .tint(.blue)
                if let total = item.totalPages, let downloaded = item.downloadedPages {
                    Text("Page \(downloaded) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = item.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if let author = item.author {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .pending:
            Label("Queued", systemImage: "clock")
                .labelStyle(.iconOnly)
                .foregroundStyle(.orange)
        case .processing:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
