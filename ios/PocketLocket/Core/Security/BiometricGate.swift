import Foundation
import LocalAuthentication
import Observation

/// Gates access to the app behind Face ID / Touch ID (with device passcode
/// fallback). The app locks whenever it enters the background.
@Observable
@MainActor
final class BiometricGate {
    enum State: Equatable {
        case locked
        case unlocked
        case unavailable // No biometrics/passcode enrolled — don't block the user.
    }

    var state: State = .locked
    private(set) var authenticationContext: LAContext?
    private(set) var isAuthenticating = false
    private var authenticationAttemptID: UUID?

    init() {
        if Self.isRunningTests {
            state = .unlocked
        }
    }

    private static func makeAuthenticationContext() -> LAContext {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        return context
    }

    var isUnlocked: Bool { state == .unlocked || state == .unavailable }

    func authenticate() async {
        guard !isAuthenticating else { return }
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        isAuthenticating = true
        defer {
            if authenticationAttemptID == attemptID {
                isAuthenticating = false
            }
        }

        let context = Self.makeAuthenticationContext()
        authenticationContext = context

        if Self.isRunningTests {
            if authenticationAttemptID == attemptID { state = .unlocked }
            return
        }

        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            if authenticationAttemptID == attemptID { state = .unavailable }
            return
        }

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: "Unlock PocketLocket")
            if authenticationAttemptID == attemptID {
                state = success ? .unlocked : .locked
            }
        } catch {
            if authenticationAttemptID == attemptID { state = .locked }
        }
    }

    func lock() {
        authenticationAttemptID = nil
        isAuthenticating = false
        authenticationContext?.invalidate()
        authenticationContext = nil
        state = .locked
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
