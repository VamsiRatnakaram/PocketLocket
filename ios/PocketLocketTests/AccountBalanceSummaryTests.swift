import XCTest
@testable import PocketLocket

final class AccountBalanceSummaryTests: XCTestCase {
    func testNegativeCreditCardBalanceReducesNetWorth() {
        let totals = AccountBalanceSummary.totals(for: [
            .init(type: "depository", balance: 5_000),
            .init(type: "credit", balance: -1_200),
        ])

        XCTAssertEqual(totals.assets, 5_000)
        XCTAssertEqual(totals.liabilities, 1_200)
        XCTAssertEqual(totals.netWorth, 3_800)
    }

    func testPositiveLoanBalanceIsStillALiability() {
        let totals = AccountBalanceSummary.totals(for: [
            .init(type: "loan", balance: 24_000),
        ])

        XCTAssertEqual(totals.assets, 0)
        XCTAssertEqual(totals.liabilities, 24_000)
        XCTAssertEqual(totals.netWorth, -24_000)
    }

    func testOverdraftIsALiability() {
        let totals = AccountBalanceSummary.totals(for: [
            .init(type: "depository", balance: -75),
        ])

        XCTAssertEqual(totals.assets, 0)
        XCTAssertEqual(totals.liabilities, 75)
    }
}