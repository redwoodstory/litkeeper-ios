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
    var proxyAPIKey: String {
        didSet { KeychainHelper.write(key: "proxyAPIKey", value: proxyAPIKey) }
    }
    var proxyHeaderName: String {
        didSet { UserDefaults.standard.set(proxyHeaderName, forKey: "proxyHeaderName") }
    }
    var proxyAPIKey2: String {
        didSet { KeychainHelper.write(key: "proxyAPIKey2", value: proxyAPIKey2) }
    }
    var proxyHeaderName2: String {
        didSet { UserDefaults.standard.set(proxyHeaderName2, forKey: "proxyHeaderName2") }
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
        proxyAPIKey = KeychainHelper.read(key: "proxyAPIKey") ?? ""
        proxyHeaderName = UserDefaults.standard.string(forKey: "proxyHeaderName") ?? "X-API-Key"
        proxyAPIKey2 = KeychainHelper.read(key: "proxyAPIKey2") ?? ""
        proxyHeaderName2 = UserDefaults.standard.string(forKey: "proxyHeaderName2") ?? ""
        biometricLockEnabled = UserDefaults.standard.bool(forKey: "biometricLockEnabled")
    }

    func makeAPIClient() -> APIClient {
        APIClient(
            baseURLString: serverURL,
            token: apiToken,
            proxyAPIKey: proxyAPIKey.isEmpty ? nil : proxyAPIKey,
            proxyHeaderName: proxyHeaderName,
            proxyAPIKey2: proxyAPIKey2.isEmpty ? nil : proxyAPIKey2,
            proxyHeaderName2: proxyHeaderName2
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
