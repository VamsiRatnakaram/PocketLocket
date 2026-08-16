import XCTest
@testable import PocketLocket

@MainActor
final class SavingsSuggestionsCacheTests: XCTestCase {
    private func key(
        dataHash: Int = 1,
        rulesHash: Int = 2,
        reimbursementsHash: Int = 0,
        excluded: String = "",
        budget: Double = 3000,
        monthStart: Date? = Date(timeIntervalSince1970: 0)
    ) -> SavingsSuggestionsCache.InputsKey {
        SavingsSuggestionsCache.InputsKey(
            dataHash: dataHash,
            rulesHash: rulesHash,
            reimbursementsHash: reimbursementsHash,
            excludedAccountsRaw: excluded,
            monthlyBudget: budget,
            monthStart: monthStart
        )
    }

    private let sample = [
        SavingsSuggestion(title: "t", detail: "d", monthlyImpact: 5, symbol: "leaf", tint: .green)
    ]

    func testStoreAndValueUseProductionCachePath() {
        let cache = SavingsSuggestionsCache()

        XCTAssertNil(cache.value(for: key()))
        cache.store(sample, for: key())

        XCTAssertEqual(cache.value(for: key())?.first?.title, "t")
        XCTAssertEqual(cache.missCount, 1)
    }

    /// Each field has to invalidate, or the tab silently serves stale advice.
    func testEveryKeyFieldInvalidates() {
        let variants: [(String, SavingsSuggestionsCache.InputsKey)] = [
            ("dataHash", key(dataHash: 99)),
            ("rulesHash", key(rulesHash: 99)),
            ("reimbursementsHash", key(reimbursementsHash: 99)),
            ("excludedAccounts", key(excluded: "acct-1")),
            ("monthlyBudget", key(budget: 4000)),
            ("monthStart", key(monthStart: Date(timeIntervalSince1970: 5_000_000)))
        ]

        for (label, variant) in variants {
            let cache = SavingsSuggestionsCache()
            cache.store(sample, for: key())
            XCTAssertNil(cache.value(for: variant), "\(label) should invalidate the cache")
        }
    }

    func testResetClearsValueAndCounter() {
        let cache = SavingsSuggestionsCache()
        cache.store(sample, for: key())

        cache.reset()

        XCTAssertNil(cache.value(for: key()))
        XCTAssertEqual(cache.missCount, 0)
    }
}
