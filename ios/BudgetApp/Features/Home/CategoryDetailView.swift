import SwiftUI
import SwiftData

/// Drill-down for a single category: every transaction in that category for the
/// selected period, sorted from most to least expensive.
struct CategoryDetailView: View {
    let category: SpendCategory
    let interval: DateInterval
    let periodLabel: String

    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @State private var detail: TransactionRecord?

    /// Spending transactions in this category + period, most expensive first.
    private var items: [TransactionRecord] {
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        return transactions
            .filter {
                interval.contains($0.date) && $0.amount > 0
                    && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
                    && $0.resolvedCategory(using: rules) == category
            }
            .sorted { $0.amount > $1.amount }
    }

    private var total: Double { items.reduce(0) { $0 + $1.amount } }

    var body: some View {
        List {
            Section {
                ForEach(items) { txn in
                    Button { detail = txn } label: {
                        TransactionRow(txn: txn, category: category)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            } header: {
                HStack {
                    Text(periodLabel)
                    Spacer()
                    Text("\(items.count) • \(CurrencyFormatter.string(total))")
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { txn in
            TransactionDetailView(txn: txn, currentCategory: category)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: category.symbol,
                    description: Text("No \(category.displayName) spending in \(periodLabel).")
                )
            }
        }
    }
}
