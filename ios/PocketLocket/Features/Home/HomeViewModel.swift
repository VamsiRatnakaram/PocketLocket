import Foundation

/// View-model math for the Home screen. Pure and testable — it takes plain
/// `SpendItem`s (not SwiftData models), so tests don't need a database.
struct HomeViewModel {
    let spends: [CategorySpend]
    let totalSpent: Double
    let monthlyBudget: Double
    /// Outflows held back from the budget (transfers, card payments), broken
    /// down by category so the Home screen can account for them out loud
    /// instead of dropping them on the floor.
    let excludedSpends: [CategorySpend]

    init(items: [SpendItem], monthlyBudget: Double) {
        let totals = SpendAggregator.totals(items)
        self.spends = totals
        self.totalSpent = SpendAggregator.totalSpend(totals)
        self.monthlyBudget = monthlyBudget
        self.excludedSpends = SpendAggregator.excludedTotals(items)
    }

    var excludedTotal: Double { SpendAggregator.totalSpend(excludedSpends) }

    /// Fraction of budget spent, clamped to [0, 1] for ring rendering.
    var progress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(totalSpent / monthlyBudget, 1)
    }

    var remaining: Double { monthlyBudget - totalSpent }

    var isOverBudget: Bool { totalSpent > monthlyBudget }
}
