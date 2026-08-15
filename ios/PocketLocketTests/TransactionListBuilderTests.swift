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

    func testReturnsAreSeparatedFromIncomeByResolvedCategory() {
        let transactions = [
            txn("purchase", name: "TARGET.COM", amount: 364.80, day: 3),
            txn("return", name: "TARGET STORE T3275", amount: -364.80, day: 10),
            txn("paycheck", name: "PAYCHECK", amount: -2_000, day: 12),
        ]
        let resolve: (TransactionRecord) -> SpendCategory = {
            $0.name == "PAYCHECK" ? .income : .shopping
        }

        XCTAssertEqual(rows(.init(type: .expenses), from: transactions, resolve: resolve).map(\.id), ["purchase"])
        XCTAssertEqual(rows(.init(type: .returns), from: transactions, resolve: resolve).map(\.id), ["return"])
        XCTAssertEqual(rows(.init(type: .income), from: transactions, resolve: resolve).map(\.id), ["paycheck"])
    }

    func testAmbiguousInflowRequiresReturnDescriptor() {
        let refund = txn("refund", name: "MERCHANT REFUND", amount: -20, day: 2)
        let deposit = txn("deposit", name: "MYSTERY DEPOSIT", amount: -20, day: 3)

        XCTAssertEqual(TransactionListBuilder.classify(refund, category: .other), .returns)
        XCTAssertEqual(TransactionListBuilder.classify(deposit, category: .other), .income)
    }

    func testFullyReimbursedExpenseIsNotInBudget() {
        let expense = txn("dinner", name: "Dinner", amount: 120, day: 1)
        let allocation = ReimbursementAllocationSpec(
            id: "a1",
            sourceTransactionID: "venmo",
            expenseTransactionID: expense.id,
            amount: 120
        )
        let index = ReimbursementAllocationIndex([allocation])

        let counted = TransactionListBuilder.rows(
            from: [expense],
            criteria: .init(budget: .counted),
            reimbursementIndex: index,
            resolve: { _ in .food }
        )
        let excluded = TransactionListBuilder.rows(
            from: [expense],
            criteria: .init(budget: .excluded),
            reimbursementIndex: index,
            resolve: { _ in .food }
        )

        XCTAssertTrue(counted.isEmpty)
        XCTAssertEqual(excluded.first?.id, expense.id)
        XCTAssertEqual(excluded.first?.effectiveAmount, 0)
        XCTAssertEqual(excluded.first?.reimbursedAmount, 120)
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
        // By size: the $2,000 paycheck is the largest transaction here even
        // though it is money in and therefore negative.
        XCTAssertEqual(rows(.init(sortOrder: .amountDesc)).map(\.id), ["3", "2", "1"])
        XCTAssertEqual(rows(.init(sortOrder: .amountAsc)).map(\.id), ["1", "2", "3"])
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

    /// Positive is money out and negative is money in, so sorting on the raw
    /// amount put the largest deposit last under "Largest first".
    func testAmountSortOrdersBySizeNotBySign() {
        let built = TransactionListBuilder.rows(
            from: [
                txn("small-expense", name: "Coffee", amount: 5, day: 1),
                txn("big-deposit", name: "Paycheck", amount: -900, day: 2),
                txn("big-expense", name: "Rent", amount: 400, day: 3),
            ],
            criteria: TransactionListBuilder.Criteria(sortOrder: .amountDesc),
            resolve: { _ in .other }
        )
        XCTAssertEqual(built.map(\.id), ["big-deposit", "big-expense", "small-expense"])

        let ascending = TransactionListBuilder.sort(built, by: .amountAsc)
        XCTAssertEqual(ascending.map(\.id), ["small-expense", "big-expense", "big-deposit"])
    }
}
