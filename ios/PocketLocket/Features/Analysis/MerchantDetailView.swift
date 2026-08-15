import SwiftUI
import Charts

enum MerchantDetailBuilder {
    struct Item: Identifiable {
        let transaction: TransactionRecord
        let category: SpendCategory
        var id: String { transaction.id }
    }

    struct Content {
        let items: [Item]
        let monthly: [MerchantAnalytics.CategoryMonth]
    }

    /// Match first, then resolve categories only for this merchant.
    ///
    /// The former order categorized every transaction in the scoped ledger
    /// before asking whether it belonged here, blocking the navigation
    /// animation. This builder also produces every section in one pass.
    static func build(
        stats: MerchantAnalytics.MerchantStats,
        transactions: [TransactionRecord],
        calendar: Calendar = .current,
        categoryFor: (TransactionRecord) -> SpendCategory
    ) -> Content {
        var items: [Item] = []
        items.reserveCapacity(stats.visitCount)
        for transaction in transactions
        where transaction.amount > 0 && stats.matches(transaction.title) {
            let category = categoryFor(transaction)
            guard category.isSpending else { continue }
            items.append(Item(transaction: transaction, category: category))
        }
        items.sort { $0.transaction.date > $1.transaction.date }

        var buckets: [Date: Double] = [:]
        for item in items {
            guard let monthStart = calendar.dateInterval(
                of: .month,
                for: item.transaction.date
            )?.start else { continue }
            buckets[monthStart, default: 0] += item.transaction.amount
        }
        let monthly = buckets
            .map {
                MerchantAnalytics.CategoryMonth(
                    category: stats.category,
                    monthStart: $0.key,
                    amount: $0.value
                )
            }
            .sorted { $0.monthStart < $1.monthStart }

        return Content(items: items, monthly: monthly)
    }
}

private struct MerchantDetailContentKey: Equatable {
    let dataHash: Int
    let rulesHash: Int
    let merchantID: String
}

/// Drill-down for a single merchant: visit history over time and every
/// transaction, most recent first — reuses `TransactionRow`/`TransactionDetailView`
/// from the Transactions feature for a consistent look.
struct MerchantDetailView: View {
    let stats: MerchantAnalytics.MerchantStats
    let transactions: [TransactionRecord]
    let rules: [CategoryRule]

    @Environment(\.dismiss) private var dismiss
    @State private var detail: MerchantDetailBuilder.Item?
    @State private var showGroupingEditor = false
    @State private var dismissAfterGroupingEdit = false
    @State private var dismissAfterTransactionGroupingEdit = false
    @State private var contentCache =
        DerivedCache<MerchantDetailContentKey, MerchantDetailBuilder.Content>()

    private var content: MerchantDetailBuilder.Content {
        let key = MerchantDetailContentKey(
            dataHash: RecordHash.transactions(transactions),
            rulesHash: RecordHash.rules(rules),
            merchantID: stats.id
        )
        return contentCache.value(for: key) {
            MerchantDetailBuilder.build(
                stats: stats,
                transactions: transactions
            ) {
                $0.resolvedCategory(using: rules)
            }
        }
    }

    var body: some View {
        detailList(content)
    }

    private func detailList(_ content: MerchantDetailBuilder.Content) -> some View {
        List {
            Section {
                summary
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if content.monthly.count > 1 {
                Section("Spend over time") {
                    chart(content.monthly)
                }
            }

            Section {
                ForEach(content.items) { item in
                    Button { detail = item } label: {
                        TransactionRow(
                            txn: item.transaction,
                            category: item.category
                        )
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            } header: {
                Text(
                    "\(content.items.count) transaction"
                        + "\(content.items.count == 1 ? "" : "s")"
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle(stats.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showGroupingEditor = true } label: {
                    Label("Edit Grouping", systemImage: "rectangle.3.group")
                }
            }
        }
        .sheet(item: $detail, onDismiss: {
            if dismissAfterTransactionGroupingEdit { dismiss() }
        }) { item in
            TransactionDetailView(
                txn: item.transaction,
                currentCategory: item.category
            ) {
                dismissAfterTransactionGroupingEdit = true
            }
        }
        .sheet(isPresented: $showGroupingEditor, onDismiss: {
            if dismissAfterGroupingEdit { dismiss() }
        }) {
            MerchantGroupingEditorView(stats: stats) {
                dismissAfterGroupingEdit = true
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            statTile(title: "Visits", value: "\(stats.visitCount)")
            statTile(title: "Total", value: CurrencyFormatter.compact(stats.totalSpent))
            statTile(title: "Avg", value: CurrencyFormatter.compact(stats.averagePerVisit))
        }
        .padding(.vertical, 8)
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func chart(_ monthly: [MerchantAnalytics.CategoryMonth]) -> some View {
        Chart(monthly) { entry in
            BarMark(
                x: .value("Month", entry.monthStart, unit: .month),
                y: .value("Spent", entry.amount)
            )
            .foregroundStyle(stats.category.tint)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
        }
        .frame(height: 160)
    }
}
