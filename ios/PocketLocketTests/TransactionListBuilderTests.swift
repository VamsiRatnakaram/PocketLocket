import XCTest
@testable import PocketLocket

final class TransactionListBuilderTests: XCTestCase {
    private func date(_ day: Int) -> Date {
        DateComponents(calendar: .current, year: 2024, month: 6, day: day).date!
    }

    private func txn(
        _ id: String,
        name: String,
        amount: Double,
        day: Int,
        accountId: String = "checking"
    ) -> TransactionRecord {
        TransactionRecord(
            id: id,
            plaidTransactionId: id,
            name: name,
            merchantName: name,
            amount: amount,
            isoCurrencyCode: "USD",
            date: date(day),
            pending: false,
            categoryPrimary: nil,
            categoryDetailed: nil,
            logoURL: nil,
            accountId: accountId
        )
    }

    private var sample: [TransactionRecord] {
        [
            txn("1", name: "Starbucks", amount: 5, day: 1),
            txn("2", name: "Trader Joes", amount: 80, day: 5, accountId: "savings"),
            txn("3", name: "Paycheck", amount: -2000, day: 10),
        ]
    }

    private func rows(
        _ criteria: TransactionListBuilder.Criteria,
        from transactions: [TransactionRecord]? = nil,
        resolve: @escaping (TransactionRecord) -> SpendCategory = { _ in .other }
    ) -> [TransactionListBuilder.Row] {
        TransactionListBuilder.rows(from: transactions ?? sample, criteria: criteria, resolve: resolve)
    }

    func testDefaultCriteriaReturnsEverythingNewestFirst() {
        XCTAssertEqual(rows(.init()).map(\.id), ["3", "2", "1"])
    }

    func testExpensesAndIncomeSplitOnSign() {
        XCTAssertEqual(rows(.init(type: .expenses)).map(\.id), ["2", "1"])
        XCTAssertEqual(rows(.init(type: .income)).map(\.id), ["3"])
    }

    func testAccountFilter() {
        XCTAssertEqual(rows(.init(accountId: "savings")).map(\.id), ["2"])
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(rows(.init(search: "starb")).map(\.id), ["1"])
    }

    func testPeriodIntervalExcludesOutsideDates() {
        let interval = DateInterval(start: date(4), end: date(6))
        XCTAssertEqual(rows(.init(periodInterval: interval)).map(\.id), ["2"])
    }

    func testCategoryFilterUsesResolvedCategory() {
        let result = rows(.init(category: .food)) { $0.name == "Starbucks" ? .food : .other }
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testSortOrders() {
        XCTAssertEqual(rows(.init(sortOrder: .dateAsc)).map(\.id), ["1", "2", "3"])
        XCTAssertEqual(rows(.init(sortOrder: .amountDesc)).map(\.id), ["2", "1", "3"])
        XCTAssertEqual(rows(.init(sortOrder: .amountAsc)).map(\.id), ["3", "1", "2"])
    }

    /// Each row carries the category used to filter it, so the list never has
    /// to resolve the same transaction twice.
    func testRowsCarryTheResolvedCategory() {
        let result = rows(.init()) { $0.name == "Starbucks" ? .food : .groceries }
        XCTAssertEqual(result.first { $0.id == "1" }?.category, .food)
        XCTAssertEqual(result.first { $0.id == "2" }?.category, .groceries)
    }

    /// Category resolution is the most expensive step, so it must run at most
    /// once per transaction — and not at all for rows a cheap filter already
    /// rejected.
    func testCategoryResolvesAtMostOncePerTransaction() {
        var resolved: [String] = []
        _ = rows(.init(category: .food)) { txn in
            resolved.append(txn.id)
            return .food
        }
        XCTAssertEqual(resolved.sorted(), ["1", "2", "3"])
    }

    func testCheapFiltersRunBeforeCategoryResolution() {
        var resolved: [String] = []
        _ = rows(.init(accountId: "savings")) { txn in
            resolved.append(txn.id)
            return .other
        }
        XCTAssertEqual(resolved, ["2"], "Only the surviving transaction should pay for categorization")
    }
}
