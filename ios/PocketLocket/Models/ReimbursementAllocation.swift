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

    /// Net amount for contexts that include both sides of the ledger.
    ///
    /// Expense-only surfaces ignore inflows and use `effectiveExpenseAmount`.
    /// AI includes both, so the allocated portion must also be removed from the
    /// source or the same reimbursement is subtracted twice.
    func effectiveLedgerAmount(transactionID: String, originalAmount: Double) -> Double {
        if originalAmount > 0 {
            return effectiveExpenseAmount(
                transactionID: transactionID,
                originalAmount: originalAmount
            )
        }
        if originalAmount < 0 {
            return -remainingSourceAmount(
                transactionID: transactionID,
                originalAmount: originalAmount
            )
        }
        return 0
    }

    func remainingExpenseAmount(transactionID: String, originalAmount: Double) -> Double {
        effectiveExpenseAmount(transactionID: transactionID, originalAmount: originalAmount)
    }
}

enum ReimbursementAmountInput {
    static func string(_ amount: Double, locale: Locale = .current) -> String {
        let formatter = formatter(locale: locale)
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    static func amount(from text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let number = formatter(locale: locale).number(from: trimmed)
        else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    private static func formatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        formatter.isLenient = false
        return formatter
    }
}

enum ReimbursementCandidateBuilder {
    static func candidates(
        for source: TransactionRecord,
        in transactions: [TransactionRecord],
        index: ReimbursementAllocationIndex,
        excludedAccountIDs: Set<String> = [],
        categoryFor: (TransactionRecord) -> SpendCategory
    ) -> [TransactionRecord] {
        guard source.amount < 0,
              !(source.accountId.map { excludedAccountIDs.contains($0) } ?? false)
        else { return [] }
        return transactions.filter { transaction in
            transaction.id != source.id
                && transaction.amount > 0
                && !(transaction.accountId.map { excludedAccountIDs.contains($0) } ?? false)
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
        index: ReimbursementAllocationIndex,
        excludedAccountIDs: Set<String> = []
    ) -> [TransactionRecord] {
        guard expense.amount > 0,
              !(expense.accountId.map { excludedAccountIDs.contains($0) } ?? false)
        else { return [] }
        return transactions.filter { transaction in
            transaction.id != expense.id
                && transaction.amount < 0
                && !(transaction.accountId.map { excludedAccountIDs.contains($0) } ?? false)
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
        case sourceIsMatchedTransfer
        case sameTransaction
        case currencyMismatch
        case invalidAmount
        case exceedsAvailableSource
        case exceedsExpense

        var errorDescription: String? {
            switch self {
            case .sourceMustBeInflow: "Choose money received as the reimbursement source."
            case .expenseMustBeOutflow: "Choose a purchase to reimburse."
            case .sourceIsMatchedTransfer: "A matched account transfer cannot be used as a reimbursement."
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
        do {
            guard source.amount < 0 else { throw AllocationError.sourceMustBeInflow }
            guard source.transferPairId == nil else { throw AllocationError.sourceIsMatchedTransfer }
            guard expense.amount > 0 else { throw AllocationError.expenseMustBeOutflow }
            guard source.id != expense.id else { throw AllocationError.sameTransaction }
            guard source.isoCurrencyCode.caseInsensitiveCompare(expense.isoCurrencyCode) == .orderedSame
            else { throw AllocationError.currencyMismatch }
            guard amount.isFinite else { throw AllocationError.invalidAmount }
            let amount = (amount * 100).rounded() / 100
            guard amount > 0 else { throw AllocationError.invalidAmount }

            // @Query can lag one run loop behind a just-saved allocation. The
            // context is authoritative, otherwise two rapid assignments can
            // each believe the full source amount is still available.
            _ = existing
            try reconcile(in: context)
            let current = try context.fetch(FetchDescriptor<ReimbursementAllocation>())
                .filter { $0.modelContext != nil }
            let index = ReimbursementAllocationIndex(current)
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
        } catch {
            context.rollback()
            throw error
        }
    }

    static func remove(_ allocation: ReimbursementAllocation, from context: ModelContext) throws {
        do {
            context.delete(allocation)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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

    /// Revalidates persisted links after transaction edits, sync, transfer
    /// rematching, or backup restore. Oldest allocations keep priority; later
    /// rows are trimmed or removed when a source/purchase capacity shrinks.
    ///
    /// The caller owns the final `context.save()` so reconciliation can be
    /// committed atomically with the transaction changes that required it.
    static func reconcile(
        in context: ModelContext,
        preserving preservedAllocationIDs: Set<String> = []
    ) throws {
        let transactions = try context.fetch(FetchDescriptor<TransactionRecord>())
        let transactionsByID = Dictionary(
            transactions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let allocations = try context.fetch(FetchDescriptor<ReimbursementAllocation>())
            .sorted {
                let leftPreserved = preservedAllocationIDs.contains($0.id)
                let rightPreserved = preservedAllocationIDs.contains($1.id)
                if leftPreserved != rightPreserved { return leftPreserved }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id < $1.id
            }

        var sourceUsed: [String: Int] = [:]
        var expenseUsed: [String: Int] = [:]
        for allocation in allocations {
            guard
                let source = transactionsByID[allocation.sourceTransactionID],
                let expense = transactionsByID[allocation.expenseTransactionID],
                source.id != expense.id,
                source.amount < 0,
                source.transferPairId == nil,
                expense.amount > 0,
                source.isoCurrencyCode.caseInsensitiveCompare(expense.isoCurrencyCode) == .orderedSame,
                let requested = minorUnits(allocation.amount),
                requested > 0,
                let sourceCapacity = minorUnits(abs(source.amount)),
                let expenseCapacity = minorUnits(expense.amount)
            else {
                context.delete(allocation)
                continue
            }

            let sourceRemaining = max(0, sourceCapacity - sourceUsed[source.id, default: 0])
            let expenseRemaining = max(0, expenseCapacity - expenseUsed[expense.id, default: 0])
            let allowed = min(requested, min(sourceRemaining, expenseRemaining))
            guard allowed > 0 else {
                context.delete(allocation)
                continue
            }

            allocation.amount = Double(allowed) / 100
            sourceUsed[source.id, default: 0] += allowed
            expenseUsed[expense.id, default: 0] += allowed
        }
    }

    private static func minorUnits(_ amount: Double) -> Int? {
        guard amount.isFinite, amount >= 0, amount <= Double(Int.max) / 100 else {
            return nil
        }
        return Int((amount * 100).rounded())
    }
}