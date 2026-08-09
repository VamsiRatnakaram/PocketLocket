import Foundation

/// Produces data-driven money-saving suggestions from a month of spending.
/// Pure and testable — the UI builds `Input`s from the transaction cache.
enum SavingsAdvisor {
    struct Input {
        let title: String
        let amount: Double
        let category: SpendCategory
        let isSubscription: Bool
    }

    static func suggestions(_ inputs: [Input], previous: [Input] = [], monthlyBudget: Double) -> [SavingsSuggestion] {
        let spending = inputs.filter { $0.category.isSpending && $0.amount > 0 }
        guard !spending.isEmpty else { return [] }
        let total = spending.reduce(0) { $0 + $1.amount }

        let prevSpending = previous.filter { $0.category.isSpending && $0.amount > 0 }
        let prevTotal = prevSpending.reduce(0) { $0 + $1.amount }

        var byCategory: [SpendCategory: Double] = [:]
        for s in spending { byCategory[s.category, default: 0] += s.amount }
        var prevByCategory: [SpendCategory: Double] = [:]
        for s in prevSpending { prevByCategory[s.category, default: 0] += s.amount }

        var out: [SavingsSuggestion] = []

        // Subscriptions
        let subs = spending.filter { $0.isSubscription }
        if !subs.isEmpty {
            let subTotal = subs.reduce(0) { $0 + $1.amount }
            let names = Array(Set(subs.map { $0.title })).sorted().prefix(4).joined(separator: ", ")
            out.append(SavingsSuggestion(
                title: "Review \(subs.count) subscription\(subs.count == 1 ? "" : "s")",
                detail: "About \(money(subTotal))/mo across \(names). Cancel the ones you don't use.",
                monthlyImpact: subTotal * 0.4,
                symbol: "arrow.triangle.2.circlepath",
                tint: .purple))
        }

        // Top category — with a month-over-month trend when last month is available.
        if let top = byCategory.max(by: { $0.value < $1.value }) {
            var detail = "You've spent \(money(top.value)) here. Trimming 10% saves \(money(top.value * 0.1))."
            if let prev = prevByCategory[top.key], prev > 0 {
                let change = (top.value - prev) / prev
                if change > 0.15 {
                    detail = "\(money(top.value)) so far — \(percent(change)) more than last month. Trimming 10% saves \(money(top.value * 0.1))."
                } else if change < -0.15 {
                    detail = "\(money(top.value)) — \(percent(-change)) less than last month. Nice work; keep it up."
                }
            }
            out.append(SavingsSuggestion(
                title: "\(top.key.displayName) is your top category",
                detail: detail,
                monthlyImpact: top.value * 0.1,
                symbol: top.key.symbol,
                tint: top.key.tint))
        }

        // Overall spending trend vs last month.
        if prevTotal > 0 {
            let change = (total - prevTotal) / prevTotal
            if change > 0.1 {
                out.append(SavingsSuggestion(
                    title: "Spending is up this month",
                    detail: "You're \(percent(change)) ahead of last month (\(money(total)) vs \(money(prevTotal))). Easing back now keeps you on track.",
                    monthlyImpact: total - prevTotal,
                    symbol: "chart.line.uptrend.xyaxis",
                    tint: .orange))
            }
        }

        // A merchant you hit often.
        var merchantStats: [String: (count: Int, total: Double)] = [:]
        for s in spending {
            var entry = merchantStats[s.title] ?? (0, 0)
            entry.count += 1
            entry.total += s.amount
            merchantStats[s.title] = entry
        }
        if let (merchant, stats) = merchantStats.max(by: { $0.value.count < $1.value.count }), stats.count >= 3 {
            out.append(SavingsSuggestion(
                title: "\(merchant) adds up",
                detail: "\(stats.count) charges totaling \(money(stats.total)). Trimming a few could save ~\(money(stats.total * 0.25)).",
                monthlyImpact: stats.total * 0.25,
                symbol: "repeat.circle.fill",
                tint: .teal))
        }

        // Budget status
        if monthlyBudget > 0 {
            if total > monthlyBudget {
                out.append(SavingsSuggestion(
                    title: "You're over budget",
                    detail: "You've spent \(money(total)) of \(money(monthlyBudget)). Pausing non-essentials will get you back on track.",
                    monthlyImpact: total - monthlyBudget,
                    symbol: "exclamationmark.triangle.fill",
                    tint: .red))
            } else {
                let left = monthlyBudget - total
                out.append(SavingsSuggestion(
                    title: "Move your surplus to savings",
                    detail: "You have \(money(left)) left this month. Auto-transfer it before you spend it.",
                    monthlyImpact: left,
                    symbol: "banknote.fill",
                    tint: .green))
            }
        }

        // Biggest single expense (informational).
        if spending.count > 3, let biggest = spending.max(by: { $0.amount < $1.amount }), biggest.amount > total * 0.2 {
            out.append(SavingsSuggestion(
                title: "Biggest expense: \(biggest.title)",
                detail: "\(money(biggest.amount)) in one go — about \(percent(biggest.amount / total)) of this month's spending.",
                monthlyImpact: nil,
                symbol: "arrow.up.right.circle.fill",
                tint: .blue))
        }

        // Dining frequency
        let dining = spending.filter { $0.category == .food }
        if dining.count >= 4 {
            let diningTotal = dining.reduce(0) { $0 + $1.amount }
            out.append(SavingsSuggestion(
                title: "Dining out adds up",
                detail: "\(dining.count) food purchases totaling \(money(diningTotal)). Cooking a few at home could save ~\(money(diningTotal * 0.2)).",
                monthlyImpact: diningTotal * 0.2,
                symbol: "fork.knife",
                tint: .orange))
        }

        // Fees / interest
        let fees = spending.filter { $0.category == .fees }
        if !fees.isEmpty {
            let feeTotal = fees.reduce(0) { $0 + $1.amount }
            out.append(SavingsSuggestion(
                title: "You're paying fees",
                detail: "\(money(feeTotal)) in fees or interest. Paying your card in full or switching to a no-fee option removes this.",
                monthlyImpact: feeTotal,
                symbol: "creditcard.trianglebadge.exclamationmark",
                tint: .gray))
        }

        return Array(out.sorted { ($0.monthlyImpact ?? 0) > ($1.monthlyImpact ?? 0) }.prefix(6))
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func money(_ value: Double) -> String {
        CurrencyFormatter.string(value)
    }
}
