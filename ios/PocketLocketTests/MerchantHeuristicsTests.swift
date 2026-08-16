import XCTest
@testable import PocketLocket

final class MerchantHeuristicsTests: XCTestCase {
    func testInvestmentCashActivityCategories() {
        XCTAssertEqual(
            MerchantHeuristics.category(for: "INTEREST EARNED CASH (315994103)"),
            .income
        )
        XCTAssertEqual(
            MerchantHeuristics.category(for: "REINVESTMENT CASH (315994103)"),
            .transfer
        )
        XCTAssertEqual(
            MerchantHeuristics.category(for: "contribution"),
            nil
        )
        XCTAssertNotEqual(
            MerchantHeuristics.category(for: "ACTBLUE POLITICAL CONTRIBUTION"),
            .transfer
        )
    }

    private func category(_ text: String) -> SpendCategory? {
        MerchantHeuristics.category(for: text.lowercased())
    }

    func testCardPaymentsAndTransfersAreNotSpend() {
        // With multiple accounts linked, these must NOT inflate the spend ring.
        XCTAssertEqual(category("AUTOPAY PAYMENT THANK YOU"), .transfer)
        XCTAssertEqual(category("ONLINE TRANSFER TO SAVINGS"), .transfer)
        XCTAssertEqual(category("VENMO CASHOUT"), .transfer)
        XCTAssertEqual(category("ROBINHOOD FUNDING"), .transfer)
        XCTAssertFalse(SpendCategory.transfer.isSpending)
    }

    func testPeerToPeerPaymentsAreNotAssumedToBeTransfers() {
        // The rail says how the money moved, not what it was for: the same
        // descriptor covers repaying a friend and buying your half of dinner.
        // Guessing "transfer" drops real spending out of the budget silently.
        XCTAssertNil(category("ZELLE TO ALEX"))
        XCTAssertNil(category("ZELLE TRANSFER TO ALEX"))
        XCTAssertNil(category("VENMO PAYMENT"))
        XCTAssertNil(category("CASH APP*JORDAN"))
        XCTAssertNil(category("PAYPAL *SARAH M"))

        // ...but moving your own money off the platform really is a transfer.
        XCTAssertEqual(category("VENMO CASHOUT"), .transfer)
        XCTAssertEqual(category("ZELLE INSTANT TRANSFER"), .transfer)

        // A rail word must not smuggle it back in through the keyword table.
        XCTAssertNil(category("VENMO PAYMENT ACH DEBIT"))
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

    func testSharedScootersAndBikesAreTransport() {
        XCTAssertEqual(category("LIME*1"), .transport)
        XCTAssertEqual(category("Lime"), .transport)
        XCTAssertEqual(category("LIMEBIKE"), .transport)
        XCTAssertEqual(category("BIRD RIDES INC"), .transport)
        XCTAssertEqual(category("CITI BIKE NYC"), .transport)
    }

    /// "lime" and "spin" are ordinary words as well as scooter brands, so the
    /// restaurants that contain them are listed ahead of the brand.
    func testRestaurantsContainingScooterBrandNamesStayFood() {
        XCTAssertEqual(category("LIME LEAF THAI CUISINE"), .food)
        XCTAssertEqual(category("LIME FRESH MEXICAN GRILL"), .food)
        XCTAssertEqual(category("KEY LIME PIE CO"), .food)
        XCTAssertEqual(category("SPIN PIZZA KC"), .food)
    }

    /// Whole-token matching, so a brand name inside a longer word is not a hit.
    /// Asserted as "not transport" rather than "no category", because the rest
    /// of the descriptor is allowed to match something else.
    func testScooterBrandDoesNotMatchInsideLongerWords() {
        XCTAssertNotEqual(category("SUBLIME DONUTS"), .transport)
        XCTAssertNotEqual(category("LIMELIGHT SUPPLY CO"), .transport)
    }

    func testUnknownMerchantFallsThrough() {
        XCTAssertNil(category("ACME WIDGETS LLC"))
    }

    /// Issuers use their own abbreviations for a card payoff, and token
    /// matching means "cc pymt" cannot reach the "mobile pymt" inside Capital
    /// One's descriptor — each abbreviation needs its own entry.
    func testIssuerShortFormCardPaymentsAreTransfers() {
        for descriptor in ["CAPITAL ONE MOBILE PYMT", "CHASE CREDIT CRD AUTOPAY",
                           "DISCOVER E-PAYMENT", "AMEX ONLINE PYMT", "DISCOVER AUTOPAY"] {
            XCTAssertEqual(MerchantHeuristics.category(for: descriptor.lowercased()), .transfer, descriptor)
        }
    }

    /// "Autopay" is not card-payment evidence. Treating it as one removed real
    /// spending from the budget entirely.
    func testBillerAutopayIsNotATransfer() {
        for (descriptor, expected) in [("NETFLIX AUTOPAY", SpendCategory.entertainment),
                                       ("VERIZON AUTOPAY", .housing),
                                       ("T-MOBILE PAYMENT", .housing)] {
            XCTAssertEqual(MerchantHeuristics.category(for: descriptor.lowercased()), expected, descriptor)
        }
    }
}
