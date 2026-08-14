import XCTest
@testable import PocketLocket

@MainActor
final class SavingsSuggestionsCacheTests: XCTestCase {
    private func key(
        dataHash: Int = 1,
        rulesHash: Int = 2,
        excluded: String = "",
        budget: Double = 3000,
        monthStart: Date? = Date(timeIntervalSince1970: 0)
    ) -> SavingsSuggestionsCache.InputsKey {
        SavingsSuggestionsCache.InputsKey(
            dataHash: dataHash,
            rulesHash: rulesHash,
            excludedAccountsRaw: excluded,
            monthlyBudget: budget,
            monthStart: monthStart
        )
    }

    private let sample = [
        SavingsSuggestion(title: "t", detail: "d", monthlyImpact: 5, symbol: "leaf", tint: .green)
    ]

    override func setUp() {
        super.setUp()
        SavingsSuggestionsCache.shared.reset()
    }

    /// The regression this cache exists for: `SuggestionsView.body` reads
    /// `suggestions` several times per render, and re-renders on every
    /// keystroke in the Ask field.
    func testRepeatedReadsWithSameKeyComputeOnce() {
        let cache = SavingsSuggestionsCache.shared
        var computeCount = 0
        for _ in 0..<20 {
            _ = cache.suggestions(for: key()) {
                computeCount += 1
                return sample
            }
        }
        XCTAssertEqual(computeCount, 1)
        XCTAssertEqual(cache.missCount, 1)
    }

    func testReturnsCachedValue() {
        let cache = SavingsSuggestionsCache.shared
        _ = cache.suggestions(for: key()) { self.sample }
        let second = cache.suggestions(for: key()) { [] }
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.title, "t")
    }

    /// Each field has to invalidate, or the tab silently serves stale advice.
    func testEveryKeyFieldInvalidates() {
        let variants: [(String, SavingsSuggestionsCache.InputsKey)] = [
            ("dataHash", key(dataHash: 99)),
            ("rulesHash", key(rulesHash: 99)),
            ("excludedAccounts", key(excluded: "acct-1")),
            ("monthlyBudget", key(budget: 4000)),
            ("monthStart", key(monthStart: Date(timeIntervalSince1970: 5_000_000)))
        ]
        for (label, variant) in variants {
            SavingsSuggestionsCache.shared.reset()
            let cache = SavingsSuggestionsCache.shared
            var computeCount = 0
            _ = cache.suggestions(for: key()) { computeCount += 1; return self.sample }
            _ = cache.suggestions(for: variant) { computeCount += 1; return self.sample }
            XCTAssertEqual(computeCount, 2, "\(label) should invalidate the cache")
        }
    }

    /// The cache is shared rather than view state so that flipping the
    /// Analysis/Save segmented picker -- which destroys the view -- does not
    /// recompute a month of category resolution.
    func testSurvivesViewTeardown() {
        let cache = SavingsSuggestionsCache.shared
        var computeCount = 0
        // Simulates three round trips through the segmented picker.
        for _ in 0..<3 {
            _ = cache.suggestions(for: key()) { computeCount += 1; return self.sample }
        }
        XCTAssertEqual(computeCount, 1)
    }
}
