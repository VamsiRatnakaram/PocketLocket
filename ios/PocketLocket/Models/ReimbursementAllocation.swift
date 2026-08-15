import Foundation
import SwiftData

/// A user-directed portion of an inflow that offsets one expense.
///
/// Transaction ids are stored instead of SwiftData relationships so bank sync
/// can replace or remove ledger rows without making the persistent schema
/// depend on cascade behavior.
@Model
final class ReimbursementAllocation {
    @Attribute(.unique) var id: String
    var sourceTransactionID: String
    var expenseTransactionID: String
    var amount: Double
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        sourceTransactionID: String,
        expenseTransactionID: String,
        amount: Double,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceTransactionID = sourceTransactionID
        self.expenseTransactionID = expenseTransactionID
        self.amount = amount
        self.createdAt = createdAt
    }
}

struct ReimbursementAllocationSpec: Hashable, Sendable {
    let id: String
    let sourceTransactionID: String
    let expenseTransactionID: String
    let amount: Double

    init(
        id: String,
        sourceTransactionID: String,
        expenseTransactionID: String,
        amount: Double
    ) {
        self.id = id
        self.sourceTransactionID = sourceTransactionID
        self.expenseTransactionID = expenseTransactionID
        self.amount = amount
    }

    init(_ allocation: ReimbursementAllocation) {
        self.init(
            id: allocation.id,
            sourceTransactionID: allocation.sourceTransactionID,
            expenseTransactionID: allocation.expenseTransactionID,
            amount: allocation.amount
        )
    }
}

struct ReimbursementAllocationIndex: Sendable {
    static let empty = ReimbursementAllocationIndex([] as [ReimbursementAllocationSpec])

    private let bySource: [String: Double]
    private let byExpense: [String: Double]

    init(_ allocations: [ReimbursementAllocationSpec]) {
        var sourceTotals: [String: Double] = [:]
        var expenseTotals: [String: Double] = [:]
        for allocation in allocations where allocation.amount.isFinite && allocation.amount > 0 {
            sourceTotals[allocation.sourceTransactionID, default: 0] += allocation.amount
            expenseTotals[allocation.expenseTransactionID, default: 0] += allocation.amount
        }
        bySource = sourceTotals
        byExpense = expenseTotals
    }

    @MainActor
    init(_ allocations: [ReimbursementAllocation]) {
        self.init(allocations.map(ReimbursementAllocationSpec.init))
    }

    func allocatedFromSource(_ transactionID: String) -> Double {
        bySource[transactionID] ?? 0
    }

    func allocatedToExpense(_ transactionID: String) -> Double {
        byExpense[transactionID] ?? 0
    }

    func remainingSourceAmount(transactionID: String, originalAmount: Double) -> Double {
        max(0, abs(min(originalAmount, 0)) - allocatedFromSource(transactionID))
    }

    func effectiveExpenseAmount(transactionID: String, originalAmount: Double) -> Double {
        guard originalAmount > 0 else { return originalAmount }
        return max(0, originalAmount - allocatedToExpense(transactionID))
    }

    func remainingExpenseAmount(transactionID: String, originalAmount: Double) -> Double {
        effectiveExpenseAmount(transactionID: transactionID, originalAmount: originalAmount)
    }
}

enum ReimbursementCandidateBuilder {
    static func candidates(
        for source: TransactionRecord,
        in transactions: [TransactionRecord],
        index: ReimbursementAllocationIndex,
        categoryFor: (TransactionRecord) -> SpendCategory
    ) -> [TransactionRecord] {
        guard source.amount < 0 else { return [] }
        return transactions.filter { transaction in
            transaction.id != source.id
                && transaction.amount > 0
                && transaction.isoCurrencyCode.caseInsensitiveCompare(source.isoCurrencyCode) == .orderedSame
                && categoryFor(transaction).isSpending
                && index.remainingExpenseAmount(
                    transactionID: transaction.id,
                    originalAmount: transaction.amount
                ) > 0.005
        }
        .sorted { $0.date > $1.date }
    }
}

enum ReimbursementSourceCandidateBuilder {
    static func candidates(
        for expense: TransactionRecord,
        in transactions: [TransactionRecord],
        index: ReimbursementAllocationIndex
    ) -> [TransactionRecord] {
        guard expense.amount > 0 else { return [] }
        return transactions.filter { transaction in
            transaction.id != expense.id
                && transaction.amount < 0
                && transaction.transferPairId == nil
                && transaction.isoCurrencyCode.caseInsensitiveCompare(expense.isoCurrencyCode) == .orderedSame
                && index.remainingSourceAmount(
                    transactionID: transaction.id,
                    originalAmount: transaction.amount
                ) > 0.005
        }
        .sorted { $0.date > $1.date }
    }
}

@MainActor
enum ReimbursementAllocationService {
    enum AllocationError: LocalizedError {
        case sourceMustBeInflow
        case expenseMustBeOutflow
        case sameTransaction
        case currencyMismatch
        case invalidAmount
        case exceedsAvailableSource
        case exceedsExpense

        var errorDescription: String? {
            switch self {
            case .sourceMustBeInflow: "Choose money received as the reimbursement source."
            case .expenseMustBeOutflow: "Choose a purchase to reimburse."
            case .sameTransaction: "A transaction cannot reimburse itself."
            case .currencyMismatch: "Both transactions must use the same currency."
            case .invalidAmount: "Enter an amount greater than zero."
            case .exceedsAvailableSource: "That exceeds the reimbursement amount remaining."
            case .exceedsExpense: "That exceeds the unreimbursed part of the purchase."
            }
        }
    }

    @discardableResult
    static func allocate(
        amount: Double,
        from source: TransactionRecord,
        to expense: TransactionRecord,
        existing: [ReimbursementAllocation],
        in context: ModelContext
    ) throws -> ReimbursementAllocation {
        guard source.amount < 0 else { throw AllocationError.sourceMustBeInflow }
        guard expense.amount > 0 else { throw AllocationError.expenseMustBeOutflow }
        guard source.id != expense.id else { throw AllocationError.sameTransaction }
        guard source.isoCurrencyCode.caseInsensitiveCompare(expense.isoCurrencyCode) == .orderedSame
        else { throw AllocationError.currencyMismatch }
        guard amount.isFinite else { throw AllocationError.invalidAmount }
        let amount = (amount * 100).rounded() / 100
        guard amount > 0 else { throw AllocationError.invalidAmount }

        let index = ReimbursementAllocationIndex(existing)
        let tolerance = 0.005
        guard amount <= index.remainingSourceAmount(
            transactionID: source.id,
            originalAmount: source.amount
        ) + tolerance else { throw AllocationError.exceedsAvailableSource }
        guard amount <= index.remainingExpenseAmount(
            transactionID: expense.id,
            originalAmount: expense.amount
        ) + tolerance else { throw AllocationError.exceedsExpense }

        let allocation = ReimbursementAllocation(
            sourceTransactionID: source.id,
            expenseTransactionID: expense.id,
            amount: amount
        )
        context.insert(allocation)
        try context.save()
        return allocation
    }

    static func remove(_ allocation: ReimbursementAllocation, from context: ModelContext) throws {
        context.delete(allocation)
        try context.save()
    }

    static func deleteAllocations(
        referencing transactionIDs: Set<String>,
        from allocations: [ReimbursementAllocation],
        in context: ModelContext
    ) {
        for allocation in allocations where
            transactionIDs.contains(allocation.sourceTransactionID)
                || transactionIDs.contains(allocation.expenseTransactionID) {
            context.delete(allocation)
        }
    }
}