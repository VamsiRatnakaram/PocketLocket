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
