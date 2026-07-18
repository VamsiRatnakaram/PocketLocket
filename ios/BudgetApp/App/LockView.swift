import SwiftUI

/// Shown while the app is locked; triggers Face ID automatically on appear.
struct LockView: View {
    @Environment(BiometricGate.self) private var gate

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Budget is locked")
                .font(.title2.bold())
            Text("Authenticate to view your finances.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Unlock") {
                Task { await gate.authenticate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .task { await gate.authenticate() }
    }
}
