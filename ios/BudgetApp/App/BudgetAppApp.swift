import SwiftUI
import SwiftData

@main
struct BudgetAppApp: App {
    @State private var gate = BiometricGate()
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(gate)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .modelContainer(AppModelContainer.shared)
    }
}
