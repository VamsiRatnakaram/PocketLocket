import XCTest
@testable import PocketLocket

final class MerchantAnalyticsTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    // MARK: - MerchantNormalizer

    func testNormalizerStripsStoreNumbersAndCase() {
        XCTAssertEqual(MerchantNormalizer.normalize("STARBUCKS #4521"), "Starbucks")
        XCTAssertEqual(MerchantNormalizer.normalize("starbucks 04521"), "Starbucks")
        XCTAssertEqual(MerchantNormalizer.normalize("Chipotle"), "Chipotle")
    }

    func testNormalizerStripsPOSPrefixes() {
        XCTAssertEqual(MerchantNormalizer.normalize("SQ *Blue Bottle Coffee"), "Blue Bottle Coffee")
    }

    func testNormalizerStripsTrailingState() {
        XCTAssertEqual(MerchantNormalizer.normalize("Trader Joes CA"), "Trader Joes")
    }

    // MARK: - merchantStats

    func testMerchantStatsCountsVisitsAndTotals() {
        let inputs = [
            MerchantAnalytics.Input(title: "Chipotle #1234", amount: 12, category: .food, date: date(2025, 1, 5)),
            MerchantAnalytics.Input(title: "Chipotle 01234", amount: 14, category: .food, date: date(2025, 2, 5)),
            MerchantAnalytics.Input(title: "Chipotle", amount: 13, category: .food, date: date(2025, 3, 5)),
        ]

        let stats = MerchantAnalytics.merchantStats(inputs)
        XCTAssertEqual(stats.count, 1)
        let chipotle = try! XCTUnwrap(stats.first)
        XCTAssertEqual(chipotle.name, "Chipotle")
        XCTAssertEqual(chipotle.visitCount, 3)
        XCTAssertEqual(chipotle.totalSpent, 39, accuracy: 0.0001)
        XCTAssertEqual(chipotle.averagePerVisit, 13, accuracy: 0.0001)
        XCTAssertEqual(chipotle.category, .food)
    }

    func testMerchantStatsExcludesIncomeTransfersAndRefunds() {
        let inputs = [
            MerchantAnalytics.Input(title: "Payroll", amount: 3000, category: .income, date: date(2025, 1, 1)),
            MerchantAnalytics.Input(title: "Venmo", amount: 50, category: .transfer, date: date(2025, 1, 2)),
            MerchantAnalytics.Input(title: "Amazon", amount: -20, category: .shopping, date: date(2025, 1, 3)),
            MerchantAnalytics.Input(title: "Amazon", amount: 40, category: .shopping, date: date(2025, 1, 4)),
        ]

        let stats = MerchantAnalytics.merchantStats(inputs)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.first?.name, "Amazon")
        XCTAssertEqual(stats.first?.totalSpent ?? 0, 40, accuracy: 0.0001)
    }

    func testMerchantStatsEmptyForNoSpending() {
        XCTAssertTrue(MerchantAnalytics.merchantStats([]).isEmpty)
    }

    // MARK: - topByFrequency / topBySpend

    func testTopByFrequencyOrdersByVisitCount() {
        let inputs = [
            MerchantAnalytics.Input(title: "Coffee Shop", amount: 5, category: .food, date: date(2025, 1, 1)),
            MerchantAnalytics.Input(title: "Coffee Shop", amount: 5, category: .food, date: date(2025, 1, 2)),
            MerchantAnalytics.Input(title: "Coffee Shop", amount: 5, category: .food, date: date(2025, 1, 3)),
            MerchantAnalytics.Input(title: "Steakhouse", amount: 100, category: .food, date: date(2025, 1, 4)),
        ]

        let stats = MerchantAnalytics.merchantStats(inputs)
        let byFrequency = MerchantAnalytics.topByFrequency(stats)
        XCTAssertEqual(byFrequency.first?.name, "Coffee Shop")

        let bySpend = MerchantAnalytics.topBySpend(stats)
        XCTAssertEqual(bySpend.first?.name, "Steakhouse")
    }

    // MARK: - recurringMerchants

    func testRecurringMerchantsRequiresDistinctMonths() {
        let inputs = [
            MerchantAnalytics.Input(title: "Gym", amount: 30, category: .services, date: date(2025, 1, 1)),
            MerchantAnalytics.Input(title: "Gym", amount: 30, category: .services, date: date(2025, 2, 1)),
            MerchantAnalytics.Input(title: "Gym", amount: 30, category: .services, date: date(2025, 3, 1)),
            MerchantAnalytics.Input(title: "One-off Store", amount: 200, category: .shopping, date: date(2025, 1, 15)),
        ]

        let recurring = MerchantAnalytics.recurringMerchants(inputs, minMonths: 3)
        XCTAssertEqual(recurring.map(\.name), ["Gym"])
    }

    func testRecurringMerchantsSameMonthMultipleVisitsDoesNotQualify() {
        let inputs = [
            MerchantAnalytics.Input(title: "Diner", amount: 15, category: .food, date: date(2025, 1, 1)),
            MerchantAnalytics.Input(title: "Diner", amount: 15, category: .food, date: date(2025, 1, 10)),
            MerchantAnalytics.Input(title: "Diner", amount: 15, category: .food, date: date(2025, 1, 20)),
        ]

        // 3 visits, but all within a single calendar month — should not qualify for minMonths: 3.
        let recurring = MerchantAnalytics.recurringMerchants(inputs, minMonths: 3)
        XCTAssertTrue(recurring.isEmpty)
    }

    // MARK: - categoryMonthlyTotals / categoryAverages

    func testCategoryMonthlyTotalsBucketsByMonth() {
        let inputs = [
            MerchantAnalytics.Input(title: "Whole Foods", amount: 100, category: .groceries, date: date(2025, 1, 5)),
            MerchantAnalytics.Input(title: "Trader Joes", amount: 50, category: .groceries, date: date(2025, 1, 20)),
            MerchantAnalytics.Input(title: "Whole Foods", amount: 80, category: .groceries, date: date(2025, 2, 5)),
        ]

        let monthly = MerchantAnalytics.categoryMonthlyTotals(inputs)
        XCTAssertEqual(monthly.count, 2)
        XCTAssertEqual(monthly[0].amount, 150, accuracy: 0.0001)
        XCTAssertEqual(monthly[1].amount, 80, accuracy: 0.0001)
    }

    func testCategoryAveragesComputesMeanAndTrend() {
        let inputs = [
            MerchantAnalytics.Input(title: "Groceries A", amount: 100, category: .groceries, date: date(2025, 1, 5)),
            MerchantAnalytics.Input(title: "Groceries A", amount: 300, category: .groceries, date: date(2025, 2, 5)),
        ]

        let averages = MerchantAnalytics.categoryAverages(inputs)
        XCTAssertEqual(averages.count, 1)
        let groceries = try! XCTUnwrap(averages.first)
        XCTAssertEqual(groceries.category, .groceries)
        XCTAssertEqual(groceries.averagePerMonth, 200, accuracy: 0.0001)
        if case .up = groceries.trend {
            // Spend increased from Jan ($100) to Feb ($300) — expect an "up" trend.
        } else {
            XCTFail("Expected an upward trend, got \(groceries.trend)")
        }
    }

    func testCategoryAveragesEmptyForNoData() {
        XCTAssertTrue(MerchantAnalytics.categoryAverages([]).isEmpty)
    }
}
