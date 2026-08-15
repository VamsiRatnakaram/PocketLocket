import SwiftData
import XCTest
@testable import PocketLocket

@MainActor
final class ReimbursementAllocationTests: XCTestCase {
    private func transaction(id: String, amount: Double, currency: String = "USD") -> TransactionRecord {
        TransactionRecord(
            id: id,
            plaidTransactionId: id,
            name: id,
            merchantName: id,
            amount: amount,
            isoCurrencyCode: currency,
            date: .now,
            pending: false,
            categoryPrimary: nil,
            categoryDetailed: nil,
            logoURL: nil,
            accountId: "checking"
        )
    }

    private func context() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TransactionRecord.self,
            ReimbursementAllocation.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    func testOneInflowCanOffsetPartsOfMultipleExpenses() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -120)
        let dinner = transaction(id: "dinner", amount: 200)
        let tickets = transaction(id: "tickets", amount: 75)
        [source, dinner, tickets].forEach(context.insert)

        let dinnerAllocation = try ReimbursementAllocationService.allocate(
            amount: 80, from: source, to: dinner, existing: [], in: context
        )
        _ = try ReimbursementAllocationService.allocate(
            amount: 40,
            from: source,
            to: tickets,
            existing: [dinnerAllocation],
            in: context
        )

        let allocations = try context.fetch(FetchDescriptor<ReimbursementAllocation>())
        let index = ReimbursementAllocationIndex(allocations)
        XCTAssertEqual(index.remainingSourceAmount(transactionID: source.id, originalAmount: source.amount), 0)
        XCTAssertEqual(index.effectiveExpenseAmount(transactionID: dinner.id, originalAmount: dinner.amount), 120)
        XCTAssertEqual(index.effectiveExpenseAmount(transactionID: tickets.id, originalAmount: tickets.amount), 35)
    }

    func testAllocationCannotExceedSourceOrExpense() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -50)
        let dinner = transaction(id: "dinner", amount: 40)
        [source, dinner].forEach(context.insert)

        XCTAssertThrowsError(try ReimbursementAllocationService.allocate(
            amount: 60, from: source, to: dinner, existing: [], in: context
        ))
        XCTAssertThrowsError(try ReimbursementAllocationService.allocate(
            amount: 45, from: source, to: dinner, existing: [], in: context
        ))
    }

    func testAllocationRequiresMatchingCurrency() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -50, currency: "USD")
        let dinner = transaction(id: "dinner", amount: 50, currency: "EUR")

        XCTAssertThrowsError(try ReimbursementAllocationService.allocate(
            amount: 20, from: source, to: dinner, existing: [], in: context
        ))
    }

    func testCandidatesExcludeNonSpendAndFullyReimbursedPurchases() {
        let source = transaction(id: "venmo", amount: -100)
        let dinner = transaction(id: "dinner", amount: 80)
        let transfer = transaction(id: "transfer", amount: 90)
        let paidBack = transaction(id: "paid-back", amount: 25)
        let index = ReimbursementAllocationIndex([
            ReimbursementAllocationSpec(
                id: "a1",
                sourceTransactionID: "another-source",
                expenseTransactionID: paidBack.id,
                amount: 25
            )
        ])

        let candidates = ReimbursementCandidateBuilder.candidates(
            for: source,
            in: [source, dinner, transfer, paidBack],
            index: index,
            categoryFor: { $0.id == transfer.id ? .transfer : .food }
        )

        XCTAssertEqual(candidates.map(\.id), [dinner.id])
    }

    func testExpenseCanChooseAvailableIncomingReimbursements() {
        let expense = transaction(id: "dinner", amount: 100)
        let newestSource = transaction(id: "venmo-new", amount: -60)
        let olderSource = transaction(id: "venmo-old", amount: -50)
        olderSource.date = newestSource.date.addingTimeInterval(-86_400)
        let matchedTransfer = transaction(id: "card-payment", amount: -100)
        matchedTransfer.transferPairId = "pair-1"
        let wrongCurrency = transaction(id: "euros", amount: -50, currency: "EUR")
        let index = ReimbursementAllocationIndex([
            ReimbursementAllocationSpec(
                id: "a1",
                sourceTransactionID: olderSource.id,
                expenseTransactionID: "another-expense",
                amount: 50
            )
        ])

        let candidates = ReimbursementSourceCandidateBuilder.candidates(
            for: expense,
            in: [expense, olderSource, newestSource, matchedTransfer, wrongCurrency],
            index: index
        )

        XCTAssertEqual(candidates.map(\.id), [newestSource.id])
    }

    func testAllocationRoundsToCents() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -50)
        let dinner = transaction(id: "dinner", amount: 50)
        [source, dinner].forEach(context.insert)

        let allocation = try ReimbursementAllocationService.allocate(
            amount: 12.345,
            from: source,
            to: dinner,
            existing: [],
            in: context
        )

        XCTAssertEqual(allocation.amount, 12.35, accuracy: 0.001)
    }

    func testMultipleInflowsCanFullyOffsetOneExpense() throws {
        let context = try context()
        let firstSource = transaction(id: "venmo-1", amount: -50)
        let secondSource = transaction(id: "venmo-2", amount: -70)
        let dinner = transaction(id: "dinner", amount: 100)
        [firstSource, secondSource, dinner].forEach(context.insert)

        let firstAllocation = try ReimbursementAllocationService.allocate(
            amount: 40, from: firstSource, to: dinner, existing: [], in: context
        )
        _ = try ReimbursementAllocationService.allocate(
            amount: 60,
            from: secondSource,
            to: dinner,
            existing: [firstAllocation],
            in: context
        )

        let index = ReimbursementAllocationIndex(
            try context.fetch(FetchDescriptor<ReimbursementAllocation>())
        )
        XCTAssertEqual(index.effectiveExpenseAmount(
            transactionID: dinner.id,
            originalAmount: dinner.amount
        ), 0)
        XCTAssertEqual(index.remainingSourceAmount(
            transactionID: firstSource.id,
            originalAmount: firstSource.amount
        ), 10)
        XCTAssertEqual(index.remainingSourceAmount(
            transactionID: secondSource.id,
            originalAmount: secondSource.amount
        ), 10)
    }

    func testCentRoundingCannotOverallocateSource() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -12.34)
        let dinner = transaction(id: "dinner", amount: 20)
        [source, dinner].forEach(context.insert)

        XCTAssertThrowsError(try ReimbursementAllocationService.allocate(
            amount: 12.345,
            from: source,
            to: dinner,
            existing: [],
            in: context
        ))
        let allocation = try ReimbursementAllocationService.allocate(
            amount: 12.344,
            from: source,
            to: dinner,
            existing: [],
            in: context
        )
        XCTAssertEqual(allocation.amount, 12.34, accuracy: 0.001)
    }

    func testStaleQuerySnapshotCannotOverallocateSource() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -100)
        let firstExpense = transaction(id: "dinner", amount: 100)
        let secondExpense = transaction(id: "tickets", amount: 100)
        [source, firstExpense, secondExpense].forEach(context.insert)

        _ = try ReimbursementAllocationService.allocate(
            amount: 80,
            from: source,
            to: firstExpense,
            existing: [],
            in: context
        )

        XCTAssertThrowsError(
            try ReimbursementAllocationService.allocate(
                amount: 30,
                from: source,
                to: secondExpense,
                existing: [], // Simulates @Query before its next publication.
                in: context
            )
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ReimbursementAllocation>()).count,
            1
        )
    }

    func testReconcileTrimsAllocationsWhenSourceShrinks() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -100)
        let firstExpense = transaction(id: "dinner", amount: 100)
        let secondExpense = transaction(id: "tickets", amount: 100)
        let first = ReimbursementAllocation(
            id: "a",
            sourceTransactionID: source.id,
            expenseTransactionID: firstExpense.id,
            amount: 70,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = ReimbursementAllocation(
            id: "b",
            sourceTransactionID: source.id,
            expenseTransactionID: secondExpense.id,
            amount: 30,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        [source, firstExpense, secondExpense].forEach(context.insert)
        [first, second].forEach(context.insert)
        try context.save()

        source.amount = -40
        try ReimbursementAllocationService.reconcile(in: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<ReimbursementAllocation>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "a")
        XCTAssertEqual(remaining.first?.amount ?? 0, 40, accuracy: 0.001)
    }

    func testReconcileDeletesInvalidCurrencyOrSignLinks() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -50)
        let expense = transaction(id: "dinner", amount: 50)
        let allocation = ReimbursementAllocation(
            sourceTransactionID: source.id,
            expenseTransactionID: expense.id,
            amount: 20
        )
        [source, expense].forEach(context.insert)
        context.insert(allocation)
        try context.save()

        expense.isoCurrencyCode = "EUR"
        try ReimbursementAllocationService.reconcile(in: context)
        try context.save()

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ReimbursementAllocation>()).isEmpty
        )
    }

    func testReconcilePreservesExistingAllocationBeforeImportedRows() throws {
        let context = try context()
        let source = transaction(id: "venmo", amount: -100)
        let firstExpense = transaction(id: "existing-expense", amount: 100)
        let secondExpense = transaction(id: "imported-expense", amount: 100)
        let existing = ReimbursementAllocation(
            id: "existing",
            sourceTransactionID: source.id,
            expenseTransactionID: firstExpense.id,
            amount: 80,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let imported = ReimbursementAllocation(
            id: "imported",
            sourceTransactionID: source.id,
            expenseTransactionID: secondExpense.id,
            amount: 30,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        [source, firstExpense, secondExpense].forEach(context.insert)
        [existing, imported].forEach(context.insert)
        try context.save()

        try ReimbursementAllocationService.reconcile(
            in: context,
            preserving: [existing.id]
        )
        try context.save()

        let allocations = try context.fetch(FetchDescriptor<ReimbursementAllocation>())
        XCTAssertEqual(allocations.first { $0.id == existing.id }?.amount, 80)
        XCTAssertEqual(allocations.first { $0.id == imported.id }?.amount, 20)
    }

    func testEffectiveLedgerAmountRemovesBothAppliedSides() {
        let index = ReimbursementAllocationIndex([
            ReimbursementAllocationSpec(
                id: "a",
                sourceTransactionID: "venmo",
                expenseTransactionID: "dinner",
                amount: 50
            )
        ])

        XCTAssertEqual(
            index.effectiveLedgerAmount(transactionID: "dinner", originalAmount: 100),
            50
        )
        XCTAssertEqual(
            index.effectiveLedgerAmount(transactionID: "venmo", originalAmount: -50),
            0
        )
    }

    func testAmountInputUsesLocaleDecimalSeparator() {
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(
            ReimbursementAmountInput.amount(from: "1,50", locale: german) ?? 0,
            1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ReimbursementAmountInput.string(1.5, locale: german),
            "1,50"
        )
    }

    func testMatchedTransferCannotBeReimbursementSource() throws {
        let context = try context()
        let source = transaction(id: "transfer", amount: -50)
        source.transferPairId = "pair"
        let expense = transaction(id: "dinner", amount: 50)

        XCTAssertThrowsError(
            try ReimbursementAllocationService.allocate(
                amount: 20,
                from: source,
                to: expense,
                existing: [],
                in: context
            )
        )
    }
}