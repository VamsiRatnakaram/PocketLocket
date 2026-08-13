import SwiftUI
import Charts

/// Drill-down for a single category: every transaction in that category
/// within the current Analysis range, most recent first, with dates —
/// mirrors `MerchantDetailView`'s layout for a consistent look.
struct AnalysisCategoryDetailView: View {
    let category: SpendCategory
    let transactions: [TransactionRecord]
    let rules: [CategoryRule]

    @State private var detail: TransactionRecord?

    private var items: [TransactionRecord] {
        transactions
            .filter { $0.resolvedCategory(using: rules) == category }
            .sorted { $0.date > $1.date }
    }

    private var total: Double {
        items.reduce(0) { $0 + $1.amount }
    }

    private var monthly: [MerchantAnalytics.CategoryMonth] {
        let calendar = Calendar.current
        var buckets: [Date: Double] = [:]
        for txn in items {
            guard let monthStart = calendar.dateInterval(of: .month, for: txn.date)?.start else { continue }
            buckets[monthStart, default: 0] += txn.amount
        }
        return buckets
            .map { MerchantAnalytics.CategoryMonth(category: category, monthStart: $0.key, amount: $0.value) }
            .sorted { $0.monthStart < $1.monthStart }
    }

    var body: some View {
        List {
            Section {
                summary
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if monthly.count > 1 {
                Section("Spend over time") {
                    chart
                }
            }

            Section {
                ForEach(items) { txn in
                    Button { detail = txn } label: {
                        TransactionRow(txn: txn, category: category)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            } header: {
                Text("\(items.count) transaction\(items.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { txn in
            TransactionDetailView(txn: txn, currentCategory: category)
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            statTile(title: "Transactions", value: "\(items.count)")
            statTile(title: "Total", value: CurrencyFormatter.compact(total))
            statTile(title: "Avg", value: CurrencyFormatter.compact(items.isEmpty ? 0 : total / Double(items.count)))
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

    private var chart: some View {
        Chart(monthly) { entry in
            BarMark(
                x: .value("Month", entry.monthStart, unit: .month),
                y: .value("Spent", entry.amount)
            )
            .foregroundStyle(category.tint)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
        }
        .frame(height: 160)
    }
}
