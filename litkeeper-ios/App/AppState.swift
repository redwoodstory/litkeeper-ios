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
        let t0 = Date()
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let t1 = Date(); print("[LK-STARTUP] AppState: UserDefaults read \(String(format: "%.1f", t1.timeIntervalSince(t0)*1000))ms")
        apiToken = KeychainHelper.read(key: "apiToken") ?? ""
        let t2 = Date(); print("[LK-STARTUP] AppState: apiToken keychain \(String(format: "%.1f", t2.timeIntervalSince(t1)*1000))ms")
        proxyTokenId = KeychainHelper.read(key: "proxyTokenId") ?? ""
        let t3 = Date(); print("[LK-STARTUP] AppState: proxyTokenId keychain \(String(format: "%.1f", t3.timeIntervalSince(t2)*1000))ms")
        proxyToken = KeychainHelper.read(key: "proxyToken") ?? ""
        let t4 = Date(); print("[LK-STARTUP] AppState: proxyToken keychain \(String(format: "%.1f", t4.timeIntervalSince(t3)*1000))ms")
        KeychainHelper.delete(key: "pangolinTokenId")
        KeychainHelper.delete(key: "pangolinToken")
        KeychainHelper.delete(key: "proxyAuthToken")
        let t5 = Date(); print("[LK-STARTUP] AppState: legacy key deletes \(String(format: "%.1f", t5.timeIntervalSince(t4)*1000))ms")
        biometricLockEnabled = UserDefaults.standard.bool(forKey: "biometricLockEnabled")
        print("[LK-STARTUP] AppState.init total: \(String(format: "%.1f", Date().timeIntervalSince(t0)*1000))ms")
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
