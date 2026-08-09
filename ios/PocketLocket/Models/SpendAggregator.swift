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
}
