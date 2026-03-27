import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var urlDraft: String = ""
    @State private var tokenDraft: String = ""
    @State private var pangolinTokenIdDraft: String = ""
    @State private var pangolinTokenDraft: String = ""
    @State private var testResult: TestResult? = nil
    @State private var isTesting = false
    @State private var showDisconnectConfirm = false
    @State private var hasAppeared = false

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
                LabeledContent("Token ID") {
                    SecureField("P-Access-Token-Id value", text: $pangolinTokenIdDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Token") {
                    SecureField("P-Access-Token value", text: $pangolinTokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Pangolin Access Control")
            } footer: {
                Text("Required when accessing via Pangolin from outside your LAN. Find these under Access > [your resource] in the Pangolin dashboard. Leave blank for direct LAN access.")
                    .font(.caption)
            }

            Section {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Testing…")
                        } else {
                            Label("Test Connection", systemImage: "network")
                        }
                    }
                }
                .disabled(urlDraft.isEmpty || tokenDraft.isEmpty || isTesting)

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connected successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure:
                        Label("Unreachable", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            if !urlDraft.isEmpty || !tokenDraft.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Disconnect Server", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            urlDraft = appState.serverURL
            tokenDraft = appState.apiToken
            pangolinTokenIdDraft = appState.pangolinTokenId
            pangolinTokenDraft = appState.pangolinToken
            // Mark as appeared AFTER setting drafts so onChange handlers below
            // don't write back to appState during initialization (which would
            // cause isConfigured to flicker false→true and trigger a spurious
            // library refresh or, worse, briefly clear the displayed library).
            hasAppeared = true
        }
        .onChange(of: urlDraft) { _, new in
            guard hasAppeared else { return }
            appState.serverURL = new
            testResult = nil
        }
        .onChange(of: tokenDraft) { _, new in
            guard hasAppeared else { return }
            appState.apiToken = new
            testResult = nil
        }
        .onChange(of: pangolinTokenIdDraft) { _, new in
            guard hasAppeared else { return }
            appState.pangolinTokenId = new
            testResult = nil
        }
        .onChange(of: pangolinTokenDraft) { _, new in
            guard hasAppeared else { return }
            appState.pangolinToken = new
            testResult = nil
        }
        .confirmationDialog(
            "Disconnect from server?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                appState.serverURL = ""
                appState.apiToken = ""
                appState.pangolinTokenId = ""
                appState.pangolinToken = ""
                urlDraft = ""
                tokenDraft = ""
                pangolinTokenIdDraft = ""
                pangolinTokenDraft = ""
                testResult = nil
            }
        } message: {
            Text("This removes the saved server URL and API token from this device. Your library on the server is unaffected.")
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let idLen = appState.pangolinTokenId.count
        let tokLen = appState.pangolinToken.count
        print("[LK-Settings] testConnection — pangolinTokenId: \(idLen) chars, pangolinToken: \(tokLen) chars")
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
