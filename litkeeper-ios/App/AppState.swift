import Foundation
import LocalAuthentication

@Observable
final class AppState {
    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    var apiToken: String {
        didSet { KeychainHelper.write(key: "apiToken", value: apiToken) }
    }
    var pangolinTokenId: String {
        didSet { KeychainHelper.write(key: "pangolinTokenId", value: pangolinTokenId) }
    }
    var pangolinToken: String {
        didSet { KeychainHelper.write(key: "pangolinToken", value: pangolinToken) }
    }
    var biometricLockEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricLockEnabled, forKey: "biometricLockEnabled") }
    }
    var isLocked: Bool = false

    var isConfigured: Bool {
        !serverURL.isEmpty && !apiToken.isEmpty
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        apiToken = KeychainHelper.read(key: "apiToken") ?? ""
        pangolinTokenId = KeychainHelper.read(key: "pangolinTokenId") ?? ""
        pangolinToken = KeychainHelper.read(key: "pangolinToken") ?? ""
        biometricLockEnabled = UserDefaults.standard.bool(forKey: "biometricLockEnabled")
    }

    func makeAPIClient() -> APIClient {
        APIClient(
            baseURLString: serverURL,
            token: apiToken,
            pangolinTokenId: pangolinTokenId.isEmpty ? nil : pangolinTokenId,
            pangolinToken: pangolinToken.isEmpty ? nil : pangolinToken
        )
    }

    func lockIfEnabled() {
        if biometricLockEnabled { isLocked = true }
    }

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock LitKeeper"
            )
            if success { isLocked = false }
        } catch {
            // User cancelled — stay locked
        }
    }
}
