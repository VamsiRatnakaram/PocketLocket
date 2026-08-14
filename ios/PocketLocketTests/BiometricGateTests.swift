import XCTest
import LocalAuthentication
@testable import PocketLocket

@MainActor
final class BiometricGateTests: XCTestCase {
    private func laError(_ code: LAError.Code) -> NSError {
        NSError(domain: LAErrorDomain, code: code.rawValue)
    }

    /// Only a device with no passcode can never authenticate; that one case
    /// opens the app rather than bricking it.
    func testPasscodeNotSetIsTheOnlyUnavailableState() {
        XCTAssertEqual(BiometricGate.stateForUnevaluablePolicy(laError(.passcodeNotSet)), .unavailable)
    }

    /// Everything else is transient, and treating it as unavailable handed out
    /// the whole ledger with no authentication at all.
    func testTransientFailuresStayLocked() {
        for code: LAError.Code in [.invalidContext, .notInteractive, .appCancel, .systemCancel,
                                   .biometryNotAvailable, .biometryLockout, .authenticationFailed] {
            XCTAssertEqual(BiometricGate.stateForUnevaluablePolicy(laError(code)), .locked,
                           "\(code) must not unlock the app")
        }
        XCTAssertEqual(BiometricGate.stateForUnevaluablePolicy(nil), .locked)
        XCTAssertEqual(
            BiometricGate.stateForUnevaluablePolicy(
                NSError(domain: "SomeOtherDomain", code: LAError.passcodeNotSet.rawValue)),
            .locked,
            "a matching code in an unrelated domain is not a passcode-not-set")
    }
}
