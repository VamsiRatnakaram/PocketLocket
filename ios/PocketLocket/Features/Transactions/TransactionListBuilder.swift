import Foundation

/// The filter/sort pipeline behind the Transactions list, lifted out of the
/// view so it runs once per change instead of once per reference — and so it
/// can be tested without a SwiftData container driving a `body`.
enum TransactionListBuilder {
    /// A transaction paired with the category the list should display for it.
    ///
    /// Resolving a category is the most expensive per-transaction operation in
    /// the app, and the list needs it twice: once to apply the category/budget
    /// filters and once to render the row. Carrying it on the row means it is
    /// computed a single time per transaction per rebuild.
    struct Row: Identifiable {
        let transaction: TransactionRecord
        let category: SpendCategory
        var id: String { transaction.id }
    }

    struct Criteria: Equatable {
        var search: String = ""
        var accountId: String?
        var category: SpendCategory?
        var type: TransactionsView.TxnType = .all
        var periodInterval: DateInterval?
        var sortOrder: TransactionsView.SortOrder = .dateDesc
    }

    /// Applies `criteria` to `transactions`, resolving each category at most once.
    ///
    /// `resolve` is injected so tests can supply a categorization without
    /// building a rule store.
    static func rows(
        from transactions: [TransactionRecord],
        criteria: Criteria,
        resolve: (TransactionRecord) -> SpendCategory
    ) -> [Row] {
        var rows: [Row] = []
        rows.reserveCapacity(transactions.count)

        for txn in transactions {
            // Cheap scalar rejections come first so the expensive category
            // resolution below only runs for transactions still in the running.
            if let interval = criteria.periodInterval, !interval.contains(txn.date) { continue }
            if let accountId = criteria.accountId, txn.accountId != accountId { continue }

            switch criteria.type {
            case .all: break
            case .expenses: if txn.amount <= 0 { continue }
            case .income: if txn.amount >= 0 { continue }
            }

            if !criteria.search.isEmpty {
                let matches = txn.title.localizedCaseInsensitiveContains(criteria.search)
                    || txn.name.localizedCaseInsensitiveContains(criteria.search)
                if !matches { continue }
            }

            let category = resolve(txn)
            if let wanted = criteria.category, category != wanted { continue }

            rows.append(Row(transaction: txn, category: category))
        }

        return sort(rows, by: criteria.sortOrder)
    }

    static func sort(_ rows: [Row], by order: TransactionsView.SortOrder) -> [Row] {
        switch order {
        case .dateDesc: return rows.sorted { $0.transaction.date > $1.transaction.date }
        case .dateAsc: return rows.sorted { $0.transaction.date < $1.transaction.date }
        // By size, not by sign. Positive is money out and negative is money in,
        // so ordering on the raw value filed the largest deposits under
        // "Smallest first" — the opposite of what the label promises.
        case .amountDesc: return rows.sorted { abs($0.transaction.amount) > abs($1.transaction.amount) }
        case .amountAsc: return rows.sorted { abs($0.transaction.amount) < abs($1.transaction.amount) }
        }
    }
}
