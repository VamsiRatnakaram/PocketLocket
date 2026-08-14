import XCTest
@testable import PocketLocket

final class AnalysisSnapshotTests: XCTestCase {
    private func date(_ month: Int, _ day: Int = 1) -> Date {
        DateComponents(calendar: .current, year: 2024, month: month, day: day).date!
    }

    private func input(_ title: String, _ amount: Double, _ category: SpendCategory, _ month: Int) -> MerchantAnalytics.Input {
        MerchantAnalytics.Input(title: title, amount: amount, category: category, date: date(month))
    }

    private var sample: [MerchantAnalytics.Input] {
        [
            input("Starbucks #101", 5, .food, 1),
            input("Starbucks #101", 6, .food, 2),
            input("Starbucks #101", 7, .food, 3),
            input("Trader Joes", 80, .groceries, 1),
            input("Trader Joes", 90, .groceries, 2),
        ]
    }

    func testSnapshotMatchesIndividualAnalyticsCalls() {
        let snapshot = AnalysisSnapshot.make(inputs: sample, categoryFilter: nil)
        let stats = MerchantAnalytics.merchantStats(sample)

        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(snapshot.topByFrequency.map(\.id), MerchantAnalytics.topByFrequency(stats, limit: 8).map(\.id))
        XCTAssertEqual(snapshot.topBySpend.map(\.id), MerchantAnalytics.topBySpend(stats, limit: 8).map(\.id))
        XCTAssertEqual(
            snapshot.recurring.map(\.id),
            MerchantAnalytics.recurringMerchants(sample, minMonths: 3).map(\.id)
        )
        XCTAssertEqual(snapshot.categoryAverages.map(\.id), MerchantAnalytics.categoryAverages(sample).map(\.id))
        XCTAssertEqual(snapshot.categoryMonthly.count, MerchantAnalytics.categoryMonthlyTotals(sample).count)
    }

    /// Passing pre-computed stats must not change results — it only skips a
    /// redundant grouping pass.
    func testRecurringWithPrecomputedStatsMatches() {
        let stats = MerchantAnalytics.merchantStats(sample)
        XCTAssertEqual(
            MerchantAnalytics.recurringMerchants(sample, minMonths: 3, stats: stats).map(\.id),
            MerchantAnalytics.recurringMerchants(sample, minMonths: 3).map(\.id)
        )
    }

    func testFilterRestrictsToSelectedCategory() {
        let snapshot = AnalysisSnapshot.make(inputs: sample, categoryFilter: .groceries)
        XCTAssertEqual(snapshot.topBySpend.map(\.name), ["Trader Joes"])
        XCTAssertTrue(snapshot.availableCategories.contains(.food), "availableCategories stays unfiltered")
    }

    /// The chart and averages list render *above* the category chips, so
    /// resizing them on filter change moved the chips out from under the tap
    /// that triggered it. They must stay identical across filters.
    func testFilterLeavesChartAndAveragesUnchanged() {
        let unfiltered = AnalysisSnapshot.make(inputs: sample, categoryFilter: nil)
        let filtered = AnalysisSnapshot.make(inputs: sample, categoryFilter: .groceries)

        XCTAssertEqual(filtered.categoryAverages.map(\.id), unfiltered.categoryAverages.map(\.id))
        XCTAssertEqual(filtered.categoryMonthly.count, unfiltered.categoryMonthly.count)
        XCTAssertTrue(
            filtered.categoryMonthly.contains { $0.category == .food },
            "The chart keeps every category's line so its height can't change"
        )
    }

    func testEmptyInputsProduceEmptySnapshot() {
        XCTAssertTrue(AnalysisSnapshot.make(inputs: [], categoryFilter: nil).isEmpty)
    }

    func testCacheReusesInputsUntilKeyChanges() {
        let cache = AnalysisSnapshotCache()
        var builds = 0
        let key = AnalysisSnapshotCache.InputsKey(dataHash: 1, rulesHash: 1, excludedAccountsRaw: "", range: .all)
        let build: () -> [MerchantAnalytics.Input] = { builds += 1; return self.sample }

        _ = cache.snapshot(key: key, categoryFilter: nil, buildInputs: build)
        _ = cache.snapshot(key: key, categoryFilter: nil, buildInputs: build)
        XCTAssertEqual(builds, 1, "repeat renders must not rebuild inputs")

        var changed = key
        changed.dataHash = 2
        _ = cache.snapshot(key: changed, categoryFilter: nil, buildInputs: build)
        XCTAssertEqual(builds, 2, "a data change must invalidate the cache")

        var ruleChanged = changed
        ruleChanged.rulesHash = 9
        _ = cache.snapshot(key: ruleChanged, categoryFilter: nil, buildInputs: build)
        XCTAssertEqual(builds, 3, "a rule change must invalidate the cache")
    }

    func testCacheRecomputesSnapshotWhenFilterChanges() {
        let cache = AnalysisSnapshotCache()
        var builds = 0
        let key = AnalysisSnapshotCache.InputsKey(dataHash: 1, rulesHash: 1, excludedAccountsRaw: "", range: .all)
        let build: () -> [MerchantAnalytics.Input] = { builds += 1; return self.sample }

        let all = cache.snapshot(key: key, categoryFilter: nil, buildInputs: build)
        let groceries = cache.snapshot(key: key, categoryFilter: .groceries, buildInputs: build)

        XCTAssertEqual(builds, 1, "filter changes reuse resolved inputs")
        XCTAssertNotEqual(all.topBySpend.count, groceries.topBySpend.count)
        XCTAssertEqual(groceries.topBySpend.map(\.name), ["Trader Joes"])
    }

    func testNormalizeCachingIsStable() {
        let first = MerchantNormalizer.normalize("SQ *Blue Bottle Coffee #12")
        let second = MerchantNormalizer.normalize("SQ *Blue Bottle Coffee #12")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "Blue Bottle Coffee")
    }
}
