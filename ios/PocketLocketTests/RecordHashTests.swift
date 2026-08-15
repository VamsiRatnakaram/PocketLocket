import XCTest
@testable import PocketLocket

/// `RecordHash` keys the memo caches on the Transactions and Home tabs, so a
/// field it misses is a field whose edits never reach the screen.
final class RecordHashTests: XCTestCase {
    private func txn(
        id: String = "1",
        name: String = "SQ *BLUE BOTTLE",
        merchantName: String? = "Blue Bottle",
        amount: Double = 5,
        currency: String = "USD",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        categoryPrimary: String? = nil,
        accountId: String? = "checking"
    ) -> TransactionRecord {
        TransactionRecord(
            id: id,
            plaidTransactionId: id,
            name: name,
            merchantName: merchantName,
            amount: amount,
            isoCurrencyCode: currency,
            date: date,
            pending: false,
            categoryPrimary: categoryPrimary,
            categoryDetailed: nil,
            logoURL: nil,
            accountId: accountId
        )
    }

    func testIdenticalContentHashesEqual() {
        XCTAssertEqual(RecordHash.transactions([txn()]), RecordHash.transactions([txn()]))
    }

    /// The one that bit us: `title` collapses to `merchantName` when it is set,
    /// so hashing `title` alone hid every edit to `name` — which drives both
    /// category resolution and search.
    func testNameChangeIsDetectedEvenWhenMerchantNameMasksIt() {
        let before = RecordHash.transactions([txn(name: "SQ *BLUE BOTTLE")])
        let after = RecordHash.transactions([txn(name: "VENMO PAYMENT")])
        XCTAssertNotEqual(before, after)
    }

    func testMerchantNameChangeIsDetected() {
        XCTAssertNotEqual(
            RecordHash.transactions([txn(merchantName: "Blue Bottle")]),
            RecordHash.transactions([txn(merchantName: "Peet's")])
        )
    }

    func testAmountCurrencyDateCategoryAndAccountChangesAreDetected() {
        let base = RecordHash.transactions([txn()])
        XCTAssertNotEqual(base, RecordHash.transactions([txn(amount: 6)]))
        XCTAssertNotEqual(base, RecordHash.transactions([txn(currency: "EUR")]))
        XCTAssertNotEqual(base, RecordHash.transactions([txn(date: Date(timeIntervalSince1970: 1_700_086_400))]))
        XCTAssertNotEqual(base, RecordHash.transactions([txn(categoryPrimary: "FOOD_AND_DRINK")]))
        XCTAssertNotEqual(base, RecordHash.transactions([txn(accountId: "savings")]))
    }

    func testCountChangeIsDetected() {
        XCTAssertNotEqual(
            RecordHash.transactions([txn()]),
            RecordHash.transactions([txn(), txn(id: "2")])
        )
    }

    func testRuleChangesAreDetected() {
        let base = [CategoryRule(matchText: "blue bottle", category: .food)]
        XCTAssertEqual(RecordHash.rules(base), RecordHash.rules([CategoryRule(matchText: "blue bottle", category: .food)]))
        XCTAssertNotEqual(RecordHash.rules(base), RecordHash.rules([CategoryRule(matchText: "blue bottle", category: .shopping)]))
        XCTAssertNotEqual(RecordHash.rules(base), RecordHash.rules([CategoryRule(matchText: "peets", category: .food)]))
        XCTAssertNotEqual(RecordHash.rules(base), RecordHash.rules([]))
    }

    func testGroupingRuleChangesAreDetected() {
        let base = [
            MerchantGroupingRule(
                sourceKey: "MS CAFE 34",
                groupID: "cafe-group",
                groupName: "Cafe 34"
            )
        ]
        XCTAssertEqual(
            RecordHash.groupingRules(base),
            RecordHash.groupingRules([
                MerchantGroupingRule(
                    sourceKey: "MS CAFE 34",
                    groupID: "cafe-group",
                    groupName: "Cafe 34"
                )
            ])
        )
        XCTAssertNotEqual(
            RecordHash.groupingRules(base),
            RecordHash.groupingRules([
                MerchantGroupingRule(
                    sourceKey: "MS CAFE 34",
                    groupID: "cafe-group",
                    groupName: "Work Cafe"
                )
            ])
        )
    }
}
