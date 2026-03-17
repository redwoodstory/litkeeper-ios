import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var urlDraft: String = ""
    @State private var tokenDraft: String = ""
    @State private var proxyKeyDraft: String = ""
    @State private var proxyHeaderDraft: String = ""
    @State private var proxyKeyDraft2: String = ""
    @State private var proxyHeaderDraft2: String = ""
    @State private var testResult: TestResult? = nil
    @State private var isTesting = false
    @State private var showDisconnectConfirm = false

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
                LabeledContent("Header 1 Name") {
                    TextField("X-API-Key", text: $proxyHeaderDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Header 1 Value") {
                    SecureField("Leave blank for LAN access", text: $proxyKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Header 2 Name") {
                    TextField("Optional second header", text: $proxyHeaderDraft2)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Header 2 Value") {
                    SecureField("Optional", text: $proxyKeyDraft2)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("External Proxy")
            } footer: {
                Text("Required when accessing via a reverse proxy (e.g. Pangolin) from outside your LAN. For Pangolin, set Header 1 to P-Access-Token-Id and Header 2 to P-Access-Token. Leave blank for direct LAN access.")
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

            if !urlDraft.isEmpty || !tokenDraft.isEmpty {
                Section {
                    Button("Disconnect Server", role: .destructive) {
                        showDisconnectConfirm = true
                    }
                }
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            urlDraft = appState.serverURL
            tokenDraft = appState.apiToken
            proxyKeyDraft = appState.proxyAPIKey
            proxyHeaderDraft = appState.proxyHeaderName
            proxyKeyDraft2 = appState.proxyAPIKey2
            proxyHeaderDraft2 = appState.proxyHeaderName2
        }
        .onChange(of: urlDraft) { _, new in
            appState.serverURL = new
            testResult = nil
        }
        .onChange(of: tokenDraft) { _, new in
            appState.apiToken = new
            testResult = nil
        }
        .onChange(of: proxyKeyDraft) { _, new in
            appState.proxyAPIKey = new
            testResult = nil
        }
        .onChange(of: proxyHeaderDraft) { _, new in
            appState.proxyHeaderName = new.isEmpty ? "X-API-Key" : new
            testResult = nil
        }
        .onChange(of: proxyKeyDraft2) { _, new in
            appState.proxyAPIKey2 = new
            testResult = nil
        }
        .onChange(of: proxyHeaderDraft2) { _, new in
            appState.proxyHeaderName2 = new
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
                appState.proxyAPIKey = ""
                appState.proxyAPIKey2 = ""
                urlDraft = ""
                tokenDraft = ""
                proxyKeyDraft = ""
                proxyKeyDraft2 = ""
                testResult = nil
            }
        } message: {
            Text("This removes the saved server URL and API token from this device. Your library on the server is unaffected.")
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
