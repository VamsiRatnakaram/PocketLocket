import Foundation
import LocalAuthentication
import Observation

/// Gates access to the app behind Face ID / Touch ID (with device passcode
/// fallback). The app locks whenever it enters the background.
@Observable
@MainActor
final class BiometricGate {
    enum State {
        case locked
        case unlocked
        case unavailable // No biometrics/passcode enrolled — don't block the user.
    }

    var state: State = .locked

    init() {
        if Self.isRunningTests {
            state = .unlocked
        }
    }

    /// A shared context: a successful unlock can be briefly reused to read the
    /// Keychain-protected bank token without prompting a second time.
    let authenticationContext: LAContext = {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration
        return context
    }()

    var isUnlocked: Bool { state == .unlocked || state == .unavailable }

    func authenticate() async {
        if Self.isRunningTests {
            state = .unlocked
            return
        }

        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard authenticationContext.canEvaluatePolicy(policy, error: &error) else {
            state = .unavailable
            return
        }

        do {
            let success = try await authenticationContext.evaluatePolicy(policy, localizedReason: "Unlock Budget")
            state = success ? .unlocked : .locked
        } catch {
            state = .locked
        }
    }

    func lock() {
        if state == .unlocked { state = .locked }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
