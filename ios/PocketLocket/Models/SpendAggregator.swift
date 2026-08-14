import Foundation

/// A single categorized amount fed into the aggregator.
struct SpendItem {
    let category: SpendCategory
    let amount: Double
}

/// A category's total spend, used to render the ring and breakdown.
struct CategorySpend: Identifiable {
    let category: SpendCategory
    let amount: Double
    var id: String { category.id }
}

/// Pure aggregation logic (easy to unit test).
///
/// Plaid amount convention: a POSITIVE amount means money moved *out* of the
/// account (i.e. spending). We therefore sum positive amounts and ignore
/// income/transfer categories.
enum SpendAggregator {
    static func totals(_ items: [SpendItem]) -> [CategorySpend] {
        var sums: [SpendCategory: Double] = [:]
        for item in items where item.category.isSpending && item.amount > 0 {
            sums[item.category, default: 0] += item.amount
        }
        return sums
            .map { CategorySpend(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    static func totalSpend(_ spends: [CategorySpend]) -> Double {
        spends.reduce(0) { $0 + $1.amount }
    }

    /// The mirror image of `totals`: money that left your accounts but is
    /// deliberately kept out of the budget because it's a transfer, a card
    /// payment, or income being moved around.
    ///
    /// Without this, those transactions are silently invisible — you can't tell
    /// whether a payment is missing from the app or excluded on purpose. Same
    /// `amount > 0` filter as `totals`, because the matching inflow leg of a
    /// transfer was never counted as spend either and reporting it here would
    /// just cancel out.
    static func excludedTotals(_ items: [SpendItem]) -> [CategorySpend] {
        var sums: [SpendCategory: Double] = [:]
        for item in items where !item.category.isSpending && item.amount > 0 {
            sums[item.category, default: 0] += item.amount
        }
        return sums
            .map { CategorySpend(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }
}
