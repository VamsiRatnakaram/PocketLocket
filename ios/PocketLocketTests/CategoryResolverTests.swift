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
        // Asserted as "unchanged" rather than as a specific category: what this
        // test is about is the narrow scope not reaching the sibling, not
        // whatever the heuristics happen to default a bare Venmo to.
        XCTAssertNil(repayment.categoryOverride)
        XCTAssertNotEqual(repayment.resolvedCategory(using: []), .food)
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

    @MainActor
    func testTaughtRuleReachesEveryDescriptorFromTheSameMerchant() throws {
        let families: [[String]] = [
            ["SAFEWAY 1993 SEATTLE WA", "Safeway #1993", "Safeway"],
            ["PUGET SOUND ENERGY BILLPAY 4471", "PUGET SOUND ENERGY WEBPAY 8832"],
            ["Lime*RIDE S2FQ", "LIME*1"],
            ["WEBPASS INC 123ABC", "WEBPASS INC 998ZZ"],
        ]
        let container = try ModelContainer(
            for: TransactionRecord.self, CategoryRule.self, AccountRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for family in families {
            let ledger = family.map {
                TransactionRecord(
                    id: $0, plaidTransactionId: $0, name: $0, merchantName: $0,
                    amount: 10, isoCurrencyCode: "USD", date: Date(), pending: false,
                    categoryPrimary: nil, categoryDetailed: nil, logoURL: nil, accountId: nil
                )
            }
            ledger.forEach(container.mainContext.insert)

            // Whichever transaction the user happens to tap must teach a rule
            // that reaches the whole merchant.
            for taught in ledger {
                let key = CategoryAssignment.matchKey(for: taught, in: ledger)
                let index = CategoryRuleIndex(
                    specs: [CategoryRuleSpec(matchText: key, category: .housing)]
                )
                let reached = family.filter { index.category(for: $0) != nil }
                XCTAssertEqual(reached.count, family.count, "taught from \(taught.name) as \(key)")
            }
            ledger.forEach(container.mainContext.delete)
        }
    }

    @MainActor
    func testTaughtRuleDoesNotLeakIntoADifferentSubBrand() throws {
        let container = try ModelContainer(
            for: TransactionRecord.self, CategoryRule.self, AccountRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ledger = ["UBER *TRIP", "UBER *EATS"].map {
            TransactionRecord(
                    id: $0, plaidTransactionId: $0, name: $0, merchantName: $0,
                    amount: 10, isoCurrencyCode: "USD", date: Date(), pending: false,
                    categoryPrimary: nil, categoryDetailed: nil, logoURL: nil, accountId: nil
                )
        }
        ledger.forEach(container.mainContext.insert)
        let eatsKey = CategoryAssignment.matchKey(for: ledger[1], in: ledger)
        let eats = CategoryRuleIndex(specs: [CategoryRuleSpec(matchText: eatsKey, category: .food)])
        XCTAssertNil(eats.category(for: "UBER *TRIP"))
        XCTAssertNotNil(eats.category(for: "UBER *EATS"))

        // …and the reverse: teaching from a ride must not swallow Uber Eats.
        let tripKey = CategoryAssignment.matchKey(for: ledger[0], in: ledger)
        let trip = CategoryRuleIndex(specs: [CategoryRuleSpec(matchText: tripKey, category: .transport)])
        XCTAssertNil(trip.category(for: "UBER *EATS"))
        XCTAssertNotNil(trip.category(for: "UBER *TRIP"))
    }
}
