import XCTest
@testable import PocketLocket

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

    func testRecognizedProviderCategoryBeatsHeuristic() {
        let category = CategoryResolver.resolve(
            name: "SHELL OIL 4567",
            merchant: nil,
            plaidPrimary: "groceries",
            rules: []
        )
        XCTAssertEqual(category, .groceries)
    }

    func testUserRuleIgnoresDescriptorCaseAndPunctuation() {
        let rule = CategoryRule(matchText: "Maria's Market", category: .groceries)
        let category = CategoryResolver.resolve(
            name: "MARIAS MARKET #27",
            merchant: nil,
            plaidPrimary: nil,
            rules: [rule]
        )
        XCTAssertEqual(category, .groceries)
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
