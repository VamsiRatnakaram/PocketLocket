import XCTest
@testable import BudgetApp

final class MerchantHeuristicsTests: XCTestCase {
    private func category(_ text: String) -> SpendCategory? {
        MerchantHeuristics.category(for: text.lowercased())
    }

    func testCardPaymentsAndTransfersAreNotSpend() {
        // With multiple accounts linked, these must NOT inflate the spend ring.
        XCTAssertEqual(category("AUTOPAY PAYMENT THANK YOU"), .transfer)
        XCTAssertEqual(category("ONLINE TRANSFER TO SAVINGS"), .transfer)
        XCTAssertEqual(category("ZELLE TO ALEX"), .transfer)
        XCTAssertEqual(category("VENMO CASHOUT"), .transfer)
        XCTAssertEqual(category("ROBINHOOD FUNDING"), .transfer)
        XCTAssertFalse(SpendCategory.transfer.isSpending)
    }

    func testCommonMerchantsResolve() {
        XCTAssertEqual(category("CHICK-FIL-A #123"), .food)
        XCTAssertEqual(category("SHELL OIL 4567"), .transport)
        XCTAssertEqual(category("T-MOBILE"), .housing)
        XCTAssertEqual(category("TRADER JOE'S #45"), .groceries)
        XCTAssertEqual(category("WHOLE FOODS MKT"), .groceries)
        XCTAssertEqual(category("NETFLIX.COM"), .entertainment)
        XCTAssertEqual(category("COSTCO WHSE"), .shopping)
    }

    func testForeignTransactionFeeIsAFeeNotATransfer() {
        // "transaction" must not be mistaken for a "transfer".
        XCTAssertEqual(category("FOREIGN TRANSACTION FEE"), .fees)
    }

    func testUnknownMerchantFallsThrough() {
        XCTAssertNil(category("ACME WIDGETS LLC"))
    }
}
