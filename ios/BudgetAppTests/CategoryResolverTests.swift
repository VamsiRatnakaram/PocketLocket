import XCTest
@testable import BudgetApp

final class CategoryResolverTests: XCTestCase {
    func testUserRuleOverridesEverything() {
        let rule = CategoryRule(matchText: "amazon", category: .health)
        let category = CategoryResolver.resolve(
            name: "AMAZON MARKETPLACE",
            merchant: "Amazon",
            plaidPrimary: "GENERAL_MERCHANDISE",
            rules: [rule]
        )
        XCTAssertEqual(category, .health)
    }

    func testHeuristicUsedWhenNoRule() {
        let category = CategoryResolver.resolve(
            name: "NETFLIX.COM",
            merchant: "Netflix",
            plaidPrimary: nil,
            rules: []
        )
        XCTAssertEqual(category, .entertainment)
    }

    func testFallsBackToPlaidWhenNoRuleOrHeuristic() {
        let category = CategoryResolver.resolve(
            name: "Blorp 4211",
            merchant: "Blorp Industries",
            plaidPrimary: "TRANSPORTATION",
            rules: []
        )
        XCTAssertEqual(category, .transport)
    }

    func testUnknownEverythingIsOther() {
        let category = CategoryResolver.resolve(
            name: "Zzz",
            merchant: nil,
            plaidPrimary: nil,
            rules: []
        )
        XCTAssertEqual(category, .other)
    }

    func testSubscriptionDetection() {
        XCTAssertTrue(MerchantHeuristics.isLikelySubscription("Spotify USA"))
        XCTAssertTrue(MerchantHeuristics.isLikelySubscription("Equinox Gym"))
        XCTAssertFalse(MerchantHeuristics.isLikelySubscription("Shell Gas Station"))
    }
}
