import XCTest
@testable import PocketLocket
import SwiftData

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

// MARK: - Per-transaction overrides

@MainActor
final class PerTransactionCategoryTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TransactionRecord.self, AccountRecord.self, CategoryRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeTransaction(_ id: String, name: String, amount: Double = 40) -> TransactionRecord {
        TransactionRecord(
            id: id, plaidTransactionId: id, name: name, merchantName: nil,
            amount: amount, isoCurrencyCode: "USD", date: Date(), pending: false,
            categoryPrimary: nil, categoryDetailed: nil, logoURL: nil, accountId: "acct"
        )
    }

    /// The whole point: correcting one Venmo must not retag the rest.
    func testNarrowScopeLeavesOtherTransactionsFromSameMerchantAlone() throws {
        let context = try makeContext()
        let dinner = makeTransaction("t1", name: "VENMO PAYMENT")
        let repayment = makeTransaction("t2", name: "VENMO PAYMENT")
        context.insert(dinner)
        context.insert(repayment)

        try CategoryAssignment.assign(.food, to: [dinner], using: [], in: context, scope: .thisTransactionOnly)

        XCTAssertEqual(dinner.resolvedCategory(using: []), .food)
        XCTAssertEqual(repayment.resolvedCategory(using: []), .transfer)
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertTrue(rules.isEmpty, "A narrow assignment must not teach a merchant-wide rule")
    }

    func testBroadScopeStillTeachesARule() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        context.insert(txn)

        try CategoryAssignment.assign(.food, to: [txn], using: [], in: context, scope: .allMatching)

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.category, .food)
    }

    func testOverrideOutranksAUserRule() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "VENMO PAYMENT")
        context.insert(txn)
        let rule = CategoryRule(matchText: "venmo payment", category: .shopping)
        context.insert(rule)

        try CategoryAssignment.assign(.food, to: [txn], using: [rule], in: context, scope: .thisTransactionOnly)

        XCTAssertEqual(txn.resolvedCategory(using: [rule]), .food)
    }

    /// Teaching a rule has to clear any stale override, otherwise the broader
    /// choice would appear to do nothing on the transaction you made it from.
    func testBroadScopeClearsAnExistingOverride() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "VENMO PAYMENT")
        context.insert(txn)

        try CategoryAssignment.assign(.food, to: [txn], using: [], in: context, scope: .thisTransactionOnly)
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        try CategoryAssignment.assign(.shopping, to: [txn], using: rules, in: context, scope: .allMatching)

        XCTAssertNil(txn.categoryOverride)
        let updated = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(txn.resolvedCategory(using: updated), .shopping)
    }

    func testUntouchedTransactionsResolveAsBefore() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        context.insert(txn)

        XCTAssertNil(txn.categoryOverride)
        XCTAssertEqual(txn.resolvedCategory(using: []), .food)
    }

    func testPeerToPeerDetection() {
        XCTAssertTrue(MerchantHeuristics.isPeerToPeer("VENMO PAYMENT JOHN SMITH"))
        XCTAssertTrue(MerchantHeuristics.isPeerToPeer("ZELLE TO ALEX"))
        XCTAssertTrue(MerchantHeuristics.isPeerToPeer("CASH APP TRANSFER"))
        XCTAssertFalse(MerchantHeuristics.isPeerToPeer("BLUE BOTTLE COFFEE"))
        XCTAssertFalse(MerchantHeuristics.isPeerToPeer("CHASE CREDIT CRD AUTOPAY"))
    }
}
