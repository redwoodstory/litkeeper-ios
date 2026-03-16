import Foundation
import LocalAuthentication

@Observable
final class AppState {
    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    var biometricLockEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricLockEnabled, forKey: "biometricLockEnabled") }
    }
    var isLocked: Bool = false

    var apiToken: String {
        get { KeychainHelper.read(key: "apiToken") ?? "" }
        set { KeychainHelper.write(key: "apiToken", value: newValue) }
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && !apiToken.isEmpty
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        biometricLockEnabled = UserDefaults.standard.bool(forKey: "biometricLockEnabled")
    }

    func makeAPIClient() -> APIClient {
        APIClient(baseURLString: serverURL, token: apiToken)
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
