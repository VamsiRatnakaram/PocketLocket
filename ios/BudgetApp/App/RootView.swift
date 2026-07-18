import SwiftUI

/// Top-level router: biometric lock -> main app.
struct RootView: View {
    @Environment(BiometricGate.self) private var gate
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if gate.isUnlocked {
                MainTabView()
            } else {
                LockView()
            }
        }
        .task {
            if !gate.isUnlocked {
                await gate.authenticate()
            }
            SyncService.shared.authContext = gate.authenticationContext
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { gate.lock() }
        }
        .overlay {
            if scenePhase != .active {
                PrivacyCover().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: scenePhase)
    }
}
