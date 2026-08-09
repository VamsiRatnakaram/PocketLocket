import SwiftUI

/// A list of categories with their spend. Shows a share-of-total bar, or — when
/// `showBudgets` is on and a category has a monthly limit — progress toward that
/// limit (turning red when over).
struct CategoryBreakdownList: View {
    let spends: [CategorySpend]
    let total: Double
    /// When provided, each row taps into a per-category detail for this period.
    var interval: DateInterval? = nil
    var periodLabel: String = ""
    var showBudgets: Bool = false

    @AppStorage(CategoryBudgetStore.key) private var categoryBudgetsRaw = ""

    private var budgets: [SpendCategory: Double] {
        showBudgets ? CategoryBudgetStore.decode(categoryBudgetsRaw) : [:]
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(spends) { spend in
                if let interval {
                    NavigationLink {
                        CategoryDetailView(category: spend.category, interval: interval, periodLabel: periodLabel)
                    } label: {
                        row(for: spend, showChevron: true)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                } else {
                    row(for: spend, showChevron: false)
                }
            }
        }
    }

    private func row(for spend: CategorySpend, showChevron: Bool) -> some View {
        let limit = budgets[spend.category]
        let over = limit.map { spend.amount > $0 } ?? false
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: spend.category.symbol)
                    .foregroundStyle(spend.category.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spend.category.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let limit {
                        Text(over ? "over \(CurrencyFormatter.compact(limit)) limit" : "of \(CurrencyFormatter.compact(limit))")
                            .font(.caption2)
                            .foregroundStyle(over ? .red : .secondary)
                    }
                }
                Spacer()
                Text(CurrencyFormatter.string(spend.amount))
                    .font(.subheadline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(over ? .red : .secondary)
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            bar(for: spend, limit: limit)
        }
        .contentShape(Rectangle())
    }

    private func bar(for spend: CategorySpend, limit: Double?) -> some View {
        let fraction: Double
        let over: Bool
        if let limit, limit > 0 {
            fraction = min(spend.amount / limit, 1)
            over = spend.amount > limit
        } else {
            fraction = total > 0 ? spend.amount / total : 0
            over = false
        }
        let color = over ? Color.red : spend.category.tint
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}
