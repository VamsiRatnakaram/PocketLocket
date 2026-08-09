import SwiftUI

/// Set optional monthly limits per spending category. Reached from Settings.
/// Limits drive the per-category progress shown in the Home breakdown.
struct CategoryBudgetsView: View {
    @AppStorage(CategoryBudgetStore.key) private var raw = ""
    @AppStorage(SafeToSpendFocus.key) private var focusRaw = ""

    private var spendingCategories: [SpendCategory] {
        SpendCategory.allCases.filter(\.isSpending)
    }

    private var focus: Set<SpendCategory> { SafeToSpendFocus.categories(from: focusRaw) }

    var body: some View {
        Form {
            Section {
                ForEach(spendingCategories) { category in
                    HStack(spacing: 10) {
                        Button {
                            focusRaw = SafeToSpendFocus.toggling(category, in: focusRaw)
                        } label: {
                            Image(systemName: focus.contains(category) ? "star.fill" : "star")
                                .foregroundStyle(focus.contains(category) ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                        Label(category.displayName, systemImage: category.symbol)
                            .foregroundStyle(category.tint)
                        Spacer()
                        TextField("No limit", value: limitBinding(for: category), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }
            } header: {
                Text("Monthly limits")
            } footer: {
                Text("Set an optional monthly limit per category (0 = no limit). Tap ★ to base “Safe to spend” on that category's daily allowance — handy for focusing on, say, food.")
            }
        }
        .navigationTitle("Category Budgets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func limitBinding(for category: SpendCategory) -> Binding<Double> {
        Binding(
            get: { CategoryBudgetStore.decode(raw)[category] ?? 0 },
            set: { newValue in
                var budgets = CategoryBudgetStore.decode(raw)
                if newValue > 0 { budgets[category] = newValue } else { budgets[category] = nil }
                raw = CategoryBudgetStore.encode(budgets)
            }
        )
    }
}
