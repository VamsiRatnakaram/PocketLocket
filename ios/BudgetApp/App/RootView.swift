import SwiftUI

/// Top-level router: biometric lock -> main app.
struct RootView: View {
    @Environment(BiometricGate.self) private var gate
    @Environment(\.scenePhase) private var scenePhase
    @State private var showStoreRecoveryAlert = false

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
            showStoreRecoveryAlert = AppModelContainer.persistentStoreError != nil
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
        .alert("Local data needs recovery", isPresented: $showStoreRecoveryAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The existing on-device data store could not be opened. The app started with an empty temporary store so it remains usable. Your original data has not been deleted.")
        }
    }
}
