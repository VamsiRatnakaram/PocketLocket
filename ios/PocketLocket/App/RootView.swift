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
            await authenticateIfNeeded()
            showStoreRecoveryAlert = AppModelContainer.persistentStoreError != nil
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await authenticateIfNeeded() }
            case .background:
                gate.lock()
                SyncService.shared.authContext = nil
            case .inactive:
                break
            @unknown default:
                gate.lock()
                SyncService.shared.authContext = nil
            }
        }
        .onChange(of: gate.state) { _, state in
            SyncService.shared.authContext = state == .unlocked ? gate.authenticationContext : nil
        }
        .overlay {
            // Only cover the *unlocked* main app content when backgrounding —
            // LockView is already privacy-safe. Skip the cover during Face ID
            // authentication (gate.isAuthenticating) too, since scenePhase
            // toggles active/inactive rapidly while the system Face ID sheet
            // is presented/dismissed — both while still locked and in the
            // instant right after unlock completes but before scenePhase
            // catches up — and that overlay churn caused a visible flicker.
            if scenePhase != .active && gate.isUnlocked && !gate.isAuthenticating {
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

    private func authenticateIfNeeded() async {
        guard scenePhase == .active, !gate.isUnlocked else { return }
        await gate.authenticate()
        SyncService.shared.authContext = gate.isUnlocked ? gate.authenticationContext : nil
    }
}
