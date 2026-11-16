import SwiftUI
import SwiftData

@main
struct PocketLocketApp: App {
    @State private var gate = BiometricGate()
    @State private var router = AppRouter()
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    init() {
        #if DEBUG
        DebugLaunch.seedSimpleFINIfNeeded()
        #endif
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(gate)
                .environment(router)
                .preferredColorScheme(appearanceMode.colorScheme)
                // A widget tap arrives here. Nothing opens directly: the request
                // is parked on the router and applied once the app has unlocked,
                // so a tap can never preview data behind the lock.
                .onOpenURL { url in router.handle(url: url) }
        }
        .modelContainer(AppModelContainer.shared)
    }
}
