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

    func testProviderTransferTagDoesNotExcludePeerToPeerFromBudget() {
        // The reported symptom: identical Zelle payments landed on different
        // sides of the budget purely because the bank tagged some of them
        // TRANSFER_OUT and left others uncategorized.
        let tagged = CategoryResolver.resolve(
            name: "ZELLE PAYMENT TO ALEX",
            merchant: nil,
            plaidPrimary: "TRANSFER_OUT",
            rules: []
        )
        let untagged = CategoryResolver.resolve(
            name: "ZELLE PAYMENT TO ALEX",
            merchant: nil,
            plaidPrimary: nil,
            rules: []
        )
        XCTAssertEqual(tagged, untagged)
        XCTAssertTrue(tagged.isSpending)
    }

    func testPeerToPeerStillRespectsASpecificProviderCategory() {
        let category = CategoryResolver.resolve(
            name: "PAYPAL *CORNER CAFE",
            merchant: nil,
            plaidPrimary: "FOOD_AND_DRINK",
            rules: []
        )
        XCTAssertEqual(category, .food)
    }

    func testUserRuleStillWinsOverPeerToPeer() {
        let rule = CategoryRule(matchText: "venmo", category: .food)
        let category = CategoryResolver.resolve(
            name: "VENMO PAYMENT",
            merchant: nil,
            plaidPrimary: "TRANSFER_OUT",
            rules: [rule]
        )
        XCTAssertEqual(category, .food)
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

    func testMoreSpecificUserRuleWinsRegardlessOfInputOrder() {
        let broad = CategoryRuleSpec(matchText: "uber", category: .transport)
        let specific = CategoryRuleSpec(matchText: "uber trip", category: .travel)

        XCTAssertEqual(
            CategoryRuleIndex(specs: [broad, specific]).category(for: "UBER *TRIP"),
            .travel
        )
        XCTAssertEqual(
            CategoryRuleIndex(specs: [specific, broad]).category(for: "UBER *TRIP"),
            .travel
        )
        XCTAssertEqual(
            CategoryRuleIndex(specs: [specific, broad]).category(for: "UBER *EATS"),
            .transport
        )
    }

    func testCanonicalRuleTextMatchesResolverNormalization() {
        XCTAssertEqual(
            CategoryRule.canonicalMatchText("Café's-Market"),
            CategoryRule.canonicalMatchText("cafés market")
        )
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

    func testPreparedKeyFastPathUpdatesRuleImmediately() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        context.insert(txn)

        try CategoryAssignment.assign(
            .food,
            to: txn,
            using: [],
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee"
        )

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(txn.resolvedCategory(using: rules), .food)
    }

    func testPreparedKeyFastPathReusesRuleDuringRapidChanges() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        context.insert(txn)

        try CategoryAssignment.assign(
            .food,
            to: txn,
            using: [],
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee"
        )
        // Deliberately pass the same stale query snapshot a second time. The
        // context fetch must find the just-saved rule instead of inserting a
        // duplicate while SwiftUI's @Query catches up.
        try CategoryAssignment.assign(
            .shopping,
            to: txn,
            using: [],
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee"
        )

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.category, .shopping)
    }

    func testPreparedKeyFastPathSupportsTransactionOnlyScope() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "VENMO PAYMENT")
        context.insert(txn)

        try CategoryAssignment.assign(
            .food,
            to: txn,
            using: [],
            in: context,
            scope: .thisTransactionOnly,
            preparedMatchKey: nil
        )

        XCTAssertEqual(txn.categoryOverride, .food)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CategoryRule>()).isEmpty)
    }

    func testPreparedKeyFastPathRejectsMissingBroadKey() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        context.insert(txn)

        XCTAssertThrowsError(
            try CategoryAssignment.assign(
                .food,
                to: txn,
                using: [],
                in: context,
                scope: .allMatching,
                preparedMatchKey: nil
            )
        )
    }

    func testBroadThenNarrowRestoresAbsentRule() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        let sibling = makeTransaction("t2", name: "BLUE BOTTLE COFFEE")
        context.insert(txn)
        context.insert(sibling)
        let original = try CategoryAssignment.preparedRuleState(
            for: "blue bottle coffee",
            using: [],
            in: context
        )

        try CategoryAssignment.assign(
            .health,
            to: txn,
            using: [],
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )
        let broadRules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(sibling.resolvedCategory(using: broadRules), .health)

        try CategoryAssignment.assign(
            .shopping,
            to: txn,
            using: broadRules,
            in: context,
            scope: .thisTransactionOnly,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )

        let finalRules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertTrue(finalRules.isEmpty)
        XCTAssertEqual(txn.resolvedCategory(using: finalRules), .shopping)
        XCTAssertEqual(sibling.resolvedCategory(using: finalRules), .food)
    }

    func testBroadThenNarrowRestoresExistingRule() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        let sibling = makeTransaction("t2", name: "BLUE BOTTLE COFFEE")
        let rule = CategoryRule(matchText: "blue bottle coffee", category: .groceries)
        context.insert(txn)
        context.insert(sibling)
        context.insert(rule)
        try context.save()
        let original = try CategoryAssignment.preparedRuleState(
            for: "blue bottle coffee",
            using: [rule],
            in: context
        )

        try CategoryAssignment.assign(
            .health,
            to: txn,
            using: [rule],
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )
        try CategoryAssignment.assign(
            .shopping,
            to: txn,
            using: [rule],
            in: context,
            scope: .thisTransactionOnly,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )

        let finalRules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(finalRules.count, 1)
        XCTAssertEqual(finalRules.first?.category, .groceries)
        XCTAssertEqual(txn.resolvedCategory(using: finalRules), .shopping)
        XCTAssertEqual(sibling.resolvedCategory(using: finalRules), .groceries)
    }

    func testScopeRoundTripLeavesOnlyFinalBroadChoice() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        context.insert(txn)
        let original = try CategoryAssignment.preparedRuleState(
            for: "blue bottle coffee",
            using: [],
            in: context
        )

        try CategoryAssignment.assign(
            .health,
            to: txn,
            using: [],
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )
        var rules = try context.fetch(FetchDescriptor<CategoryRule>())
        try CategoryAssignment.assign(
            .shopping,
            to: txn,
            using: rules,
            in: context,
            scope: .thisTransactionOnly,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )
        rules = try context.fetch(FetchDescriptor<CategoryRule>())
        try CategoryAssignment.assign(
            .services,
            to: txn,
            using: rules,
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )

        let finalRules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertNil(txn.categoryOverride)
        XCTAssertEqual(finalRules.count, 1)
        XCTAssertEqual(finalRules.first?.category, .services)
    }

    func testScopeRoundTripIgnoresDetachedRuleInStaleQuerySnapshot() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "BLUE BOTTLE COFFEE")
        context.insert(txn)
        let original = try CategoryAssignment.preparedRuleState(
            for: "blue bottle coffee",
            using: [],
            in: context
        )

        try CategoryAssignment.assign(
            .health,
            to: txn,
            using: [],
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )
        let staleRules = try context.fetch(FetchDescriptor<CategoryRule>())
        try CategoryAssignment.assign(
            .shopping,
            to: txn,
            using: staleRules,
            in: context,
            scope: .thisTransactionOnly,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )
        XCTAssertNil(staleRules.first?.modelContext, "the query snapshot now holds a detached model")

        try CategoryAssignment.assign(
            .services,
            to: txn,
            using: staleRules,
            in: context,
            scope: .allMatching,
            preparedMatchKey: "blue bottle coffee",
            originalRuleState: original
        )

        let finalRules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(finalRules.count, 1)
        XCTAssertEqual(finalRules.first?.category, .services)
        XCTAssertNil(txn.categoryOverride)
    }

    func testPreparedKeyRekeyRestoresOldRuleAndAppliesNewRuleAtomically() throws {
        let context = try makeContext()
        let txn = makeTransaction("t1", name: "OLD MERCHANT")
        context.insert(txn)
        let oldOriginal = try CategoryAssignment.preparedRuleState(
            for: "old merchant",
            using: [],
            in: context
        )

        try CategoryAssignment.assign(
            .health,
            to: txn,
            using: [],
            in: context,
            scope: .allMatching,
            preparedMatchKey: "old merchant",
            originalRuleState: oldOriginal
        )
        let currentRules = try context.fetch(FetchDescriptor<CategoryRule>())
        let newOriginal = try CategoryAssignment.preparedRuleState(
            for: "new merchant",
            using: currentRules,
            in: context
        )

        try CategoryAssignment.assign(
            .health,
            to: txn,
            using: currentRules,
            in: context,
            scope: .allMatching,
            preparedMatchKey: "new merchant",
            originalRuleState: newOriginal,
            restoringRuleState: oldOriginal
        )

        let finalRules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(finalRules.count, 1)
        XCTAssertEqual(finalRules.first?.matchText, "new merchant")
        XCTAssertEqual(finalRules.first?.category, .health)
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

    @MainActor
    func testTaughtRuleKeyAndMatchingIgnoreCase() throws {
        let container = try ModelContainer(
            for: TransactionRecord.self, CategoryRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let variants = ["SAFEWAY 1993 SEATTLE WA", "safeway #1993", "SaFeWaY"]
        let ledger = variants.map {
            TransactionRecord(
                id: $0, plaidTransactionId: $0, name: $0, merchantName: $0,
                amount: 10, isoCurrencyCode: "USD", date: Date(), pending: false,
                categoryPrimary: nil, categoryDetailed: nil, logoURL: nil, accountId: nil
            )
        }
        ledger.forEach(container.mainContext.insert)

        let keys = Set(ledger.map { CategoryAssignment.matchKey(for: $0, in: ledger) })
        XCTAssertEqual(keys, ["safeway"])

        let index = CategoryRuleIndex(
            specs: [CategoryRuleSpec(matchText: "SAFEWAY", category: .groceries)]
        )
        for variant in variants {
            XCTAssertEqual(index.category(for: variant), .groceries, variant)
        }
    }
}
