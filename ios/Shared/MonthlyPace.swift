import Foundation

/// The month's pace, shared by Home and the widgets.
///
/// Both surfaces show "how much is left per day", and if each computed the day
/// count its own way a widget could say $40/day while the app below it said
/// $45/day for the same ledger.
enum MonthlyPace {
    /// Days remaining in `date`'s month, counting today. Always at least 1, so
    /// the last day of a month divides by 1 rather than 0.
    static func daysLeftInMonth(for date: Date, calendar: Calendar = .current) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return 1 }
        return max(1, range.count - calendar.component(.day, from: date) + 1)
    }
}

/// The budget basis behind "Safe to spend": either the starred-and-budgeted
/// categories, or the whole monthly budget when nothing is starred.
///
/// Extracted from `HomeView`, which had this as three private functions. The
/// widget needs the same figure, and a second copy would have been free to
/// drift from the number on the screen right above it.
struct SafeToSpendBasis: Equatable, Sendable {
    let budget: Double
    let spent: Double
    /// Starred category names, empty when the basis is the overall budget.
    let label: String

    /// - Parameter focus: starred categories. Those without a monthly limit are
    ///   ignored, so starring a category you never budgeted can't silently
    ///   redefine the figure to "unlimited minus spend".
    static func resolve(
        items: [SpendItem],
        monthlyBudget: Double,
        categoryBudgets: [SpendCategory: Double],
        focus: Set<SpendCategory>,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> SafeToSpendBasis? {
        let active = focus.filter { categoryBudgets[$0] != nil }
        if !active.isEmpty {
            let budget = active.reduce(0) { $0 + (categoryBudgets[$1] ?? 0) }
            // Reuses the categories already resolved for the month rather than
            // resolving the whole ledger a second time.
            let spent = items
                .filter { $0.amount > 0 && active.contains($0.category) }
                .reduce(0) { $0 + $1.amount }
            let names = active.map(\.displayName).sorted().joined(separator: ", ")
            return SafeToSpendBasis(budget: budget, spent: spent, label: names)
        } else if monthlyBudget > 0 {
            let spent = items
                .filter { $0.amount > 0 && $0.category.isSpending }
                .reduce(0) { $0 + $1.amount }
            return SafeToSpendBasis(budget: monthlyBudget, spent: spent, label: "")
        }
        return nil
    }

    /// Remaining allowance spread over the rest of the month, never negative.
    func dailyAllowance(daysLeft: Int) -> Double {
        max(0, budget - spent) / Double(max(1, daysLeft))
    }

    var dailyAllowance: Double {
        dailyAllowance(daysLeft: MonthlyPace.daysLeftInMonth(for: Date()))
    }
}
