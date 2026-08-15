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
        XCTAssertEqual(snapshot.categoryAverages.map(\.id), MerchantAnalytics.categoryAverages(sample).map(\.id))
        XCTAssertEqual(snapshot.categoryMonthly.count, MerchantAnalytics.categoryTrendTotals(sample).count)
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

    func testSnapshotAppliesUserGroupingRules() {
        let groupID = UUID().uuidString
        let groupingRules = [
            MerchantGroupingRuleSpec(
                sourceKey: "Starbucks #101",
                groupID: groupID,
                groupName: "Coffee"
            ),
            MerchantGroupingRuleSpec(
                sourceKey: "Trader Joes",
                groupID: groupID,
                groupName: "Coffee"
            ),
        ]
        let snapshot = AnalysisSnapshot.make(
            inputs: sample,
            categoryFilter: nil,
            groupingRules: groupingRules
        )

        XCTAssertEqual(snapshot.topBySpend.map(\.name), ["Coffee"])
        XCTAssertEqual(snapshot.topBySpend.first?.visitCount, sample.count)
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

    func testAnalysisWindowDoesNotChangeCurrentMonthComparison() throws {
        let inputs = [
            input("Cafe", 100, .food, 1),
            input("Cafe", 200, .food, 2),
            input("Cafe", 300, .food, 3),
        ]
        let januaryOnly = DateInterval(start: date(1), end: date(2))
        let februaryOnly = DateInterval(start: date(2), end: date(3))

        let januarySnapshot = AnalysisSnapshot.make(
            inputs: inputs,
            window: januaryOnly,
            categoryFilter: nil,
            chartEnd: date(3, 15)
        )
        let februarySnapshot = AnalysisSnapshot.make(
            inputs: inputs,
            window: februaryOnly,
            categoryFilter: nil,
            chartEnd: date(3, 15)
        )

        let januaryComparison = try XCTUnwrap(januarySnapshot.categoryAverages.first)
        let februaryComparison = try XCTUnwrap(februarySnapshot.categoryAverages.first)
        XCTAssertEqual(januarySnapshot.comparisonMonthStart, date(3))
        XCTAssertEqual(februarySnapshot.comparisonMonthStart, date(3))
        XCTAssertEqual(januaryComparison.currentMonthSpend, 300, accuracy: 0.001)
        XCTAssertEqual(januaryComparison.priorMonthsAverage, 150, accuracy: 0.001)
        XCTAssertEqual(
            januaryComparison.currentMonthSpend,
            februaryComparison.currentMonthSpend,
            accuracy: 0.001
        )
        XCTAssertEqual(
            januaryComparison.priorMonthsAverage,
            februaryComparison.priorMonthsAverage,
            accuracy: 0.001
        )
        XCTAssertEqual(januaryComparison.priorMonthCount, februaryComparison.priorMonthCount)
    }

    func testEmptySelectedWindowKeepsFullDomainChartAvailable() {
        let emptyWindow = DateInterval(start: date(6), end: date(7))
        let snapshot = AnalysisSnapshot.make(inputs: sample, window: emptyWindow, categoryFilter: nil)

        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertTrue(snapshot.topBySpend.isEmpty)
        XCTAssertFalse(snapshot.categoryMonthly.isEmpty)
    }

    func testEmptyInputsProduceEmptySnapshot() {
        XCTAssertTrue(AnalysisSnapshot.make(inputs: [], categoryFilter: nil).isEmpty)
    }

    func testCacheReusesInputsUntilKeyChanges() {
        let cache = AnalysisSnapshotCache()
        var builds = 0
        let key = AnalysisSnapshotCache.InputsKey(dataHash: 1, rulesHash: 1, excludedAccountsRaw: "")
        let build: () -> [MerchantAnalytics.Input]? = { builds += 1; return self.sample }

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

        var groupingChanged = ruleChanged
        groupingChanged.groupingRulesHash = 9
        _ = cache.snapshot(key: groupingChanged, categoryFilter: nil, buildInputs: build)
        XCTAssertEqual(builds, 4, "a grouping correction must invalidate the cache")

        var reimbursementChanged = groupingChanged
        reimbursementChanged.reimbursementsHash = 9
        _ = cache.snapshot(key: reimbursementChanged, categoryFilter: nil, buildInputs: build)
        XCTAssertEqual(builds, 5, "a reimbursement change must invalidate resolved amounts")

        let firstWindow = DateInterval(start: date(1), end: date(2))
        let secondWindow = DateInterval(start: date(2), end: date(3))
        _ = cache.snapshot(key: reimbursementChanged, window: firstWindow, categoryFilter: nil, buildInputs: build)
        _ = cache.snapshot(key: reimbursementChanged, window: secondWindow, categoryFilter: nil, buildInputs: build)
        XCTAssertEqual(builds, 5, "moving the window must reuse already-resolved inputs")
    }

    func testCacheRecomputesSnapshotWhenFilterChanges() throws {
        let cache = AnalysisSnapshotCache()
        var builds = 0
        let key = AnalysisSnapshotCache.InputsKey(dataHash: 1, rulesHash: 1, excludedAccountsRaw: "")
        let build: () -> [MerchantAnalytics.Input]? = { builds += 1; return self.sample }

        let all = try XCTUnwrap(cache.snapshot(key: key, categoryFilter: nil, buildInputs: build))
        let groceries = try XCTUnwrap(cache.snapshot(key: key, categoryFilter: .groceries, buildInputs: build))

        XCTAssertEqual(builds, 1, "filter changes reuse resolved inputs")
        XCTAssertNotEqual(all.topBySpend.count, groceries.topBySpend.count)
        XCTAssertEqual(groceries.topBySpend.map(\.name), ["Trader Joes"])
    }

    func testChartEndRebuildsTrendWithoutRebuildingResolvedInputs() throws {
        let cache = AnalysisSnapshotCache()
        let key = AnalysisSnapshotCache.InputsKey(dataHash: 1, rulesHash: 1, excludedAccountsRaw: "")
        var builds = 0
        let build: () -> [MerchantAnalytics.Input]? = { builds += 1; return self.sample }

        _ = cache.snapshot(key: key, chartEnd: date(4), categoryFilter: nil, buildInputs: build)
        let updated = try XCTUnwrap(
            cache.snapshot(key: key, chartEnd: date(5), categoryFilter: nil, buildInputs: build)
        )

        XCTAssertEqual(builds, 1)
        XCTAssertEqual(updated.categoryMonthly.last?.monthStart, date(5))
    }

    func testNormalizeCachingIsStable() {
        let first = MerchantNormalizer.normalize("SQ *Blue Bottle Coffee #12")
        let second = MerchantNormalizer.normalize("SQ *Blue Bottle Coffee #12")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "Blue Bottle Coffee")
    }

    func testArbitraryDateWindowFractionsRoundTrip() {
        let domain = DateInterval(start: date(1), end: date(5))
        let fractions = 0.173...0.814
        let interval = AnalysisDateWindow.interval(for: fractions, in: domain)
        let result = AnalysisDateWindow.fractions(for: interval, in: domain)

        XCTAssertEqual(result.lowerBound, fractions.lowerBound, accuracy: 0.000_001)
        XCTAssertEqual(result.upperBound, fractions.upperBound, accuracy: 0.000_001)
    }

    func testDateWindowSnapsToFullCalendarMonths() {
        let domain = DateInterval(start: date(1), end: date(7))
        let selection = DateInterval(start: date(2, 10), end: date(5, 22))

        let snapped = AnalysisDateWindow.snappedToMonths(selection, in: domain)

        XCTAssertEqual(snapped.start, date(2))
        XCTAssertEqual(snapped.end, date(6))
    }

    func testDateWindowDomainIsStableWithinTheSameDay() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2025, month: 8, day: 14, hour: 8))!
        let evening = calendar.date(from: DateComponents(year: 2025, month: 8, day: 14, hour: 20))!
        let transaction = calendar.date(from: DateComponents(year: 2025, month: 1, day: 2, hour: 12))!

        let morningDomain = AnalysisDateWindow.domain(for: [transaction], reference: morning, calendar: calendar)
        let eveningDomain = AnalysisDateWindow.domain(for: [transaction], reference: evening, calendar: calendar)

        XCTAssertEqual(morningDomain, eveningDomain)
        XCTAssertTrue(morningDomain.contains(transaction))
    }

    func testDateWindowFindsNewestFirstSlice() {
        let dates = [date(5), date(4), date(3), date(2), date(1)]
        let selection = DateInterval(start: date(2), end: date(5))
        let indices = AnalysisDateWindow.indices(count: dates.count, dateAt: { dates[$0] }, in: selection)

        XCTAssertEqual(Array(dates[indices]), [date(4), date(3), date(2)])
    }

    func testTrendSamplesRollingWindowThroughExactEndDate() {
        let inputs = [
            MerchantAnalytics.Input(title: "Cafe", amount: 5, category: .food, date: date(1, 2)),
            MerchantAnalytics.Input(title: "Cafe", amount: 6, category: .food, date: date(1, 5)),
        ]

        let points = MerchantAnalytics.categoryTrendTotals(inputs, through: date(2, 5))
        XCTAssertGreaterThan(points.count, 2)
        XCTAssertEqual(points.last?.monthStart, date(2, 5))
        XCTAssertGreaterThan(points.last?.amount ?? 0, 0)
        XCTAssertLessThan(points.last?.amount ?? .infinity, 6)
    }

    func testTrendProvidesDailyPointsForScrubbing() {
        let inputs = [
            MerchantAnalytics.Input(title: "Cafe", amount: 5, category: .food, date: date(1, 2)),
        ]

        let points = MerchantAnalytics.categoryTrendTotals(inputs, through: date(1, 5))

        XCTAssertEqual(points.map(\.monthStart), [date(1, 2), date(1, 3), date(1, 4), date(1, 5)])
        XCTAssertEqual(points.map(\.amount), [5, 5, 5, 5])
    }

    func testCumulativeSeriesDoesNotDropWhenRentMovesOneDayLater() {
        let inputs = [
            MerchantAnalytics.Input(title: "Rent", amount: 2_700, category: .housing, date: date(7, 1)),
            MerchantAnalytics.Input(title: "Rent", amount: 2_700, category: .housing, date: date(8, 2)),
        ]

        let points = MerchantAnalytics.categoryCumulativeTotals(
            inputs,
            from: date(7, 1),
            through: date(8, 3)
        )

        XCTAssertEqual(points.last?.amount ?? 0, 5_400, accuracy: 0.001)
        XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.amount <= $1.amount })
    }

    func testLazyRollingTrendSoftensShiftedRentCliff() {
        let inputs = [
            MerchantAnalytics.Input(title: "Rent", amount: 2_700, category: .housing, date: date(7, 1)),
            MerchantAnalytics.Input(title: "Rent", amount: 2_700, category: .housing, date: date(8, 2)),
        ]

        let points = MerchantAnalytics.categoryTrendTotals(inputs, through: date(8, 4))
        let largestDrop = zip(points, points.dropFirst())
            .map { $0.amount - $1.amount }
            .max() ?? 0

        XCTAssertGreaterThan(largestDrop, 0)
        XCTAssertLessThan(largestDrop, 1_000, "a shifted rent date must not draw a full-payment cliff")
    }

    func testTrendSeriesZeroFillsMissingPeriods() {
        let inputs = [
            MerchantAnalytics.Input(title: "Cafe", amount: 5, category: .food, date: date(1, 2)),
            MerchantAnalytics.Input(title: "Cafe", amount: 6, category: .food, date: date(3, 4)),
        ]

        let points = MerchantAnalytics.categoryTrendTotals(inputs, through: date(3, 4))
        XCTAssertTrue(points.contains { abs($0.amount) < 0.001 })
        XCTAssertGreaterThan(points.last?.amount ?? 0, 0)
        XCTAssertLessThan(points.last?.amount ?? .infinity, 6)
    }

    func testCategoryComparisonUsesSelectedFinalMonthAndPriorAverage() throws {
        let window = DateInterval(start: date(1), end: date(4))
        let inputs = [
            MerchantAnalytics.Input(title: "Gym", amount: 120, category: .health, date: date(1, 10)),
        ]

        let average = try XCTUnwrap(
            MerchantAnalytics.categoryAverages(inputs, window: window).first
        )
        XCTAssertEqual(average.currentMonthSpend, 0, accuracy: 0.001)
        XCTAssertEqual(average.priorMonthsAverage, 60, accuracy: 0.001)
    }

    func testSnapshotExcludesIncompleteLedgerMonthFromPriorAverage() throws {
        let window = DateInterval(start: date(5), end: date(8))
        let inputs = [
            MerchantAnalytics.Input(title: "Rent", amount: 500, category: .housing, date: date(5, 15)),
            MerchantAnalytics.Input(title: "Rent", amount: 1_000, category: .housing, date: date(6)),
            MerchantAnalytics.Input(title: "Rent", amount: 1_000, category: .housing, date: date(7)),
        ]

        let snapshot = AnalysisSnapshot.make(inputs: inputs, window: window, categoryFilter: nil)
        let housing = try XCTUnwrap(snapshot.categoryAverages.first)

        XCTAssertEqual(housing.currentMonthSpend, 1_000, accuracy: 0.001)
        XCTAssertEqual(housing.priorMonthsAverage, 1_000, accuracy: 0.001)
        XCTAssertEqual(housing.priorMonthCount, 1)
    }

    func testTransactionEditsInvalidateCachedAnalysisInputs() {
        let transaction = TransactionRecord(
            id: "edited", plaidTransactionId: "edited", name: "Cafe", merchantName: "Cafe",
            amount: 10, isoCurrencyCode: "USD", date: date(1), pending: false,
            categoryPrimary: nil, categoryDetailed: nil, logoURL: nil, accountId: "checking"
        )
        let cache = AnalysisSnapshotCache()
        var builds = 0

        func build() {
            let key = AnalysisSnapshotCache.InputsKey(
                dataHash: AnalysisSnapshotCache.dataHash([transaction]),
                rulesHash: 0,
                excludedAccountsRaw: ""
            )
            _ = cache.snapshot(key: key, categoryFilter: nil) {
                builds += 1
                return [MerchantAnalytics.Input(
                    title: transaction.title,
                    amount: transaction.amount,
                    category: transaction.categoryOverride ?? .food,
                    date: transaction.date
                )]
            }
        }

        build()
        transaction.amount = 25
        build()
        transaction.categoryOverride = .shopping
        build()

        XCTAssertEqual(builds, 3, "amount and category edits must rebuild analysis inputs")
    }

    /// A superseded pass bails out partway through. Memoizing what it had
    /// built so far would pin a wrong snapshot under a key that claims to be
    /// complete, and every later request would be served from it.
    func testCancelledBuildIsNotMemoized() throws {
        let cache = AnalysisSnapshotCache()
        let key = AnalysisSnapshotCache.InputsKey(dataHash: 1, rulesHash: 1, excludedAccountsRaw: "")

        XCTAssertNil(cache.snapshot(key: key, categoryFilter: nil) { nil })

        var builds = 0
        let complete = try XCTUnwrap(
            cache.snapshot(key: key, categoryFilter: nil) { builds += 1; return self.sample }
        )
        XCTAssertEqual(builds, 1, "the cancelled pass must not have satisfied this key")
        XCTAssertFalse(complete.topBySpend.isEmpty)
    }
}
