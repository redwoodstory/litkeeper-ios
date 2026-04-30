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
        case unauthorized
        case unreachable
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
                        .onSubmit {
                            appState.serverURL = urlDraft
                        }
                }
                LabeledContent("API Token") {
                    SecureField("Paste token here", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            appState.apiToken = tokenDraft
                        }
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
                        .onSubmit {
                            appState.pangolinTokenId = pangolinTokenIdDraft
                        }
                }
                LabeledContent("Token") {
                    SecureField("P-Access-Token value", text: $pangolinTokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            appState.pangolinToken = pangolinTokenDraft
                        }
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
                    case .unauthorized:
                        Label("Invalid API token", systemImage: "lock.slash.fill")
                            .foregroundStyle(.red)
                    case .unreachable:
                        Label("Server unreachable", systemImage: "wifi.slash")
                            .foregroundStyle(.red)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
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
        .onChange(of: urlDraft) { _, _ in
            guard hasAppeared else { return }
            testResult = nil
        }
        .onChange(of: tokenDraft) { _, _ in
            guard hasAppeared else { return }
            testResult = nil
        }
        .onChange(of: pangolinTokenIdDraft) { _, _ in
            guard hasAppeared else { return }
            testResult = nil
        }
        .onChange(of: pangolinTokenDraft) { _, _ in
            guard hasAppeared else { return }
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
        // Save drafts before testing
        appState.serverURL = urlDraft
        appState.apiToken = tokenDraft
        appState.pangolinTokenId = pangolinTokenIdDraft
        appState.pangolinToken = pangolinTokenDraft
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
            } catch let apiError as APIError {
                await MainActor.run {
                    switch apiError {
                    case .unauthorized:
                        testResult = .unauthorized
                    case .networkError:
                        testResult = .unreachable
                    default:
                        testResult = .failure(apiError.errorDescription ?? apiError.localizedDescription)
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .unreachable
                    isTesting = false
                }
            }
        }
    }
}
