import SwiftUI
import SwiftData

@main
struct BudgetAppApp: App {
    @State private var gate = BiometricGate()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(gate)
        }
        .modelContainer(AppModelContainer.shared)
    }
}
