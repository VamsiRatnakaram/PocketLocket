import XCTest
@testable import PocketLocket

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

    func testDescriptorPunctuationAndSpacingAreNormalized() {
        XCTAssertEqual(category("APPLE COM BILL"), .services)
        XCTAssertEqual(category("7 ELEVEN #123"), .food)
    }

    func testHousingKeywordsDoNotMatchInsideRestaurantOrBarNames() {
        XCTAssertEqual(category("BRENT'S BISTRO"), .food)
        XCTAssertEqual(category("THE INTERNET CAFE"), .food)
        XCTAssertEqual(category("RENT PAYMENT"), .housing)
        XCTAssertEqual(category("CITY ELECTRIC UTILITY"), .housing)
    }

    func testRawBankDescriptorsAndLocalVenueTermsResolve() {
        XCTAssertEqual(category("SQ *RIVER CITY TAVERN 0042"), .food)
        XCTAssertEqual(category("TST*JANE'S BISTRO NEW YORK NY"), .food)
        XCTAssertEqual(category("PAYPAL *NETFLIX.COM"), .entertainment)
        XCTAssertEqual(category("WHOLEFOODS MKT #102"), .groceries)
    }

    func testDescriptorCleanerProducesReusableMerchantRule() {
        XCTAssertEqual(MerchantHeuristics.ruleMatchText(for: "SQ *River City Tavern 0042"), "river city tavern")
        XCTAssertEqual(MerchantHeuristics.ruleMatchText(for: "DEBIT CARD PURCHASE Target 1098"), "target")
    }

    func testExtendedMerchantCatalogCoversEverySpendingCategory() {
        XCTAssertEqual(category("HELLOFRESH WEEKLY MEAL PREP"), .groceries)
        XCTAssertEqual(category("REI CO OP STORE"), .shopping)
        XCTAssertEqual(category("PSEG ELECTRIC BILL"), .housing)
        XCTAssertEqual(category("CHARGEPOINT EV STATION"), .transport)
        XCTAssertEqual(category("RITZ CARLTON HOTEL"), .travel)
        XCTAssertEqual(category("SEATGEEK CONCERT"), .entertainment)
        XCTAssertEqual(category("BETTERHELP THERAPY"), .health)
        XCTAssertEqual(category("TURBOTAX DELUXE"), .services)
        XCTAssertEqual(category("EXPERIAN CREDIT REPORT"), .fees)
    }

    func testSectorAndToastFallbacksHandleLocalMerchants() {
        XCTAssertEqual(category("TST*LITTLE LEMON 1029"), .food)
        XCTAssertEqual(category("LOCAL FOOD HALL"), .food)
        XCTAssertEqual(category("SMITH PHYSICAL THERAPY"), .health)
        XCTAssertEqual(category("CITY PROPERTY MANAGEMENT"), .housing)
        XCTAssertEqual(category("METRO RENTAL CAR"), .travel)
        XCTAssertEqual(category("NEIGHBORHOOD PLUMBING"), .services)
    }

    func testForeignTransactionFeeIsAFeeNotATransfer() {
        // "transaction" must not be mistaken for a "transfer".
        XCTAssertEqual(category("FOREIGN TRANSACTION FEE"), .fees)
    }

    func testUnknownMerchantFallsThrough() {
        XCTAssertNil(category("ACME WIDGETS LLC"))
    }
}
