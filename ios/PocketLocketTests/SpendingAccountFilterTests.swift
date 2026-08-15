import XCTest
@testable import PocketLocket

final class SpendingAccountFilterTests: XCTestCase {
    /// The Transactions "In budget" filter used to test only `isSpending`, so
    /// it listed refunds and excluded-account rows that contribute nothing to
    /// the ring. All three now go through this one definition.
    func testCountsTowardBudgetRequiresSpendPositiveAmountAndIncludedAccount() {
        XCTAssertTrue(SpendingAccountFilter.countsTowardBudget(
            category: .food, amount: 20, accountId: "a", excluded: []))
        XCTAssertFalse(SpendingAccountFilter.countsTowardBudget(
            category: .food, amount: -20, accountId: "a", excluded: []),
            "a refund is money in, not budgeted spending")
        XCTAssertFalse(SpendingAccountFilter.countsTowardBudget(
            category: .food, amount: 20, accountId: "a", excluded: ["a"]),
            "an excluded account never feeds the budget")
        XCTAssertFalse(SpendingAccountFilter.countsTowardBudget(
            category: .transfer, amount: 20, accountId: "a", excluded: []),
            "transfers are not spending")
    }

    /// `DateInterval.contains` includes `end`, so a transaction stamped exactly
    /// at the next month's start was counted in both months.
    func testHalfOpenMembershipExcludesTheEndInstant() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400)
        let interval = DateInterval(start: start, end: end)

        XCTAssertTrue(interval.containsHalfOpen(start))
        XCTAssertTrue(interval.containsHalfOpen(end.addingTimeInterval(-1)))
        XCTAssertFalse(interval.containsHalfOpen(end))
        XCTAssertTrue(interval.contains(end), "documents the behavior being avoided")
    }
}
