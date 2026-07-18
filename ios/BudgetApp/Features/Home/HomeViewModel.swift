import Foundation

/// View-model math for the Home screen. Pure and testable — it takes plain
/// `SpendItem`s (not SwiftData models), so tests don't need a database.
struct HomeViewModel {
    let spends: [CategorySpend]
    let totalSpent: Double
    let monthlyBudget: Double

    init(items: [SpendItem], monthlyBudget: Double) {
        let totals = SpendAggregator.totals(items)
        self.spends = totals
        self.totalSpent = SpendAggregator.totalSpend(totals)
        self.monthlyBudget = monthlyBudget
    }

    /// Fraction of budget spent, clamped to [0, 1] for ring rendering.
    var progress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(totalSpent / monthlyBudget, 1)
    }

    var remaining: Double { monthlyBudget - totalSpent }

    var isOverBudget: Bool { totalSpent > monthlyBudget }
}
