import SwiftUI
import LocalAuthentication

struct LockView: View {
    @Environment(AppState.self) private var appState

    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                    .offset(x: shakeOffset)

                VStack(spacing: 8) {
                    Text("LitKeeper Locked")
                        .font(.title2.bold())
                    Text("Authenticate to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await attemptUnlock() }
                } label: {
                    Label(biometricLabel, systemImage: biometricIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .task { await attemptUnlock() }  // auto-prompt on appear
    }

    private func attemptUnlock() async {
        await appState.unlock()
        if appState.isLocked {
            // Auth failed or was cancelled — shake the lock icon
            HapticManager.shared.notify(.error)
            await MainActor.run { triggerShake() }
        } else {
            HapticManager.shared.notify(.success)
        }
    }

    private func triggerShake() {
        let offsets: [CGFloat] = [0, -12, 12, -10, 10, -6, 6, 0]
        var delay: Double = 0
        for offset in offsets {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.06)) {
                    shakeOffset = offset
                }
            }
            delay += 0.06
        }
    }

    private var biometricLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        default: return "Unlock"
        }
    }

    private var biometricIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.open"
        }
    }
}
