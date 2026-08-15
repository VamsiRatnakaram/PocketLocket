import XCTest
@testable import PocketLocket

final class TransactionSheetDismissalPolicyTests: XCTestCase {
    func testSmallPullAtTopDoesNotDismiss() {
        XCTAssertFalse(
            TransactionSheetDismissalPolicy.shouldDismiss(
                startingScrollDepth: 0,
                currentScrollDepth: 0,
                translation: 119
            )
        )
    }

    func testDeliberatePullAtTopDismisses() {
        XCTAssertTrue(
            TransactionSheetDismissalPolicy.shouldDismiss(
                startingScrollDepth: 0,
                currentScrollDepth: 0,
                translation: 120
            )
        )
    }

    func testPullCannotDismissWhileContentIsStillScrolled() {
        XCTAssertFalse(
            TransactionSheetDismissalPolicy.shouldDismiss(
                startingScrollDepth: 300,
                currentScrollDepth: 20,
                translation: 600
            )
        )
    }

    func testContinuousPullMustTravelPastScrollDepthAndThreshold() {
        XCTAssertFalse(
            TransactionSheetDismissalPolicy.shouldDismiss(
                startingScrollDepth: 300,
                currentScrollDepth: 0,
                translation: 419
            )
        )
        XCTAssertTrue(
            TransactionSheetDismissalPolicy.shouldDismiss(
                startingScrollDepth: 300,
                currentScrollDepth: 0,
                translation: 420
            )
        )
    }
}
