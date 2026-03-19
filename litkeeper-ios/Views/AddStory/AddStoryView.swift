import SwiftUI

struct AddStoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var isSubmitting = false
    @State private var resultMessage: String? = nil
    @State private var resultIsError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Story URL")
                        .font(.headline)
                    Text("Paste a Literotica story link below")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("https://www.literotica.com/s/story-name", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                        .onSubmit { submit() }
                }

                if let msg = resultMessage {
                    Label(msg, systemImage: resultIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(resultIsError ? .red : .green)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button(action: submit) {
                    HStack(spacing: 6) {
                        if isSubmitting { ProgressView().tint(.white) }
                        Text(isSubmitting ? "Adding…" : "Add to Queue")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(urlText.isEmpty || isSubmitting)
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

                Text("The story will be downloaded in the background by your server. Check the Queue tab for progress.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Add Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        guard !urlText.isEmpty else { return }
        isSubmitting = true
        resultMessage = nil
        let client = appState.makeAPIClient()
        Task {
            do {
                let item = try await client.queueDownload(url: urlText)
                await MainActor.run {
                    HapticManager.shared.notify(.success)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        resultMessage = "Added to queue (position \(item.id))"
                        resultIsError = false
                    }
                    isSubmitting = false
                    urlText = ""
                }
                // Auto-dismiss after brief delay on success
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    HapticManager.shared.notify(.error)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        resultMessage = error.localizedDescription
                        resultIsError = true
                    }
                    isSubmitting = false
                }
            }
        }
    }
}
