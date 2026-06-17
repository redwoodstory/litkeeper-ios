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
    var proxyTokenId: String {
        didSet { KeychainHelper.write(key: "proxyTokenId", value: proxyTokenId) }
    }
    var proxyToken: String {
        didSet { KeychainHelper.write(key: "proxyToken", value: proxyToken) }
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
        proxyTokenId = KeychainHelper.read(key: "proxyTokenId") ?? ""
        proxyToken = KeychainHelper.read(key: "proxyToken") ?? ""
        // Clean up legacy proxy auth keys
        KeychainHelper.delete(key: "pangolinTokenId")
        KeychainHelper.delete(key: "pangolinToken")
        KeychainHelper.delete(key: "proxyAuthToken")
        biometricLockEnabled = UserDefaults.standard.bool(forKey: "biometricLockEnabled")
    }

    func makeAPIClient() -> APIClient {
        APIClient(
            baseURLString: serverURL,
            token: apiToken,
            proxyTokenId: proxyTokenId.isEmpty ? nil : proxyTokenId,
            proxyToken: proxyToken.isEmpty ? nil : proxyToken
        )
    }

    func lockIfEnabled() {
        if biometricLockEnabled { isLocked = true }
    }

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock LitKeeper"
            )
            if success { isLocked = false }
        } catch {
            // User cancelled — stay locked
        }
    }
}
