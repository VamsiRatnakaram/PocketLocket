import XCTest
@testable import PocketLocket

final class SpendAggregatorTests: XCTestCase {
    func testExcludesIncomeTransfersAndNegativeAmounts() {
        let items = [
            SpendItem(category: .food, amount: 20),
            SpendItem(category: .food, amount: 30),
            SpendItem(category: .income, amount: 1000),   // excluded (not spending)
            SpendItem(category: .transfer, amount: 200),  // excluded (not spending)
            SpendItem(category: .shopping, amount: -15),   // excluded (refund / inflow)
        ]

        let totals = SpendAggregator.totals(items)

        XCTAssertEqual(SpendAggregator.totalSpend(totals), 50, accuracy: 0.0001)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals.first?.category, .food)
        XCTAssertEqual(totals.first?.amount ?? 0, 50, accuracy: 0.0001)
    }

    func testSortedByAmountDescending() {
        let items = [
            SpendItem(category: .food, amount: 10),
            SpendItem(category: .housing, amount: 100),
            SpendItem(category: .transport, amount: 40),
        ]

        let categories = SpendAggregator.totals(items).map(\.category)
        XCTAssertEqual(categories, [.housing, .transport, .food])
    }

    func testHomeViewModelProgressAndRemaining() {
        let vm = HomeViewModel(
            items: [SpendItem(category: .food, amount: 1500)],
            monthlyBudget: 3000
        )

        XCTAssertEqual(vm.totalSpent, 1500, accuracy: 0.0001)
        XCTAssertEqual(vm.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(vm.remaining, 1500, accuracy: 0.0001)
        XCTAssertFalse(vm.isOverBudget)
    }

    func testHomeViewModelOverBudgetClampsProgress() {
        let vm = HomeViewModel(
            items: [SpendItem(category: .housing, amount: 4000)],
            monthlyBudget: 3000
        )

        XCTAssertTrue(vm.isOverBudget)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.0001) // clamped
        XCTAssertEqual(vm.remaining, -1000, accuracy: 0.0001)
    }
}

// MARK: - Excluded outflows

extension SpendAggregatorTests {
    /// The exact mirror of `totals`: whatever the budget drops should show up
    /// here, so the two together account for every outflow.
    func testExcludedTotalsCapturesNonSpendingOutflows() {
        let items = [
            SpendItem(category: .food, amount: 20),
            SpendItem(category: .transfer, amount: 500),
            SpendItem(category: .transfer, amount: 250),
            SpendItem(category: .income, amount: 40),
        ]

        let excluded = SpendAggregator.excludedTotals(items)

        XCTAssertEqual(SpendAggregator.totalSpend(excluded), 790, accuracy: 0.0001)
        XCTAssertEqual(excluded.count, 2)
        XCTAssertEqual(excluded.first?.category, .transfer)
        XCTAssertEqual(excluded.first?.amount ?? 0, 750, accuracy: 0.0001)
    }

    /// Inflows were never in the spend total, so surfacing them as "excluded"
    /// would overstate the gap — a $500 card payment out and the matching $500
    /// credit in would read as $1,000 held back.
    func testExcludedTotalsIgnoresInflows() {
        let items = [
            SpendItem(category: .transfer, amount: 500),
            SpendItem(category: .transfer, amount: -500),
            SpendItem(category: .income, amount: -3000),
        ]

        let excluded = SpendAggregator.excludedTotals(items)

        XCTAssertEqual(SpendAggregator.totalSpend(excluded), 500, accuracy: 0.0001)
    }

    func testExcludedTotalsIgnoresSpendingCategories() {
        let items = [
            SpendItem(category: .food, amount: 20),
            SpendItem(category: .shopping, amount: 60),
        ]

        XCTAssertTrue(SpendAggregator.excludedTotals(items).isEmpty)
    }

    /// Every positive amount lands in exactly one of the two buckets — that
    /// invariant is what makes the Home screen's "not in budget" line a real
    /// reconciliation rather than a second, unrelated number.
    func testSpendAndExcludedPartitionAllOutflows() {
        let items = [
            SpendItem(category: .food, amount: 20),
            SpendItem(category: .transfer, amount: 500),
            SpendItem(category: .income, amount: 40),
            SpendItem(category: .shopping, amount: 60),
            SpendItem(category: .housing, amount: -10),
        ]

        let spent = SpendAggregator.totalSpend(SpendAggregator.totals(items))
        let excluded = SpendAggregator.totalSpend(SpendAggregator.excludedTotals(items))
        let allOutflows = items.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }

        XCTAssertEqual(spent + excluded, allOutflows, accuracy: 0.0001)
    }

    func testHomeViewModelReportsExcludedTotal() {
        let model = HomeViewModel(
            items: [
                SpendItem(category: .food, amount: 100),
                SpendItem(category: .transfer, amount: 900),
            ],
            monthlyBudget: 3000
        )

        XCTAssertEqual(model.totalSpent, 100, accuracy: 0.0001)
        XCTAssertEqual(model.excludedTotal, 900, accuracy: 0.0001)
    }
}
