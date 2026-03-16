import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var urlDraft: String = ""
    @State private var tokenDraft: String = ""
    @State private var testResult: TestResult? = nil
    @State private var isTesting = false

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        @Bindable var appStateBindable = appState
        Form {
            Section {
                LabeledContent("Server URL") {
                    TextField("http://192.168.1.x:5017", text: $urlDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("API Token") {
                    SecureField("Paste token here", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Set LITKEEPER_API_TOKEN in your server's .env file.")
                    .font(.caption)
            }

            Section {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text(isTesting ? "Testing…" : "Test Connection")
                    }
                }
                .disabled(urlDraft.isEmpty || tokenDraft.isEmpty || isTesting)

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connected successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            urlDraft = appState.serverURL
            tokenDraft = appState.apiToken
        }
        .onChange(of: urlDraft) { _, new in
            appState.serverURL = new
            testResult = nil
        }
        .onChange(of: tokenDraft) { _, new in
            appState.apiToken = new
            testResult = nil
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let client = appState.makeAPIClient()
        Task {
            do {
                try await client.testConnection()
                await MainActor.run {
                    testResult = .success
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}
