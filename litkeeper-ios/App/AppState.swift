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
    var proxyAuthToken: String {
        didSet { KeychainHelper.write(key: "proxyAuthToken", value: proxyAuthToken) }
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
        var resolvedProxyToken = KeychainHelper.read(key: "proxyAuthToken") ?? ""
        if resolvedProxyToken.isEmpty,
           let legacyTok = KeychainHelper.read(key: "pangolinToken"), !legacyTok.isEmpty {
            resolvedProxyToken = legacyTok
            KeychainHelper.write(key: "proxyAuthToken", value: legacyTok)
        }
        KeychainHelper.delete(key: "pangolinTokenId")
        KeychainHelper.delete(key: "pangolinToken")
        proxyAuthToken = resolvedProxyToken
        biometricLockEnabled = UserDefaults.standard.bool(forKey: "biometricLockEnabled")
    }

    func makeAPIClient() -> APIClient {
        APIClient(
            baseURLString: serverURL,
            token: apiToken,
            proxyAuthToken: proxyAuthToken.isEmpty ? nil : proxyAuthToken
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
